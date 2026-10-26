#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
IC_TOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
"$IC_TOOL" Assets/AppIcon.icon --export-image --output-file "$PWD/Assets/AppIcon.png" \
    --platform macOS --rendition Default --width 1024 --height 1024 --scale 1 --design-generation 27
ICON_SET="$PWD/.build/AppIcon.iconset"
mkdir -p "$ICON_SET"
# Keep PNG / ICNS fallbacks in addition to the native layered icon compiled by actool.
for POINTS in 16 32 128 256 512; do
    sips -s format png -z "$POINTS" "$POINTS" Assets/AppIcon.png \
        --out "$ICON_SET/icon_${POINTS}x${POINTS}.png" >/dev/null
    PIXELS=$((POINTS * 2))
    sips -s format png -z "$PIXELS" "$PIXELS" Assets/AppIcon.png \
        --out "$ICON_SET/icon_${POINTS}x${POINTS}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_SET" -o Assets/AppIcon.icns
