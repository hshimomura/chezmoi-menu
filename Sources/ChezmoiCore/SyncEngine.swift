import Foundation
import Darwin

public enum SyncDirection: String, Sendable { case download, upload }

public struct SyncSettings: Codable, Sendable {
    public var chezmoiPath = "/opt/homebrew/bin/chezmoi"
    public var configPath = ""
    public var model = "gpt-6-luna"
    public var autoResolve = true
    public var runScripts = false
    public var excludedAIPaths = "encrypted_\nprivate_\n.env\ndot_env\n.ssh\ndot_ssh\ncredential\nsecret\ntoken\n.pem\n.key"
    public init() {}
}

public struct SyncReport: Sendable {
    public let backup: URL
    public let resolvedCount: Int
}

public struct SyncCheckReport: Sendable {
    public let source: String
    public let destination: String
    public let managedCount: Int
    public let sourceChanges: Int
    public let destinationChanges: Int
    public let localCaptures: Int
    public let remoteMatches: Bool
}

public actor SyncEngine {
    let settings: SyncSettings
    let backups: URL
    let resolver: (any ConflictResolving)?
    let logger: @Sendable (String) -> Void
    let onEvent: @Sendable (SyncEvent) -> Void
    private var operationInProgress = false
    let command = Command()
    let fm = FileManager.default

    public init(settings: SyncSettings, backups: URL, resolver: (any ConflictResolving)?,
                log: @escaping @Sendable (String) -> Void = { _ in },
                onEvent: @escaping @Sendable (SyncEvent) -> Void = { _ in }) {
        self.settings = settings; self.backups = backups; self.resolver = resolver
        self.logger = log; self.onEvent = onEvent
    }

    private var flags: [String] {
        ["--no-tty", "--no-pager", "--color=false"] +
        (settings.configPath.isEmpty ? [] : ["--config", NSString(string: settings.configPath).expandingTildeInPath])
    }

    private func report(_ phase: SyncPhase, _ message: String) {
        logger(message)
        onEvent(SyncEvent(phase: phase, message: message))
    }

    private func beginOperation() throws {
        try Task.checkCancellation()
        guard !operationInProgress else { throw SyncError("別の操作を実行しています。完了を待ってください。") }
        operationInProgress = true
    }

    @discardableResult
    private func chez(_ args: [String]) async throws -> CommandResult {
        try Task.checkCancellation()
        let executable = NSString(string: settings.chezmoiPath).expandingTildeInPath
        if args.first == "re-add" || (args.first == "apply" && !args.contains("--dry-run")) {
            return try await command.runToCompletion(executable, flags + args)
        }
        return try await command.run(executable, flags + args)
    }

    @discardableResult
    private func git(_ args: [String], _ source: URL, allowFailure: Bool = false) async throws -> CommandResult {
        try Task.checkCancellation()
        if ["add", "commit", "merge", "push"].contains(args.first ?? "") {
            return try await command.runToCompletion("/usr/bin/git", args, directory: source, allowFailure: allowFailure)
        }
        return try await command.run("/usr/bin/git", args, directory: source, allowFailure: allowFailure)
    }

    // No fetch, re-add, commit, apply, push or API requests. Dry-run renders the current source.
    public func check() async throws -> SyncCheckReport {
        try beginOperation()
        defer { operationInProgress = false }
        report(.checking, "同期前チェックを開始しています…")
        let config = try JSONSerialization.jsonObject(with: await chez(["dump-config", "--format=json"]).data) as? [String: Any] ?? [:]
        guard let sourcePath = config["sourceDir"] as? String, let destinationPath = config["destDir"] as? String else {
            throw SyncError("chezmoi の source / destination を確認できません。")
        }
        guard (config["hooks"] as? [String: Any] ?? [:]).isEmpty else {
            throw SyncError("chezmoi hooks が設定されているため、同期前チェックでは実行しません。hooks の内容を確認してください。")
        }
        let source = URL(fileURLWithPath: sourcePath).resolvingSymlinksInPath()
        let destination = URL(fileURLWithPath: destinationPath).resolvingSymlinksInPath()
        guard (config["mode"] as? String ?? "file") == "file" else { throw SyncError("chezmoi の mode=file が必要です。") }
        let gitConfig = config["git"] as? [String: Any] ?? [:]
        guard !["autoadd", "autocommit", "autopush", "autoAdd", "autoCommit", "autoPush"].contains(where: { gitConfig[$0] as? Bool == true }) else {
            throw SyncError("chezmoi の Git 自動処理を無効にしてから同期してください。")
        }
        let root = try await git(["rev-parse", "--show-toplevel"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.path == URL(fileURLWithPath: root).resolvingSymlinksInPath().path else { throw SyncError("Git のルートと source が一致しません。") }
        for marker in ["MERGE_HEAD", "rebase-merge", "rebase-apply", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_START", "index.lock", "chezmoi-menu-pending-apply.json"] {
            guard !fm.fileExists(atPath: source.appendingPathComponent(".git/" + marker).path) else {
                throw SyncError("進行中または未完了の Git / apply 操作があります。履歴を確認してください。")
            }
        }
        let branch = try await git(["symbolic-ref", "--quiet", "--short", "HEAD"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = try await git(["config", "--get", "branch.\(branch).remote"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = try await git(["config", "--get", "branch.\(branch).merge"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty, !remote.hasPrefix("-"), remote != ".", ref.hasPrefix("refs/heads/") else {
            throw SyncError("現在のブランチに upstream を設定してください。")
        }
        let head = try await git(["rev-parse", "HEAD"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        report(.checking, "Git の接続とリモートの状態を確認しています…")
        let remoteHead = try await git(["ls-remote", "--exit-code", "--", remote, ref], source).text.split(whereSeparator: \.isWhitespace).first.map(String.init)
        let managed = try await managedPaths()
        let sourceChanges = try await git(["status", "--porcelain"], source).text.split(separator: "\n").count
        let destinationChanges = try await chez(["status", "--exclude=scripts"]).text.split(separator: "\n").count
        let captures = try await changedDestinations(source: source, destination: destination)
        report(.checking, "現在の source の適用を予行しています（スクリプトは実行しません）…")
        try await chez(["apply", "--dry-run", "--force", "--exclude=scripts"])
        return SyncCheckReport(source: source.path, destination: destination.path, managedCount: managed.count,
                               sourceChanges: sourceChanges, destinationChanges: destinationChanges,
                               localCaptures: captures.count, remoteMatches: remoteHead == head)
    }

    public func sync(_ direction: SyncDirection) async throws -> SyncReport {
        try beginOperation()
        defer { operationInProgress = false }
        report(.preparing, "設定とリポジトリを確認しています…")
        let source = URL(fileURLWithPath: try await chez(["source-path"]).text.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath()
        let root = try await git(["rev-parse", "--show-toplevel"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.path == URL(fileURLWithPath: root).resolvingSymlinksInPath().path,
              fm.fileExists(atPath: source.appendingPathComponent(".git").path, isDirectory: nil),
              (try? fm.attributesOfItem(atPath: source.appendingPathComponent(".git").path)[.type] as? FileAttributeType) == .typeDirectory else {
            throw SyncError("Git 管理ディレクトリと chezmoi source が一致する通常のリポジトリが必要です（worktree は未対応）。")
        }
        let lock = open(source.appendingPathComponent(".git/chezmoi-menu.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw SyncError("同期用のロックを取得できません。") }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw SyncError("別の Chezmoi Menu が同期しています。完了を待ってください。") }
        defer { flock(lock, LOCK_UN) }
        let pendingApply = source.appendingPathComponent(".git/chezmoi-menu-pending-apply.json")
        if fm.fileExists(atPath: pendingApply.path) {
            let status = try await chez(["status", "--exclude=scripts"]).text
            let needsApply = status.split(separator: "\n").contains { line in
                line.count < 3 || Array(line.prefix(2))[1] != " "
            }
            guard !needsApply else {
                throw SyncError("前回の統合後に apply が完了していません。履歴とバックアップを確認し、ターミナルで chezmoi diff / apply を完了してから再実行してください。")
            }
            try fm.removeItem(at: pendingApply)
        }
        for marker in ["MERGE_HEAD", "rebase-merge", "rebase-apply", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_START", "index.lock"] {
            guard !fm.fileExists(atPath: source.appendingPathComponent(".git/" + marker).path) else {
                throw SyncError("進行中の Git 操作があります。先に完了または中止してください。")
            }
        }
        guard !fm.fileExists(atPath: source.appendingPathComponent(".gitmodules").path) else {
            throw SyncError("submodule を含むリポジトリは自動同期の対象外です。")
        }
        let config = try JSONSerialization.jsonObject(with: await chez(["dump-config", "--format=json"]).data) as? [String: Any] ?? [:]
        guard (config["hooks"] as? [String: Any] ?? [:]).isEmpty else {
            throw SyncError("chezmoi hooks を無効にしてから同期してください。")
        }
        let gitConfig = config["git"] as? [String: Any] ?? [:]
        guard !["autoadd", "autocommit", "autopush", "autoAdd", "autoCommit", "autoPush"].contains(where: { gitConfig[$0] as? Bool == true }) else {
            throw SyncError("アプリが同期順序を管理するため、chezmoi の git.autoAdd / autoCommit / autoPush を false にしてください。")
        }
        guard (config["mode"] as? String ?? "file") == "file" else { throw SyncError("chezmoi の mode=file が必要です。") }
        let destination = URL(fileURLWithPath: config["destDir"] as? String ?? NSHomeDirectory()).resolvingSymlinksInPath()
        let branch = try await git(["symbolic-ref", "--quiet", "--short", "HEAD"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = try await git(["config", "--get", "branch.\(branch).remote"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteRef = try await git(["config", "--get", "branch.\(branch).merge"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty, !remote.hasPrefix("-"), remote != ".", remoteRef.hasPrefix("refs/heads/") else {
            throw SyncError("現在のブランチに upstream を設定してください（git branch --set-upstream-to=origin/main）。")
        }
        report(.fetching, "リモートの変更を取得しています…")
        try await git(["fetch", "--no-tags", "--", remote, remoteRef], source)
        let fetched = try await git(["rev-parse", "FETCH_HEAD"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialHead = try await git(["rev-parse", "HEAD"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        let localTargets = try await changedDestinations(source: source, destination: destination)
        report(.backingUp, "同期前の状態をバックアップしています…")
        let backup = try await makeBackup(source: source, destination: destination, head: initialHead)
        report(.backingUp, "同期前のバックアップを保存しました。")
        if !localTargets.isEmpty {
            report(.capturing, "Mac 側の変更を source に取り込んでいます…")
            // Explicit targets prevent old destination files from replacing pending source edits.
            for target in localTargets { try await chez(["re-add", "--", target]) }
        }
        try await git(["add", "--all"], source)
        let changed = try await git(["diff", "--cached", "--quiet"], source, allowFailure: true)
        guard changed.code == 0 || changed.code == 1 else { throw SyncError("Git index の変更を確認できません。") }
        if changed.code == 1 {
            try await git(["commit", "-m", "Chezmoi Menu: capture local changes"], source)
        }
        let localHead = try await git(["rev-parse", "HEAD"], source).text.trimmingCharacters(in: .whitespacesAndNewlines)
        try "\(localHead)\n".write(to: backup.appendingPathComponent("captured-head.txt"), atomically: true, encoding: .utf8)
        let resolved = try await integrate(source: source, fetched: fetched, localHead: localHead,
                                           backup: backup, pendingApply: pendingApply)
        let applyFlags = settings.runScripts ? [] : ["--exclude=scripts"]
        report(.validating, "適用内容を検証しています…")
        // Rendering catches broken chezmoi templates before touching destination files.
        try await chez(["apply", "--dry-run", "--force"] + applyFlags)
        // Do not overwrite destination edits made while an API request was in flight.
        try await verifyDestinationUnchanged(backup: backup, destination: destination)
        report(.applying, "Mac に設定を適用しています…")
        try await chez(["apply", "--force"] + applyFlags)
        try fm.removeItem(at: pendingApply)
        if direction == .upload {
            report(.pushing, "変更をリモートへ送信しています…")
            // A normal push rejects remote races. Never force push or retry a rejected push silently.
            try await git(["push", "--", remote, "HEAD:\(remoteRef)"], source)
        }
        report(.finished, direction == .download ? "Download 同期が完了しました。" : "Upload 同期が完了しました。")
        return SyncReport(backup: backup, resolvedCount: resolved)
    }

    private func integrate(source: URL, fetched: String, localHead: String,
                           backup: URL, pendingApply: URL) async throws -> Int {
        try Task.checkCancellation()
        // Record BEFORE merging: a stopped task must not re-import the old destination over a merge.
        try JSONSerialization.data(withJSONObject: ["backup": backup.path, "head": localHead])
            .write(to: pendingApply, options: .atomic)
        var completed = false
        defer {
            if !completed {
                await withTaskCancellationShield {
                    report(.cleaningUp, "未完了の merge を後処理しています…")
                    if fm.fileExists(atPath: source.appendingPathComponent(".git/MERGE_HEAD").path) {
                        let aborted = try? await git(["merge", "--abort"], source, allowFailure: true)
                        if aborted?.code != 0 { logger("merge の中止に失敗しました。リポジトリを確認してください。") }
                    }
                    let head = try? await git(["rev-parse", "HEAD"], source).text.trimmingCharacters(in: .newlines)
                    if head == localHead && !fm.fileExists(atPath: source.appendingPathComponent(".git/MERGE_HEAD").path) {
                        try? fm.removeItem(at: pendingApply)
                    }
                }
            }
        }
        var resolved = 0
        report(.merging, "ローカルとリモートを統合しています…")
        let merge = try await git(["merge", "--no-edit", "--no-stat", fetched], source, allowFailure: true)
        if merge.code != 0 {
            let paths = try await conflictPaths(source)
            guard !paths.isEmpty else { throw SyncError("Git merge が失敗しました。リポジトリの状態を確認してください。") }
            guard settings.autoResolve, let resolver else {
                throw SyncError("競合があります。設定で AI 自動解決を有効にして API key を保存してください。")
            }
            // Validate ALL paths before sending any content.
            var conflicts: [Conflict] = []
            for path in paths { conflicts.append(try await readConflict(path, source: source)) }
            for conflict in conflicts {
                report(.resolving, "AI で競合を解決しています（\(resolved + 1)/\(conflicts.count)）…")
                let file = source.appendingPathComponent(conflict.path)
                let beforeAI = try Data(contentsOf: file)
                let resolution = try await resolver.resolve(conflict)
                try Task.checkCancellation()
                try OpenAIResolver.validate(resolution)
                guard try Data(contentsOf: file) == beforeAI else {
                    let saved = backup.appendingPathComponent("external-source-edits").appendingPathComponent(conflict.path)
                    try fm.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: file, to: saved)
                    throw SyncError("AI 解決中に source の競合ファイルが編集されたため停止しました。編集内容はバックアップの external-source-edits に保存しました。")
                }
                // Preserve an existing file's executable bit.
                try Data(resolution.content.utf8).write(to: file)
                try await git(["add", "--", conflict.path], source)
                resolved += 1
            }
            guard try await conflictPaths(source).isEmpty else { throw SyncError("未解決の競合が残っています。") }
            try await git(["commit", "-m", "Chezmoi Menu: merge upstream with AI conflict resolution"], source)
        }
        // No suspension after the last protected mutation: leave the marker until apply finishes.
        completed = true
        return resolved
    }

    // Local-only preview. The same exclusion policy protects AI input and on-screen diff content.
    public func preview() async throws -> DiffPreview {
        try beginOperation()
        defer { operationInProgress = false }
        report(.previewing, "Mac と現在の source の差分を確認しています…")
        let config = try JSONSerialization.jsonObject(with: await chez(["dump-config", "--format=json"]).data) as? [String: Any] ?? [:]
        guard (config["hooks"] as? [String: Any] ?? [:]).isEmpty,
              let destination = config["destDir"] as? String else {
            throw SyncError("hooks のない chezmoi 設定が必要です。")
        }
        let status = try await chez(["status", "--exclude=scripts", "--path-style=absolute"]).text
        var eligible: [String] = []
        var omitted = 0
        for line in status.split(separator: "\n") {
            try Task.checkCancellation()
            guard line.count >= 4, Array(line.prefix(3))[2] == " " else { throw SyncError("status の形式を確認できません。") }
            let target = String(line.dropFirst(3))
            guard target.hasPrefix(destination + "/"), !target.contains("\r") else { throw SyncError("差分のパスを確認できません。") }
            let path = try await chez(["source-path", "--", target]).text.trimmingCharacters(in: .newlines)
            let patterns = settings.excludedAIPaths.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            let excluded = patterns.contains { path.lowercased().contains($0) }
                || path.split(separator: "/").contains { $0.hasPrefix("encrypted_") }
            if excluded { omitted += 1 } else { eligible.append(target) }
        }
        // An empty target list would mean "all files" to chezmoi.
        let text = eligible.isEmpty ? "" : try await chez(["diff", "--exclude=scripts,encrypted", "--"] + eligible).text
        let limit = 100_000
        return DiffPreview(files: eligible.map { String($0.dropFirst(destination.count + 1)) },
                           omittedCount: omitted, text: String(text.prefix(limit)), truncated: text.count > limit)
    }

    private func changedDestinations(source: URL, destination: URL) async throws -> [String] {
        let status = try await chez(["status", "--exclude=scripts", "--path-style=absolute"]).text
        var targets: [String] = []
        for line in status.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.count >= 4 else { throw SyncError("chezmoi status の出力形式を確認できません。") }
            let columns = Array(line.prefix(3))
            guard columns[2] == " " else { throw SyncError("改行を含むファイル名は未対応です。") }
            if columns[0] == " " || columns[1] == " " { continue }
            let target = String(line.dropFirst(3))
            guard target.hasPrefix(destination.path + "/"), !target.contains("\r") else { throw SyncError("対象ファイルのパスを確認できません。") }
            let path = try await chez(["source-path", "--", target]).text.trimmingCharacters(in: .newlines)
            let attributes = try? fm.attributesOfItem(atPath: target)
            guard columns[0] == "M" || columns[0] == "A",
                  attributes?[.type] as? FileAttributeType == .typeRegular,
                  !path.hasSuffix(".tmpl") else {
                throw SyncError("Mac 側で変更されたテンプレート・削除・リンク・特殊ファイルがあります。chezmoi merge / edit で source に反映してから再実行してください。")
            }
            let relative = String(path.dropFirst(source.path.count + 1))
            let dirty = try await git(["status", "--porcelain", "--", relative], source).text
            guard dirty.isEmpty else { throw SyncError("同じファイルの source と Mac 側が両方変更されています。chezmoi merge で統合してから再実行してください。") }
            targets.append(target)
        }
        return targets
    }

    private func conflictPaths(_ source: URL) async throws -> [String] {
        try await git(["diff", "--name-only", "--diff-filter=U", "-z"], source).text.split(separator: "\0").map(String.init)
    }

    private func readConflict(_ path: String, source: URL) async throws -> Conflict {
        let patterns = settings.excludedAIPaths.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              !patterns.contains(where: { path.lowercased().contains($0) }),
              !path.split(separator: "/").contains(where: { $0.hasPrefix("encrypted_") }) else {
            throw SyncError("AI 送信の除外対象に競合があります。手動で解決してください。")
        }
        let stages = try await git(["ls-files", "--stage", "--", path], source).text.split(separator: "\n")
        // Only ordinary text modify/modify conflicts; never reinterpret symlinks or deletions.
        guard stages.count == 3, stages.allSatisfy({ $0.hasPrefix("100644 ") || $0.hasPrefix("100755 ") }),
              Set(stages.compactMap({ $0.split(separator: " ").first.map(String.init) })).count == 1 else {
            throw SyncError("削除・追加・名前変更・リンク・権限の競合は手動で解決してください。")
        }
        func read(_ stage: Int) async throws -> String {
            let data = try await git(["show", ":\(stage):\(path)"], source).data
            guard data.count <= 48_000, !data.contains(0), let text = String(data: data, encoding: .utf8) else {
                throw SyncError("AI 自動解決は各版 48 KB 以下の UTF-8 テキストに対応しています。")
            }
            return text
        }
        return try await Conflict(path: path, base: read(1), local: read(2), remote: read(3))
    }

    private struct DestinationEntry: Codable {
        let path: String
        let saved: String?
        let kind: String
        let permissions: Int?
    }

    private func makeBackup(source: URL, destination: URL, head: String) async throws -> URL {
        let backup = backups.appendingPathComponent(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(8))
        guard !backup.path.hasPrefix(source.path + "/") else { throw SyncError("バックアップ先を source の外に設定してください。") }
        try fm.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backups.path)
        try fm.copyItem(at: source, to: backup.appendingPathComponent("source"))
        try head.write(to: backup.appendingPathComponent("original-head.txt"), atomically: true, encoding: .utf8)
        let paths = try await managedPaths()
        let destBackup = backup.appendingPathComponent("destination")
        try fm.createDirectory(at: destBackup, withIntermediateDirectories: true)
        var entries: [DestinationEntry] = []
        for (index, path) in paths.enumerated() {
            try Task.checkCancellation()
            guard path.hasPrefix(destination.path + "/") else { throw SyncError("バックアップ対象が destination の外にあります。") }
            if let attrs = try? fm.attributesOfItem(atPath: path) {
                let kind = attrs[.type] as? FileAttributeType
                guard kind == .typeRegular || kind == .typeSymbolicLink else { throw SyncError("通常ファイル以外の対象があり停止しました。") }
                let saved = "destination/\(index)"
                try fm.copyItem(at: URL(fileURLWithPath: path), to: backup.appendingPathComponent(saved))
                entries.append(DestinationEntry(path: path, saved: saved, kind: kind == .typeSymbolicLink ? "symlink" : "file", permissions: attrs[.posixPermissions] as? Int))
            } else { entries.append(DestinationEntry(path: path, saved: nil, kind: "absent", permissions: nil)) }
        }
        try JSONEncoder().encode(entries).write(to: backup.appendingPathComponent("destination.json"))
        return backup
    }

    private func verifyDestinationUnchanged(backup: URL, destination: URL) async throws {
        let entries = try JSONDecoder().decode([DestinationEntry].self, from: Data(contentsOf: backup.appendingPathComponent("destination.json")))
        for entry in entries {
            try Task.checkCancellation()
            let attrs = try? fm.attributesOfItem(atPath: entry.path)
            let kind = attrs?[.type] as? FileAttributeType
            var same = false
            if let saved = entry.saved {
                let savedURL = backup.appendingPathComponent(saved)
                if entry.kind == "symlink", kind == .typeSymbolicLink {
                    same = try fm.destinationOfSymbolicLink(atPath: entry.path) == fm.destinationOfSymbolicLink(atPath: savedURL.path)
                } else if entry.kind == "file", kind == .typeRegular {
                    same = fm.contentsEqual(atPath: entry.path, andPath: savedURL.path) && attrs?[.posixPermissions] as? Int == entry.permissions
                }
            } else { same = attrs == nil }
            guard same else { throw SyncError("同期中に Mac 側のファイルが変更されたため、適用せず停止しました。再実行してください。") }
        }
        // Newly managed paths must not overwrite an existing unmanaged local file.
        let oldPaths = Set(entries.map(\.path))
        let current = try await managedPaths()
        for path in current where !oldPaths.contains(path) {
            if (try? fm.attributesOfItem(atPath: path)) != nil { throw SyncError("リモートで追加された対象と既存の Mac ファイルが重なっています。手動で確認してください。") }
        }
    }

    private func managedPaths() async throws -> [String] {
        try await chez(["managed", "--include=files,symlinks", "--path-style=absolute", "--nul-path-separator"]).text.split(separator: "\0").map(String.init)
    }
}
