/* Boss framework shared by dungeon.c (fixed bank) and the per-boss files in switchable banks.
   Docs: docs/TECH.md "PRG-Banking". Banked code may call fixed-bank code and its own bank only. */
#ifndef BOSS_H
#define BOSS_H

#define FLOOR_Y 192                    /* top of the floor = feet position of a standing player */
#define WALL    16                     /* wall width in px */
#define FB_MAX  3
#define BT 0x40                        /* tile id of tile 0 of a boss sheet (R3 = $1400; docs/TECH.md "CHR-Layout"): boss tiles are BT + n */
#define WEB_TILE (BT + 19)             /* fireball sprite tile of a web ball (spider sheet): slows the player instead of costing a heart */
#define SHOCK    17                    /* shockwave tile (common sheet, shared by oni and lord) */

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
    unsigned char w, h, y0;            /* sprite width (16..32 px), height (16..32 px) and start y */
    void (*ai)(void);                  /* runs every frame; in bank `bank` */
    const struct phase *ph;            /* 3 phases; in bank `bank` */
};

extern const struct boss *bs;          /* current boss */
extern signed char   ivx, ivy, fb_vx[3], fb_vy[3];
extern unsigned char ig, iair, ai_t, rng, ftick, facing;   /* ftick: frame counter of the fight (all boss timing uses it, not frame_count); rng is seeded per dungeon in arena_reset; iair = boss state, debug byte $0328; facing: player, 0 right / 1 left */
extern unsigned      fb_t;

unsigned char overlap(unsigned char ax, unsigned char ay, unsigned char aw, unsigned char ah,
                      unsigned char bx, unsigned char by, unsigned char bw, unsigned char bh);   /* math.s */
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
void winged_ai(void);
extern const struct phase winged_ph[3];
void mirror_ai(void);
extern const struct phase mirror_ph[3];
void toad_ai(void);
extern const struct phase toad_ph[3];
void spider_ai(void);
extern const struct phase spider_ph[3];
void oni_ai(void);
extern const struct phase oni_ph[3];
void lord_ai(void);
extern const struct phase lord_ph[3];

#endif
