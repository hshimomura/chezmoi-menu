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
bash -n scripts/build-app.sh scripts/build-icons.sh scripts/package-release.sh
python3 -m unittest discover -s Tests/DistributionTests
bash scripts/build-app.sh
codesign --verify --strict "dist/Chezmoi Menu.app"
open "dist/Chezmoi Menu.app"
```

`--disable-sandbox` は制限付き環境で SwiftPM の二重 sandbox を避けるための指定です。chezmoi など実行する外部ツール自体の検証を省略する指定ではありません。

ビルドスクリプトは実行する Mac 向けの release バイナリを作り、アイコンとライセンス表示を `.app/Contents/Resources` へ同梱します。`dist/` と `.build/` は Git 管理しません。インストール済みアプリを更新するときは、同期を完了してアプリを終了してからコピーしてください。

## アイコン

`bash scripts/build-icons.sh` で元画像から標準サイズの iconset を生成し、`iconutil` で ICNS に変換します。変換済み素材が新しければ再利用します。中間ファイルは `.build/AppIcon.iconset/` です。制限付き実行環境で `iconutil` が失敗する場合は、通常の macOS ターミナルから実行してください。

## テストと CI

[テストの説明](TESTING.md) を参照してください。GitHub Actions は macOS の Apple Silicon / Intel ランナーで chezmoi を用意し、テストと Universal アプリビルドを実行します。OpenAI API key やユーザーの dotfiles、署名・公証の認証情報は必要ありません。CI のビルドは ad-hoc 署名です。

## 配布

`VERSION` がバージョンの正本です。通常ビルドは ad-hoc 署名ですが、`CHEZMOI_MENU_SIGN_IDENTITY` にローカルの Developer ID Application 証明書名またはハッシュを指定すると Hardened Runtime と secure timestamp を有効にして署名します。個人の署名情報はソースへ書き込みません。

```sh
# 署名済み Universal ZIP とチェックサムを生成
CHEZMOI_MENU_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
  bash scripts/package-release.sh --notarize
```

公証スクリプトは `~/.env` の `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_FILEPATH` だけを読みます。環境変数で渡すこともできます。環境変数とファイルの両方に値がある場合はファイルの値を優先します。`ASC_KEY_FILEPATH` は App Store Connect API の秘密鍵 `.p8` を指します。チームキーは issuer を指定し、個人キーの場合は issuer を空欄にします。`.env` をシェルで source せず、指定外の変数やコマンドは実行しません。

Apple へ ZIP を提出し、承認後にチケットを staple / validate してから ZIP を作り直します。最終 ZIP と `.sha256` が公開対象です。`dist/notarization.json` などのローカル結果と、認証情報・秘密鍵は公開しません。処理が長い場合は、表示された提出 ID と `scripts/notarize-app.py --resume` で再開できます。再開時も承認後に ZIP を作り直し、チェックサムを更新してから配布してください。

`--notarize` を省略すると、署名後の ZIP だけを生成します。そのアーカイブを公証済みと表示してはいけません。Developer ID 署名・Apple 公証の完了と両アーキテクチャの検証後、GitHub Release に ZIP とチェックサムを公開します。ロゴの帰属を含む `LICENSE` と `THIRD_PARTY_NOTICES.md` をアプリへ同梱します。
