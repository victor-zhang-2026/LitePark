#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP=".build/LitePark.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/ChatGPTLaterQueue" "$APP/Contents/MacOS/ChatGPTLaterQueue"
cp "Resources/LitePark.icns" "$APP/Contents/Resources/LiteParkCards.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.chatgpt.desktop.later-queue</string>
<key>CFBundleName</key><string>LitePark</string>
<key>CFBundleDisplayName</key><string>LitePark</string>
<key>CFBundleExecutable</key><string>ChatGPTLaterQueue</string>
<key>CFBundleVersion</key><string>1.0.0</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>LiteParkCards.icns</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
# Prefer the stable local identity so Accessibility approval survives rebuilds.
# Contributors without that certificate can still build an ad-hoc signed app.
LOCAL_IDENTITY="ChatGPT Later Queue Local Development"
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$LOCAL_IDENTITY\""; then
    SIGN_IDENTITY="$LOCAL_IDENTITY"
else
    SIGN_IDENTITY="-"
fi
codesign --force --sign "$SIGN_IDENTITY" --identifier local.chatgpt.desktop.later-queue "$APP"
echo "$PWD/$APP"
