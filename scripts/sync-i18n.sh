#!/bin/bash
# Syncs shared/i18n/*.json into each platform app and verifies byte-identity.
#   scripts/sync-i18n.sh          copy + verify
#   scripts/sync-i18n.sh --check  verify only (CI mode)
set -euo pipefail

cd "$(dirname "$0")/.."

declare -a TARGETS=(
  "apps/macos/Sources/Taskly/Resources"
  "apps/windows/Taskly/Strings"
  "apps/linux/resources/i18n"
)

copy() {
  for target in "${TARGETS[@]}"; do
    mkdir -p "$target"
    cp shared/i18n/zh.json "$target/zh.json"
    cp shared/i18n/en.json "$target/en.json"
    echo "synced → $target"
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
