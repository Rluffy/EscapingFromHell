/* Start menu and ending screen: plain text screens drawn with rendering off. Docs: docs/TECH.md "Startmenü und Ende (v0.8)". */
#pragma code-name("BANK10")
#pragma rodata-name("BANK10")
#include "nes.h"

#define END_LEN 240                    /* ending screen: 4 s, Start leaves after 1 s */

/* Menu entries. v0.9 appends CONTINUE / DELETE SAVE here and handles the new index in start_game() (main.c). */
static const char *const item[] = { "NORMAL", "CHEAT" };
#define NITEM 2
#define ITEM_ROW 14                    /* first entry; 2 tile rows apart */
#define ITEM_COL 13

/* Text (A-Z, spaces) on a nametable-0 row, rendering off; col 0 = centered. */
static void put_text(const char *s, unsigned char row, unsigned char col)
{
    unsigned char l = 0;
    unsigned int a;
    while (s[l]) ++l;
    if (!col) col = (32 - l) >> 1;
    a = 0x2000 + ((unsigned int)row << 5) + col;
    PPU_ADDR = a >> 8; PPU_ADDR = a;
    for (; *s; ++s) PPU_DATA = *s > ' ' ? ftile[*s - 'A'] : 0;
}

/* Background palettes 0..3 (white text on black); sprite palette 2 is the cursor heart. */
static const unsigned char pal[32] = {
    0x0F,0x06,0x16,0x30, 0x0F,0x06,0x16,0x30, 0x0F,0x06,0x16,0x30, 0x0F,0x06,0x16,0x30,
    0x0F,0x17,0x21,0x36, 0x0F,0x06,0x16,0x30, 0x0F,0x16,0x30,0x10, 0x0F,0x21,0x31,0x30
};

/* Blank text screen with the palette above, all sprites hidden; the caller adds text and calls screen_on. */
static void blank_screen(void)
{
    unsigned int i;
    screen_off();
    PPU_ADDR = 0x3F; PPU_ADDR = 0x00;
    for (i = 0; i < 32; ++i) PPU_DATA = pal[i];
    PPU_ADDR = 0x20; PPU_ADDR = 0x00;
    for (i = 0; i < 1024; ++i) PPU_DATA = 0;
    for (i = 0; i < 256; i += 4) oam[i] = 0xFF;
    scroll_x = 0;
}

void menu_enter(void)
{
    unsigned char i;
    blank_screen();
    put_text("ESCAPING", 6, 0);
    put_text("FROM HELL", 8, 0);
    for (i = 0; i < NITEM; ++i) put_text(item[i], ITEM_ROW + 2 * i, ITEM_COL);
    oam[1] = 14; oam[2] = 2; oam[3] = (ITEM_COL - 2) * 8;     /* cursor: heart */
    menu_sel = 0;
    game_state = ST_MENU;
    screen_on(0x88);
}

/* 1 = an entry was chosen (menu_sel). */
unsigned char menu_frame(void)
{
    if (PRESSED(PAD_UP)) { menu_sel = menu_sel ? menu_sel - 1 : NITEM - 1; sfx_play(SFX_MOVE); }
    if (PRESSED(PAD_DOWN | PAD_SELECT)) { menu_sel = menu_sel + 1 < NITEM ? menu_sel + 1 : 0; sfx_play(SFX_MOVE); }
    oam[0] = (ITEM_ROW + 2 * menu_sel) * 8 - 1;
    if (!PRESSED(PAD_A | PAD_START)) return 0;
    sfx_play(SFX_OK);
    return 1;
}

void end_enter(void)
{
    blank_screen();
    put_text("YOU ESCAPED", 12, 0);
    put_text("PRESS START", 18, 0);
    end_t = END_LEN;
    sfx_play(SFX_END);
    game_state = ST_END;
    screen_on(0x88);
}

/* 1 = back to the overworld. */
unsigned char end_frame(void)
{
    return !--end_t || (end_t < END_LEN - 60 && PRESSED(PAD_START));
}
