#!/usr/bin/env python3
"""Convert a PNG to NES 2bpp CHR data.

Usage: python3 tools/png2chr.py in.png out.chr [--pad N]

Width and height must be multiples of 8. Tiles are written row-major (8x8 cells),
16 bytes each: 8 bytes plane 0 (low bit), then 8 bytes plane 1 (high bit), MSB = leftmost.
Palette PNG: pixel index 0..3 is used as is.
RGB/RGBA PNG: transparent or #000000 -> 0, other colors sorted by brightness -> 1..3.
"""
import argparse
import sys

from PIL import Image


def die(msg):
    print(f"png2chr: error: {msg}", file=sys.stderr)
    sys.exit(1)


def pixel_indices(img):
    """Return a flat list of color indices 0..3, row-major."""
    if img.mode == "P":
        indices = list(img.get_flattened_data())
        if max(indices) > 3:
            die(f"palette index {max(indices)} used, only 0..3 allowed")
        return indices
    pixels = list(img.convert("RGBA").get_flattened_data())
    opaque = {(r, g, b) for r, g, b, a in pixels if a and (r, g, b) != (0, 0, 0)}
    order = sorted(opaque, key=lambda c: (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2], c))
    if len(order) > 3:
        die(f"{len(order)} non-background colors found, at most 3 allowed (plus 0 = background)")
    index = {c: i + 1 for i, c in enumerate(order)}
    return [index.get((r, g, b), 0) if a else 0 for r, g, b, a in pixels]


def encode(indices, w, h):
    out = bytearray()
    for ty in range(0, h, 8):
        for tx in range(0, w, 8):
            lo, hi = bytearray(8), bytearray(8)
            for y in range(8):
                for x in range(8):
                    v = indices[(ty + y) * w + tx + x]
                    bit = 0x80 >> x
                    if v & 1:
                        lo[y] |= bit
                    if v & 2:
                        hi[y] |= bit
            out += lo + hi
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description="PNG to NES 2bpp CHR")
    ap.add_argument("src", help="input PNG")
    ap.add_argument("dst", help="output CHR file")
    ap.add_argument("--pad", type=int, metavar="N", help="pad output with zero bytes to N bytes")
    args = ap.parse_args()

    img = Image.open(args.src)
    w, h = img.size
    if w % 8 or h % 8:
        die(f"image size {w}x{h} is not a multiple of 8")
    data = encode(pixel_indices(img), w, h)
    if args.pad is not None:
        if len(data) > args.pad:
            die(f"CHR data is {len(data)} bytes, larger than --pad {args.pad}")
        data += bytes(args.pad - len(data))
    with open(args.dst, "wb") as f:
        f.write(data)


if __name__ == "__main__":
    main()
