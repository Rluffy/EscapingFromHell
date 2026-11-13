; Music engine, lives in PRG bank 11 which is mapped at $A000 (MMC3 R7) for good (crt0.s sets it once; bank_set only touches R6).
; 4 channels: 0 pulse 1, 1 pulse 2, 2 noise (drums), 3 triangle (bass). Sound effects own pulse 1/2/noise (src/sfx.s): while
; sfx_id[ch] is set the music leaves that channel alone but keeps its timeline, and rewrites the registers when the effect is over.
; music_update() runs once per frame after sfx_update (main loop). Song format and docs: docs/TECH.md "Musik (v1.1)", tools/music.py.
.importzp ptr1, tmp1, tmp2
.import _sfx_id, _mus_song, _mus_loops, _mus_mute, _mus_rows, _mus_tempo
.export _music_play, _music_stop, _music_update, _music_pause, _music_fast

.segment "ZEROPAGE"
m_pl:    .res 4            ; stream pointer of the channel
m_ph:    .res 4
m_dur:   .res 4            ; rows left on the current note
m_note:  .res 4            ; current note (0 = rest; noise: drum 1..6)
m_vol:   .res 4            ; volume of new notes (command $80)
m_duty:  .res 4            ; $4000-style byte without volume: duty << 6 | $30
m_env:   .res 4            ; decay: frames per volume step, 0 = flat
m_et:    .res 4            ; frames to the next decay step
m_vcur:  .res 4            ; volume now
m_floor: .res 4            ; decay stops here (half the note volume, 0 for drums)
m_plo:   .res 4            ; period of the note (noise: period/mode register)
m_phi:   .res 4
m_shd:   .res 4            ; last $4003 value written ($FF = write it again): rewriting it every frame would restart the pulse
mus_tc:  .res 1            ; frames to the next row
mus_base: .res 1           ; tempo of the song (frames per row)
mus_pause: .res 1

.segment "MUSIC"
apu_base: .byte 0, 4, 12, 8        ; offset of the channel's registers from $4000
mute_bit: .byte 1, 2, 4

; void music_play(unsigned char id): start song id (1..) from the top unless it already plays.
_music_play:
    cmp _mus_song
    beq @done
    sta _mus_song
    asl a
    asl a
    asl a
    asl a
    tax                     ; X = id * 16: record in mus_songs
    lda mus_songs,x
    sta mus_base
    sta _mus_tempo
    ldy #0
@ch:
    lda mus_songs+1,x
    sta m_pl,y
    lda mus_songs+2,x
    sta m_ph,y
    inx
    inx
    lda #1
    sta m_dur,y             ; the first tick fetches
    lda #0
    sta m_note,y
    sta m_env,y
    sta m_phi,y
    lda #$FF
    sta m_shd,y
    lda #$B0
    sta m_duty,y
    lda #6
    sta m_vol,y
    lda #3
    sta m_floor,y
    iny
    cpy #4
    bne @ch
    lda #$30
    sta m_duty+2            ; noise has no duty
    lda #0
    sta m_floor+2
    sta _mus_loops
    sta _mus_rows
    sta _mus_rows+1
    sta mus_pause
    lda #1
    sta mus_tc
@done:
    rts

; void music_stop(void): silence and forget the song.
_music_stop:
    lda #0
    sta _mus_song
    sta mus_pause
    sta _mus_mute
silence:
    lda #$FF
    sta m_shd+3
    ldx #2
@l:
    lda #$FF
    sta m_shd,x
    lda _sfx_id,x
    bne @n                  ; an effect plays there
    ldy apu_base,x
    lda #$30
    sta $4000,y
@n:
    dex
    bpl @l
    lda #$80
    sta $4008               ; triangle: linear counter 0
    rts

; void music_pause(unsigned char on): 1 = silent, the song keeps its place; 0 = go on.
_music_pause:
    sta mus_pause
    lda mus_pause
    beq @r
    lda #0
    sta _mus_mute
    jmp silence
@r: rts

; void music_fast(void): tempo x 3/4 (boss phase 3); music_play resets it.
_music_fast:
    lda mus_base
    lsr a
    lsr a
    sta tmp1
    lda mus_base
    sec
    sbc tmp1
    sta _mus_tempo
    rts

; void music_update(void): one frame. Row tick (every tempo frames): advance every channel; every frame: decay and registers.
_music_update:
    lda _mus_song
    beq @off
    lda mus_pause
    beq @go
@off:
    rts
