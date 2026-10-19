#!/usr/bin/env bash
# Builds the app and packages it as build/Petal-<version>.dmg with an Applications shortcut.
#
#   scripts/build-dmg.sh
#   VERSION=1.2.0 UNIVERSAL=1 scripts/build-dmg.sh
#
# For public release (no Gatekeeper warning), sign with Developer ID and notarize:
#   xcrun notarytool store-credentials petal-notary --apple-id … --team-id … --password <app-specific>
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=petal-notary scripts/build-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."
export VERSION="${VERSION:-1.0.0}"
scripts/build-app.sh

APP="build/Petal.app"
STAGE="build/dmg"
DMG="build/Petal-${VERSION}.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<'TXT'
Petal
=====

Install: drag "Petal" onto the Applications folder.

First launch: this build isn't notarized by Apple, so macOS may say it
"can't be opened". Right-click (or Control-click) the app in Applications,
choose Open, then click Open again. You only need to do this once.
(Or: System Settings → Privacy & Security → "Open Anyway".)

The app lives in the menu bar (ring icon). Start dragging any file and
the ring appears beside the pointer. Open the Manager from the menu bar
to work with many files at once, browse history and change settings.
TXT

hdiutil create -volname "Petal" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
if [[ -n "${SIGN_IDENTITY:-}" ]]; then codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"; fi
rm -rf "$STAGE"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ -n "${SIGN_IDENTITY:-}" ]] || { echo "NOTARY_PROFILE needs SIGN_IDENTITY (Developer ID)"; exit 1; }
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
