/* Demon 8, Spider queen: code and phase data live in PRG bank 7 ($8000). Docs: docs/GAMEDESIGN.md, docs/TECH.md "Spinnenkönigin". */
#pragma code-name("BANK7")
#pragma rodata-name("BANK7")
#include "nes.h"
#include "boss.h"

/* tile = first of 6 (24x16, like the hound); spd = descent px/frame; wait = frames hanging low; rate = frames crawling on the
   ceiling between descents; shots = webs per volley; fspd = crawl px/frame. */
const struct phase spider_ph[3] = {
    { BT + 0, 2, 55, 200, 1, 1, { 0x03, 0x13, 0x2A } },
    { BT + 6, 3, 45, 150, 2, 1, { 0x05, 0x25, 0x2A } },
    { BT + 12, 4, 40, 110, 3, 2, { 0x06, 0x16, 0x28 } }
};
static const unsigned char wint[3] = { 120, 80, 70 };      /* frames between web volleys while crawling */

/* iair = state, ai_t = state timer, ig = crawl frames left, fb_t = frames to the next volley. */
enum { INIT, CRAWL, TELE, DESC, HANG, CLIMB };
#define CEIL_Y  32                     /* body top while on the ceiling (the ceiling tiles are row 3, y 24..31) */
#define HANG_Y  144                    /* body top while hanging low: a jump plus a sword swing (or a platform) reaches it */
#define MAXX    (256 - WALL - 24)
#define TELE_T  30                     /* flicker before a descent */
#define WARN_T  15                     /* flicker before a volley */
#define CLIMB_V 2
#define SPIDERLING (BT + 20)                /* sprite tile of a dropped spiderling (web ball: WEB_TILE in boss.h) */
#define O_THREAD 72                    /* OAM byte offset: 14 thread sprites (up to byte 127) */
#define NTHREAD  14
#define O_FB    52                     /* the boss fireball sprites (dungeon.c) */

static unsigned char vn;               /* volley counter (a stale value is harmless: INIT sets it) */

/* The thread: 8x8 sprites in one column from the ceiling down to the body (one sprite per scanline at most). */
static void thread(void)
{
    unsigned char *o = oam + O_THREAD;
    unsigned char i, y = en.y, n = (en.y - CEIL_Y + 7) >> 3;
    unsigned char hide = (boss_hide & 2) || (en.flash & 2) || !en.hp;
    for (i = 0; i < NTHREAD; ++i) {
        y -= 8;
        *o++ = hide || i >= n ? 0xFF : y - 1;
        *o++ = BT + 18;
        *o++ = 1;
        *o++ = en.x + 8;
    }
}

static unsigned char slot(unsigned char tile)       /* a free fireball slot with its sprite set to tile, 255 = none */
{
    unsigned char k;
    for (k = 0; k < FB_MAX; ++k)
        if (!fb_x[k]) { oam[O_FB + k * 4 + 1] = tile; oam[O_FB + k * 4 + 2] = 1; return k; }
    return 255;
}

/* Webs aimed at the player: 1 px/frame sideways, falling slowly. Ball 0 aimed, 1 straight down, 2 the mirror of 0. */
static void webs(const struct phase *p)
{
    unsigned char n, k;
    int dx = (int)player_x + 4 - (en.x + 8), dy = (int)player_y + 8 - (en.y + 16), a = dx < 0 ? -dx : dx;
    signed char vx = a < 24 ? 0 : dx < 0 ? -1 : 1, v = a < 24 ? 3 : (2 * dy) / a;
    if (v > 4) v = 4;
    if (v < 1) v = 1;
    for (n = 0; n < p->shots; ++n)
        if ((k = slot(WEB_TILE)) != 255) {
            fb_x[k] = en.x + 8; fb_y[k] = en.y + 16;
            fb_vx[k] = n == 0 ? vx : n == 1 ? 0 : -vx;
            fb_vy[k] = n == 0 ? v : 3;
        }
}

static void drop(void)                 /* spiderlings fall straight down from the body (cost a heart) */
{
    unsigned char n, k;
    for (n = 0; n < 2; ++n)
        if ((k = slot(SPIDERLING)) != 255) {
            fb_x[k] = en.x + 4 + n * 10; fb_y[k] = en.y + 16; fb_vx[k] = 0; fb_vy[k] = 4;
        }
}

void spider_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    unsigned char f = (ftick & 4) ? 2 : 0;
    int d, nx;

    boss_hide = 0;
    if (iair == INIT) { vn = 0; en.y = CEIL_Y; ig = p->rate; fb_t = 60; iair = CRAWL; }
    switch (iair) {
    case CRAWL:                        /* along the ceiling, wall to wall; webs on a timer; then the descent */
        nx = en.x + en.dir * p->fspd;
        if (nx <= WALL || nx >= MAXX) en.dir = -en.dir;
        en.x = nx < WALL ? WALL : nx > MAXX ? MAXX : nx;
        if (fb_t < WARN_T) boss_hide = f;
        if (fb_t) --fb_t;
        else {
            if (boss_phase == 3 && (vn++ & 1)) drop(); else webs(p);
            fb_t = wint[boss_phase - 1];
        }
        if (!--ig) { iair = TELE; ai_t = TELE_T; }
        break;
    case TELE:                         /* flickers (still hittable, out of reach anyway) and slides over the player */
        boss_hide = f;
        d = (int)player_x - 4 - en.x;
        en.x += d > 6 ? 6 : d < -6 ? -6 : d;
        if (en.x < WALL) en.x = WALL;
        if (en.x > MAXX) en.x = MAXX;
        if (!--ai_t) iair = DESC;
        break;
    case DESC:                         /* down the thread, x fixed */
        en.y += p->spd;
        if (en.y >= HANG_Y) { en.y = HANG_Y; iair = HANG; ai_t = p->wait; }
        break;
    case HANG:                         /* the hit window */
        if (!--ai_t) iair = CLIMB;
        break;
    case CLIMB:
        en.y -= CLIMB_V;
        if (en.y <= CEIL_Y) { en.y = CEIL_Y; iair = CRAWL; ig = p->rate; }
        break;
    }
    thread();
}
