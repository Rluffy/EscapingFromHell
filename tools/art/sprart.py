#!/usr/bin/env python3
"""Sprite art generator (v0.9 art pass, packages 3a and 3b): hero + shared sprites and demons 1..10.

Usage (from the repo root):
  python3 tools/art/sprart.py                   write assets/sprites/common.png and boss01..boss10.png
  python3 tools/art/sprart.py --preview out.png [N]   zoomed sheet of hero, shared sprites and demons 1..10 in every phase,
                                                (reads the PNGs + the phase palettes from src/*.c, N = zoom, default 6)

Art is drawn here as ASCII pixel grids ('.' = colour 0 = transparent, '1'..'3' = the three colours of the sprite
palette). Demons 1..5 are drawn as the left half only (mirrored); demons 6..10 (package 3b) are built in code from ellipses,
polygons and hand-stamped details (toad, spider, oni, lord) or from half grids plus stamps (mirror demon). The script patches
the tiles it owns into the existing PNGs (other tiles, e.g. the shockwave 17, are left alone). After the first run the PNGs
are the editable truth: repaint them directly and do NOT rerun this script, or it overwrites your changes. Tile layout and
palettes: docs/TECH.md "Sprite-Kunst (v0.9)".
"""
import os
import re
import sys

from PIL import Image

# Mesen's default palette (what the screenshots show); the PPU colour ids 0x00..0x3F
NES = ("666666 002A88 1412A7 3B00A4 5C007E 6E0040 6C0600 561D00 333500 0B4800 005200 004F08 00404D 000000 000000 000000 "
       "ADADAD 155FD9 4240FF 7527FE A01ACC B71E7B B53120 994E00 6B6D00 388700 0D9300 008C47 007AA0 000000 000000 000000 "
       "FFFEFF 64B0FF 9290FF C676FF F36AFF FE6ECC FE8170 EA9E22 BCBE00 88D800 5CE430 45E082 48CDDE 4F4F4F 000000 000000 "
       "FFFEFF C0DFFF D3D2FF E8C8FF FBC2FF FEC4EA FECCC5 F7D8A5 E4E594 CFEF96 BDF4AB B3F3CC B5EBF2 B8B8B8 000000 000000").split()

SPR = "assets/sprites/"

# ------------------------------------------------------------------ layouts: tile offset -> (x, y) in the composite
L16 = [(0, 0), (8, 0), (0, 8), (8, 8)]                  # 16x16 = 4 tiles (TL, TR, BL, BR)
L24 = L16 + [(0, 16), (8, 16)]                          # 16x24 = 6 tiles, row-major
LHD = L16 + [(16, 0), (16, 8)]                          # 24x16: left 16x16, then the right column top / bottom
LSEG = [(0, 0), (8, 0)]                                 # 16x8 snake body segment (2 tiles)
LTOAD = [(c * 8, r * 8) for r in range(3) for c in range(4)]   # 32x24 toad body = 12 tiles, row-major (facing right)
LONI = [(0, 0), (8, 0), (16, 0), (0, 8), (8, 8), (16, 8), (4, 16), (12, 16), (4, 24), (12, 24)]   # oni: 24 px shoulders, 16 px legs
LLORD = [(0, 0), (8, 0), (0, 8), (8, 8), (8, 16), (8, 24)]     # lord LEFT half (16 x 32): rows 0, 1 two tiles, rows 2, 3 one tile
L8 = [(0, 0)]                                           # single 8x8 tile
LCLUB = [(0, 0), (0, 8)]                                # oni club: head over handle (8x16)


def rows(s):
    return [r for r in s.strip("\n").split("\n")]


def mir(half):
    """Left half -> full width (mirrored)."""
    h = rows(half)
    w = len(h[0])
    assert all(len(r) == w for r in h), [(i, r) for i, r in enumerate(h) if len(r) != w]
    return [r + r[::-1] for r in h]


def check(g, w, h, name):
    assert len(g) == h and all(len(r) == w for r in g), (name, len(g), [len(r) for r in g])
    return g


# ====================================================================== HERO (sprite palette 0: 1 hair/belt/boots, 2 tunic, 3 skin)
# Side view facing right (flip = left). Upper body shared by idle / walk; legs differ.
HERO_UP = rows("""
................
......11111.....
.....1111111....
.....1111133....
.....111313.....
.....11.333.....
......3333......
.....222222.....
....22222233....
....2222223.....
.....22222......
.....11111......
""")
HERO_LEGS = {
    "idle": rows("""
.....22.22......
.....22.22......
.....11.11......
....111.111.....
"""),
    "walkA": rows("""
....222..22.....
....22....22....
....11.....11...
...111....111...
"""),
    "walkB": rows("""
.....222.22.....
......22.22.....
......11.11.....
.....111.111....
"""),
}
HERO_JUMP = rows("""
................
......11111.....
.....1111111....
.....1111133....
.....111313.....
.....11.333.....
......3333......
....33222222....
...3.22222233...
.....2222223....
.....11111......
....22.22.22....
....22.....22...
...111.....111..
................
................
""")
# Top-down overworld hero, facing the viewer (no flip), 16x16; two walk frames differ in the feet.
HERO_TD_UP = rows("""
................
.....111111.....
....11111111....
....11333311....
....13133131....
....13333331....
.....333333.....
...3.222222.3...
...3.222222.3...
....11111111....
....22222222....
""")
HERO_TD = {
    "idle": rows("""
.....22..22.....
.....22..22.....
....111..111....
................
................
"""),
    "walk": rows("""
.....22.........
.....22..22.....
....111..22.....
........111.....
................
"""),
}

# ====================================================================== shared small sprites (8x8 unless noted)
SWORD = rows("""
................
...1............
...12222222.....
11112222222222..
...13333333333..
...1............
................
................
""")
HEART_FULL = rows("""
........
.11..11.
1211.111
11111111
11111111
.111111.
..1111..
...11...
""")
HEART_EMPTY = rows("""
........
.33..33.
3..33..3
3......3
3......3
.3....3.
..3..3..
...33...
""")
WAVE = rows("""
..2.....
...22...
...3.2..
....32..
....32..
...3.2..
...22...
..2.....
""")
FIRE_BOSS = rows("""
...1....
..11.1..
.11221..
.12221..
.12221..
.11221.1
..111.1.
...11...
""")
FIRE_PLAYER = rows("""
........
..1.....
.12.2...
1233322.
.12333..
..12.2..
...1....
........
""")
SHIELD = rows("""
..2222..
.222222.
22111122
21111112
21111112
21111112
21133112
21333312
21333312
21133112
21111112
21111112
21111112
22111122
.222222.
..2222..
""")


