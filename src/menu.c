/* Title + start menu, intro and ending screen: drawn with rendering off. Docs: docs/TECH.md "Titel, Intro und Ende (v0.9)".
   Banked code: never calls bank_set, only fixed code (main.c, crt0.s, sfx.s). */
#pragma code-name("BANK10")
#pragma rodata-name("BANK10")
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
static unsigned char attr[64];         /* attribute table being built (metatile palettes, flushed by screen_go) */

/* Scene cells are metatile indices of meta.h (16 per row, 2 tile rows each); X = nothing. */
#define X 255
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
    if (c == '.') return U_DOT;
    if (c == '!') return U_EXC;
    if (c == '?') return U_Q;
    if (c == 'X') return U_X;
    if (c == 'Z') return U_Z;
    return c > ' ' ? ftile[c - 'A'] : 0;
}

static void at(unsigned char row, unsigned char col)
{
    unsigned int a = 0x2000 + ((unsigned int)row << 5) + col;
    PPU_ADDR = a >> 8; PPU_ADDR = a;
}

/* Text on a nametable-0 row, rendering off; col 0 = centered. */
static void put_text(const char *s, unsigned char row, unsigned char col)
{
    unsigned char l = 0;
    while (s[l]) ++l;
    at(row, col ? col : (32 - l) >> 1);
    for (; *s; ++s) PPU_DATA = glyph(*s);
}

/* Big 2x2-tile letters (U_BIGSET) on rows row, row + 1, centered; a space is one tile wide. */
static void put_big(const char *s, unsigned char row)
{
    unsigned char w = 0, p, k, t;
    const char *c;
    for (c = s; *c; ++c) w += *c == ' ' ? 1 : 2;
    for (p = 0; p < 2; ++p) {
        at(row + p, (32 - w) >> 1);
        for (c = s; *c; ++c) {
            if (*c == ' ') { PPU_DATA = 0; continue; }
            for (k = 0; U_BIGSET[k] != *c; ++k) ;
            t = U_BIG0 + 4 * k + 2 * p;
            PPU_DATA = t; PPU_DATA = t + 1;
        }
    }
}

/* n rows of a scene table from cell row r0 down; the attribute bits of every cell are collected into attr[]. */
static void draw_cells(const unsigned char *t, unsigned char r0, unsigned char n)
{
    unsigned char r, c, k, m;
    for (r = 0; r < n; ++r)
        for (k = 0; k < 2; ++k) {
            at((r0 + r) * 2 + k, 0);
            for (c = 0; c < 16; ++c) {
                m = t[(r << 4) + c];
                if (m == 255) { PPU_DATA = 0; PPU_DATA = 0; continue; }
                PPU_DATA = k ? meta_bl[m] : meta_tl[m];
                PPU_DATA = k ? meta_br[m] : meta_tr[m];
                if (!k) attr[((r0 + r) >> 1 << 3) + (c >> 1)] |= meta_pal[m] << (((c & 1) << 1) | (((r0 + r) & 1) << 2));
            }
        }
}

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
    unsigned int i;
    screen_off();
    PPU_ADDR = 0x3F; PPU_ADDR = 0x00;
    for (i = 0; i < 32; ++i) PPU_DATA = p[i];
    PPU_ADDR = 0x20; PPU_ADDR = 0x00;
    for (i = 0; i < 1024; ++i) PPU_DATA = 0;
    for (i = 0; i < 256; i += 4) oam[i] = 0xFF;
    for (i = 0; i < 64; ++i) attr[i] = 0;
    scroll_x = 0;
}

static void screen_go(void)
{
    unsigned char i;
    PPU_ADDR = 0x23; PPU_ADDR = 0xC0;
    for (i = 0; i < 64; ++i) PPU_DATA = attr[i];
    screen_on(0x88);
}

/* Title scene, then either the entries or (menu_conf) the DELETE SAVE question. */
static void menu_draw(void)
{
    unsigned char i, v = save_valid();
    blank_screen(pal_title);
    for (i = 0; i < 16; ++i) attr[i] = 0xAA;          /* rows 0..7 = logo palette */
    draw_cells(title_scene, 0, 15);
    put_big("ESCAPING", 3);
    put_big("FROM HELL", 6);
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
    unsigned char r, c;
    blank_screen(pal_end);
    for (r = 4; r < 17; ++r) {                         /* sky bands: solid tiles, the palette of each band colours them */
        at(r, 0);
        for (c = 0; c < 32; ++c) PPU_DATA = (r & 3) ? U_SKY1 : U_DITH;
    }
    for (c = 0; c < 32; ++c) PPU_DATA = u_sky17[c];    /* sun and mountain silhouettes on the horizon */
    for (c = 0; c < 32; ++c) PPU_DATA = u_sky18[c];
    for (c = 0; c < 32; ++c) PPU_DATA = u_sky19[c];
    for (r = 0; r < 64; ++r) attr[r] = end_attr[r >> 3];
    put_big("YOU ESCAPED", 2);
    put_text("THE END", 22, 0);
    put_text("THANKS FOR PLAYING", 25, 0);
    put_hero(146);                                     /* the hero walks out of hell into the dawn */
    end_t = END_LEN;
    sfx_play(SFX_END);
    game_state = ST_END;
    screen_go();
}

/* 1 = back to the overworld. */
unsigned char end_frame(void)
{
    return !--end_t || (end_t < END_LEN - 60 && PRESSED(PAD_START));
}
