/* Demon 2, Ghost: code and phase data live in PRG bank 1 ($8000). Docs: docs/GAMEDESIGN.md, docs/TECH.md "Ghost". */
#pragma code-name("BANK1")
#pragma rodata-name("BANK1")
#include "nes.h"
#include "boss.h"

/* tile = first of 6 (16x24); spd = x drift in quarter px/frame; wait = frames solid before it vanishes;
   rate = frames between attacks (0 = none); shots = 1: every second attack is a fireball; fspd = fireball px/frame. */
const struct phase ghost_ph[3] = {
    { BT + 0, 2, 250,   0, 0, 1, { 0x22, 0x30, 0x0F } },
    { BT + 6, 3, 220, 150, 0, 1, { 0x03, 0x33, 0x16 } },
    { BT + 12, 4, 160, 180, 1, 1, { 0x0F, 0x16, 0x38 } }
};

/* iair = state. SOLID counts the visible window (ig) and the attack timer (fb_t). */
enum { INIT, SOLID, OUT, GONE, IN, TELE, SWOOP };
#define OUT_T  20                      /* flickers (still hittable) before it vanishes */
#define GONE_T 90                      /* invisible and untouchable */
#define IN_T   30                      /* flickers (still untouchable) before it is solid again */
#define TELE_T 30                      /* attack warning: stands still and flickers */

static unsigned char tx, ty, par;      /* swoop target, attack parity (stale values are harmless: INIT comes first) */

static unsigned char toward(unsigned char a, unsigned char b, unsigned char m)
{
    if (a + m < b) return a + m;
    if (a > b + m) return a - m;
    return b;
}

void ghost_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    unsigned char k, f = (frame_count & 4) ? 2 : 0;
    int t;

    boss_hide = 0;
    if (iair != TELE && iair != SWOOP) {
        t = player_x + ((frame_count & 255) < 128 ? 40 : -40);      /* drift beside the player, switching sides */
        if (t < WALL) t = WALL;
        if (t > 256 - WALL - 16) t = 256 - WALL - 16;
        ivx += p->spd;
        if (ivx >= 4) { ivx -= 4; en.x = toward(en.x, t, 1); }
        k = frame_count & 127;                                      /* bob: triangle wave, y 104..168 */
        en.y = toward(en.y, 104 + (k < 64 ? 64 - k : k - 64), 2);
    }
    switch (iair) {
    case INIT:
        iair = SOLID; ig = p->wait;
        break;
    case SOLID:
        if (!ig) { iair = OUT; ai_t = OUT_T; break; }
        --ig;
        if (!p->rate) break;
        if (fb_t) { --fb_t; break; }
        iair = TELE; ai_t = TELE_T;
        tx = player_x;
        t = (int)player_y - 8;
        ty = t < 40 ? 40 : t;
        break;
    case OUT:
        boss_hide = f;
        if (!--ai_t) { iair = GONE; ai_t = GONE_T; }
        break;
    case GONE:
        boss_hide = 3;
        if (!--ai_t) { iair = IN; ai_t = IN_T; }
        break;
    case IN:
        boss_hide = 1 | f;
        if (!--ai_t) { iair = SOLID; ig = p->wait; }
        break;
    case TELE:
        boss_hide = f;
        if (--ai_t) break;
        fb_t = p->rate;
        par ^= 1;
        if (p->shots && par) {
            iair = SOLID;
            for (k = 0; k < FB_MAX; ++k)
                if (!fb_x[k]) {
                    fb_x[k] = en.x + 4;
                    fb_y[k] = en.y + 8;
                    fb_vx[k] = player_x > en.x ? (signed char)p->fspd : -(signed char)p->fspd;
                    fb_vy[k] = player_y > en.y + 8 ? 1 : player_y + 8 < en.y ? -1 : 0;
                    break;
                }
        } else { iair = SWOOP; ai_t = 60; }
        break;
    case SWOOP:
        en.x = toward(en.x, tx, 3);
        en.y = toward(en.y, ty, 3);
        if (en.x == tx && en.y == ty && ai_t > 20) ai_t = 20;       /* short rest at the bottom: the sword gets its chance */
        if (!--ai_t) iair = SOLID;
        break;
    }
}
