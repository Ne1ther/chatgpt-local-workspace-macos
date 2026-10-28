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
HELPER="$APP/Contents/Helpers/workspace-credentials"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$IDENTITY" != - ]]; then
    /usr/libexec/PlistBuddy -c 'Set :LWCredentialHelperRequired true' "$APP/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Add :LWCredentialHelperRequired bool true' "$APP/Contents/Info.plist"
else
    /usr/libexec/PlistBuddy -c 'Set :LWCredentialHelperRequired false' "$APP/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Add :LWCredentialHelperRequired bool false' "$APP/Contents/Info.plist"
    # A preview copied from a signed build must not retain a helper for another identity.
    if [[ -e "$HELPER" ]]; then node -e 'require("node:fs").unlinkSync(process.argv[1])' "$HELPER"; fi
fi
for binary in "$BACKEND/"*.dylib "$BACKEND/workspace-server" "$BACKEND/workspace-launcher" "$BACKEND/tunnel-client"; do
    codesign "${SIGN_ARGS[@]}" --identifier "$BUNDLE_ID.$(basename "$binary")" "$binary"
done
if [[ "$IDENTITY" != - ]]; then
    # Obtain the real leaf certificate for either a local or Developer ID identity.
    codesign "${SIGN_ARGS[@]}" --options runtime "$APP"
    STAGE="$(mktemp -d "${TMPDIR:-/tmp}/workspace-helper-signing.XXXXXX")"
    trap 'node -e '\''const fs=require("node:fs"),path=require("node:path"),p=process.argv[1];if(!/^workspace-helper-signing\.[A-Za-z0-9]+$/.test(path.basename(p))||fs.lstatSync(p).isSymbolicLink())throw Error("Unexpected signing temp path");fs.rmSync(p,{recursive:true})'\'' "$STAGE"' EXIT
    codesign -d --extract-certificates="$STAGE/cert" "$APP"
    CERT_SHA1="$(/usr/bin/openssl x509 -inform DER -in "$STAGE/cert0" -noout -fingerprint -sha1 | sed 's/.*=//;s/://g')"
    [[ "$CERT_SHA1" =~ ^[0-9A-Fa-f]{40}$ ]] || exit 1
    mkdir -p "$APP/Contents/Helpers"
    MACOS_MIN_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
    xcrun clang -O2 "-mmacosx-version-min=$MACOS_MIN_VERSION" "-DWORKSPACE_CERT_SHA1=\"$CERT_SHA1\"" "$ROOT/macos/credential_helper.c" -framework Security -framework CoreFoundation -o "$HELPER"
    codesign "${SIGN_ARGS[@]}" --options runtime --identifier "$BUNDLE_ID.credentials" "$HELPER"
    codesign "${SIGN_ARGS[@]}" --options runtime "$APP"
else
    codesign "${SIGN_ARGS[@]}" "$APP"
fi
codesign --verify --deep --strict "$APP"
