#!/usr/bin/env python3
"""Overworld demon mini-sprites (v1.1 package 2): assets/sprites/owdemon.png.

Usage (repo root):  python3 tools/art/owart.py [--preview out.png [zoom]]
Block k (0..9) = the phase-1 look of demon k+1 shrunk to 16x16 (4 tiles TL, TR, BL, BR); block 10 = skull marker of a
defeated demon. The shrink is automatic (box filter from the grids in sprart.py), then hand fixes in FIX. After the first run
the PNG is the editable truth: repaint it directly and do NOT rerun this script. Palettes: docs/TECH.md "Overworld-Figuren (v1.1)".
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sprart as S
from PIL import Image

# phase-1 sprite palettes (index 1, 2, 3) of the demons = tables in src/<boss>.c, ow_pal[] in main.c must match
PAL = [(0x0A, 0x2A, 0x38), (0x22, 0x30, 0x0F), (0x08, 0x37, 0x2A), (0x07, 0x27, 0x30), (0x04, 0x24, 0x30),
       (0x01, 0x21, 0x30), (0x09, 0x1A, 0x26), (0x03, 0x13, 0x2A), (0x06, 0x26, 0x38), (0x06, 0x16, 0x28)]
HERO_PAL = (0x17, 0x21, 0x36)

SRC = [S.IMP[0], S.GHOST[0], S.HOUND[0], S.SNAKE_HEAD[0], S.WINGED[0], S.MIRROR[0], S.TOAD[0], S.SPIDER[0], S.ONI[0], S.LORD[0]]

SKULL = S.rows("""
................
................
....11111111....
...1333333331...
..133333333331..
..133333333331..
..131133331131..
..131133331131..
..133333333331..
...1333113331...
....13333331....
...1.133331.1...
..11.131313.11..
.1331.1111.1331.
.1311......1131.
..11........11..
""")


def shrink(g):
    g = [r.replace("e", "3") for r in g]          # mirror demon: e = eye marker (colour 3 on the original)
    h, w = len(g), len(g[0])
    s = max(w, h) / 16.0
    ow, oh = round(w / s), round(h / s)
    ox, oy = (16 - ow) // 2, 16 - oh          # centred, standing on the bottom edge
    out = [["."] * 16 for _ in range(16)]
    for ty in range(oh):
        for tx in range(ow):
            x0, x1 = int(tx * s), max(int(tx * s) + 1, int((tx + 1) * s))
            y0, y1 = int(ty * s), max(int(ty * s) + 1, int((ty + 1) * s))
            cnt = {"1": 0, "2": 0, "3": 0, ".": 0}
            for y in range(y0, min(y1, h)):
                for x in range(x0, min(x1, w)):
                    cnt[g[y][x]] += 1
            tot = sum(cnt.values())
            solid = tot - cnt["."]
            if solid * 2 < tot:
                continue
            # details (eyes, teeth, horn tips = the rarer colours) win over the body colour when they cover a third of the cell
            best = max("123", key=lambda c: (cnt[c] * (1.6 if c != "2" else 1.0), c))
            out[oy + ty][ox + tx] = best
    return ["".join(r) for r in out]


HOUND = S.rows("""
................
................
................
..11........11..
.1221......1221.
.12211111111221.
.12222222222221.
.12233222233221.
.12233222233221.
.12222211222221.
..122222222221..
..121212121212..
..11.111111.11..
.1221......1221.
.1221......1221.
..11........11..
""")
REPLACE = {2: HOUND}   # blocks the box filter does not do well (the skull hound)


def blocks():
    b = [REPLACE.get(k) or shrink(g) for k, g in enumerate(SRC)]
    return b + [SKULL]


def build():
    bl = blocks()
    img = Image.new("P", (16, 16 * len(bl)), 0)
    img.putpalette([0, 0, 0, 64, 64, 64, 128, 128, 128, 255, 255, 255] + [0] * 756)
    px = img.load()
    for k, g in enumerate(bl):
        for y, r in enumerate(g):
            for x, c in enumerate(r):
                px[x, k * 16 + y] = 0 if c == "." else int(c)
    return img


def preview(out, z):
    bl = blocks()
    pals = PAL + [HERO_PAL]
    im = Image.new("RGB", (16 * z * len(bl) + 8 * len(bl), 16 * z + 8), (0, 0, 0))
    for k, g in enumerate(bl):
        for y, r in enumerate(g):
            for x, c in enumerate(r):
                if c != ".":
                    col = tuple(int(S.NES[pals[k][int(c) - 1]][i:i + 2], 16) for i in (0, 2, 4))
                    for j in range(z):
                        for i in range(z):
                            im.putpixel((4 + k * (16 * z + 8) + x * z + i, 4 + y * z + j), col)
    im.save(out)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 6)
    else:
        path = S.SPR + "owdemon.png"
        build().save(path)
        print("wrote", path)
