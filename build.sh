#!/bin/zsh
# Builds ClipStack.app into ./build.
#   --install  also copies it to /Applications
#   --dmg      also packages build/ClipStack.dmg for a release
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/ClipStack.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ClipStack" "$APP/Contents/MacOS/ClipStack"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClipStack</string>
    <key>CFBundleDisplayName</key><string>ClipStack</string>
    <key>CFBundleIdentifier</key><string>com.kain.clipstack</string>
    <key>CFBundleExecutable</key><string>ClipStack</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/ClipStack.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/ClipStack.app"
fi

if [[ "${1:-}" == "--dmg" ]]; then
    STAGE=build/dmg
    rm -rf "$STAGE" build/ClipStack.dmg
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname ClipStack -srcfolder "$STAGE" -ov -format UDZO build/ClipStack.dmg >/dev/null
    rm -rf "$STAGE"
    echo "Packaged build/ClipStack.dmg"
fi
