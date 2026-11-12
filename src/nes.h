#ifndef NES_H
#define NES_H

#define PPU_CTRL   (*(volatile unsigned char*)0x2000)
#define PPU_MASK   (*(volatile unsigned char*)0x2001)
#define PPU_STATUS (*(volatile unsigned char*)0x2002)
#define PPU_SCROLL (*(volatile unsigned char*)0x2005)
#define PPU_ADDR   (*(volatile unsigned char*)0x2006)
#define PPU_DATA   (*(volatile unsigned char*)0x2007)
#define JOY1       (*(volatile unsigned char*)0x4016)

#define PAD_A      0x80
#define PAD_B      0x40
#define PAD_START  0x10
#define PAD_UP     0x08
#define PAD_DOWN   0x04
#define PAD_LEFT   0x02
#define PAD_RIGHT  0x01

/* Test-visible RAM, fixed at $0300 (see src/debug.s, cfg/mmc3.cfg). */
extern volatile unsigned int  frame_count;  /* $0300/$0301, +1 per NMI */
extern volatile unsigned char game_state;   /* $0302, 0 = boot, 2 = overworld, 3 = dungeon placeholder */
extern unsigned int  player_x;              /* $0303/$0304 world x (top-left of the 16x16 sprite) */
extern unsigned char player_y;              /* $0305 world y */
extern unsigned int  cam_x;                 /* $0306/$0307 camera x, 0..768 */
extern unsigned int  dungeons_cleared;      /* $0308/$0309 bit n-1 = dungeon n cleared */
extern unsigned char cur_dungeon;           /* $030A 1..10 in a dungeon, else 0 */

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