# ====================================================================== DEMONS (left halves, mirrored)
# Colours per phase come from src/<boss>.c: 1 = shadow / outline, 2 = body, 3 = light (eyes, teeth, horns).
IMP = [mir("""
........
........
..1.....
..21....
...11111
..122222
.1222222
.1222332
.1222332
.1222222
.1222211
..122222
....1222
..112222
.1222222
..1221..
"""), mir("""
3.......
33......
.33.....
..33....
..311111
.1222222
.1211222
.1222112
.1222332
.1222332
.1222222
.1211111
.1132323
..122222
3.122222
33.1221.
"""), mir("""
3......3
33.....3
.33...33
..33.333
..311111
.1222222
.1121222
.1222112
.1222332
.1223332
.1222222
.1111111
.1313131
.1131313
3.112222
33.1221.
""")]


GHOST = [mir("""
........
....1111
..112222
.1222222
.1222222
12222222
12222332
12222332
12222332
12222222
12222233
12222233
12222222
12222222
12222222
12222222
12222222
12222222
12222222
12222222
12222222
12222222
22.22.22
1..11..1
"""), mir("""
........
...11111
..112222
.1222222
.1222222
12222222
12221112
12221312
12221112
12222222
12222222
12211111
12221212
12222222
11122222
12122222
12212222
12222222
.1222222
12222222
.1222222
12222222
2.2.22.2
1.1.1.1.
"""), mir("""
......11
.....122
....1222
...12222
..122222
.1223333
.1233333
.1231123
.1231123
.1233333
.1233133
.1313131
.1131313
.1222222
12222222
12222222
31222222
31222222
.3122222
..122222
..122222
..2.2222
..2.2.2.
...1.1.1
""")]

def overlay(base, block, x, y):
    """Paste `block` onto the rows of `base` at (x, y); '.' in the block keeps the base."""
    g = [list(r) for r in rows(base) if r != ""] if isinstance(base, str) else [list(r) for r in base]
    for j, r in enumerate(rows(block)):
        for i, c in enumerate(r):
            if c != ".":
                g[y + j][x + i] = c
    return ["".join(r) for r in g]


def mirh(half):
    """Left half (list or text) -> full width."""
    h = rows(half) if isinstance(half, str) else half
    return [r + r[::-1] for r in h]


# --- Bone hound: front view, 24x16 (halves are 12 wide); the head is flanked by shoulders and forelegs
HOUND_1 = rows("""
............
..111..11111
.1221.122222
..11.1222222
....12222222
....12111122
....12133122
....12111122
....12222222
....12222212
....12222222
....12121212
...111111111
..1222222222
.12212222222
.1221.122222
""")
HOUND_2 = rows("""
..3.........
..33..111111
..13.1222222
..1131222222
....12222222
....12111122
....12133122
....12111122
....12222222
....12222212
....12222222
....12121212
...131313131
..1222222222
.12212222222
.1221.122222
""")
HOUND_3 = overlay(HOUND_2, """
.111.
12221
13231
12221
.1331
..11.
""", 0, 6)
HOUND_3 = overlay(HOUND_3, """
.......3...3
......33..33
.....3...333
""", 0, 0)
HOUND = [mirh(h) for h in (HOUND_1, HOUND_2, HOUND_3)]

# --- Lava snake: head 16x16 (front) + body segment 16x8 (tile +4 / +5)
SNAKE_HEAD = [mir("""
........
........
...11111
..122222
.1222222
12222222
12331222
12331222
12222222
.1222222
..122222
...12122
....1222
.....122
......33
.....3.3
"""), mir("""
3.......
33......
.3311111
..322222
.1222222
12112222
12331222
12331222
12222222
.1222222
..122222
...13123
....1232
...3.122
......33
.....3.3
"""), mir("""
3......3
33....33
.3311333
..322222
.1222222
12112222
13331222
13331222
12222222
31222222
3.122222
..131313
...31233
...3.133
......33
.....3.3
""")]
SNAKE_BODY = [mir("""
..333333
.3222222
12222233
12222233
12222233
12222222
.1111111
..111111
"""), mir("""
..333333
.3222222
32222233
32222233
32222233
12222222
.1111111
..111111
"""), mir("""
..333333
.3232222
32322233
32223233
32232233
12222222
.1111111
..111111
""")]

# --- Winged demon 16x24 (front, wings spread to the sides): rows are "wing|body" = left half, 4 + 4 columns, mirrored
def wing(s):
    h = [r.replace("|", "") for r in rows(s)]
    assert len(h) == 24 and all(len(r) == 8 for r in h), [(i, r) for i, r in enumerate(h) if len(r) != 8]
    for i in range(8, 12):                              # broad chest: the wing's inner column becomes body there
        h[i] = h[i][:3] + "2" + h[i][4:]
    return mirh(h)


WINGED = [wing("""
....|....
....|1111
....|1222
....|1332
....|1332
....|1222
2...|1122
21..|.122
211.|1222
2111|1222
2111|1222
.111|1222
..11|1122
...1|.122
....|.122
....|.112
....|.122
....|.122
....|.12.
....|.12.
....|.12.
....|.11.
....|111.
....|....
"""), wing("""
....|33..
....|3111
....|1222
2...|1112
21..|1332
211.|1222
2111|1313
2111|.122
2211|1222
2111|1222
.211|1222
..21|1222
...2|1122
....|.122
....|.122
....|.112
....|.122
....|.122
....|.12.
....|.12.
....|.12.
....|.11.
....|111.
....|....
"""), wing("""
....|3..3
....|3113
3...|1223
23..|1112
211.|1332
2111|1332
2111|1313
2111|1313
2211|3222
2111|1222
2111|1222
.211|1222
.221|1122
..21|.122
...2|.122
....|.112
....|.122
....|.122
....|.12.
....|.12.
....|.12.
....|.11.
....|111.
....|....
""")]

