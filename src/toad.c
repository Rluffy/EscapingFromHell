/* Demon 7, Giant toad: code and phase data live in PRG bank 6 ($8000). Docs: docs/GAMEDESIGN.md, docs/TECH.md "Riesenkröte". */
#pragma code-name("BANK6")
#pragma rodata-name("BANK6")
#include "nes.h"
#include "boss.h"

/* tile = first of 12 body tiles (32x24, row-major, drawn facing right); spd = gap in px between the toad's front edge and the
   player's center after a hop; wait = crouch frames before a hop; rate = frames sitting between actions; shots = slime blobs
   per spit; fspd = blob px/frame. */
const struct phase toad_ph[3] = {
    { BT + 0, 24, 30, 70, 0, 1, { 0x2A, 0x1A, 0x27 } },
    { BT + 12, 12, 30, 60, 1, 1, { 0x2A, 0x14, 0x26 } },
    { BT + 24, 12, 30, 50, 2, 1, { 0x24, 0x13, 0x16 } }
};
/* Action cycle per phase: H hop, T tongue, S spit. In phase 3 an action followed by the same one runs back to back. */
static const char seq[3][6] = { "HHT", "HSHT", "HHTTS" };

/* iair = state, ai_t = state timer. */
enum { INIT, SIT, CROUCH, HOP, LAND, TTELE, TONGUE, STELE };
#define GROUND  (FLOOR_Y - 24)
#define MAXX    (256 - WALL - 32)
#define LAND_T  40                     /* stunned after a landing: the window to hit it */
#define O_TOAD  72                     /* OAM byte offset: 3 tongue sprites, then 12 body sprites (up to byte 131) */
#define O_FB    52                     /* the boss fireball sprites (dungeon.c): turned into slime blobs here */

extern unsigned char tlen;             /* debug.s $0330: tongue segments out */
static unsigned char par, ph, ch, hs, hrem, hacc, shk;   /* action index, phase seen, back to back, hop step / remainder / accumulator, shake */
static signed char hd;                 /* hop direction */
static char lc;                        /* last action */

static char next(void)                 /* the action take() will return */
{
    const char *s = seq[boss_phase - 1];
    return s[par] ? s[par] : s[0];
}

static char take(void)
{
    const char *s = seq[boss_phase - 1];
    if (!s[par]) par = 0;
    return s[par++];
}

/* Tongue (3 sprites at the mouth), then the 12 body sprites. The default boss sprites are off (dungeon.c, en.w = 32). */
static void sprites(void)
{
    unsigned char *o = oam + O_TOAD;
    unsigned char j, r, c, x, t = bs->ph[boss_phase - 1].tile;
    unsigned char hide = (boss_hide & 2) || (en.flash & 2) || !en.hp;
    unsigned char fl = en.dir > 0 ? 1 : 0x41;
    unsigned char n = iair == TONGUE ? tlen : 0;
    unsigned char open = iair == TTELE || iair == STELE;
    unsigned char yo = iair == CROUCH ? 2 : 255;       /* en.y - 1; crouch: sinks 3 px and trembles */
    x = en.x + (iair == CROUCH && (frame_count & 2) ? 1 : 0);
    for (j = 0; j < 3; ++j) {
        *o++ = j < n ? en.y + 7 : 0xFF;
        *o++ = BT + (j + 1 == n ? 37 : 36);
        *o++ = fl;
        *o++ = en.dir > 0 ? en.x + 24 + j * 8 : en.x - j * 8;
    }
    for (r = 0; r < 3; ++r)
        for (c = 0; c < 4; ++c) {
            *o++ = hide || (r == 1 && c == 3 && n) ? 0xFF : en.y + r * 8 + yo;
            *o++ = r == 1 && c == 3 && open ? BT + 38 : t + r * 4 + c;
            *o++ = fl;
            *o++ = x + (en.dir > 0 ? c : 3 - c) * 8;
        }
}

static void spit(const struct phase *p)
{
    unsigned char k, n, v, sx = en.dir > 0 ? en.x + 24 : en.x;
    int d = (int)player_x + 4 - sx;
    if (d < 0) d = -d;
    for (n = 0; n < p->shots; ++n)
        for (k = 0; k < FB_MAX; ++k)
            if (!fb_x[k]) {            /* lob: flight time 14 * v + 27 frames at 1 px/frame: v = (distance - 20) / 14 aims at the player */
                v = d > 34 ? (d - 20) / 14 : 1;
                v += n * 2;
                fb_x[k] = sx; fb_y[k] = en.y - 8;
                fb_vx[k] = en.dir > 0 ? (signed char)p->fspd : -(signed char)p->fspd;
                fb_vy[k] = v > 8 ? -8 : -(signed char)v;
                break;
            }
}

