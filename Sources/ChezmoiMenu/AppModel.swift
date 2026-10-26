import AppKit
import Combine
import ServiceManagement
import ChezmoiCore

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: SyncSettings
    @Published var apiKey = ""
    @Published var running = false
    @Published var status = "同期を開始できます"
    @Published var history: [String] = []
    @Published var notice = ""
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    let support: URL
    var backups: URL { support.appendingPathComponent("Backups") }
    private var settingsURL: URL { support.appendingPathComponent("settings.json") }
    private var historyURL: URL { support.appendingPathComponent("history.json") }

    init() {
        support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ChezmoiMenu")
        let settingsFile = support.appendingPathComponent("settings.json")
        settings = (try? JSONDecoder().decode(SyncSettings.self, from: Data(contentsOf: settingsFile))) ?? SyncSettings()
        if !FileManager.default.isExecutableFile(atPath: settings.chezmoiPath), FileManager.default.isExecutableFile(atPath: "/usr/local/bin/chezmoi") {
            settings.chezmoiPath = "/usr/local/bin/chezmoi"
        }
        history = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: support.appendingPathComponent("history.json")))) ?? []
    }

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
            notice = "設定を保存しました。API key はこの Mac のキーチェーンに保存されています。"
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

    func start(_ direction: SyncDirection) {
        guard !running else { return }
        // Read persisted values, so unfinished edits in Settings never affect a sync.
        let saved = (try? JSONDecoder().decode(SyncSettings.self, from: Data(contentsOf: settingsURL))) ?? settings
        running = true
        status = direction == .download ? "Download を開始しています…" : "Upload を開始しています…"
        record(status)
        let engine = SyncEngine(settings: saved, backups: backups,
                                resolver: KeychainResolver(model: saved.model)) { [weak self] message in
            Task { @MainActor in self?.status = message; self?.record(message) }
        }
        Task {
            do {
                let report = try await Task.detached { try await engine.sync(direction) }.value
                status = "\(direction == .download ? "Download" : "Upload") 完了 · AI 解決 \(report.resolvedCount) 件"
                record(status)
                record("バックアップ: \(report.backup.lastPathComponent)")
            } catch {
                status = "同期を停止しました"
                record(error.localizedDescription)
                notice = error.localizedDescription
            }
            running = false
        }
    }

    func check() {
        guard !running else { return }
        let saved = (try? JSONDecoder().decode(SyncSettings.self, from: Data(contentsOf: settingsURL))) ?? settings
        running = true
        notice = ""
        status = "同期前チェックを開始しています…"
        let engine = SyncEngine(settings: saved, backups: backups, resolver: nil) { [weak self] message in
            Task { @MainActor in self?.status = message; self?.record(message) }
        }
        Task {
            do {
                let report = try await Task.detached { try engine.check() }.value
                record("対象: \(report.destination) / source: \(report.source)")
                record("管理対象 \(report.managedCount) 件 / source の変更 \(report.sourceChanges) 件 / Mac との差分 \(report.destinationChanges) 件 / 取り込み対象 \(report.localCaptures) 件")
                record(report.remoteMatches ? "リモートと HEAD は一致しています。" : "リモートと HEAD は異なります。Download / Upload で統合が必要です。")
                status = "チェック完了 · 管理対象 \(report.managedCount) 件 / 差分 \(report.destinationChanges) 件"
                notice = "適用予行に成功しました。commit・push・ファイル適用・OpenAI API 通信は行っていません。詳細は実行履歴を確認してください。"
                record(status)
            } catch {
                status = "同期前チェックを停止しました"
                notice = error.localizedDescription
                record(notice)
            }
            running = false
        }
    }

    func record(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        history.append("\(time)  \(message)")
        history = Array(history.suffix(300))
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
    }

    func openBackups() {
        try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(backups)
    }
}
