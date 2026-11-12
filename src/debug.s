; Test-visible variables at fixed addresses ($0300, segment DEBUG).
; Keep in sync with tests/*.lua and docs/TECH.md.
.export _frame_count, _game_state, _player_x, _player_y, _cam_x
.export _dungeons_cleared, _cur_dungeon, _debug_bytes

.segment "DEBUG"
_frame_count:      .res 2   ; $0300
_game_state:       .res 1   ; $0302
_player_x:         .res 2   ; $0303 world x of the 16x16 sprite's top-left
_player_y:         .res 1   ; $0305 world y
_cam_x:            .res 2   ; $0306 camera x (world px of the left screen edge)
_dungeons_cleared: .res 2   ; $0308 bit n-1 = dungeon n cleared
_cur_dungeon:      .res 1   ; $030A 1..10 while in a dungeon, else 0
_debug_bytes:      .res 5   ; $030B-$030F free for later tests
