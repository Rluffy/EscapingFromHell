#!/usr/bin/env python3
"""UI tiles of v0.9 package 5 (title logo, punctuation, ending sky): docs/TECH.md "Titel, Intro und Ende (v0.9)".

Run from the repo root: python3 tools/art/uiart.py
Writes the tile ids 152.. (R1 sheet, the same tile in anim_a.png and anim_b.png, so they do not flicker) and src/ui.h.
Only those ids are touched; the animated overworld tiles 128..151 stay. Re-running is safe (idempotent).
"""
from PIL import Image

FONT = dict(A=37, B=43, C=33, D=26, E=30, F=48, G=29, H=39, I=13, J=45, K=46, L=44, M=14, N=28, O=31, P=15, Q=49,
            R=35, S=38, T=34, U=27, V=32, W=47, Y=36)
BIGSET = "ACDEFGHILMNOPRSUY"          # letters of ESCAPING FROM HELL / YOU ESCAPED, 2x2 tiles each
FIRST = 152

PUNCT = {  # 5x7 glyphs in tile columns 1..5, like the font
    ".": ["........", "........", "........", "........", "........", "........", ".3......", "........"],
    "!": [".3......", ".3......", ".3......", ".3......", ".3......", "........", ".3......", "........"],
    "?": [".3333...", ".3...3..", ".....3..", "...33...", "...3....", "........", "...3....", "........"],
    "X": [".3...3..", ".3...3..", "..3.3...", "...3....", "..3.3...", ".3...3..", ".3...3..", "........"],
    "+": ["........", "...3....", "...3....", ".33333..", "...3....", "...3....", "........", "........"],
    "Z": [".33333..", ".....3..", "....3...", "...3....", "..3.....", ".3......", ".33333..", "........"],
}


def font_rows():
    im = Image.open("assets/sprites/tiles.png")
    out = {}
    for ch, t in FONT.items():
        tx, ty = (t % 16) * 8, (t // 16) * 8
        out[ch] = ["".join("." if im.getpixel((tx + x, ty + y)) == 0 else "3" for x in range(8)) for y in range(8)]
    return out


def big(glyph):
    """8x8 glyph -> 16x16 tile block: 2x scale, fill 2, lit top/left edges 3, 2 px drop shadow 1."""
    on = lambda x, y: 0 <= x < 16 and 0 <= y < 16 and glyph[y // 2][x // 2] != "."
    px = [["."] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            if on(x, y):
                px[y][x] = "3" if not on(x, y - 1) or not on(x - 1, y) else "2"
            elif on(x - 1, y - 1) or on(x - 2, y - 2):
                px[y][x] = "1"
    return ["".join(r) for r in px]


def quad(rows):
    return [tuple(r[tx * 8:tx * 8 + 8] for r in rows[ty * 8:ty * 8 + 8]) for ty, tx in ((0, 0), (0, 1), (1, 0), (1, 1))]


def build():
    tiles, ids = [], {}

    def add(rows, name=None):
        rows = tuple(rows)
        if rows not in tiles:
            tiles.append(rows)
        if name:
            ids[name] = FIRST + tiles.index(rows)
        return FIRST + tiles.index(rows)

    for ch, g in PUNCT.items():
        if ch != "+":
            add(g, {".": "DOT", "!": "EXC", "?": "Q", "X": "X", "Z": "Z"}[ch])
    ids["BIG0"] = FIRST + len(tiles)
    fr = font_rows()
    for ch in BIGSET:
        for q in quad(big(fr[ch])):                # TL, TR, BL, BR; copies are kept (the C code assumes 4 per letter)
            tiles.append(q)
    add(["1" * 8] * 8, "SKY1")                     # solid band colour: palette entry 1 (upper bands) ...
    sky2 = add(["2" * 8] * 8, "SKY2")               # ... entry 2 (horizon band, whose palette is the logo palette)
    add(["12121212" if y % 2 == 0 else "21212121" for y in range(8)], "DITH")   # checker band start: entry 1 / entry 2 (the band above)
    # sun: half disc 48x24 (entry 3) on the horizon band colour, flat at the ground
    sun = [["2"] * 48 for _ in range(24)]
    for y in range(24):
        for x in range(48):
            if (x - 23.5) ** 2 + (y - 24) ** 2 <= 24.5 ** 2:
                sun[y][x] = "3"
    sunrows = ["".join(r) for r in sun]
    sunid = [[add([sunrows[ty * 8 + y][tx * 8:tx * 8 + 8] for y in range(8)]) for tx in range(6)] for ty in range(3)]
    # skyline: heights (units of 8 px, 0..3) at the 33 tile column borders, steps of at most 1 = 45 degree slopes
    h = [1, 2, 3, 3, 2, 1, 2, 2, 1, 0, 1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 3, 3, 2, 1, 1, 2, 3, 2, 1, 1]
    upt = ["".join("." if (7 - y) <= x else "2" for x in range(8)) for y in range(8)]   # black under a line rising to the right
    dnt = [r[::-1] for r in upt]
    up, dn = add(upt, "UP"), add(dnt, "DN")
    rows = ([], [], [])                             # tile rows 17, 18, 19 (level 2, 1, 0)
    for c in range(32):
        a, b = h[c], h[c + 1]
        for j, lv in enumerate((2, 1, 0)):
            if 13 <= c <= 18:
                rows[j].append(sunid[j][c - 13]); continue
            rows[j].append(0 if min(a, b) >= lv + 1 else sky2 if max(a, b) <= lv else up if a < b else dn)
    add(PUNCT["+"], "PLUS")                         # last, so no other id moves (v1.1: ability hints "UP + B")
    assert FIRST + len(tiles) <= 256, f"out of tile ids: {FIRST + len(tiles)}"
    return tiles, ids, rows


def write(tiles):
    for name in ("anim_a", "anim_b"):
        path = f"assets/sprites/{name}.png"
        im = Image.open(path)
        for i, rows in enumerate(tiles):
            t = FIRST - 128 + i
            for y, r in enumerate(rows):
                for x, c in enumerate(r):
                    im.putpixel(((t % 16) * 8 + x, (t // 16) * 8 + y), 0 if c == "." else int(c))
        im.save(path)


def header(tiles, ids, rows):
    o = ["/* Generated by tools/art/uiart.py (docs/TECH.md \"Titel, Intro und Ende (v0.9)\"): UI tile ids in R1 (128..255). */"]
    o += [f"#define U_{k} {v}" for k, v in ids.items()]
    o.append(f'#define U_BIGSET "{BIGSET}"      /* big letter k = 4 tiles U_BIG0 + 4k: TL TR BL BR */')
    o.append(f"/* last used tile id {FIRST + len(tiles) - 1} */")
    for n, r in zip((17, 18, 19), rows):
        o.append(f"static const unsigned char u_sky{n}[32] = {{ " + ",".join(map(str, r)) + " };")
    open("src/ui.h", "w").write("\n".join(o) + "\n")


if __name__ == "__main__":
    t, i, rows = build()
    write(t)
    header(t, i, rows)
    print(f"ui tiles {FIRST}..{FIRST + len(t) - 1} ({len(t)} tiles), ids {i}")
