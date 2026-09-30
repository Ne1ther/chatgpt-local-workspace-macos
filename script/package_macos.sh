#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP="dist-macos/Local Workspace.app"
[[ -d "$APP" ]] || ./script/build_and_run.sh --build-only
codesign --verify --deep --strict "$APP"
ARCH="$(uname -m)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Local Workspace.app"
cp README.macos.md "$STAGE/使用说明.md"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname 'Local Workspace' -srcfolder "$STAGE" -format UDZO -ov "dist-macos/Local-Workspace-$VERSION-$ARCH.dmg"
ditto -c -k --keepParent "$APP" "dist-macos/Local-Workspace-$VERSION-$ARCH.zip"
shasum -a 256 "dist-macos/Local-Workspace-$VERSION-$ARCH.dmg" "dist-macos/Local-Workspace-$VERSION-$ARCH.zip" > dist-macos/SHA256SUMS.txt
