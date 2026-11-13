; APU sound effects (no music): 3 channels (0 pulse 1, 1 pulse 2, 2 noise), one effect per channel at a time,
; a new effect replaces the playing one on its channel if its priority is >= the playing one's.
; sfx_play(id) is __fastcall__ (A = id, 1..18), sfx_update() runs once per frame at the end of the main-loop iteration (never in NMI, never in the vblank start).
; Effect ids = order of the tables below = SFX_* in src/nes.h. Docs: docs/TECH.md "Soundeffekte (v0.9)".
.importzp ptr1, tmp1, tmp2
.import _sfx_last, _sfx_id
.export _sfx_play, _sfx_update

.segment "BSS"
sfx_pri: .res 3            ; priority of the playing effect (0 = channel idle)
sfx_t:   .res 3            ; frames left in the current step
sfx_pl:  .res 3            ; pointer to the next step
sfx_ph:  .res 3

.segment "CODE"
; Step = 5 bytes: frames, then the channel's 4 APU registers; a 0 frame count ends the effect.
; Pulse regs $4000+4n: duty/halt/const-volume/volume, sweep, period lo, period hi. Noise regs $400C..: volume, -, mode/period, -.
; Length counters are halted (bit 5), so a step sounds until the next one; the end writes volume 0.
.macro P dur, duty, vol, sweep, per
    .byte dur, (duty << 6) | $30 | vol, sweep, <(per), >(per)
.endmacro
.macro N dur, vol, mode
    .byte dur, $30 | vol, 0, mode, 0
.endmacro

; id 1 jump (pulse 1, rising slide)
fx_jump:  P 8, 2, 6, $8C, 400
          .byte 0
fx_djump: P 6, 1, 6, $8B, 260
          .byte 0
fx_sword: N 2, 8, $05
          N 2, 6, $04
          N 2, 3, $03
          .byte 0
fx_hurt:  P 3, 2, 9, 0, 200
          P 3, 2, 8, 0, 260
          P 3, 2, 7, 0, 340
          P 3, 2, 5, 0, 440
          P 3, 2, 3, 0, 560
          .byte 0
fx_bhit:  N 2, 10, $04
          N 3, 8, $06
          N 3, 5, $08
          N 3, 2, $0A
          .byte 0
fx_phase: P 5, 1, 8, 0, 426
          P 5, 1, 8, 0, 570
          P 5, 1, 8, 0, 677
          P 6, 1, 6, 0, 853
          P 4, 1, 3, 0, 853
          .byte 0
fx_bdeath: N 4, 10, $02
          N 4, 9, $05
          N 4, 8, $07
          N 6, 6, $09
          N 6, 4, $0B
          N 8, 2, $0D
          .byte 0
fx_victory: P 4, 2, 7, 0, 213
          P 4, 2, 7, 0, 169
          P 4, 2, 7, 0, 142
          P 4, 2, 7, 0, 106
          P 8, 2, 7, 0, 106
          P 6, 2, 5, 0, 106
          P 6, 2, 3, 0, 106
          .byte 0
fx_dash:  N 3, 7, $02
          N 3, 6, $04
          N 3, 4, $06
          N 3, 2, $08
          .byte 0
fx_fire:  P 3, 1, 7, 0, 150
          P 3, 1, 6, 0, 190
          P 3, 1, 5, 0, 240
          P 3, 1, 3, 0, 300
          .byte 0
fx_wave:  P 3, 0, 5, 0, 100
          P 3, 0, 5, 0, 80
          P 3, 0, 4, 0, 64
          P 3, 0, 2, 0, 50
          .byte 0
fx_block: N 2, 9, $83
          N 3, 5, $83
          N 3, 2, $84
          .byte 0
fx_spit:  P 3, 1, 3, 0, 200
          P 3, 1, 3, 0, 260
          P 3, 1, 2, 0, 340
          .byte 0
fx_thump: N 3, 10, $0E
          N 4, 8, $0F
          N 5, 5, $0F
          N 5, 2, $0F
          .byte 0
fx_move:  P 3, 2, 6, 0, 126
          .byte 0
