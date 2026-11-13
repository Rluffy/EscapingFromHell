/* Demon 6, Mirror demon: code and phase data live in PRG bank 5 ($8000). Docs: docs/GAMEDESIGN.md, docs/TECH.md "Spiegeldämon". */
#pragma code-name("BANK5")
#pragma rodata-name("BANK5")
#include "nes.h"
#include "boss.h"

/* tile = first of 6 (16x24); spd = walk speed in quarter px/frame; wait = frames walking between teleports;
   rate = frames between shots; shots = fireballs per shot; fspd = fireball px/frame. The copies count equals the phase. */
const struct phase mirror_ph[3] = {
    { BT + 0, 2, 240, 150, 1, 1, { 0x01, 0x21, 0x30 } },
    { BT + 6, 3, 190, 120, 1, 1, { 0x04, 0x24, 0x38 } },
    { BT + 12, 4, 150, 100, 2, 1, { 0x06, 0x16, 0x38 } }
};

/* iair = state. ig = frames of walking left, ai_t = fade / appear timer, fb_t = frames to the next shot. */
enum { INIT, WALK, OUT, IN };
#define OUT_T   20                     /* fading out: flickers, untouchable */
#define IN_T    24                     /* telegraph at the new spot: flickers, untouchable */
#define WARN_T  20                     /* flicker before a shot (not drawn, still hittable) */
#define CTILE   (BT + 18)                   /* copy head tiles (dull eyes): CTILE + 2 * (phase - 1) */
#define O_COPY  140                    /* OAM byte offset of the copies: 3 x 6 sprites, up to byte 211 */

/* Spots: 0 floor, 1/2 the side platforms, 3 the top platform; x range of the demon's left edge, and y. */
static const unsigned char sx0[4] = { WALL, 32, 176, 104 }, sx1[4] = { 224, 64, 208, 136 }, sy[4] = { FLOOR_Y - 24, 128, 128, 88 };

extern unsigned char mcx[3], mcur;     /* debug.s $032C..$032F: copies' x (0 = popped / none), spot of the original */
static unsigned char cs[3];            /* spot of each copy */
static unsigned char ph;               /* phase seen last (stale values are harmless: INIT sets it) */

static unsigned char spot_x(unsigned char s)
{
    return s ? (sx0[s] + sx1[s]) >> 1 : player_x < 128 ? 200 : 40;     /* floor: the far side from the player */
}

/* Original on spot o, one copy per phase on other spots; no copy shares the original's height (<= 8 sprites per line). */
static void place(unsigned char o)
{
    unsigned char s, k = 0;
    mcur = o; en.x = spot_x(o); en.y = sy[o];
    mcx[0] = mcx[1] = mcx[2] = 0;
    fb_x[0] = fb_x[1] = fb_x[2] = 0;       /* shots die with the teleport: none left on a height the new copies share */
    for (s = 0; s < 4 && k < boss_phase; ++s)
        if (((s + 1) >> 1) != ((o + 1) >> 1)) { mcx[k] = spot_x(s); cs[k++] = s; }
}

static unsigned char clamp(unsigned char x, signed char d, unsigned char s)
{
    int v = x + d;
    return v < sx0[s] ? sx0[s] : v > sx1[s] ? sx1[s] : v;
}

static void walk(signed char d)        /* original and copies move together, each inside its own spot */
{
    unsigned char k;
    en.x = clamp(en.x, d, mcur);        /* also pulls a knocked-back original back onto its platform */
    for (k = 0; k < 3; ++k) if (mcx[k]) mcx[k] = clamp(mcx[k], d, cs[k]);
}

static void spit(const struct phase *p)
{
    unsigned char k, n;
    signed char vx = player_x > en.x ? (signed char)p->fspd : -(signed char)p->fspd;
    for (n = 0; n < p->shots; ++n)
        for (k = 0; k < FB_MAX; ++k)
            if (!fb_x[k]) {
                fb_x[k] = en.x + 4; fb_y[k] = en.y + 4 + n * 8; fb_vx[k] = vx; fb_vy[k] = 0;
                break;
            }
}

/* Copies: harmless, pop when the sword or the player fireball touches them, drawn like the demon (dull eyes). */
static void copies(void)
{
    unsigned char k, j, y, x, hide, t = bs->ph[boss_phase - 1].tile, c = CTILE + 2 * (boss_phase - 1);
    unsigned char *o = oam + O_COPY;       /* pointer walk: indexed oam[] math is too slow for the frame budget */
    for (k = 0; k < 3; ++k) {
        x = mcx[k];
        y = sy[cs[k]];
        if (x && !(boss_hide & 1)) {
            if (pf_x && overlap(pf_x, pf_y, 8, 8, x, y, 16, 24)) { pf_x = 0; mcx[k] = x = 0; }
            else if (sword_t && overlap(facing ? player_x - 16 : player_x + 12, player_y + 6, 20, 8, x, y, 16, 24)) mcx[k] = x = 0;
        }
        hide = !x || (boss_hide & 2);
        --y;
        for (j = 0; j < 6; ++j) {
            *o++ = hide ? 0xFF : y + (j & 6) * 4;      /* rows at +0, +8, +16 */
            *o++ = j < 2 ? c + j : t + j;
            *o++ = 1;
            *o++ = x + (j & 1) * 8;
        }
    }
}

void mirror_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    unsigned char f = (ftick & 4) ? 2 : 0, o;
    signed char d = 0;

    boss_hide = 0;
    rng = rng * 5 + 17;
    if (iair == INIT) { ph = boss_phase; place(0); iair = IN; ai_t = IN_T; }
    else if (ph != boss_phase) { ph = boss_phase; iair = OUT; ai_t = OUT_T; }   /* new phase: teleport now, new copy count */
    switch (iair) {
    case WALK:                         /* walk toward the player; shoot; teleport when the walk time is up */
        if (fb_t < WARN_T) boss_hide = f;
        if (fb_t) --fb_t;
        else { spit(p); fb_t = p->rate; }
        if ((ivx += p->spd) >= 4) {
            ivx -= 4;
            d = player_x > en.x + 4 ? 1 : player_x + 4 < en.x ? -1 : 0;
        }
        walk(d);
        if (!--ig) { iair = OUT; ai_t = OUT_T; }
        break;
    case OUT:
        boss_hide = 1 | f;
        if (!--ai_t) {
            o = (rng >> 2) & 3;
            place(o == mcur ? (o + 1) & 3 : o);
            iair = IN; ai_t = IN_T;
        }
        break;
    case IN:
        boss_hide = 1 | f;
        if (!--ai_t) { iair = WALK; ig = p->wait; fb_t = p->rate; }
        break;
    }
    copies();
}
