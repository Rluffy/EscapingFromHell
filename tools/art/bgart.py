#!/usr/bin/env python3
"""Background art generator (v0.9 art pass): metatiles + arena tiles -> PNG sheets + src/meta.h.

Usage: python3 tools/art/bgart.py [--preview out.png]     (run from the repo root)

Writes assets/sprites/tiles.png (128 tiles, 16 per row, bg pattern table R0) and
assets/sprites/anim_a.png / anim_b.png (128 tiles each, R1, tile ids 128..255) and src/meta.h
(metatile table + arena tile ids). Art is drawn here as 16x16 pixel grids ('.' = colour 0 = backdrop,
'1'..'3' = palette colours); every metatile is cut into 4 tiles, identical tiles are shared.
After the first run the PNGs are the editable truth: repaint them directly and do NOT rerun this
script (it overwrites the art tiles; fonts and HP bar tiles 13..49 are kept). Tile layout and the
metatile table: docs/TECH.md "Hintergrund-Kunst (v0.9)".
"""
import sys
from PIL import Image

NES = ("7C7C7C 0000FC 0000BC 4428BC 940084 A80020 A81000 881400 503000 007800 006800 005800 004058 000000 000000 000000 "
       "BCBCBC 0078F8 0058F8 6844FC D800CC E40058 F83800 E45C10 AC7C00 00B800 00A800 00A844 008888 000000 000000 000000 "
       "F8F8F8 3CBCFC 6888FC 9878F8 F878F8 F85898 F87858 FCA044 F8B800 B8F818 58D854 58F898 00E8D8 787878 000000 000000 "
       "FCFCFC A4E4FC B8B8F8 D8B8F8 F8B8F8 F8A4C0 F0D0B0 FCE0A8 F8D878 D8F878 B8F8B8 B8F8D8 00FCFC F8D8F8 000000 000000").split()
# overworld bg palettes (must match pal_overworld in src/main.c); backdrop $0F everywhere
PAL = [(0x0F, 0x02, 0x03, 0x32),    # 0 ground, path, rocks, trees, bones: deep blue / violet / lavender
       (0x0F, 0x06, 0x16, 0x26),    # 1 walls, pillars, doors: dark red / red / salmon
       (0x0F, 0x16, 0x27, 0x38),    # 2 lava, lanterns, locked seal: red / orange / yellow
       (0x0F, 0x03, 0x12, 0x21)]    # 3 roofs, open gate: violet / blue / cyan


def grid(s, n=16):
    rows = s.strip("\n").split("\n")
    assert len(rows) == n and all(len(r) == n for r in rows), f"bad grid: {[len(r) for r in rows]}\n{s}"
    return rows


def roll(rows, dx, dy=0):
    n = len(rows[0])
    m = len(rows)
    return [rows[(y - dy) % m][-dx % n:] + rows[(y - dy) % m][:-dx % n] if dx % n else rows[(y - dy) % m] for y in range(m)]


def hflip(rows):
    return [r[::-1] for r in rows]


def patch(rows, p):
    """p = list of (x, y, char)."""
    g = [list(r) for r in rows]
    for x, y, c in p:
        g[y][x] = c
    return ["".join(r) for r in g]


def sway(rows, top, bottom):
    """Shift rows 0..7 by `top`, 8..11 by `bottom` (grass blown by the wind)."""
    return [roll([r], top if y < 8 else bottom if y < 12 else 0)[0] for y, r in enumerate(rows)]


# ---------------------------------------------------------------- overworld metatiles (cell id -> art)
ART = {}      # cell id -> (name, palette, frame A rows, frame B rows)


def meta(cid, name, pal, a, b=None):
    ART[cid] = (name, pal, a, b or a)


