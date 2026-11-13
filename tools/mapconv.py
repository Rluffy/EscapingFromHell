#!/usr/bin/env python3
"""Convert assets/overworld.txt to build/overworld.bin: 64 columns x 16 bytes (column-major).

Usage: python3 tools/mapconv.py in.txt out.bin
Cell ids (= metatile table index in src/meta.h, see tools/art/bgart.py and docs/TECH.md):
  0 ground, 10/11 ground variants, 1 path, 12 path variant, 2 rock, 13/14 rock variants, 3 lava, 15/43 lava variants,
  4 wall, 8/9 wall beside a door (left/right), 5 roof middle, 6/7 roof left/right end,
  16..25 gate of dungeon 1..10, 32..41 door of dungeon 1..10, 26 tree, 27 lantern, 28 grass, 29 skull, 30 bones, 31 eyes (map char o).
Variants of , . # ~ are picked by a position hash, W/R by their neighbours (door / roof run). Row 15 of every column is padding (id 0).
"""
import sys

W, H = 64, 15
VARIANT = {",": [0, 0, 0, 0, 0, 10, 10, 11], ".": [1, 1, 1, 12], "#": [2, 2, 13, 14], "~": [3, 3, 15, 43]}
SIMPLE = {"T": 26, "L": 27, "y": 28, "k": 29, "x": 30, "o": 31}
SIMPLE.update({chr(ord("A") + i): 32 + i for i in range(10)})
SIMPLE.update({chr(ord("a") + i): 16 + i for i in range(10)})

# Map rows always start with 'W' (border), so lines starting with '#' are comments.
rows = [l.rstrip("\n") for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")]
if len(rows) != H or any(len(r) != W for r in rows):
    sys.exit(f"mapconv: map must be {W}x{H}")


def cell(c, r):
    ch = rows[r][c]
    if ch in VARIANT:
        v = VARIANT[ch]
        return v[(c * 31 + r * 17 + c * r) % len(v)]
    if ch == "W":
        left, right = rows[r][c - 1] if c else " ", rows[r][c + 1] if c < W - 1 else " "
        return 8 if right in "ABCDEFGHIJ" else 9 if left in "ABCDEFGHIJ" else 4
    if ch == "R":
        left, right = rows[r][c - 1] if c else " ", rows[r][c + 1] if c < W - 1 else " "
        return 5 if left == "R" and right == "R" else 6 if right == "R" else 7
    if ch in SIMPLE:
        return SIMPLE[ch]
    sys.exit(f"mapconv: unknown map character {ch!r} at column {c}, row {r}")


out = bytes(cell(c, r) if r < H else 0 for c in range(W) for r in range(16))
# Temple grid used by the game code: door col 6n-3, door row 5 (odd n) / 3 (even n).
for n in range(1, 11):
    assert out[(6 * n - 3) * 16 + (5 if n % 2 else 3)] == 31 + n, f"door {n} misplaced"
open(sys.argv[2], "wb").write(out)
