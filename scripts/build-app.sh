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

# Translations (Resources/<lang>.lproj/Localizable.strings), looked up through the main bundle.
for lproj in Resources/*.lproj; do
    [[ -d "$lproj" ]] && ditto "$lproj" "$APP/Contents/Resources/$(basename "$lproj")"
done

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
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>th</string></array>
    <key>NSDesktopFolderUsageDescription</key><string>Petal saves converted and edited files next to the originals on your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Petal saves converted and edited files next to the originals in Documents.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Petal saves converted and edited files next to the originals in Downloads, and can watch it for new files.</string>
    <key>NSRemovableVolumesUsageDescription</key><string>Petal works on files stored on external drives.</string>
    <key>NSNetworkVolumesUsageDescription</key><string>Petal works on files stored on network drives.</string>
    <key>NSAppleEventsUsageDescription</key><string>Petal reads which files are selected in Finder when you press ⌥⌘P.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.zen20.petal</string>
            <key>CFBundleURLSchemes</key><array><string>petal</string></array>
        </dict>
    </array>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Add to Shelf</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>shelf</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Compress to Under 1 MB</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>compress-1mb</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Compress</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>compress</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Copy Text</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>copyText</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Remove Background</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>cutOut</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Convert to JPG</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>convert-jpg</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Convert to PDF</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>convert-pdf</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Merge into PDF</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>merge</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Split PDF</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>split</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Organize PDF Pages</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>pages</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Rename</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>rename</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Open Ring</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>ring</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Petal: Add to Workspace</string></dict>
            <key>NSMessage</key><string>runService</string>
            <key>NSPortName</key><string>Petal</string>
            <key>NSUserData</key><string>workspace</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
    </array>
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
                <string>public.movie</string>
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
#
# Without a Developer ID, a local self-signed "Petal Code Signing" identity (if it's in the keychain)
# gives every build the same designated requirement, so macOS keeps folder permissions across
# updates (ad-hoc signatures change with every build and macOS would ask again).
LOCAL_IDENTITY="Petal Code Signing"
if [[ -z "${SIGN_IDENTITY:-}" ]] && security find-certificate -c "$LOCAL_IDENTITY" >/dev/null 2>&1; then
    SIGN=(codesign --force --sign "$LOCAL_IDENTITY")
else
    SIGN=(codesign --force --sign "${SIGN_IDENTITY:--}")
fi
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    # Hardened runtime needs this entitlement for the Finder selection (⌥⌘P) Apple Events.
    ENTITLEMENTS="build/Petal.entitlements"
    cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.automation.apple-events</key><true/></dict></plist>
ENT
    SIGN+=(--options runtime --timestamp)
fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" ${ENTITLEMENTS:+--entitlements "$ENTITLEMENTS"} "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
