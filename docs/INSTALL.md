# 別の Mac へのインストール

macOS 14 以降の Apple Silicon / Intel Mac で利用できます。Universal 版には両方の実行コードが含まれ、アプリのビルドや Rosetta は不要です。

## 1. アプリを配置する

1. [GitHub Releases](https://github.com/hshimomura/chezmoi-menu/releases/latest) から `Chezmoi-Menu-<バージョン>-universal.zip` をダウンロードします。
2. ZIP を展開します。
3. `Chezmoi Menu.app` を `~/Applications` または `/Applications` に移します。`~/Applications` がなければ Finder で作成できます。
4. アプリを起動します。初回は設定画面が開き、メニューバーに家と鍵穴のマークが表示されます。

配布版は Developer ID 署名・Apple 公証を行い、公証チケットをアプリへ添付しています。初回のインターネットからダウンロードしたアプリの確認は、macOS の表示に従ってください。Gatekeeper や quarantine を一括で無効化する操作は不要です。

ダウンロードの整合性を確認したい場合は、同じ Release の `.sha256` ファイルも ZIP と同じフォルダへ保存し、そのフォルダで実行します。

```sh
shasum -a 256 -c Chezmoi-Menu-0.1.1-universal.zip.sha256
```

別バージョンではファイル名を読み替えます。

## 2. その Mac の chezmoi と Git を確認する

既に使っている環境なら、次を確認します。

```sh
chezmoi --version
chezmoi source-path
chezmoi git -- status
chezmoi git -- branch -vv
```

chezmoi が未導入なら、Homebrew がある環境では `brew install chezmoi` でインストールできます。Git とリモートへの認証もその Mac に用意してください。Git が起動時に Command Line Tools の導入を求める場合は、macOS の案内に従います。

dotfiles をまだ初期化していない Mac では、自分のリポジトリを指定します。

```sh
# URL は自分の dotfiles リポジトリに置き換える
chezmoi init https://github.com/YOUR_ACCOUNT/YOUR_DOTFILES.git
chezmoi diff
```

この例は `--apply` を付けていません。差分を確認し、環境固有の設定や復号設定を整えます。Chezmoi Menu のアプリ用リポジトリを dotfiles として初期化しないでください。

現在のブランチには upstream が必要です。chezmoi の `git.autoAdd` / `git.autoCommit` / `git.autoPush` は無効にします。詳しくは [使い方](USAGE.md) を参照してください。

## 3. アプリを設定する

- chezmoi の実行ファイルは、Apple Silicon の Homebrew なら通常 `/opt/homebrew/bin/chezmoi`、Intel なら `/usr/local/bin/chezmoi` です。通常は自動選択されます。
- 独自の chezmoi 設定ファイルを使わない場合、設定ファイル欄は空欄にします。
- AI 競合解決を使う場合は、その Mac の設定画面で OpenAI API key を保存します。
- 必要なら「ログイン時に起動する」を有効にします。起動時に自動同期は行いません。

API key は各 Mac のキーチェーンに個別保存します。アプリ設定、バックアップ、実行履歴、Git 認証も Mac ごとに管理します。これらのコピーを dotfiles リポジトリへ入れる必要はありません。

## 4. 最初の同期

1. 「同期前チェック（適用・送信なし）」を実行します。
2. source / destination と差分を実行履歴で確認します。
3. リモートから取り込みたい Mac では Download 同期を実行します。
4. その Mac の編集を他へ送る場合は Upload 同期を実行します。

別の Mac でも Download 同期を実行すると、送信した変更を取り込めます。Mac ごとの差分を残したい設定は、chezmoi のテンプレートやローカル設定で表現してください。Mac 固有の絶対パスが自動的に移植されるわけではありません。

## アップデート

同期完了後にアプリを終了し、新しい Release のアプリで既存の `.app` を置き換えます。`~/Library/Application Support/ChezmoiMenu` とキーチェーンを削除しなければ、設定とキーは保持されます。自動アップデート機能はありません。

## ソースからビルドする場合

Swift 6 対応の開発ツールを用意し、リポジトリで `bash scripts/build-app.sh` を実行します。両アーキテクチャ用なら `bash scripts/build-app.sh --universal` を使用します。既定のローカルビルドは ad-hoc 署名です。[開発手順](DEVELOPMENT.md) を参照してください。
