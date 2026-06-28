# ThoughtCapture

A lightweight macOS menu bar app for capturing fleeting thoughts. Press a hotkey anywhere, type your thought, and it's saved to your Obsidian vault or Apple Notes.

轻量 macOS 菜单栏应用，随时随地按快捷键记录灵感，自动保存到 Obsidian 或 Apple Notes。

![Obsidian demo](assets/obsidian-demo.png)

## Features / 功能

- **Global hotkey** — capture thoughts from any app without switching windows
- **AI Quick Answer** — type `/` followed by a question to get an instant AI answer (powered by DeepSeek)
- **Context-aware** — automatically captures selected text and browser URL as context
- **Screenshot capture** — annotate screenshots with thoughts
- **Obsidian or Apple Notes** — choose where to save

---

- **全局快捷键** — 在任何应用里按快捷键，无需切换窗口
- **AI 快问快答** — 输入 `/` 加问题，即时获得 AI 回答（DeepSeek 驱动）
- **上下文感知** — 自动抓取选中文本和浏览器 URL 作为上下文
- **截图标注** — 截屏后附上你的想法
- **Obsidian 或 Apple Notes** — 自由选择存储位置

## Install / 安装

### Download (recommended) / 下载安装（推荐）

1. Download the latest `.zip` from [Releases](https://github.com/Claire1217/ThoughtCapture/releases)
2. Unzip and move `ThoughtCapture.app` to `/Applications`
3. **Bypass Gatekeeper** (required for unsigned apps): right-click the app → **Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ThoughtCapture.app
   ```
4. **System Settings → Privacy & Security → Accessibility** → enable ThoughtCapture

---

1. 从 [Releases](https://github.com/Claire1217/ThoughtCapture/releases) 下载最新 `.zip`
2. 解压后将 `ThoughtCapture.app` 拖到 `/Applications`
3. **绕过 Gatekeeper**（未签名应用必须）：右键点击应用 → **打开**，或终端执行：
   ```bash
   xattr -dr com.apple.quarantine /Applications/ThoughtCapture.app
   ```
4. **系统设置 → 隐私与安全性 → 辅助功能** → 开启 ThoughtCapture

One-liner install / 一键安装：
```bash
cd /tmp && curl -LOsS "$(curl -s https://api.github.com/repos/Claire1217/ThoughtCapture/releases/latest | grep browser_download_url | cut -d'"' -f4)" && unzip -oq ThoughtCapture-*.zip -d /Applications && xattr -dr com.apple.quarantine /Applications/ThoughtCapture.app && open /Applications/ThoughtCapture.app
```

### Build from source (for developers) / 从源码构建（开发者）

Requires macOS 12+ and Xcode Command Line Tools (`xcode-select --install`).

需要 macOS 12+ 和 Xcode 命令行工具（`xcode-select --install`）。

```bash
git clone https://github.com/Claire1217/ThoughtCapture.git
cd ThoughtCapture
./deploy.sh
```

For frequent rebuilds without re-granting Accessibility each time / 频繁重新编译时免重授权限：
```bash
./setup_cert.sh   # one-time: creates a persistent signing certificate / 一次性：创建持久签名证书
./build.sh        # uses the certificate so TCC permission survives rebuilds / 用证书签名，权限不会因重编译失效
```

### First launch / 首次启动

1. **System Settings → Privacy & Security → Accessibility** → enable ThoughtCapture
2. Right-click the **TC** menu bar icon → **Settings** → choose your save folder
3. (Optional) Paste a [DeepSeek API key](https://platform.deepseek.com) to enable `/` AI answers

---

1. **系统设置 → 隐私与安全性 → 辅助功能** → 开启 ThoughtCapture
2. 右键菜单栏 **TC** 图标 → **Settings** → 选择保存文件夹
3. （可选）粘贴 [DeepSeek API key](https://platform.deepseek.com)，开启 `/` AI 问答功能

## Usage / 使用

| Action / 操作 | Default Hotkey / 默认快捷键 |
|--------|---------------|
| Capture thought / 捕捉想法 | ⌥T |
| Screenshot + comment / 截图+标注 | ⌥R |

- Type your thought and press **Enter** to save / 输入想法后按 **Enter** 保存
- Start with `/` to ask AI a question (answer appears inline) / 以 `/` 开头提问，AI 回答直接显示
- Select text in any app before pressing the hotkey to include it as context / 先选中文本再按快捷键，自动作为上下文
- Hotkeys are configurable in Settings / 快捷键可在 Settings 中自定义

## File Structure / 文件结构

Thoughts are saved as daily Markdown files / 按天保存为 Markdown 文件：

```
your-folder/
  2026-06-29/
    Thoughts.md        # all thoughts for the day / 当天所有想法
    attachments/       # screenshots / 截图
  2026-06-30/
    Thoughts.md
```

## Obsidian Styling / Obsidian 样式

The custom callout styles (colored thought cards with sparkle icon) are **installed automatically** when you save Settings with the Obsidian backend. If Obsidian is already open, close and reopen it to load the new snippet.

自定义 callout 样式（彩色卡片 + 闪光图标）会在保存 Settings（Obsidian 模式下）时**自动安装**。如果 Obsidian 已打开，关闭后重新打开即可生效。

If you prefer to install manually: copy `thought-cards.css` to `.obsidian/snippets/`, then enable it in Obsidian Settings → Appearance → CSS snippets.

手动安装：将 `thought-cards.css` 复制到 `.obsidian/snippets/`，然后在 Obsidian 设置 → 外观 → CSS 代码片段中启用。

## CLI Configuration / 命令行配置

All settings are accessible via `defaults write`, useful for scripted or AI-agent setup:

所有设置都可通过 `defaults write` 配置，适合脚本化或 AI agent 自动设置：

```bash
# Storage — path to the folder where thoughts are saved
# 存储路径 — 想法保存到的文件夹
defaults write com.thoughtcapture.app vaultPath "/path/to/obsidian-vault/01_daily"
defaults write com.thoughtcapture.app storageBackend "obsidian"  # or "notes"

# AI Quick Answer — DeepSeek API key (enables / commands)
# AI 快问快答 — DeepSeek API 密钥
defaults write com.thoughtcapture.app llmApiKey "sk-your-key"

# Restart app to apply / 重启应用生效
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
