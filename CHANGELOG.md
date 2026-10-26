# 変更履歴

## 0.2.0 — 2026-10-26

- macOS 27 / Apple Silicon 専用。Xcode 27.1・Swift 6.4・Swift 6 言語モードへ移行。
- Swift Subprocess、SyncEngine actor、Observation による非同期処理と状態管理。
- 安全な区切りでの停止、キャンセル後の merge 後処理、統合前からの未適用記録。
- SwiftUI MenuBarExtra パネル、進捗、変更ファイルと差分、サイドバー付き設定画面。
- Download / Upload / 同期前チェックの App Intents とショートカット。
- 明暗に対応するレイヤー付き Icon Composer アイコン。
- Apple Intelligence は使用せず、既存の OpenAI 設定・Keychain を保持。
- arm64 ZIP 配布と macOS 27 の CI。Intel / macOS 26 以前の対応を終了。

## 0.1.1 — 2026-10-26

- Apple Silicon / Intel に対応する Universal ビルドと ZIP 配布。
- Developer ID 署名・Apple 公証・公証チケット添付の配布手順。
- 別の Mac へのインストール手順と SHA-256 チェックサム。
- App Store Connect 認証情報を限定して読み込むスクリプトとテスト。
- Apple Silicon / Intel の CI 検証。

## 0.1.0 — 2026-10-26

- macOS のメニューバーから Download / Upload 同期を実行。
- Git の 3-way テキスト競合を OpenAI Responses API で統合。
- キーチェーンへの API key 保存、送信除外パス、低い推論量の Luna モデル設定。
- 適用・push・AI 通信を行わない同期前チェック。
- 同期前バックアップ、未完了 apply の保護、実行履歴、ログイン時起動。
- chezmoi ロゴを基にした macOS 用アプリアイコンと単色メニューバー表示。
- MIT ライセンスと upstream ロゴの帰属表示。
