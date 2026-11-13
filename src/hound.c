/* Demon 3, Bone hound: code and phase data live in PRG bank 2 ($8000). Docs: docs/GAMEDESIGN.md, docs/TECH.md "Knochenhund". */
#pragma code-name("BANK2")
#pragma rodata-name("BANK2")
#include "nes.h"
#include "boss.h"

/* tile = first of 6 (24x16: left 16x16 as 4 tiles, then top and bottom of the right column); spd = run px/frame;
   wait = telegraph frames; rate = frames between attacks; shots = charges per attack (2 = back to back);
   fspd = charge px/frame. Phase 2/3 sometimes leap instead of charging (see hound_ai). */
const struct phase hound_ph[3] = {
    { BT + 0, 1, 30, 480, 1, 4, { 0x08, 0x37, 0x2A } },
    { BT + 6, 1, 24, 460, 1, 5, { 0x06, 0x37, 0x16 } },
    { BT + 12, 2, 20, 520, 2, 5, { 0x0F, 0x16, 0x38 } }
};

/* iair = state. fb_t counts frames to the next attack, ig is the bite cooldown (90), ai_t the state timer. */
enum { RUN, TELE, CHARGE, REST, BITE, LEAP };
#define REST_T  40                     /* dizzy after a charge: the window to hit it */
#define TURN_T  10                     /* short telegraph before the second charge of a back-to-back pair */
#define BITE_T  10                     /* lunge: 3 px/frame */
#define KEEP    56                     /* patrol turns back this far from the player */
#define BITE_R  28                     /* bite range: a standing player is not bitten by a hound passing or resting at 32 px */
#define MAXX    (256 - WALL - 24)

static unsigned char leap, left;       /* attack kind (1 = leap), charges still to run */

/* Move en.x by v, clamped to the walls; returns 1 when it stands at a wall. */
static unsigned char step(signed char v)
{
    int nx = en.x + v;
    if (nx < WALL) nx = WALL;
    if (nx > MAXX) nx = MAXX;
    en.x = nx;
    return nx == WALL || nx == MAXX;
}

static void rest(unsigned char t)
{
    iair = REST; ai_t = t; ivx = ivy = 0;
}

void hound_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    signed char d = player_x > en.x ? 1 : -1;
    int dx;

    rng = rng * 5 + 17;
    boss_hide = 0;
    switch (iair) {
    case RUN:                          /* patrol, turn at the walls */
        if (ig) --ig;
        if (fb_t) --fb_t;
        else {
            iair = TELE; ai_t = p->wait; en.dir = d; left = p->shots;
            leap = boss_phase > 1 && !(rng & (boss_phase == 2 ? 0xC0 : 0x40));
            break;
        }
        dx = (int)player_x - en.x;
        if (!ig && player_y > FLOOR_Y - 24 && (unsigned)(dx + BITE_R) < 2 * BITE_R) {      /* player close and on the ground: bite */
            iair = BITE; ai_t = BITE_T; en.dir = d; ig = 90;
            break;
        }
        if (en.dir == d && (unsigned)(dx + KEEP) < 2 * KEEP) en.dir = -en.dir;     /* never patrols into the player: turns KEEP px short */
        if (step(en.dir * (signed char)p->spd)) en.dir = -en.dir;
        break;
    case TELE:                         /* paw-scrape: flickers, stands still */
        boss_hide = (ftick & 4) ? 2 : 0;
        if (--ai_t) break;
        if (leap) {
            dx = ((int)player_x - en.x) >> 5;
            ivx = dx > 4 ? 4 : dx < -4 ? -4 : dx;
            ivy = -5; ig = 0; iair = LEAP;
        } else iair = CHARGE;
        break;
    case CHARGE:
        if (step(en.dir * (signed char)p->fspd)) {
            if (--left) { en.dir = -en.dir; iair = TELE; ai_t = TURN_T; }
            else { rest(REST_T); fb_t = p->rate; }
        }
        break;
    case BITE:
        step(en.dir * 3);
        if (!--ai_t) rest(20);
        break;
    case LEAP:                         /* arc toward where the player stood, then dizzy */
        step(ivx);
        en.y += ivy;
        if (++ig == 3) { ig = 0; ++ivy; }
        if (ivy >= 0 && en.y + 16 >= FLOOR_Y) { en.y = FLOOR_Y - 16; rest(20); fb_t = p->rate; }
        break;
    default:                           /* REST */
        boss_hide = (ftick & 16) ? 2 : 0;
        if (!--ai_t) iair = RUN;
        break;
    }
}
