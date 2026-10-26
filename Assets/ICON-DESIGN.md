# アイコン

chezmoi のロゴ画像を基に、家・鍵穴・曲線の土台を残して macOS 向けの表示を作成しました。元の図形は [upstream のロゴ](https://github.com/twpayne/chezmoi/blob/master/assets/images/logo-256px.svg) に由来します。帰属とライセンス本文は [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) を参照してください。

- `chezmoi-original.png`: 提供された原図のコピー。メニューバーの単色マークに使用。
- `AppIcon-master.png`: built-in ImageGen で生成した最終アートワーク。元画像は上書きしていません。
- `AppIcon.png`: 1024 × 1024 px の PNG。
- `AppIcon.icns`: 16 / 32 / 128 / 256 / 512 pt と各 Retina 解像度を含む macOS アイコン。

設定画面と Finder のアプリアイコンにタイル版を使用します。メニューバーでは元のマークを AppKit の template image として表示し、OS が背景に応じた単色へ自動調整します。同期中は進行を示すシステムシンボルを表示します。

アプリアイコンは静的な PNG / ICNS です。Icon Composer のレイヤーや、動的な Liquid Glass の光源・外観バリエーションは含みません。構成の参考: [Apple Human Interface Guidelines — App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)。

## 生成方法

built-in ImageGen を使用しました。CLI/API fallback やアプリの保存済み OpenAI API key は使用していません。

最終採用画像のプロンプト:

```text
Create a clean production macOS app icon using this exact chezmoi house-and-keyhole silhouette as the edit target. Vector-sharp, smooth flat graphic construction, no photographic rendering. A simple soft pearl-white/light-gray rounded-square tile with a continuous smooth boundary; centered warm dark-gray house logo preserving the peaked roof, the original roof eaves and upright walls, central keyhole and gently curved baseline. The logo is solid high-contrast graphite, with only an extremely subtle bevel INSIDE its edges. Tile is centered at 82 percent of the square canvas width, logo at 64 percent. Restrained native Mac utility icon. The rounded-square tile is fully opaque, everything outside the tile fully transparent. ABSOLUTELY NO outer shadows, NO glows, NO semi-transparent fringe, NO noise, NO texture, NO grain, NO white flecks, NO painterly borders. The outside contour must be perfectly clean like an SVG. Only subtle gradients within the tile and logo, no effects outside their clean geometrical boundaries. No text, no badge, no extra shapes, no colored accents. Single centered icon asset, square canvas, transparent margin uniform on all sides.
```

`bash scripts/build-icons.sh` でサイズ別の画像と ICNS を再作成します。`bash scripts/build-app.sh` では生成したリソースを `.app` にコピーし、`CFBundleIconFile` を設定してから署名します。
