/* Demon 5, Winged demon: code and phase data live in PRG bank 4 ($8000). Docs: docs/GAMEDESIGN.md, docs/TECH.md "Geflügelter Dämon". */
#pragma code-name("BANK4")
#pragma rodata-name("BANK4")
#include "nes.h"
#include "boss.h"

/* tile = first of 6 (16x24); spd = dive px/frame; wait = telegraph frames; rate = frames of patrol between attacks;
   shots = fireballs dropped while rising (0 = none, 3 = spread); fspd = patrol speed in quarter px/frame. */
const struct phase winged_ph[3] = {
    { BT + 0, 4, 30, 460, 0, 3, { 0x04, 0x24, 0x30 } },
    { BT + 6, 5, 28, 440, 1, 5, { 0x06, 0x26, 0x38 } },
    { BT + 12, 5, 24, 420, 3, 6, { 0x06, 0x16, 0x30 } }
};

/* iair = state. fb_t = patrol frames left until the next attack, ai_t = telegraph / rest timer. */
enum { INIT, PATROL, TELE, DIVE, REST, RISE };
#define TOP_Y   56                     /* patrol height; bobs down by 0..15 */
#define LAND_Y  (FLOOR_Y - 24)         /* resting on the floor */
#define REST_T  40                     /* on the floor: the sword's main window */
#define RISE_V  3                      /* px/frame back up */
#define TELE2_T 14                     /* phase 3: telegraph of the second dive (only after a miss: a hit player is invulnerable and spared it) */
#define DROP_Y  120                    /* fireballs leave the demon when it rises above this */

static unsigned char tx, par;          /* dive target x, dives done in this attack (stale values are harmless: INIT comes first) */

static unsigned char toward(unsigned char a, unsigned char b, unsigned char m)
{
    if (a + m < b) return a + m;
    if (a > b + m) return a - m;
    return b;
}

static void drop(const struct phase *p)
{
    unsigned char k, n;
    signed char vx = player_x > en.x ? 1 : -1;
    for (n = 0; n < p->shots; ++n)
        for (k = 0; k < FB_MAX; ++k)
            if (!fb_x[k]) {
                fb_x[k] = en.x + 4;
                fb_y[k] = en.y + 8 + n * 8;                       /* staggered: one fireball per scanline */
                fb_vx[k] = p->shots > 1 ? (signed char)n - 1 : vx;   /* spread -1 / 0 / +1, else toward the player */
                fb_vy[k] = 2;                                     /* vertical runs at half rate: 1 px/frame down */
                break;
            }
}

void winged_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    unsigned char k = ftick & 63;

    boss_hide = 0;
    switch (iair) {
    case INIT:
        par = 0; iair = PATROL; fb_t = 90;
        break;
    case PATROL:                       /* fly left/right, bob gently; dive when the timer is up */
        ivx += p->fspd;
        while (ivx >= 4) {
            ivx -= 4; en.x += en.dir;
            if (en.x <= WALL) en.dir = 1;
            if (en.x >= 256 - WALL - 16) en.dir = -1;
        }
        en.y = toward(en.y, TOP_Y + ((k < 32 ? k : 63 - k) >> 1), 1);
        if (fb_t) --fb_t;
        else { iair = TELE; ai_t = p->wait; par = 0; }
        break;
    case TELE:                         /* hover above the player and flicker (still hittable) */
        boss_hide = (ftick & 4) ? 2 : 0;
        en.x = toward(en.x, (unsigned char)player_x, 4);
        en.y = toward(en.y, TOP_Y, 3);
        if (!--ai_t) { tx = player_x; iair = DIVE; }
        break;
    case DIVE:                         /* straight down (a little sideways) to where the player was */
        en.x = toward(en.x, tx, 2);
        en.y = toward(en.y, LAND_Y, p->spd);
        if (en.y == LAND_Y) { iair = REST; ai_t = REST_T; }
        break;
    case REST:
        if (!--ai_t) { iair = RISE; ig = 0; }
        break;
    default:                           /* RISE */
        en.y = toward(en.y, TOP_Y, RISE_V);
        if (!ig && en.y <= DROP_Y) { ig = 1; if (p->shots) drop(p); }
        if (en.y == TOP_Y) {
            if (boss_phase == 3 && !par && !invuln) { par = 1; iair = TELE; ai_t = TELE2_T; }     /* phase 3: a second dive in a row, but only after a miss */
            else { iair = PATROL; fb_t = p->rate; }
        }
        break;
    }
}
