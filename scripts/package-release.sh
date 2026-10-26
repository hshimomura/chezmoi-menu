#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
    ""|--notarize) ;;
    *) printf 'Usage: bash scripts/package-release.sh [--notarize]\n' >&2; exit 2 ;;
esac
if [[ "${1:-}" == --notarize && "${CHEZMOI_MENU_SIGN_IDENTITY:--}" == - ]]; then
    printf 'Notarization requires CHEZMOI_MENU_SIGN_IDENTITY (Developer ID Application).\n' >&2
    exit 2
fi
bash scripts/build-app.sh --universal
APP_VERSION="$(tr -d '\r\n' < VERSION)"
ARCHIVE_NAME="Chezmoi-Menu-${APP_VERSION}-universal.zip"
APP="$PWD/dist/Chezmoi Menu.app"
ARCHIVE="$PWD/dist/$ARCHIVE_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
if [[ "${1:-}" == --notarize ]]; then
    python3 scripts/notarize-app.py --app "$APP" --archive "$ARCHIVE"
    # The downloadable archive must contain the stapled app, not the original submission.
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
fi
(
    cd dist
    shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)
printf 'Archive: %s\nChecksum: %s.sha256\n' "$ARCHIVE" "$ARCHIVE"
