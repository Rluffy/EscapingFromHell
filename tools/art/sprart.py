#!/usr/bin/env python3
"""Sprite art generator (v0.9 art pass, package 3a): hero + shared sprites and demons 1..5.

Usage (from the repo root):
  python3 tools/art/sprart.py                   write assets/sprites/common.png and boss01..boss05.png
  python3 tools/art/sprart.py --preview out.png [N]   zoomed sheet of hero, shared sprites and demons 1..5 in every phase,
                                                (reads the PNGs + the phase palettes from src/*.c, N = zoom, default 6)

Art is drawn here as ASCII pixel grids ('.' = colour 0 = transparent, '1'..'3' = the three colours of the sprite
palette). Demons are drawn as the left half only (mirrored). The script patches the tiles it owns into the existing
PNGs (other tiles, e.g. the shockwave 17 or boss06..10, are left alone). After the first run the PNGs are the editable
truth: repaint them directly and do NOT rerun this script, or it overwrites your changes. Tile layout and palettes:
docs/TECH.md "Sprite-Kunst (v0.9)".
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

    canvas = Image.new("RGB", (1500, 1700), (20, 20, 20))
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
    canvas.save(out)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--preview":
        preview(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 6)
    else:
        write()
