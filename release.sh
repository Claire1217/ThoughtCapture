#!/bin/bash
# Build ThoughtCapture.app and package as .zip for GitHub release
set -e
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
APP="ThoughtCapture.app"
BINARY="$APP/Contents/MacOS/ThoughtCapture"

echo "=== Building ThoughtCapture v$VERSION ==="

# Create app bundle
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" << EOF
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
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>ThoughtCapture needs Automation access to save thoughts to Apple Notes.</string>
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
rm -f "ThoughtCapture-v${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "ThoughtCapture-v${VERSION}.zip"

SIZE=$(du -h "ThoughtCapture-v${VERSION}.zip" | cut -f1)
echo ""
echo "=== Done ==="
echo "  ThoughtCapture-v${VERSION}.zip ($SIZE)"
echo ""
echo "Upload to GitHub: gh release create v${VERSION} ThoughtCapture-v${VERSION}.zip --title 'v${VERSION}' --notes 'Initial release'"