meta(0, "ground_a", 0, grid("""
................
.....1..........
............1...
..1.............
.........2......
....1...........
..............1.
.1..........1...
........1.......
...........1....
..1.............
.............2..
......1.........
.1..............
..........1.....
......1.....1...
"""))
meta(10, "ground_b", 0, grid("""
................
..22............
.2332...........
..22.......1....
...........22...
.....1.....22...
................
.1.........1....
........2.......
.......232......
........22...1..
.1..............
..........1.....
....22..........
...2332.....1...
....22..........
"""))
meta(11, "ground_c", 0, grid("""
................
..1.............
...1....1.......
....11...1......
.....1...11.....
......1....1....
.....1.......1..
....1...........
................
...........1....
..........1.....
.........11.....
..1.....1.......
...1...1........
....1..1....1...
................
"""))

_path = grid("""
3333333.3333333.
2222222.2222222.
2222122.2222222.
2222222.2222122.
2222222.2222222.
2222222.2222222.
1111111.1111111.
................
3333.3333333.333
2222.2222222.222
2222.2222222.222
2122.2222212.222
2222.2222222.222
2222.2222222.222
1111.1111111.111
................
""")
meta(1, "path_a", 0, _path)
meta(12, "path_b", 0, patch(roll(_path, 4, 8), [(3, 3, "1"), (4, 2, "2"), (11, 12, "1"), (2, 12, "1")]))

def mountain(a1, h1, a2, h2):
    """Two peaks (apex column, height); lit left faces (2), shaded right faces (1), snow rim (3)."""
    g = [["."] * 16 for _ in range(16)]
    for x in range(16):
        h, a = max((h - abs(x - a), a) for a, h in ((a1, h1), (a2, h2)))
        if h < 1:
            continue
        top = 16 - h
        for y in range(top, 16):
            g[y][x] = "3" if y - top < (2 if h >= 9 and y - top < h - 6 else 1) else ("2" if x <= a else "1")
            if g[y][x] in "12" and (x * 3 + y * 5) % 11 == 0:
                g[y][x] = "1" if g[y][x] == "2" else "2"
        g[15][x] = "1"
    return ["".join(r) for r in g]


def remap(rows, m):
    return ["".join(m.get(c, c) for c in r) for r in rows]


meta(2, "rock_a", 0, mountain(4, 13, 11, 9))
meta(13, "rock_b", 0, remap(grid("""
................
................
....3322........
...322221.......
...322221..332..
..3222211.32221.
..2222211.32221.
...11111..22211.
.332.......1111.
32221..33322....
32221.3222221...
22211.3222221...
.1111.2222211...
.332..2222211.33
32221..11111.322
22211.......2222
"""), {"3": "2", "2": "1", "1": "."}))
meta(14, "rock_c", 0, remap(grid("""
................
................
................
..33............
.3221...........
.32221..3.......
3222221322......
3222222222221...
2222222222221...
2222222222211.33
2222222222111322
2222222221111222
1222222211.11222
.11111111...1111
................
................
"""), {"3": "2", "2": "1", "1": "."}))


