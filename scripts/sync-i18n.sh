#!/bin/bash
# Verifies the shared string sources stay coherent (shared/spec/UPDATE.md,
# DATA-FORMAT §"i18n").
#
# The hosts no longer carry file copies: Linux/Windows/macOS all read the
# staged res/i18n at runtime (the release pipeline copies shared/i18n into
# the package), so there is nothing to sync — this check validates the
# source of truth instead:
#   - shared/i18n/{zh,en}.json parse as flat string→string objects
#   - both languages expose the exact same key set
#   - shared/emoji.json parses as JSON
#   scripts/sync-i18n.sh          validate (+ kept for call compat)
#   scripts/sync-i18n.sh --check  validate (CI mode)
set -euo pipefail

cd "$(dirname "$0")/.."

check() {
  local status=0
  python3 - <<'PY' || status=1
import json, sys

def load(path):
    with open(path, encoding="utf-8") as f:
        value = json.load(f)
    if not isinstance(value, dict) or not all(isinstance(k, str) and isinstance(v, str)
                                              for k, v in value.items()):
        print(f"✗ {path} is not a flat string→string object")
        sys.exit(1)
    return value

zh = load("shared/i18n/zh.json")
en = load("shared/i18n/en.json")
missing_zh = set(en) - set(zh)
missing_en = set(zh) - set(en)
if missing_zh or missing_en:
    for key in sorted(missing_zh):
        print(f"✗ key only in en.json: {key}")
    for key in sorted(missing_en):
        print(f"✗ key only in zh.json: {key}")
    sys.exit(1)
with open("shared/emoji.json", encoding="utf-8") as f:
    json.load(f)
print(f"✓ i18n sources coherent ({len(zh)} keys, zh/en parity, emoji.json valid)")
PY
  return $status
}

if [[ "${1:-}" == "--check" ]]; then
  check
else
  check
fi
