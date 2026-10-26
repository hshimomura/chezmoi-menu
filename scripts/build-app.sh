#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --disable-sandbox -c release
bash scripts/build-icons.sh
APP="$PWD/dist/Chezmoi Menu.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ChezmoiMenu "$APP/Contents/MacOS/ChezmoiMenu"
cp Assets/AppIcon.icns Assets/AppIcon.png "$APP/Contents/Resources/"
cp Assets/chezmoi-original.png "$APP/Contents/Resources/MenuBarMark.png"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ChezmoiMenu</string>
<key>CFBundleIdentifier</key><string>jp.local.ChezmoiMenu</string>
<key>CFBundleName</key><string>Chezmoi Menu</string>
<key>CFBundleDisplayName</key><string>Chezmoi Menu</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Ad-hoc signing supports running locally. Distribution needs Developer ID signing/notarization.
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
