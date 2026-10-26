<img src="Assets/AppIcon.png" width="96" alt="Chezmoi Menu のアイコン">

# Chezmoi Menu

macOS のメニューバーから [chezmoi](https://www.chezmoi.io/) を Download / Upload 同期するネイティブアプリです。通常の Git merge で解消できないテキスト競合は、OpenAI API で自動統合できます。

**chezmoi の非公式クライアントです。** dotfiles の管理には、別途インストールした chezmoi と既存の Git リポジトリを使用します。ホーム全体を自動で Git 管理する機能はありません。

## できること

| 操作 | 動作 |
| --- | --- |
| Download 同期 | ローカル変更を保護してリモートを統合し、この Mac に適用。push はしません |
| Upload 同期 | ローカル変更とリモートを統合・適用し、upstream に push |
| 同期前チェック | Git 接続・差分・現在の source の適用予行を確認。実適用・commit・push・AI 通信はしません |
| AI 競合解決 | 共通祖先・ローカル・リモートの 3 つの版からテキストを統合 |

同期前のバックアップ、実行履歴、macOS キーチェーンへの API key 保存、ログイン時起動に対応します。同期はメニューまたは設定画面から手動で開始します。

## 必要なもの

- macOS 14 以降。
- [chezmoi](https://www.chezmoi.io/install/)、Git、および初期化済みの dotfiles リポジトリ。
- AI 競合解決を使う場合は、課金と利用権限を設定した OpenAI API key。

通常の同期と同期前チェックは、競合がなければ API key なしでも実行できます。Swift の外部パッケージには依存していません。

## 別の Mac にインストール

[GitHub Releases](https://github.com/hshimomura/chezmoi-menu/releases/latest) の **Universal 版 ZIP** を展開し、`Chezmoi Menu.app` を `~/Applications` または `/Applications` に移して起動します。Apple Silicon / Intel の両方で利用でき、アプリのビルドは不要です。

配布版は Developer ID 署名と Apple 公証を行い、公証チケットを添付しています。chezmoi・Git・dotfiles の設定と Git 認証、AI 用 API key は各 Mac に用意してください。API key は Mac ごとのキーチェーンに保存します。

**[別の Mac への詳しい導入・更新手順](docs/INSTALL.md)**

## ソースからビルドと起動

Swift 6 対応の Xcode / Command Line Tools が必要です。

```sh
brew install chezmoi
git clone https://github.com/hshimomura/chezmoi-menu.git
cd chezmoi-menu
bash scripts/build-app.sh
open "dist/Chezmoi Menu.app"
```

初回は設定画面が開きます。継続して使う場合は、アプリを終了してから `dist/Chezmoi Menu.app` を `~/Applications` にコピーし、そのコピーを起動してください。Dock には常駐せず、メニューバーの家と鍵穴のマークから操作できます。

通常ビルドは実行中の Mac 向けで、ローカル用の ad-hoc 署名を行います。`bash scripts/build-app.sh --universal` では両アーキテクチャを含めます。署名・公証を伴う配布ビルドは [開発手順](docs/DEVELOPMENT.md) を参照してください。自動アップデート機能はありません。

## 最初の設定

1. chezmoi の実行ファイルを確認します。通常、Apple Silicon は `/opt/homebrew/bin/chezmoi`、Intel は `/usr/local/bin/chezmoi` です。
2. 「設定ファイル」は通常は空欄です。別環境を使う場合は chezmoi 設定ファイルのパスを指定します。
3. AI を使う場合は API key を入力し、「設定を保存」を押します。空欄で保存すると既存キーを保持します。
4. 「同期前チェック（適用・送信なし）」を実行し、実行履歴を確認します。
5. Download 同期または Upload 同期を実行します。

モデルの既定値は `gpt-6-luna` で、`gpt-5.6-luna` も指定できます。この 2 系統には推論量 `low` を指定します。API アカウントで利用できるモデル名を設定してください。

## 利用前に知っておくこと

- **Download でもローカル変更をコミットします。** source にある未コミット変更も対象です。リモートへの push は Upload のみです。
- Upload もリモート変更を先に統合して、この Mac に適用します。force push は行いません。
- **競合ファイルのパスと 3 つの版を OpenAI API に送信します。** API 料金が発生します。通常の Git merge で解消できる場合には送信しません。
- AI の意味的な正しさを完全には保証できません。除外パス、バックアップ、停止時の履歴を確認してください。
- 暗号化・バイナリ・追加/削除などの競合や、Mac 側で直接編集したテンプレートの出力は、自動統合せず停止します。
- chezmoi のスクリプトは既定で適用しません。既存の hooks・externals・テンプレート関数の副作用は、それぞれの設定に従います。
- apply はファイルシステム全体のトランザクションではありません。途中で失敗すると、一部のファイルが更新済みになる場合があります。

## ドキュメント

- [別の Mac へのインストール](docs/INSTALL.md)
- [使い方と同期の前提](docs/USAGE.md)
- [バックアップ・停止時の復旧](docs/RECOVERY.md)
- [データ保存と AI への送信範囲](docs/SECURITY.md)
- [開発・ビルド・構成](docs/DEVELOPMENT.md)
- [テスト内容と検証範囲](docs/TESTING.md)
- [アイコンの素材・生成方法](Assets/ICON-DESIGN.md)
- [コントリビューション](CONTRIBUTING.md)

## ライセンス

独自のコードとドキュメントは [MIT License](LICENSE) です。改変、商用利用、再配布を認めます。著作権表示とライセンス本文を保持してください。派生版のソース公開義務はありません。

chezmoi の名称・ロゴは upstream に由来します。原図とそれを基にしたアイコンの帰属、および upstream のライセンス本文は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) に記載しています。MIT の採用は、公式クライアントと誤認させる表示や upstream の推奨を意味しません。
