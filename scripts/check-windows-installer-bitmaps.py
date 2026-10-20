#!/usr/bin/env python3
"""Verify WiX 5 completion dialog bitmap and native checkbox background."""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[1] / "assets"
WIDTH, HEIGHT = 493, 312


def bmp_pixels() -> bytes:
    source = (ASSETS / "wizard-dialog.bmp").read_bytes()
    assert source[:2] == b"BM", "invalid BMP"
    offset = struct.unpack_from("<I", source, 10)[0]
    width, height, planes, depth = struct.unpack_from("<iiHH", source, 18)
    assert (width, abs(height), planes, depth) == (WIDTH, HEIGHT, 1, 24)
    stride = (WIDTH * 3 + 3) & ~3
    assert offset + HEIGHT * stride <= len(source)
    pixels = bytearray()
    for y in range(HEIGHT):
        row = y if height < 0 else HEIGHT - y - 1
        offset_row = offset + row * stride
        for x in range(WIDTH):
            start = offset_row + x * 3
            blue, green, red = source[start : start + 3]
            pixels.extend((red, green, blue))
    return bytes(pixels)


def png_pixels() -> bytes:
    source = (ASSETS / "wizard-dialog.png").read_bytes()
    assert source[:8] == b"\x89PNG\r\n\x1a\n"
    pos, chunks = 8, []
    while pos < len(source):
        size = struct.unpack_from(">I", source, pos)[0]
        tag = source[pos + 4 : pos + 8]
        payload = source[pos + 8 : pos + 8 + size]
        if tag == b"IHDR":
            assert struct.unpack_from(">IIBBBBB", payload) == (
                WIDTH, HEIGHT, 8, 2, 0, 0, 0
            )
        if tag == b"IDAT":
            chunks.append(payload)
        pos += size + 12
    raw = zlib.decompress(b"".join(chunks))
    stride = WIDTH * 3
    pixels = bytearray()
    for y in range(HEIGHT):
        offset = y * (stride + 1)
        assert raw[offset] == 0, "PNG preview must use filter None"
        pixels.extend(raw[offset + 1 : offset + 1 + stride])
    return bytes(pixels)


def main() -> None:
    pixels = bmp_pixels()
    assert png_pixels() == pixels, "preview PNG differs from shipping BMP"
    row_width = WIDTH * 3
    for y in range(248, HEIGHT):
        row = pixels[y * row_width : (y + 1) * row_width]
        assert row == bytes((240, 240, 240)) * WIDTH, (
            f"Windows checkbox backing is not flat #F0F0F0 at y={y}"
        )
    divider = pixels[247 * row_width : 248 * row_width]
    assert divider == bytes((214, 210, 206)) * WIDTH
    print("Windows MSI artwork OK: 493x312, flat native checkbox footer")


if __name__ == "__main__":
    main()
