/* Demon 9, Oni warlord: code and phase data live in PRG bank 8 ($8000). Docs: docs/GAMEDESIGN.md, docs/TECH.md "Oni-Kriegsherr". */
#pragma code-name("BANK8")
#pragma rodata-name("BANK8")
#include "nes.h"
#include "boss.h"

/* tile = first of 10 body tiles (rows of 3, 3, 2, 2 sprites, 24 px wide on top, 16 px legs below, drawn facing right);
   spd = walk px/frame; wait = frames the club stays raised; rate = idle frames between attacks; shots = smashes per smash
   attack; fspd = shockwave px/frame. Phase 2 sends shockwaves both ways and charges faster, phase 3 adds the double smash
   (forward waves) and the leap (waves both ways on landing). */
const struct phase oni_ph[3] = {
    { BT + 0, 1, 26, 300, 1, 2, { 0x06, 0x26, 0x38 } },
    { BT + 10, 2, 22, 220, 1, 3, { 0x06, 0x16, 0x30 } },
    { BT + 20, 2, 22, 190, 2, 3, { 0x0F, 0x06, 0x28 } }
};
static const unsigned char cspd[3] = { 4, 5, 5 };      /* charge px/frame */
static const unsigned char rest[3] = { 40, 34, 28 };   /* recovery frames: the hit window shrinks */

/* iair = state, ai_t = state timer, fb_t = idle frames until the next attack, ig/ivx/ivy = leap tick and speed. */
enum { INIT, WALK, STELE, SMASH, REST, CTELE, CHARGE, LTELE, LEAP };
#define GROUND  (FLOOR_Y - 32)
#define MAXX    (256 - WALL - 24)
#define STAND   32                     /* walks until its front edge is this far from the player's center */
#define COOL    120                    /* frames after a recovery in which a sword hit gets no smash in return */
#define SMASH_T 6                      /* frames the club contact box is live */
#define TELE2   20                     /* club raised again before the second smash */
#define O_ONI   72                     /* OAM byte offset: 10 body sprites, then 2 club sprites (up to byte 119) */
#define O_FB    52                     /* the boss fireball sprites (dungeon.c): shockwaves here */
#define CLUB    (BT + 30)                   /* club head tile, handle = +1 */

static unsigned char ph, left, cool;   /* phase seen, smashes left in this attack, reaction cooldown */

static unsigned char step(signed char v)   /* move by v, clamped to the walls; 1 = stands at a wall */
{
    int nx = en.x + v;
    if (nx < WALL) nx = WALL;
    if (nx > MAXX) nx = MAXX;
    en.x = nx;
    return nx == WALL || nx == MAXX;
}

static void face(void)
{
    en.dir = (int)player_x + 8 >= (int)en.x + 12 ? 1 : -1;
}

static int gap(void)                   /* px from the front edge to the player's center (negative: overlapping) */
{
    return en.dir > 0 ? (int)player_x + 8 - (int)en.x - 24 : (int)en.x - (int)player_x - 8;
}

static void wave(unsigned char x, signed char v)       /* a shockwave on the floor: low, 8x8, jumpable */
{
    unsigned char k;
    for (k = 0; k < FB_MAX; ++k)
        if (!fb_x[k]) {
            oam[O_FB + k * 4 + 1] = SHOCK; oam[O_FB + k * 4 + 2] = 1;
            fb_x[k] = x; fb_y[k] = FLOOR_Y - 9; fb_vx[k] = v; fb_vy[k] = 0;
            return;
        }
}

static void quake(const struct phase *p, unsigned char both)   /* forward from the club, backward from the heel */
{
    signed char v = en.dir > 0 ? (signed char)p->fspd : -(signed char)p->fspd;
    wave(en.dir > 0 ? en.x + 24 : en.x - 8, v);
    if (both) wave(en.dir > 0 ? en.x - 8 : en.x + 24, -v);
}

static void smash(const struct phase *p)
{
    left = p->shots; iair = STELE; ai_t = p->wait;
}

static void pick(const struct phase *p)                 /* idle time is up: smash, charge or (phase 3) leap */
{
    unsigned char r = rng >> 6;
    face();
    if (boss_phase == 1 ? r == 3 : boss_phase == 2 ? r > 1 : r == 0) { iair = CTELE; ai_t = p->wait; }
    else if (boss_phase == 3 && r == 1) { iair = LTELE; ai_t = p->wait + 10; }   /* the leap lands on where he stands: a longer warning */
    else smash(p);
}

