#!/bin/bash
# Build Eureka.app and package as .zip for GitHub release
set -e
cd "$(dirname "$0")"

VERSION="${1:-2.0.0}"
APP="Eureka.app"
BINARY="$APP/Contents/MacOS/Eureka"

echo "=== Building Eureka v$VERSION ==="

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" << EOF
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
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Eureka needs Automation access to save thoughts to Apple Notes.</string>
</dict>
</plist>
EOF

cp -f bubbleicon.png "$APP/Contents/Resources/" 2>/dev/null || true

echo "Compiling..."
swiftc Sources/*.swift \
    -o "$BINARY" \
    -framework Cocoa \
    -framework Carbon \
    -framework ApplicationServices \
    -framework CoreGraphics \
    -framework WebKit \
    -O

echo "Signing..."
codesign --force --sign - "$APP"

echo "Packaging..."
rm -f "Eureka-v${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "Eureka-v${VERSION}.zip"

SIZE=$(du -h "Eureka-v${VERSION}.zip" | cut -f1)
echo ""
echo "=== Done ==="
echo "  Eureka-v${VERSION}.zip ($SIZE)"
