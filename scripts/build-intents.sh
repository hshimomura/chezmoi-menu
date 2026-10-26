#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?Pass the staging app path}"
SOURCE_LIST="$PWD/.build/intent-sources.txt"
CONST_LIST="$PWD/.build/intent-constants.txt"
find "$PWD/Sources/ChezmoiMenu" -name '*.swift' -print > "$SOURCE_LIST"
find "$PWD/.build" -path '*/Release/ChezmoiMenu-p.build/Objects-normal/arm64/*' \
    -name '*.swiftconstvalues' -print > "$CONST_LIST"
if [[ ! -s "$CONST_LIST" ]]; then
    printf 'Release App Intents constants were not emitted.\n' >&2; exit 1
fi
xcrun appintentsmetadataprocessor \
    --output "$APP/Contents/Resources" \
    --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
    --module-name ChezmoiMenu --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
    --platform-family macOS --deployment-target 27.0 --target-triple arm64-apple-macos27.0 \
    --source-file-list "$SOURCE_LIST" --swift-const-vals-list "$CONST_LIST"
test -f "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata"
