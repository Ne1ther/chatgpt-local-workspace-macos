#!/bin/bash
set -euo pipefail
shopt -s nullglob
MODE="${1:-run}"
case "$MODE" in
  run|--build-only|--install|--verify|--debug|--logs|--telemetry) ;;
  *) echo 'Usage: scripts/build_and_run.sh [--build-only|--install|--verify|--debug|--logs|--telemetry]' >&2; exit 2 ;;
esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME="ChatGPT Codex Workspace"
APP_BUNDLE="$ROOT_DIR/dist-macos/$APP_NAME.app"
BUILD_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/local-workspace-build.XXXXXX")"
trap 'rm -rf "$BUILD_STAGE"' EXIT
STAGED_APP="$BUILD_STAGE/$APP_NAME.app"
DOTNET="$ROOT_DIR/.tools/dotnet/dotnet"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
if [[ ! -x "$DOTNET" ]]; then
    mkdir -p .tools
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o .tools/dotnet-install.sh
    bash .tools/dotnet-install.sh --channel 10.0 --install-dir .tools/dotnet --no-path
fi
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then RID="osx-arm64"; TUNNEL_ARCH="arm64"; else RID="osx-x64"; TUNNEL_ARCH="amd64"; fi
TUNNEL_VERSION="v0.0.16"
TUNNEL_DIR="$ROOT_DIR/.tools/tunnel-$TUNNEL_VERSION-$TUNNEL_ARCH"
if [[ ! -x "$TUNNEL_DIR/tunnel-client" ]]; then
    mkdir -p "$TUNNEL_DIR"
    curl -fL "https://github.com/openai/tunnel-client/releases/download/$TUNNEL_VERSION/tunnel-client-$TUNNEL_VERSION-darwin-$TUNNEL_ARCH.zip" -o "$TUNNEL_DIR/release.zip"
    if [[ "$TUNNEL_ARCH" == "arm64" ]]; then TUNNEL_SHA="a160820d45089b5253d8d671fe2a689bde0f73d78c135d1497a7b33f28a3ac62"; else TUNNEL_SHA="57b3dd73f2d042c7aeb5664681f7538078359f55538b9e048640f1df71a0c83f"; fi
    echo "$TUNNEL_SHA  $TUNNEL_DIR/release.zip" | shasum -a 256 -c -
    unzip -oq "$TUNNEL_DIR/release.zip" -d "$TUNNEL_DIR"
    chmod +x "$TUNNEL_DIR/tunnel-client"
    rm -f "$TUNNEL_DIR/release.zip"
fi
if [[ ! -d node_modules ]]; then npm ci --no-audit --no-fund; fi
if [[ ! -f src/ui/assets/macos-symbols.json || scripts/generate_ui_symbols.swift -nt src/ui/assets/macos-symbols.json ]]; then
    swift scripts/generate_ui_symbols.swift "$ROOT_DIR"
fi
npm run build:ui
"$DOTNET" publish macos/backend/WorkspaceBackend.csproj -c Release -r "$RID" -o "$BUILD_STAGE/backend" --nologo
MACOS_MIN_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' macos/Resources/Info.plist)"
xcrun clang -O2 "-mmacosx-version-min=$MACOS_MIN_VERSION" macos/launcher.c -o "$BUILD_STAGE/backend/workspace-launcher"
swift build --package-path macos -c release -j 4
SWIFT_BIN="$(swift build --package-path macos -c release --show-bin-path)/LocalWorkspace"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources/Backend" "$STAGED_APP/Contents/Resources/Licenses"
cp "$SWIFT_BIN" "$STAGED_APP/Contents/MacOS/LocalWorkspace"
cp "$BUILD_STAGE/backend/workspace-server" "$STAGED_APP/Contents/Resources/Backend/"
for library in "$BUILD_STAGE/backend/"*.dylib; do cp "$library" "$STAGED_APP/Contents/Resources/Backend/"; done
cp "$BUILD_STAGE/backend/workspace-launcher" "$STAGED_APP/Contents/Resources/Backend/"
cp src/dashboard.html "$STAGED_APP/Contents/Resources/Backend/"
DESKTOP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' macos/Resources/Info.plist)"
node -e 'const fs=require("node:fs");fs.writeFileSync(process.argv[1],JSON.stringify({core:"2.4.1",desktop:process.argv[2],tunnel:"0.0.16"})+"\n")' "$STAGED_APP/Contents/Resources/Backend/runtime-components.json" "$DESKTOP_VERSION"
cp "$TUNNEL_DIR/tunnel-client" "$STAGED_APP/Contents/Resources/Backend/"
cp LICENSE "$STAGED_APP/Contents/Resources/Licenses/Workspace-MIT.txt"
cp macos/Resources/Frontend-Licenses.txt "$STAGED_APP/Contents/Resources/Licenses/"
cp macos/Resources/Phosphor-MIT.txt "$STAGED_APP/Contents/Resources/Licenses/"
cp vendor/devspace/LICENSE "$STAGED_APP/Contents/Resources/Licenses/DevSpace-MIT.txt"
cp "$TUNNEL_DIR/LICENSE" "$STAGED_APP/Contents/Resources/Licenses/Tunnel-Apache-2.0.txt"
cp "$TUNNEL_DIR/NOTICE" "$STAGED_APP/Contents/Resources/Licenses/Tunnel-NOTICE.txt"
cp "$TUNNEL_DIR/"*-licenses.txt "$STAGED_APP/Contents/Resources/Licenses/"
cp "$ROOT_DIR/.tools/dotnet/LICENSE.txt" "$STAGED_APP/Contents/Resources/Licenses/DotNET-MIT.txt"
cp "$ROOT_DIR/.tools/dotnet/ThirdPartyNotices.txt" "$STAGED_APP/Contents/Resources/Licenses/DotNET-ThirdParty.txt"
cp macos/Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
if [[ ! -f macos/Resources/AppIcon.icns || ! -f macos/Resources/AppIcon.png || ! -f macos/Resources/MenuBarIconTemplate.png || ! -f macos/Resources/MenuBarIconTemplate@2x.png || scripts/generate_icons.swift -nt macos/Resources/AppIcon.icns || macos/Resources/Brand/InterlaceApp.png -nt macos/Resources/AppIcon.icns || macos/Resources/Brand/InterlaceMenuOptical.png -nt macos/Resources/AppIcon.icns ]]; then
    swift scripts/generate_icons.swift "$ROOT_DIR"
fi
cp macos/Resources/AppIcon.icns macos/Resources/AppIcon.png macos/Resources/MenuBarIconTemplate*.png "$STAGED_APP/Contents/Resources/"
./scripts/sign_macos.sh "$STAGED_APP"
mkdir -p "$ROOT_DIR/dist-macos"
./scripts/install_macos.sh --source "$STAGED_APP" --destination "$ROOT_DIR/dist-macos"
case "$MODE" in
  --build-only) echo "Built: $APP_BUNDLE" ;;
  --install) ./scripts/install_macos.sh; /usr/bin/open -n "/Applications/$APP_NAME.app" ;;
  --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; pgrep -x LocalWorkspace >/dev/null; echo "App launched successfully." ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/LocalWorkspace" ;;
  --logs|--telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "LocalWorkspace"' ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
