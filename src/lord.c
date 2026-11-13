/* Demon 10, Hell lord (final boss): code and phase data live in PRG bank 9 ($8000). Docs: docs/GAMEDESIGN.md, docs/TECH.md "Höllenfürst". */
#pragma code-name("BANK9")
#pragma rodata-name("BANK9")
#include "nes.h"
#include "boss.h"

/* tile = first of 6 tiles of the LEFT half (row 0: 2, row 1: 2, row 2: 1, row 3: 1; the right half is the mirror image);
   spd = dive px/frame; wait = idle frames (hit window) after every action; rate = frames invisible (0 = never);
   shots = 1: shockwaves on landing; fspd = fireball and shockwave px/frame. */
const struct phase lord_ph[3] = {
    { BT + 0, 0, 100,  0, 0, 2, { 0x06, 0x16, 0x28 } },
    { BT + 6, 5, 100,  0, 0, 2, { 0x05, 0x15, 0x38 } },
    { BT + 12, 6,  80, 90, 1, 3, { 0x0F, 0x06, 0x30 } }
};
/* Action cycle per phase: F aimed fireball, P 3-way spread, T teleport, S flying swoop, I invisible teleport (fires while unseen). */
static const char seq[3][6] = { "FTT", "SPTT", "ISTPT" };

/* iair = state, ai_t = state timer. */
enum { INIT, IDLE, FTELE, FADE, GONE, APPEAR, RISE, HOVER, STELE, DIVE, REST };
#define GROUND   (FLOOR_Y - 32)
#define MAXX     (256 - WALL - 32)
#define HOVER_Y  56                    /* flying: upper half, out of reach from the floor */
#define FTELE_T  22                    /* fireball warning: flickers (still hittable) */
#define FADE_T   20                    /* teleport out: flickers, untouchable */
#define APPEAR_T 30                    /* telegraph at the new spot: flickers, untouchable, harmless */
#define HOVER_T  45
#define STELE_T  28                    /* swoop warning: hovers over the player, then locks on */
#define REST_T   40                    /* after a swoop: the main hit window */
#define MIN_GAP  56                    /* a teleport never lands closer than this to the player */
#define O_LORD   72                    /* OAM byte offset: 12 body sprites (up to byte 119) */
#define O_FB     52                    /* the boss fireball sprites (dungeon.c) */
#define FIREBALL 28

static unsigned char ph, par, act, tx; /* phase seen, index in the cycle, current action, swoop target x (stale values are harmless: INIT sets them) */

static unsigned char toward(unsigned char a, unsigned char b, unsigned char m)
{
    if (a + m < b) return a + m;
    if (a > b + m) return a - m;
    return b;
}

static unsigned char aim(void)         /* x that centers the lord over the player */
{
    int t = (int)player_x - 8;
    return t < WALL ? WALL : t > MAXX ? MAXX : t;
}

static void place(void)                /* teleport target on the floor, away from the player */
{
    int d, t = WALL + ((rng >> 1) * 3 >> 1);
    d = t + 16 - (int)player_x - 8;
    if (d < 0) d = -d;
    if (d < MIN_GAP) t = player_x < 112 ? MAXX - 16 : WALL + 16;
    en.x = t; en.y = GROUND;
}

static unsigned char slot(unsigned char tile)   /* a free fireball slot with its sprite set to tile, 255 = none */
{
    unsigned char k;
    for (k = 0; k < FB_MAX; ++k)
        if (!fb_x[k]) { oam[O_FB + k * 4 + 1] = tile; oam[O_FB + k * 4 + 2] = tile == SHOCK ? 1 : 2; return k; }
    return 255;
}

static void fire(const struct phase *p, unsigned char n)   /* n = 1: aimed at the player; 3: a spread (-1 / 0 / +1) */
{
    unsigned char s, k;
    int dx = (int)player_x + 8 - (en.x + 16), a = dx < 0 ? -dx : dx, dy, v;
    signed char vx = dx < 0 ? -(signed char)p->fspd : (signed char)p->fspd;
    for (s = 0; s < n; ++s) {
        k = slot(FIREBALL);
        if (k == 255) return;
        fb_x[k] = dx < 0 ? en.x : en.x + 22;
        fb_y[k] = en.y + (n > 1 ? 4 + s * 8 : 16);
        fb_vx[k] = vx;
        if (n > 1) fb_vy[k] = (signed char)s - 1;
        else {                          /* vertical runs at half rate: v = 2 * dy * speed / dx */
            if (a < 8) a = 8;
            dy = (int)player_y + 8 - fb_y[k] - 4;
            v = (2 * dy * (int)p->fspd) / a;
            fb_vy[k] = v > 3 ? 3 : v < -3 ? -3 : v;
        }
    }
}

