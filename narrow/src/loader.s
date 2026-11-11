; ============================================================================
; LOAD16 (the narrow build, for a Model B with one bank of sideways RAM: LOADER
; runs it): everything the game needs from the MOS and the filing system, done
; before the game is in memory, since the game's code ($0E00-$32FF) covers a
; Model B's DFS workspace.  *RUN from !BOOT at $1900 (above that workspace).
;
;   1  the machine (OSBYTE 0) and, on a Model B, its sideways RAM bank
;   2  MODE 1, the cursor off, the palette black
;   3  BANK4 (map, tiles, tables) to $3000, the MOS's font (32..95) into it at
;      FONTB, then the lot into the sideways RAM bank
;   4  EXPL (the explosion's frames): the Master's into bank 5, the Model B's
;      left in main RAM at EXPLB
;   5  TRON to $4400, then (interrupts off, from page 1) down to $0E00 and run
;
; The game reads what it needs to know from hand.
; ============================================================================
        .setcpu "6502"
        .include "hw.inc"
        .include "../build/gen.inc"

TRONHI  = $4400                     ; where TRON is loaded, before its move
TRONLEN = $3000 - $0E00             ; the game's CODE (34 pages), then its LOWX
LOWXRUN = $0800                     ; image, which goes to $0800-$0CFF (tron.cfg)
LOWXLEN = $0500
OSCLI   = $FFF7
lp      = $70                       ; (the user's zero page, while the MOS runs)
lq      = $72
lb      = $74
lt      = $75

        .segment "CODE"
loader: ldx #$FF
        txs
        lda #0                      ; ---- 1: the machine
        ldx #1
        jsr OSBYTE
        lda #0
        cpx #3
        bcs :+
        lda #1                      ; (MOS 0..2: a Model B or B+)
:       sta hand
        beq @master
        jsr find_ram
        bcc :+
        ldx #0                      ; no sideways RAM: say so, and stop
@nr:    lda msg_noram,x
        beq *
        jsr OSWRCH
        inx
        bne @nr
:       sta hand+1
        sta hand+2
        jmp @mode
@master:
        lda #4
        sta hand+1
        lda #5
        sta hand+2
@mode:  ldx #0                      ; ---- 2: MODE 1
:       lda vdu,x
        jsr OSWRCH
        inx
        cpx #vdu_end-vdu
        bne :-
        ldx #15                     ; the palette black: every logical colour
        lda #$07                    ; (physical 7 xor 7 = black)
:       sta ULA_PAL
        clc
        adc #$10
        dex
        bpl :-
        ldx #<cmd_b4                ; ---- 3: bank 4's image, the font into it
        ldy #>cmd_b4
        jsr OSCLI
        lda #32
        sta lt
        lda #<(FONTB-$8000+$3000)
        sta lp
        lda #>(FONTB-$8000+$3000)
        sta lp+1
@font:  lda lt
        sta fontbuf
        ldx #<fontbuf
        ldy #>fontbuf
        lda #10
        jsr OSWORD
        ldy #7
:       lda fontbuf+1,y
        sta (lp),y
        dey
        bpl :-
        lda lp
        clc
        adc #8
        sta lp
        bcc :+
        inc lp+1
:       inc lt
        lda lt
        cmp #96
        bne @font
        lda hand+1
        jsr to_bank
        lda hand                 ; ---- 4: the explosion's frames
        bne @b
        ldx #<cmd_exm
        ldy #>cmd_exm
        jsr OSCLI
        lda hand+2
        jsr to_bank
        jmp @tron
@b:     ldx #<cmd_exb
        ldy #>cmd_exb
        jsr OSCLI
@tron:  ldx #<cmd_tr                ; ---- 5: the game, high, then down
        ldy #>cmd_tr
        jsr OSCLI
        ldx #2                      ; (the handoff, only now: the MOS's file loading
:       lda hand,x                  ;  uses $0380 on a Model B)
        sta HANDOFF,x
        dex
        bpl :-
        sei
        lda #$40                    ; RTI for any NMI from here on: the disc
        sta $0D00                   ; controller may still signal, and the DFS's
        ldx #mover_end-mover-1      ; handler and its workspace are going
:       lda mover,x
        sta $0100,x
        dex
        bpl :-
        jmp $0100

; (run from $0100: copies TRONLEN bytes from TRONHI to $0E00, then runs it)
mover:  ldy #0
        sty lp
        sty lq
        lda #>TRONHI
        sta lp+1
        lda #$0E
        sta lq+1
        ldx #>TRONLEN
@m:     lda (lp),y
        sta (lq),y
        iny
        bne @m
        inc lp+1
        inc lq+1
        dex
        bne @m
        lda #<LOWXRUN               ; (lp: the image, which follows)
        sta lq
        lda #>LOWXRUN
        sta lq+1
        ldx #>LOWXLEN+1             ; 5 pages: up to $0D00
@x:     lda (lp),y
        sta (lq),y
        iny
        bne :+
        inc lp+1
        inc lq+1
        dex
:       cpx #1
        bne @x
        cpy #<LOWXLEN
        bne @x
        jmp $0E00
mover_end:

; A = bank: copy $3000-$6FFF there, interrupts off (the MOS may page ROMs)
to_bank:
        php
        sei
        sta lb
        lda ROMSEL_CPY
        pha
        lda lb
        sta ROMSEL_CPY
        sta ROMSEL
        lda #0
        sta lp
        sta lq
        lda #$30
        sta lp+1
        lda #$80
        sta lq+1
        ldy #0
:       lda (lp),y
        sta (lq),y
        iny
        bne :-
        inc lp+1
        inc lq+1
        lda lq+1
        cmp #$C0
        bne :-
        pla
        sta ROMSEL_CPY
        sta ROMSEL
        plp
        rts

; the Model B's sideways RAM: the highest bank whose $8000 changes when written
; (put back as it was); A = the bank, C = 0; C = 1 if none
find_ram:
        php
        sei
        lda ROMSEL_CPY
        pha
        lda #15
        sta lb
@t:     lda lb
        sta ROMSEL_CPY
        sta ROMSEL
        lda $8000
        sta lt
        eor #$FF
        sta $8000
        cmp $8000
        bne @no
        lda lt                      ; RAM: put it back
        sta $8000
        pla
        sta ROMSEL_CPY
        sta ROMSEL
        plp
        lda lb
        clc
        rts
@no:    dec lb
        bpl @t
        pla
        sta ROMSEL_CPY
        sta ROMSEL
        plp
        sec
        rts

vdu:    .byte 22, 1, 23, 1, 0, 0, 0, 0, 0, 0, 0, 0
vdu_end:
cmd_b4: .byte "LOAD BANK16 3000", 13
cmd_exm: .byte "LOAD EXPL16 3000", 13
cmd_exb: .byte "LOAD EXPL16 ", >EXPLB / 16 + '0', (>EXPLB & 15) + '0', "00", 13
cmd_tr: .byte "LOAD TRON16 4400", 13
msg_noram:
        .byte 22, 7, "TRON Lightcycle Run needs a Master 128,", 13, 10
        .byte "or a Model B with 16K of sideways RAM.", 13, 10, 0
fontbuf: .res 9
hand:   .res 3
