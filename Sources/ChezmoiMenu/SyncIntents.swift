import AppIntents

struct DownloadSyncIntent: AppIntent {
    static let title: LocalizedStringResource = "Download 同期"
    static let description = IntentDescription("リモートの変更を取り込み、この Mac に適用します。")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = try await AppModel.shared.perform(.download)
        return .result(dialog: "\(summary)")
    }
}

struct UploadSyncIntent: AppIntent {
    static let title: LocalizedStringResource = "Upload 同期"
    static let description = IntentDescription("ローカルとリモートを統合し、この Mac に適用してから送信します。")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = try await AppModel.shared.perform(.upload)
        return .result(dialog: "\(summary)")
    }
}

struct CheckSyncIntent: AppIntent {
    static let title: LocalizedStringResource = "同期前チェック"
    static let description = IntentDescription("接続と適用予行を確認します。commit・apply・push は実行しません。")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = try await AppModel.shared.perform(.check)
        return .result(dialog: "\(summary)")
    }
}

struct SyncShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DownloadSyncIntent(), phrases: ["\(.applicationName) で Download 同期"],
                    shortTitle: "Download 同期", systemImageName: "arrow.down.circle")
        AppShortcut(intent: UploadSyncIntent(), phrases: ["\(.applicationName) で Upload 同期"],
                    shortTitle: "Upload 同期", systemImageName: "arrow.up.circle")
        AppShortcut(intent: CheckSyncIntent(), phrases: ["\(.applicationName) で同期前チェック"],
                    shortTitle: "同期前チェック", systemImageName: "checkmark.shield")
    }
}
