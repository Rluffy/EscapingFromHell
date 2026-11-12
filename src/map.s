; Overworld map: 64 columns x 16 bytes, see tools/mapconv.py.
.export _overworld_map
.segment "RODATA"
_overworld_map: .incbin "build/overworld.bin"
