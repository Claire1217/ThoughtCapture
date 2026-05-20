#!/bin/bash
set -e
cd "$(dirname "$0")"

SIGNING_ID="ThoughtCapture Dev"

echo "=== Building ==="
swiftc ThoughtCaptureHotkey.swift -o ThoughtCaptureHotkey -framework Cocoa -framework Carbon

echo "=== Stopping old instances ==="
killall ThoughtCapture 2>/dev/null || true
sleep 0.5

echo "=== Deploying ==="
mkdir -p /Applications/ThoughtCapture.app/Contents/MacOS
mkdir -p /Applications/ThoughtCapture.app/Contents/Resources
cp ThoughtCaptureHotkey /Applications/ThoughtCapture.app/Contents/MacOS/ThoughtCapture
cp bubbleicon.png /Applications/ThoughtCapture.app/Contents/Resources/ 2>/dev/null || true

# Write Info.plist
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

# Sign with persistent certificate
echo "=== Signing ==="
codesign --force --sign "$SIGNING_ID" /Applications/ThoughtCapture.app

echo "=== Launching ==="
open /Applications/ThoughtCapture.app
sleep 1

# Verify AX status
echo ""
echo "=== Status ==="
pgrep -c ThoughtCapture | xargs -I{} echo "Running instances: {}"
echo ""
echo "✓ Deployed with '$SIGNING_ID' certificate."
echo "  Accessibility permission persists across rebuilds."
echo ""
echo "If this is the FIRST deploy with this certificate:"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  → remove old ThoughtCapture entry → add /Applications/ThoughtCapture.app"
