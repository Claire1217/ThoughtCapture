# ThoughtCapture

A lightweight macOS menu bar app for capturing fleeting thoughts. Press a hotkey anywhere, type your thought, and it's saved to your Obsidian vault or Apple Notes.

## Features

- **Global hotkey** — capture thoughts from any app without switching windows
- **/ AI Quick Answer** — type `/` followed by a question to get an instant AI answer (powered by DeepSeek)
- **Context-aware** — automatically captures selected text and browser URL as context
- **Screenshot capture** — annotate screenshots with thoughts
- **Obsidian or Apple Notes** — choose where to save

## Install

### Download (recommended)
1. Download the latest `.zip` from [Releases](https://github.com/Claire1217/ThoughtCapture/releases)
2. Unzip and drag `ThoughtCapture.app` to `/Applications`
3. Right-click the app → **Open** (first time only, to bypass unsigned app warning)

### Build from source
Requires macOS 12+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/Claire1217/ThoughtCapture.git
cd ThoughtCapture
./deploy.sh
```

After first launch:
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

## Obsidian Styling (optional)

For styled thought cards, copy `thought-cards.css` to your vault:

```bash
cp thought-cards.css /path/to/vault/.obsidian/snippets/
```

Then in Obsidian: **Settings → Appearance → CSS snippets** → enable **thought-cards**.

## Configuration

All settings are in the menu bar → **Settings**, or via CLI:

```bash
# Storage — path to the folder where thoughts are saved
defaults write com.thoughtcapture.app vaultPath "/path/to/obsidian-vault/01_daily"
defaults write com.thoughtcapture.app storageBackend "obsidian"  # or "notes"

# AI Quick Answer — DeepSeek API key (enables / commands)
defaults write com.thoughtcapture.app llmApiKey "sk-your-key"

# Restart app to apply CLI changes
killall ThoughtCapture; open /Applications/ThoughtCapture.app
```

## License

MIT
