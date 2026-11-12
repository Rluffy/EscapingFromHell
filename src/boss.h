/* Boss framework shared by dungeon.c (fixed bank) and the per-boss files in switchable banks.
   Docs: docs/TECH.md "PRG-Banking". Banked code may call fixed-bank code and its own bank only. */
#ifndef BOSS_H
#define BOSS_H

#define FLOOR_Y 192                    /* top of the floor = feet position of a standing player */
#define WALL    16                     /* wall width in px */
#define FB_MAX  3

struct phase {
    unsigned char tile;                /* first of 4 sprite tiles (TL, TR, BL, BR) */
    unsigned char spd, wait;           /* hop speed px/frame, frames standing between hops */
    unsigned rate;                     /* frames between spits (16 bit: up to 300) */
    unsigned char shots, fspd;         /* fireballs per spit, fireball px/frame */
    unsigned char pal[3];              /* sprite palette 1 */
};
struct boss {
    const char *name;                  /* letters must exist in ftile[] */
    unsigned char hp;
    unsigned char bank;                /* PRG bank at $8000 holding ai and ph */
    unsigned char w, h, y0;            /* sprite width (16 or 24 px), height (16 or 24 px) and start y */
    void (*ai)(void);                  /* runs every frame; in bank `bank` */
    const struct phase *ph;            /* 3 phases; in bank `bank` */
};

extern const struct boss *bs;          /* current boss, 0 = test dummy */
extern signed char   ivx, ivy, fb_vx[3], fb_vy[3];
extern unsigned char ig, iair, ai_t, rng;   /* iair = boss state, debug byte $0328 */
extern unsigned      fb_t;

void __fastcall__ bank_set(unsigned char b);        /* crt0.s: map PRG bank b at $8000, remember it in cur_bank */

unsigned char overlap(unsigned char ax, unsigned char ay, unsigned char aw, unsigned char ah,
                      unsigned char bx, unsigned char by, unsigned char bw, unsigned char bh);   /* dungeon.c */
void hurt(unsigned char sx);                        /* dungeon.c: player hit by something at x = sx */

/* One line per boss: its behavior function and phase data (defined in src/<boss>.c, banked). */
void imp_ai(void);
extern const struct phase imp_ph[3];
void ghost_ai(void);
extern const struct phase ghost_ph[3];
void hound_ai(void);
extern const struct phase hound_ph[3];
void snake_ai(void);
extern const struct phase snake_ph[3];

#endif
