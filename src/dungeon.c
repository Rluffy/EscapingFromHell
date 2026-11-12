/* Dungeon arena: one screen, side view. Docs: docs/TECH.md "Dungeon (v0.3)". */
#include "nes.h"
#include "boss.h"

#define ST_DUNGEON 3
#define HEARTS_MAX 3
#define INVULN     120
#define KNOCK      8                   /* knockback frames, 3 px/frame */
#define SWORD_LEN  8
#define SWORD_CD   14
#define ENEMY_HP   5
#define ENEMY_HIT  12                  /* enemy invulnerable after a sword hit (blinks) */
#define NBOSS      6                   /* dungeons 1..NBOSS have a boss, the rest a test dummy */
#define INTRO_LEN  75                  /* boss name on screen, everything frozen (1.25 s) */
#define PHASE_FX   30                  /* phase change: boss frozen and harmless, backdrop flashes */
#define DASH_LEN   10                  /* dash: 4 px/frame for 10 frames, invulnerable */
#define DASH_CD    30                  /* frames from dash start until the next one */
#define VICTORY_LEN 120                /* victory screen, 2 s */
#define BAR_ADDR   0x2054              /* boss hp bar: row 2, columns 20..29 (10 tiles = 20 half steps) */
#define BAR_N      10
#define FIRE_CD    40                  /* player fireball cooldown (Up + B) */
#define FIRE_VX    3                   /* player fireball px/frame */
#define BOSS_KNOCK 16                  /* px the boss is pushed away from the player by a sword hit */

/* One-way platforms, 48 px wide (6 tiles); x and y are multiples of 8. */
static const unsigned char plat_x[3] = { 32, 176, 104 };
static const unsigned char plat_y[3] = { 152, 152, 112 };

/* Per-dungeon BG palette 0 (backdrop, floor, mortar, edge); sprite palettes are shared. */
static const unsigned char dpal[10][4] = {
    {0x02,0x11,0x01,0x21}, {0x0F,0x16,0x06,0x26}, {0x01,0x14,0x04,0x24}, {0x06,0x16,0x07,0x27},
    {0x08,0x18,0x07,0x28}, {0x03,0x13,0x02,0x23}, {0x0C,0x1C,0x0B,0x2C}, {0x09,0x19,0x0A,0x29},
    {0x05,0x15,0x04,0x25}, {0x0F,0x00,0x2D,0x10}
};
/* Sprite palettes 0..3 without the backdrop: player, enemy, heart + sword, player fireball. */
static const unsigned char spal[12] = { 0x17,0x21,0x36, 0x06,0x16,0x30, 0x16,0x30,0x10, 0x21,0x31,0x30 };

/* Boss table (docs/TECH.md "Boss-Rahmen"). Phase 1 = 100..71 %, 2 = 70..51 %, 3 = 50..0 % of max hp.
   Behavior function and phase data live in the boss's PRG bank (src/boss.h); the table itself stays fixed. */
static const struct boss bosses[NBOSS] = {
    { "IMP", 10, 0, 16, 16, FLOOR_Y - 16, imp_ai, imp_ph },
    { "GHOST", 12, 1, 16, 24, 104, ghost_ai, ghost_ph },
    { "BONE HOUND", 14, 2, 24, 16, FLOOR_Y - 16, hound_ai, hound_ph },
    { "LAVA SNAKE", 14, 3, 16, 16, FLOOR_Y - 16, snake_ai, snake_ph },
    { "WINGED DEMON", 14, 4, 16, 24, 56, winged_ai, winged_ph },
    { "MIRROR DEMON", 14, 5, 16, 24, FLOOR_Y - 24, mirror_ai, mirror_ph }
};
const struct boss *bs;                 /* 0 = test dummy */
/* Ability bit a demon grants (index = dungeon - 1; GAMEDESIGN table) and the text shown the first time. */
static const unsigned char grant[10] = { 1, 0, 2, 0, 4, 0, 8, 0, 16, 0 };
static const char *const gotname[10] = { "GOT DASH", 0, "GOT DOUBLE JUMP", 0, "GOT FIREBALL" };   /* Dash, Double jump, Fireball act so far */
/* BG tile of the letter A..Z (0 = not in the font sheet). */
static const unsigned char ftile[26] = {
    37, 43, 33, 26, 30, 48, 29, 39, 13, 45, 46, 44, 14, 28, 31, 15, 0, 35, 38, 34, 27, 32, 47, 0, 36, 0
};
static const unsigned char white = 0x30;
static unsigned char hp_max, bar_hp;   /* max hp of the enemy; hp the bar shows (255 = redraw) */
static unsigned char ph_t2, ph_t3;     /* phase 2 / 3 start at hp <= these */
static unsigned char pal_ph, pal_bg;   /* what the PPU currently shows */
signed char   ivx, ivy, fb_vx[3], fb_vy[3];     /* boss state shared with the banked AI (boss.h) */
unsigned char ig, ai_t, rng;                      /* iair lives in debug.s ($0328) */
unsigned      fb_t;

