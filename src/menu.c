/* Title + start menu, intro and ending screen: drawn with rendering off. Docs: docs/TECH.md "Titel, Intro und Ende (v0.9)".
   Banked code: never calls bank_set, only fixed code (main.c, crt0.s, sfx.s). */
#pragma code-name("BANK10")
#pragma rodata-name("BANK10")
#include <string.h>
#include "nes.h"
#include "meta.h"                      /* overworld metatiles: the title and intro scenes reuse them */
#include "ui.h"                        /* tile ids of the big letters, punctuation and the ending sky */

#define END_LEN 240                    /* ending screen: 4 s, Start leaves after 1 s */
#define INTRO_LEN 240                  /* intro page: 4 s, A turns the page early, Start skips the rest */
#define NPAGE 3
#define ITEM_ROW 12                    /* first menu entry; 2 tile rows apart */
#define ITEM_COL 12

/* Menu entries by id; the visible list (mid[], mn) leaves out CONTINUE and DELETE SAVE without a save. */
static const char *const item[] = { "CONTINUE", "NEW GAME", "CHEAT", "DELETE SAVE" };
static unsigned char mid[4], mn;
unsigned char attr[64];                /* attribute table being built (metatile palettes, ppu.s scene_draw; flushed by screen_go) */

/* Scene cells are metatile indices of meta.h (16 per row, 2 tile rows each); X = nothing. */
#define X META_BLANK
#define LA 27                          /* lantern (animated flame) */
#define LV 3,15,3,3,15,43,3,15         /* a stretch of lava (animated) */
static const unsigned char title_scene[15 * 16] = {
    X,X,X,X,X,X,X,X,X,X,X,X,X,X,X,X,
    X,X,LA,X,X,X,X,X,X,X,X,X,X,LA,X,X,
    X,X,LA,X,X,X,X,X,X,X,X,X,X,LA,X,X,
    X,X,X,X,X,X,X,X,X,X,X,X,X,X,X,X,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
    X,X,X,X,X,X,X,X,X,X,X,X,X,X,X,X,
    X,X,X,X,X,X,X,X,X,X,X,X,X,X,X,X,
    6,5,7,X,X,X,X,X,X,X,X,X,X,6,5,7,
    8,32,9,X,X,X,X,X,X,X,X,X,X,8,32,9,
    LA,16,LA,X,X,X,X,X,X,X,X,X,X,LA,42,LA,      /* left gate locked (seal), right gate open */
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    LV,LV,
    LV,LV,
    LV,LV,
    LV,LV
};
static const unsigned char intro_scene[5 * 16] = {
    X,LA,X,X,X,X,X,X,X,X,X,X,X,X,LA,X,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    LV,LV,
    15,3,3,15,43,3,15,3,3,15,3,43,3,3,15,3,
    3,15,43,3,3,15,3,3,15,3,15,3,43,3,15,3
};
#undef LV
#undef LA
#undef X

/* Background palettes: 0 ground / text (lavender), 1 walls, 2 lava / lanterns / logo (red, orange, gold), 3 roofs;
   sprite palette 0 = hero, 2 = cursor heart. */
static const unsigned char pal_title[32] = {
    0x0F,0x02,0x03,0x32, 0x0F,0x06,0x16,0x26, 0x0F,0x16,0x27,0x38, 0x0F,0x03,0x12,0x21,
    0x0F,0x17,0x21,0x36, 0x0F,0x06,0x16,0x30, 0x0F,0x16,0x30,0x10, 0x0F,0x21,0x31,0x30
};
/* Dawn, top down: palette 0 violet, 1 magenta, 3 crimson, 2 orange (= the logo palette, band colour in entry 2, sun in 3).
   Entry 2 of 1 and 3 is the band above, for the dithered start of the band; entry 3 of 0/1/3 = white text. */
static const unsigned char pal_end[32] = {
    0x0F,0x03,0x0F,0x30, 0x0F,0x04,0x03,0x30, 0x0F,0x16,0x27,0x38, 0x0F,0x15,0x04,0x30,
    0x0F,0x17,0x21,0x36, 0x0F,0x06,0x16,0x30, 0x0F,0x16,0x30,0x10, 0x0F,0x21,0x31,0x30
};
/* Ending attribute byte rows (all 8 bytes of a row alike): logo / violet / magenta / crimson / horizon / black. */
static const unsigned char end_attr[8] = { 0xAA, 0x00, 0x55, 0xFF, 0xAA, 0x00, 0x00, 0x00 };

