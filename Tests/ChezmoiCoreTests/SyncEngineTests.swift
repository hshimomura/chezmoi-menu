import XCTest
@testable import ChezmoiCore

private struct FixedResolver: ConflictResolving {
    let content: String
    func resolve(_ conflict: Conflict) async throws -> Resolution {
        guard conflict.base == "value=base\n", conflict.local == "value=local\n", conflict.remote == "value=remote\n" else {
            throw SyncError("three-way input mismatch")
        }
        return Resolution(content: content, summary: "統合しました", resolved: true)
    }
}

private struct FailingResolver: ConflictResolving {
    func resolve(_ conflict: Conflict) async throws -> Resolution { throw SyncError("simulated API failure") }
}

private actor WaitingResolver: ConflictResolving {
    private var entered = false
    func resolve(_ conflict: Conflict) async throws -> Resolution {
        entered = true
        try await Task.sleep(for: .seconds(30))
        throw SyncError("resolver should have been cancelled")
    }
    func waitUntilEntered() async throws {
        for _ in 0..<500 {
            if entered { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw SyncError("resolver did not start")
    }
}

private struct EditingResolver: ConflictResolving {
    let target: URL
    func resolve(_ conflict: Conflict) async throws -> Resolution {
        try "value=edited-during-sync\n".write(to: target, atomically: true, encoding: .utf8)
        return Resolution(content: "value=merged\n", summary: "統合", resolved: true)
    }
}

private struct RacingResolver: ConflictResolving {
    let other: URL
    func resolve(_ conflict: Conflict) async throws -> Resolution {
        let command = FixtureCommand()
        try "remote raced\n".write(to: other.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try command.run("/usr/bin/git", ["add", "."], directory: other)
        try command.run("/usr/bin/git", ["commit", "-m", "concurrent push"], directory: other)
        try command.run("/usr/bin/git", ["push"], directory: other)
        return Resolution(content: "value=merged\n", summary: "統合", resolved: true)
    }
}

private final class Fixture {
    let root: URL
    let source: URL
    let other: URL
    let home: URL
    let remote: URL
    let config: URL
    let backups: URL
    let command = FixtureCommand()
    var settings = SyncSettings()
    let filename: String

    init(filename: String = "dot_test", content: String = "value=base\n") throws {
        self.filename = filename
        root = FileManager.default.temporaryDirectory.appendingPathComponent("chezmoi-menu-tests-" + UUID().uuidString)
        source = root.appendingPathComponent("source")
        other = root.appendingPathComponent("other")
        home = root.appendingPathComponent("home")
        remote = root.appendingPathComponent("remote.git")
        config = root.appendingPathComponent("chezmoi.json")
        backups = root.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        settings.chezmoiPath = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/chezmoi") ? "/opt/homebrew/bin/chezmoi" : "/usr/local/bin/chezmoi"
        settings.configPath = config.path
        let json: [String: Any] = ["sourceDir": source.path, "destDir": home.path,
            "persistentState": root.appendingPathComponent("state.boltdb").path,
            "cacheDir": root.appendingPathComponent("cache").path,
            "git": ["autoCommit": false, "autoPush": false, "autoAdd": false]]
        try JSONSerialization.data(withJSONObject: json).write(to: config)
        try command.run("/usr/bin/git", ["init", "--bare", "--initial-branch=main", remote.path])
        try command.run("/usr/bin/git", ["clone", remote.path, source.path])
        try configure(source)
        try writeSource(content)
        try git(["add", "."])
        try git(["commit", "-m", "initial"])
        try git(["push", "-u", "origin", "main"])
        try command.run("/usr/bin/git", ["clone", remote.path, other.path])
        try configure(other)
        try chez(["apply", "--force"])
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func configure(_ url: URL) throws {
        try command.run("/usr/bin/git", ["config", "user.name", "Test"], directory: url)
        try command.run("/usr/bin/git", ["config", "user.email", "test@example.invalid"], directory: url)
        try command.run("/usr/bin/git", ["config", "commit.gpgsign", "false"], directory: url)
    }
    @discardableResult func git(_ args: [String], at url: URL? = nil, allowFailure: Bool = false) throws -> CommandResult {
        try command.run("/usr/bin/git", args, directory: url ?? source, allowFailure: allowFailure)
    }
    @discardableResult func chez(_ args: [String]) throws -> CommandResult {
        try command.run(settings.chezmoiPath, ["--config", config.path, "--no-tty", "--no-pager"] + args)
    }
    func writeSource(_ text: String, at url: URL? = nil) throws {
        try text.write(to: (url ?? source).appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }
    func remoteChange(_ text: String) throws {
        try writeSource(text, at: other)
        try git(["add", "."], at: other)
        try git(["commit", "-m", "remote change"], at: other)
        try git(["push"], at: other)
    }
    var target: URL { home.appendingPathComponent(filename.replacingOccurrences(of: "dot_", with: ".")) }
    func writeTarget(_ text: String) throws { try text.write(to: target, atomically: true, encoding: .utf8) }
    func targetContent() throws -> String { try String(contentsOf: target, encoding: .utf8) }
    func engine(resolver: (any ConflictResolving)? = nil) -> SyncEngine {
        SyncEngine(settings: settings, backups: backups, resolver: resolver)
    }
    func assertNoMerge() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent(".git/MERGE_HEAD").path))
        XCTAssertEqual(try git(["status", "--porcelain"]).text, "")
    }
}

@MainActor
final class SyncEngineTests: XCTestCase {
    func testCancellationDuringAIAbortsMergeAndRejectsConcurrentOperation() async throws {
        let f = try Fixture()
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        let resolver = WaitingResolver()
        let engine = f.engine(resolver: resolver)
        let task = Task { try await engine.sync(.upload) }
        try await resolver.waitUntilEntered()
        do { _ = try await engine.check(); XCTFail("concurrent operation accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("別の操作")) }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancel ignored") }
        catch { XCTAssertTrue(error is CancellationError) }
        try f.assertNoMerge()
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        XCTAssertEqual(try String(contentsOf: f.source.appendingPathComponent(f.filename), encoding: .utf8), "value=local\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.appendingPathComponent(".git/chezmoi-menu-pending-apply.json").path))
        XCTAssertNotEqual(try f.git(["rev-parse", "HEAD"]).text, try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text)
    }

    func testCancellationAfterMergeRetainsPendingApplyAndBlocksReimport() async throws {
        let f = try Fixture()
        try f.remoteChange("value=remote\n")
        let engine = SyncEngine(settings: f.settings, backups: f.backups, resolver: nil, onEvent: { event in
            if event.phase == .validating { withUnsafeCurrentTask { $0?.cancel() } }
        })
        let task = Task { try await engine.sync(.download) }
        do { _ = try await task.value; XCTFail("cancel ignored") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try f.targetContent(), "value=base\n")
        XCTAssertEqual(try String(contentsOf: f.source.appendingPathComponent(f.filename), encoding: .utf8), "value=remote\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.appendingPathComponent(".git/chezmoi-menu-pending-apply.json").path))
        do { _ = try await f.engine().sync(.download); XCTFail("pending apply ignored") }
        catch { XCTAssertTrue(error.localizedDescription.contains("apply")) }
    }

    func testPreviewIsReadOnlyAndOmitsExcludedContent() async throws {
        let f = try Fixture()
        try f.writeTarget("value=local\n")
        try "sensitive=source\n".write(to: f.source.appendingPathComponent("dot_env"), atomically: true, encoding: .utf8)
        try "sensitive=home\n".write(to: f.home.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let head = try f.git(["rev-parse", "HEAD"]).text
        let preview = try await f.engine(resolver: FailingResolver()).preview()
        XCTAssertEqual(preview.files, [".test"])
        XCTAssertEqual(preview.omittedCount, 1)
        XCTAssertTrue(preview.text.contains("value=local"))
        XCTAssertFalse(preview.text.contains("sensitive"))
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        XCTAssertEqual(try f.git(["rev-parse", "HEAD"]).text, head)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.backups.path))
    }

    func testPreviewWithOnlyExcludedFilesDoesNotFallBackToAllFiles() async throws {
        let f = try Fixture(filename: "dot_env")
        try f.writeTarget("sensitive=local\n")
        let preview = try await f.engine().preview()
        XCTAssertEqual(preview.omittedCount, 1)
        XCTAssertTrue(preview.files.isEmpty)
        XCTAssertEqual(preview.text, "")
    }

    func testCancellationDuringApplyWaitsForCompletion() async throws {
        let f = try Fixture()
        try f.remoteChange("value=remote\n")
        let started = f.root.appendingPathComponent("apply-started")
        let completed = f.root.appendingPathComponent("apply-completed")
        let wrapper = f.root.appendingPathComponent("chezmoi-wrapper")
        let script = """
        #!/bin/sh
        applying=no
        dry=no
        for arg in "$@"; do
            [ "$arg" = apply ] && applying=yes
            [ "$arg" = --dry-run ] && dry=yes
        done
        if [ "$applying" = yes ] && [ "$dry" = no ]; then
            touch '\(started.path)'
            sleep 0.5
            '\(f.settings.chezmoiPath)' "$@"
            result=$?
            [ "$result" = 0 ] && touch '\(completed.path)'
            exit "$result"
        fi
        exec '\(f.settings.chezmoiPath)' "$@"
        """
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        f.settings.chezmoiPath = wrapper.path
        let engine = f.engine()
        let task = Task { try await engine.sync(.download) }
        for _ in 0..<500 {
            if FileManager.default.fileExists(atPath: started.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: started.path))
        task.cancel()
        _ = try await task.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: completed.path))
        XCTAssertEqual(try f.targetContent(), "value=remote\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.appendingPathComponent(".git/chezmoi-menu-pending-apply.json").path))
        try f.assertNoMerge()
    }

    func testCheckDoesNotApplyCommitPushOrCreateBackups() async throws {
        let f = try Fixture()
        try f.writeTarget("value=local\n")
        let before = try f.git(["rev-parse", "HEAD"]).text
        let indexBefore = try Data(contentsOf: f.source.appendingPathComponent(".git/index"))
        let report = try await f.engine(resolver: FailingResolver()).check()
        XCTAssertEqual(report.destination, f.home.resolvingSymlinksInPath().path)
        XCTAssertEqual(report.managedCount, 1)
        XCTAssertEqual(report.localCaptures, 1)
        XCTAssertEqual(report.destinationChanges, 1)
        XCTAssertTrue(report.remoteMatches)
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        XCTAssertEqual(try f.git(["rev-parse", "HEAD"]).text, before)
        XCTAssertEqual(try Data(contentsOf: f.source.appendingPathComponent(".git/index")), indexBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.backups.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.appendingPathComponent(".git/FETCH_HEAD").path))
    }

    func testCheckDetectsNewRemoteWithoutUpdatingTrackingRef() async throws {
        let f = try Fixture()
        let tracking = try f.git(["rev-parse", "origin/main"]).text
        try f.remoteChange("value=remote\n")
        let report = try await f.engine().check()
        XCTAssertFalse(report.remoteMatches)
        XCTAssertEqual(try f.git(["rev-parse", "origin/main"]).text, tracking)
        XCTAssertEqual(try f.targetContent(), "value=base\n")
    }

    func testDownloadAppliesRemoteWithoutPush() async throws {
        let f = try Fixture()
        try f.remoteChange("value=remote\n")
        let before = try f.git(["ls-remote", "origin", "refs/heads/main"]).text
        let report = try await f.engine().sync(.download)
        XCTAssertEqual(try f.targetContent(), "value=remote\n")
        XCTAssertEqual(try f.git(["ls-remote", "origin", "refs/heads/main"]).text, before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.backup.appendingPathComponent("source/.git").path))
        try f.assertNoMerge()
    }

    func testUploadCapturesDestinationAndPushes() async throws {
        let f = try Fixture()
        try f.writeTarget("value=local\n")
        _ = try await f.engine().sync(.upload)
        try f.git(["pull", "--ff-only"], at: f.other)
        XCTAssertEqual(try String(contentsOf: f.other.appendingPathComponent("dot_test"), encoding: .utf8), "value=local\n")
        try f.assertNoMerge()
    }

    func testPendingSourceChangeIsNotOverwrittenByOldDestination() async throws {
        let f = try Fixture()
        try f.writeSource("value=source-edit\n")
        _ = try await f.engine().sync(.upload)
        XCTAssertEqual(try f.targetContent(), "value=source-edit\n")
    }

    func testDownloadPreservesLocalDestinationCommitWithoutPushing() async throws {
        let f = try Fixture()
        try f.writeTarget("value=local\n")
        let remoteBefore = try f.git(["ls-remote", "origin", "refs/heads/main"]).text
        _ = try await f.engine().sync(.download)
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        XCTAssertEqual(try f.git(["ls-remote", "origin", "refs/heads/main"]).text, remoteBefore)
        XCTAssertEqual(try f.git(["rev-list", "--count", "origin/main..HEAD"]).text.trimmingCharacters(in: .newlines), "1")
    }

    func testConflictUsesActualThreeWayInputsAndPushesMergedResult() async throws {
        let f = try Fixture()
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        let report = try await f.engine(resolver: FixedResolver(content: "value=merged\n")).sync(.upload)
        XCTAssertEqual(report.resolvedCount, 1)
        XCTAssertEqual(try f.targetContent(), "value=merged\n")
        try f.git(["pull", "--ff-only"], at: f.other)
        XCTAssertEqual(try String(contentsOf: f.other.appendingPathComponent("dot_test"), encoding: .utf8), "value=merged\n")
        try f.assertNoMerge()
    }

    func testAPIFailureAbortsMergeAndPreservesLocalChanges() async throws {
        let f = try Fixture()
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        let before = try f.git(["ls-remote", "origin", "refs/heads/main"]).text
        do { _ = try await f.engine(resolver: FailingResolver()).sync(.upload); XCTFail("must stop") }
        catch { XCTAssertTrue(error.localizedDescription.contains("simulated")) }
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        XCTAssertEqual(try String(contentsOf: f.source.appendingPathComponent("dot_test"), encoding: .utf8), "value=local\n")
        XCTAssertEqual(try f.git(["ls-remote", "origin", "refs/heads/main"]).text, before)
        try f.assertNoMerge()
    }

    func testExcludedFileNeverReachesResolver() async throws {
        let f = try Fixture(filename: "dot_env")
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        do { _ = try await f.engine(resolver: FailingResolver()).sync(.upload); XCTFail("must stop") }
        catch { XCTAssertTrue(error.localizedDescription.contains("除外対象")) }
        try f.assertNoMerge()
    }

    func testDestinationEditDuringAPIIsPreservedAndNotPushed() async throws {
        let f = try Fixture()
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        let before = try f.git(["ls-remote", "origin", "refs/heads/main"]).text
        do { _ = try await f.engine(resolver: EditingResolver(target: f.target)).sync(.upload); XCTFail("must stop") }
        catch { XCTAssertTrue(error.localizedDescription.contains("同期中")) }
        XCTAssertEqual(try f.targetContent(), "value=edited-during-sync\n")
        XCTAssertEqual(try f.git(["ls-remote", "origin", "refs/heads/main"]).text, before)
        do { _ = try await f.engine().sync(.upload); XCTFail("retry must not recapture old destination") }
        catch { XCTAssertTrue(error.localizedDescription.contains("前回の統合後")) }
    }

    func testBothSourceAndDestinationDirtyStopsWithoutOverwriting() async throws {
        let f = try Fixture()
        try f.writeTarget("value=local\n")
        try f.writeSource("value=source\n")
        do { _ = try await f.engine().sync(.upload); XCTFail("must stop") }
        catch { XCTAssertTrue(error.localizedDescription.contains("両方変更")) }
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        XCTAssertEqual(try String(contentsOf: f.source.appendingPathComponent("dot_test"), encoding: .utf8), "value=source\n")
    }

    func testPushRaceRejectsWithoutForcePush() async throws {
        let f = try Fixture()
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        do { _ = try await f.engine(resolver: RacingResolver(other: f.other)).sync(.upload); XCTFail("push must reject") }
        catch { XCTAssertTrue(error.localizedDescription.contains("push")) }
        XCTAssertEqual(try f.targetContent(), "value=merged\n")
        XCTAssertEqual(try f.git(["show", "HEAD:dot_test"], at: f.other).text, "value=remote\n")
        XCTAssertEqual(try f.git(["show", "HEAD:README.md"], at: f.other).text, "remote raced\n")
    }

    func testLocallyEditedTemplateDestinationIsNotFlattened() async throws {
        let f = try Fixture(filename: "dot_test.tmpl", content: "value={{ .chezmoi.os }}\n")
        let target = f.home.appendingPathComponent(".test")
        try "value=local\n".write(to: target, atomically: true, encoding: .utf8)
        do { _ = try await f.engine().sync(.upload); XCTFail("template must not be re-added") }
        catch { XCTAssertTrue(error.localizedDescription.contains("テンプレート")) }
        XCTAssertEqual(try String(contentsOf: f.source.appendingPathComponent("dot_test.tmpl"), encoding: .utf8), "value={{ .chezmoi.os }}\n")
    }

    func testDeletedDestinationDoesNotSilentlyDisappear() async throws {
        let f = try Fixture()
        try FileManager.default.removeItem(at: f.target)
        do { _ = try await f.engine().sync(.upload); XCTFail("local deletion must stop") }
        catch { XCTAssertTrue(error.localizedDescription.contains("削除")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.target.path))
    }

    func testAPIResponseRejectsIncompleteRefusalAndMarkers() throws {
        for data in [
            #"{"status":"incomplete","output":[]}"#,
            #"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal"}]}]}"#,
            #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"resolved\":true,\"summary\":\"x\",\"content\":\"<<<<<<< ours\\n\"}"}]}]}"#
        ] { XCTAssertThrowsError(try OpenAIResolver.decode(Data(data.utf8))) }
        let result = try OpenAIResolver.decode(Data(#"{"status":"completed","output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"{\"resolved\":true,\"summary\":\"ok\",\"content\":\"merged\\n\"}"}]}]}"#.utf8))
        XCTAssertEqual(result.content, "merged\n")
    }
}
