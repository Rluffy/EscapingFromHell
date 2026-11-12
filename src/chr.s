; CHR-ROM (128 KB): pattern table 0 ($0000) = background tiles, pattern table 1 ($1000) = sprites.
; Both are converted from assets/sprites/*.png by tools/png2chr.py (Makefile), padded to 4 KB.
.segment "CHARS"
    .incbin "build/tiles.chr"
    .incbin "build/player.chr"