unsigned char facing;                  /* 0 right, 1 left (boss.h) */
static unsigned char air_jumped;       /* double jump used in this airtime */
static unsigned char sword_cd, gtick;
static signed char   pf_vx;           /* player fireball px/frame, signed */
static signed char   kb_dir;           /* knockback px/frame, signed */
static unsigned char kb_t;

/* OAM layout (byte offsets): player 0, sword 16, enemy 24, hearts 40, fireballs 52, enemy row 3 at 64. */
#define O_SWORD  16
#define O_ENEMY  24
#define O_HEART  40
#define O_FB     52
#define O_ENEMY2 64                    /* third sprite row of a 24 px boss */
#define O_BODY   72                    /* body segments of a long boss (snake.c, 8 x 2 sprites, up to byte 135) */
#define O_PF     136                   /* player fireball */

static unsigned char arena_tile(unsigned char r, unsigned char c)
{
    unsigned char i, c0;
    if (r == 24 && cur_dungeon == 4 && (c < 6 || c >= 26)) return 3;    /* dungeon 4: lava pools at both walls (decoration) */
    if (r >= 24) return r == 24 ? 11 : 10;
    if (c < 2 || c >= 30) return 10;
    if (r != 14 && r != 19) return 0;      /* platform rows only: keeps the redraw short */
    for (i = 0; i < 3; ++i) {
        c0 = plat_x[i] >> 3;
        if (r == (plat_y[i] >> 3) && c >= c0 && c < c0 + 6) return 12;
    }
    return 0;
}

