import Foundation

public struct SyncError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct CommandResult {
    public let code: Int32
    public let data: Data
    public let error: String
    public var text: String { String(data: data, encoding: .utf8) ?? "" }
}

public struct Command {
    public init() {}

    // Files avoid a pipe-buffer deadlock when Git or chezmoi emits a large diff.
    @discardableResult
    public func run(_ executable: String, _ arguments: [String], directory: URL? = nil,
                    timeout: TimeInterval = 120, allowFailure: Bool = false) throws -> CommandResult {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temp) }
        let outURL = temp.appendingPathComponent("stdout")
        let errURL = temp.appendingPathComponent("stderr")
        fm.createFile(atPath: outURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        fm.createFile(atPath: errURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let out = try FileHandle(forWritingTo: outURL)
        let err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_EDITOR"] = "/usr/bin/true"
        environment["GIT_MERGE_AUTOEDIT"] = "no"
        environment["GIT_PAGER"] = "cat"
        environment["SSH_ASKPASS_REQUIRE"] = "never"
        environment["GIT_SSH_COMMAND"] = "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=15"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let end = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw SyncError("コマンドがタイムアウトしました（\(URL(fileURLWithPath: executable).lastPathComponent)）。状態を確認して再実行してください。")
        }
        process.waitUntilExit()
        let result = CommandResult(code: process.terminationStatus,
                                   data: try Data(contentsOf: outURL),
                                   error: (try? String(contentsOf: errURL, encoding: .utf8)) ?? "")
        if result.code != 0 && !allowFailure {
            // Command output may contain credentials, diff content, or remote URLs.
            throw SyncError("\(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.first ?? "") が失敗しました（終了コード \(result.code)）。Git 認証・設定とリポジトリの状態を確認してください。")
        }
        return result
    }
}