/* Tile of a text character: font letters (X and Z are new), three punctuation marks, blank. */
static unsigned char glyph(char c)
{
    if (c > 'A' - 1 && c != 'X' && c != 'Z') return ftile[c - 'A'];       /* the common case first (speed: the redraw is black) */
    if (c == '.') return U_DOT;
    if (c == '!') return U_EXC;
    if (c == '?') return U_Q;
    if (c == 'X') return U_X;
    if (c == 'Z') return U_Z;
    return 0;
}

static void at(unsigned char row, unsigned char col)
{
    unsigned int a = 0x2000 + ((unsigned int)row << 5) + col;
    PPU_ADDR = a >> 8; PPU_ADDR = a;
}

/* Text on a nametable-0 row, rendering off; col 0 = centered. (statics: cc65 is much faster without stack locals) */
static unsigned char tl;
static const char *tp;
static void put_text(const char *s, unsigned char row, unsigned char col)
{
    tl = 0;
    while (s[tl]) ++tl;
    at(row, col ? col : (32 - tl) >> 1);
    for (tp = s; *tp; ++tp) PPU_DATA = glyph(*tp);
}

/* Big 2x2-tile letters (U_BIGSET: A C D E F G H I L M N O P R S U Y = k 0..16, tiles U_BIG0 + 4k + TL TR BL BR). A line is its
   top-row tiles, then its bottom-row tiles; a space is one blank tile. Constant data: the title screen is black while it is drawn. */
#define K(k, p) U_BIG0 + 4 * (k) + (p), U_BIG0 + 4 * (k) + (p) + 1     /* letter k, p = 0 top row, 2 bottom row */
#define ESCAPING(p) K(3,p), K(14,p), K(1,p), K(0,p), K(12,p), K(7,p), K(10,p), K(5,p)
#define FROM_HELL(p) K(4,p), K(13,p), K(11,p), K(9,p), 0, K(6,p), K(3,p), K(8,p), K(8,p)
#define YOU_ESCAPED(p) K(16,p), K(11,p), K(15,p), 0, K(3,p), K(14,p), K(1,p), K(0,p), K(12,p), K(3,p), K(2,p)
static const unsigned char big_escaping[] = { ESCAPING(0), ESCAPING(2) };
static const unsigned char big_from_hell[] = { FROM_HELL(0), FROM_HELL(2) };
static const unsigned char big_you_escaped[] = { YOU_ESCAPED(0), YOU_ESCAPED(2) };

/* A big line b (2 * n tiles) on rows row, row + 1, centered. */
static void put_big(const unsigned char *b, unsigned char n, unsigned char row)
{
    at(row, (32 - n) >> 1);
    ppu_copy(b, n);
    at(row + 1, (32 - n) >> 1);
    ppu_copy(b + n, n);
}

/* n rows of a scene table from cell row r0 down (ppu.s scene_draw); the attribute bits of every cell are collected into attr[]. */
#define draw_cells scene_draw

/* The overworld hero (sprite tiles 0..3, palette 0) standing at x 120, sprite top y. */
static void put_hero(unsigned char y)
{
    unsigned char r;
    for (r = 0; r < 4; ++r) {
        oam[r * 4] = y + (r >> 1) * 8;
        oam[r * 4 + 1] = r;
        oam[r * 4 + 2] = 0;
        oam[r * 4 + 3] = 120 + (r & 1) * 8;
    }
}

/* Blank screen with palette p, all sprites hidden; the caller draws and calls screen_go. */
static void blank_screen(const unsigned char *p)
{
    screen_off();
    PPU_ADDR = 0x3F; PPU_ADDR = 0x00;
    ppu_copy(p, 32);
    PPU_ADDR = 0x20; PPU_ADDR = 0x00;
    ppu_fill(0, 1024);
    memset(attr, 0, 64);
    oam_hide();
    scroll_x = 0;
}

static void screen_go(void)
{
    PPU_ADDR = 0x23; PPU_ADDR = 0xC0;
    ppu_copy(attr, 64);
    screen_on(0x88);
}

