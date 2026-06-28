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

## Configuration

All settings are in the menu bar → **Settings**:

- **Storage** — Obsidian Vault folder or Apple Notes
- **AI Quick Answer** — DeepSeek API key
- **Hotkeys** — modifier + key for each action

## License

MIT
