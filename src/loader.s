; ============================================================================
; LOADER: everything the game needs from the MOS and the filing system, done
; before the game is in memory, since the game covers a Model B's DFS workspace.
; *RUN from !BOOT at $1900 (above that workspace).
;
;   1  the machine (OSBYTE 0) and, on a Model B, its two sideways RAM banks
;   2  MODE 1, the cursor off, the palette black
;   3  BANK4 (map, tiles, tables, the code that reads the map) into one bank
;   4  BANKB (the explosion's frames, room for the font, most of the code) to
;      $3000, the MOS's font (32..95) into it, then into the other bank
;   5  TRON (the interrupt, the display, the drawing) to $3000, then (interrupts
;      off, from page 1) down to $0800, and run
;
; The game reads what it needs to know from HANDOFF.  A Model B with one bank of
; sideways RAM gets the narrow-window build instead (LOAD16).
; ============================================================================
        .setcpu "6502"
        .include "hw.inc"
        .include "../build/gen.inc"

TRONHI  = $3000                     ; where TRON is loaded, before its move
TRONLO  = $0800                     ; ... and where it runs (tron.cfg: MAIN)
TRONPG  = $11                       ; pages moved (MAIN is $1080 bytes)
OSCLI   = $FFF7
ROMTYPE = $02A1                     ; the MOS's table of sideways ROM types
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
        lda #15                     ; the two highest banks of RAM
        jsr find_ram
        bcs @nr
        sta hand+2                  ; (the code bank)
        sbc #0                      ; (C = 0: the bank below)
        bmi @nr
        jsr find_ram
        bcs @nr
        sta hand+1                  ; (map and tiles)
        jmp @mode
@nr:    ldx #<cmd_16                ; one bank (or none): the narrow build
        ldy #>cmd_16
        jmp OSCLI
@master:
        lda #4
        sta hand+1
        lda #5
        sta hand+2
@mode:  lda #0                      ; neither bank a ROM to the MOS any more
        ldx hand+1
        sta ROMTYPE,x
        ldx hand+2
        sta ROMTYPE,x
        ldx #0                      ; ---- 2: MODE 1
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
        ldx #<cmd_b4                ; ---- 3: bank 4's image
        ldy #>cmd_b4
        jsr OSCLI
        lda hand+1
        jsr to_bank
        ldx #<cmd_bb                ; ---- 4: the code bank's, the font into it
        ldy #>cmd_bb
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
        lda hand+2
        jsr to_bank
        ldx #<cmd_tr                ; ---- 5: the game, high, then down
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

; (run from $0100: copies TRONPG pages from TRONHI to TRONLO, then runs it)
mover:  ldy #0
        sty lp
        sty lq
        lda #>TRONHI
        sta lp+1
        lda #>TRONLO
        sta lq+1
        ldx #TRONPG
@m:     lda (lp),y
        sta (lq),y
        iny
        bne @m
        inc lp+1
        inc lq+1
        dex
        bne @m
        jmp TRONLO
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

; A = the bank to start from: the highest bank at or below it whose $8000 changes
; when written (put back as it was); A = the bank, C = 0; C = 1 if none
find_ram:
        sta lb
        php
        sei
        lda ROMSEL_CPY
        pha
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
cmd_b4: .byte "LOAD BANK4 3000", 13
cmd_bb: .byte "LOAD BANKB 3000", 13
cmd_tr: .byte "LOAD TRON 3000", 13
cmd_16: .byte "RUN LOAD16", 13
fontbuf: .res 9
hand:   .res 3
