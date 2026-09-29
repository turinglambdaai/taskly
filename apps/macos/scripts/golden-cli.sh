#!/usr/bin/env bash
# Run the shared golden-CLI suite against the macOS binary.
# Usage: scripts/golden-cli.sh [--record] [--binary PATH]
# Default binary: .build/debug/Taskly (run `swift build` first).
set -euo pipefail

cd "$(dirname "$0")/.."

RECORD=0
BINARY=".build/debug/Taskly"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --record) RECORD=1; shift ;;
    --binary) BINARY="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: scripts/golden-cli.sh [--record] [--binary PATH]"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -x "$BINARY" ]]; then
  echo "Binary not found: $BINARY — run 'swift build' first (or pass --binary)." >&2
  exit 1
fi

python3 ../../shared/cli-golden/runner.py --binary "$BINARY" $([[ $RECORD == 1 ]] && echo --record)
