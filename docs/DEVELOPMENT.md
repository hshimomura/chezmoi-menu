# 開発

## 構成

| パス | 役割 |
| --- | --- |
| `Sources/ChezmoiCore/Command.swift` | Swift Subprocess による非同期実行、プロセスグループ、タイムアウト |
| `Sources/ChezmoiCore/SyncEngine.swift` | 同期前チェック、バックアップ、Git 統合、適用と push |
| `Sources/ChezmoiCore/OpenAIResolver.swift` | Responses API、JSON Schema、応答検証 |
| `Sources/ChezmoiMenu/` | SwiftUI MenuBarExtra、Observation、App Intents、設定、キーチェーン |
| `Tests/ChezmoiCoreTests/` | 一時環境の Git / chezmoi 統合テストと API モック |
| `Assets/` | Icon Composer のレイヤー、PNG / ICNS フォールバック、元画像 |
| `scripts/` | ローカル用 `.app` とアイコンの生成 |

macOS 27、Apple Silicon、Xcode 27.1 以降が必要です。Swift tools version は 6.4、言語モードは Swift 6 です。SyncEngine actor と @MainActor の @Observable モデルで状態を分離します。actor の再入可能性を考慮した busy guard と Git ディレクトリ内のファイルロックで重複同期を防ぎます。ターミナルなど別の Git クライアントとの排他は保証しません。[設計](ARCHITECTURE.md) も参照してください。

Swift Subprocess 1.0.2 とその依存 Swift System 1.8.1 を使用し、`Package.resolved` をコミットします。更新時は `LICENSES/` の同梱ライセンスも確認してください。

## ビルドと検証

```sh
brew install chezmoi
swift test --disable-sandbox
bash -n scripts/*.sh
python3 -m unittest discover -s Tests/DistributionTests
bash scripts/build-app.sh
codesign --verify --strict "dist/Chezmoi Menu.app"
open "dist/Chezmoi Menu.app"
```

`--disable-sandbox` は制限付き環境で SwiftPM の二重 sandbox を避けるための指定です。chezmoi など実行する外部ツール自体の検証を省略する指定ではありません。

ビルドスクリプトは arm64 の release バイナリを作り、アイコン・App Intents メタデータ・ライセンス表示を `.app/Contents/Resources` へ同梱します。`dist/` と `.build/` は Git 管理しません。インストール済みアプリを更新するときは、同期を完了してアプリを終了してからコピーしてください。

## アイコン

`Assets/AppIcon.icon` が正本です。`bash scripts/build-icons.sh` は Xcode 27.1 の Icon Composer `ictool` で PNG を生成し、`iconutil` で ICNS を生成します。アプリ構築時は `actool` で明暗のレイヤーを `Assets.car` にコンパイルします。グラフィックスサービスの利用を制限する実行環境では、通常の macOS ターミナルからビルドしてください。

## テストと CI

[テストの説明](TESTING.md) を参照してください。GitHub Actions は `xcode-27` ランナー（macOS 27 / arm64）でテストとアプリビルドを実行します。OpenAI API key やユーザーの dotfiles、署名・公証の認証情報は不要です。CI のビルドは ad-hoc 署名です。

## 配布

`VERSION` がバージョンの正本です。通常ビルドは ad-hoc 署名ですが、`CHEZMOI_MENU_SIGN_IDENTITY` にローカルの Developer ID Application 証明書名またはハッシュを指定すると Hardened Runtime と secure timestamp を有効にして署名します。個人の署名情報はソースへ書き込みません。

```sh
# 署名済み arm64 ZIP とチェックサムを生成
CHEZMOI_MENU_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
  bash scripts/package-release.sh --notarize
```

公証スクリプトは `~/.env` の `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_FILEPATH` だけを読みます。環境変数で渡すこともできます。環境変数とファイルの両方に値がある場合はファイルの値を優先します。`ASC_KEY_FILEPATH` は App Store Connect API の秘密鍵 `.p8` を指します。チームキーは issuer を指定し、個人キーの場合は issuer を空欄にします。`.env` をシェルで source せず、指定外の変数やコマンドは実行しません。

Apple へ ZIP を提出し、承認後にチケットを staple / validate してから ZIP を作り直します。最終 ZIP と `.sha256` が公開対象です。`dist/notarization.json` などのローカル結果と、認証情報・秘密鍵は公開しません。処理が長い場合は、表示された提出 ID と `scripts/notarize-app.py --resume` で再開できます。再開時も承認後に ZIP を作り直し、チェックサムを更新してから配布してください。

`--notarize` を省略すると、署名後の ZIP だけを生成します。そのアーカイブを公証済みと表示してはいけません。Developer ID 署名・Apple 公証の完了、arm64 と最低 OS 27.0 の検証後、GitHub Release に ZIP とチェックサムを公開します。ロゴの帰属を含む `LICENSE`、`THIRD_PARTY_NOTICES.md`、依存パッケージの `LICENSES/` をアプリへ同梱します。
