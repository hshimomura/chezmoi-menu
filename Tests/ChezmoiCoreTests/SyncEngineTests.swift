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

private actor WaitingConflictSelection {
    private var entered = false
    func choose(_ request: ConflictSelectionRequest) async throws -> [String: ConflictSide] {
        entered = true
        try await Task.sleep(for: .seconds(30))
        throw SyncError("selection should have been cancelled")
    }
    func waitUntilEntered() async throws {
        for _ in 0..<500 {
            if entered { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw SyncError("selection did not start")
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

    init(filename: String = "dot_test", content: String = "value=base\n", encryptedEnv: Bool = false) throws {
        self.filename = encryptedEnv ? "encrypted_private_dot_env.age" : filename
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
        var json: [String: Any] = ["sourceDir": source.path, "destDir": home.path,
            "persistentState": root.appendingPathComponent("state.boltdb").path,
            "cacheDir": root.appendingPathComponent("cache").path,
            "git": ["autoCommit": false, "autoPush": false, "autoAdd": false]]
        try JSONSerialization.data(withJSONObject: json).write(to: config)
        if encryptedEnv {
            // Generate a disposable identity outside Git; never use the user's age key.
            let identity = root.appendingPathComponent("key.txt")
            try chez(["age-keygen", "--output", identity.path])
            let recipient = try chez(["age-keygen", "--convert", identity.path]).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            json["encryption"] = "age"
            json["age"] = ["identity": identity.path, "recipient": recipient]
            try JSONSerialization.data(withJSONObject: json).write(to: config)
        }
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
        let file = (url ?? source).appendingPathComponent(filename)
        if filename == "encrypted_private_dot_env.age" {
            let plaintext = root.appendingPathComponent("env-input")
            try text.write(to: plaintext, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: plaintext) }
            try chez(["encrypt", "--output", file.path, plaintext.path])
        } else {
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
    }
    func remoteChange(_ text: String) throws {
        try writeSource(text, at: other)
        try git(["add", "."], at: other)
        try git(["commit", "-m", "remote change"], at: other)
        try git(["push"], at: other)
    }
    var target: URL {
        home.appendingPathComponent(filename == "encrypted_private_dot_env.age" ? ".env" : filename.replacingOccurrences(of: "dot_", with: "."))
    }
    func writeTarget(_ text: String) throws { try text.write(to: target, atomically: true, encoding: .utf8) }
    func targetContent() throws -> String { try String(contentsOf: target, encoding: .utf8) }
    func engine(resolver: (any ConflictResolving)? = nil, chooseConflicts: ConflictSelecting? = nil) -> SyncEngine {
        SyncEngine(settings: settings, backups: backups, resolver: resolver, chooseConflicts: chooseConflicts)
    }
    func assertNoMerge() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent(".git/MERGE_HEAD").path))
        XCTAssertEqual(try git(["status", "--porcelain"]).text, "")
    }
}

