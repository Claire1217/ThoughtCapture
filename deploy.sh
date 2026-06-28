#!/bin/bash
set -e
cd "$(dirname "$0")"

DEV_CERT="ThoughtCapture Dev"

echo "=== Building ==="
swiftc Sources/*.swift -o ThoughtCapture -framework Cocoa -framework Carbon -framework ApplicationServices -framework CoreGraphics -framework WebKit

echo "=== Stopping old instances ==="
killall ThoughtCapture 2>/dev/null || true
sleep 0.5

echo "=== Deploying ==="
mkdir -p /Applications/ThoughtCapture.app/Contents/MacOS
mkdir -p /Applications/ThoughtCapture.app/Contents/Resources
cp ThoughtCapture /Applications/ThoughtCapture.app/Contents/MacOS/ThoughtCapture
cp bubbleicon.png /Applications/ThoughtCapture.app/Contents/Resources/ 2>/dev/null || true

cat > /Applications/ThoughtCapture.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.thoughtcapture.app</string>
    <key>CFBundleName</key>
    <string>ThoughtCapture</string>
    <key>CFBundleExecutable</key>
    <string>ThoughtCapture</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "=== Signing ==="
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEV_CERT"; then
    codesign --force --sign "$DEV_CERT" /Applications/ThoughtCapture.app
    echo "Signed with '$DEV_CERT' (dev certificate)"
else
    codesign --force --sign - /Applications/ThoughtCapture.app
    echo "Signed with ad-hoc signature"
fi

echo "=== Launching ==="
open /Applications/ThoughtCapture.app
sleep 1

echo ""
echo "✓ Installed to /Applications/ThoughtCapture.app"
echo ""
echo "Next step: grant Accessibility permission"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  → enable ThoughtCapture"
