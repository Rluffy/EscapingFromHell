#ifndef NES_H
#define NES_H

#define PPU_CTRL   (*(volatile unsigned char*)0x2000)
#define PPU_MASK   (*(volatile unsigned char*)0x2001)
#define PPU_STATUS (*(volatile unsigned char*)0x2002)
#define PPU_SCROLL (*(volatile unsigned char*)0x2005)
#define PPU_ADDR   (*(volatile unsigned char*)0x2006)
#define PPU_DATA   (*(volatile unsigned char*)0x2007)

/* Test-visible RAM, fixed at $0300 (see src/debug.s, cfg/mmc3.cfg). */
extern volatile unsigned int  frame_count;  /* $0300/$0301, +1 per NMI */
extern volatile unsigned char game_state;   /* $0302, 0 = boot, 1 = hello ROM running */

/* Block until the next NMI. */
void wait_vblank(void);

#endif
