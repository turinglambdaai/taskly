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
  # Release tags must be annotated — lightweight tags have slipped in
  # (v0.1.0, v0.1.4, v0.2.0) and the family convention requires the tag
  # message to travel with the ref.
  [[ "$(git -C "$ROOT" cat-file -t "$TAG" 2>/dev/null)" == "tag" ]] || \
    fail "tag '$TAG' is lightweight — release tags must be annotated (git tag -a)"
fi

# The Rivet app manifest carries the product version on this tree.
RIVET_RKTD_VERSION="$(grep -o '"[0-9]*\.[0-9]*\.[0-9]*"' "$ROOT/rivet.rktd" | head -n1 | tr -d '"')"
[[ "$RIVET_RKTD_VERSION" == "$VERSION" ]] || \
  fail "rivet.rktd version '$RIVET_RKTD_VERSION' does not match VERSION '$VERSION'"

# The release identity lives in the leaf version module (updater.rkt and
# the CLI both consume it from there).
grep -qF "(define app-version \"$VERSION\")" "$ROOT/racket/taskly/version.rkt" || \
  fail "racket/taskly/version.rkt app-version does not match VERSION '$VERSION'"

# The Racket package metadata carries the same identity (it drifted to
# 0.1.0 while the tree released 0.1.1–0.2.0 unnoticed).
grep -qF "(define version \"$VERSION\")" "$ROOT/racket/info.rkt" || \
  fail "racket/info.rkt version does not match VERSION '$VERSION'"

# The generated native clients embed the same release identity. These files
# are marked do-not-edit: a mismatch means the tree forgot to regenerate
# them after the version bump (the 0.1.1 release shipped a stale macOS
# constant and was only patched by hand in commit 8c34ed5).
check_generated_version() {
  local file="$1" pattern="$2" found
  found="$(grep -oE "$pattern" "$ROOT/$file" | head -n1 | grep -oE '"[^"]*"' | tr -d '"')"
  [[ "$found" == "$VERSION" ]] || \
    fail "generated file '$file' version '${found:-missing}' does not match VERSION '$VERSION' (regenerate, do not hand-edit)"
}
check_generated_version \
  "macos-host/Sources/RivetHost/GeneratedBackend.swift" \
  'public static let version = "[^"]+"'
check_generated_version \
  "windows/GeneratedBackend.hpp" \
  'kVersion\[\] = "[^"]+"'
check_generated_version \
  "linux/GeneratedBackend.hpp" \
  'kVersion\[\] = "[^"]+"'

echo "release preflight: version $VERSION is aligned (VERSION == rivet.rktd == version.rkt == generated clients)"
