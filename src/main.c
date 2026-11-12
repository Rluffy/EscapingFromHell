#include "nes.h"

void main(void)
{
    /* rendering is still off: write universal background colour (red) */
    PPU_ADDR = 0x3F;
    PPU_ADDR = 0x00;
    PPU_DATA = 0x16;
    PPU_ADDR = 0;
    PPU_ADDR = 0;
    PPU_SCROLL = 0;
    PPU_SCROLL = 0;

    PPU_CTRL = 0x80;    /* NMI on */
    PPU_MASK = 0x1E;    /* show background + sprites */
    game_state = 1;

    for (;;)
        wait_vblank();
}
