#!/bin/bash
# A local, separately identified preview. Never replaces /Applications or shares
# its preferences; the built-in local check also uses an isolated state directory.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
PREVIEW="$ROOT_DIR/dist-macos/ChatGPT Codex Workspace Preview.app"
PREVIEW_ID="community.localworkspace.mac.preview"
if [[ -e "$PREVIEW" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PREVIEW/Contents/Info.plist")" == "$PREVIEW_ID" ]] || exit 1
    for pid in $(pgrep -x LocalWorkspace || true); do
        if [[ "$(ps -p "$pid" -o comm=)" == "$PREVIEW/Contents/MacOS/LocalWorkspace" ]]; then
            echo 'Quit the preview app before rebuilding it. The installed app can keep running.' >&2
            exit 1
        fi
    done
fi
./scripts/build_and_run.sh --build-only
STAGE="$(mktemp -d "$ROOT_DIR/dist-macos/.preview-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$ROOT_DIR/dist-macos/ChatGPT Codex Workspace.app" "$STAGE/Preview.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PREVIEW_ID" "$STAGE/Preview.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName ChatGPT Codex Workspace Preview' "$STAGE/Preview.app/Contents/Info.plist"
./scripts/sign_macos.sh "$STAGE/Preview.app"
if [[ -e "$PREVIEW" ]]; then mv "$PREVIEW" "$STAGE/Previous.app"; fi
mv "$STAGE/Preview.app" "$PREVIEW"
echo "Local preview: $PREVIEW"
