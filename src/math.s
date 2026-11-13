; unsigned char __fastcall__ mulhi(unsigned char a, unsigned char b): (a * b) >> 8, a shift-add 8x8 multiply (~110 cycles; cc65's
; 16-bit multiply costs several times that). Fixed bank, callable from banked code.
.import popa
.importzp tmp1, tmp2
.export _mulhi
_mulhi:
    sta tmp1            ; multiplier
    jsr popa
    sta tmp2            ; multiplicand
    lda #0
    ldx #8
    lsr tmp1
@l: bcc @n
    clc
    adc tmp2
@n: ror
    ror tmp1
    dex
    bne @l
    ldx #0              ; A = high byte of the product
    rts

; unsigned char overlap(ax, ay, aw, ah, bx, by, bw, bh): 1 when the rectangles overlap (cc65 convention: bh in A, the other seven on
; the C stack, bw at (sp),0 .. ax at (sp),6; the callee removes them). ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah,
; sums may exceed 255 (a sum >= 256 is always greater). Fixed bank: the boss AIs call it up to ~10 times a frame.
.importzp sp
.export _overlap
.macro lt p, q, r       ; fail unless arg p < arg q + arg r
    ldy #q
    lda (sp),y
    ldy #r
    clc
    adc (sp),y
    bcs :+
    sta tmp1
    ldy #p
    lda (sp),y
    cmp tmp1
    bcs @no
:
.endmacro
_overlap:
    sta tmp2            ; bh arrives in A (cc65 passes the last argument in A)
    lt 6, 2, 0          ; ax < bx + bw
    lt 2, 6, 4          ; bx < ax + aw
    ldy #1              ; ay < by + bh
    lda (sp),y
    clc
    adc tmp2
    bcs :+
    sta tmp1
    ldy #5
    lda (sp),y
    cmp tmp1
    bcs @no
:   lt 1, 5, 3          ; by < ay + ah
    lda #1
@out:
    ldy #7              ; callee pops the 7 stacked argument bytes (cc65 cdecl), A kept
    pha
    clc
    tya
    adc sp
    sta sp
    bcc :+
    inc sp+1
:   pla
    ldx #0
    rts
@no:
    lda #0
    beq @out
