#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_ARGS=(--disable-sandbox -c release --product ChezmoiMenu)
case "${1:-}" in
    "") ;;
    --universal) BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
    *) printf 'Usage: bash scripts/build-app.sh [--universal]\n' >&2; exit 2 ;;
esac
APP_VERSION="$(tr -d '\r\n' < VERSION)"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Invalid VERSION\n' >&2; exit 2
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
bash scripts/build-icons.sh
APP="$PWD/dist/Chezmoi Menu.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ChezmoiMenu" "$APP/Contents/MacOS/ChezmoiMenu"
strip -S "$APP/Contents/MacOS/ChezmoiMenu"
if [[ "${1:-}" == --universal ]]; then
    APP_ARCHS=" $(lipo -archs "$APP/Contents/MacOS/ChezmoiMenu") "
    if [[ "$APP_ARCHS" != *" arm64 "* || "$APP_ARCHS" != *" x86_64 "* ]]; then
        printf 'Universal binary must include arm64 and x86_64.\n' >&2; exit 1
    fi
fi
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
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP/Contents/Info.plist"
SIGN_IDENTITY="${CHEZMOI_MENU_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == - ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi
codesign --verify --strict "$APP"
printf 'Built: %s\n' "$APP"
