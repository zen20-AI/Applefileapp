#!/usr/bin/env bash
# Publishes the download page and README (site/) to the releases repo and turns on GitHub Pages there.
#   scripts/publish-site.sh      → https://<owner>.github.io/petal-releases/
set -euo pipefail
cd "$(dirname "$0")/.."
RELEASES_REPO="${RELEASES_REPO:-AImunich20/petal-releases}"

[[ -f build/AppIcon-1024.png ]] || scripts/build-app.sh
sips -z 512 512 build/AppIcon-1024.png --out build/site-icon.png >/dev/null

upload() { # <local file> <path in repo>
    local sha
    sha="$(gh api "repos/$RELEASES_REPO/contents/$2" --jq .sha 2>/dev/null || true)"
    gh api -X PUT "repos/$RELEASES_REPO/contents/$2" -f message="Update $2" \
        -f content="$(base64 -i "$1")" ${sha:+-f sha="$sha"} --jq .content.path
}
upload site/index.html index.html
upload build/site-icon.png icon.png
# The repo's front page on GitHub: install guide with screenshots.
upload site/README.md README.md
for image in docs/images/*.png; do upload "$image" "images/$(basename "$image")"; done

gh api "repos/$RELEASES_REPO/pages" >/dev/null 2>&1 || \
    gh api -X POST "repos/$RELEASES_REPO/pages" -f "source[branch]=main" -f "source[path]=/" --jq .html_url
echo "https://${RELEASES_REPO%%/*}.github.io/${RELEASES_REPO#*/}/" | tr '[:upper:]' '[:lower:]'
