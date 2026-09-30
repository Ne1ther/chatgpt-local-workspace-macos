#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP="dist-macos/ChatGPT Codex Workspace.app"
[[ -d "$APP" ]] || ./script/build_and_run.sh --build-only
codesign --verify --deep --strict "$APP"
ARCH="$(uname -m)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/ChatGPT Codex Workspace.app"
cp README.macos.md "$STAGE/使用说明.md"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname 'ChatGPT Codex Workspace' -srcfolder "$STAGE" -format UDZO -ov "dist-macos/ChatGPT-Codex-Workspace-$VERSION-$ARCH.dmg"
ditto -c -k --keepParent "$APP" "dist-macos/ChatGPT-Codex-Workspace-$VERSION-$ARCH.zip"
shasum -a 256 "dist-macos/ChatGPT-Codex-Workspace-$VERSION-$ARCH.dmg" "dist-macos/ChatGPT-Codex-Workspace-$VERSION-$ARCH.zip" > dist-macos/SHA256SUMS.txt
