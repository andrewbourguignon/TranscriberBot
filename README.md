# Transcriber Bot 🤖🎬

**Universal video transcription for macOS.**

Transcriber Bot is a high-performance tool designed for content creators and researchers to turn video content into high-fidelity text. Formerly known as `IGTranscriber`, it has been expanded to support all major video platforms.

## ✨ Features
- **Universal Support**: Transcribe videos from **YouTube, TikTok, Instagram**, and direct video links.
- **Privacy First**: Uses Apple's native Speech Recognition framework directly on your Mac. No data leaves your machine for transcription.
- **Auto-Save Engine**: Automatically generates and files transcripts in `~/Downloads/Transcriptions/`.
- **Intelligent Metadata**: Includes video titles, source URLs, and timestamps in every export.
- **CLI & GUI**: Use the standalone Mac App or the `transcriber-bot-cli` for automated workflows.

## 🚀 Getting Started

### Prerequisites
- macOS 14.0 or later.
- `yt-dlp` installed (via Homebrew: `brew install yt-dlp`).

### Building from Source
```bash
# Build the App and CLI
swift build -c release

# Run the CLI
./.build/release/transcriber-bot-cli "https://..."
```

## 🛠 Usage
1. **Mac App**: Open `TranscriberBot.app`, paste a link, and hit Transcribe.
2. **CLI**: Use `transcriber-bot-cli <URL>` for instant transcription and auto-saving to your Downloads folder.

---
Part of the **AI Command Center** ecosystem.
