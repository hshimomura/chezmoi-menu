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

### 暗号化した `~/.env` の共有

chezmoi で `encrypted_private_dot_env.age` として管理している `~/.env` も同期対象です。直接編集した `~/.env` は Upload 時の `re-add` で暗号化属性を保持して取り込みます。`chezmoi edit ~/.env` で source に保存した変更も Upload できます。受信する Mac では Download により復号され、`~/.env` に配置されます。AI 送信・差分表示の除外設定は、この通常の同期を除外する設定ではありません。

各 Mac に同じ age 秘密鍵を復元し、アプリが使う chezmoi 設定に次を指定してください。アプリは鍵の配布や暗号化設定の作成を行いません。

```toml
# encryption は [age] や [git] より前のトップレベルに指定する
encryption = "age"

[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "age1..." # 自分の鍵の公開鍵に置き換える
```

共有できない場合は、次の順に確認します。秘密鍵や `.env` の内容を不具合報告に貼り付けないでください。

1. 送信元で Upload、受信先で Download を実行したか。Download だけでは送信しません。
2. 各 Mac の設定画面で、意図する chezmoi 設定ファイルを使っているか。`chezmoi source-path ~/.env` で暗号化した source が返るか、`chezmoi status ~/.env` に未適用の変更がないか確認します。設定ファイルを指定している場合は、CLI にも同じ `--config` を渡します。
3. 各 Mac に `~/.config/chezmoi/key.txt` があり、`encryption`・`identity`・`recipient` が設定されているか。鍵ファイルの権限は `600` にします。
4. アプリの履歴に競合や失敗がないか。暗号化ファイルが競合した場合は AI に送信せず停止するため、source を手動で解決してから再実行します。
5. ファイルが更新された後、利用するシェルを再読み込みしたか。`.zshrc` / `.bashrc` が `~/.env` を読み込む構成なら `exec zsh` / `exec bash` で反映します。起動済みアプリの環境変数は同期だけでは更新されません。

参考: [chezmoi の age 設定](https://www.chezmoi.io/user-guide/encryption/age/) / [暗号化属性を保持する re-add](https://www.chezmoi.io/reference/commands/re-add/)。

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

設定ウインドウの「同期」にチェック結果と source / destination、「実行履歴」に直近の処理を表示します。「差分」では次の比較を切り替えます。

| 比較対象 | 表示する変更 |
| --- | --- |
| 未コミット | source と HEAD の差分。ステージ済み・未ステージ・Git 未追跡ファイルを含む、コミット後に残る最終的な変更 |
| コミット済み ↔ upstream | 取得済みの upstream と HEAD の差分と、先行・遅延コミット数 |
| Mac ↔ source | 現在の Mac のファイルと source の差分 |

「差分を更新」で再読み込みします。fetch は行わないため、upstream は最後に取得した状態です。暗号化・除外パスも変更ファイルの名前を表示し、内容だけを非表示にします。表示本文は先頭 100,000 文字までで、履歴や設定ファイルには保存しません。

### 未コミット変更を GUI でコミットする

1. 「差分」→「未コミット」で source の変更を確認します。`chezmoi edit ~/.env` で保存した暗号化ファイルも一覧に表示されます。
2. コミットメッセージを入力し、「source をコミット」を押します。source 内の変更をすべて stage し、コミットします。既存の stage 状態にかかわらず全変更が対象です。
3. コミットが完了すると「コミット済み ↔ upstream」へ切り替わります。送信前の差分と先行コミット数を確認します。
4. 送信する場合は「同期」またはメニューから Upload を実行します。

コミット前には既存のバックアップ方式で source / Mac 側を保存します。コミット操作は re-add・merge・apply・push・OpenAI API 呼び出しを行いません。`~/.env` など Mac 側だけを直接編集した場合、その取り込みは既存の Download / Upload 同期で行います。

source と Mac が一致していても、source の未コミット変更は「未コミット」に表示されます。「Mac ↔ source」が空であることは、コミット・送信済みであることを意味しません。upstream 未設定でもローカルコミットは可能ですが、同期には upstream の設定が必要です。

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
