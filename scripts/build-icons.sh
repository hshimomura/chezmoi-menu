#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ Assets/AppIcon.icns -nt Assets/AppIcon-master.png && Assets/AppIcon.png -nt Assets/AppIcon-master.png ]]; then
    exit 0
fi
ICON_SET="$PWD/.build/AppIcon.iconset"
mkdir -p "$ICON_SET"
# Convert the selected artwork into macOS's standard 16–1024 px icon representations.
for POINTS in 16 32 128 256 512; do
    sips -s format png -z "$POINTS" "$POINTS" Assets/AppIcon-master.png \
        --out "$ICON_SET/icon_${POINTS}x${POINTS}.png" >/dev/null
    PIXELS=$((POINTS * 2))
    sips -s format png -z "$PIXELS" "$PIXELS" Assets/AppIcon-master.png \
        --out "$ICON_SET/icon_${POINTS}x${POINTS}@2x.png" >/dev/null
done
cp "$ICON_SET/icon_512x512@2x.png" Assets/AppIcon.png
iconutil -c icns "$ICON_SET" -o Assets/AppIcon.icns