fx_ok:    P 3, 2, 7, 0, 169
          P 5, 2, 7, 0, 106
          .byte 0
fx_gate:  P 4, 2, 6, 0, 426
          P 4, 2, 6, 0, 338
          P 4, 2, 6, 0, 285
          P 4, 2, 6, 0, 213
          P 8, 2, 6, 0, 213
          P 6, 2, 4, 0, 213
          .byte 0
fx_end:   P 6, 2, 7, 0, 213
          P 6, 2, 7, 0, 169
          P 6, 2, 7, 0, 142
          P 6, 2, 7, 0, 106
          P 6, 2, 7, 0, 84
          P 6, 2, 7, 0, 70
          P 8, 2, 7, 0, 70
          P 8, 2, 5, 0, 70
          P 8, 2, 3, 0, 70
          .byte 0

.macro FX ch, pri
    .byte (pri << 2) | ch
.endmacro
fx_cp:    FX 0,1          ; 1 jump
          FX 0,1          ; 2 double jump
          FX 2,1          ; 3 sword
          FX 0,3          ; 4 player hurt
          FX 2,2          ; 5 boss hit
          FX 1,3          ; 6 phase change
          FX 2,4          ; 7 boss death
          FX 1,4          ; 8 victory
          FX 2,2          ; 9 dash
          FX 0,2          ; 10 player fireball
          FX 0,2          ; 11 sword wave
          FX 2,2          ; 12 shield block
          FX 1,1          ; 13 boss spit
          FX 2,2          ; 14 thump
          FX 0,1          ; 15 menu move
          FX 0,2          ; 16 menu confirm
          FX 1,2          ; 17 gate / dungeon enter
          FX 1,4          ; 18 ending
fx_lo:    .lobytes fx_jump, fx_djump, fx_sword, fx_hurt, fx_bhit, fx_phase, fx_bdeath, fx_victory, fx_dash, fx_fire, fx_wave, fx_block, fx_spit, fx_thump, fx_move, fx_ok, fx_gate, fx_end
fx_hi:    .hibytes fx_jump, fx_djump, fx_sword, fx_hurt, fx_bhit, fx_phase, fx_bdeath, fx_victory, fx_dash, fx_fire, fx_wave, fx_block, fx_spit, fx_thump, fx_move, fx_ok, fx_gate, fx_end
ch_base:  .byte 0, 4, 12  ; offset of the channel's registers from $4000

; void sfx_play(unsigned char id): start effect id unless a higher-priority one plays on its channel.
_sfx_play:
    tax
    lda fx_cp-1,x
    sta tmp1
    and #3
    tay                 ; Y = channel
    lda tmp1
    and #$FC
    cmp sfx_pri,y
    bcc @done           ; weaker than what plays: ignored
    sta sfx_pri,y
    stx _sfx_last
    txa
    sta _sfx_id,y
    lda fx_lo-1,x
    sta sfx_pl,y
    lda fx_hi-1,x
    sta sfx_ph,y
    lda #1
    sta sfx_t,y         ; the next sfx_update starts the first step
@done:
    rts

; void sfx_update(void): advance every playing effect by one frame.
_sfx_update:
    lda #2
    sta tmp2
@ch:
    ldx tmp2
    lda _sfx_id,x
    beq @next
    dec sfx_t,x
    bne @next
    lda sfx_pl,x
    sta ptr1
    lda sfx_ph,x
    sta ptr1+1
    ldy #0
    lda (ptr1),y
    beq @end
    sta sfx_t,x
    lda ch_base,x
    tax                 ; X = register offset, the channel stays in tmp2
@w: iny
    lda (ptr1),y
    sta $4000,x
    inx
    cpy #4
    bne @w
    ldx tmp2
    lda sfx_pl,x
    clc
    adc #5
    sta sfx_pl,x
    bcc @next
    inc sfx_ph,x
    bcs @next           ; (always)
@end:
    lda ch_base,x
    tay
    lda #$30            ; volume 0
    sta $4000,y
    lda #0
    sta _sfx_id,x
    sta sfx_pri,x
@next:
    dec tmp2
    bpl @ch
    rts
