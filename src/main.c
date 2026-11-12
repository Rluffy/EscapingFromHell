#include "nes.h"

#define ST_OVERWORLD 2
#define ST_DUNGEON   3
#define CAM_MAX      768   /* 1024 px map - 256 px screen */

extern const unsigned char overworld_map[];   /* 64 columns x 16 ids, see tools/mapconv.py */

/* Per map cell id 0..41: bg tile and bg palette number. Gates (ids 16..25) store the locked
   tile 7; id_tile() swaps in 8 when the dungeon is open. Doors (32..41) are tile 6. */
#define G 7, 7, 7, 7, 7, 7, 7, 7, 7, 7
#define D 6, 6, 6, 6, 6, 6, 6, 6, 6, 6
static const unsigned char cell_tile[42] = { 0,1,2,3,4,5,6,7,8,9, 0,0,0,0,0,0, G, 0,0,0,0,0,0, D };
#undef G
#undef D
static const unsigned char cell_pal[42]  = { 0,0,1,2,1,3,0,3,3,3, 0,0,0,0,0,0, 3,3,3,3,3,3,3,3,3,3, 0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0 };

static const unsigned char pal_overworld[32] = {
    0x0F,0x17,0x27,0x37,  0x0F,0x06,0x16,0x26,  0x0F,0x06,0x16,0x27,  0x0F,0x16,0x26,0x38,
    0x0F,0x17,0x21,0x36,  0x0F,0x17,0x21,0x36,  0x0F,0x17,0x21,0x36,  0x0F,0x17,0x21,0x36
};
static const unsigned char pal_dungeon[32] = {
    0x02,0x02,0x02,0x30,  0x02,0x02,0x02,0x30,  0x02,0x02,0x02,0x30,  0x02,0x02,0x02,0x30,
    0x02,0x02,0x02,0x30,  0x02,0x02,0x02,0x30,  0x02,0x02,0x02,0x30,  0x02,0x02,0x02,0x30
};

static unsigned char pad, pad_prev;
static unsigned char drawn_col;          /* leftmost streamed metatile column; 255 = nothing drawn */
static unsigned int  drawn_mask;         /* dungeons_cleared the gate tiles were drawn with */

/* Dungeon n0 (0-based) is open if it is the first or the previous one is cleared. */
static unsigned char is_open(unsigned char n0)
{
    return n0 == 0 || (dungeons_cleared & (1u << (n0 - 1)));
}

/* Map cell id: 0..15 tile, 16..25 gate, 32..41 door. shortcut: no bounds check,
   the map border is solid so the player never leaves it. */
static unsigned char cell_id(unsigned int x, unsigned char y)
{
    return overworld_map[(((x >> 4) << 4) | (y >> 4)) & 0x3FF];
}

static unsigned char solid(unsigned char id)
{
    if (id < 16) return (0x023C >> id) & 1;       /* rock, lava, wall, roof, block */
    if (id < 32) return !is_open(id - 16);        /* gate */
    return 0;                                     /* door */
}

static unsigned char blocked(unsigned int x, unsigned char y)
{
    /* feet box: 8 wide, 6 tall inside the 16x16 sprite */
    return solid(cell_id(x + 4, y + 10)) || solid(cell_id(x + 11, y + 10)) ||
           solid(cell_id(x + 4, y + 15)) || solid(cell_id(x + 11, y + 15));
}

static unsigned char id_tile(unsigned char id)
{
    unsigned char t = cell_tile[id];
    return (id >= 16 && id < 32 && is_open(id - 16)) ? 8 : t;
}

/* Prepare metatile column c (2 tile columns + attributes) for the PPU. */
static void build_col(unsigned char c)
{
    const unsigned char *m = overworld_map + ((unsigned int)c << 4);
    const unsigned char *e = overworld_map + ((unsigned int)(c & 0xFE) << 4);
    const unsigned char *o = e + 16;
    unsigned char r, t, nt = (c >> 4) & 1;
    unsigned char *p = colbuf;

    for (r = 0; r < 15; ++r) {
        t = id_tile(m[r]);
        p[0] = p[1] = p[30] = p[31] = t;
        p += 2;
    }
    for (r = 0; r < 16; r += 2)
        attrbuf[r >> 1] = cell_pal[e[r]] | (cell_pal[o[r]] << 2) |
                          (cell_pal[e[r + 1]] << 4) | (cell_pal[o[r + 1]] << 6);
    col_addr  = 0x2000 + ((unsigned int)nt << 10) + ((c << 1) & 31);
    attr_addr = 0x23C0 + ((unsigned int)nt << 10) + ((c >> 1) & 7);
}

static void screen_off(void)
{
    wait_vblank();
    PPU_MASK = 0;
    PPU_CTRL = 0;                     /* NMI off while main writes VRAM directly */
}

static void screen_on(unsigned char ctrl)
{
    ppu_ctrl = ctrl;
    col_pending = 0;
    while (!(PPU_STATUS & 0x80)) ;    /* NMI is off: poll for vblank */
    PPU_CTRL = ppu_ctrl;
    PPU_MASK = 0x1E;
}

