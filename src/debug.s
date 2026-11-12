; Test-visible variables at fixed addresses ($0300, segment DEBUG).
; Keep in sync with tests/*.lua and docs/TECH.md.
.export _frame_count, _game_state, _debug_bytes

.segment "DEBUG"
_frame_count: .res 2    ; $0300
_game_state:  .res 1    ; $0302
_debug_bytes: .res 13   ; $0303-$030F free for later tests
