# アイコン

chezmoi の家・鍵穴・曲線の土台を保ち、macOS 27 向けのレイヤー付きアイコンにしました。[upstream の原図](https://github.com/twpayne/chezmoi/blob/e5ae319347c3efa0acbc3d2ab2a01e5abf62b276/assets/images/logo-256px.svg) のパスを使用し、家と鍵穴を分離しています。帰属と MIT License 本文は [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) を参照してください。

| 素材 | 用途 |
| --- | --- |
| `AppIcon.icon/icon.json` | Icon Composer の正本。背景・明暗の色・ガラス効果 |
| `AppIcon.icon/Assets/House.svg` | 家と曲線のベクターレイヤー |
| `AppIcon.icon/Assets/Keyhole.svg` | 鍵穴のベクターレイヤー |
| `AppIcon.png` / `AppIcon.icns` | Xcode のレンダラーから生成したフォールバック |
| `chezmoi-original.png` | 提供された原図。メニューバーの template image |
| `AppIcon-master.png` | 0.1 系で使用した旧アートワーク。現在のビルドでは使用しない |

明るい外観は暖色の白い背景とグレーの図形、暗い外観は暗い背景と明るい図形です。角丸・光・レイヤーの表現は Icon Composer に任せます。メニューバーは背景に合わせて OS が色を決める単色画像です。

## 生成

Xcode 27.1 以降で `AppIcon.icon` を Icon Composer から編集できます。

```sh
bash scripts/build-icons.sh
bash scripts/build-app.sh
```

前者は `ictool --design-generation 27` で PNG、`sips` / `iconutil` で ICNS を生成します。後者は `actool` でネイティブのレイヤーを `Assets.car` にコンパイルし、`CFBundleIconName = AppIcon` を設定してから署名します。PNG は設定画面のブランド表示にも使用します。

このバージョンの生成に ImageGen や OpenAI API は使用しません。[Apple Icon Composer](https://developer.apple.com/icon-composer/) と [App icons HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons) を参照してください。
