/* Demon 1, Imp: code and phase data live in PRG bank 0 ($8000). Docs: docs/TECH.md "PRG-Banking". */
#pragma code-name("BANK0")
#pragma rodata-name("BANK0")
#include "nes.h"
#include "boss.h"

#define STOP 28                        /* a hop toward the player ends at least this many px from him (sword reach: he can hit it from there) */

const struct phase imp_ph[3] = {
    { BT + 0, 1, 140, 600, 1, 1, { 0x0A, 0x2A, 0x38 } },
    { BT + 4, 1, 100, 560, 1, 1, { 0x07, 0x27, 0x38 } },
    { BT + 8, 2, 72, 560, 3, 1, { 0x0F, 0x16, 0x38 } }
};

/* Imp: hops (floor only) toward the player (1 in 4 away), spits fireballs at him. */
void imp_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    signed char d, v;
    unsigned char k, s;
    int nx, dx;

    rng = rng * 5 + 17;
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
    dx = (int)player_x - nx;
    if ((dx < 0 ? -dx : dx) < STOP && (ivx > 0) == (player_x > en.x)) nx = en.x;      /* never hops onto the player: stays STOP px away */
    if (nx < WALL) nx = WALL;
    if (nx > 256 - WALL - 16) nx = 256 - WALL - 16;
    en.x = nx;
    en.y += ivy;
    if (++ig == 3) { ig = 0; ++ivy; }
    if (ivy >= 0 && en.y + 16 >= FLOOR_Y) { en.y = FLOOR_Y - 16; ivx = ivy = iair = 0; }
}

