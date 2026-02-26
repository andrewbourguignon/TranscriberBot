# IGTranscriber

Simple macOS app to:

- choose an Instagram video file from anywhere on disk
- paste an Instagram reel/post link
- transcribe its audio to text (Apple Speech Recognition)
- copy transcript to clipboard
- save transcript to a `.txt` file

## Run locally

```bash
swift run
```

## Build a DMG

```bash
chmod +x scripts/build_dmg.sh
./scripts/build_dmg.sh
```

Output:

- `dist/IGTranscriber.dmg`

`build_dmg.sh` will bundle `yt-dlp` into the app automatically if `yt-dlp` is installed on your Mac.
You can also point to a specific binary:

```bash
YTDLP_PATH=/path/to/yt-dlp ./scripts/build_dmg.sh
```

For a truly standalone DMG, use the official standalone macOS `yt-dlp` binary (not the Homebrew wrapper script).
The build script can download it for you:

```bash
AUTO_DOWNLOAD_YTDLP_STANDALONE=1 ./scripts/build_dmg.sh
```

## Notes

- First run will ask for Speech Recognition permission.
- Video files are chosen with a picker; no fixed local storage path is required.
- Instagram link mode downloads to a temporary folder and removes it after transcription.
- Instagram link mode uses `yt-dlp` (bundled into the app if available when you build the DMG).
- Homebrew `yt-dlp` may be a Python wrapper script and is not truly standalone when copied by itself.
- Private/login-protected Instagram posts may fail unless `yt-dlp` has access (cookies/auth).
- Transcript quality depends on the audio and macOS Speech Recognition availability for your language.
