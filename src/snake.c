/* Demon 4, Lava snake: code and phase data live in PRG bank 3 ($8000). Docs: docs/GAMEDESIGN.md, docs/TECH.md "Lavaschlange". */
#pragma code-name("BANK3")
#pragma rodata-name("BANK3")
#include "nes.h"
#include "boss.h"

/* tile = first of 6: head 16x16 (4 tiles), then the two halves of a 16x8 body segment; spd = rise/sink/lean px/frame;
   wait = frames submerged; rate = frames between spits while up; shots = fireballs per spit (3 = spread);
   fspd = fireball px/frame. Phase 2 spits twice per visit (short rate), phase 3 spreads and hides shorter. */
const struct phase snake_ph[3] = {
    { BT + 0, 1, 100, 120, 1, 1, { 0x07, 0x27, 0x30 } },
    { BT + 6, 2,  70,  70, 1, 1, { 0x06, 0x26, 0x38 } },
    { BT + 12, 2,  40,  80, 3, 1, { 0x06, 0x16, 0x30 } }
};

/* iair = state. ai_t = state timer (also the time left up), fb_t = frames to the next spit. */
enum { INIT, HIDE, TELE, RISE, UP, SINK };
#define TELE_T  30                     /* bubbling at the pool: flickers, untouchable */
#define UP_T    170                    /* frames hovering */
#define WARN_T  20                     /* head flickers (still hittable) before a spit */
#define HOVER   124                    /* head y when up; bobs down by 0..12 */
#define REST_Y  176                    /* head y at the pool: resting on the floor */
#define LEAN    96                     /* max px the head leans from its pool toward the player */
#define MAXSEG  8
#define O_BODY  72                     /* OAM byte offset of the body segments (after the 3rd enemy row at 64) */

static const signed char wob[8] = { 0, 2, 3, 2, 0, -2, -3, -2 };
static unsigned char side;             /* 0 = pool at the left wall, 1 = right (stale values are harmless: INIT comes first) */

static unsigned char toward(unsigned char a, unsigned char b, unsigned char m)
{
    if (a + m < b) return a + m;
    if (a > b + m) return a - m;
    return b;
}

static void spit(const struct phase *p)
{
    unsigned char k, n;
    signed char vx = player_x > en.x ? (signed char)p->fspd : -(signed char)p->fspd, vy;
    int dx = (int)player_x - en.x, dy = (int)player_y - en.y;

    if (dx < 0) dx = -dx;
    if (dx < 8) dx = 8;
    dy = dy * 2 * (int)p->fspd / dx;                    /* aimed: vertical speed is half-rate (see fireballs()) */
    vy = boss_phase == 1 ? 0 : dy < -2 ? -2 : dy > 3 ? 3 : dy;      /* phase 1 shoots level with the head: harmless on the floor */
    for (n = 0; n < p->shots; ++n)
        for (k = 0; k < FB_MAX; ++k)
            if (!fb_x[k]) {
                fb_x[k] = en.x + 4;
                fb_y[k] = en.y + 4 + (n - (p->shots >> 1)) * 8;    /* spread: staggered start, diverging paths */
                fb_vx[k] = vx;
                fb_vy[k] = vy + n - (p->shots >> 1);
                break;
            }
}

/* Body: 16x8 segments in a column from the pool to the head, 8 px apart (so one segment per scanline), bending out
   to the head's x in a curve plus a small wiggle. Contact hurts; only the head can be hit. */
static void body(const struct phase *p)
{
    unsigned char j, o = O_BODY, n = (FLOOR_Y - 16 - en.y) >> 3, step = 255 / (n + 1), rx = side ? 216 : 24;
    unsigned char y, x;
    unsigned f, q;
    int d;

    if (n > MAXSEG) n = MAXSEG;
    for (j = 0; j < MAXSEG; ++j, o += 8) {
        if (j >= n) { oam[o] = oam[o + 4] = 0xFF; continue; }
        f = 255 - (j + 1) * step;
        q = ((f * f >> 8) + f) >> 1;                    /* between linear and quadratic: hugs the wall low, bends to the head high */
        y = en.y + 16 + j * 8;
        d = en.x; d -= rx; d = (d * (int)q) >> 8;
        x = rx + d + wob[((frame_count >> 2) + j) & 7];
        oam[o] = oam[o + 4] = y - 1;
        oam[o + 1] = p->tile + 4; oam[o + 5] = p->tile + 5;
        oam[o + 2] = oam[o + 6] = 1;
        oam[o + 3] = x; oam[o + 7] = x + 8;
        if (!invuln && overlap(player_x + 3, player_y + 2, 10, 14, x, y, 16, 8)) { hurt(x + 8); return; }
    }
}

void snake_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    unsigned char f = (frame_count & 4) ? 2 : 0, k = frame_count & 63, rx = side ? 216 : 24;
    int t;

    boss_hide = 0;
    switch (iair) {
    case INIT:
        en.x = rx; en.y = REST_Y;
        iair = HIDE; ai_t = 30;
        break;
    case HIDE:                         /* submerged: invisible and untouchable; re-emerges at the other wall */
        boss_hide = 3;
        if (--ai_t) break;
        side ^= 1;
        en.x = side ? 216 : 24; en.y = REST_Y;
        iair = TELE; ai_t = TELE_T;
        break;
    case TELE:                         /* flickers at the pool, still untouchable */
        boss_hide = 1 | f;
        if (!--ai_t) iair = RISE;
        break;
    default:                           /* RISE, UP, SINK: in UP lean toward the player, sway, bob */
        t = (int)player_x - 8 + ((k < 32 ? k : 63 - k) - 16);
        if (iair != UP) t = rx;                          /* rises straight out of the pool, sinks back into it */
        else if (side) t = t > rx ? rx : t < rx - LEAN ? rx - LEAN : t;
        else t = t < rx ? rx : t > rx + LEAN ? rx + LEAN : t;
        en.x = toward(en.x, t, iair == SINK ? 2 * p->spd : p->spd);
        if (iair == RISE) {
            en.y = toward(en.y, HOVER, p->spd);
            if (en.y == HOVER) { iair = UP; ai_t = UP_T; fb_t = 60; }
        } else if (iair == SINK) {
            en.y = toward(en.y, REST_Y, p->spd);
            if (en.y == REST_Y) { iair = HIDE; ai_t = p->wait; boss_hide = 3; }
        } else {
            en.y = toward(en.y, HOVER + ((k < 32 ? k : 63 - k) >> 2), 2);
            if (fb_t < WARN_T) boss_hide = f;           /* warning flicker: head not drawn but still hittable */
            if (fb_t) --fb_t;
            else { spit(p); fb_t = p->rate; }
            if (!--ai_t) iair = SINK;
        }
        break;
    }
    body(p);
}
