#!/usr/bin/env bash
# Build update-manifest.json for a release and sign it (shared/spec/UPDATE.md).
#
#   scripts/make-update-manifest.sh <tag> <dist-dir> [key-path]
#
#   <tag>       release tag, e.g. v1.1.0 (must match the VERSION file)
#   <dist-dir>  directory containing the release artifacts, i.e. the names
#               the release pipeline produces:
#                 taskly-<ver>-macos-arm64.zip   taskly-<ver>-windows-x64.zip
#                 taskly-<ver>-linux-x64.tar.gz
#   <key-path>  Ed25519 private key PEM (default: $UPDATE_KEY_PATH, then
#               ~/.taskly/update-signing-key.pem)
#
# Writes update-manifest.json + manifest.sig into <dist-dir>. Runs on macOS
# and Linux (sha256sum/shasum, GNU/BSD stat are both handled).
set -euo pipefail

TAG="${1:?usage: make-update-manifest.sh <tag> <dist-dir> [key-path]}"
DIST="${2:?usage: make-update-manifest.sh <tag> <dist-dir> [key-path]}"
KEY="${3:-${UPDATE_KEY_PATH:-$HOME/.taskly/update-signing-key.pem}}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${TAG#v}"
[[ "$VERSION" == "$(tr -d '[:space:]' < "$ROOT/VERSION")" ]] || {
  echo "error: tag $TAG does not match VERSION '$(cat "$ROOT/VERSION")'" >&2; exit 1; }

MACOS_ZIP="$DIST/taskly-$VERSION-macos-arm64.zip"
WINDOWS_ZIP="$DIST/taskly-$VERSION-windows-x64.zip"
LINUX_TAR="$DIST/taskly-$VERSION-linux-x64.tar.gz"
REPO_URL="https://github.com/turinglambdaai/taskly/releases/download/$TAG"
BASE_URL="${RELEASE_ASSET_BASE_URL:-$REPO_URL}"

for artifact in "$MACOS_ZIP" "$WINDOWS_ZIP" "$LINUX_TAR"; do
  [[ -f "$artifact" ]] || { echo "error: missing $artifact" >&2; exit 1; }
done
[[ -f "$KEY" ]] || { echo "error: missing signing key $KEY (see scripts/update-keys.sh)" >&2; exit 1; }

# sha256 helper: macOS ships shasum, Linux CI ships sha256sum.
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
size_of() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

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

MACOS_SHA="$(sha256_file "$MACOS_ZIP")"
WINDOWS_SHA="$(sha256_file "$WINDOWS_ZIP")"
LINUX_SHA="$(sha256_file "$LINUX_TAR")"

cat > "$DIST/update-manifest.json" <<JSON
{
  "version": "$VERSION",
  "notesUrl": "$REPO_URL",
  "platforms": {
    "macos": { "url": "$BASE_URL/taskly-$VERSION-macos-arm64.zip", "sha256": "$MACOS_SHA", "size": $(size_of "$MACOS_ZIP") },
    "windows": { "url": "$BASE_URL/taskly-$VERSION-windows-x64.zip", "sha256": "$WINDOWS_SHA", "size": $(size_of "$WINDOWS_ZIP") },
    "linux": { "url": "$BASE_URL/taskly-$VERSION-linux-x64.tar.gz", "sha256": "$LINUX_SHA", "size": $(size_of "$LINUX_TAR") }
  }
}
JSON

"$OPENSSL_BIN" pkeyutl -sign -inkey "$KEY" -rawin \
  -in "$DIST/update-manifest.json" -out "$DIST/manifest.sig"

echo "wrote $DIST/update-manifest.json + manifest.sig (signed with $KEY)"
