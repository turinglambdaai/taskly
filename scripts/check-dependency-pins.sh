#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS=(
  "$ROOT/.github/workflows/ci.yml"
  "$ROOT/.github/workflows/acceptance.yml"
  "$ROOT/.github/workflows/release.yml"
)

fail() {
  echo "dependency pin preflight: $*" >&2
  exit 1
}

env_pin() {
  local file="$1"
  local name="$2"
  sed -nE "s/^[[:space:]]*${name}:[[:space:]]*([0-9a-f]{40})[[:space:]]*$/\\1/p" "$file" | head -n1
}

RIVET_PIN="$(env_pin "${WORKFLOWS[0]}" RIVET_PIN)"
[[ -n "$RIVET_PIN" ]] || fail "missing RIVET_PIN in ci.yml"

for workflow in "${WORKFLOWS[@]}"; do
  pin="$(env_pin "$workflow" RIVET_PIN)"
  [[ -n "$pin" ]] || fail "missing RIVET_PIN in ${workflow#"$ROOT/"}"
  [[ "$pin" == "$RIVET_PIN" ]] ||     fail "RIVET_PIN drift: ${workflow#"$ROOT/"} has $pin, expected $RIVET_PIN"
done

# Migration must not hide dependency refs from the checker: reject old remote
# names and verify that the current namespace is explicitly represented.
if grep -qE 'turinglambdaai/(rivet|keel)' "${WORKFLOWS[@]}"; then
  fail "legacy GitHub namespace in workflow dependency references"
fi
grep -qE 'turlamai/rivet/\.github/actions/setup-embed-racket@' "${WORKFLOWS[@]}" ||
  fail "missing pinned setup-embed-racket action"

while IFS= read -r action_pin; do
  [[ "$action_pin" == "$RIVET_PIN" ]] ||     fail "setup-embed-racket ref $action_pin does not match RIVET_PIN $RIVET_PIN"
done < <(
  grep -h -oE 'turlamai/rivet/\.github/actions/setup-embed-racket@[0-9a-f]{40}'     "${WORKFLOWS[@]}" |
    sed -E 's/.*@//'
)

KEEL_PIN="$(env_pin "$ROOT/.github/workflows/acceptance.yml" KEEL_PIN)"
[[ -n "$KEEL_PIN" ]] || fail "missing KEEL_PIN in acceptance.yml"

while IFS= read -r keel_pin; do
  [[ "$keel_pin" == "$KEEL_PIN" ]] ||     fail "Keel pin drift: found $keel_pin, expected $KEEL_PIN"
done < <(
  grep -h -oE 'turlamai/keel\.git#[0-9a-f]{40}' "${WORKFLOWS[@]}" |
    sed -E 's/.*#//'
)

echo "dependency pin preflight: aligned (Rivet $RIVET_PIN, Keel $KEEL_PIN)"
