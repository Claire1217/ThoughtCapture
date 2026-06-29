#!/bin/bash
# Eureka one-shot installer
# Usage: curl -fsSL https://raw.githubusercontent.com/Claire1217/Eureka/main/install.sh | bash
#
# Optional env vars (set before piping):
#   TC_VAULT_PATH   — Obsidian folder path, e.g. ~/Documents/vault/01_daily
#   TC_BACKEND      — "obsidian" (default) or "notes"
#   TC_API_KEY      — DeepSeek API key for /AI answers
set -e

echo "[Eureka] Downloading latest release..."
DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/Claire1217/Eureka/releases/latest \
  | grep browser_download_url | head -1 | cut -d'"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "ERROR: Could not find release download URL."
    exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$DOWNLOAD_URL" -o "$TMPDIR/Eureka.zip"

echo "[Eureka] Installing to /Applications..."
killall Eureka 2>/dev/null || true
unzip -oq "$TMPDIR/Eureka.zip" -d /Applications

echo "[Eureka] Removing quarantine flag..."
xattr -dr com.apple.quarantine /Applications/Eureka.app 2>/dev/null || true

if [ -n "$TC_VAULT_PATH" ]; then
    echo "[Eureka] Setting vault path: $TC_VAULT_PATH"
    defaults write com.eureka.app vaultPath "$TC_VAULT_PATH"
fi
if [ -n "$TC_BACKEND" ]; then
    defaults write com.eureka.app storageBackend "$TC_BACKEND"
fi
if [ -n "$TC_API_KEY" ]; then
    echo "[Eureka] Setting API key"
    defaults write com.eureka.app llmApiKey "$TC_API_KEY"
fi

echo "[Eureka] Launching..."
open /Applications/Eureka.app

echo ""
echo "✓ Eureka installed."
echo ""
echo "MANUAL STEP REQUIRED:"
echo "  System Settings → Privacy & Security → Accessibility → enable Eureka"
echo ""
if [ -z "$TC_VAULT_PATH" ]; then
    echo "Then: right-click E! menu bar icon → Settings → choose save folder"
fi
