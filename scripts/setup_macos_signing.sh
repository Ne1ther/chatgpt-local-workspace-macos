#!/bin/bash
# One local identity survives builds. Never change global certificate trust or password ACLs.
set -euo pipefail
CONFIG_DIR="$HOME/Library/Application Support/ChatGPT Codex Workspace/Build"
CONFIG="$CONFIG_DIR/signing-identity.txt"
if [[ -f "$CONFIG" ]]; then
    IDENTITY="$(cat "$CONFIG")"
    [[ "$IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]] || { echo 'Invalid local signing configuration.' >&2; exit 1; }
    security find-identity -p codesigning | grep -Fi "$IDENTITY" >/dev/null || { echo 'The configured signing key is missing. Restore it instead of silently changing identity.' >&2; exit 1; }
    echo 'Local signing identity is already configured.'
    exit 0
fi
umask 077
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/workspace-signing.XXXXXX")"
cleanup() {
    node -e 'const fs=require("node:fs"),path=require("node:path");const p=process.argv[1];if(!/^workspace-signing\.[A-Za-z0-9]+$/.test(path.basename(p))||fs.lstatSync(p).isSymbolicLink())throw Error("Unexpected signing temp path");fs.rmSync(p,{recursive:true})' "$STAGE"
}
trap cleanup EXIT
KEYCHAIN="$(security default-keychain -d user | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//')"
[[ -f "$KEYCHAIN" ]] || { echo 'No user keychain is available.' >&2; exit 1; }
# Recover a configured identity if only its public fingerprint file was removed.
EXISTING="$(security find-identity -p codesigning "$KEYCHAIN" | awk -F'"' '$2 == "ChatGPT Codex Workspace Local Build" { split($1, fields, " "); print fields[2] }' | sort -u)"
if [[ -n "$EXISTING" ]]; then
    [[ "$EXISTING" =~ ^[0-9A-Fa-f]{40}$ ]] || { echo 'Multiple local signing identities found; choose one explicitly instead of replacing them.' >&2; exit 1; }
    IDENTITY="$EXISTING"
else
cat > "$STAGE/openssl.cnf" <<'EOF'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=ChatGPT Codex Workspace Local Build
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 -config "$STAGE/openssl.cnf" -keyout "$STAGE/key.pem" -out "$STAGE/cert.pem" 2> "$STAGE/openssl.log"
/usr/bin/openssl rsa -in "$STAGE/key.pem" -out "$STAGE/signing-key.pem" 2>> "$STAGE/openssl.log"
IDENTITY="$(/usr/bin/openssl x509 -in "$STAGE/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//;s/://g')"
security import "$STAGE/cert.pem" -k "$KEYCHAIN" -t cert -f pemseq
# Non-extractable signing key; codesign is the only pre-authorized client.
if ! security import "$STAGE/signing-key.pem" -k "$KEYCHAIN" -t priv -f openssl -x -T /usr/bin/codesign; then
    security delete-certificate -Z "$IDENTITY" "$KEYCHAIN"
    exit 1
fi
fi
cp /usr/bin/true "$STAGE/probe"
codesign --force --timestamp=none --sign "$IDENTITY" --keychain "$KEYCHAIN" --identifier community.localworkspace.signing-probe "$STAGE/probe"
codesign --verify --strict "$STAGE/probe"
mkdir -p "$CONFIG_DIR"
printf '%s\n' "$IDENTITY" > "$CONFIG"
echo 'Stable local signing configured. Future builds reuse this identity.'
echo 'This local certificate does not provide Developer ID notarization.'
