#!/usr/bin/env bash
# Build update-manifest.json for a release and sign it (shared/spec/UPDATE.md).
#
#   scripts/make-update-manifest.sh <tag> <dist-dir> [key-path]
#
#   <tag>       release tag, e.g. v1.0.1 (must match the VERSION file)
#   <dist-dir>  directory containing the release artifacts:
#                 Taskly-v<tag>-macos.zip  Taskly-v<tag>-linux-x64.tar.gz
#   <key-path>  Ed25519 private key PEM (default: $UPDATE_KEY_PATH, then
#               ~/.taskly/update-signing-key.pem)
#
# Writes update-manifest.json + manifest.sig into <dist-dir>.
set -euo pipefail

TAG="${1:?usage: make-update-manifest.sh <tag> <dist-dir> [key-path]}"
DIST="${2:?usage: make-update-manifest.sh <tag> <dist-dir> [key-path]}"
KEY="${3:-${UPDATE_KEY_PATH:-$HOME/.taskly/update-signing-key.pem}}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${TAG#v}"
[[ "$VERSION" == "$(tr -d '[:space:]' < "$ROOT/VERSION")" ]] || {
  echo "error: tag $TAG does not match VERSION '$(cat "$ROOT/VERSION")'" >&2; exit 1; }

MACOS_ZIP="$DIST/Taskly-$TAG-macos.zip"
LINUX_TAR="$DIST/Taskly-$TAG-linux-x64.tar.gz"
REPO_URL="https://github.com/turinglambdaai/taskly/releases/download/$TAG"
BASE_URL="${RELEASE_ASSET_BASE_URL:-$REPO_URL}"

[[ -f "$MACOS_ZIP" ]] || { echo "error: missing $MACOS_ZIP" >&2; exit 1; }
[[ -f "$LINUX_TAR" ]] || { echo "error: missing $LINUX_TAR" >&2; exit 1; }
[[ -f "$KEY" ]] || { echo "error: missing signing key $KEY (see scripts/update-keys.sh)" >&2; exit 1; }

shasum -a 256 "$MACOS_ZIP" >/dev/null 2>&1 || { echo "error: shasum unavailable" >&2; exit 1; }

# Ed25519 needs OpenSSL 3+ (macOS ships LibreSSL, which cannot do it).
OPENSSL_BIN="${OPENSSL_BIN:-}"
if [[ -z "$OPENSSL_BIN" ]]; then
  for candidate in /opt/homebrew/opt/openssl@3/bin/openssl \
                   /usr/local/opt/openssl@3/bin/openssl openssl; do
    if command -v "$candidate" >/dev/null 2>&1 \
       && "$candidate" version 2>/dev/null | grep -q "OpenSSL 3"; then
      OPENSSL_BIN="$candidate"
      break
    fi
  done
fi
[[ -n "$OPENSSL_BIN" ]] || {
  echo "error: OpenSSL 3.x required for Ed25519 (brew install openssl@3," >&2
  echo "       or set OPENSSL_BIN=/path/to/openssl)" >&2
  exit 1
}

MACOS_SHA="$(shasum -a 256 "$MACOS_ZIP" | awk '{print $1}')"
MACOS_SIZE="$(stat -f%z "$MACOS_ZIP" 2>/dev/null || stat -c%s "$MACOS_ZIP")"
LINUX_SHA="$(shasum -a 256 "$LINUX_TAR" | awk '{print $1}')"
LINUX_SIZE="$(stat -f%z "$LINUX_TAR" 2>/dev/null || stat -c%s "$LINUX_TAR")"

cat > "$DIST/update-manifest.json" <<JSON
{
  "version": "$VERSION",
  "notesUrl": "$REPO_URL",
  "platforms": {
    "macos": { "url": "$BASE_URL/Taskly-$TAG-macos.zip", "sha256": "$MACOS_SHA", "size": $MACOS_SIZE },
    "linux": { "url": "$BASE_URL/Taskly-$TAG-linux-x64.tar.gz", "sha256": "$LINUX_SHA", "size": $LINUX_SIZE }
  }
}
JSON

"$OPENSSL_BIN" pkeyutl -sign -inkey "$KEY" -rawin \
  -in "$DIST/update-manifest.json" -out "$DIST/manifest.sig"

echo "wrote $DIST/update-manifest.json + manifest.sig (signed with $KEY)"