static void quake(const struct phase *p)   /* shockwaves along the floor to both sides of the landing lord (jumpable, the shield stops them) */
{
    unsigned char k;
    k = slot(SHOCK);
    if (k != 255) { fb_x[k] = en.x + 32; fb_y[k] = FLOOR_Y - 9; fb_vx[k] = p->fspd; fb_vy[k] = 0; }
    k = slot(SHOCK);
    if (k != 255) { fb_x[k] = en.x - 8; fb_y[k] = FLOOR_Y - 9; fb_vx[k] = -(signed char)p->fspd; fb_vy[k] = 0; }
}

/* 12 body sprites: rows of 4, 4, 2, 2 (wide shoulders and wings above, a narrow body below, so the fireball and shockwave
   rows stay light); the left half's tiles, then the same tile mirrored for the right half. */
static void sprites(void)
{
    unsigned char *o = oam + O_LORD;
    unsigned char r, c, n, off, t = bs->ph[boss_phase - 1].tile;
    unsigned char hide = (boss_hide & 2) || (en.flash & 2) || !en.hp;
    for (r = 0; r < 4; ++r) {
        n = r < 2 ? 2 : 1;
        for (c = 0; c < n; ++c) {
            off = (r < 2 ? 0 : 8) + c * 8;
            *o++ = hide ? 0xFF : en.y + r * 8 - 1; *o++ = t; *o++ = 1; *o++ = en.x + off;
            *o++ = hide ? 0xFF : en.y + r * 8 - 1; *o++ = t++; *o++ = 0x41; *o++ = en.x + 24 - off;
        }
    }
}

void lord_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    unsigned char f = (ftick & 4) ? 2 : 0, c, k;

    if (intro || boss_fx) { sprites(); return; }       /* frozen: only redraw (new look at a phase change) */
    rng = rng * 5 + 17;
    boss_hide = 0;
    if (iair == INIT) { ph = boss_phase; par = 0; iair = IDLE; ai_t = p->wait; }
    else if (ph != boss_phase) { ph = boss_phase; par = 0; act = 'T'; iair = FADE; ai_t = FADE_T; }   /* new phase: teleport to the floor */
    switch (iair) {
    case IDLE:                         /* solid on the floor: the hit window; then the next action of the cycle */
        if (--ai_t) break;
        c = seq[boss_phase - 1][par];
        if (!c) { par = 0; c = seq[boss_phase - 1][0]; }
        ++par; act = c;
        if (c == 'F' || c == 'P') { iair = FTELE; ai_t = FTELE_T; }
        else if (c == 'S') iair = RISE;
        else { iair = FADE; ai_t = FADE_T; }
        break;
    case FTELE:                        /* warning flicker, then the shot */
        boss_hide = f;
        if (--ai_t) break;
        fire(p, act == 'P' ? 3 : 1);
        iair = IDLE; ai_t = p->wait; boss_hide = 0;      /* the solid window starts with this frame (no leftover flicker) */
        break;
    case FADE:                         /* fading out where it stands */
        boss_hide = 1 | f;
        if (--ai_t) break;
        place();
        if (act == 'I' && p->rate) { iair = GONE; ai_t = p->rate; }
        else { iair = APPEAR; ai_t = APPEAR_T; }
        break;
    case GONE:                         /* invisible and untouchable, but the fireballs show */
        boss_hide = 3;
        if (ai_t == 60 || ai_t == 30) fire(p, 1);
        if (--ai_t) break;
        iair = APPEAR; ai_t = APPEAR_T;
        break;
    case APPEAR:                       /* telegraph at the new spot */
        boss_hide = 1 | f;
        if (--ai_t) break;
        iair = IDLE; ai_t = p->wait; boss_hide = 0;
        break;
    case RISE:                         /* up to the hover height, drifting toward the player */
        en.x = toward(en.x, aim(), 2);
        en.y = toward(en.y, HOVER_Y, 3);
        if (en.y == HOVER_Y) { iair = HOVER; ai_t = HOVER_T; }
        break;
    case HOVER:
        en.x = toward(en.x, aim(), 2);
        k = ftick & 15;
        en.y = HOVER_Y + (k < 8 ? k : 15 - k);
        if (!--ai_t) { iair = STELE; ai_t = STELE_T; }
        break;
    case STELE:                        /* warning: flickers (still hittable), follows the player, then locks on */
        boss_hide = f;
        en.x = toward(en.x, aim(), 4);
        if (--ai_t) break;
        tx = aim(); iair = DIVE;
        break;
    case DIVE:                         /* straight down onto where the player was */
        en.x = toward(en.x, tx, 2);
        en.y = toward(en.y, GROUND, p->spd);
        if (en.y == GROUND) {
            if (p->shots) quake(p);
            iair = REST; ai_t = REST_T;
        }
        break;
    default:                           /* REST: sits on the floor and blinks slowly, then teleports away (never idles on top of the player) */
        boss_hide = (ftick & 16) ? 2 : 0;
        if (!--ai_t) { act = 'T'; iair = FADE; ai_t = FADE_T; }
        break;
    }
    sprites();
}
