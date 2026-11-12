; Minimal NES/MMC3 runtime: iNES header, reset, NMI, IRQ stub, cc65 C startup.
.import _main, copydata, zerobss
.import __CSTACK_START__, __CSTACK_SIZE__
.importzp sp
.import _frame_count, _cur_bank
.export _wait_vblank, _ppu_flush, _bank_set, __STARTUP__: absolute = 1
.export _colbuf, _attrbuf, _col_pending, _col_addr, _attr_addr, _ppu_ctrl, _scroll_x

.export _oam

BANK_NONE = 13          ; unused PRG bank mapped at $8000 after reset

.segment "OAM"
_oam: .res 256         ; $0200, DMA source

; Background streaming state, filled by C (see docs/TECH.md "Overworld-Scrolling").
.segment "BSS"
_colbuf:      .res 60   ; two tile columns of 30 tiles (left, right)
_attrbuf:     .res 8    ; attribute bytes of the 4-tile-wide attribute column
_col_pending: .res 1    ; 1 = NMI must flush colbuf/attrbuf
_col_addr:    .res 2    ; PPU address of the left tile column (row 0)
_attr_addr:   .res 2    ; PPU address of the attribute byte of row 0 (clobbered by flush)
_ppu_ctrl:    .res 1    ; $2000 value for the frame (incl. NMI bit, nametable bit)
_scroll_x:    .res 1    ; $2005 X value for the frame

.segment "HEADER"
    .byte "NES", $1A
    .byte 8             ; 8 x 16 KB PRG
    .byte 16            ; 16 x 8 KB CHR
    .byte $42           ; mapper 4, battery, mirroring (MMC3 overrides)
    .byte $00
    .byte 1             ; 1 x 8 KB PRG-RAM

.segment "STARTUP"
reset:
    sei
    cld
    ldx #$40
    stx $4017           ; APU frame IRQ off
    ldx #$FF
    txs
    inx
    stx $2000           ; NMI off
    stx $2001           ; rendering off
    stx $4010           ; DMC IRQ off
    bit $2002
:   bit $2002           ; PPU warm-up, 1st vblank
    bpl :-

    ; MMC3: PRG mode 0, boot banks 0/1 at $8000/$A000; vertical mirroring; PRG-RAM on; IRQ off
    lda #$06
    sta $8000
    lda #BANK_NONE      ; empty bank until a boss bank is mapped (cur_bank is set after the RAM clear)
    sta $8001
    lda #$07
    sta $8000
    lda #1
    sta $8001
    lda #0
    sta $A000
    lda #$80
    sta $A001
    sta $E000           ; IRQ disable (value irrelevant)
    ; CHR: R0..R5 = linear 8 KB (2 KB banks at $0000/$0800, 1 KB banks at $1000-$1FFF)
    ldx #0
:   stx $8000
    lda chr_banks,x
    sta $8001
    inx
    cpx #6
    bne :-

    ; clear RAM $0000-$07FF, sprites ($0200 page) hidden
    lda #0
    tax
:   sta $0000,x
    sta $0100,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne :-
    lda #$FF
:   sta $0200,x
    inx
    bne :-

:   bit $2002           ; 2nd vblank
    bpl :-

    lda #BANK_NONE
    sta _cur_bank
    lda #<(__CSTACK_START__ + __CSTACK_SIZE__)
    sta sp
    lda #>(__CSTACK_START__ + __CSTACK_SIZE__)
    sta sp+1
    jsr copydata
    jsr zerobss
    jsr _main
:   jmp :-

nmi:
    pha
    txa
    pha
    tya
    pha
    lda #$02
    sta $4014           ; OAM DMA from $0200
    lda _col_pending
    beq :+
    jsr _ppu_flush
    lda #0
    sta _col_pending
:   lda $2002           ; reset the address latch
    lda _ppu_ctrl
    sta $2000
    lda _scroll_x
    sta $2005
    lda #0
    sta $2005
    inc _frame_count
    bne :+
    inc _frame_count+1
:   pla
    tay
    pla
    tax
    pla
irq:
    rti

; Write colbuf as two tile columns and attrbuf as one attribute column. NMI off or in vblank.
_ppu_flush:
    lda _ppu_ctrl
    and #$7F            ; never enable NMI from here
    ora #$04            ; +32 per write: vertical runs
    sta $2000
    lda $2002
    lda _col_addr+1
    sta $2006
    lda _col_addr
    sta $2006
    ldx #0
:   lda _colbuf,x
    sta $2007
    inx
    cpx #30
    bne :-
    lda $2002
    lda _col_addr+1
    sta $2006
    lda _col_addr
    ora #1              ; right tile column (left one is even)
    sta $2006
:   lda _colbuf,x
    sta $2007
    inx
    cpx #60
    bne :-
    ldx #0
:   lda _attr_addr+1
    sta $2006
    lda _attr_addr
    sta $2006
    lda _attrbuf,x
    sta $2007
    lda _attr_addr
    clc
    adc #8
    sta _attr_addr
    inx
    cpx #8
    bne :-
    rts

chr_banks: .byte 0, 2, 4, 5, 6, 7

; void bank_set(unsigned char b): map PRG bank b at $8000 (MMC3 R6), remember it in cur_bank.
; Main loop only: NMI never touches $8000, so no select-register race and no banked code in NMI.
_bank_set:
    sta _cur_bank
    ldx #$06
    stx $8000
    sta $8001
    rts

_wait_vblank:
    lda _frame_count
:   cmp _frame_count
    beq :-
    rts

.segment "VECTORS"
    .word nmi, reset, irq