# ====================================================================== DEMON 6: MIRROR DEMON (16x24, front)
# Drawn as the left half (mirrored), then a few asymmetric glints / cracks are stamped on. Rows 0..7 are the head tile row:
# 'e' = eyes, bright (3) on the original, dull (1) on the decoy copies; the copies' head tiles (18 + 2 * phase) are cut from
# the same grid (mirror.c draws a copy's top row from them, the body rows are shared with the original).
def stamp(g, pts, c):
    g = [list(r) for r in g]
    for x, y in pts:
        g[y][x] = c
    return ["".join(r) for r in g]


MIRROR = [
    stamp(mir("""
........
......11
....1122
...12222
..122222
..1eee22
..1eee22
..122222
..121222
..122111
...12222
....1122
...33333
..332222
.3322222
.3122222
33122222
33122222
33122222
33122222
.3122222
.3322222
..332222
...33333
"""), [(6, 14), (5, 15), (5, 16), (4, 17), (4, 19)], "3"),
    stamp(mir("""
3.......
33....11
.33.1122
..312222
..122222
.12eee22
.122ee22
.1221222
..122222
..121111
..123222
...12222
....3333
.2.33222
12322222
12312222
12312222
12312222
12322222
3.322222
..322222
..332222
...33222
....3333
"""), [(6, 15), (7, 16), (8, 17), (7, 18), (9, 19), (5, 16)], "1"),
    stamp(stamp(mir("""
3..3.3.3
33.3.3.3
.3333333
..122222
.1111122
.11ee222
.112ee22
..122222
..122222
..111111
..131313
...11222
3...3333
.2.33222
12322222
12312222
12312222
12312222
33322222
3.322222
3..22222
..332222
..33.222
...33333
"""), [(6, 15), (7, 16), (8, 17), (7, 18), (9, 19), (8, 20), (5, 16)], "1"),
        [(9, 16), (10, 16), (11, 16), (10, 17), (11, 17), (11, 18), (8, 21), (9, 21), (10, 21), (9, 22)], "."),
]
for _g in MIRROR:
    check(_g, 16, 24, "mirror")


# ====================================================================== DEMON 7: GIANT TOAD (32x24, side view facing right)
# Procedural: a union of ellipses, outlined with colour 1, then hand-stamped details (eye, mouth, warts, spikes). The code flips
# the body (attribute) when the toad faces left, so the art is drawn facing right: the front edge (x 24..31 of the middle row,
# tile +7) holds the mouth line, a tongue sprite (tiles 36 / 37) starts at x 24, y 7..14, tile 38 is the open mouth.
def canvas(w, h):
    return [["."] * w for _ in range(h)]


def ell(g, cx, cy, rx, ry, c="2"):
    for y in range(len(g)):
        for x in range(len(g[0])):
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                g[y][x] = c


def rect(g, x0, y0, x1, y1, c="2"):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = c


def outline(g, c="1", ground=True):
    """Every filled pixel with an empty 4-neighbour becomes `c` (the canvas edge counts as empty except at the bottom)."""
    h, w = len(g), len(g[0])
    out = [r[:] for r in g]
    for y in range(h):
        for x in range(w):
            if g[y][x] == ".":
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    e = g[ny][nx] == "."
                elif ny >= h:
                    e = ground
                else:
                    e = True
                if e:
                    out[y][x] = c
                    break
    return out


def patch(g, x0, y0, art, keep="."):
    for j, r in enumerate(rows(art)):
        for i, ch in enumerate(r):
            if ch != keep:
                g[y0 + j][x0 + i] = ch


def sp(g, pts, c):
    for x, y in pts:
        g[y][x] = c


def toad_base():
    g = canvas(32, 24)
    ell(g, 14, 14.5, 13, 8.5)          # back
    ell(g, 9, 16.5, 8.5, 7.5)          # hind haunch
    ell(g, 24.5, 13.5, 7.5, 6)         # head
    ell(g, 22.5, 19.5, 4.5, 4.5)       # front leg
    ell(g, 22.5, 5, 4.7, 4.2)          # eye bump
    rect(g, 1, 22, 12, 23)             # hind foot
    rect(g, 17, 22, 30, 23)            # front foot with toes
    return g


def shade(g):
    """Dithered shadow along the underside: a body pixel with a dark pixel below it turns dark on every other column."""
    h, w = len(g), len(g[0])
    o = [r[:] for r in g]
    for y in range(h - 1):
        for x in range(w):
            if g[y][x] == "2" and g[y + 1][x] == "1" and (x + y) % 2 == 0 and y > 12:
                o[y][x] = "1"
    return o


def toad_finish(g):
    g = shade(outline(g))
    # mouth: a long dark line from the cheek (curled up) to the front edge, lips below it
    sp(g, [(x, 12) for x in range(17, 32)], "1")
    sp(g, [(16, 11), (15, 10), (21, 13), (22, 13), (23, 13), (24, 13), (25, 13), (26, 13), (27, 13), (28, 13)], "1")
    sp(g, [(30, 9), (29, 9)], "1")                                  # nostril
    # toes (gaps between them), knee creases
    sp(g, [(20, 23), (23, 23), (26, 23), (29, 23), (3, 23), (6, 23), (9, 23)], ".")
    sp(g, [(20, 22), (23, 22), (26, 22), (29, 22), (3, 22), (6, 22), (9, 22)], "1")
    sp(g, [(4, 15), (5, 14), (6, 14), (7, 14), (8, 14), (9, 15), (10, 17), (11, 19), (11, 20)], "1")
    sp(g, [(18, 17), (19, 16), (20, 16), (21, 16), (22, 17), (17, 19)], "1")
    return g