static void set_palette(const unsigned char *p)
{
    unsigned char i;
    PPU_ADDR = 0x3F;
    PPU_ADDR = 0x00;
    for (i = 0; i < 32; ++i) PPU_DATA = p[i];
}

/* Camera follows the player, clamped to the map. */
static void update_camera(void)
{
    cam_x = player_x < 120 ? 0 : player_x - 120;
    if (cam_x > CAM_MAX) cam_x = CAM_MAX;
    scroll_x = cam_x & 0xFF;
    ppu_ctrl = 0x88 | ((cam_x >> 8) & 1);
}

/* Redraw every visible column with rendering off (entering the overworld, gate changes, teleports). */
static void redraw_overworld(void)
{
    unsigned char c, last;
    screen_off();
    set_palette(pal_overworld);
    update_camera();
    drawn_col = cam_x >> 4;
    last = drawn_col + 16;
    for (c = drawn_col; c <= last && c < 64; ++c) {
        build_col(c);
        ppu_flush();
    }
    drawn_mask = dungeons_cleared;
    screen_on(ppu_ctrl);
}

static void enter_dungeon(void)
{
    unsigned char i, n = cur_dungeon;
    static const unsigned char name[8] = { 26, 27, 28, 29, 30, 31, 28, 0 };  /* "DUNGEON " */

    screen_off();
    set_palette(pal_dungeon);
    PPU_ADDR = 0x20;
    PPU_ADDR = 0x00;
    for (i = 0; i < 4; ++i) {          /* clear nametable 0 (1024 bytes) */
        unsigned int k;
        for (k = 0; k < 256; ++k) PPU_DATA = 0;
    }
    PPU_ADDR = 0x21;
    PPU_ADDR = 0xAB;
    for (i = 0; i < 8; ++i) PPU_DATA = name[i];
    if (n >= 10) { PPU_DATA = 17; n -= 10; }   /* tile 17 = "1" */
    PPU_DATA = 16 + n;
    for (i = 0; i < 4; ++i) oam[i * 4] = 0xFF; /* hide the player */
    scroll_x = 0;
    game_state = ST_DUNGEON;
    screen_on(0x88);
}

static void leave_dungeon(void)
{
    unsigned char n = cur_dungeon;
    /* temple grid: door column 6n-3, door row 5 (odd n) / 3 (even n) */
    player_x = (unsigned int)(6 * n - 3) << 4;
    player_y = (n & 1) ? 80 : 48;
    cur_dungeon = 0;
    game_state = ST_OVERWORLD;
    redraw_overworld();
}

static void read_pad(void)
{
    unsigned char i, b = 0;
    pad_prev = pad;
    JOY1 = 1;
    JOY1 = 0;
    for (i = 0; i < 8; ++i) b = (b << 1) | (JOY1 & 1);
    pad = b;
}

static void overworld_frame(void)
{
    int dx = 0, dy = 0;
    unsigned char id, last, nc;

    if (pad & PAD_RIGHT) dx = 2;
    if (pad & PAD_LEFT)  dx = -2;
    if (pad & PAD_DOWN)  dy = 2;
    if (pad & PAD_UP)    dy = -2;
    if (dx && !blocked(player_x + dx, player_y)) player_x += dx;
    if (dy && !blocked(player_x, player_y + dy)) player_y += dy;

    if ((pad & PAD_A) && !(pad_prev & PAD_A)) {
        id = cell_id(player_x + 8, player_y + 12);
        if (id >= 32 && is_open(id - 32)) {
            cur_dungeon = id - 31;
            enter_dungeon();
            return;
        }
    }

    update_camera();
    nc = cam_x >> 4;
    if (dungeons_cleared != drawn_mask || (unsigned char)(nc - drawn_col + 1) > 2) {
        redraw_overworld();            /* gate state changed or camera jumped (teleport) */
    } else if (nc != drawn_col) {      /* stream the column entering on the right / left */
        last = nc > drawn_col ? nc + 16 : nc;
        drawn_col = nc;
        if (last < 64) {
            build_col(last);
            col_pending = 1;
        }
    }
    oam[0] = oam[4] = player_y - 1;
    oam[8] = oam[12] = player_y + 7;
    oam[3] = oam[11] = player_x - cam_x;
    oam[7] = oam[15] = player_x - cam_x + 8;
}

void main(void)
{
    unsigned char i;
    for (i = 0; i < 4; ++i) {
        oam[i * 4 + 1] = i;            /* player tiles 0..3, palette 0 */
        oam[i * 4 + 2] = 0;
    }
    player_x = 32;
    player_y = 144;
    game_state = ST_OVERWORLD;
    ppu_ctrl = 0x88;
    PPU_CTRL = 0x88;                   /* NMI on, so screen_off can wait for vblank */
    redraw_overworld();

    for (;;) {
        wait_vblank();
        read_pad();
        if (game_state == ST_OVERWORLD) {
            overworld_frame();
        } else if (pad & (PAD_B | PAD_START)) {
            leave_dungeon();
        }
    }
}
