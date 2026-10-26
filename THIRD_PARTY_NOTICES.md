# サードパーティの帰属とライセンス

## chezmoi ロゴ

- プロジェクト: [twpayne/chezmoi](https://github.com/twpayne/chezmoi)
- 原図: [assets/images/logo-256px.svg](https://github.com/twpayne/chezmoi/blob/e5ae319347c3efa0acbc3d2ab2a01e5abf62b276/assets/images/logo-256px.svg)
- 確認した upstream のコミット: `e5ae319347c3efa0acbc3d2ab2a01e5abf62b276`
- ライセンス: [upstream の MIT License](https://github.com/twpayne/chezmoi/blob/e5ae319347c3efa0acbc3d2ab2a01e5abf62b276/LICENSE)

`Assets/chezmoi-original.png` は chezmoi ロゴに由来する提供画像です。`AppIcon.icon/Assets/` は上記 SVG の図形を家と鍵穴に分けて配置したものです。`AppIcon.icon`、`AppIcon.png`、`AppIcon.icns` および旧 `AppIcon-master.png` は macOS 用に調整した派生素材です。原図の著作権表示と利用条件を以下に保持します。独自の変更部分には、このリポジトリの MIT License を適用します。

Chezmoi Menu は upstream の公式製品ではなく、名称やロゴの使用によって推奨・提携・承認を示すものではありません。

### upstream ライセンス本文

```text
The MIT License (MIT)

Copyright (c) 2018 Tom Payne

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## Swift Subprocess / Swift System

非同期プロセス実行に [Swift Subprocess](https://github.com/swiftlang/swift-subprocess) 1.0.2 と、依存する [Swift System](https://github.com/apple/swift-system) 1.8.1 を使用します。いずれも Apache License 2.0 with Runtime Library Exception です。各ソースの著作権は Apple Inc. and the Swift project authors に帰属します。

各リポジトリのライセンス本文を [LICENSES/swift-subprocess.txt](LICENSES/swift-subprocess.txt) と [LICENSES/swift-system.txt](LICENSES/swift-system.txt) に保持します。Subprocess のソースヘッダーが参照する [Swift のライセンスと例外条項](https://www.swift.org/LICENSE.txt) は [LICENSES/swift-runtime.txt](LICENSES/swift-runtime.txt) に保持します。すべて配布アプリにも同梱します。独自コードの MIT License をこれらの依存コードへ上書きするものではありません。
