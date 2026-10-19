#!/usr/bin/env bash
# Builds a release DMG, signs it for Sparkle and writes the update feed (appcast.xml).
#
#   VERSION=1.1.0 scripts/release.sh               # prepare build/release/ (nothing is uploaded)
#   VERSION=1.1.0 PUBLISH=1 scripts/release.sh     # also create the GitHub release in $RELEASES_REPO
#
# Sparkle compares CFBundleVersion (the git commit count), so commit before each release.
#
# Every installed copy of Petal checks
#   https://github.com/$RELEASES_REPO/releases/latest/download/appcast.xml
# so the releases repo must be public. Release notes: put Markdown/HTML in release-notes/<version>.md
set -euo pipefail

cd "$(dirname "$0")/.."
: "${VERSION:?Set VERSION, e.g. VERSION=1.1.0}"
RELEASES_REPO="${RELEASES_REPO:-zen20-AI/petal-releases}"
export VERSION UNIVERSAL="${UNIVERSAL:-1}"
export FEED_URL="${FEED_URL-https://github.com/$RELEASES_REPO/releases/latest/download/appcast.xml}"

scripts/build-dmg.sh

DMG="build/Petal-${VERSION}.dmg"
OUT="build/release"
mkdir -p "$OUT"
cp "$DMG" "$OUT/"

SIGN_UPDATE="$(find .build/artifacts -path '*Sparkle/bin/sign_update' -not -path '*old_dsa*' | head -1)"
[[ -x "$SIGN_UPDATE" ]] || { echo "sign_update not found; run 'swift package resolve' first"; exit 1; }
# Prints: sparkle:edSignature="…" length="…"
SIGNATURE_ATTRS="$("$SIGN_UPDATE" --account petal "$DMG")"

BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' build/Petal.app/Contents/Info.plist)"
NOTES_FILE="release-notes/${VERSION}.md"
URL="https://github.com/$RELEASES_REPO/releases/download/v${VERSION}/Petal-${VERSION}.dmg"

# The feed lives in the repo (appcast.xml) so earlier entries survive a clean build.
python3 - appcast.xml "$VERSION" "$BUILD_NUMBER" "$URL" "$SIGNATURE_ATTRS" "$NOTES_FILE" <<'PY'
import html, os, sys, email.utils
path, version, build, url, attrs, notes_file = sys.argv[1:]
notes = open(notes_file).read() if os.path.exists(notes_file) else f"Petal {version}"
fmt = "markdown" if notes_file.endswith(".md") else "html"
item = f"""        <item>
            <title>Petal {version}</title>
            <pubDate>{email.utils.formatdate(localtime=True)}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <description sparkle:format="{fmt}"><![CDATA[{notes}]]></description>
            <enclosure url="{html.escape(url)}" type="application/octet-stream" {attrs.strip()}/>
        </item>
"""
head = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Petal</title>
"""
tail = "    </channel>\n</rss>\n"
old_items = ""
if os.path.exists(path):
    text = open(path).read()
    start = text.find("<item>")
    end = text.rfind("</item>")
    if start != -1:
        old_items = "        " + text[start:end + len("</item>")] + "\n"
        # Drop an earlier entry for the same version (re-running a release).
        marker = f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>"
        if marker in old_items:
            blocks = old_items.split("</item>")
            old_items = "</item>".join(b for b in blocks if marker not in b)
open(path, "w").write(head + item + old_items + tail)
PY

cp appcast.xml "$OUT/appcast.xml"
echo "Prepared $OUT/Petal-${VERSION}.dmg and appcast.xml (commit it after publishing)"

if [[ "${PUBLISH:-0}" == "1" ]]; then
    NOTES_ARGS=(--notes "Petal ${VERSION}")
    [[ -f "$NOTES_FILE" ]] && NOTES_ARGS=(--notes-file "$NOTES_FILE")
    gh release create "v${VERSION}" -R "$RELEASES_REPO" --title "Petal ${VERSION}" "${NOTES_ARGS[@]}" \
        "$OUT/Petal-${VERSION}.dmg" "$OUT/appcast.xml"
    echo "Published v${VERSION} to $RELEASES_REPO"
fi
