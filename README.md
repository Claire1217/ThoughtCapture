# ThoughtCapture

A lightweight macOS menu bar app for capturing fleeting thoughts. Press a hotkey anywhere, type your thought, and it's saved to your Obsidian vault or Apple Notes.

## Features

- **Global hotkey** — capture thoughts from any app without switching windows
- **AI Quick Answer** — type `/` followed by a question to get an instant AI answer (powered by DeepSeek)
- **Context-aware** — automatically captures selected text and browser URL as context
- **Screenshot capture** — annotate screenshots with thoughts
- **Obsidian or Apple Notes** — choose where to save

## Install

### Download (recommended)

1. Download the latest `.zip` from [Releases](https://github.com/Claire1217/ThoughtCapture/releases)
2. Unzip and move `ThoughtCapture.app` to `/Applications`
3. **Bypass Gatekeeper** (required for unsigned apps): right-click the app → **Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ThoughtCapture.app
   ```
4. **System Settings → Privacy & Security → Accessibility** → enable ThoughtCapture

Or one-liner install:
```bash
cd /tmp && curl -LOsS "$(curl -s https://api.github.com/repos/Claire1217/ThoughtCapture/releases/latest | grep browser_download_url | cut -d'"' -f4)" && unzip -oq ThoughtCapture-*.zip -d /Applications && xattr -dr com.apple.quarantine /Applications/ThoughtCapture.app && open /Applications/ThoughtCapture.app
```

### Build from source (for developers)

Requires macOS 12+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/Claire1217/ThoughtCapture.git
cd ThoughtCapture
./deploy.sh
```

For frequent rebuilds without re-granting Accessibility each time:
```bash
./setup_cert.sh   # one-time: creates a persistent signing certificate
./build.sh        # uses the certificate so TCC permission survives rebuilds
```

### First launch

1. **System Settings → Privacy & Security → Accessibility** → enable ThoughtCapture
2. Right-click the **TC** menu bar icon → **Settings** → choose your save folder
3. (Optional) Paste a [DeepSeek API key](https://platform.deepseek.com) to enable `/` AI answers

## Usage

| Action | Default Hotkey |
|--------|---------------|
| Capture thought | ⌥T |
| Screenshot + comment | ⌥R |

- Type your thought and press **Enter** to save
- Start with `/` to ask AI a question (answer appears inline)
- Select text in any app before pressing the hotkey to include it as context
- Hotkeys are configurable in Settings

## File Structure

Thoughts are saved as daily Markdown files:

```
your-folder/
  2026-06-29/
    Thoughts.md        # all thoughts for the day
    attachments/       # screenshots
  2026-06-30/
    Thoughts.md
```

## Obsidian Styling

The custom callout styles (colored thought cards with sparkle icon) are **installed automatically** when you save Settings with the Obsidian backend. If Obsidian is already open, close and reopen it to load the new snippet.

If you prefer to install manually: copy `thought-cards.css` to `.obsidian/snippets/`, then enable it in Obsidian Settings → Appearance → CSS snippets.

## CLI Configuration

All settings are accessible via `defaults write`, useful for scripted or AI-agent setup:

```bash
# Storage — path to the folder where thoughts are saved
defaults write com.thoughtcapture.app vaultPath "/path/to/obsidian-vault/01_daily"
defaults write com.thoughtcapture.app storageBackend "obsidian"  # or "notes"

# AI Quick Answer — DeepSeek API key (enables / commands)
defaults write com.thoughtcapture.app llmApiKey "sk-your-key"

# Restart app to apply
killall ThoughtCapture; open /Applications/ThoughtCapture.app
```

## Agent Installation

If you are an AI coding agent (Claude Code, Cursor, etc.) helping a user install ThoughtCapture, run the following commands in order:

```bash
# 1. Install
curl -fsSL https://raw.githubusercontent.com/Claire1217/ThoughtCapture/main/install.sh | bash

# 2. Configure (substitute real values)
defaults write com.thoughtcapture.app vaultPath "/absolute/path/to/obsidian-folder"
defaults write com.thoughtcapture.app storageBackend "obsidian"   # or "notes"
defaults write com.thoughtcapture.app llmApiKey "sk-xxx"          # optional, for /AI

# 3. Restart to apply config
killall ThoughtCapture 2>/dev/null; open /Applications/ThoughtCapture.app
```

**You cannot automate this step** — the user must do it manually:
> System Settings → Privacy & Security → Accessibility → enable ThoughtCapture

To verify installation worked:
```bash
# Check app is running
pgrep -x ThoughtCapture && echo "running" || echo "not running"

# Check config
defaults read com.thoughtcapture.app vaultPath 2>/dev/null
defaults read com.thoughtcapture.app storageBackend 2>/dev/null
```

## License

MIT
