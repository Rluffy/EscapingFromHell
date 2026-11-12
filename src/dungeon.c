/* Dungeon arena: one screen, side view. Docs: docs/TECH.md "Dungeon (v0.3)". */
#include "nes.h"

#define ST_DUNGEON 3
#define FLOOR_Y    192                 /* top of the floor = feet position of a standing player */
#define WALL       16                  /* wall width in px */
#define HEARTS_MAX 3
#define INVULN     90
#define KNOCK      8                   /* knockback frames, 3 px/frame */
#define SWORD_LEN  8
#define SWORD_CD   20
#define ENEMY_HP   5
#define ENEMY_HIT  12                  /* enemy invulnerable after a sword hit (blinks) */

/* One-way platforms, 48 px wide (6 tiles); x and y are multiples of 8. */
static const unsigned char plat_x[3] = { 32, 176, 104 };
static const unsigned char plat_y[3] = { 152, 152, 112 };

/* Per-dungeon BG palette 0 (backdrop, floor, mortar, edge); sprite palettes are shared. */
static const unsigned char dpal[10][4] = {
    {0x02,0x11,0x01,0x21}, {0x0F,0x16,0x06,0x26}, {0x01,0x14,0x04,0x24}, {0x0A,0x1A,0x0B,0x2A},
    {0x08,0x18,0x07,0x28}, {0x03,0x13,0x02,0x23}, {0x0C,0x1C,0x0B,0x2C}, {0x09,0x19,0x0A,0x29},
    {0x05,0x15,0x04,0x25}, {0x0F,0x00,0x2D,0x10}
};
/* Sprite palettes 0..3 without the backdrop: player, enemy, heart + sword, unused. */
static const unsigned char spal[12] = { 0x17,0x21,0x36, 0x06,0x16,0x30, 0x16,0x30,0x10, 0x17,0x21,0x36 };

static unsigned char facing;           /* 0 right, 1 left */
static unsigned char sword_cd, gtick;
static signed char   kb_dir;           /* knockback px/frame, signed */
static unsigned char kb_t;

/* OAM layout (byte offsets): player 0, sword 16, enemy 24, hearts 40. */
#define O_SWORD  16
#define O_ENEMY  24
#define O_HEART  40

static unsigned char arena_tile(unsigned char r, unsigned char c)
{
    unsigned char i, c0;
    if (r >= 24) return r == 24 ? 11 : 10;
    if (c < 2 || c >= 30) return 10;
    if (r != 14 && r != 19) return 0;      /* platform rows only: keeps the redraw short */
    for (i = 0; i < 3; ++i) {
        c0 = plat_x[i] >> 3;
        if (r == (plat_y[i] >> 3) && c >= c0 && c < c0 + 6) return 12;
    }
    return 0;
}

static unsigned char overlap(unsigned char ax, unsigned char ay, unsigned char aw, unsigned char ah,
                             unsigned char bx, unsigned char by, unsigned char bw, unsigned char bh)
{
    return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah;
}

/* Fresh fight: also the restart after the last heart. The screen stays as it is. */
static void arena_reset(void)
{
    hearts = HEARTS_MAX;
    invuln = sword_t = sword_cd = kb_t = gtick = paused = 0;
    vy = 0;
    on_ground = 1;
    facing = 0;
    player_x = 48;
    player_y = FLOOR_Y - 16;
    en.x = 160; en.y = FLOOR_Y - 16; en.w = 16; en.h = 16;
    en.hp = ENEMY_HP; en.flash = 0; en.dir = -1;
}

void dungeon_enter(void)
{
    unsigned char i, j, r, c;
    const unsigned char *p = dpal[cur_dungeon - 1];

    screen_off();
    PPU_ADDR = 0x3F;
    PPU_ADDR = 0x00;
    for (i = 0; i < 4; ++i)
        for (j = 0; j < 4; ++j) PPU_DATA = p[j];
    for (i = 0; i < 4; ++i) {
        PPU_DATA = p[0];                /* $3F10 mirrors the backdrop */
        for (j = 0; j < 3; ++j) PPU_DATA = spal[i * 3 + j];
    }
    PPU_ADDR = 0x20;
    PPU_ADDR = 0x00;
    for (r = 0; r < 30; ++r)
        for (c = 0; c < 32; ++c) PPU_DATA = arena_tile(r, c);
    for (i = 0; i < 64; ++i) PPU_DATA = 0;      /* attributes: palette 0 everywhere */

    for (i = 0; i < 4; ++i) {           /* sprite tiles/palettes: player 4..7, sword 12/13, enemy 8..11, hearts */
        oam[i * 4 + 1] = 4 + i;
        oam[O_ENEMY + i * 4 + 1] = 8 + i;
        oam[O_ENEMY + i * 4 + 2] = 1;
    }
    for (i = 0; i < 2; ++i) oam[O_SWORD + i * 4 + 1] = 12 + i;
    for (i = 0; i < 3; ++i) {
        oam[O_HEART + i * 4]     = 15;
        oam[O_HEART + i * 4 + 2] = 2;
        oam[O_HEART + i * 4 + 3] = 24 + i * 10;
    }
    arena_reset();
    scroll_x = 0;
    game_state = ST_DUNGEON;
    screen_on(0x88);
}

