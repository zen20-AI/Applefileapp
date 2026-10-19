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
"can't be opened". Open System Settings → Privacy & Security, scroll down
and click "Open Anyway" next to Petal (on older macOS: right-click the app
→ Open). You only need to do this once; updates install by themselves.

The app lives in the menu bar (petal icon). Start dragging any file and
the ring appears beside the pointer, or select files in Finder and press
Option-Command-P. Open the Workspace from the menu bar to work with many
files at once, set up watch folders, browse history and change settings.

ภาษาไทย: ลาก Petal ไปที่ Applications ถ้าเปิดครั้งแรกไม่ได้ ไปที่ System Settings → Privacy & Security
แล้วกด "Open Anyway"
เปลี่ยนภาษาได้ที่ Settings → Language
TXT

# Styled window (background + icon layout) via dmgbuild, which writes Finder's .DS_Store without
# scripting Finder. It's installed into a local venv on first use; without it, a plain image is made.
DMGBUILD=".build/dmgvenv/bin/dmgbuild"
if [[ ! -x "$DMGBUILD" ]]; then
    (python3 -m venv .build/dmgvenv && .build/dmgvenv/bin/pip install -q dmgbuild) >/dev/null 2>&1 || true
fi
if [[ -x "$DMGBUILD" ]]; then
    BG="build/dmg-background"
    (unset SDKROOT; swift scripts/make-dmg-background.swift "$BG.png" 1 && swift scripts/make-dmg-background.swift "$BG@2x.png" 2)
    tiffutil -cathidpicheck "$BG.png" "$BG@2x.png" -out "$BG.tiff" >/dev/null 2>&1
    "$DMGBUILD" -s scripts/dmg-settings.py -D app="$STAGE/Petal.app" -D readme="$STAGE/Read Me.txt" \
        -D background="$BG.tiff" "Petal" "$DMG" >/dev/null
else
    hdiutil create -volname "Petal" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
fi
if [[ -n "${SIGN_IDENTITY:-}" ]]; then codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"; fi
rm -rf "$STAGE"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ -n "${SIGN_IDENTITY:-}" ]] || { echo "NOTARY_PROFILE needs SIGN_IDENTITY (Developer ID)"; exit 1; }
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
