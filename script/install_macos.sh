#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ChatGPT Codex Workspace"
EXPECTED_ID="community.localworkspace.mac"
SOURCE="$ROOT_DIR/dist-macos/$APP_NAME.app"
DESTINATION="/Applications"
while [[ $# -gt 0 ]]; do
    case "$1" in
      --source) [[ $# -ge 2 ]] || exit 2; SOURCE="$2"; shift 2 ;;
      --destination) [[ $# -ge 2 ]] || exit 2; DESTINATION="$2"; shift 2 ;;
      *) echo 'Usage: script/install_macos.sh [--source app-path] [--destination directory]' >&2; exit 2 ;;
    esac
done

validate_bundle() {
    local bundle="$1" identity
    [[ -d "$bundle" && ! -L "$bundle" ]] || { echo "Not a regular app bundle: $bundle" >&2; return 1; }
    identity="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist" 2>/dev/null)" || return 1
    [[ "$identity" == "$EXPECTED_ID" ]] || { echo "Refusing to replace an unrelated app: $bundle" >&2; return 1; }
    [[ -x "$bundle/Contents/MacOS/LocalWorkspace" ]] || return 1
}

stop_bundle() {
    local bundle="$1" pid executable attempt
    for pid in $(pgrep -x LocalWorkspace || true); do
        executable="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
        if [[ "$executable" == "$bundle/Contents/MacOS/LocalWorkspace" ]]; then
            kill -TERM "$pid"
            for attempt in {1..50}; do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.1
            done
            if kill -0 "$pid" 2>/dev/null; then
                echo "Please quit this app before updating: $bundle" >&2
                return 1
            fi
        fi
    done
}

validate_bundle "$SOURCE"
codesign --verify --deep --strict "$SOURCE"
[[ -d "$DESTINATION" && -w "$DESTINATION" ]] || {
    echo "Destination directory is missing or not writable: $DESTINATION" >&2
    exit 1
}
SOURCE="$(cd "$SOURCE" && pwd -P)"
DESTINATION="$(cd "$DESTINATION" && pwd -P)"
TARGET="$DESTINATION/$APP_NAME.app"
LEGACY_TARGET="$DESTINATION/Local Workspace.app"
MIGRATE_LEGACY=0
[[ "$SOURCE" != "$TARGET" ]] || { echo "The app is already at the destination." >&2; exit 1; }
if [[ -e "$TARGET" || -L "$TARGET" ]]; then validate_bundle "$TARGET"; fi
if [[ -e "$LEGACY_TARGET" || -L "$LEGACY_TARGET" ]]; then
    if validate_bundle "$LEGACY_TARGET"; then MIGRATE_LEGACY=1
    else echo "Preserving unrelated legacy-named app: $LEGACY_TARGET" >&2
    fi
fi

# Copy beside the target, so both renames stay on the same filesystem.
INSTALL_STAGE="$(mktemp -d "$DESTINATION/.local-workspace-update.XXXXXX")"
PREVIOUS="$INSTALL_STAGE/previous.app"
LEGACY_PREVIOUS="$INSTALL_STAGE/legacy.app"
STAGED="$INSTALL_STAGE/$APP_NAME.app"
REPLACED=0
cleanup() {
    local status=$?
    if [[ "$status" -ne 0 ]]; then
        if [[ "$REPLACED" == 1 && -e "$TARGET" ]]; then mv "$TARGET" "$INSTALL_STAGE/failed.app" || return; fi
        if [[ -d "$PREVIOUS" ]]; then
            if ! mv "$PREVIOUS" "$TARGET"; then
                echo "Could not restore the previous app. It is preserved at: $PREVIOUS" >&2
                return
            fi
        fi
        if [[ -d "$LEGACY_PREVIOUS" ]]; then
            if ! mv "$LEGACY_PREVIOUS" "$LEGACY_TARGET"; then
                echo "Could not restore the legacy app. It is preserved at: $LEGACY_PREVIOUS" >&2
                return
            fi
        fi
    fi
    rm -rf "$INSTALL_STAGE"
}
trap cleanup EXIT
ditto "$SOURCE" "$STAGED"
validate_bundle "$STAGED"
codesign --verify --deep --strict "$STAGED"
# Recheck after copying in case the destination changed while staging.
if [[ -e "$TARGET" || -L "$TARGET" ]]; then validate_bundle "$TARGET"; fi
if [[ "$MIGRATE_LEGACY" == 1 ]]; then validate_bundle "$LEGACY_TARGET"; fi
stop_bundle "$TARGET"
if [[ "$MIGRATE_LEGACY" == 1 ]]; then stop_bundle "$LEGACY_TARGET"; fi
if [[ -d "$TARGET" ]]; then mv "$TARGET" "$PREVIOUS"; fi
if [[ "$MIGRATE_LEGACY" == 1 ]]; then mv "$LEGACY_TARGET" "$LEGACY_PREVIOUS"; fi
REPLACED=1
mv "$STAGED" "$TARGET"
codesign --verify --deep --strict "$TARGET"
echo "Installed: $TARGET"
