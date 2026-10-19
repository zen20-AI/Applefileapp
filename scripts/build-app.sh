#!/usr/bin/env bash
# Builds a release binary and wraps it in "build/Petal.app" (menu bar app with a Manager window).
#
#   VERSION=1.2.0 scripts/build-app.sh      # set the version (default 1.0.0)
#   UNIVERSAL=1 scripts/build-app.sh        # arm64 + x86_64
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#   FEED_URL=https://example.com/appcast.xml scripts/build-app.sh   # Sparkle update feed ("" turns updates off)
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/Petal.app"
# Sparkle update feed: appcast.xml attached to the latest release of the public releases repo.
FEED_URL="${FEED_URL-https://github.com/AImunich20/petal-releases/releases/latest/download/appcast.xml}"
# EdDSA public key matching the private key in the login keychain (account "petal", see scripts/release.sh).
SPARKLE_PUBLIC_KEY="8/6VGk8EEFt1xtMKHKDSALTKI7FtVNwBVDYbS7NGHeY="

# The macOS 27 SDK turns SwiftUI's @State into a macro whose plugin only ships with full Xcode.
# With just the Command Line Tools, build against the newest older SDK instead.
if [[ -z "${SDKROOT:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
    for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX2[0-6].*.sdk 2>/dev/null | sort -V -r); do
        export SDKROOT="$sdk"
        echo "Using $(basename "$sdk") (Command Line Tools)"
        break
    done
fi

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Petal" "$APP/Contents/MacOS/Petal"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# App icon, drawn by scripts/make-icon.swift.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
(unset SDKROOT; swift scripts/make-icon.swift "build/AppIcon-1024.png" >/dev/null)
for size in 16 32 128 256 512; do
    sips -z $size $size "build/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "build/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Petal</string>
    <key>CFBundleDisplayName</key><string>Petal</string>
    <key>CFBundleIdentifier</key><string>com.zen20.petal</string>
    <key>CFBundleExecutable</key><string>Petal</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>${FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Petal</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Image, PDF or Document</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
                <string>com.adobe.pdf</string>
                <string>public.rtf</string>
                <string>public.plain-text</string>
                <string>public.html</string>
                <string>org.openxmlformats.wordprocessingml.document</string>
                <string>com.microsoft.word.doc</string>
                <string>public.folder</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc signature by default; pass SIGN_IDENTITY for a Developer ID build.
# Sign inside-out (Sparkle's helpers first), as Sparkle's docs recommend instead of --deep.
# Hardened runtime (required for notarization) only with a real identity: under it, an ad-hoc app
# refuses to load the separately ad-hoc-signed Sparkle.framework.
SIGN=(codesign --force --sign "${SIGN_IDENTITY:--}")
if [[ -n "${SIGN_IDENTITY:-}" ]]; then SIGN+=(--options runtime --timestamp); fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
