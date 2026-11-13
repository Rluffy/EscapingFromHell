; CHR-ROM (128 KB), layout table in docs/TECH.md "CHR-Layout". Every sheet is converted from assets/sprites/*.png by
; tools/png2chr.py (Makefile) and padded to its slot, so the offsets below are fixed (KB = 1 KB bank number).
.segment "CHARS"
    .incbin "build/tiles.chr"       ; KB 0-1: R0 background: overworld/arena tiles, font (tile ids 0..127)
    .incbin "build/anim_a.chr"      ; KB 2-3: R1 overworld animation frame A (tile ids 128..255)
    .incbin "build/anim_b.chr"      ; KB 4-5: R1 frame B
    .incbin "build/common.chr"      ; KB 6-7: R2 sprites: player, sword, hearts, shared projectiles (tile ids 0..63)
    .incbin "build/boss01.chr"      ; KB 8-11: boss of dungeon 1 (R3..R5), 4 KB per boss
    .incbin "build/boss02.chr"
    .incbin "build/boss03.chr"
    .incbin "build/boss04.chr"
    .incbin "build/boss05.chr"
    .incbin "build/boss06.chr"
    .incbin "build/boss07.chr"
    .incbin "build/boss08.chr"
    .incbin "build/boss09.chr"
    .incbin "build/boss10.chr"      ; KB 44-47
    .incbin "build/owdemon.chr"     ; KB 48-51: overworld demon figures + skull (R3..R5 = 48..50 in the overworld, tile ids 0x40..)
