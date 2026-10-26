# 使い方

## 対象となる環境

既存の chezmoi 設定から source / destination を取得します。通常、source は `~/.local/share/chezmoi`、destination は `~/` です。アプリは既に chezmoi が管理しているファイルを対象にします。未管理のファイルを自動追加しません。

同期には次の前提があります。

- `mode = "file"`。
- source が Git リポジトリのルートで、通常の `.git` ディレクトリを持つこと。
- 現在のブランチに upstream があること。
- `git user.name` / `user.email` と、無人実行できる認証・コミット署名の設定。
- chezmoi の `git.autoAdd` / `git.autoCommit` / `git.autoPush` が無効であること。
- chezmoi hooks が設定されていないこと。

設定例（chezmoi の TOML 設定）:

```toml
[git]
    autoAdd = false
    autoCommit = false
    autoPush = false
```

upstream の確認と設定例:

```sh
chezmoi source-path
chezmoi git -- status
chezmoi git -- branch -vv
# origin/main が目的のブランチである場合のみ実行する
chezmoi git -- branch --set-upstream-to=origin/main
```

worktree、submodule、detached HEAD、および進行中の merge / rebase / cherry-pick / revert / bisect は同期対象外です。同期中に別のターミナルから同じ source を編集・Git 操作しないでください。

## メニュー

### 同期前チェック

Git の接続とリモート HEAD、source の変更、Mac 側の差分、取り込み可能な変更を確認し、現在の source に対して `chezmoi apply --dry-run --force --exclude=scripts` を実行します。管理対象の件数などは実行履歴に表示します。

fetch・re-add・commit・push・実際の apply・OpenAI API 呼び出しを行いません。Git のリモート照会は行います。リモートが HEAD と異なる場合、統合後の変更までは予測しません。hooks が設定されている環境では停止します。テンプレートが外部コマンドを呼ぶ場合、その評価はテンプレートの内容に従います。

### Download

fetch → source / Mac 側のバックアップ → Mac 側で編集した通常ファイルの re-add → ローカルの変更をコミット → upstream を merge → apply の予行 → Mac 側の再編集がないか確認 → apply の順です。

Mac 側の変更は `chezmoi status` の第 1 列から判断します。source にだけ存在する未適用の編集を、古い Mac 側のファイルで置き換えないようにしています。Download はリモートへ push しませんが、ローカルコミットは作成します。

### Upload

Download と同じ手順で統合・適用したあと、現在のブランチから upstream のブランチへ通常の push を行います。source 内の未コミット変更もコミット対象です。別の Mac が先に push した場合は拒否されます。force push は行いません。

## 設定

| 項目 | 動作 |
| --- | --- |
| 実行ファイル | Homebrew などでインストールした chezmoi のパス |
| 設定ファイル | 空欄で chezmoi の既定設定。指定時は `--config` で渡す |
| API key | 新しい値を入力するとキーチェーンへ保存。空欄なら既存キーを保持 |
| モデル | Responses API / Structured Outputs に対応する利用可能なモデル名 |
| 競合を自動解決する | 有効時のみ、対応する Git テキスト競合を AI へ送る |
| AI 送信の除外パス | 大小文字を区別しない部分一致。1 行に 1 件。差分表示にも使用 |
| スクリプトも適用する | 既定は無効。有効にした場合は chezmoi のスクリプトも実行 |
| ログイン時に起動する | メニューバーへの常駐を登録。同期は開始しない |

同期とチェックは保存済み設定を使用します。「ログイン時に起動する」はその場で変更を反映します。macOS の許可が必要な場合はシステム設定のログイン項目を確認してください。

## パネル・差分・停止

メニューバーの家マークを押すと、Download / Upload、同期前チェック、処理段階、停止ボタンを表示します。進捗バーは段階の目安で、ファイル数や残り時間の割合ではありません。

設定ウインドウの「同期」にチェック結果と source / destination、「差分」に変更ファイルと現在の source との差分、「実行履歴」に直近の処理を表示します。差分は「差分を更新」で読み込みます。fetch しないため、リモートの新しい変更のプレビューではありません。暗号化・除外パスを省き、表示本文は先頭 100,000 文字までです。差分は履歴やファイルに保存しません。

停止を押すと通信や AI 待機を中断し、変更処理の途中なら完了と後処理を待ちます。「停止を待機しています…」の間はアプリを終了せず待ってください。最後の適用や送信が完了し、完了として終了する場合もあります。復旧が必要な場合は [復旧手順](RECOVERY.md) を参照してください。

## macOS ショートカット

「ショートカット」アプリで Chezmoi Menu の「Download 同期」「Upload 同期」「同期前チェック」を追加できます。Apple Intelligence の有効化は不要です。保存済み設定を使い、完了または失敗まで待って結果を返します。メニューで操作中や別のショートカットを実行中は、新しい操作を拒否します。初回はアプリを起動して設定を保存してください。

既定モデルは `gpt-6-luna` です。`gpt-6-*` / `gpt-5.6-*` の名前には `reasoning.effort = low` を指定します。利用権限や課金は OpenAI API アカウントの設定によります。

## 自動統合を止める対象

- Mac 側で直接編集した `.tmpl` の出力、削除、リンク、特殊ファイル。
- 同じファイルの source と Mac 側が両方変更されている場合。
- AI 送信の除外対象、暗号化ファイル、バイナリ、追加/削除/リンク/権限の競合など。
- 各版が 48 KB を超える競合、または UTF-8 以外の競合。
- AI 解決中や適用前に Mac 側が再編集された場合、リモートで新規管理されたパスと既存の未管理ファイルが重なる場合。

`chezmoi merge` / `chezmoi edit` などで意図する source に統合してから再実行してください。停止時の詳細は [復旧手順](RECOVERY.md) を参照してください。

参考: [chezmoi Daily operations](https://www.chezmoi.io/user-guide/daily-operations/) / [re-add](https://www.chezmoi.io/reference/commands/re-add/)。
