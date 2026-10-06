#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP="dist-macos/ChatGPT Codex Workspace.app"
# Package the current checkout, not a possibly stale app from an earlier build.
./script/build_and_run.sh --build-only
codesign --verify --deep --strict "$APP"
ARCH="$(lipo -archs "$APP/Contents/MacOS/LocalWorkspace")"
case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "Unsupported package architecture: $ARCH" >&2; exit 1 ;;
esac
for binary in workspace-server workspace-launcher tunnel-client; do
    [[ "$(lipo -archs "$APP/Contents/Resources/Backend/$binary")" == "$ARCH" ]] || {
        echo "Architecture mismatch: $binary" >&2; exit 1;
    }
done
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/ChatGPT Codex Workspace.app"
cp README.macos.md "$STAGE/使用说明.md"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname 'ChatGPT Codex Workspace' -srcfolder "$STAGE" -format UDZO -ov "dist-macos/ChatGPT-Codex-Workspace-$VERSION-$ARCH.dmg"
ditto -c -k --keepParent "$APP" "dist-macos/ChatGPT-Codex-Workspace-$VERSION-$ARCH.zip"
(
    cd dist-macos
    shasum -a 256 "ChatGPT-Codex-Workspace-$VERSION-$ARCH.dmg" "ChatGPT-Codex-Workspace-$VERSION-$ARCH.zip" > SHA256SUMS.txt
)
