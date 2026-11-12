; CHR-ROM: 128 KB. Tile 0 blank, tile 1 solid colour 1. A later package replaces this
; with .incbin "../build/<name>.chr" (output of tools/png2chr.py).
.segment "CHARS"
    .res 16, $00
    .res 8, $FF
    .res 8, $00
