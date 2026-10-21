#!/usr/bin/env bash
# The SVG is the editable source; Rivet stages the PNG named in rivet.rktd.
# Run before packaging on macOS so the release never ships stale artwork.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
svg="$root/assets/dmg-background.svg"
png="$root/assets/dmg-background.png"
if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required (macOS: brew install librsvg)" >&2
  exit 1
fi
rsvg-convert --format png --output "$png" "$svg"
# Fail before Rivet if the generated image no longer matches its fixed Finder
# window geometry (660x400 at 2x): a valid PNG may still crop/misalign icons.
python3 - "$png" <<'PY'
import struct
import sys
with open(sys.argv[1], "rb") as stream:
    header = stream.read(24)
if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
    raise SystemExit("DMG artwork is not a valid PNG")
size = struct.unpack(">II", header[16:24])
if size != (1320, 800):
    raise SystemExit(f"DMG artwork must be 1320x800, got {size}")
print(f"Rendered DMG artwork: {size[0]}x{size[1]}")
PY
