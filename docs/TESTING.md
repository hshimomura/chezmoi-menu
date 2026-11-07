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

暗号化 `.env` のテストでは `chezmoi age-keygen` で使い捨ての鍵を Git の外に生成します。実際の age 暗号化・復号を使い、ユーザーの秘密鍵や `.env` は読み込みません。

API はテスト用 resolver と URLProtocol のスタブに置き換えます。API key は架空の値を使い、実際の OpenAI API 通信や課金は発生させません。

## 確認している動作

- Download がリモートの変更を適用し、push しないこと。
- Upload が Mac 側の編集を取り込み、統合した内容を送信すること。
- age で暗号化した `~/.env` の直接編集を Upload し、独立した source / destination / 状態データベースで Download・復号して権限 `600` で配置できること。Git に入るのは暗号化ファイルだけであること。
- 暗号化 `.env` の source 編集を古い destination で置き換えず適用・送信すること。除外設定が空でも暗号化ファイルの競合を AI に送らず、差分表示では名前のみ取得すること。秘密鍵がない場合はチェックが失敗し、ファイルを変更しないこと。
- source の未コミット変更をコミットすると upstream との差分へ移り、apply・push を行わず、バックアップを保存すること。その後の Upload で適用・送信できること。
- source の stage 済み・未 stage・未追跡ファイルと特殊文字を含むパスを扱い、外部 diff driver / textconv を実行しないこと。upstream 未設定、空メッセージ、変更なし、未完了 apply を扱うこと。
- 複数ファイルの変更・追加・削除・名前変更と暗号化 `.env`・除外パスが混在しても、全件を一覧表示してまとめてコミットできること。Mac 側の複数ファイルもまとめてプレビュー・Upload できること。本文が 100,000 文字で打ち切られても、全ファイル名とコミット対象を保持すること。
- source だけの編集を、古い destination の内容で上書きしないこと。
- 競合する暗号化ファイルのローカル／リモート採用、複数ファイルごとに異なる版の採用、削除版の採用、通常の AI 競合解決との混在を扱うこと。
- 版の選択待ちの停止で merge を中止し、採用版の未選択・source / ホーム側の編集・外部 Git index の変更を保護すること。
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
- 差分が読み取り専用で、暗号化・除外対象の名前を表示し、内容は表示しないこと。対象がすべて除外された場合も全体 diff にフォールバックしないこと。

2026-10-26 のローカル検証環境は macOS 27.0.1 / Apple Silicon、Xcode 27.1 / Swift 6.4、chezmoi 2.72.2 です。Swift 25 件と配布用 Python 3 件が成功しました。Python テストでは、指定した App Store Connect 変数だけを読み込むこと、`.env` のコマンドを実行しないこと、エラーに認証値を含めないことを確認します。設定画面の表示、既存の保存済みモデルの引き継ぎ、実環境の読み取り専用チェック・差分更新も確認しました。GitHub Actions は `xcode-27` の arm64 ランナーで実行します。最新結果はリポジトリの Actions で確認してください。

2026-11-07 に macOS 27.2 / Apple Silicon / Swift 6.4 / chezmoi 2.72.2 で Swift 35 件と配布用 Python 3 件が成功しました。暗号化 `.env` の端末間同期と source の差分・コミット操作を追加で検証しています。

同日、複数ファイル用の統合テスト 3 件を追加し、`swift test --disable-sandbox --filter 'SyncEngineTests.testMultiple'` で全件成功しました。実際の Git / chezmoi と隔離したローカルリモートで検証し、ユーザーの dotfiles は変更していません。

0.3.0 のバージョン更新後に全体を再実行し、Swift 38 件・配布用 Python 3 件が成功しました。GUI の未コミット変更の確認・コミット・差分表示は利用者による動作確認済みです。

0.4.0 の公開前に全体を再実行し、Swift 49 件・配布用 Python 3 件が成功しました。暗号化ファイルのローカル／リモート採用、複数ファイルの選択・再編集、中止時の保護、外部 Git index の変更を含みます。競合選択画面は利用者による実環境での動作確認済みで、GUI の対話操作自体は自動検証していません。

配布時は展開後の arm64、最低 OS 27.0、バージョン、SHA-256、Developer ID 署名、公証チケット、Gatekeeper の受け入れを確認します。App Intents メタデータ、Icon Composer の Assets.car、第三者ライセンスの同梱も確認します。署名用・公証用の認証情報は CI や配布物に含めません。

## 未検証・保証しない範囲

実 API key を使った OpenAI 接続と AI の統合品質は検証していません。実際の dotfiles に対する書き込みを伴う同期・ショートカットの実行は自動検証しません。Intel / macOS 26 以前は対象外です。任意のユーザーの Git hooks / externals / scripts、設定内容の意味的な正しさ、ファイルシステム全体の原子的な巻き戻しも保証しません。

実環境では最初にアプリの同期前チェックを使い、バックアップと差分を確認してください。個別環境の実行履歴やバックアップはこのリポジトリへコミットしないでください。