@go:
    lda #0
    sta _mus_mute
    dec mus_tc
    bne @out
    lda _mus_tempo
    sta mus_tc
    inc _mus_rows
    bne :+
    inc _mus_rows+1
:   ldx #3
@row:
    dec m_dur,x
    bne :+
    jsr fetch
:   dex
    bpl @row
@out:
    ldx #2
@ch:
    lda _sfx_id,x
    beq @free
    lda mute_bit,x
    ora _mus_mute
    sta _mus_mute
    lda #$FF
    sta m_shd,x
    bne @next               ; (always)
@free:
    lda m_env,x
    beq @noenv
    dec m_et,x
    bne @noenv
    sta m_et,x
    lda m_vcur,x
    cmp m_floor,x
    beq @noenv
    bcc @noenv
    dec m_vcur,x
@noenv:
    ldy apu_base,x
    lda m_note,x
    beq @quiet
    lda m_vcur,x
    ora m_duty,x
    sta $4000,y
    lda #$08                ; sweep off, negate set: no mute for periods above 1023 (noise: $400D, unused)
    sta $4001,y
    lda m_plo,x
    sta $4002,y
    lda m_phi,x
    cmp m_shd,x
    beq @next
    sta m_shd,x
    sta $4003,y
    jmp @next
@quiet:
    lda #$30
    sta $4000,y
@next:
    dex
    bpl @ch
    lda m_note+3            ; triangle: on unless a rest or the last frame of the note (articulation)
    beq @tq
    lda mus_tc
    cmp #1
    bne @ton
    lda m_dur+3
    cmp #1
    beq @tq
@ton:
    lda #$FF
    sta $4008
    lda m_plo+3
    sta $400A
    lda m_phi+3
    cmp m_shd+3
    beq @quit
    sta m_shd+3
    sta $400B
@quit:
    rts
@tq:
    lda #$80
    sta $4008
    rts

; fetch(X = channel): read the stream up to and including the next note/rest, set it up. Keeps X.
; (Row ticks where all four channels fetch are the busiest frames, ~1000 cycles.)
fetch:
    lda m_pl,x
    sta ptr1
    lda m_ph,x
    sta ptr1+1
    ldy #0
@next:
    lda (ptr1),y
    iny
    cmp #$80
    bcs @cmd
    sta m_note,x
    lda (ptr1),y
    iny
    sta m_dur,x
    tya                     ; stream pointer = ptr1 + Y
    clc
    adc ptr1
    sta m_pl,x
    lda ptr1+1
    adc #0
    sta m_ph,x
    ldy m_note,x
    beq @ret                ; rest
    cpx #2
    beq @drum
    cpx #3
    beq @tri
    lda mus_per_lo,y
    sta m_plo,x
    lda mus_per_hi,y
    jmp @pv
@tri:
    lda mus_tri_lo,y
    sta m_plo,x
    lda mus_tri_hi,y
@pv:
    sta m_phi,x
    lda m_vol,x
    sta m_vcur,x
    lda m_env,x
    sta m_et,x
@ret:
    rts
@drum:
    lda mus_drum_vol-1,y
    sta m_vcur,x
    lda mus_drum_per-1,y
    sta m_plo,x
    lda mus_drum_env-1,y
    sta m_env,x
    sta m_et,x
    rts
@cmd:
    cmp #$80                ; volume
    bne @c81
    lda (ptr1),y
    iny
    sta m_vol,x
    lsr a
    sta m_floor,x
    jmp @next
@c81:
    cmp #$81                ; duty
    bne @c82
    lda (ptr1),y
    iny
    sta m_duty,x
    jmp @next
@c82:
    cmp #$82                ; decay
    bne @c83
    lda (ptr1),y
    iny
    sta m_env,x
    jmp @next
@c83:
    cmp #$83                ; jump (loop)
    bne @c84
    lda (ptr1),y
    sta tmp1
    iny
    lda (ptr1),y
    sta ptr1+1
    lda tmp1
    sta ptr1
    ldy #0
    cpx #0
    bne @j
    inc _mus_loops          ; counts the loops of pulse 1
@j: jmp @next
@c84:                       ; $84 end: rest for ever (stay on this byte, wait 255 rows, read it again)
    dey
    lda #0
    sta m_note,x
    lda #255
    sta m_dur,x
    tya
    clc
    adc ptr1
    sta m_pl,x
    lda ptr1+1
    adc #0
    sta m_ph,x
    rts

.include "songs.inc"
