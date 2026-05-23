# ThoughtCapture

A macOS menubar app for zero-friction thought capture. Press **Option+T** anywhere to jot down an idea, ask AI a question, or annotate what you're reading. Everything saves to your Obsidian vault or Apple Notes.

## Features

- **Instant capture** - Option+T opens a floating input anywhere on screen
- **Context-aware** - automatically grabs selected text and current app/URL
- **AI questions** - prefix with `/` to ask AI (uses any OpenAI-compatible API)
- **Screenshot + comment** - Option+R to capture a screen region and annotate it
- **Floating bubble** - persistent orb shows your thought history on hover
- **Paper reading** - `/pr` generates structured paper notes from arXiv URLs

## Quick Start

### 1. Configure

```bash
cp .env.example .env
# Edit .env with your settings:
#   VAULT_PATH  - path to your Obsidian vault
#   VAULT_NAME  - vault name (as shown in Obsidian sidebar)
#   LLM_API_KEY - your API key (DeepSeek, OpenAI, etc.)
```

**Don't use Obsidian?** Set `STORAGE_BACKEND=notes` to save to Apple Notes instead.

### 2. Start the server

```bash
python3 server.py
```

### 3. Build and run the app

```bash
# First time: create the app bundle
mkdir -p /Applications/ThoughtCapture.app/Contents/MacOS
cp Info.plist /Applications/ThoughtCapture.app/Contents/

# Build and deploy
./deploy.sh
```

### 4. Grant permissions

On first launch, go to **System Preferences > Security & Privacy > Privacy > Accessibility** and add ThoughtCapture.app. This enables selected text capture.

## Usage

| Shortcut | Action |
|----------|--------|
| **Option+T** | Open capture panel |
| **Option+R** | Screenshot + comment |
| **Enter** | Save thought |
| **/question** | Ask AI |
| **/pr** | Read paper at current URL |
| **/plan** | Generate daily plan |
| **Esc** | Close panel |

## Requirements

- macOS 12+
- Python 3.8+
- Xcode Command Line Tools (`xcode-select --install`)
- Obsidian (optional - can use Apple Notes instead)
- An OpenAI-compatible API key (optional - needed for AI features)

## Architecture

```
Option+T  -->  Swift menubar app  -->  HTTP POST  -->  Python server  -->  Obsidian / Notes
                (ThoughtCapture)       localhost:19876   (server.py)        (your vault)
```

The Swift app handles the UI (floating panel, bubble, hotkeys). The Python server handles routing, LLM calls, and file storage. They communicate over localhost HTTP.

## License

MIT