def eye(g, mood):
    """Eye on the bump at (22.5, 5): iris 3 with a slit pupil; mood 1 round, 2 half-lidded, 3 angry (lid slanted down to the front)."""
    for y in range(0, 10):
        for x in range(17, 28):
            if g[y][x] == ".":
                continue
            if ((x + 0.5 - 22.5) / 3.2) ** 2 + ((y + 0.5 - 5) / 2.8) ** 2 <= 1.0:
                g[y][x] = "3"
    sp(g, [(22, y) for y in range(3, 8)], "1")
    if mood == 2:                                                      # lid across the upper third
        for x in range(18, 28):
            if g[3][x] == "3" or g[2][x] == "3" or g[3][x] == "1":
                g[3][x] = "1"
            if g[2][x] == "3":
                g[2][x] = "2"
    if mood == 3:                                                      # lid line from (19, 2) down to (26, 5)
        for x in range(18, 28):
            ly = 2 + (x - 19) * 3 // 7
            for y in range(0, 10):
                if g[y][x] in "13" and y < ly and x in range(19, 27):
                    g[y][x] = "2"
            if 2 <= ly < 10 and g[ly][x] != ".":
                g[ly][x] = "1"
    return g


def top(g, x):
    for y in range(len(g)):
        if g[y][x] != ".":
            return y
    return len(g)


def warts(g, pts):
    for x, y in pts:
        sp(g, [(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)], "1")
        g[y][x] = "3"


def spikes(g, xs, h):
    for x in xs:
        t = top(g, x)
        for k in range(h):
            sp(g, [(x + i, t - 1 - k) for i in range(h - k) if 0 <= t - 1 - k], "3")


def toad_p1():
    g = eye(toad_finish(toad_base()), 1)
    sp(g, [(8, 9), (14, 8), (19, 9)], "1")                           # a few freckles
    return ["".join(r) for r in g]


def toad_p2():
    g = toad_finish(toad_base())
    sp(g, [(x, 12) for x in range(11, 17)], "1")                      # wider mouth: the corner reaches behind the eye
    sp(g, [(10, 11), (11, 11), (12, 13), (13, 13), (14, 13), (15, 13), (16, 13), (17, 13), (18, 13), (19, 13), (20, 13)], "1")
    sp(g, [(30, 14), (29, 14), (28, 14)], "1")                        # heavy lower lip
    warts(g, [(5, 8), (10, 6), (14, 9), (18, 7), (7, 12), (12, 11), (3, 14), (20, 14)])
    g = eye(g, 2)
    sp(g, [(18, 2), (19, 1), (26, 1), (27, 2)], "1")                  # brow bumps
    return ["".join(r) for r in g]


def toad_p3():
    g = toad_finish(toad_base())
    sp(g, [(x, 12) for x in range(10, 17)], "1")
    sp(g, [(9, 11), (10, 10), (11, 11)], "1")
    sp(g, [(x, 13) for x in range(11, 31)], "1")
    sp(g, [(x, 14) for x in range(22, 31)], "1")
    sp(g, [(x, 12) for x in range(13, 31, 3)], "3")                    # teeth: upper row (y 12) and lower row (y 13), staggered
    sp(g, [(x, 13) for x in range(14, 31, 3)], "3")
    sp(g, [(x, 14) for x in range(16, 31, 6)], "3")
    warts(g, [(5, 8), (10, 6), (14, 9), (7, 12), (3, 14)])
    spikes(g, [3, 7, 11, 15], 3)
    g = eye(g, 3)
    sp(g, [(21, 21), (21, 22), (24, 21), (24, 22), (27, 21), (27, 22), (30, 21), (30, 22)], "3")   # claws
    return ["".join(r) for r in g]


TOAD = [toad_p1(), toad_p2(), toad_p3()]

TONGUE_SEG = rows("""
........
........
11111111
33333333
33233233
33333333
11111111
........
""")
TONGUE_TIP = rows("""
........
........
1111111.
33333331
33233331
33333331
1111111.
........
""")
MOUTH_OPEN = rows("""
22222222
22222211
22222222
11111111
13131313
13333333
13131313
22222222
""")
SLIME = rows("""
........
...11...
..1221..
.122321.
.122221.
.122221.
..1221..
...11...
""")


# ====================================================================== DEMON 8: SPIDER QUEEN (24x16, hangs head down from her thread)
# The thread (tile 18) ends at the top centre (x 11 / 12). Abdomen on top, head with fangs at the bottom, four legs per side.
# Drawn symmetric: legs on the left, then the left half is mirrored.
def line(g, x0, y0, x1, y1, c="2"):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        x, y = x0 + (x1 - x0) * i // n, y0 + (y1 - y0) * i // n
        if 0 <= y < len(g) and 0 <= x < len(g[0]):
            g[y][x] = c


def poly(g, pts, c="2", thick=1):
    for (a, b), (d, e) in zip(pts, pts[1:]):
        line(g, a, b, d, e, c)
        if thick > 1:
            line(g, a, b + 1, d, e + 1, c)


