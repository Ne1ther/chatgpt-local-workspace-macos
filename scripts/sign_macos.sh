#!/bin/bash
set -euo pipefail
shopt -s nullglob
APP="${1:?Usage: scripts/sign_macos.sh path/to/Application.app}"
CONFIG="$HOME/Library/Application Support/ChatGPT Codex Workspace/Build/signing-identity.txt"
if [[ -n "${WORKSPACE_CODESIGN_IDENTITY:-}" ]]; then
    IDENTITY="$WORKSPACE_CODESIGN_IDENTITY"
elif [[ -f "$CONFIG" ]]; then
    IDENTITY="$(cat "$CONFIG")"
    [[ "$IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]] || { echo 'Invalid local signing configuration.' >&2; exit 1; }
else
    IDENTITY=-
    echo 'Using ad-hoc signing. Run scripts/setup_macos_signing.sh once to retain Keychain trust across local updates.' >&2
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
case "$BUNDLE_ID" in community.localworkspace.mac|community.localworkspace.mac.preview) ;; *) echo 'Unexpected application identity.' >&2; exit 1 ;; esac
SIGN_ARGS=(--force --timestamp=none --sign "$IDENTITY")
if [[ -n "${WORKSPACE_CODESIGN_KEYCHAIN:-}" ]]; then SIGN_ARGS+=(--keychain "$WORKSPACE_CODESIGN_KEYCHAIN"); fi
BACKEND="$APP/Contents/Resources/Backend"
for binary in "$BACKEND/"*.dylib "$BACKEND/workspace-server" "$BACKEND/workspace-launcher" "$BACKEND/tunnel-client"; do
    codesign "${SIGN_ARGS[@]}" --identifier "$BUNDLE_ID.$(basename "$binary")" "$binary"
done
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