@MainActor
final class SyncEngineTests: XCTestCase {
    func testConflictSelectionExternalIndexChangeIsPreservedWithoutAbortingOtherWork() async throws {
        for cancelSelection in [false, true] {
            let f = try Fixture(filename: "dot_env")
            try f.writeTarget("value=local\n")
            try f.remoteChange("value=remote\n")
            let source = f.source
            let remoteBefore = try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text
            do {
                _ = try await f.engine(chooseConflicts: { request in
                    try "value=external-index-edit\n".write(to: source.appendingPathComponent("dot_env"), atomically: true, encoding: .utf8)
                    try FixtureCommand().run("/usr/bin/git", ["add", "--", "dot_env"], directory: source)
                    if cancelSelection { throw CancellationError() }
                    return [request.conflicts[0].path: .remote]
                }).sync(.upload)
                XCTFail("external index edit ignored")
            } catch { XCTAssertTrue(error.localizedDescription.contains("Git の状態が変更")) }
            XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("dot_env"), encoding: .utf8), "value=external-index-edit\n")
            XCTAssertEqual(try f.git(["show", ":0:dot_env"]).text, "value=external-index-edit\n")
            XCTAssertEqual(try f.targetContent(), "value=local\n")
            XCTAssertEqual(try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text, remoteBefore)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent(".git/MERGE_HEAD").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent(".git/chezmoi-menu-pending-apply.json").path))
        }
    }

    func testConflictSelectionCancellationAbortsMergeAndPreservesLocalEnv() async throws {
        let f = try Fixture(encryptedEnv: true)
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        let remoteBefore = try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text
        let waiting = WaitingConflictSelection()
        let engine = f.engine(chooseConflicts: { try await waiting.choose($0) })
        let task = Task { try await engine.sync(.upload) }
        try await waiting.waitUntilEntered()
        do { _ = try await engine.sourcePreview(); XCTFail("concurrent operation accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("別の操作")) }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancellation ignored") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        XCTAssertEqual(try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text, remoteBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.appendingPathComponent(".git/chezmoi-menu-pending-apply.json").path))
        try f.assertNoMerge()
    }

    func testConflictSelectionSourceEditIsBackedUpAndNotOverwritten() async throws {
        let f = try Fixture(filename: "dot_env")
        try "other=base\n".write(to: f.source.appendingPathComponent("private_dot_other"), atomically: true, encoding: .utf8)
        try f.git(["add", "--all"])
        try f.git(["commit", "-m", "add second conflict file"])
        try f.git(["push"])
        try f.git(["pull", "--ff-only"], at: f.other)
        try f.chez(["apply", "--force"])
        try f.writeTarget("value=local\n")
        try "other=local\n".write(to: f.home.appendingPathComponent(".other"), atomically: true, encoding: .utf8)
        try "other=remote\n".write(to: f.other.appendingPathComponent("private_dot_other"), atomically: true, encoding: .utf8)
        try f.remoteChange("value=remote\n")
        let sourceFile = f.source.appendingPathComponent("dot_env")
        let otherFile = f.source.appendingPathComponent("private_dot_other")
        do {
            _ = try await f.engine(chooseConflicts: { request in
                try "value=edited-while-choosing\n".write(to: sourceFile, atomically: true, encoding: .utf8)
                try "other=edited-while-choosing\n".write(to: otherFile, atomically: true, encoding: .utf8)
                return Dictionary(uniqueKeysWithValues: request.conflicts.map { ($0.path, .remote) })
            }).sync(.upload)
            XCTFail("source edit ignored")
        } catch { XCTAssertTrue(error.localizedDescription.contains("選択中に source")) }
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: f.backups, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("external-source-edits/dot_env"), encoding: .utf8), "value=edited-while-choosing\n")
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("external-source-edits/private_dot_other"), encoding: .utf8), "other=edited-while-choosing\n")
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        try f.assertNoMerge()
    }

    func testConflictSelectionDestinationEditBlocksApplyAndPush() async throws {
        let f = try Fixture(encryptedEnv: true)
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        let target = f.target
        let remoteBefore = try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text
        do {
            _ = try await f.engine(chooseConflicts: { request in
                try "value=edited-while-choosing\n".write(to: target, atomically: true, encoding: .utf8)
                return [request.conflicts[0].path: .remote]
            }).sync(.upload)
            XCTFail("destination edit ignored")
        } catch { XCTAssertTrue(error.localizedDescription.contains("同期中")) }
        XCTAssertEqual(try f.targetContent(), "value=edited-while-choosing\n")
        XCTAssertEqual(try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text, remoteBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.appendingPathComponent(".git/chezmoi-menu-pending-apply.json").path))
    }

    func testConflictSelectionOrdinaryFileCanChooseRemoteWithAIDisabled() async throws {
        let f = try Fixture()
        f.settings.autoResolve = false
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        let report = try await f.engine(chooseConflicts: { request in
            XCTAssertEqual(request.conflicts.map(\.path), ["dot_test"])
            return ["dot_test": .remote]
        }).sync(.download)
        XCTAssertEqual(report.selectedCount, 1)
        XCTAssertEqual(report.resolvedCount, 0)
        XCTAssertEqual(try f.targetContent(), "value=remote\n")
        try f.assertNoMerge()
    }

    func testConflictSelectionLocalEncryptedEnvUploadsAndPreservesRemoteChanges() async throws {
        let f = try Fixture(encryptedEnv: true)
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        try "remote-only\n".write(to: f.other.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try f.git(["add", "README.md"], at: f.other)
        try f.git(["commit", "-m", "remote unrelated file"], at: f.other)
        try f.git(["push"], at: f.other)
        let remoteBefore = try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text.trimmingCharacters(in: .newlines)
        let engine = f.engine(resolver: FailingResolver(), chooseConflicts: { request in
            XCTAssertEqual(request.conflicts.map(\.path), ["encrypted_private_dot_env.age"])
            XCTAssertEqual(request.remoteHead, remoteBefore)
            XCTAssertEqual(request.direction, .upload)
            XCTAssertFalse(request.conflicts[0].localDeleted)
            XCTAssertFalse(request.conflicts[0].remoteDeleted)
            return [request.conflicts[0].path: .local]
        })
        let report = try await engine.sync(.upload)
        XCTAssertEqual(report.selectedCount, 1)
        XCTAssertEqual(report.resolvedCount, 0)
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        XCTAssertEqual(try f.git(["show", "HEAD:README.md"]).text, "remote-only\n")
        XCTAssertEqual(try f.git(["show", "HEAD:README.md"], at: f.remote).text, "remote-only\n")
        XCTAssertEqual(try f.git(["rev-list", "--parents", "-n", "1", "HEAD"]).text.split(whereSeparator: \.isWhitespace).count, 3)
        XCTAssertEqual(try f.git(["merge-base", "--is-ancestor", remoteBefore, "HEAD"]).code, 0)
        XCTAssertEqual(try String(contentsOf: report.backup.appendingPathComponent("destination/0"), encoding: .utf8), "value=local\n")
        try f.assertNoMerge()
    }

    func testConflictSelectionRemoteEncryptedEnvDownloadsWithoutAIOrPush() async throws {
        let f = try Fixture(encryptedEnv: true)
        f.settings.autoResolve = false
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        let remoteBefore = try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text
        let report = try await f.engine(chooseConflicts: { request in
            XCTAssertEqual(request.direction, .download)
            return Dictionary(uniqueKeysWithValues: request.conflicts.map { ($0.path, .remote) })
        }).sync(.download)
        XCTAssertEqual(try f.targetContent(), "value=remote\n")
        XCTAssertEqual(report.selectedCount, 1)
        XCTAssertEqual(report.resolvedCount, 0)
        XCTAssertEqual(try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text, remoteBefore)
        try f.assertNoMerge()
    }

    func testConflictSelectionCanMixLocalAndRemoteAcrossMultipleFiles() async throws {
        let f = try Fixture(encryptedEnv: true)
        try "other=base\n".write(to: f.source.appendingPathComponent("private_dot_other"), atomically: true, encoding: .utf8)
        try f.git(["add", "--all"])
        try f.git(["commit", "-m", "add second private file"])
        try f.git(["push"])
        try f.git(["pull", "--ff-only"], at: f.other)
        try f.chez(["apply", "--force"])
        try f.writeTarget("value=local\n")
        try "other=local\n".write(to: f.home.appendingPathComponent(".other"), atomically: true, encoding: .utf8)
        try "other=remote\n".write(to: f.other.appendingPathComponent("private_dot_other"), atomically: true, encoding: .utf8)
        try f.remoteChange("value=remote\n")
        let report = try await f.engine(resolver: FailingResolver(), chooseConflicts: { request in
            XCTAssertEqual(Set(request.conflicts.map(\.path)), ["encrypted_private_dot_env.age", "private_dot_other"])
            return ["encrypted_private_dot_env.age": .remote, "private_dot_other": .local]
        }).sync(.upload)
        XCTAssertEqual(report.selectedCount, 2)
        XCTAssertEqual(try f.targetContent(), "value=remote\n")
        XCTAssertEqual(try String(contentsOf: f.home.appendingPathComponent(".other"), encoding: .utf8), "other=local\n")
        try f.assertNoMerge()
    }

    func testConflictSelectionMissingChoicesAbortsMergeWithoutPush() async throws {
        let f = try Fixture(encryptedEnv: true)
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        let remoteBefore = try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text
        do { _ = try await f.engine(chooseConflicts: { _ in [:] }).sync(.upload); XCTFail("missing choices accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("すべての競合")) }
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        XCTAssertEqual(try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text, remoteBefore)
        try f.assertNoMerge()
    }

    func testConflictSelectionRemoteDeletionRemovesEncryptedEnv() async throws {
        let f = try Fixture(encryptedEnv: true)
        try f.writeTarget("value=local\n")
        try f.git(["rm", "encrypted_private_dot_env.age"], at: f.other)
        try f.git(["commit", "-m", "remove encrypted env"], at: f.other)
        try f.git(["push"], at: f.other)
        let report = try await f.engine(chooseConflicts: { request in
            XCTAssertTrue(request.conflicts[0].remoteDeleted)
            return ["encrypted_private_dot_env.age": .remote]
        }).sync(.download)
        XCTAssertEqual(report.selectedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.appendingPathComponent("encrypted_private_dot_env.age").path))
        // chezmoi does not remove a destination simply because it was forgotten from source.
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        try f.assertNoMerge()
    }

    func testConflictSelectionMixedWithAIResolvesEachOnlyOnce() async throws {
        let f = try Fixture(encryptedEnv: true)
        try "value=base\n".write(to: f.source.appendingPathComponent("dot_test"), atomically: true, encoding: .utf8)
        try f.git(["add", "--all"])
        try f.git(["commit", "-m", "add ordinary file"])
        try f.git(["push"])
        try f.git(["pull", "--ff-only"], at: f.other)
        try f.chez(["apply", "--force"])
        try f.writeTarget("value=local\n")
        try "value=local\n".write(to: f.home.appendingPathComponent(".test"), atomically: true, encoding: .utf8)
        try "value=remote\n".write(to: f.other.appendingPathComponent("dot_test"), atomically: true, encoding: .utf8)
        try f.remoteChange("value=remote\n")
        let report = try await f.engine(resolver: FixedResolver(content: "value=merged\n"), chooseConflicts: { request in
            XCTAssertEqual(request.conflicts.map(\.path), ["encrypted_private_dot_env.age"])
            return ["encrypted_private_dot_env.age": .remote]
        }).sync(.upload)
        XCTAssertEqual(report.selectedCount, 1)
        XCTAssertEqual(report.resolvedCount, 1)
        XCTAssertEqual(try f.targetContent(), "value=remote\n")
        XCTAssertEqual(try String(contentsOf: f.home.appendingPathComponent(".test"), encoding: .utf8), "value=merged\n")
        try f.assertNoMerge()
    }

    func testMultipleSourceFilesWithEncryptedEnvCommitAllChanges() async throws {
        let f = try Fixture(encryptedEnv: true)
        let initial = ["dot_alpha": "alpha=base\n", "dot_deleted": "deleted=base\n",
                       "dot_old": "renamed=base\n", "private_dot_credentials": "credential=base\n"]
        for (path, content) in initial {
            try content.write(to: f.source.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        try f.git(["add", "--all"])
        try f.git(["commit", "-m", "Add multiple managed files"])
        try f.git(["push"])
        try f.chez(["apply", "--force"])
        let remoteBefore = try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text

        try f.writeSource("value=env-edited\n")
        try "alpha=edited\n".write(to: f.source.appendingPathComponent("dot_alpha"), atomically: true, encoding: .utf8)
        try f.git(["add", "dot_alpha"])
        try FileManager.default.removeItem(at: f.source.appendingPathComponent("dot_deleted"))
        try f.git(["mv", "dot_old", "dot_renamed"])
        try "new=edited\n".write(to: f.source.appendingPathComponent("new [config].txt"), atomically: true, encoding: .utf8)
        try "credential=edited\n".write(to: f.source.appendingPathComponent("private_dot_credentials"), atomically: true, encoding: .utf8)

        let visible = ["dot_alpha", "dot_deleted", "dot_old", "dot_renamed", "new [config].txt"]
        let hidden = ["encrypted_private_dot_env.age", "private_dot_credentials"]
        let engine = f.engine(resolver: FailingResolver())
        let before = try await engine.sourcePreview()
        XCTAssertEqual(before.uncommitted.files, visible)
        XCTAssertEqual(before.uncommitted.omittedFiles, hidden)
        XCTAssertTrue(before.uncommitted.text.contains("+alpha=edited"))
        XCTAssertTrue(before.uncommitted.text.contains("-deleted=base"))
        XCTAssertTrue(before.uncommitted.text.contains("+new=edited"))
        XCTAssertTrue(before.uncommitted.text.contains("deleted file mode"))
        XCTAssertTrue(before.uncommitted.text.contains("new file mode"))
        XCTAssertFalse(before.uncommitted.text.contains("env-edited"))
        XCTAssertFalse(before.uncommitted.text.contains("credential=edited"))

        let report = try await engine.commitSource(message: "Update multiple files")
        XCTAssertTrue(report.preview.uncommitted.files.isEmpty)
        XCTAssertTrue(report.preview.uncommitted.omittedFiles.isEmpty)
        XCTAssertEqual(report.preview.upstream?.files, visible)
        XCTAssertEqual(report.preview.upstream?.omittedFiles, hidden)
        XCTAssertEqual(report.preview.ahead, 1)
        XCTAssertEqual(try f.git(["diff-tree", "--no-commit-id", "--name-only", "--no-renames", "-r", "HEAD"]).text
            .split(separator: "\n").map(String.init).sorted(), (visible + hidden).sorted())
        XCTAssertEqual(try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text, remoteBefore)
        XCTAssertEqual(try f.targetContent(), "value=base\n")
        XCTAssertEqual(try String(contentsOf: f.home.appendingPathComponent(".alpha"), encoding: .utf8), "alpha=base\n")
        try f.assertNoMerge()
    }

    func testMultipleDestinationFilesWithEncryptedEnvPreviewAndUpload() async throws {
        let f = try Fixture(encryptedEnv: true)
        for name in ["alpha", "beta"] {
            try "\(name)=base\n".write(to: f.source.appendingPathComponent("dot_" + name), atomically: true, encoding: .utf8)
        }
        try f.git(["add", "--all"])
        try f.git(["commit", "-m", "Add destination fixtures"])
        try f.git(["push"])
        try f.chez(["apply", "--force"])
        for name in ["alpha", "beta"] {
            try "\(name)=edited\n".write(to: f.home.appendingPathComponent("." + name), atomically: true, encoding: .utf8)
        }
        try f.writeTarget("value=env-edited\n")
        let head = try f.git(["rev-parse", "HEAD"]).text
        let index = try Data(contentsOf: f.source.appendingPathComponent(".git/index"))
        let engine = f.engine(resolver: FailingResolver())
        let preview = try await engine.preview()
        XCTAssertEqual(preview.files.sorted(), [".alpha", ".beta"])
        XCTAssertEqual(preview.omittedFiles, [".env"])
        XCTAssertTrue(preview.text.contains("alpha=edited"))
        XCTAssertTrue(preview.text.contains("beta=edited"))
        XCTAssertFalse(preview.text.contains("env-edited"))
        XCTAssertEqual(try f.git(["rev-parse", "HEAD"]).text, head)
        XCTAssertEqual(try Data(contentsOf: f.source.appendingPathComponent(".git/index")), index)

        _ = try await engine.sync(.upload)
        for name in ["alpha", "beta"] {
            XCTAssertEqual(try f.git(["show", "HEAD:dot_" + name], at: f.remote).text, "\(name)=edited\n")
        }
        XCTAssertEqual(try f.git(["show", "HEAD:encrypted_private_dot_env.age"], at: f.remote).data,
                       try Data(contentsOf: f.source.appendingPathComponent("encrypted_private_dot_env.age")))
        XCTAssertEqual(try f.targetContent(), "value=env-edited\n")
        let after = try await engine.preview()
        XCTAssertTrue(after.files.isEmpty)
        XCTAssertTrue(after.omittedFiles.isEmpty)
        try f.assertNoMerge()
    }

    func testMultipleSourceFilesRemainListedAndCommittedWhenDiffIsTruncated() async throws {
        let f = try Fixture(encryptedEnv: true)
        try f.writeSource("value=env-edited\n")
        try String(repeating: "large-file-line\n", count: 10_000)
            .write(to: f.source.appendingPathComponent("a-large.txt"), atomically: true, encoding: .utf8)
        try "small-file-content\n".write(to: f.source.appendingPathComponent("z-small.txt"), atomically: true, encoding: .utf8)
        let engine = f.engine()
        let before = try await engine.sourcePreview()
        XCTAssertEqual(before.uncommitted.files, ["a-large.txt", "z-small.txt"])
        XCTAssertEqual(before.uncommitted.omittedFiles, ["encrypted_private_dot_env.age"])
        XCTAssertTrue(before.uncommitted.truncated)
        XCTAssertEqual(before.uncommitted.text.count, 100_000)

        let report = try await engine.commitSource(message: "Commit all files despite preview limit")
        XCTAssertEqual(report.preview.upstream?.files, ["a-large.txt", "z-small.txt"])
        XCTAssertEqual(report.preview.upstream?.omittedFiles, ["encrypted_private_dot_env.age"])
        XCTAssertEqual(report.preview.upstream?.truncated, true)
        XCTAssertEqual(try f.git(["show", "HEAD:z-small.txt"]).text, "small-file-content\n")
        XCTAssertTrue(report.preview.uncommitted.files.isEmpty)
        XCTAssertTrue(report.preview.uncommitted.omittedFiles.isEmpty)
        try f.assertNoMerge()
    }

    func testSourceCommitShowsEncryptedEnvBeforeAndAfterCommitWithoutSendingOrApplying() async throws {
        let f = try Fixture(encryptedEnv: true)
        f.settings.excludedAIPaths = ""
        try f.writeSource("value=source-edit\n")
        let remoteBefore = try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text
        let indexBefore = try Data(contentsOf: f.source.appendingPathComponent(".git/index"))
        let engine = f.engine(resolver: FailingResolver())
        let before = try await engine.sourcePreview()
        XCTAssertEqual(before.uncommitted.omittedFiles, ["encrypted_private_dot_env.age"])
        XCTAssertEqual(before.uncommitted.text, "")
        XCTAssertEqual(before.ahead, 0)
        XCTAssertEqual(try Data(contentsOf: f.source.appendingPathComponent(".git/index")), indexBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.backups.path))

        let report = try await engine.commitSource(message: "Update encrypted env")
        XCTAssertTrue(report.preview.uncommitted.files.isEmpty)
        XCTAssertTrue(report.preview.uncommitted.omittedFiles.isEmpty)
        XCTAssertEqual(report.preview.upstream?.omittedFiles, ["encrypted_private_dot_env.age"])
        XCTAssertEqual(report.preview.upstream?.text, "")
        XCTAssertEqual(report.preview.ahead, 1)
        XCTAssertEqual(report.preview.behind, 0)
        XCTAssertEqual(try f.git(["log", "-1", "--format=%s"]).text, "Update encrypted env\n")
        XCTAssertEqual(try f.targetContent(), "value=base\n")
        XCTAssertEqual(try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text, remoteBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.backup.appendingPathComponent("source/.git").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.appendingPathComponent(".git/chezmoi-menu-pending-apply.json").path))
        // A subsequent Upload still applies and sends the committed source edit.
        _ = try await engine.sync(.upload)
        XCTAssertEqual(try f.targetContent(), "value=source-edit\n")
        try f.assertNoMerge()
    }

    func testSourcePreviewIncludesStagedUnstagedAndUntrackedLiteralPaths() async throws {
        let f = try Fixture()
        try f.writeSource("value=staged\n")
        try f.git(["add", "dot_test"])
        try f.writeSource("value=worktree\n")
        let name = "new [config].txt"
        try "new-file-content\n".write(to: f.source.appendingPathComponent(name), atomically: true, encoding: .utf8)
        let preview = try await f.engine().sourcePreview()
        XCTAssertEqual(preview.uncommitted.files, ["dot_test", name])
        XCTAssertTrue(preview.uncommitted.text.contains("+value=worktree"))
        XCTAssertTrue(preview.uncommitted.text.contains("+new-file-content"))
        let report = try await f.engine().commitSource(message: "Capture source edits")
        XCTAssertEqual(report.preview.upstream?.files.sorted(), ["dot_test", name])
        XCTAssertTrue(report.preview.uncommitted.files.isEmpty)
        XCTAssertEqual(try f.git(["status", "--porcelain"]).text, "")
    }

    func testSourcePreviewDoesNotExecuteExternalDiffOrTextConversion() async throws {
        let f = try Fixture()
        let marker = f.root.appendingPathComponent("diff-driver-ran")
        let driver = f.root.appendingPathComponent("diff-driver")
        try "#!/bin/sh\ntouch '\(marker.path)'\n".write(to: driver, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: driver.path)
        try f.git(["config", "diff.test.command", driver.path])
        try f.git(["config", "diff.test.textconv", driver.path])
        try "dot_test diff=test\n".write(to: f.source.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
        try f.writeSource("value=edit\n")
        let preview = try await f.engine().sourcePreview()
        XCTAssertTrue(preview.uncommitted.text.contains("+value=edit"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testSourceCommitWithoutUpstreamStillCommitsLocally() async throws {
        let f = try Fixture()
        try f.git(["branch", "--unset-upstream"])
        try f.writeSource("value=edit\n")
        let preview = try await f.engine().sourcePreview()
        XCTAssertNil(preview.upstream)
        let report = try await f.engine().commitSource(message: "Local edit")
        XCTAssertNil(report.preview.upstream)
        XCTAssertEqual(try f.git(["status", "--porcelain"]).text, "")
    }

    func testSourceCommitRejectsEmptyMessageNoChangesAndPendingApply() async throws {
        let f = try Fixture()
        let head = try f.git(["rev-parse", "HEAD"]).text
        do { _ = try await f.engine().commitSource(message: "  "); XCTFail("empty message accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("メッセージ")) }
        do { _ = try await f.engine().commitSource(message: "No edits"); XCTFail("empty commit accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("未コミット変更はありません")) }
        try f.writeSource("value=edit\n")
        try Data("{}".utf8).write(to: f.source.appendingPathComponent(".git/chezmoi-menu-pending-apply.json"))
        do { _ = try await f.engine().commitSource(message: "Pending"); XCTFail("pending apply accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("未完了")) }
        XCTAssertEqual(try f.git(["rev-parse", "HEAD"]).text, head)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.backups.path))
    }

    func testEncryptedEnvUploadAndDownloadOnAnotherDestination() async throws {
        let f = try Fixture(encryptedEnv: true)
        try f.writeTarget("value=local\n")
        let check = try await f.engine().check()
        XCTAssertEqual(check.localCaptures, 1)
        _ = try await f.engine(resolver: FailingResolver()).sync(.upload)
        let ciphertext = try f.git(["show", "HEAD:encrypted_private_dot_env.age"], at: f.remote).data
        XCTAssertFalse(String(decoding: ciphertext, as: UTF8.self).contains("value=local"))
        XCTAssertEqual(try f.git(["ls-tree", "-r", "--name-only", "HEAD"], at: f.remote).text,
                       "encrypted_private_dot_env.age\n")

        // Use a separate source, destination and state database, as on a second Mac.
        let secondHome = f.root.appendingPathComponent("second-home")
        try FileManager.default.createDirectory(at: secondHome, withIntermediateDirectories: true)
        var config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: f.config)) as? [String: Any])
        config["sourceDir"] = f.other.path
        config["destDir"] = secondHome.path
        config["persistentState"] = f.root.appendingPathComponent("second-state.boltdb").path
        let configURL = f.root.appendingPathComponent("second-chezmoi.json")
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)
        var settings = f.settings
        settings.configPath = configURL.path
        let second = SyncEngine(settings: settings, backups: f.root.appendingPathComponent("second-backups"),
                                resolver: FailingResolver())
        _ = try await second.sync(.download)
        let target = secondHome.appendingPathComponent(".env")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "value=local\n")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        try f.assertNoMerge()
    }

    func testEncryptedEnvSourceEditIsAppliedAndPushed() async throws {
        let f = try Fixture(encryptedEnv: true)
        // Equivalent to saving chezmoi edit ~/.env, before apply.
        try f.writeSource("value=source-edit\n")
        _ = try await f.engine(resolver: FailingResolver()).sync(.upload)
        XCTAssertEqual(try f.targetContent(), "value=source-edit\n")
        XCTAssertEqual(try f.git(["rev-parse", "HEAD"]).text,
                       try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text)
    }

    func testEncryptedEnvConflictNeverReachesResolverEvenWithoutExclusions() async throws {
        let f = try Fixture(encryptedEnv: true)
        f.settings.excludedAIPaths = ""
        try f.writeTarget("value=local\n")
        try f.remoteChange("value=remote\n")
        let remoteBefore = try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text
        do { _ = try await f.engine(resolver: FailingResolver()).sync(.upload); XCTFail("must stop") }
        catch { XCTAssertTrue(error.localizedDescription.contains("除外対象")) }
        XCTAssertEqual(try f.targetContent(), "value=local\n")
        XCTAssertEqual(try f.git(["rev-parse", "refs/heads/main"], at: f.remote).text, remoteBefore)
        try f.assertNoMerge()
    }

    func testEncryptedEnvPreviewIsOmittedEvenWithoutExclusions() async throws {
        let f = try Fixture(encryptedEnv: true)
        f.settings.excludedAIPaths = ""
        try f.writeTarget("value=local\n")
        let preview = try await f.engine().preview()
        XCTAssertEqual(preview.omittedCount, 1)
        XCTAssertEqual(preview.omittedFiles, [".env"])
        XCTAssertTrue(preview.files.isEmpty)
        XCTAssertEqual(preview.text, "")
    }

    func testEncryptedEnvMissingIdentityStopsCheckWithoutChangingFiles() async throws {
        let f = try Fixture(encryptedEnv: true)
        let head = try f.git(["rev-parse", "HEAD"]).text
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("key.txt"))
        do { _ = try await f.engine().check(); XCTFail("missing identity accepted") }
        catch { XCTAssertTrue(error is SyncError) }
        XCTAssertEqual(try f.git(["rev-parse", "HEAD"]).text, head)
        XCTAssertEqual(try f.targetContent(), "value=base\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.backups.path))
    }

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
        XCTAssertEqual(preview.omittedFiles, [".env"])
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
        XCTAssertEqual(preview.omittedFiles, [".env"])
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
