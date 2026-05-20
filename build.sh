#!/bin/bash
# Build ThoughtCapture.app from source
# Uses persistent "ThoughtCapture Dev" certificate so Accessibility permission
# survives across rebuilds (TCC matches by certificate identity, not CDHash).
set -e
cd "$(dirname "$0")"

APP="ThoughtCapture.app"
BINARY="$APP/Contents/MacOS/ThoughtCapture"
SIGNING_ID="ThoughtCapture Dev"

# Verify signing identity exists
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGNING_ID"; then
    echo "ERROR: Signing identity '$SIGNING_ID' not found."
    echo "Run setup_cert.sh first to create the code signing certificate."
    exit 1
fi

# Create app bundle structure
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Write Info.plist
cat > "$APP/Contents/Info.plist" << 'EOF'
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

# Copy icon
cp -f bubbleicon.png "$APP/Contents/Resources/" 2>/dev/null || true

# Compile
echo "Compiling..."
swiftc ThoughtCaptureHotkey.swift \
    -o "$BINARY" \
    -framework Cocoa \
    -framework Carbon

# Sign with persistent certificate (NOT adhoc)
echo "Signing with '$SIGNING_ID'..."
codesign --force --sign "$SIGNING_ID" "$APP"

echo ""
echo "✓ Built $APP (signed with $SIGNING_ID)"
echo "  Accessibility permission will persist across rebuilds."
echo ""
echo "To deploy: ./deploy.sh"
