import Foundation
import Subprocess
import System

public struct SyncError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct CommandResult: Sendable {
    public let code: Int32
    public let data: Data
    public let error: String
    public var text: String { String(data: data, encoding: .utf8) ?? "" }
}

public struct Command: Sendable {
    public init() {}

    // Keep Subprocess's internal task groups independent of the caller's cancellation.
    // This task is owned here and ALWAYS joined; it cannot outlive the operation.
    @discardableResult
    public func runToCompletion(_ executable: String, _ arguments: [String], directory: URL? = nil,
                                timeout: TimeInterval = 120, allowFailure: Bool = false) async throws -> CommandResult {
        try await withTaskCancellationShield {
            let task = Task {
                try await run(executable, arguments, directory: directory, timeout: timeout, allowFailure: allowFailure)
            }
            return try await task.value
        }
    }

    @discardableResult
    public func run(_ executable: String, _ arguments: [String], directory: URL? = nil,
                    timeout: TimeInterval = 120, allowFailure: Bool = false) async throws -> CommandResult {
        try Task.checkCancellation()
        var options = PlatformOptions()
        options.createSession = true
        options.teardownSequence = [
            // Non-interactive shell children may inherit SIGINT ignored. SIGTERM reaches them too.
            .send(signal: .terminate, toProcessGroup: true, allowedDurationToNextStep: .seconds(1)),
            .send(signal: .kill, toProcessGroup: true, allowedDurationToNextStep: .zero)
        ]
        let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "")
        let config = Configuration(
            executable: .path(FilePath(executable)), arguments: Arguments(arguments),
            environment: .inherit.updating([
                "PATH": path, "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0",
                "GIT_EDITOR": "/usr/bin/true", "GIT_MERGE_AUTOEDIT": "no", "GIT_PAGER": "cat",
                "SSH_ASKPASS_REQUIRE": "never",
                "GIT_SSH_COMMAND": "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=15"
            ]), workingDirectory: directory.map { FilePath($0.path) }, platformOptions: options
        )
        do {
            return try await withThrowingTaskGroup(of: CommandResult.self) { group in
                group.addTask {
                    let result = try await Subprocess.run(config, input: .none,
                        output: .data(limit: 16 * 1024 * 1024), error: .data(limit: 1024 * 1024))
                    try Task.checkCancellation()
                    let code: Int32
                    switch result.terminationStatus {
                    case .exited(let value): code = value
                    case .signaled(let signal): code = 128 + signal
                    }
                    let value = CommandResult(code: code, data: result.standardOutput,
                                              error: String(decoding: result.standardError, as: UTF8.self))
                    if code != 0 && !allowFailure {
                        let known = ["fetch", "merge", "commit", "push", "apply", "status", "diff", "re-add"]
                        let operation = arguments.first.flatMap { known.contains($0) ? $0 : nil } ?? "command"
                        throw SyncError("\(operation) が失敗しました（終了コード \(code)）。認証・設定とリポジトリの状態を確認してください。")
                    }
                    return value
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw SyncError("コマンドがタイムアウトしました。状態を確認して再実行してください。")
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw CancellationError() }
                return result
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if error is SyncError { throw error }
            // Never expose raw subprocess errors, arguments, stderr or file contents to history.
            throw SyncError("コマンドを実行できませんでした。実行ファイル・権限・出力量を確認してください。")
        }
    }
}
