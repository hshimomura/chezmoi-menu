# テストと検証範囲

## 実行

```sh
brew install chezmoi
swift test --disable-sandbox
python3 -m unittest discover -s Tests/DistributionTests
```

macOS 27、Apple Silicon、Xcode 27.1 以降、Homebrew の chezmoi が必要です。テストは `/opt/homebrew/bin/chezmoi` または `/usr/local/bin/chezmoi` を使用します。

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
- コマンドのキャンセル・タイムアウトと子プロセスグループの終了。
- 変更コマンドの完了待ち、apply 実行中の停止で適用が途中終了しないこと。
- AI 待機中の停止後に merge を中止し、取り込み済みコミットを残すこと。
- 統合直後の停止でも未適用記録を残し、古い home の再取り込みを拒否すること。
- actor の await 中に同じエンジンへ並行操作を追加できないこと。
- 差分が読み取り専用で、除外対象を表示しないこと。対象がすべて除外された場合も全体 diff にフォールバックしないこと。

2026-10-26 のローカル検証環境は macOS 27.0.1 / Apple Silicon、Xcode 27.1 / Swift 6.4、chezmoi 2.72.2 です。Swift 25 件と配布用 Python 3 件が成功しました。Python テストでは、指定した App Store Connect 変数だけを読み込むこと、`.env` のコマンドを実行しないこと、エラーに認証値を含めないことを確認します。設定画面の表示、既存の保存済みモデルの引き継ぎ、実環境の読み取り専用チェック・差分更新も確認しました。GitHub Actions は `xcode-27` の arm64 ランナーで実行します。最新結果はリポジトリの Actions で確認してください。

配布時は展開後の arm64、最低 OS 27.0、バージョン、SHA-256、Developer ID 署名、公証チケット、Gatekeeper の受け入れを確認します。App Intents メタデータ、Icon Composer の Assets.car、第三者ライセンスの同梱も確認します。署名用・公証用の認証情報は CI や配布物に含めません。

## 未検証・保証しない範囲

実 API key を使った OpenAI 接続と AI の統合品質は検証していません。実際の dotfiles に対する書き込みを伴う同期・ショートカットの実行は自動検証しません。Intel / macOS 26 以前は対象外です。任意のユーザーの Git hooks / externals / scripts、設定内容の意味的な正しさ、ファイルシステム全体の原子的な巻き戻しも保証しません。

実環境では最初にアプリの同期前チェックを使い、バックアップと差分を確認してください。個別環境の実行履歴やバックアップはこのリポジトリへコミットしないでください。
