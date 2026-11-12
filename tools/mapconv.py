#!/usr/bin/env python3
"""Convert assets/overworld.txt to build/overworld.bin: 64 columns x 16 bytes (column-major).

Usage: python3 tools/mapconv.py in.txt out.bin
Cell ids: 0..15 = bg tile index, 16..25 = gate of dungeon 1..10, 32..41 = door of dungeon 1..10.
Row 15 of every column is padding (id 0).
"""
import sys

LEGEND = {",": 0, ".": 1, "#": 2, "~": 3, "W": 4, "R": 5}
LEGEND.update({chr(ord("A") + i): 32 + i for i in range(10)})
LEGEND.update({chr(ord("a") + i): 16 + i for i in range(10)})
W, H = 64, 15

# Map rows always start with 'W' (border), so lines starting with '#' are comments.
rows = [l.rstrip("\n") for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")]
if len(rows) != H or any(len(r) != W for r in rows):
    sys.exit(f"mapconv: map must be {W}x{H}")
try:
    out = bytes(LEGEND[rows[r][c]] if r < H else 0 for c in range(W) for r in range(16))
except KeyError as e:
    sys.exit(f"mapconv: unknown map character {e}")
# Temple grid used by the game code: door col 6n-3, door row 5 (odd n) / 3 (even n).
for n in range(1, 11):
    assert out[(6 * n - 3) * 16 + (5 if n % 2 else 3)] == 31 + n, f"door {n} misplaced"
open(sys.argv[2], "wb").write(out)
