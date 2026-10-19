#!/usr/bin/env bash
# Builds a release binary and wraps it in "Apple File App.app" (menu bar only, no Dock icon).
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release

APP="build/Apple File App.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/AppleFileApp" "$APP/Contents/MacOS/AppleFileApp"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Apple File App</string>
    <key>CFBundleDisplayName</key><string>Apple File App</string>
    <key>CFBundleIdentifier</key><string>com.zen20.applefileapp</string>
    <key>CFBundleExecutable</key><string>AppleFileApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