unsigned char overlap(unsigned char ax, unsigned char ay, unsigned char aw, unsigned char ah,
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
    invuln = sword_t = sword_cd = kb_t = gtick = paused = air_jumped = pf_x = pf_cd = 0;
    vy = 0;
    on_ground = 1;
    facing = 0;
    player_x = 48;
    player_y = FLOOR_Y - 16;
    en.x = 160; en.y = FLOOR_Y - 16; en.w = 16; en.h = 16;
    en.hp = hp_max = ENEMY_HP; en.flash = 0; en.dir = -1;
    boss_phase = bs ? 1 : 0;
    boss_dead = boss_fx = boss_hide = ivx = ivy = ig = iair = dash_t = dash_cd = victory = 0;
    clear_fb();
    if (bs) {
        en.hp = hp_max = bs->hp;
        en.w = bs->w; en.h = bs->h; en.y = bs->y0;
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

/* Text (A-Z and spaces, max 16 letters) centered on the nametable row at row_addr, or erased again (on = 0).
   The tiles are prepared into tb[] during the frame and written by text_flush() at the start of the next
   one, while vblank is still on: the vblank is too short to do the letter lookup there.
   shortcut: a letter missing from ftile[] shows blank. */
static unsigned char tb[18], tb_n;     /* PPU addr hi, lo, tiles; tb_n = end index, 0 = nothing pending */

static void text_prep(const char *n, unsigned int row_addr, unsigned char on)
{
    unsigned char l = 0;
    while (n[l]) ++l;
    row_addr += (32 - l) >> 1;
    tb[0] = row_addr >> 8; tb[1] = row_addr;
    for (tb_n = 2; *n; ++n) tb[tb_n++] = on && *n > ' ' ? ftile[*n - 'A'] : 0;
}

static void text_flush(void)
{
    unsigned char i;
    if (!tb_n) return;
    PPU_ADDR = tb[0]; PPU_ADDR = tb[1];
    for (i = 2; i < tb_n; ++i) PPU_DATA = tb[i];
    PPU_ADDR = 0; PPU_ADDR = 0;
    tb_n = 0;
}

/* Boss hp bar: tiles 40 full, 41 half, 42 empty; ceil(hp * 20 / max) half steps, so any hp > 0 shows something. */
static void bar_sync(void)
{
    unsigned char i, s;
    /* unchanged, buffer busy, or a palette write is due next frame (both in one vblank do not fit): retry next frame */
    if (bar_hp == en.hp || tb_n || (pal_ph && pal_ph != boss_phase)) return;
    bar_hp = en.hp;
    s = ((unsigned)en.hp * 20 + hp_max - 1) / hp_max;
    if (s > 20) s = 20;
    tb[0] = BAR_ADDR >> 8; tb[1] = BAR_ADDR & 0xFF;
    for (i = 0; i < BAR_N; ++i) tb[2 + i] = s >= 2 * i + 2 ? 40 : s > 2 * i ? 41 : 42;
    tb_n = 2 + BAR_N;
}

void dungeon_enter(void)
{
    unsigned char i, j, r, c;
    const unsigned char *p = dpal[cur_dungeon - 1];

    bs = cur_dungeon <= NBOSS ? &bosses[cur_dungeon - 1] : 0;
    if (bs) bank_set(bs->bank);         /* stays mapped for the whole fight */
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
    oam[O_ENEMY2 + 2] = oam[O_ENEMY2 + 6] = 1;
    for (i = 0; i < FB_MAX; ++i) {
        oam[O_FB + i * 4 + 1] = 28;
        oam[O_FB + i * 4 + 2] = 2;
    }
    for (i = 0; i < 2; ++i) oam[O_SWORD + i * 4 + 1] = 12 + i;
    oam[O_PF + 1] = 29;
    for (i = 0; i < 3; ++i) {
        oam[O_HEART + i * 4]     = 15;
        oam[O_HEART + i * 4 + 2] = 2;
        oam[O_HEART + i * 4 + 3] = 24 + i * 10;
    }
    arena_reset();
    intro = 0;
    tb_n = 0; bar_hp = 255;
    bar_sync(); text_flush();
    if (bs) { intro = INTRO_LEN; text_prep(bs->name, 0x2140, 1); text_flush(); }
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
    if (dash_cd) --dash_cd;
    if (pf_cd) --pf_cd;

    if (PRESSED(PAD_SELECT) && (abilities & AB_DASH) && !dash_cd && !kb_t) {
        dash_t = DASH_LEN; dash_cd = DASH_CD;
        if (invuln < DASH_LEN) invuln = DASH_LEN;       /* invulnerable (and blinking) while dashing */
    }
    if (dash_t) {                       /* gravity keeps working: in the air the dash is a flat arc */
        --dash_t;
        dx = facing ? -4 : 4;
    } else if (kb_t) {
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

    if (PRESSED(PAD_A) && (on_ground || ((abilities & AB_DJUMP) && !air_jumped))) {
        air_jumped |= !on_ground;       /* double jump: once per airtime (also after a ledge or a knockback), a bit lower */
        vy = on_ground ? -6 : -5; gtick = 0;
    }
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
        if (land) { ny = land - 16; vy = 0; on_ground = 1; air_jumped = 0; }
    }
    player_y = ny;

    if (PRESSED(PAD_B)) {
        if ((pad & PAD_UP) && (abilities & AB_FIRE)) {      /* Up + B with the ability: fireball instead of a sword swing */
            if (!pf_x && !pf_cd) {
                pf_x = facing ? player_x - 4 : player_x + 12;
                pf_y = player_y + 4;
                pf_vx = facing ? -FIRE_VX : FIRE_VX;
                pf_cd = FIRE_CD;
            }
        } else if (!sword_cd) { sword_t = SWORD_LEN; sword_cd = SWORD_CD; }
    }
}

static void pfire(void)
{
    if (!pf_x) return;
    pf_x += pf_vx;
    if (pf_x <= WALL || pf_x >= 256 - WALL - 8) pf_x = 0;     /* gone at the wall */
}

void hurt(unsigned char sx)     /* player hit by something at x = sx */
{
    if (--hearts == 0) { arena_reset(); return; }
    invuln = INVULN;
    kb_t = KNOCK;
    kb_dir = (player_x + 8 < sx) ? -3 : 3;
    vy = -3;
    gtick = 0;
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
    unsigned char ph, ok = en.hp && !(boss_hide & 1) && !en.flash && !boss_fx, hit = 0;
    int nx;
    if (ok && pf_x && overlap(pf_x, pf_y, 8, 8, en.x, en.y, en.w, en.h)) { pf_x = 0; hit = 1; }
    else if (ok && sword_t && overlap(facing ? player_x - 16 : player_x + 12, player_y + 6, 20, 8, en.x, en.y, en.w, en.h)) hit = 1;
    if (hit) {
        --en.hp;
        en.flash = ENEMY_HIT;
        if (bs) {
            nx = (int)en.x + (en.x >= player_x ? BOSS_KNOCK : -BOSS_KNOCK);
            en.x = nx < WALL ? WALL : nx > 256 - WALL - en.w ? 256 - WALL - en.w : nx;
            ph = en.hp <= ph_t3 ? 3 : en.hp <= ph_t2 ? 2 : 1;
            if (!en.hp) { boss_dead = 1; clear_fb(); }
            else if (ph != boss_phase) { boss_phase = ph; boss_fx = PHASE_FX; clear_fb(); }
        }
    }
    if (en.hp && !(boss_hide & 1) && !boss_fx && !en.flash && !invuln && overlap(player_x + 3, player_y + 2, 10, 14, en.x, en.y, en.w, en.h))
        hurt(en.x + en.w / 2);
}

static void draw(void)
{
    unsigned char x = player_x, y = player_y, f = facing, i;
    unsigned char py = (invuln & 4) ? 0xFF : y - 1;       /* blink while invulnerable */
    unsigned char ey = (en.hp && !(en.flash & 2) && !(boss_hide & 2)) ? en.y - 1 : 0xFF;
    unsigned char t = bs ? bs->ph[boss_phase - 1].tile : 8;

    bar_sync();

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

    for (i = 0; i < 4; ++i) oam[O_ENEMY + i * 4 + 1] = t + i;
    oam[O_ENEMY2] = oam[O_ENEMY2 + 4] = 0xFF;       /* 24 px high: third row; 24 px wide: third column (tiles t+4, t+5) */
    oam[O_ENEMY2 + 1] = t + 4; oam[O_ENEMY2 + 5] = t + 5;
    if (ey != 0xFF) {
        if (en.h > 16) {
            oam[O_ENEMY2] = oam[O_ENEMY2 + 4] = en.y + 15;
            oam[O_ENEMY2 + 3] = en.x; oam[O_ENEMY2 + 7] = en.x + 8;
        } else if (en.w > 16) {
            oam[O_ENEMY2] = ey; oam[O_ENEMY2 + 4] = en.y + 7;
            oam[O_ENEMY2 + 3] = oam[O_ENEMY2 + 7] = en.x + 16;
        }
    }
    for (i = 0; i < FB_MAX; ++i) {
        oam[O_FB + i * 4] = fb_x[i] ? fb_y[i] - 1 : 0xFF;
        oam[O_FB + i * 4 + 3] = fb_x[i];
    }
    oam[O_PF] = pf_x && en.hp ? pf_y - 1 : 0xFF;
    oam[O_PF + 2] = 3 | (pf_vx < 0 ? 0x40 : 0);
    oam[O_PF + 3] = pf_x;
    for (i = 0; i < 3; ++i) oam[O_HEART + i * 4 + 1] = i < hearts ? 14 : 15;
    if (!en.hp) for (i = O_BODY; i < 212; i += 4) oam[i] = 0xFF;      /* dead: hide a boss's body segments / copies (up to O_COPY + 72) */
}

/* Demon (or dummy) beaten and the victory screen is over: clear the dungeon, grant the ability, autosave. */
static void win(void)
{
    dungeons_cleared |= 1u << (cur_dungeon - 1);
    abilities |= grant[cur_dungeon - 1];
    save_game();
}

unsigned char dungeon_frame(void)
{
    text_flush();                       /* PPU writes first: still in vblank */
    if (victory) {                      /* input ignored */
        if (victory == VICTORY_LEN - 1 && (grant[cur_dungeon - 1] & ~abilities) && gotname[cur_dungeon - 1])
            text_prep(gotname[cur_dungeon - 1], 0x21A0, 1);
        if (!--victory) { win(); return 1; }
        draw();
        return 0;
    }
    if (paused && PRESSED(PAD_SELECT)) return 1;    /* Start, then Select: give up the fight */
    if (PRESSED(PAD_START)) paused ^= 1;
    if (bs) pal_sync();                 /* PPU writes first: still in vblank */
    if (intro) {
        if (!--intro) text_prep(bs->name, 0x2140, 0);
    } else if (!paused) {
        update_player();
        pfire();
        update_enemy();
        combat();
        if (!en.hp) { victory = VICTORY_LEN; text_prep("VICTORY", 0x2140, 1); }
    }
    draw();
    return 0;
}
