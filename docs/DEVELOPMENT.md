# 開発

## 構成

| パス | 役割 |
| --- | --- |
| `Sources/ChezmoiCore/Command.swift` | 対話なしのプロセス実行、タイムアウト、一時出力 |
| `Sources/ChezmoiCore/SyncEngine.swift` | 同期前チェック、バックアップ、Git 統合、適用と push |
| `Sources/ChezmoiCore/OpenAIResolver.swift` | Responses API、JSON Schema、応答検証 |
| `Sources/ChezmoiMenu/` | AppKit / SwiftUI、設定、実行履歴、キーチェーン、アイコン |
| `Tests/ChezmoiCoreTests/` | 一時環境の Git / chezmoi 統合テストと API モック |
| `Assets/` | アイコンの元画像、PNG、ICNS、生成方法 |
| `scripts/` | ローカル用 `.app` とアイコンの生成 |

Swift tools version は 6.0、コンパイラの言語モードは Swift 5 です。同期処理は UI の外で実行し、同じ source へのアプリ同士の同期は Git ディレクトリ内のファイルロックで排他します。ターミナルなど別の Git クライアントとの排他は保証しません。

## ビルドと検証

```sh
brew install chezmoi
swift test --disable-sandbox
bash -n scripts/build-app.sh scripts/build-icons.sh
bash scripts/build-app.sh
codesign --verify --strict "dist/Chezmoi Menu.app"
open "dist/Chezmoi Menu.app"
```

`--disable-sandbox` は制限付き環境で SwiftPM の二重 sandbox を避けるための指定です。chezmoi など実行する外部ツール自体の検証を省略する指定ではありません。

ビルドスクリプトは実行する Mac 向けの release バイナリを作り、アイコンとライセンス表示を `.app/Contents/Resources` へ同梱します。`dist/` と `.build/` は Git 管理しません。インストール済みアプリを更新するときは、同期を完了してアプリを終了してからコピーしてください。

## アイコン

`bash scripts/build-icons.sh` で元画像から標準サイズの iconset を生成し、`iconutil` で ICNS に変換します。変換済み素材が新しければ再利用します。中間ファイルは `.build/AppIcon.iconset/` です。制限付き実行環境で `iconutil` が失敗する場合は、通常の macOS ターミナルから実行してください。

## テストと CI

[テストの説明](TESTING.md) を参照してください。GitHub Actions は macOS 上で chezmoi を用意し、テストとアプリビルドを実行します。OpenAI API key やユーザーの dotfiles は必要ありません。

## 配布

現在のビルドはローカル用の ad-hoc 署名です。第三者向けバイナリ配布には Developer ID 署名、notarization、配布アーキテクチャなどの設計が別途必要です。ロゴの帰属を含む `LICENSE` と `THIRD_PARTY_NOTICES.md` を保持してください。
