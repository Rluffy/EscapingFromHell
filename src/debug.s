; Test-visible variables at fixed addresses ($0300, segment DEBUG).
; Keep in sync with tests/*.lua and docs/TECH.md.
.export _frame_count, _game_state, _player_x, _player_y, _cam_x
.export _dungeons_cleared, _cur_dungeon
.export _hearts, _invuln, _on_ground, _sword_t, _vy, _en, _paused

.segment "DEBUG"
_frame_count:      .res 2   ; $0300
_game_state:       .res 1   ; $0302
_player_x:         .res 2   ; $0303 world x of the 16x16 sprite's top-left
_player_y:         .res 1   ; $0305 world y
_cam_x:            .res 2   ; $0306 camera x (world px of the left screen edge)
_dungeons_cleared: .res 2   ; $0308 bit n-1 = dungeon n cleared
_cur_dungeon:      .res 1   ; $030A 1..10 while in a dungeon, else 0
_hearts:           .res 1   ; $030B dungeon: hearts left (3 on entry)
_invuln:           .res 1   ; $030C dungeon: player invulnerability frames left
_on_ground:        .res 1   ; $030D dungeon: 1 = standing on floor/platform
_sword_t:          .res 1   ; $030E dungeon: sword swing frames left
_vy:               .res 1   ; $030F dungeon: vertical speed (signed, px/frame)
_en:               .res 7   ; $0310 enemy struct: x, y, w, h, hp, flash, dir (see src/nes.h)
_paused:           .res 1   ; $0317 dungeon: 1 = paused
