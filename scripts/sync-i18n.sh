#!/bin/bash
# Syncs shared/i18n/*.json into each platform app and verifies byte-identity.
#   scripts/sync-i18n.sh          copy + verify
#   scripts/sync-i18n.sh --check  verify only (CI mode)
set -euo pipefail

cd "$(dirname "$0")/.."

# File-based targets. The Linux (GTK4) and Windows (WinRT) hosts embed their
# string tables in source (linux/src/main.cpp / windows MainWindow), so only
# the macOS SwiftPM host consumes JSON resources today.
declare -a EMOJI_TARGETS=(
  "macos-host/Sources/RivetHost/Resources"
)

declare -a TARGETS=(
  "macos-host/Sources/RivetHost/Resources"
)

copy() {
  for target in "${TARGETS[@]}"; do
    mkdir -p "$target"
    cp shared/i18n/zh.json "$target/zh.json"
    cp shared/i18n/en.json "$target/en.json"
    echo "synced → $target"
  done
  for target in "${EMOJI_TARGETS[@]}"; do
    mkdir -p "$target"
    cp shared/emoji.json "$target/emoji.json"
    echo "synced → $target/emoji.json"
  done
}

check() {
  local status=0
  for target in "${TARGETS[@]}"; do
    for lang in zh en; do
      if ! diff -q "shared/i18n/$lang.json" "$target/$lang.json" >/dev/null 2>&1; then
        echo "✗ i18n drift: $target/$lang.json differs from shared/i18n/$lang.json"
        echo "  run: scripts/sync-i18n.sh"
        status=1
      fi
    done
  done
  for target in "${EMOJI_TARGETS[@]}"; do
    if ! diff -q "shared/emoji.json" "$target/emoji.json" >/dev/null 2>&1; then
      echo "✗ emoji drift: $target/emoji.json differs from shared/emoji.json"
      echo "  run: scripts/sync-i18n.sh"
      status=1
    fi
  done
  if [[ $status -eq 0 ]]; then
    echo "✓ i18n in sync across all platforms"
  fi
  return $status
}

if [[ "${1:-}" == "--check" ]]; then
  check
else
  copy
  check
fi