def glow(rows):
    """Lava: red body, orange only next to the yellow bubbles."""
    g = [list(r) for r in rows]
    for y in range(16):
        for x in range(16):
            if rows[y][x] == "2" and not any(rows[(y + dy) % 16][(x + dx) % 16] == "3" for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                g[y][x] = "1"
    return ["".join(r) for r in g]


def bubbles(base, off, on):
    g = [list(r) for r in base]
    for x, y in off:
        g[y][x] = "2"
    for x, y in on:
        g[y][x] = "3"
    return ["".join(r) for r in g]


_lava_a = grid("""
................
.11111..........
1122211....111..
122332211.12221.
1223332211122221
.1222221..112221
..11111....1111.
................
.........111....
.1111...11221...
12221..1222221..
1223211.122211..
.12221...1111...
..111....1.....1
...........11.11
....1111..1221..
""")
meta(3, "lava_a", 2, glow(_lava_a), glow(bubbles(_lava_a, [(3, 3), (4, 3), (5, 4), (3, 4), (4, 4), (3, 11)], [(13, 3), (10, 10), (11, 15), (9, 14)])))
_lava_b = grid("""
................
...1111....11...
..122221..1221..
.12233221.12221.
.1223221...1111.
..12221..111....
...1111..12221..
.........123221.
.1111.....1221..
12221......11...
123321...111111.
12221...12222221
.111....12333221
.......112222211
..11111..11111..
.12221..........
""")
meta(15, "lava_b", 2, glow(_lava_b), glow(bubbles(_lava_b, [(4, 3), (5, 3), (4, 10), (3, 10), (11, 12), (10, 12), (12, 12)], [(2, 2), (13, 2), (11, 9), (6, 7)])))
_lava_c = grid("""
................
.11......111....
1221....12221...
122211.1223221..
.12221.12333221.
..1111.122221.1.
......1.1111.121
.1111.......1221
12221..11....111
123221.1221.....
.12221.12221.11.
..111...111.1221
...........11221
.1111.......111.
12221...1111....
.111...122221...
""")
meta(43, "lava_c", 2, glow(_lava_c), glow(bubbles(_lava_c, [(11, 4), (12, 4), (4, 9), (5, 9), (10, 3)], [(3, 4), (4, 3), (9, 11), (14, 8), (7, 15)])))

# ---- temples (pal 1 walls, pal 3 roof)
_roof = ["3333333333333333",
         "1111111111111111",
         "3222322232223222",
         "2111211121112111",
         "2232223222322232",
         "1121112111211121",
         "3222322232223222",
         "2111211121112111",
         "2232223222322232",
         "1121112111211121",
         "3222322232223222",
         "2111211121112111",
         "3232323232323232",
         "1.1.1.1.1.1.1.1.",
         "................",
         "................"]
meta(5, "roof_m", 3, _roof)


def roof_end(rows):
    """Left end: slanted outline, eave tip curling up (right end = mirror)."""
    top = [7, 6, 5, 4, 3, 3, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0]
    bot = [10, 11, 12, 12, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13]
    g = [["." if not top[x] <= y <= bot[x] else rows[y][x] for x in range(16)] for y in range(16)]
    for x in range(16):                       # bright outline on the top edge, dark one under the eave
        if top[x] <= bot[x]:
            g[top[x]][x] = "3"
            if bot[x] + 1 < 16 and x > 3:
                g[bot[x] + 1][x] = "1" if x % 2 == 0 else "."
    return ["".join(r) for r in g]


meta(6, "roof_l", 3, roof_end(_roof))
meta(7, "roof_r", 3, hflip(roof_end(_roof)))
_wall = grid("""
3222222222222222
1111111111111111
.............1..
.111111111111...
.1..1...1...1...
.1..1...1...1...
.111111111111...
.1..1...1...1...
.1..1...1...1...
.111111111111...
.1..1...1...1...
.1..1...1...1...
.111111111111...
................
2222222222222222
1111111111111111
""")
meta(8, "wall_l", 1, ["3222" + r[4:] if y > 1 else r for y, r in enumerate(_wall)])
meta(9, "wall_r", 1, hflip(["3222" + r[4:] if y > 1 else r for y, r in enumerate(_wall)]))
meta(4, "wall", 1, grid("""
3333333333333333
2222222222222222
1111111111111111
................
1111.1111111.111
1111.1111111.111
................
1.1111111.111111
1.1111111.111111
................
1111.1111111.111
1111.1111111.111
................
1.1111111.111111
1.1111111.111111
................
"""))
meta(32, "door", 1, grid("""
2222222222222222
3333333333333333
1111111111111111
1..............1
1..............1
1....3....3....1
1...333..333...1
1....3....3....1
1..............1
1..............1
1..............1
11111111111111.1
22222222222222.2
2111111111111112
2222222222222222
1111111111111111
"""))
meta(16, "gate_locked", 2, grid("""
.22222222222222.
2111111111111112
.11222222222211.
..1..........1..
.21..2222222.12.
.21.2233333222..
.21.2333333322..
.21.2333223322..
.21.2333223322..
.21.2333333322..
.21..2233322....
.21...22222..12.
.21..........12.
.21..........12.
.21111111111112.
2222222222222222
"""))
meta(42, "gate_open", 3, grid("""
.22222222222222.
2111111111111112
.11222222222211.
..1..........1..
.21..........12.
.21....3.3...12.
.21...3...3..12.
.21.....3....12.
.21..3.......12.
.21....3...3.12.
.21...3..3...12.
.21.....3....12.
.21..3.......12.
.21..........12.
.21111111111112.
2222222222222222
"""))
meta(26, "tree", 0, grid("""
................
.....2.....3....
..3...2...32....
...2...2.32.....
....2..22.2.....
.....22.22......
..3...2222...3..
...22..22..22...
.....2222.22....
......222.......
......222.......
......2221......
.....22221......
.....2221.......
...3.22211.3....
.12222222222211.
"""))
_lan = grid("""
.......11.......
.......11.......
......1221......
.....122221.....
.....123321.....
.....123321.....
.....122221.....
.....123321.....
.....122221.....
......1221......
.......11.......
.......11.......
.......11.......
.......11.......
.......11.......
......1111......
""")
meta(27, "lantern", 2, _lan, patch(_lan, [(7, 4, "2"), (8, 5, "2"), (7, 5, "3")]))
_gra = grid("""
................
................
................
...3............
...3.......3....
..23.......3....
..23...3...2....
..22...3..22....
..22..22..2.....
..2..222..2...3.
..2..22..22...3.
.22..22..22..23.
.22.222..2..222.
.2..22..22..22..
.2.222.22..22...
11122211221221.1
""")
meta(28, "grass", 0, sway(_gra, -1, 0), sway(_gra, 1, 0))
meta(29, "skull", 0, grid("""
................
................
................
................
....33333333....
...3333333333...
..333333333333..
..333.3333.333..
..33...33...33..
..333.3333.333..
...3333..3333...
....33333333....
.....3.33.3.....
.....3.33.3.....
......3333......
................
"""))
meta(30, "bones", 0, grid("""
................
................
................
................
................
..3.............
.33...3.........
..3..33....3....
......3...33....
.3333333333.....
..3.3..3..33....
.33.33.33..3....
..3..3..3.......
................
................
................
"""))
_eyes = grid("""
................
................
................
................
................
................
................
...33......33...
..3..3....3..3..
...33......33...
................
................
................
................
................
................
""")
meta(31, "eyes", 2, _eyes, patch(_eyes, [(2, 8, "."), (5, 8, "."), (10, 8, "."), (13, 8, "."), (3, 7, "."), (4, 7, "."), (11, 7, "."), (12, 7, "."), (3, 9, "3"), (4, 9, "3"), (11, 9, "3"), (12, 9, "3"), (3, 8, "3"), (4, 8, "3"), (11, 8, "3"), (12, 8, "3")]))

# ---------------------------------------------------------------- arena tiles (8x8, palette 0 unless noted)
ARENA = {}    # name -> (fixed id or None, rows)


def tile(name, fixed, s):
    rows = s.strip("\n").split("\n")
    assert len(rows) == 8 and all(len(r) == 8 for r in rows), name
    ARENA[name] = (fixed, rows)


# Arena palette 0 = (backdrop, stone body, mortar/dark, edge light) per dungeon (dpal in src/dungeon.c); palette 2 = fire (lava).
# Back pillars use only colours 1 and 2 (they stay dim behind the fight).
tile("brick", 10, """
22222222
13111131
11111111
11111111
22222222
11311113
11111111
11111111
""")
tile("floor", 11, """
33333333
31111113
11111111
22222222
11113111
11111111
11111111
22222222
""")
tile("plat", 12, """
33333333
11111111
12121212
22222222
.1....1.
.1....1.
........
........
""")
tile("plat_l", None, """
.3333333
31111111
12121212
22222222
.1....1.
.1....1.
........
........
""")
tile("plat_r", None, """
3333333.
11111113
12121212
22222222
.1....1.
.1....1.
........
........
""")
tile("lava", 3, """
..3..3..
.22.223.
22222222
21222122
11121111
11111111
11111111
11111111
""")
tile("lava2", None, """
11111111
12111211
11111111
11211121
11111111
11112111
11111111
11111111
""")
tile("wall_out", None, """
11111111
12222221
12111121
12133121
12133121
12111121
12222221
11111111
""")
tile("beam0", None, """
33333333
11111111
12222221
11111111
11111111
12222221
11111111
11111111
""")
tile("beam1", None, """
33333333
11111111
13111131
11111111
22222222
.1.11.1.
..1..1..
........
""")
tile("cap_l", None, """
22222222
21111111
21111111
22222222
..211111
..211111
..211111
..211111
""")
tile("cap_r", None, """
22222222
11111112
11111112
22222222
111112..
111112..
111112..
111112..
""")
tile("pil_l", None, """
..211111
..211111
..211111
..211111
..211111
..211111
..211111
..222222
""")
tile("pil_r", None, """
111112..
111112..
111112..
111112..
111112..
111112..
111112..
222222..
""")
tile("base_l", None, """
..211111
..211111
22222222
21111111
21111111
21111111
22222222
11111111
""")
tile("base_r", None, """
111112..
111112..
22222222
11111112
11111112
11111112
22222222
11111111
""")


def build():
    fixed = {("gate_locked", 0): 7, ("gate_open", 0): 8}
    free = [1, 2, 4, 5, 6, 9] + list(range(50, 128))
    sheets = {"a": {}, "b": {}}   # id -> 8 rows
    used = set(fixed.values()) | {v[0] for v in ARENA.values() if v[0] is not None}
    free = [i for i in free if i not in used]
    for name, (fid, rows) in list(ARENA.items()):
        if fid is None:
            fid = free.pop(0)
            ARENA[name] = (fid, rows)
        sheets["a"][fid] = sheets["b"][fid] = tuple(rows)
    arena_ids = {n: v[0] for n, v in ARENA.items()}

    def cut(rows, tx, ty):
        return tuple(rows[ty * 8 + y][tx * 8:tx * 8 + 8] for y in range(8))

    pending = []
    for cid, (name, pal, ra, rb) in sorted(ART.items()):
        for ti, (tx, ty) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
            pending.append((cid, name, ti, cut(ra, tx, ty), cut(rb, tx, ty)))
    next_anim, tid, anim_pairs, static_pairs = 128, {}, {}, {}
    for cid, name, ti, ta, tb in pending:          # animated tiles must live in 128..255
        if (name, ti) in fixed:
            assert ta == tb
            tid[(cid, ti)] = fixed[(name, ti)]
            sheets["a"][tid[(cid, ti)]] = sheets["b"][tid[(cid, ti)]] = ta
        elif ta != tb:
            if (ta, tb) not in anim_pairs:
                anim_pairs[(ta, tb)] = next_anim
                sheets["a"][next_anim], sheets["b"][next_anim] = ta, tb
                next_anim += 1
            tid[(cid, ti)] = anim_pairs[(ta, tb)]
    for cid, name, ti, ta, tb in pending:          # static tiles: free R0 slots first, then spill into 128..
        if (cid, ti) in tid:
            continue
        if ta not in static_pairs:
            i = free.pop(0) if free else next_anim
            next_anim += 0 if free or i != next_anim else 1
            static_pairs[ta] = i
            sheets["a"][i] = sheets["b"][i] = ta
        tid[(cid, ti)] = static_pairs[ta]
    assert next_anim <= 256, "out of tile ids"
    table = {cid: ([tid[(cid, ti)] for ti in range(4)], pal) for cid, (name, pal, ra, rb) in ART.items()}
    return sheets, table, arena_ids, next_anim


def write_pngs(sheets):
    def save(path, tiles_):
        img = Image.new("P", (128, 64), 0)
        img.putpalette([0, 0, 0, 64, 64, 64, 128, 128, 128, 255, 255, 255] + [0] * 756)
        for i, rows in tiles_.items():
            for y, r in enumerate(rows):
                for x, c in enumerate(r):
                    img.putpixel(((i % 16) * 8 + x, (i // 16) * 8 + y), 0 if c == "." else int(c))
        img.save(path)

    old = Image.open("assets/sprites/tiles.png")
    cur = {}
    if old.size[1] == 8:                           # first run: the old one-row strip
        cells = [(i * 8, 0) for i in range(old.size[0] // 8)]
    else:
        cells = [((i % 16) * 8, (i // 16) * 8) for i in range(128)]
    for i, (ox, oy) in enumerate(cells):
        cur[i] = tuple("".join("." if old.getpixel((ox + x, oy + y)) == 0 else str(old.getpixel((ox + x, oy + y))) for x in range(8)) for y in range(8))
    for i in list(range(1, 13)) + list(range(50, 128)):
        cur.pop(i, None)
    cur.update({i: r for i, r in sheets["a"].items() if i < 128})
    save("assets/sprites/tiles.png", cur)
    save("assets/sprites/anim_a.png", {i - 128: r for i, r in sheets["a"].items() if i >= 128})
    save("assets/sprites/anim_b.png", {i - 128: r for i, r in sheets["b"].items() if i >= 128})


def write_header(table, arena_ids, next_anim):
    n = max(table) + 1
    out = ["/* Generated by tools/art/bgart.py (docs/TECH.md \"Hintergrund-Kunst (v0.9)\"). Metatile table indexed by cell id. */",
           "/* META_N metatiles (cell ids) + META_BLANK (all tiles 0, palette 0): an empty scene cell. Defined once (main.c: #define META_DEF), extern elsewhere. */",
           f"#define META_N {n + 1}", f"#define META_BLANK {n}", "#ifdef META_DEF",
           "#define META_T(nm, ...) const unsigned char nm[META_N] = { __VA_ARGS__ };", "#else",
           "#define META_T(nm, ...) extern const unsigned char nm[META_N];", "#endif"]
    for k, nm in enumerate(("tl", "tr", "bl", "br")):
        out.append(f"META_T(meta_{nm}, " + ",".join(str(table.get(c, table[0])[0][k]) for c in range(n)) + ",0)")
    for sh in (0, 2, 4, 6):                    # palette number pre-shifted into its attribute-byte quadrant (speed)
        out.append(f"META_T(meta_pal{sh if sh else ''}, " + ",".join(str(table.get(c, table[0])[1] << sh) for c in range(n)) + ",0)")
    out.append(f"/* tile ids used: up to {next_anim - 1} (128.. = animated or spill) */")
    open("src/meta.h", "w").write("\n".join(out) + "\n")
    out = ["/* Generated by tools/art/bgart.py: arena tile ids (dungeon.c). */"]
    out += [f"#define T_{nm.upper()} {i}" for nm, i in arena_ids.items()]
    open("src/arena.h", "w").write("\n".join(out) + "\n")


def preview(path):
    S, COLS = 5, 10
    items = []
    for cid in sorted(ART):
        name, pal, ra, rb = ART[cid]
        items += [(pal, ra)] + ([(pal, rb)] if ra != rb else [])
    rows_n = (len(items) + COLS - 1) // COLS
    img = Image.new("RGB", (4 + COLS * 17 * S, 4 + rows_n * 17 * S), (24, 24, 24))
    for k, (pal, rows) in enumerate(items):
        ox, oy = 4 + (k % COLS) * 17 * S, 4 + (k // COLS) * 17 * S
        for y in range(16):
            for x in range(16):
                c = rows[y][x]
                col = tuple(int(NES[PAL[pal][0 if c == "." else int(c)]][i:i + 2], 16) for i in (0, 2, 4))
                for sy in range(S):
                    for sx in range(S):
                        img.putpixel((ox + x * S + sx, oy + y * S + sy), col)
    img.save(path)


if __name__ == "__main__":
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
    else:
        sheets, table, arena_ids, next_anim = build()
        write_pngs(sheets)
        write_header(table, arena_ids, next_anim)
        print(f"tile ids up to {next_anim - 1}; arena ids {arena_ids}")
