; Fast PPU data writes for the full-screen redraws (docs/TECH.md "Bildaufbau (v1.0)"). Fixed bank, rendering off only.
; The caller has set PPU_ADDR; every routine writes $2007 in sequence.
.import popa, popax
.importzp ptr1, ptr2, tmp1, tmp2, tmp3, tmp4
.zeropage
tmp5: .res 1
tmp6: .res 1
.code
.import _meta_tl, _meta_tr, _meta_bl, _meta_br, _meta_pal, _meta_pal2, _meta_pal4, _meta_pal6
.import _colbuf, _attrbuf, _cell_meta, _me, _mo, _attr, _oam
.export _pair_meta, _col_attr, _ppu_fill, _ppu_copy, _scene_draw, _oam_hide, _col_tiles

; void ppu_fill(unsigned char v, unsigned n): n >= 1 bytes of v.
_ppu_fill:
    sta ptr1
    stx ptr1+1
    jsr popa
    ldy ptr1+1
    beq @rest
@page:
    ldx #0
:   sta $2007
    dex
    bne :-
    dey
    bne @page
@rest:
    ldx ptr1
    beq @done
:   sta $2007
    dex
    bne :-
@done:
    rts

; void ppu_copy(const unsigned char *src, unsigned char n): 1..255 bytes (n = 0 would copy 256).
_ppu_copy:
    sta tmp1
    jsr popax
    sta ptr1
    stx ptr1+1
    ldy #0
:   lda (ptr1),y
    sta $2007
    iny
    cpy tmp1
    bne :-
    rts

; void scene_draw(const unsigned char *t, unsigned char r0, unsigned char n): n metatile rows (16 cells each, t[0..16n-1]) from cell
; row r0 down: writes their tiles to nametable 0 (the two tile rows of a cell row are 64 consecutive bytes, so one PPU address
; suffices) and ORs every cell's palette bits into attr[] (cell row r0 + i, even / odd row = which quadrant of the attribute byte).
_scene_draw:
    sta tmp4            ; rows left
    jsr popa
    sta tmp3            ; current cell row
    jsr popax
    sta ptr1
    stx ptr1+1
    lda tmp3            ; PPU address $2000 + 64 * r0
    lsr
    lsr
    clc
    adc #$20
    sta $2006
    lda tmp3
    and #3
    asl
    asl
    asl
    asl
    asl
    asl
    sta $2006
@row:
    ldy #0              ; top tile row
:   lda (ptr1),y
    tax
    lda _meta_tl,x
    sta $2007
    lda _meta_tr,x
    sta $2007
    iny
    cpy #16
    bne :-
    ldy #0              ; bottom tile row
:   lda (ptr1),y
    tax
    lda _meta_bl,x
    sta $2007
    lda _meta_br,x
    sta $2007
    iny
    cpy #16
    bne :-
    lda tmp3            ; attribute bytes: ptr2 = attr + 8 * (r >> 1)
    lsr
    asl
    asl
    asl
    clc
    adc #<_attr
    sta ptr2
    lda #>_attr
    adc #0
    sta ptr2+1
    lda tmp3
    and #1
    sta tmp1            ; odd row
    lda #0
    sta tmp2            ; index into the 8 attribute bytes
    tay
@at:
    lda (ptr1),y
    sta tmp5            ; even column cell
    iny
    lda (ptr1),y
    tax                 ; odd column cell
    iny
    sty tmp6
    lda tmp1
    bne @odd
    lda _meta_pal2,x
    ldx tmp5
    ora _meta_pal,x
    jmp @st
@odd:
    lda _meta_pal6,x
    ldx tmp5
    ora _meta_pal4,x
@st:
    ldy tmp2
    ora (ptr2),y
    sta (ptr2),y
    inc tmp2
    ldy tmp6
    cpy #16
    bne @at
    clc                 ; next cell row
    lda ptr1
    adc #16
    sta ptr1
    bcc :+
    inc ptr1+1
:   inc tmp3
    dec tmp4
    beq @done
    jmp @row
@done:
    rts

; void oam_hide(void): every sprite below the screen.
_oam_hide:
    lda #$FF
    ldy #0
:   sta _oam,y
    iny
    iny
    iny
    iny
    bne :-
    rts

; void col_tiles(const unsigned char *mm): colbuf = the two tile columns of the 15 metatiles mm[0..14] (main.c build_col).
_col_tiles:
    sta ptr1
    stx ptr1+1
    lda #0
    sta tmp1            ; metatile row
    sta tmp2            ; colbuf offset = 2 * row
@lp:
    ldy tmp1
    lda (ptr1),y
    tay
    ldx tmp2
    lda _meta_tl,y
    sta _colbuf,x
    lda _meta_bl,y
    sta _colbuf+1,x
    lda _meta_tr,y
    sta _colbuf+30,x
    lda _meta_br,y
    sta _colbuf+31,x
    inc tmp2
    inc tmp2
    inc tmp1
    lda tmp1
    cmp #15
    bne @lp
    rts

; void pair_meta(const unsigned char *e): me[i] = cell_meta[e[i]], mo[i] = cell_meta[e[i + 16]] for i = 0..15.
_pair_meta:
    sta ptr1
    stx ptr1+1
    ldy #0
:   lda (ptr1),y
    tax
    lda _cell_meta,x
    sta _me,y
    tya
    clc
    adc #16
    tay
    lda (ptr1),y
    tax
    lda _cell_meta,x
    sta _mo-16,y
    tya
    sec
    sbc #15
    tay
    cpy #16
    bne :-
    rts

; void col_attr(void): attrbuf[i] = pal[me[2i]] | pal2[mo[2i]] | pal4[me[2i+1]] | pal6[mo[2i+1]], i = 0..7.
_col_attr:
    ldy #0
    sty tmp1            ; i
:   lda _me,y
    tax
    lda _meta_pal,x
    sta tmp2
    lda _mo,y
    tax
    lda _meta_pal2,x
    ora tmp2
    sta tmp2
    lda _me+1,y
    tax
    lda _meta_pal4,x
    ora tmp2
    sta tmp2
    lda _mo+1,y
    tax
    lda _meta_pal6,x
    ora tmp2
    ldx tmp1
    sta _attrbuf,x
    inc tmp1
    iny
    iny
    cpy #16
    bne :-
    rts
