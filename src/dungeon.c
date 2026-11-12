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
#define NBOSS      1                   /* dungeons 1..NBOSS have a boss, the rest a test dummy */
#define INTRO_LEN  75                  /* boss name on screen, everything frozen (1.25 s) */
#define PHASE_FX   30                  /* phase change: boss frozen and harmless, backdrop flashes */
#define FB_MAX     3

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

/* Boss table (docs/TECH.md "Boss-Rahmen"). Phase 1 = 100..71 %, 2 = 70..51 %, 3 = 50..0 % of max hp. */
struct phase {
    unsigned char tile;                /* first of 4 sprite tiles (TL, TR, BL, BR) */
    unsigned char spd, wait;           /* hop speed px/frame, frames standing between hops */
    unsigned char rate, shots, fspd;   /* frames between spits, fireballs per spit, fireball px/frame */
    unsigned char pal[3];              /* sprite palette 1 */
};
struct boss {
    const char *name;                  /* letters must exist in font[] */
    unsigned char hp;
    void (*ai)(void);
    struct phase ph[3];
};
static void imp_ai(void);
static const struct boss bosses[NBOSS] = {
    { "IMP", 20, imp_ai, {
        { 16, 1, 40, 100, 1, 1, { 0x2A, 0x1A, 0x30 } },
        { 20, 2, 24,  60, 1, 2, { 0x27, 0x17, 0x30 } },
        { 24, 3, 14,  75, 3, 2, { 0x16, 0x06, 0x28 } } } }
};
static const struct boss *bs;          /* 0 = test dummy */
static const char font[] = "             IMP0123456789DUNGEO";     /* index = BG tile */
static const unsigned char white = 0x30;
static unsigned char ph_t2, ph_t3;     /* phase 2 / 3 start at hp <= these */
static unsigned char pal_ph, pal_bg;   /* what the PPU currently shows */
static signed char   ivx, ivy, fb_vx[3], fb_vy[3];
static unsigned char ig, iair, ai_t, fb_t, rng;

static unsigned char facing;           /* 0 right, 1 left */
static unsigned char sword_cd, gtick;
static signed char   kb_dir;           /* knockback px/frame, signed */
static unsigned char kb_t;

/* OAM layout (byte offsets): player 0, sword 16, enemy 24, hearts 40. */
#define O_SWORD  16
#define O_ENEMY  24
#define O_HEART  40
#define O_FB     52

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
static void clear_fb(void)
{
    unsigned char i;
    for (i = 0; i < FB_MAX; ++i) fb_x[i] = 0;
}

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
    boss_phase = bs ? 1 : 0;
    boss_dead = boss_fx = ivx = ivy = ig = iair = 0;
    clear_fb();
    if (bs) {
        en.hp = bs->hp;
        ph_t2 = (unsigned)en.hp * 70 / 100;
        ph_t3 = en.hp / 2;
        ai_t = 40; fb_t = 70;
    }
}

/* PPU palette write; only in vblank (start of the frame). Leaves the scroll at 0/0 (the arena never scrolls). */
static void setpal(unsigned char a, const unsigned char *c, unsigned char n)
{
    PPU_ADDR = 0x3F; PPU_ADDR = a;
    while (n--) PPU_DATA = *c++;
    PPU_ADDR = 0; PPU_ADDR = 0;
}

static void pal_sync(void)
{
    unsigned char w = (boss_fx & 4) != 0;       /* flash: 4 frames white, 4 normal */
    if (pal_ph != boss_phase) { pal_ph = boss_phase; setpal(0x15, bs->ph[pal_ph - 1].pal, 3); }
    if (w != pal_bg) { pal_bg = w; setpal(0, w ? &white : &dpal[cur_dungeon - 1][0], 1); }
}

/* Boss name centered on nametable row 10 (on) or erased again (off). shortcut: a missing letter shows 'O'. */
static void text(unsigned char on)
{
    const char *n = bs->name;
    unsigned char l = 0, t;
    while (n[l]) ++l;
    PPU_ADDR = 0x21; PPU_ADDR = 0x40 + ((32 - l) >> 1);
    for (; *n; ++n) {
        t = 0;
        if (on) for (t = 0; t < 31 && font[t] != *n; ++t) ;     /* erasing must stay cheap: vblank is short */
        PPU_DATA = t;
    }
    PPU_ADDR = 0; PPU_ADDR = 0;
}

