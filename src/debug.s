; Test-visible variables at fixed addresses ($0300, segment DEBUG).
; Keep in sync with tests/*.lua and docs/TECH.md.
.export _frame_count, _game_state, _player_x, _player_y, _cam_x
.export _dungeons_cleared, _cur_dungeon
.export _hearts, _invuln, _on_ground, _sword_t, _vy, _en, _paused
.export _boss_phase, _boss_dead, _intro, _fb_x, _fb_y, _boss_fx
.export _abilities, _dash_t, _dash_cd, _victory, _cur_bank, _boss_hide, _iair
.export _pf_x, _pf_y, _pf_cd, _mcx, _mcur, _tlen, _shield, _slow

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

_boss_phase:       .res 1   ; $0318 boss fight: phase 1..3 (0 = no boss, test dummy)
_boss_dead:        .res 1   ; $0319 boss fight: 1 = boss defeated
_intro:            .res 1   ; $031A boss fight: intro frames left (player and boss frozen)
_fb_x:             .res 3   ; $031B fireball x (0 = slot free)
_fb_y:             .res 3   ; $031E fireball y
_boss_fx:          .res 1   ; $0321 phase-change effect frames left (boss frozen and harmless)
_abilities:        .res 1   ; $0322 bit 0 Dash, 1 Double jump, 2 Fireball, 3 Shield, 4 Sword wave
_dash_t:           .res 1   ; $0323 dungeon: dash frames left (0 = not dashing)
_dash_cd:          .res 1   ; $0324 dungeon: dash cooldown frames left
_victory:          .res 1   ; $0325 dungeon: victory frames left (0 = fight running)
_cur_bank:        .res 1   ; $0326 PRG bank mapped at $8000 (13 = none after reset, 0 = Imp)
_boss_hide:       .res 1   ; $0327 boss: bit 0 untouchable (no hit, no contact damage), bit 1 not drawn
_iair:            .res 1   ; $0328 boss state (Ghost / Bone hound state machine)
_pf_x:            .res 1   ; $0329 player fireball x (0 = none)
_pf_y:            .res 1   ; $032A player fireball y
_pf_cd:           .res 1   ; $032B player fireball cooldown frames left
_mcx:            .res 3   ; $032C Mirror demon: copies' x (0 = none / popped)
_mcur:           .res 1   ; $032F Mirror demon: spot of the original (0 floor, 1/2 side platforms, 3 top)
_tlen:           .res 1   ; $0330 Giant toad: tongue segments out (0..3)
_shield:         .res 1   ; $0331 dungeon: 1 = the player holds the shield up (Down on the ground, with the ability)
_slow:           .res 1   ; $0332 dungeon: frames the player is webbed (Spider queen): half walk speed, no dash
