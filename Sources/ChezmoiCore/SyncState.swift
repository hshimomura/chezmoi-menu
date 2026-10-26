import Foundation

public enum SyncPhase: String, Sendable, Codable {
    case preparing, checking, fetching, backingUp, capturing, merging, resolving, validating, applying, pushing, previewing, cleaningUp, finished

    public var title: String {
        switch self {
        case .preparing: "準備"
        case .checking: "チェック"
        case .fetching: "取得"
        case .backingUp: "バックアップ"
        case .capturing: "変更の取り込み"
        case .merging: "統合"
        case .resolving: "AI 競合解決"
        case .validating: "検証"
        case .applying: "適用"
        case .pushing: "送信"
        case .previewing: "差分の確認"
        case .cleaningUp: "後処理"
        case .finished: "完了"
        }
    }

    public var progress: Double {
        switch self {
        case .preparing: 0.03
        case .checking, .previewing: 0.12
        case .fetching: 0.18
        case .backingUp: 0.28
        case .capturing: 0.38
        case .merging: 0.48
        case .resolving: 0.6
        case .validating: 0.74
        case .applying: 0.86
        case .pushing: 0.94
        case .cleaningUp: 0.95
        case .finished: 1
        }
    }
}

public struct SyncEvent: Sendable {
    public let phase: SyncPhase
    public let message: String
}

public struct DiffPreview: Sendable {
    public let files: [String]
    public let omittedCount: Int
    public let text: String
    public let truncated: Bool
}
