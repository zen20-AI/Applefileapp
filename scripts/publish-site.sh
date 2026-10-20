#!/usr/bin/env bash
# Publishes the download page and README (site/) to the releases repo and turns on GitHub Pages there.
#   scripts/publish-site.sh      → https://<owner>.github.io/petal-releases/
set -euo pipefail
cd "$(dirname "$0")/.."
RELEASES_REPO="${RELEASES_REPO:-AImunich20/petal-releases}"

[[ -f build/AppIcon-1024.png ]] || scripts/build-app.sh
sips -z 512 512 build/AppIcon-1024.png --out build/site-icon.png >/dev/null

upload() { # <local file> <path in repo>
    local sha body
    sha="$(gh api "repos/$RELEASES_REPO/contents/$2" --jq .sha 2>/dev/null || true)"
    # The request goes through a file: big images overflow the command line as a -f argument.
    body="$(mktemp)"
    python3 -c 'import base64, json, sys
print(json.dumps({"message": "Update " + sys.argv[2], "content": base64.b64encode(open(sys.argv[1], "rb").read()).decode(),
                  **({"sha": sys.argv[3]} if sys.argv[3] else {})}))' "$1" "$2" "$sha" > "$body"
    gh api -X PUT "repos/$RELEASES_REPO/contents/$2" --input "$body" --jq .content.path
    rm -f "$body"
}
upload site/index.html index.html
upload build/site-icon.png icon.png
# The repo's front page on GitHub: install guide with screenshots.
upload site/README.md README.md
for image in docs/images/*.png; do upload "$image" "images/$(basename "$image")"; done

gh api "repos/$RELEASES_REPO/pages" >/dev/null 2>&1 || \
    gh api -X POST "repos/$RELEASES_REPO/pages" -f "source[branch]=main" -f "source[path]=/" --jq .html_url
echo "https://${RELEASES_REPO%%/*}.github.io/${RELEASES_REPO#*/}/" | tr '[:upper:]' '[:lower:]'
