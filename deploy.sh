#!/bin/bash
# Build and install Eureka to /Applications
set -e
cd "$(dirname "$0")"

DEV_CERT="Eureka Dev"

echo "=== Building ==="
swiftc Sources/*.swift -o Eureka -framework Cocoa -framework Carbon -framework ApplicationServices -framework CoreGraphics -framework WebKit

echo "=== Stopping old instances ==="
killall Eureka 2>/dev/null || true
killall ThoughtCapture 2>/dev/null || true
sleep 0.5

echo "=== Deploying ==="
rm -rf /Applications/ThoughtCapture.app
mkdir -p /Applications/Eureka.app/Contents/MacOS
mkdir -p /Applications/Eureka.app/Contents/Resources
cp Eureka /Applications/Eureka.app/Contents/MacOS/Eureka
cp bubbleicon.png /Applications/Eureka.app/Contents/Resources/ 2>/dev/null || true

cat > /Applications/Eureka.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.eureka.app</string>
    <key>CFBundleName</key>
    <string>Eureka</string>
    <key>CFBundleExecutable</key>
    <string>Eureka</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Eureka needs Automation access to save thoughts to Apple Notes.</string>
</dict>
</plist>
EOF

echo "=== Signing ==="
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEV_CERT"; then
    codesign --force --sign "$DEV_CERT" /Applications/Eureka.app
    echo "Signed with '$DEV_CERT' (dev certificate)"
else
    codesign --force --sign - /Applications/Eureka.app
    echo "Signed with ad-hoc signature"
fi

echo "=== Launching ==="
open /Applications/Eureka.app
sleep 1

echo ""
echo "✓ Installed to /Applications/Eureka.app"
echo ""
echo "Next step: grant Accessibility permission"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  → enable Eureka"
