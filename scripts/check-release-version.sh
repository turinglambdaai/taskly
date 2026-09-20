#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
TAG="${1:-}"

fail() {
  echo "release preflight: $*" >&2
  exit 1
}

[[ -n "$VERSION" ]] || fail "VERSION is empty"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] || \
  fail "VERSION '$VERSION' is not a supported semantic version"

if [[ -n "$TAG" ]]; then
  TAG_VERSION="${TAG#v}"
  [[ "$TAG_VERSION" == "$VERSION" ]] || \
    fail "tag '$TAG' does not match VERSION '$VERSION'"
fi

WINDOWS_VERSION="$(sed -n 's:.*<Version>\([^<]*\)</Version>.*:\1:p' "$ROOT/apps/windows/Taskly/Taskly.csproj" | head -n1 | tr -d '[:space:]')"
[[ "$WINDOWS_VERSION" == "$VERSION" ]] || \
  fail "Windows version '$WINDOWS_VERSION' does not match VERSION '$VERSION'"

LINUX_VERSION="$(sed -n "s/^[[:space:]]*version:[[:space:]]*'\([^']*\)'.*/\1/p" "$ROOT/apps/linux/meson.build" | head -n1 | tr -d '[:space:]')"
[[ "$LINUX_VERSION" == "$VERSION" ]] || \
  fail "Linux version '$LINUX_VERSION' does not match VERSION '$VERSION'"

grep -q 'VERSION_FILE="../../VERSION"' "$ROOT/apps/macos/scripts/make-app.sh" || \
  fail "macOS packaging script is not wired to the root VERSION file"

echo "release preflight: version $VERSION is aligned across platforms"