/* Body (10 sprites), then the club (2): raised above the front shoulder while telegraphing, in front during the smash. */
static void sprites(void)
{
    unsigned char *o = oam + O_ONI;
    unsigned char r, c, n, x0, t = bs->ph[boss_phase - 1].tile;
    unsigned char hide = (boss_hide & 2) || BLINK || !en.hp;
    unsigned char fl = en.dir > 0 ? 1 : 0x41;
    for (r = 0; r < 4; ++r) {
        n = r < 2 ? 3 : 2;
        x0 = en.x + (r < 2 ? 0 : 4);
        for (c = 0; c < n; ++c) {
            *o++ = hide ? 0xFF : en.y + r * 8 - 1;
            *o++ = t++;
            *o++ = fl;
            *o++ = x0 + (en.dir > 0 ? c : n - 1 - c) * 8;
        }
    }
    x0 = iair == STELE ? (en.dir > 0 ? en.x + 16 : en.x) : (en.dir > 0 ? en.x + 24 : en.x - 8);
    n = iair == STELE ? en.y - 17 : en.y - 1;
    *o++ = iair == STELE || iair == SMASH ? n : 0xFF;
    *o++ = iair == STELE ? CLUB : CLUB + 1;
    *o++ = fl;
    *o++ = x0;
    *o++ = iair == STELE || iair == SMASH ? n + 8 : 0xFF;
    *o++ = iair == STELE ? CLUB + 1 : CLUB;
    *o++ = iair == STELE ? fl : fl | 0x80;             /* smash: head down */
    *o++ = x0;
}

void oni_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    int g, d;

    if (intro || boss_fx) { sprites(); return; }       /* frozen: only redraw (new look at a phase change) */
    rng = rng * 5 + 17;
    boss_hide = 0;
    if (iair == INIT || ph != boss_phase) {            /* first frame, or a new phase: back to walking on the floor */
        ph = boss_phase; iair = WALK; fb_t = p->rate; cool = COOL; en.y = GROUND;
    }
    switch (iair) {
    case WALK:                         /* walk toward the player, stop at a distance */
        face();
        if (cool) --cool;
        g = gap();
        if (g > STAND) step(en.dir * (signed char)p->spd);
        else if (g < STAND / 2) step(-en.dir * (signed char)p->spd);     /* the player is in its face (after a leap or a charge): it backs off instead of sitting on him */
        if (fb_t) --fb_t;
        if (!fb_t) pick(p);
        else if (en.flash && !cool) smash(p);        /* hit while walking: retaliates */
        break;
    case STELE:                        /* club up: flickers, then the club comes down and the shockwave runs */
        boss_hide = (ftick & 4) ? 2 : 0;
        if (--ai_t) break;
        quake(p, boss_phase == 2);       /* phase 3 smashes twice: forward only (sprite budget) */
        iair = SMASH; ai_t = SMASH_T;
        break;
    case SMASH:                        /* the club hits the floor in front: contact box */
        d = en.dir > 0 ? en.x + 24 : en.x - 16;
        if (!invuln && overlap(player_x + 3, player_y + 2, 10, 14, d, FLOOR_Y - 24, 16, 24)) hurt(d + 8);
        if (--ai_t) break;
        if (--left) { iair = STELE; ai_t = TELE2; }
        else { iair = REST; ai_t = rest[boss_phase - 1]; }
        break;
    case CTELE:                        /* charge telegraph: flickers, stands still */
        boss_hide = (ftick & 4) ? 2 : 0;
        if (!--ai_t) iair = CHARGE;
        break;
    case CHARGE:                       /* across the arena (jumpable, dashable), dazed at the wall */
        if (step(en.dir * (signed char)cspd[boss_phase - 1])) { iair = REST; ai_t = rest[boss_phase - 1]; }
        break;
    case LTELE:                        /* crouch: flickers, then a leap to where the player stands */
        boss_hide = (ftick & 4) ? 2 : 0;
        if (--ai_t) break;
        d = (int)player_x + 8 - (int)en.x - 12;
        d = (d + (d < 0 ? -16 : 16)) / 32;                /* ~1 px/frame per 32 px, rounded */
        ivx = d > 4 ? 4 : d < -4 ? -4 : d;
        ivy = -6; ig = 0; iair = LEAP;
        break;
    case LEAP:                         /* arc (63 px high), shockwaves both ways on landing */
        step(ivx);
        en.y += ivy;
        if (++ig == 3) { ig = 0; ++ivy; }
        if (ivy >= 0 && en.y >= GROUND) { en.y = GROUND; quake(p, 1); iair = REST; ai_t = rest[boss_phase - 1]; }
        break;
    default:                           /* REST: sits still and blinks slowly, the main hit window */
        boss_hide = (ftick & 16) ? 2 : 0;
        if (!--ai_t) { iair = WALK; fb_t = p->rate; cool = COOL; }
        break;
    }
    sprites();
}