static void update_player(void)
{
    int nx, ny;
    unsigned char i, land;
    signed char dx = 0;

    if (invuln) --invuln;
    if (sword_cd) --sword_cd;
    if (sword_t) --sword_t;

    if (kb_t) {
        --kb_t;
        dx = kb_dir;
    } else {
        if (pad & PAD_RIGHT) { dx = 2;  facing = 0; }
        if (pad & PAD_LEFT)  { dx = -2; facing = 1; }
    }
    nx = (int)player_x + dx;
    if (nx < WALL) nx = WALL;
    if (nx > 256 - WALL - 16) nx = 256 - WALL - 16;
    player_x = nx;

    if (PRESSED(PAD_A) && on_ground) { vy = -6; gtick = 0; }
    else if (!(pad & PAD_A) && vy < -2) vy = -2;        /* variable jump height */
    if (++gtick == 3) {
        gtick = 0;
        if (vy < 7) ++vy;
    }
    ny = player_y + vy;
    on_ground = 0;
    if (vy >= 0) {                       /* falling: land on the floor or on top of a platform */
        land = 0;
        for (i = 0; i < 3; ++i)
            if (player_y + 16 <= plat_y[i] && ny + 16 >= plat_y[i] &&
                player_x + 3 < plat_x[i] + 48 && player_x + 13 > plat_x[i]) land = plat_y[i];
        if (!land && ny + 16 >= FLOOR_Y) land = FLOOR_Y;
        if (land) { ny = land - 16; vy = 0; on_ground = 1; }
    }
    player_y = ny;

    if (PRESSED(PAD_B) && !sword_cd) { sword_t = SWORD_LEN; sword_cd = SWORD_CD; }
}

static void update_enemy(void)
{
    if (en.flash) --en.flash;
    if (!en.hp) return;
    en.x += en.dir;
    if (en.x <= WALL || en.x >= 256 - WALL - en.w) en.dir = -en.dir;
}

static void combat(void)
{
    if (en.hp && sword_t && !en.flash &&
        overlap(facing ? player_x - 12 : player_x + 12, player_y + 6, 16, 8, en.x, en.y, en.w, en.h)) {
        --en.hp;
        en.flash = ENEMY_HIT;
    }
    if (en.hp && !invuln && overlap(player_x + 3, player_y + 2, 10, 14, en.x, en.y, en.w, en.h)) {
        if (--hearts == 0) { arena_reset(); return; }
        invuln = INVULN;
        kb_t = KNOCK;
        kb_dir = (player_x + 8 < en.x + en.w / 2) ? -3 : 3;
        vy = -3;
        gtick = 0;
    }
}

static void draw(void)
{
    unsigned char x = player_x, y = player_y, f = facing, i;
    unsigned char py = (invuln & 4) ? 0xFF : y - 1;       /* blink while invulnerable */
    unsigned char ey = (en.hp && !(en.flash & 2)) ? en.y - 1 : 0xFF;

    oam[0] = oam[4] = py;
    oam[8] = oam[12] = py == 0xFF ? 0xFF : y + 7;
    oam[2] = oam[6] = oam[10] = oam[14] = f << 6;         /* bit 6 = horizontal flip */
    oam[3] = oam[11] = x + (f ? 8 : 0);
    oam[7] = oam[15] = x + (f ? 0 : 8);

    oam[O_SWORD] = oam[O_SWORD + 4] = sword_t ? y + 5 : 0xFF;
    oam[O_SWORD + 2] = oam[O_SWORD + 6] = 2 | (f << 6);
    oam[O_SWORD + 3] = x + (f ? -4 : 12);
    oam[O_SWORD + 7] = x + (f ? -12 : 20);

    oam[O_ENEMY] = oam[O_ENEMY + 4] = ey;
    oam[O_ENEMY + 8] = oam[O_ENEMY + 12] = ey == 0xFF ? 0xFF : en.y + 7;
    oam[O_ENEMY + 3] = oam[O_ENEMY + 11] = en.x;
    oam[O_ENEMY + 7] = oam[O_ENEMY + 15] = en.x + 8;

    for (i = 0; i < 3; ++i) oam[O_HEART + i * 4 + 1] = i < hearts ? 14 : 15;
}

unsigned char dungeon_frame(void)
{
    if (PRESSED(PAD_SELECT)) return 1;  /* temporary way out until the victory screen (v0.3 package 3) */
    if (PRESSED(PAD_START)) paused ^= 1;
    if (!paused) {
        update_player();
        update_enemy();
        combat();
    }
    draw();
    return 0;
}
