# テストと検証範囲

## 実行

```sh
brew install chezmoi
swift test --disable-sandbox
python3 -m unittest discover -s Tests/DistributionTests
```

macOS、Swift 6 対応の開発ツール、Homebrew の chezmoi が必要です。テストは `/opt/homebrew/bin/chezmoi` または `/usr/local/bin/chezmoi` を使用します。

## 隔離した環境

テストごとに一時ディレクトリへ bare Git リポジトリ、2 つの clone、専用 chezmoi 設定、destination、状態データベース、バックアップ先を作成します。通常のホーム内の dotfiles やリモートを同期しません。

API はテスト用 resolver と URLProtocol のスタブに置き換えます。API key は架空の値を使い、実際の OpenAI API 通信や課金は発生させません。

## 確認している動作

- Download がリモートの変更を適用し、push しないこと。
- Upload が Mac 側の編集を取り込み、統合した内容を送信すること。
- source だけの編集を、古い destination の内容で上書きしないこと。
- 共通祖先・ローカル・リモートが正しく resolver に渡ること。
- API 失敗、拒否、未完了、競合マーカーなどで停止すること。
- 除外パス、テンプレートの出力、ローカルの削除を保護すること。
- 同期中の再編集と、未完了 apply の再実行を保護すること。
- 同期中にリモートが更新された場合、push が拒否されること。
- 同期前チェックがファイル、HEAD、Git index、追跡 ref を変更しないこと。
- Responses API のヘッダー・Schema・`store: false` と、Luna の推論量 `low`。

2026-10-26 のローカル検証環境（Apple Silicon、Swift 6.4、chezmoi 2.72.2）で Swift の 17 件が成功しました。配布用 Python テスト 3 件では、指定した App Store Connect 変数だけを読み込むこと、`.env` のコマンドを実行しないこと、エラーに認証値を含めないことを確認しています。アプリビルド、設定画面とアイコンの表示も確認しています。GitHub Actions は Apple Silicon / Intel ランナーで実行します。最新結果はリポジトリの Actions で確認してください。

0.1.1 の Universal 配布 ZIP は、展開後の `arm64` / `x86_64`、バージョン、SHA-256、Developer ID 署名、公証チケット、Gatekeeper の受け入れを検証しました。Apple 公証は Accepted で、ZIP を作り直してチケットを同梱しています。

## 未検証・保証しない範囲

実 API key を使った OpenAI 接続と AI の統合品質、利用者の Intel 実機、macOS 14 実機での GUI 操作は検証していません。任意のユーザーの hooks / externals / scripts、設定内容の意味的な正しさ、ファイルシステム全体の原子的な巻き戻しも保証しません。

実環境では最初にアプリの同期前チェックを使い、バックアップと差分を確認してください。個別環境の実行履歴やバックアップはこのリポジトリへコミットしないでください。
