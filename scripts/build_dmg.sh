#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="IGTranscriber"
BUILD_DIR="$ROOT_DIR/.build-release"
STAGING_DIR="$BUILD_DIR/staging"
APP_DIR="$STAGING_DIR/$APP_NAME.app"
DMG_DIR="$BUILD_DIR/dmg"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
YTDLP_STANDALONE_URL_DEFAULT="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

is_python_wrapper_ytdlp() {
  local candidate="$1"
  [[ -f "$candidate" ]] || return 1

  local first_line=""
  IFS= read -r first_line < "$candidate" || true
  [[ "$first_line" == "#!"*python* ]] || return 1

  grep -q "yt_dlp" "$candidate" 2>/dev/null
}

download_standalone_ytdlp() {
  local destination="$1"
  local url="${YTDLP_STANDALONE_URL:-$YTDLP_STANDALONE_URL_DEFAULT}"

  echo "Downloading standalone yt-dlp from: $url" >&2

  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --output "$destination" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$destination" "$url"
  else
    echo "Error: curl or wget is required to download standalone yt-dlp." >&2
    return 1
  fi

  chmod +x "$destination"
}

resolve_ytdlp_for_bundle() {
  local requested_path="${YTDLP_PATH:-}"
  local auto_download="${AUTO_DOWNLOAD_YTDLP_STANDALONE:-0}"
  local candidate=""
  local downloaded="$BUILD_DIR/yt-dlp_macos"

  if [[ -n "$requested_path" ]]; then
    candidate="$requested_path"
  else
    candidate="$(command -v yt-dlp || true)"
  fi

  if [[ -z "$candidate" ]]; then
    if [[ "$auto_download" == "1" ]]; then
      rm -f "$downloaded"
      download_standalone_ytdlp "$downloaded"
      printf '%s\n' "$downloaded"
      return 0
    fi
    return 0
  fi

  if [[ ! -x "$candidate" ]]; then
    echo "Error: YTDLP_PATH is not executable: $candidate" >&2
    return 1
  fi

  if is_python_wrapper_ytdlp "$candidate"; then
    if [[ "$auto_download" == "1" ]]; then
      rm -f "$downloaded"
      download_standalone_ytdlp "$downloaded"
      printf '%s\n' "$downloaded"
      return 0
    fi

    cat >&2 <<EOF
Error: Detected a Python-wrapper yt-dlp at:
  $candidate

Copying this file into the app is NOT standalone (it depends on Homebrew Python paths).

Use one of these options:
  1) Auto-download the official standalone binary during the build:
     AUTO_DOWNLOAD_YTDLP_STANDALONE=1 ./scripts/build_dmg.sh

  2) Download the official standalone binary yourself and point the script to it:
     YTDLP_PATH=/absolute/path/to/yt-dlp_macos ./scripts/build_dmg.sh
EOF
    return 1
  fi

  printf '%s\n' "$candidate"
}

mkdir -p "$BUILD_DIR" "$STAGING_DIR" "$DMG_DIR" "$ROOT_DIR/dist"

echo "Building release binary..."
swift build -c release --package-path "$ROOT_DIR"

BIN_PATH="$ROOT_DIR/.build/release/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Expected binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

RESOLVED_YTDLP_PATH=""
if ! RESOLVED_YTDLP_PATH="$(resolve_ytdlp_for_bundle)"; then
  exit 1
fi

if [[ -n "$RESOLVED_YTDLP_PATH" && -x "$RESOLVED_YTDLP_PATH" ]]; then
  cp "$RESOLVED_YTDLP_PATH" "$APP_DIR/Contents/Resources/yt-dlp"
  chmod +x "$APP_DIR/Contents/Resources/yt-dlp"
  echo "Bundled standalone yt-dlp: $RESOLVED_YTDLP_PATH"
else
  echo "Warning: yt-dlp not found. Instagram link mode will require yt-dlp installed on the user's Mac."
fi

echo "Preparing DMG contents..."
rm -rf "$DMG_DIR"/*
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

rm -f "$DMG_PATH"
echo "Creating DMG..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Done: $DMG_PATH"
