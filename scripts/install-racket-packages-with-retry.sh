#!/usr/bin/env bash
set -euo pipefail

if (( $# == 0 )); then
  echo "usage: $0 PACKAGE-OR-SOURCE [...]" >&2
  exit 2
fi

attempts="${RACKET_PKG_INSTALL_ATTEMPTS:-3}"
if [[ ! "$attempts" =~ ^[1-9][0-9]*$ ]]; then
  echo "RACKET_PKG_INSTALL_ATTEMPTS must be a positive integer" >&2
  exit 2
fi

status=1
for ((attempt = 1; attempt <= attempts; attempt++)); do
  echo "Racket package install attempt $attempt/$attempts: $*"
  if raco pkg install --auto --no-docs --skip-installed "$@"; then
    exit 0
  else
    status=$?
  fi
  if (( attempt < attempts )); then
    delay=$((attempt * 10))
    echo "Racket package install failed (exit $status); retrying in ${delay}s" >&2
    sleep "$delay"
  fi
done

echo "Racket package install failed after $attempts attempts" >&2
exit "$status"
