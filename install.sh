#!/bin/bash
# ThoughtCapture one-shot installer
# Usage: curl -fsSL https://raw.githubusercontent.com/Claire1217/ThoughtCapture/main/install.sh | bash
#
# Optional env vars (set before piping):
#   TC_VAULT_PATH   — Obsidian folder path, e.g. ~/Documents/vault/01_daily
#   TC_BACKEND      — "obsidian" (default) or "notes"
#   TC_API_KEY      — DeepSeek API key for /AI answers
set -e

echo "[ThoughtCapture] Downloading latest release..."
DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/Claire1217/ThoughtCapture/releases/latest \
  | grep browser_download_url | head -1 | cut -d'"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "ERROR: Could not find release download URL."
    exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$DOWNLOAD_URL" -o "$TMPDIR/ThoughtCapture.zip"

echo "[ThoughtCapture] Installing to /Applications..."
killall ThoughtCapture 2>/dev/null || true
unzip -oq "$TMPDIR/ThoughtCapture.zip" -d /Applications

echo "[ThoughtCapture] Removing quarantine flag..."
xattr -dr com.apple.quarantine /Applications/ThoughtCapture.app 2>/dev/null || true

# Apply configuration if env vars are set
if [ -n "$TC_VAULT_PATH" ]; then
    echo "[ThoughtCapture] Setting vault path: $TC_VAULT_PATH"
    defaults write com.thoughtcapture.app vaultPath "$TC_VAULT_PATH"
fi
if [ -n "$TC_BACKEND" ]; then
    defaults write com.thoughtcapture.app storageBackend "$TC_BACKEND"
fi
if [ -n "$TC_API_KEY" ]; then
    echo "[ThoughtCapture] Setting API key"
    defaults write com.thoughtcapture.app llmApiKey "$TC_API_KEY"
fi

echo "[ThoughtCapture] Launching..."
open /Applications/ThoughtCapture.app

echo ""
echo "✓ ThoughtCapture installed."
echo ""
echo "MANUAL STEP REQUIRED:"
echo "  System Settings → Privacy & Security → Accessibility → enable ThoughtCapture"
echo ""
if [ -z "$TC_VAULT_PATH" ]; then
    echo "Then: right-click TC menu bar icon → Settings → choose save folder"
fi
