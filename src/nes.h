#ifndef NES_H
#define NES_H

#define PPU_CTRL   (*(volatile unsigned char*)0x2000)
#define PPU_MASK   (*(volatile unsigned char*)0x2001)
#define PPU_STATUS (*(volatile unsigned char*)0x2002)
#define PPU_SCROLL (*(volatile unsigned char*)0x2005)
#define PPU_ADDR   (*(volatile unsigned char*)0x2006)
#define PPU_DATA   (*(volatile unsigned char*)0x2007)
#define JOY1       (*(volatile unsigned char*)0x4016)

#define ST_MENU 1                           /* game_state values the menu/ending code sets (menu.c, main.c) */
#define ST_END  4

#define BANK_NONE 13                        /* empty PRG bank, mapped only until main() maps BANK_UI */
#define BANK_UI   10                        /* menu.c + overworld map: mapped in menu, overworld and ending; a dungeon maps its boss bank */
void __fastcall__ bank_set(unsigned char b);        /* crt0.s: map PRG bank b at $8000, remember it in cur_bank */
void __fastcall__ chr_set(unsigned char r, unsigned char b);   /* crt0.s: MMC3 CHR register r (0..5) = 1 KB bank number b; main loop only */

#define PAD_A      0x80
#define PAD_B      0x40
#define PAD_SELECT 0x20
#define PAD_START  0x10
#define PAD_UP     0x08
#define PAD_DOWN   0x04
#define PAD_LEFT   0x02
#define PAD_RIGHT  0x01

/* Test-visible RAM, fixed at $0300 (see src/debug.s, cfg/mmc3.cfg). */
extern volatile unsigned int  frame_count;  /* $0300/$0301, +1 per NMI */
extern volatile unsigned char game_state;   /* $0302, 0 = boot, 1 = start menu, 2 = overworld, 3 = dungeon arena, 4 = ending */
extern unsigned int  player_x;              /* $0303/$0304 world x (top-left of the 16x16 sprite) */
extern unsigned char player_y;              /* $0305 world y */
extern unsigned int  cam_x;                 /* $0306/$0307 camera x, 0..768 */
extern unsigned int  dungeons_cleared;      /* $0308/$0309 bit n-1 = dungeon n cleared */
extern unsigned char cur_dungeon;           /* $030A 1..10 in a dungeon, else 0 */

/* Dungeon state, $030B..$0321 (src/dungeon.c). Tests may write all of it. */
extern unsigned char hearts, invuln, on_ground, sword_t;   /* $030B..$030E */
extern signed char   vy;                    /* $030F */
struct enemy { unsigned char x, y, w, h, hp, flash; signed char dir; };   /* generic enemy, package 2: boss table */
extern struct enemy en;                     /* $0310..$0316 */
extern unsigned char paused;                /* $0317 */
extern unsigned char boss_phase, boss_dead, intro;         /* $0318..$031A, boss fight (en.hp = boss hp) */
extern unsigned char fb_x[3], fb_y[3];      /* $031B..$0320 fireballs, x = 0 = free */
extern unsigned char boss_fx;               /* $0321 */
extern unsigned char abilities;             /* $0322 bit 0 Dash, 1 Double jump, 2 Fireball, 3 Shield, 4 Sword wave */
extern unsigned char dash_t, dash_cd, victory;   /* $0323..$0325 */
extern unsigned char cur_bank;               /* $0326 PRG bank at $8000 (set by bank_set) */
extern unsigned char boss_hide;              /* $0327 bit 0 = boss untouchable (no hit, no contact), bit 1 = not drawn */
#define AB_DASH 1
#define AB_DJUMP 2
#define AB_FIRE 4
#define AB_SHIELD 8
#define AB_WAVE 16
extern unsigned char shield;                 /* $0331 1 = shield raised (Down held on the ground, with AB_SHIELD) */
extern unsigned char slow;                   /* $0332 frames the player is webbed (walks 1 px/frame, no dash) */
extern unsigned char ending_seen;            /* $0333 1 = the ending was seen (saved: bit 7 of $6004) */
extern unsigned char cheat;                  /* $0334 1 = cheat mode: all gates open, no heart loss, no saving */
extern unsigned char menu_sel;               /* $0335 start menu cursor (0 NORMAL, 1 CHEAT) */
extern unsigned char end_t;                  /* $0336 ending screen frames left */
extern unsigned char boss_chr;               /* $0337 CHR bank in R3 (R4, R5 = +1, +2): sheet of the current boss */
extern unsigned char anim_bank;              /* $0338 CHR bank in R1: overworld animation frame (CHR_ANIM_A / CHR_ANIM_B) */
#define CHR_ANIM_A 2                         /* CHR layout: docs/TECH.md "CHR-Layout" */
#define CHR_ANIM_B 4
#define CHR_BOSS(n) (8 + 4 * ((n) - 1))      /* first 1 KB bank of the boss of dungeon n */
extern unsigned char sfx_last;               /* $0339 id of the last effect that started (0 = none) */
extern unsigned char sfx_id[3];              /* $033A..$033C effect playing on pulse 1 / pulse 2 / noise (0 = idle) */
/* Sound effect ids: order of the tables in src/sfx.s (docs/TECH.md "Soundeffekte (v0.9)"). */
#define SFX_JUMP 1
#define SFX_DJUMP 2
#define SFX_SWORD 3
#define SFX_HURT 4
#define SFX_BHIT 5
#define SFX_PHASE 6
#define SFX_BDEATH 7
#define SFX_VICTORY 8
#define SFX_DASH 9
#define SFX_FIRE 10
#define SFX_WAVE 11
#define SFX_BLOCK 12
#define SFX_SPIT 13
#define SFX_THUMP 14
#define SFX_MOVE 15
#define SFX_OK 16
#define SFX_GATE 17
#define SFX_END 18
void __fastcall__ sfx_play(unsigned char id);   /* sfx.s: start an effect (ignored while a higher-priority one plays on its channel) */
void sfx_update(void);                      /* sfx.s: once per frame at the end of the main-loop iteration (not in the vblank start: PPU writes need it) */
extern unsigned char pf_x, pf_y, pf_cd;      /* $0329..$032B player fireball: x (0 = none), y, cooldown frames left */

extern const unsigned char ftile[26];       /* dungeon.c: BG tile of the letter A..Z (0 = none) */
void menu_enter(void);                      /* menu.c: start menu / ending screen (rendering off, then on) */
unsigned char menu_frame(void);             /* 1 = entry chosen */
void end_enter(void);
unsigned char end_frame(void);              /* 1 = back to the overworld */

/* Shared with dungeon.c (main.c). */
extern unsigned char pad, pad_prev;
#define PRESSED(b) (pad & ~pad_prev & (b))
void screen_off(void);
void screen_on(unsigned char ctrl);
void save_game(void);                       /* main.c: write dungeons_cleared + abilities to PRG-RAM $6000 */
void dungeon_enter(void);                   /* cur_dungeon = 1..10 */
unsigned char dungeon_frame(void);          /* 1 = leave the dungeon (Start+Select, or victory done) */

/* Background streaming buffers, consumed by NMI / ppu_flush (src/crt0.s). */
extern unsigned char colbuf[60];
extern unsigned char attrbuf[8];
extern unsigned char col_pending;
extern unsigned int  col_addr, attr_addr;
extern unsigned char ppu_ctrl, scroll_x;
extern unsigned char oam[256];

/* Write colbuf/attrbuf to the PPU (rendering off or vblank only). */
void ppu_flush(void);

/* Block until the next NMI. */
void wait_vblank(void);

#endif
