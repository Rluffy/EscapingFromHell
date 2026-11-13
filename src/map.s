; Overworld map: 64 columns x 16 bytes, see tools/mapconv.py.
.export _overworld_map
.segment "BANK10"        ; UI bank: only readable while it is mapped (not in a dungeon)
_overworld_map: .incbin "build/overworld.bin"