void toad_ai(void)
{
    const struct phase *p = &bs->ph[boss_phase - 1];
    int d, nx;
    unsigned char k, t, x0;
    char c;

    if (intro || boss_fx) { scroll_x = 0; sprites(); return; }      /* frozen: only redraw (new look at a phase change) */
    boss_hide = 0;
    if (!(frame_count & 7))            /* slime gravity: the blobs arc (dungeon.c moves them) */
        for (k = 0; k < FB_MAX; ++k) if (fb_x[k] && fb_vy[k] < 7) ++fb_vy[k];
    if (iair == INIT) {
        ph = boss_phase; par = ch = shk = tlen = 0; lc = 0;
        for (k = 0; k < FB_MAX; ++k) { oam[O_FB + k * 4 + 1] = BT + 39; oam[O_FB + k * 4 + 2] = 1; }   /* slime tile, boss palette */
        iair = SIT; ai_t = 50;
    } else if (ph != boss_phase) { ph = boss_phase; par = 0; }
    switch (iair) {
    case SIT:                          /* face the player, wait, then the next action of the cycle */
        en.dir = (int)player_x + 8 >= (int)en.x + 16 ? 1 : -1;
        if (ai_t) { --ai_t; break; }
        lc = c = take();
        if (c == 'H') { iair = CROUCH; ai_t = ch ? 14 : p->wait; }
        else if (c == 'T') { iair = TTELE; ai_t = ch ? 15 : 25; }
        else { iair = STELE; ai_t = 20; }
        break;
    case CROUCH:                       /* crouches, then jumps to a spot beside the player (at most 108 px) */
        if (--ai_t) break;
        nx = en.dir > 0 ? (int)player_x + 8 - p->spd - 32 : (int)player_x + 8 + p->spd;
        if (nx < WALL) nx = WALL;
        if (nx > MAXX) nx = MAXX;
        d = nx - en.x;
        hd = d < 0 ? -1 : 1;
        if (d < 0) d = -d;
        if (d > 108) d = 108;
        hs = d / 36; hrem = d % 36; hacc = 0;   /* 36 horizontal steps: the flight takes 39 frames */
        ivy = -6; ig = 0; ai_t = 36; iair = HOP;
        break;
    case HOP:
        if (ai_t) {
            --ai_t;
            k = hs;
            if ((hacc += hrem) >= 36) { hacc -= 36; ++k; }
            nx = en.x + (hd < 0 ? -(int)k : (int)k);
            en.x = nx < WALL ? WALL : nx > MAXX ? MAXX : nx;
        }
        en.y += ivy;
        if (++ig == 3) { ig = 0; ++ivy; }
        if (ivy >= 0 && en.y >= GROUND) {
            en.y = GROUND; shk = 12;
            ch = boss_phase == 3 && next() == lc;
            iair = LAND; ai_t = ch ? 14 : LAND_T;
        }
        break;
    case LAND:                         /* stunned: sits still and blinks slowly */
        boss_hide = (frame_count & 16) ? 2 : 0;
        if (!--ai_t) { iair = SIT; ai_t = ch ? 6 : p->rate; }
        break;
    case TTELE:                        /* mouth open, flickers */
        boss_hide = (frame_count & 4) ? 2 : 0;
        if (--ai_t) break;
        iair = TONGUE; ai_t = 0;
        break;
    case TONGUE:                       /* out in 12 frames, held 20, back in 8; eats (hurt) whoever it touches */
        t = ai_t++;
        tlen = t < 4 ? 1 : t < 8 ? 2 : t < 28 ? 3 : t < 32 ? 2 : 1;
        if (t >= 36) {
            tlen = 0;
            ch = boss_phase == 3 && next() == lc;
            iair = SIT; ai_t = ch ? 8 : p->rate;
            break;
        }
        x0 = en.dir > 0 ? en.x + 24 : en.x - (tlen - 1) * 8;
        if (!invuln && overlap(player_x + 3, player_y + 2, 10, 14, x0, en.y + 8, tlen * 8, 8)) hurt(x0 + tlen * 4);
        break;
    case STELE:                        /* spit: flickers, then the blobs */
        boss_hide = (frame_count & 4) ? 2 : 0;
        if (--ai_t) break;
        spit(p);
        ch = boss_phase == 3 && next() == lc;
        iair = SIT; ai_t = ch ? 8 : p->rate;
        break;
    }
    if (shk) { --shk; scroll_x = (shk & 2) ? 2 : 0; }     /* landing shake: 2 px jitter every 2 frames */
    else scroll_x = 0;
    sprites();
}
