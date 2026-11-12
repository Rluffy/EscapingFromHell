; Minimal NES/MMC3 runtime: iNES header, reset, NMI, IRQ stub, cc65 C startup.
.import _main, copydata, zerobss
.import __CSTACK_START__, __CSTACK_SIZE__
.importzp sp
.import _frame_count
.export _wait_vblank, __STARTUP__: absolute = 1

.export _oam

.segment "OAM"
_oam: .res 256         ; $0200, DMA source

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
    lda #0
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

_wait_vblank:
    lda _frame_count
:   cmp _frame_count
    beq :-
    rts

.segment "VECTORS"
    .word nmi, reset, irq
