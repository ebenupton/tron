; ============================================================================
; Keys and sound, from the vsync interrupt (beebgame's scan_keys and sndwrite)
; ============================================================================
KEYN = 11
        .segment "CODEB"
keytab:  .byte $61, $42, $66, $67, $19, $79, $62, $49, $30, $31, $70
keybits: .byte K_1L, K_1R, K_2L, K_2R, K_2L, K_2R, K_GO, K_GO, K_ONE, K_TWO, K_ESC

scan_keys:
        lda #$7F
        sta VIA_DDRA
        lda #3
        sta VIA_ORB                 ; keyboard autoscan off
        lda #0                ; (stz)
        sta knew                ; (stz)
        ldx #KEYN-1
@k:     lda keytab,x
        sta VIA_ORANH
        lda VIA_ORANH
        bpl :+
        lda keybits,x
        ora knew
        sta knew
:       dex
        bpl @k
        lda keys                    ; newly down: latched for the logic
        eor #$FF
        and knew
        ora keyhit
        sta keyhit
        lda knew
        sta keys
        rts

; one byte to the sound chip, from anywhere (sound_tick's own writes are sndw's,
; between one opening and closing of the port)
sndwrite:
        pha
        lda #$FF
        sta VIA_DDRA
        lda #$0B
        sta VIA_ORB
        pla
        jsr sndw
        lda #$7F
        sta VIA_DDRA
        rts
sndw:   sta VIA_ORANH
        lda #0
        sta VIA_ORB
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        lda #8
        sta VIA_ORB
        rts

; ---------------------------------------------------------------- the state
; Four voices (the chip's three tones and its noise), each a period, a slide a
; vsync, an attenuation (4.4) and a fade a vsync; a sequencer that sets them from
; SEQ's steps; and the two engines, which take voices 0 and 1 while they run.
VPL     = SNDBSS+0                  ; period (the noise: its control byte)
VPH     = SNDBSS+4                  ;        (the noise: control not yet written)
VD      = SNDBSS+8                  ; slide a vsync (signed)
VV      = SNDBSS+12                 ; attenuation, 4.4 ($F1 and up: off)
VF      = SNDBSS+16                 ; fade a vsync (sixteenths)
S_WAIT  = SNDBSS+20                 ; vsyncs to the sequence's next step (0: none)
S_POS   = SNDBSS+21                 ; that step, in SEQ
S_ENG   = SNDBSS+22                 ; engines running
S_REV   = SNDBSS+23                 ; (2) added to their periods: the revs, falling
S_TRN   = SNDBSS+25                 ; (2) a bike's turn: its engine's screech, fading

snd_init:
        ldx #31
        lda #0
:       sta SNDBSS,x
        dex
        bpl :-
        ldx #3
        lda #$FF
:       sta VV,x
        dex
        bpl :-
        rts

; X = the bike that turned: its engine screeches, and its own zap (effects 3, 4)
snd_turn:
        lda #8
        sta S_TRN,x
        txa
        clc
        adc #3
; A = effect: 1 count, 2 go, 3/4 turn, 5 crash, 6 round, 7 draw, 8 match, 9 title
sfx:    sta nm_a                    ; (no sei, which would delay a chain step: the
        txa                         ; sequence is off while its place changes, and
        pha                         ; on again last)
        ldx nm_a
        lda #0
        sta S_WAIT
        lda seqst-1,x
        sta S_POS
        lda #1
        sta S_WAIT
        pla
        tax
        lda nm_a
        rts

eng_on: lda #<520                   ; from a growl, up
        sta S_REV
        lda #>520
        sta S_REV+1
        sta S_ENG
        rts
eng_off:
        pha
        lda #0
        sta S_ENG
        pla
        rts
eng_pitch:                          ; (the engines' pitch is the sound's own)
        rts

; (sndw in line, for sound_tick's three writes a voice: its worst case is tight)
.macro  SNDW
        sta VIA_ORANH
        lda #0
        sta VIA_ORB
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        lda #8
        sta VIA_ORB
.endmacro

; every vsync: the sequencer's step if it is due, then the four voices
sound_tick:
        lda #$FF                    ; the port to the chip, for sndw
        sta VIA_DDRA
        lda #$0B
        sta VIA_ORB
        lda S_WAIT
        beq @vo
        dec S_WAIT
        bne @vo
        ldy S_POS                   ; a step: wait << 2 | commands - 1
        lda seq,y
        iny
        sty S_POS
        pha
        and #3
        sta itmp+3
        pla
        lsr a
        lsr a
        sta S_WAIT
@c:     ldy S_POS                   ; a command: note << 2 | voice, then
        lda seq,y                   ; attenuation << 4 | fade
        pha
        and #3
        tax
        iny
        lda seq,y
        iny
        sty S_POS
        sta VV,x
        and #15
        sta VF,x
        pla
        lsr a
        lsr a
        tay
        lda ntl,y
        sta VPL,x
        lda nth,y
        sta VPH,x
        lda #0
        cpy #NSL
        bcs :+
        lda nsl,y
:       sta VD,x
        dec itmp+3
        bpl @c
@vo:    lda S_ENG                   ; the revs: up fast from the start, then
        beq @vl                     ; creeping up for as long as the round lasts
        lda S_REV+1
        beq @slow
        lda S_REV
        sec
        sbc #12
        sta S_REV
        bcs @vl
        dec S_REV+1
        bcc @vl
@slow:  lda vsyncs
        and #7
        bne @vl
        lda S_REV
        beq @vl
        dec S_REV
@vl:    ldx #3
@v:     cpx #2
        bcs @sv
        lda S_ENG
        beq @sv
        ; ---- an engine: a buzz from a wobble, its pitch the revs', and a turn's
        ; screech (up, and louder) falling back
        lda #$FF
        sta VV,x                    ; (the sequencer's voice is dead under it)
        lda vsyncs
        and #1
        asl a
        asl a
        asl a
        ora engb,x
        clc
        adc S_REV
        sta VPL,x
        lda S_REV+1
        adc #1
        sta VPH,x
        lda S_TRN,x
        beq @e1
        dec S_TRN,x
        asl a
        asl a
        asl a
        asl a
        sta itmp
        lda VPL,x
        sec
        sbc itmp
        sta VPL,x
        bcs :+
        dec VPH,x
:       ldy #$40
        bne @e2
@e1:    ldy #$70
@e2:    sty itmp
        bne @per
        ; ---- a voice: fade, period and slide (the noise: its control, once: a
        ; write restarts it)
@sv:    lda VV,x
        sta itmp
        cmp #$F1
        bcs @att
        adc VF,x
        bcc :+
        lda #$FF
:       sta VV,x
        cpx #3
        bne @per
        lda VPH+3
        beq @att
        lsr VPH+3
        lda VPL+3
        jsr sndw
        jmp @att
@per:   lda VPL,x
        and #15
        ora cha,x
        eor #$10
        SNDW
        lda VPH,x
        asl a
        asl a
        asl a
        asl a
        sta itmp+1
        lda VPL,x
        lsr a
        lsr a
        lsr a
        lsr a
        ora itmp+1
        SNDW
        ldy #0
        lda VD,x
        bpl :+
        dey
:       clc
        adc VPL,x
        sta VPL,x
        tya
        adc VPH,x
        and #3
        sta VPH,x
@att:   lda itmp
        lsr a
        lsr a
        lsr a
        lsr a
        ora cha,x
        SNDW
        dex
        bmi :+
        jmp @v
:       lda #$7F
        sta VIA_DDRA
        rts

; the round's end: its sting, a draw's, or the match's fanfare
snd_over:
        ldx #7
        lda bdead
        and bdead+1
        bne @s
        dex
        lda score
        cmp #5
        beq @m
        lda score+1
        cmp #5
        bne @s
@m:     ldx #8
@s:     txa
        jmp sfx

cha:    .byte $90, $B0, $D0, $F0    ; attenuation latches (eor $10: the period's)
engb:   .byte $B0, $E0              ; engine periods less the revs: 432, 480 (+8)

; ---- the notes: periods (125000 / Hz).  The first NSL slide.  The noise's are
; its control byte, with a high byte of 1 (written once).  The B_ notes are a
; silent channel 2 clocking the periodic noise: a bass, a fifteenth of the tone.
.define NOTES 160, 210, 160, 200, 25, 170, $1E4, $1E7, $1E3, 956, 950, 602, 536, 478, 426, 402, 379, 358, 319, 301, 268, 239, 159, 119, 127, 255
N_ZAP0  = 0                         ; the turns' zaps, rising
N_ZAP1  = 1
N_CR0   = 2                         ; the crash's two falling tones
N_CR1   = 3
N_CRK   = 4                         ; and its noise's clock, falling
N_BD    = 5                         ; the countdown's bass (G1), sagging
NSL     = 6
N_WHI   = 6                         ; white noise, high
N_WC2   = 7                         ; white noise at channel 2's rate
N_PC2   = 8                         ; periodic noise at channel 2's rate
N_C3    = 9
N_C3D   = 10                        ; (a little sharp: beats against C3)
N_AB3   = 11
N_BB3   = 12
N_C4    = 13
N_D4    = 14
N_EB4   = 15
N_E4    = 16
N_F4    = 17
N_G4    = 18
N_AB4   = 19
N_BB4   = 20
N_C5    = 21
N_G5    = 22
N_C6    = 23
N_BC2   = 24
N_BC1   = 25
ntl:    .lobytes NOTES
nth:    .hibytes NOTES
nsl:    .byte <-14, <-18, 9, 12, 4, 1

; ---- the sequences: steps of a header (vsyncs to the next step, 0 the last;
; commands) and its commands (note and voice; attenuation and fade)
.macro  STEP wait, n
        .byte (wait)<<2|((n)-1)
.endmacro
.macro  NOTE v, n, env
        .byte (n)<<2|(v), env
.endmacro
OFF     = $FF
CLK     = $F0                       ; silent, but its period written: the noise's clock

seqst:  .byte sq_count-seq, sq_go-seq, sq_t0-seq, sq_t1-seq, sq_crash-seq
        .byte sq_round-seq, sq_draw-seq, sq_match-seq, sq_title-seq
seq:
sq_count:                           ; 3, 2, 1: a fifth over a bass drum's note
        STEP 0, 4
        NOTE 0, N_G4, $26
        NOTE 1, N_D4, $36
        NOTE 2, N_BD, CLK
        NOTE 3, N_PC2, $05
sq_go:  STEP 4, 2                   ; go: up the octaves in a hiss, over the engines
        NOTE 2, N_C5, $18
        NOTE 3, N_WHI, $34
        STEP 4, 1
        NOTE 2, N_G5, $18
        STEP 0, 1
        NOTE 2, N_C6, $04
sq_t0:  STEP 4, 1                   ; a turn: a zap (and the engine's screech)
        NOTE 2, N_ZAP0, $40
        STEP 0, 1
        NOTE 2, N_ZAP0, OFF
sq_t1:  STEP 4, 1
        NOTE 2, N_ZAP1, $40
        STEP 0, 1
        NOTE 2, N_ZAP1, OFF
sq_crash:                           ; a crack, two tones falling away, and a boom
        STEP 3, 4                   ; that sinks, with two echoes
        NOTE 3, N_WHI, $00
        NOTE 0, N_CR0, $34
        NOTE 1, N_CR1, $34
        NOTE 2, N_CRK, CLK
        STEP 16, 1
        NOTE 3, N_WC2, $03
        STEP 16, 1
        NOTE 3, N_WC2, $23
        STEP 0, 1
        NOTE 3, N_WC2, $53
sq_round:                           ; a round won: three and a chord on a bass
        STEP 6, 4
        NOTE 0, N_G4, $18
        NOTE 1, N_E4, $38
        NOTE 2, N_C4, $38
        NOTE 3, N_WHI, OFF
        STEP 6, 1
        NOTE 0, N_G4, $18
        STEP 6, 1
        NOTE 0, N_G4, $18
        STEP 0, 4
        NOTE 0, N_C5, $13
        NOTE 1, N_G4, $33
        NOTE 2, N_BC2, CLK
        NOTE 3, N_PC2, $13
sq_draw:                            ; a draw: down, in thirds
        STEP 14, 3
        NOTE 0, N_EB4, $15
        NOTE 1, N_C4, $15
        NOTE 3, N_WHI, OFF
        STEP 14, 2
        NOTE 0, N_D4, $15
        NOTE 1, N_BB3, $15
        STEP 0, 2
        NOTE 0, N_C4, $13
        NOTE 1, N_AB3, $13
sq_match:                           ; the match: a fanfare, A flat and B flat to C
        STEP 8, 4
        NOTE 0, N_C5, $18
        NOTE 1, N_E4, $38
        NOTE 2, N_C4, $38
        NOTE 3, N_WHI, OFF
        STEP 8, 1
        NOTE 0, N_C5, $18
        STEP 8, 1
        NOTE 0, N_C5, $18
        STEP 16, 1
        NOTE 0, N_C5, $14
        STEP 16, 3
        NOTE 0, N_AB4, $14
        NOTE 1, N_EB4, $34
        NOTE 2, N_AB3, $34
        STEP 16, 3
        NOTE 0, N_BB4, $14
        NOTE 1, N_F4, $34
        NOTE 2, N_BB3, $34
        STEP 12, 3
        NOTE 0, N_C5, $16
        NOTE 1, N_G4, $34
        NOTE 2, N_C4, $34
        STEP 6, 1
        NOTE 0, N_BB4, $18
        STEP 0, 4
        NOTE 0, N_C5, $11
        NOTE 1, N_G4, $31
        NOTE 2, N_BC2, CLK
        NOTE 3, N_PC2, $11
sq_title:                           ; the title: two low Cs beating, on a deep bass
        STEP 0, 4
        NOTE 0, N_C3, $02
        NOTE 1, N_C3D, $02
        NOTE 2, N_BC1, CLK
        NOTE 3, N_PC2, $01
        .assert * - seq < 256, error, "SEQ is indexed by a byte"