def mirror_left(g):
    w = len(g[0])
    for r in g:
        for x in range(w // 2):
            r[w - 1 - x] = r[x]
    return g


LEGS = [[(8, 8), (5, 4), (2, 4), (0, 9)], [(8, 9), (4, 7), (1, 9), (0, 12)],
        [(8, 10), (3, 10), (1, 13), (0, 15)], [(9, 12), (5, 13), (3, 15), (1, 15)]]


def spider(phase):
    g = canvas(24, 16)
    for pts in LEGS:
        poly(g, pts, "2", 2 if phase == 3 else 1)
    mirror_left(g)
    body = canvas(24, 16)
    ell(body, 12, 5.2, 5.4 + (phase - 1) * 0.3, 5.2)             # abdomen
    ell(body, 12, 11.2, 3.8, 3.8)                                 # head
    body = outline(body, "1", ground=False)
    for y in range(16):
        for x in range(24):
            if body[y][x] != ".":
                g[y][x] = body[y][x]
    return g


def spider_p1():
    g = spider(1)
    sp(g, [(9, 9), (10, 9), (13, 9), (14, 9), (10, 11), (13, 11)], "3")      # eyes
    sp(g, [(10, 14), (13, 14)], "3")                                        # small fangs
    sp(g, [(10, 2), (14, 4), (9, 6), (13, 7), (11, 4)], "1")                  # spots on the abdomen
    return ["".join(r) for r in g]


def spider_p2():
    g = spider(2)
    for y in (2, 5):
        sp(g, [(x, y) for x in range(8, 16) if g[y][x] == "2"], "1")        # stripes
    sp(g, [(11, 3), (12, 3), (11, 6), (12, 6)], "3")
    sp(g, [(9, 9), (10, 9), (9, 10), (10, 10), (13, 9), (14, 9), (13, 10), (14, 10)], "3")   # big eyes
    sp(g, [(11, 11), (12, 11)], "3")
    sp(g, [(10, 14), (10, 15), (13, 14), (13, 15)], "3")                    # fangs
    sp(g, [(10, 7), (12, 7), (11, 7), (13, 7)], "3")                        # crown
    return ["".join(r) for r in g]


def spider_p3():
    g = spider(3)
    sp(g, [(11, 2), (12, 2), (10, 3), (13, 3), (11, 4), (12, 4), (11, 5), (12, 5), (10, 6), (13, 6), (11, 7), (12, 7)], "3")  # hourglass
    sp(g, [(7, 3), (6, 5), (7, 7), (16, 3), (17, 5), (16, 7)], "3")        # spines
    sp(g, [(9, 9), (10, 9), (13, 9), (14, 9), (9, 11), (14, 11), (11, 10), (12, 10)], "3")  # many eyes
    sp(g, [(9, 14), (9, 15), (10, 15), (13, 15), (14, 15), (14, 14), (11, 14), (12, 14)], "3")   # long fangs
    sp(g, [(9, 8), (11, 8), (12, 8), (14, 8), (10, 7), (13, 7)], "3")      # crown spikes
    return ["".join(r) for r in g]


SPIDER = [spider_p1(), spider_p2(), spider_p3()]
THREAD = rows("""
...33...
...33...
...33...
...33...
...33...
...33...
...33...
...33...
""")
WEB = rows("""
3..33..3
.3.33.3.
..3333..
33333333
33333333
..3333..
.3.33.3.
3..33..3
""")
SPIDERLING = rows("""
........
3..11..3
.3.22.3.
..2332..
..2332..
.3.22.3.
3..11..3
........
""")


# ====================================================================== DEMON 9: ONI WARLORD (24x32, front, symmetric)
# Procedural (ellipses + outline + stamped details), mirrored from the left. Tiles: rows 0..15 are 24 px wide (3 tiles), rows 16..31
# are 16 px wide at x 4..19 (2 tiles); everything outside those tiles is cleared. The club (tiles 30 head / 31 handle) is separate sprites.
def clip_oni(g):
    for y in range(16, 32):
        for x in list(range(0, 4)) + list(range(20, 24)):
            g[y][x] = "."
    return g


def oni_base(horn, arm_w=2.6):
    g = canvas(24, 32)
    ell(g, 12, 13.5, 10.5, 6.5)                    # chest and shoulders
    rect(g, 6, 16, 17, 23)                         # belly
    ell(g, 12, 5.8, 5.9, 5.0)                      # head
    ell(g, 4.5, 9.3, 3.8, 2.8)                     # shoulder caps
    ell(g, 19.5, 9.3, 3.8, 2.8)
    ell(g, 3.2, 11.5, arm_w, 4.2)                  # arms (end in fists at row 15)
    ell(g, 20.8, 11.5, arm_w, 4.2)
    rect(g, 5, 22, 18, 26)                         # loincloth
    rect(g, 5, 26, 10, 31)                         # legs (gap of 2 px in the middle)
    rect(g, 13, 26, 18, 31)
    rect(g, 4, 30, 10, 31)                         # feet
    rect(g, 13, 30, 19, 31)
    return g


def oni_finish(g, vein="1"):
    g = clip_oni(outline(g))
    # muscle lines (colour `vein`: dark ink, or glowing cracks in phase 3)
    sp(g, [(x, 14) for x in range(7, 12)] + [(x, 14) for x in range(13, 18)], vein)         # lower edge of the pectorals
    sp(g, [(11, y) for y in range(11, 15)] + [(12, y) for y in range(11, 15)], vein)       # breastbone
    sp(g, [(9, 18), (10, 18), (13, 18), (14, 18), (9, 20), (10, 20), (13, 20), (14, 20)], vein)   # abs
    sp(g, [(11, y) for y in range(15, 22)] + [(12, y) for y in range(15, 22)], vein)
    sp(g, [(x, 16) for x in range(5, 19)], "1")                                              # belt
    sp(g, [(x, 28) for x in (6, 7, 8, 9)] + [(x, 28) for x in (14, 15, 16, 17)], vein)     # knees
    sp(g, [(11, y) for y in range(26, 32)] + [(12, y) for y in range(26, 32)], ".")        # leg gap
    # chin line: the head stands apart from the chest
    sp(g, [(7, 8), (8, 9), (9, 10), (10, 10), (11, 10), (12, 10), (13, 10), (14, 10), (15, 9), (16, 8)], "1")
    return g


def loin(g, c):
    """Tiger-skin loincloth: light (3) with dark stripes."""
    for y in range(22, 27):
        for x in range(5, 19):
            if g[y][x] != ".":
                g[y][x] = c
    for y in range(23, 26):
        for x in range(5, 19):
            if (x + y * 2) % 5 in (0, 1):
                g[y][x] = "1"
    sp(g, [(x, 22) for x in range(5, 19)], "1")
    sp(g, [(x, 26) for x in range(5, 11)] + [(x, 26) for x in range(13, 19)], "1")


def facepatch(g, half, x0=6, y0=3):
    """Stamp a face given as its left half (6 columns from x0, '.' = keep) mirrored over the head."""
    for j, r in enumerate(rows(half)):
        for i, c in enumerate(r):
            if c != ".":
                g[y0 + j][x0 + i] = c
                g[y0 + j][23 - x0 - i] = c


def oni_p1():
    g = oni_finish(oni_base(0))
    loin(g, "3")
    facepatch(g, """
......
.1111.
.3331.
.313..
.3...1
.11111
""")
    sp(g, [(8, 0), (8, 1), (8, 2), (15, 0), (15, 1), (15, 2)], "3")       # stub horns
    return ["".join(r) for r in g]


def oni_p2():
    g = oni_finish(oni_base(1, 2.9))
    loin(g, "3")
    facepatch(g, """
.11...
..1111
.1331.
.1331.
.3..11
.11111
..3.3.
""")
    sp(g, [(7, 3), (7, 2), (6, 1), (6, 0), (5, 0), (16, 3), (16, 2), (17, 1), (17, 0), (18, 0), (7, 1), (16, 1)], "3")   # horns
    sp(g, [(x, 13) for x in (1, 2, 21, 22)], "3")                         # bracers
    return ["".join(r) for r in g]


def oni_p3():
    g = oni_finish(oni_base(2, 3.0), "3")
    loin(g, "3")
    facepatch(g, """
.111..
.11111
111331
111331
13.111
131313
111111
""")
    sp(g, [(8, 3), (7, 2), (6, 1), (5, 0), (7, 1), (6, 0), (15, 3), (16, 2), (17, 1), (18, 0), (16, 1), (17, 0), (9, 1), (14, 1), (9, 0), (14, 0), (10, 1), (13, 1)], "3")
    sp(g, [(x, 13) for x in (1, 2, 21, 22)], "3")
    sp(g, [(3, 6), (3, 7), (3, 5), (20, 6), (20, 7), (20, 5), (4, 4), (19, 4), (2, 6), (21, 6)], "3")   # shoulder spikes
    sp(g, [(5, 11), (6, 12), (18, 11), (17, 12)], "3")                    # cracks on the pectorals
    return ["".join(r) for r in g]


ONI = [oni_p1(), oni_p2(), oni_p3()]
for _g in ONI:
    check(_g, 24, 32, "oni")

CLUB_HEAD = rows("""
.3.33.3.
.111111.
12222221
32232223
12222221
12222221
.122221.
..1221..
""")
CLUB_HANDLE = rows("""
..1221..
..1221..
..1221..
..1221..
.122221.
.122221.
.122221.
..1111..
""")


# ====================================================================== DEMON 10: HELL LORD (32x32, front, symmetric)
# Procedural like the toad / oni, built symmetric on 32x32 and cut to the LEFT half (16 x 32) the lord code mirrors. Rows 0..15 are
# 32 px wide (horns, head, pauldrons, wings), rows 16..31 only 16 px (x 8..23: torso and legs).
def clip_lord(g):
    for y in range(16, 32):
        for x in list(range(0, 8)) + list(range(24, 32)):
            g[y][x] = "."
    return g


def fpatch(g, half, x0, y0, w=32):
    """Stamp a face given as its left half ('.' = keep) mirrored about the vertical centre of a w-wide canvas."""
    for j, r in enumerate(rows(half)):
        for i, c in enumerate(r):
            if c != ".":
                g[y0 + j][x0 + i] = c
                g[y0 + j][w - 1 - x0 - i] = c


def pfill(g, pts, c="2"):
    """Fill the polygon `pts` (even-odd rule, pixel centres)."""
    for y in range(len(g)):
        for x in range(len(g[0])):
            px, py, ins = x + 0.5, y + 0.5, False
            for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
                if (y0 > py) != (y1 > py) and px < (x1 - x0) * (py - y0) / (y1 - y0) + x0:
                    ins = not ins
            if ins:
                g[y][x] = c


WING = {2: [(9, 12), (6, 7), (3, 3), (4, 8), (1, 11), (5, 12), (8, 15)],
        3: [(9, 11), (5, 4), (1, 0), (2, 6), (0, 9), (3, 10), (1, 14), (5, 13), (8, 15)]}


def lord_base(phase):
    g = canvas(32, 32)
    if phase >= 2:                                  # wings behind everything: stubs, then large bat wings
        for pts in (WING[phase], [(31 - x, y) for x, y in WING[phase]]):
            pfill(g, pts)
    ell(g, 7.5, 13.8, 5.5, 3.4)                     # round pauldrons
    ell(g, 24.5, 13.8, 5.5, 3.4)
    ell(g, 16, 17.5, 8.0, 5.0)                      # chest
    ell(g, 16, 22.5, 7.4, 7.0)                      # torso
    rect(g, 9, 27, 14, 31)                          # legs
    rect(g, 17, 27, 22, 31)
    rect(g, 8, 30, 14, 31)                          # hooves
    rect(g, 17, 30, 23, 31)
    ell(g, 16, 7.0, 5.8, 6.0)                       # head
    return g


def lord_finish(g, phase):
    g = clip_lord(outline(g))
    sp(g, [(x, 16) for x in range(9, 23)], "1")      # belt / sash line
    sp(g, [(15, y) for y in range(27, 32)] + [(16, y) for y in range(27, 32)], ".")     # gap between the legs
    sp(g, [(x, 13) for x in range(10, 22)] + [(9, 12), (22, 12)], "1")                    # the head stands apart from the shoulders
    sp(g, [(x, 28) for x in (10, 11, 12, 13, 18, 19, 20, 21)], "1")                       # knees
    sp(g, [(13, 14), (18, 14), (12, 15), (19, 15)], "1")                                  # collar bone
    return g


def lord_p1():
    g = lord_finish(lord_base(1), 1)
    fpatch(g, """
......
......
.1111.
.1331.
.1331.
.....1
......
.11111
......
""", 10, 3)
    poly(g, [(11, 3), (10, 1), (9, 0)], "3", 2)                    # small horns
    poly(g, [(20, 3), (21, 1), (22, 0)], "3", 2)
    sp(g, [(15, 18), (16, 18), (14, 19), (17, 19), (15, 20), (16, 20), (15, 21), (16, 21)], "1")   # clasp
    return ["".join(r) for r in g]


def lord_p2():
    g = lord_finish(lord_base(2), 2)
    fpatch(g, """
......
.11...
..1111
.1331.
.1331.
.....1
.3....
.11111
.3.3..
""", 10, 3)
    poly(g, [(11, 4), (8, 2), (6, 0)], "3", 2)                    # big horns
    poly(g, [(20, 4), (23, 2), (25, 0)], "3", 2)
    sp(g, [(10, 14), (9, 12), (8, 13), (21, 14), (22, 12), (23, 13)], "3")      # pauldron spikes
    sp(g, [(x, 17) for x in range(11, 21)] + [(x, 23) for x in range(12, 20)] + [(11, 18), (20, 18), (12, 22), (19, 22)], "3")   # breastplate
    sp(g, [(15, 18), (16, 18), (14, 19), (15, 19), (16, 19), (17, 19), (15, 20), (16, 20), (14, 20), (17, 20), (15, 21), (16, 21)], "3")   # diamond
    return ["".join(r) for r in g]


def lord_p3():
    g = lord_finish(lord_base(3), 3)
    fpatch(g, """
......
.111..
.11111
111331
111331
.....1
13.111
131313
111111
""", 10, 3)
    poly(g, [(11, 4), (7, 3), (4, 1), (3, 0)], "3", 2)            # giant horns
    poly(g, [(20, 4), (24, 3), (27, 1), (28, 0)], "3", 2)
    for x in (12, 14, 17, 19):                                     # flame crown
        sp(g, [(x, 0), (x, 1)], "3")
    sp(g, [(15, 0), (16, 0), (15, 1), (16, 1), (15, 2), (16, 2)], "3")
    sp(g, [(8, 11), (7, 9), (6, 10), (23, 11), (24, 9), (25, 10), (9, 12), (22, 12)], "3")   # pauldron spikes
    sp(g, [(15, 18), (16, 18), (14, 19), (15, 19), (16, 19), (17, 19), (13, 20), (14, 20), (15, 20), (16, 20), (17, 20), (18, 20),
           (14, 21), (15, 21), (16, 21), (17, 21), (15, 22), (16, 22)], "3")                                # glowing chest diamond
    sp(g, [(11, 24), (12, 25), (20, 24), (19, 25), (10, 20), (21, 20)], "3")
    return ["".join(r) for r in g]


LORD = [lord_p1(), lord_p2(), lord_p3()]


# ====================================================================== tables: what goes where
# (sheet, first tile, layout, grid) of every drawn piece; boss sheets: phase p starts at tile 6 * p (imp: 4 * p).
def build_pieces():
    P = []
    # common.png: ids are fixed by the code (docs/TECH.md "CHR-Layout (v0.9)"): 4..7 stand, 8..11 walk A, 18..21 walk B, 22..25 jump,
    # 0..3 / 32..35 overworld hero (stand / walk), 12/13 sword, 14/15 hearts, 16 wave, 28 boss fireball, 29 player fireball, 30/31 shield
    P.append(("common", 4, L16, HERO_UP + HERO_LEGS["idle"]))
    P.append(("common", 8, L16, HERO_UP + HERO_LEGS["walkA"]))
    P.append(("common", 18, L16, HERO_UP + HERO_LEGS["walkB"]))
    P.append(("common", 22, L16, HERO_JUMP))
    P.append(("common", 0, L16, HERO_TD_UP + HERO_TD["idle"]))
    P.append(("common", 32, L16, HERO_TD_UP + HERO_TD["walk"]))
    P.append(("common", 12, LSEG, SWORD))
    P.append(("common", 14, [(0, 0)], HEART_FULL))
    P.append(("common", 15, [(0, 0)], HEART_EMPTY))
    P.append(("common", 16, [(0, 0)], WAVE))
    P.append(("common", 28, [(0, 0)], FIRE_BOSS))
    P.append(("common", 29, [(0, 0)], FIRE_PLAYER))
    P.append(("common", 30, [(0, 0), (0, 8)], SHIELD))
    for i, g in enumerate(IMP):
        P.append(("boss01", 4 * i, L16, g))
    for i in range(3):
        P.append(("boss04", 6 * i, L16, SNAKE_HEAD[i]))
        P.append(("boss04", 6 * i + 4, LSEG, SNAKE_BODY[i]))
    for name, ph in BOSSES.items():
        for i, g in enumerate(ph):
            P.append((name, 6 * i, g[0], g[1]))
    # --- package 3b: demons 6..10
    for i in range(3):
        m = [r.replace("e", "3") for r in MIRROR[i]]
        P.append(("boss06", 6 * i, L24, m))
        P.append(("boss06", 18 + 2 * i, LSEG, [r.replace("e", "1") for r in MIRROR[i][:8]]))     # decoy head: dull eyes
        P.append(("boss07", 12 * i, LTOAD, TOAD[i]))
        P.append(("boss08", 6 * i, LHD, SPIDER[i]))
        P.append(("boss09", 10 * i, LONI, ONI[i]))
        P.append(("boss10", 6 * i, LLORD, [r[:16] for r in LORD[i]]))
    P.append(("boss07", 36, L8, TONGUE_SEG))
    P.append(("boss07", 37, L8, TONGUE_TIP))
    P.append(("boss07", 38, L8, MOUTH_OPEN))
    P.append(("boss07", 39, L8, SLIME))
    P.append(("boss08", 18, L8, THREAD))
    P.append(("boss08", 19, L8, WEB))
    P.append(("boss08", 20, L8, SPIDERLING))
    P.append(("boss09", 30, L8, CLUB_HEAD))
    P.append(("boss09", 31, L8, CLUB_HANDLE))
    return P


BOSSES = {}   # sheet -> [(layout, grid)] x 3 (demons 2..5)
BODY = {}     # sheet -> [grid] x 3: snake body segment (tile +4/+5)


BOSSES["boss02"] = [(L24, g) for g in GHOST]
BOSSES["boss03"] = [(LHD, g) for g in HOUND]
BOSSES["boss05"] = [(L24, g) for g in WINGED]


def tile_rows(g, x, y):
    return [r[x:x + 8] for r in g[y:y + 8]]


def put(sheets, name, first, layout, g):
    img = sheets[name]
    w = max(x for x, _ in layout) + 8
    h = max(y for _, y in layout) + 8
    check(g, w, h, f"{name}@{first}")
    for k, (x, y) in enumerate(layout):
        t = first + k
        tx, ty = (t % 2) * 8, (t // 2) * 8
        if ty + 8 > img.height:
            n = Image.new("P", (img.width, ty + 8), 0)
            n.putpalette(img.getpalette())
            n.paste(img, (0, 0))
            img = sheets[name] = n
        px = img.load()
        for yy, r in enumerate(tile_rows(g, x, y)):
            for xx, c in enumerate(r):
                px[tx + xx, ty + yy] = 0 if c == "." else int(c)


def write():
    names = sorted({p[0] for p in build_pieces()})
    sheets = {n: Image.open(f"{SPR}{n}.png") for n in names}
    for name, first, layout, g in build_pieces():
        put(sheets, name, first, layout, g)
    for n, img in sheets.items():
        img.save(f"{SPR}{n}.png")
        print("wrote", f"{SPR}{n}.png", img.size)


# ====================================================================== preview (reads the PNGs and the real palettes)
def src_pal(path, pat, n=3):
    t = open(path).read()
    return [[int(v, 16) for v in m] for m in re.findall(pat, t)]


def zoom(im, z):
    """Nearest-neighbour zoom (Image.resize(NEAREST) is broken in some Pillow builds)."""
    o = Image.new("RGB", (im.width * z, im.height * z))
    px, op = im.load(), o.load()
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            for j in range(z):
                for i in range(z):
                    op[x * z + i, y * z + j] = c
    return o


def preview(out, z=6):
    spal = [int(v, 16) for v in re.search(r"spal\[12\] = \{([^}]*)\}", open("src/dungeon.c").read()).group(1).replace("0x", "").replace(",", " ").split()]
    spal = [spal[i:i + 3] for i in range(0, 12, 3)]
    dpal = [[int(v, 16) for v in m] for m in re.findall(r"\{(0x\w\w),(0x\w\w),(0x\w\w),(0x\w\w)\}", open("src/dungeon.c").read())]
    bossfiles = ["imp", "ghost", "hound", "snake", "winged"]
    phases = [src_pal(f"src/{b}.c", r"\{ 0x(\w\w), 0x(\w\w), 0x(\w\w) \} \}") for b in bossfiles]
    com = Image.open(f"{SPR}common.png")
    cells = []   # (image sheet, layout, first tile, palette (3 NES ids), bg id)

    def render(img, first, layout, pal, bg):
        w = max(x for x, _ in layout) + 8
        h = max(y for _, y in layout) + 8
        o = Image.new("RGB", (w, h), tuple(int(NES[bg][i:i + 2], 16) for i in (0, 2, 4)))
        px, op = img.load(), o.load()
        for k, (x, y) in enumerate(layout):
            t = first + k
            tx, ty = (t % 2) * 8, (t // 2) * 8
            if ty + 8 > img.height:
                continue
            for yy in range(8):
                for xx in range(8):
                    v = px[tx + xx, ty + yy]
                    if v:
                        op[x + xx, y + yy] = tuple(int(NES[pal[v - 1]][i:i + 2], 16) for i in (0, 2, 4))
        return o

    canvas = Image.new("RGB", (1500, 2500), (20, 20, 20))
    bg = 0x0F
    # hero row
    x = 4
    hero = [(4, L16), (8, L16), (18, L16), (22, L16), (0, L16), (32, L16)]
    for first, lay in hero:
        im = zoom(render(com, first, lay, spal[0], bg), z)
        canvas.paste(im, (x, 4)); x += 16 * z + 8
    sm = [(12, LSEG, spal[2]), (14, [(0, 0)], spal[2]), (15, [(0, 0)], spal[2]), (16, [(0, 0)], spal[3]), (28, [(0, 0)], spal[2]), (29, [(0, 0)], spal[3]), (30, [(0, 0), (0, 8)], spal[3])]
    x = 4
    for first, lay, pal in sm:
        im = render(com, first, lay, pal, bg)
        im = zoom(im, z)
        canvas.paste(im, (x, 4 + 16 * z + 8)); x += im.width + 8
    y0 = 4 + 16 * z + 8 + 16 * z + 8
    for bi, b in enumerate(bossfiles):
        img = Image.open(f"{SPR}boss0{bi + 1}.png")
        x = 4
        for p in range(3):
            first = (4 if bi == 0 else 6) * p
            lay = [L16, L24, LHD, L16, L24][bi]
            im = render(img, first, lay, phases[bi][p], 0x0F)
            im = zoom(im, z)
            canvas.paste(im, (x, y0)); x += im.width + 12
            if bi == 3:
                seg = zoom(render(img, first + 4, LSEG, phases[bi][p], 0x0F), z)
                canvas.paste(seg, (x, y0)); x += 16 * z + 12
        y0 += (24 if bi in (1, 2, 4) else 16) * z + 10 if bi != 2 else 16 * z + 10
    # --- demons 6..10 (package 3b); the extras (decoy head, tongue, mouth, slime, thread, web, spiderling, club) in a second row each
    shock = (17, [(0, 0)])
    for b, sheet, lay, stride, hh, extra in (("mirror", "boss06", L24, 6, 24, [("copy",)]), ("toad", "boss07", LTOAD, 12, 24, [(36, L8), (37, L8), (38, L8), (39, L8)]),
                                             ("spider", "boss08", LHD, 6, 16, [(18, L8), (19, L8), (20, L8)]), ("oni", "boss09", LONI, 10, 32, [(30, LCLUB)]),
                                             ("lord", "boss10", None, 6, 32, [])):
        img = Image.open(f"{SPR}{sheet}.png")
        pals = src_pal(f"src/{b}.c", r"\{ 0x(\w\w), 0x(\w\w), 0x(\w\w) \} \}")
        x = 4
        for p in range(3):
            pal = [int(v) for v in pals[p]]
            if lay is None:
                half = render(img, stride * p, LLORD, pal, 0x0F)
                im = Image.new("RGB", (32, 32), half.getpixel((0, 0)))
                im.paste(half, (0, 0)); im.paste(half.transpose(Image.FLIP_LEFT_RIGHT), (16, 0))
            else:
                im = render(img, stride * p, lay, pal, 0x0F)
            im = zoom(im, z)
            canvas.paste(im, (x, y0)); x += im.width + 12
        y0 += hh * z + 10
        x = 4
        for p in range(3):
            pal = [int(v) for v in pals[p]]
            if extra and extra[0] == ("copy",):
                im = render(img, stride * p, lay, pal, 0x0F)
                im.paste(render(img, 18 + 2 * p, LSEG, pal, 0x0F), (0, 0))
                im = zoom(im, z); canvas.paste(im, (x, y0)); x += im.width + 12
        if extra and extra[0] != ("copy",):
            pal = [int(v) for v in pals[2]]
            for first, lay2 in extra:
                im = zoom(render(img, first, lay2, pal, 0x0F), z); canvas.paste(im, (x, y0)); x += im.width + 12
        if extra:
            y0 += (16 if b != "mirror" else 24) * z + 10
    canvas.save(out)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--preview":
        preview(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 6)
    else:
        write()
