import AppKit
import Observation
import ServiceManagement
import ChezmoiCore

enum AppOperation: Sendable { case download, upload, check, preview }

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview = "同期", diff = "差分", general = "一般", ai = "OpenAI", history = "実行履歴"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .overview: "arrow.triangle.2.circlepath"
        case .diff: "doc.text.magnifyingglass"
        case .general: "gearshape"
        case .ai: "sparkles"
        case .history: "clock"
        }
    }
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    var settings: SyncSettings
    var apiKey = ""
    private(set) var running = false
    private(set) var stopping = false
    private(set) var status = "同期を開始できます"
    private(set) var phase: SyncPhase = .preparing
    private(set) var history: [String] = []
    private(set) var preview: DiffPreview?
    private(set) var checkReport: SyncCheckReport?
    private(set) var lastBackup: URL?
    var notice = ""
    var section: SettingsSection = .overview
    var windowRequest = 0
    var loginEnabled = SMAppService.mainApp.status == .enabled
    let support: URL
    var backups: URL { support.appendingPathComponent("Backups") }
    private var settingsURL: URL { support.appendingPathComponent("settings.json") }
    private var historyURL: URL { support.appendingPathComponent("history.json") }
    @ObservationIgnored private var operationTask: Task<String, Error>?
    @ObservationIgnored private var activeID: UUID?

    init() {
        support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ChezmoiMenu")
        settings = (try? JSONDecoder().decode(SyncSettings.self, from: Data(contentsOf: support.appendingPathComponent("settings.json")))) ?? SyncSettings()
        history = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: support.appendingPathComponent("history.json")))) ?? []
        // Read the key only when resolving a conflict; startup never prompts for Keychain access.
    }

    func show(_ section: SettingsSection = .overview) { self.section = section; windowRequest += 1 }

    func save() {
        do {
            guard FileManager.default.isExecutableFile(atPath: NSString(string: settings.chezmoiPath).expandingTildeInPath) else { throw SyncError("chezmoi 実行ファイルのパスを確認してください。") }
            guard !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SyncError("モデル名を入力してください。") }
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let newKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newKey.isEmpty { try Keychain.save(newKey) }
            try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
            apiKey = ""
            notice = "設定を保存しました。API key はこの Mac のキーチェーンに保存します。"
        } catch { notice = error.localizedDescription }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                notice = "システム設定 → 一般 → ログイン項目で許可してください。"
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { notice = "ログイン時起動を変更できません: \(error.localizedDescription)" }
    }

    func start(_ operation: AppOperation) {
        do { _ = try begin(operation) } catch { notice = error.localizedDescription }
    }

    // Menu, window, and Shortcuts share one coordinator and busy guard.
    func perform(_ operation: AppOperation) async throws -> String {
        let task = try begin(operation)
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func cancel() {
        guard running, !stopping else { return }
        stopping = true
        operationTask?.cancel()
        record("停止を要求しました。変更処理は完了を待ってから停止します。")
    }

    private func begin(_ operation: AppOperation) throws -> Task<String, Error> {
        guard !running else { throw SyncError("別の操作を実行しています。完了を待ってください。") }
        let saved = (try? JSONDecoder().decode(SyncSettings.self, from: Data(contentsOf: settingsURL))) ?? settings
        let id = UUID()
        activeID = id
        running = true; stopping = false; notice = ""; phase = .preparing
        status = "準備しています…"
        if operation != .preview { preview = nil; checkReport = nil }
        let engine = SyncEngine(settings: saved, backups: backups, resolver: KeychainResolver(model: saved.model),
                                onEvent: { [weak self] event in
            Task { @MainActor in
                guard let self, self.activeID == id else { return }
                self.phase = event.phase; self.status = event.message
                self.record(event.message)
            }
        })
        let task = Task<String, Error> { [self] in
            defer { running = false; stopping = false; activeID = nil; operationTask = nil }
            do {
                switch operation {
                case .download, .upload:
                    let result = try await engine.sync(operation == .download ? .download : .upload)
                    lastBackup = result.backup
                    record("バックアップ: \(result.backup.lastPathComponent)")
                    status = "\(operation == .download ? "Download" : "Upload") 完了 · AI 解決 \(result.resolvedCount) 件"
                case .check:
                    let result = try await engine.check()
                    checkReport = result
                    record("管理対象 \(result.managedCount) 件 / source の変更 \(result.sourceChanges) 件 / Mac との差分 \(result.destinationChanges) 件 / 取り込み対象 \(result.localCaptures) 件")
                    record(result.remoteMatches ? "リモートと HEAD は一致しています。" : "リモートと HEAD が異なります。同期で統合が必要です。")
                    status = "チェック完了 · 差分 \(result.destinationChanges) 件"
                    notice = "接続確認・適用予行に成功しました。"
                case .preview:
                    preview = nil
                    let result = try await engine.preview()
                    preview = result
                    status = "差分の確認完了 · 表示対象 \(result.files.count) 件"
                }
                phase = .finished
                record(status)
                return status
            } catch {
                status = "操作を停止しました"
                notice = error is CancellationError
                    ? "停止しました。変更済みの内容は自動で巻き戻しません。履歴とバックアップを確認してください。"
                    : error.localizedDescription
                record(notice)
                throw error
            }
        }
        operationTask = task
        return task
    }

    private func record(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        history.append("\(time)  \(message)")
        history = Array(history.suffix(300))
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
    }

    func openBackups() {
        try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(lastBackup ?? backups)
    }
}