/* Title scene, then either the entries or (menu_conf) the DELETE SAVE question. */
static void menu_draw(void)
{
    unsigned char i, v = save_valid();
    blank_screen(pal_title);
    for (i = 0; i < 16; ++i) attr[i] = 0xAA;          /* rows 0..7 = logo palette */
    draw_cells(title_scene, 0, 15);
    put_big(big_escaping, sizeof big_escaping / 2, 3);
    put_big(big_from_hell, sizeof big_from_hell / 2, 6);
    if (menu_conf) {
        put_text("DELETE SAVE?", ITEM_ROW + 2, 0);
        put_text("A YES   B NO", ITEM_ROW + 5, 0);
    } else {
        mn = 0;
        if (v) mid[mn++] = 0;
        mid[mn++] = 1; mid[mn++] = 2;
        if (v) mid[mn++] = 3;
        for (i = 0; i < mn; ++i) put_text(item[mid[i]], ITEM_ROW + 2 * i, ITEM_COL);
        oam[1] = 14; oam[2] = 2; oam[3] = (ITEM_COL - 2) * 8;     /* cursor: heart */
        oam[0] = (ITEM_ROW + 2 * menu_sel) * 8 - 1;
    }
    screen_go();
}

void menu_enter(void)
{
    menu_sel = menu_conf = 0;
    music_play(MUS_TITLE);              /* the intro goes on with it */
    game_state = ST_MENU;
    menu_draw();
}

/* 0 = nothing yet, else 1 CONTINUE / 2 NEW GAME / 3 CHEAT. DELETE SAVE asks first (A yes, B no) and redraws. */
unsigned char menu_frame(void)
{
    unsigned char id;
    if (menu_conf) {
        if (PRESSED(PAD_A | PAD_B)) {
            if (PRESSED(PAD_A)) { save_clear(); menu_sel = 0; }
            menu_conf = 0;
            sfx_play(SFX_OK);
            menu_draw();
        }
        return 0;
    }
    if (PRESSED(PAD_UP)) { menu_sel = menu_sel ? menu_sel - 1 : mn - 1; sfx_play(SFX_MOVE); }
    if (PRESSED(PAD_DOWN | PAD_SELECT)) { menu_sel = menu_sel + 1 < mn ? menu_sel + 1 : 0; sfx_play(SFX_MOVE); }
    oam[0] = (ITEM_ROW + 2 * menu_sel) * 8 - 1;
    if (!PRESSED(PAD_A | PAD_START)) return 0;
    sfx_play(SFX_OK);
    id = mid[menu_sel];
    if (id == 3) { menu_conf = 1; menu_draw(); return 0; }
    return id + 1;
}

static const char *const intro_txt[NPAGE][2] = {
    { "YOU AWAKE", "IN HELL." },
    { "TEN DEMONS GUARD", "THE WAY OUT." },
    { "DEFEAT THEM.", "ESCAPE." }
};

static void intro_draw(void)
{
    blank_screen(pal_title);
    draw_cells(intro_scene, 10, 5);
    put_text(intro_txt[ui_page][0], 7, 0);
    put_text(intro_txt[ui_page][1], 10, 0);
    put_text("A NEXT   START SKIP", 16, 0);
    put_hero(163);
    ui_t = INTRO_LEN;
    screen_go();
}

void intro_enter(void)
{
    ui_page = 0;
    game_state = ST_INTRO;
    intro_draw();
}

/* 1 = intro over. */
unsigned char intro_frame(void)
{
    if (PRESSED(PAD_START)) return 1;
    if (!--ui_t || PRESSED(PAD_A)) {
        sfx_play(SFX_MOVE);
        if (++ui_page == NPAGE) return 1;
        intro_draw();
    }
    return 0;
}

void end_enter(void)
{
    unsigned char r;
    blank_screen(pal_end);
    at(4, 0);
    for (r = 4; r < 17; ++r) ppu_fill((r & 3) ? U_SKY1 : U_DITH, 32);   /* sky bands: solid tiles, the palette of each band colours them */
    ppu_copy(u_sky17, 32);                             /* sun and mountain silhouettes on the horizon */
    ppu_copy(u_sky18, 32);
    ppu_copy(u_sky19, 32);
    for (r = 0; r < 64; ++r) attr[r] = end_attr[r >> 3];
    put_big(big_you_escaped, sizeof big_you_escaped / 2, 2);
    put_text("THE END", 22, 0);
    put_text("THANKS FOR PLAYING", 25, 0);
    put_hero(146);                                     /* the hero walks out of hell into the dawn */
    end_t = END_LEN;
    sfx_play(SFX_END);
    music_play(MUS_ENDING);
    game_state = ST_END;
    screen_go();
}

/* 1 = back to the overworld. */
unsigned char end_frame(void)
{
    return !--end_t || (end_t < END_LEN - 60 && PRESSED(PAD_START));
}