void dungeon_enter(void)
{
    unsigned char i, j, r, c;
    const unsigned char *p = dpal[cur_dungeon - 1];

    bs = cur_dungeon <= NBOSS ? &bosses[cur_dungeon - 1] : 0;
    pal_ph = pal_bg = 0;
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

    for (i = 0; i < 4; ++i) {           /* sprite tiles/palettes: player 4..7, sword 12/13, enemy tiles set in draw(), hearts */
        oam[i * 4 + 1] = 4 + i;
        oam[O_ENEMY + i * 4 + 2] = 1;
    }
    for (i = 0; i < FB_MAX; ++i) {
        oam[O_FB + i * 4 + 1] = 28;
        oam[O_FB + i * 4 + 2] = 2;
    }
    for (i = 0; i < 2; ++i) oam[O_SWORD + i * 4 + 1] = 12 + i;
    for (i = 0; i < 3; ++i) {
        oam[O_HEART + i * 4]     = 15;
        oam[O_HEART + i * 4 + 2] = 2;
        oam[O_HEART + i * 4 + 3] = 24 + i * 10;
    }
    arena_reset();
    intro = 0;
    if (bs) { intro = INTRO_LEN; text(1); }
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

static void hurt(unsigned char sx)     /* player hit by something at x = sx */
{
    if (--hearts == 0) { arena_reset(); return; }
    invuln = INVULN;
    kb_t = KNOCK;
    kb_dir = (player_x + 8 < sx) ? -3 : 3;
    vy = -3;
    gtick = 0;
}

/* Imp: hops (floor only) toward the player (1 in 4 away), spits fireballs at him. */
static void imp_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    signed char d, v;
    unsigned char k, s;
    int nx;

    rng = rng * 5 + 17 + (unsigned char)frame_count;
    if (fb_t) --fb_t;
    else {
        fb_t = p->rate;
        d = player_x > en.x ? 1 : -1;
        v = d > 0 ? (signed char)p->fspd : -(signed char)p->fspd;
        for (s = 0; s < p->shots; ++s)
            for (k = 0; k < FB_MAX; ++k)
                if (!fb_x[k]) {
                    fb_x[k] = en.x + 4;
                    fb_y[k] = en.y + 4;
                    fb_vx[k] = v;
                    fb_vy[k] = p->shots > 1 ? (signed char)s - 1 : (player_y + 8 < en.y ? -1 : 0);
                    break;
                }
    }
    if (!iair) {
        if (ai_t) { --ai_t; return; }
        d = player_x > en.x ? 1 : -1;
        if (!(rng & 0xC0)) d = -d;
        ivx = d > 0 ? (signed char)p->spd : -(signed char)p->spd;
        ivy = -4; ig = 0; iair = 1; ai_t = p->wait;
    }
    nx = en.x + ivx;
    if (nx < WALL) nx = WALL;
    if (nx > 256 - WALL - 16) nx = 256 - WALL - 16;
    en.x = nx;
    en.y += ivy;
    if (++ig == 3) { ig = 0; ++ivy; }
    if (ivy >= 0 && en.y + 16 >= FLOOR_Y) { en.y = FLOOR_Y - 16; ivx = ivy = iair = 0; }
}

static void fireballs(void)
{
    unsigned char k;
    for (k = 0; k < FB_MAX; ++k) {
        if (!fb_x[k]) continue;
        fb_x[k] += fb_vx[k];
        if (frame_count & 1) fb_y[k] += fb_vy[k];       /* vertical at half speed: shallow spread */
        if (fb_x[k] <= WALL || fb_x[k] >= 256 - WALL - 8 || fb_y[k] < 8 || fb_y[k] + 8 >= FLOOR_Y)
            fb_x[k] = 0;
        else if (!invuln && overlap(player_x + 3, player_y + 2, 10, 14, fb_x[k], fb_y[k], 8, 8)) {
            hurt(fb_x[k] + 4);
            fb_x[k] = 0;
        }
    }
}

static void update_enemy(void)
{
    if (en.flash) --en.flash;
    if (!en.hp) return;
    if (bs) {
        if (boss_fx) --boss_fx;
        else { bs->ai(); fireballs(); }
        return;
    }
    en.x += en.dir;
    if (en.x <= WALL || en.x >= 256 - WALL - en.w) en.dir = -en.dir;
}

static void combat(void)
{
    unsigned char ph;
    if (en.hp && sword_t && !en.flash && !boss_fx &&
        overlap(facing ? player_x - 12 : player_x + 12, player_y + 6, 16, 8, en.x, en.y, en.w, en.h)) {
        --en.hp;
        en.flash = ENEMY_HIT;
        if (bs) {
            ph = en.hp <= ph_t3 ? 3 : en.hp <= ph_t2 ? 2 : 1;
            if (!en.hp) { boss_dead = 1; clear_fb(); }
            else if (ph != boss_phase) { boss_phase = ph; boss_fx = PHASE_FX; clear_fb(); }
        }
    }
    if (en.hp && !boss_fx && !invuln && overlap(player_x + 3, player_y + 2, 10, 14, en.x, en.y, en.w, en.h))
        hurt(en.x + en.w / 2);
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

    for (i = 0; i < 4; ++i) oam[O_ENEMY + i * 4 + 1] = (bs ? bs->ph[boss_phase - 1].tile : 8) + i;
    for (i = 0; i < FB_MAX; ++i) {
        oam[O_FB + i * 4] = fb_x[i] ? fb_y[i] - 1 : 0xFF;
        oam[O_FB + i * 4 + 3] = fb_x[i];
    }
    for (i = 0; i < 3; ++i) oam[O_HEART + i * 4 + 1] = i < hearts ? 14 : 15;
}

unsigned char dungeon_frame(void)
{
    if (PRESSED(PAD_SELECT)) return 1;  /* temporary way out until the victory screen (v0.3 package 3) */
    if (PRESSED(PAD_START)) paused ^= 1;
    if (bs) pal_sync();                 /* PPU writes first: still in vblank */
    if (intro) {
        if (!--intro) text(0);
    } else if (!paused) {
        update_player();
        update_enemy();
        combat();
    }
    draw();
    return 0;
}
