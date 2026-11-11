; The display: two independently scrolled windows, stacked, by a rupture chain
;
; This is beebgame's display (engine.s: irq_handler, build_sections, crtc_init,
; copy_partial, the ring) taken from one window to two.  Each window is a ring of
; 32 character rows that the CRTC's hardware wrap folds for free -- the top
; window's in main RAM at $3000, the bottom's in shadow RAM at the same addresses
; -- and map character (cx, cy) lives at ring character ((cy mod 32) x 80 + cx) mod
; 2560, so a scroll only draws the newly exposed strips.  A window scrolls by a
; character (4 pixels) across and by 2 scanlines down, the vertical fine scroll
; through a composed top row exactly as beebgame does it.
;
; The frame is seven CRTC sections, fixed in number whatever the scroll:
;   0  W0 A    the composed row (f > 0: 8 - f lines) or row 0 (f = 0: 8 lines)
;   1  W0 P    rows 1..15 (f > 0) or 1..14 (f = 0)
;   2  W0 P2   the top f lines of row 16 (f > 0) or row 15 (f = 0)
;   3-5        the same for W1, in shadow RAM (ACCCON D = 1)
;   6  Q       blanking, 7 rows, the vsync on its row 3
; 2 x 128 + 56 = 312 lines.  The sections being fixed means each window owns its
; own entries, and can change them while the beam is elsewhere.
;
; There is no double buffering: two windows of 18 rows each, twice, do not fit in
; 40K.  Instead each window is drawn while the beam is NOT in it.  Everything a
; scroll exposes but the old frame does not show -- the new row, the composed row
; (which alternates between two spare ring rows) -- can be drawn at any time; only
; the new column (which reuses the characters leaving at the other edge), the
; changed tiles, and the explosion's lines touch what is on screen, and those are
; drawn in the window's own off time:
;   W0: from its last section's end (line 128) to the vsync (line ~280), which is
;       when the vsync programs W0's first section;
;   W1: from its end (line 256) to W0's last section (line ~120 of the next
;       field), whose step programs W1's first.
; Each window then commits its entries in one go (commit).
; ============================================================================

; A section's entry, 8 bytes, as beebgame's: the section's own shape (R4, R9, R6,
; R7) and the NEXT section's start address (R12, R13) and duration (T1 latch),
; because both latch one section late.  R6's bit 0 is this section's ACCCON D:
; 30 for the top window's sections, 31 for the bottom's, 0 for Q.
E_R12 = 0
E_R13 = 1
E_R4  = 2
E_R9  = 3
E_R6  = 4
E_R5  = 5                           ; (R7 is 30 but in Q: the vsync's row)
E_T1L = 6
E_T1H = 7

        .segment "BSS"
SECTAB:   .res 7*8                  ; (the Master's are 0..4; the Model B's 0..6)
R14V:     .res 8*8                  ; each step's first write, R14: 0 (no cursor from
                                    ; the section before), but the Model B's P2s,
                                    ; which keep their window's (entry 7: a dummy)
wk:       .res 2                    ; a window's P section split after row k (the Model B)
crth:     .res 1
selcur:   .res 1                    ; the window selwin last selected (init_chain: none)
fxneed:   .res 2                    ; FXNEED, each window's (the Model B's W1: more)
gt0:      .res 2                    ; GT0, the machine's (glint)
wm:       .res 2                    ; (the Model B: mirror characters needed, each window)
rmir:     .res 1                    ; the selected ring's first row ends in this page
                                    ; (+$80): writes below it go to the mirror too (the
                                    ; Model B: rbase + 2; the Master: 0, none)
mv:       .res 1                    ; (mir1's)
sxl:      .res 1                    ; (split_of's)
sxh:      .res 1
qbl:      .res 2                    ; Q's blank line (CRTC address: hi, lo)
VSB:      .res 8                    ; W0's first section, which the vsync programs: its
                                    ; duration (lo, hi) and address (hi, lo), twice
vsbuf:    .res 1                    ; the copy the vsync reads (0 or 4): commit fills
                                    ; the other and flips this, with no sei (which would
                                    ; delay a step: W0 may commit as Q's falls due)
CURS:     .res 32                   ; each window's cursor (16 bytes): R14, R15, R10,
                                    ; R11 from its P step; then the lower row's R14 (0:
                                    ; none), R15, R11, and the User VIA T1 count to it;
                                    ; then (+9) the R14V entry that keeps R14 (its P2's)
c2idx:    .res 1                    ; the window whose lower row the User VIA T1 is for
RMODN = 72                          ; world character rows a window's table covers
RBASE:    .res 2                    ; per window: its ring's base, end (exclusive) and
RTOP:     .res 2                    ; size (high bytes), length in characters (high,
RSIZE:    .res 2                    ; low), and the CRTC's address of its base (high,
RCH:      .res 2                    ; low)
RCHL:     .res 2
RCRTC:    .res 2
RCRTCL:   .res 2
CSL0:     .res 2                    ; the composed row's two spare ring rows (the Master)
CSL1:     .res 2
GEOMN = 18                          ; (geom_init's bytes, RBASE..CSL1)
RMODL:    .res 2*RMODN              ; per window, world row r: (r x rowch) mod length
RMODH:    .res 2*RMODN
RMULL:    .res 33                   ; r x rowch
RMULH:    .res 33
wpx:      .res 2                    ; a window's width in pixels (4 x rowch)
maxwx:    .res 2                    ; the camera's largest x: WORLDW - wpx
halfw:    .res 1                    ; wpx / 2
PALQ:     .res 16                   ; the palette the next vsync loads (palreq)

; ---------------------------------------------------------------- interrupt
; beebgame's handler, with the per-section ACCCON D taken from the entry and the
; 6845 cursor reprogrammed at the start of each window.  See beebgame's
; docs/DESIGN.md, "The chain", for why the registers go in this order.
        .segment "LOWX"
irq_handler:
        stx irq_x
        sty irq_y
        bit VIA_IFR
        bvs @t1
        jmp @notT1
@t1:    lda dummyz                  ; (beebgame's load-flag test: kept for its timing,
        beq @chain                  ;  which VS2T allows for)
@chain: ldx SECIDX
        lda SECTAB+E_R6,x           ; this section's D, in R6's bit 0
        lsr a
        lda ACCCON                  ; (the Model B: a RAM byte instead: patch_b)
        and #$FE
        adc #0
        sta ACCCON
        lda #14                     ; no cursor from the last section (the P steps set
        sta CRTC_IDX                ; their window's at the end): 14 cycles of the hold
        lda R14V,x
        sta CRTC_DAT
        nop                         ; 12 more: the first CRTC write must follow the
        nop                         ; restart, and the step fires ahead of it
        nop
        nop
        nop
        nop
        lda #9
        sta CRTC_IDX
        lda SECTAB+E_R9,x
        sta CRTC_DAT
        lda #4
        sta CRTC_IDX
        lda SECTAB+E_R4,x
        sta CRTC_DAT
        lda #6
        sta CRTC_IDX
        ldy SECTAB+E_R6,x
        sty CRTC_DAT
        lda #5
        sta CRTC_IDX
        lda SECTAB+E_R5,x
        sta CRTC_DAT
        lda SECTAB+E_T1L,x
        sta VIA_T1LL
        lda SECTAB+E_T1H,x
        sta VIA_T1LH
        lda VIA_T1CL                ; clear the T1 flag
        cpx qidx                    ; Q: the vsync's row, and the chain stops
        bne @adv
        lda #7
        sta CRTC_IDX
        lda #QVSYNC
        sta CRTC_DAT
        sta curR7
        jmp @addr
@adv:   txa
        clc
        adc #8
        sta SECIDX
@addr:  lda #12                     ; the next section's address, last
        sta CRTC_IDX
        lda SECTAB+E_R12,x
        sta CRTC_DAT
        lda #13
        sta CRTC_IDX
        lda SECTAB+E_R13,x
        sta CRTC_DAT
        stx SECCUR
        cpx #1*8                    ; each window's cursor, at the start of its P
        beq @cur0                   ; section: a long one, so this step may be long
        cpx p1w1                    ; (3 x 8; the Model B's 4 x 8)
        beq @cur1
@xit:   ldy irq_y
        ldx irq_x
        lda $FC
        rti
@cur1:  ldy #16
        .byte $2C                   ; (bit abs: skips the ldy #0)
@cur0:  ldy #0
        lda #14
        sta CRTC_IDX
        lda CURS,y
        sta CRTC_DAT
        ldx CURS+9,y                ; (again for its P2 step: the Model B)
        sta R14V,x
        lda #15
        sta CRTC_IDX
        lda CURS+1,y
        sta CRTC_DAT
        lda #10
        sta CRTC_IDX
        lda CURS+2,y
        sta CRTC_DAT
        lda #11
        sta CRTC_IDX
        lda CURS+3,y
        sta CRTC_DAT
        lda CURS+4,y                ; a lower row: the User VIA T1, one-shot, to the
        beq @xit                    ; upper row's last line
        sty c2idx
        lda CURS+7,y
        sta UVIA_T1CL
        lda CURS+8,y
        sta UVIA_T1CH
        jmp @xit
@user:  bit UVIA_IFR                ; the glint's lower row: in the upper row's last
        bvc @ux                     ; line, R10 and R11 first (they act from the next
        ldy c2idx                   ; line on), then the address, after the beam has
        lda #10                     ; passed the cursor's column on this line
        sta CRTC_IDX
        lda #0
        sta CRTC_DAT
        lda #11
        sta CRTC_IDX
        lda CURS+6,y
        sta CRTC_DAT
        lda #14
        sta CRTC_IDX
        lda CURS+4,y
        sta CRTC_DAT
        ldx CURS+9,y                ; (the Model B's P2 step keeps it)
        sta R14V,x
        lda #15
        sta CRTC_IDX
        lda CURS+5,y
        sta CRTC_DAT
        lda UVIA_T1CL               ; (clears its flag)
@ux:    jmp @xit
@notT1: lda VIA_IFR                 ; (the vsync's latency as beebgame's)
        and #$02
        beq @user
        ; ---- vsync: restart T1 first (constant latency), then re-phase the frame
        lda #<VS2T
        sta VIA_T1LL
        lda #>VS2T
        sta VIA_T1CH
        lda #$02
        sta VIA_IFR
        lda #$FF                    ; T2: the beam's clock (beam)
        sta VIA_T2CL
        sta VIA_T2CH
        lda dummyz                  ; (timing, as beebgame's load test)
        cmp #2
        lda #$C0
        sta VIA_IER
        lda #9
        sta CRTC_IDX
        lda #7
        sta CRTC_DAT
        lda #7                      ; no vsync in the windows' sections
        sta CRTC_IDX
        lda #30
        sta CRTC_DAT
        lda #6                      ; pre-arm W0's R6 here, in Q, where it cannot show
        sta CRTC_IDX
        lda #30
        sta CRTC_DAT
        lda #4
        sta CRTC_IDX
        lda curR7
        clc
        adc #QROWS-1-QVSYNC
        and #$7F
        sta CRTC_DAT
        inc vsyncs
        ldx vsbuf                   ; W0's first section, as W0 last committed it
        lda VSB,x
        sta VIA_T1LL
        lda VSB+1,x
        sta VIA_T1LH
        lda #12
        sta CRTC_IDX
        lda VSB+2,x
        sta CRTC_DAT
        lda #13
        sta CRTC_IDX
        lda VSB+3,x
        sta CRTC_DAT
        lda #$40
        sta VIA_IFR
        lda #0
        sta SECIDX
        lda #$F8                    ; between the vsync and W0
        sta SECCUR
        lda ACCCON                  ; D = 0 for W0
        and #$FE
        sta ACCCON
        lda #14                     ; no cursor until W0's P section sets its own
        sta CRTC_IDX
        lda #0
        sta CRTC_DAT
        lda palreq                  ; a palette change, between fields
        beq :++
        ldx #15
:       lda PALQ,x
        sta ULA_PAL
        dex
        bpl :-
        lda #0
        sta palreq
:       lda ROMSEL_CPY              ; the keys and the sound: in the code bank
        pha
        lda bspare
        sta ROMSEL
        jsr scan_keys
        jsr sound_tick
        pla
        sta ROMSEL
        jmp @xit

; CA1 fires at the end of the 2-line vsync pulse; beebgame's constant, with no
; stub latency (the Master's handler is in main RAM).
VS2T = (QROWS-QVSYNC)*8*LINE - 2*LINE - 35 - 36 - 8 + 2

; the User VIA T1 count from the P step's start of it to the upper row's line 7
; (row 1's, here; + 512 a row), plus 20 us (+ column / 4, in glint): calibrated
; under jsbeeb against where the CRTC writes land (test/frames.mjs, "glint")
GT0 = 4*LINE + 25
GT0B = GT0 - 9                      ; (the Model B's: measured the same way)

; ---------------------------------------------------------------- start-up
        .segment "CODEB"
take_over:                          ; beebgame's, with the T1 and vsync only
        sei
        lda #<irq_handler
        sta IRQ1V
        lda #>irq_handler
        sta IRQ1V+1
        lda #$7F
        sta VIA_IER
        sta UVIA_IER
        lda VIA_ACR
        and #$1F
        ora #$40                    ; T1 continuous, T2 timed
        sta VIA_ACR
        lda #<(40*LINE)
        sta VIA_T1LL
        lda #>(40*LINE)
        sta VIA_T1CH
        lda qidx                    ; a step before the first vsync is Q's: it puts
        sta SECIDX                  ; the vsync back and stops the chain (SECIDX
        lda #$C2                    ; starts as whatever was there)
        sta VIA_IER                 ; CA1 (vsync) + T1
        sta VIA_IFR
        lda UVIA_ACR                ; the User VIA's T1: one-shot (the glint)
        and #$3F
        sta UVIA_ACR
        lda #$7F
        sta UVIA_IFR
        lda #$C0
        sta UVIA_IER
        lda #$02                    ; start at a vsync: wait for one (its flag, the
        sta VIA_IFR                 ; interrupt still off), drop T1's pending flag,
:       bit VIA_IFR                 ; and let the vsync's interrupt in first, so it
        beq :-                      ; phases the chain before any step runs
        lda VIA_T1CL
        cli
        rts

; Every CRTC register: R8 = 0 (the MOS's MODE 1 leaves interlace sync on), R10 =
; $20 (the cursor off until a window programs it), a standard 39-row frame until
; the first vsync re-phases it.
crtc_init:
        lda RCRTCL                  ; (the machine's: W0's ring, the row's width and
        sta @val                    ; where its sync falls, centring it)
        lda RCRTC
        sta @val+1
        lda rowch
        sta @val+12
        lsr a
        clc
        adc #58                     ; 98 for 80 characters, 78 for 40
        sta @val+11
        ldx #13
@w:     lda @reg,x
        sta CRTC_IDX
        lda @val,x
        sta CRTC_DAT
        dex
        bpl @w
        lda #2*WROWS+QVSYNC
        sta curR7
        rts
@reg:   .byte 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0
@val:   .byte <CRTCB, >CRTCB, 8, $20, 7, 0, 2*WROWS+QVSYNC, 30, 0, 38, $28, 98, ROWCH, 127

; the chain's constant parts: Q's entry, and a black frame until the windows commit
init_chain:
        lda #$FF
        sta selcur
        lda #0
        sta vsbuf
        ldx #8*8-1
:       sta R14V,x
        cpx #7*8
        bcs :+
        sta SECTAB,x
:       dex
        bpl :--
        ldx qidx                    ; Q
        lda #QROWS-1
        sta SECTAB+E_R4,x
        lda #7
        sta SECTAB+E_R9,x
        lda #0
        sta SECTAB+E_R6,x
        sta SECTAB+E_R5,x
        lda #<(40*LINE-2)           ; (Q's duration, in the entry before it)
        sta SECTAB+E_T1L,x
        sta SECTAB-8+E_T1L,x
        lda #>(40*LINE-2)
        sta SECTAB+E_T1H,x
        sta SECTAB-8+E_T1H,x
        lda qbl                     ; a 6845 shows a frame's first scanline whatever
        sta SECTAB+E_R12,x          ; R6 says: Q's is line 0 of a blank row (main
        sta SECTAB-8+E_R12,x        ; RAM: Q's D is 0)
        lda qbl+1
        sta SECTAB+E_R13,x
        sta SECTAB-8+E_R13,x
        lda qbl                     ; black it: 80 characters (640 bytes), or 40
        sta sa+1
        lda qbl+1
        asl a
        rol sa+1
        asl a
        rol sa+1
        asl a
        rol sa+1
        sta sa
        lda rowb
        sta tmp
        lda rowb+1
        sta tmp+1
        ldy #0
        tya
:       sta (sa),y
        inc sa
        bne :+
        inc sa+1
:       lda tmp
        bne :+
        dec tmp+1
:       dec tmp
        lda #0
        ldx tmp
        bne :---
        ldx tmp+1
        bne :---
        sta CURS
        sta CURS+1
        sta CURS+4
        sta CURS+5
        sta CURS+16
        sta CURS+17
        sta CURS+20
        sta CURS+21
        ldx #0
        jsr calc_window
        jsr commit
        ldx #1
        jsr calc_window
        jmp commit

set_palette:                        ; beebgame's: logical 0..3 = K C M Y
        ldx #15
:       txa
        lsr
        lsr
        and #2
        adc #0
        tay
        txa
        asl
        asl
        asl
        asl
        ora @cmyk,y
        sta PALQ,x
        dex
        bpl :-
        lda #1                      ; (loaded at the vsync: no change mid-field)
        sta palreq
        rts
@cmyk:  .byte 0^7, 6^7, 5^7, 3^7

blank_palette:
        lda #0                ; (stz)
        sta palreq                ; (stz)
        lda #$F7
        sec
:       sta ULA_PAL
        sbc #$10
        bcs :-
        rts

flash_palette:                      ; every colour but black white: the crash
        ldx #15
:       txa
        and #$0A                    ; the index bits a MODE 1 pixel drives
        beq :+
        lda #0                      ; white (physical 7, inverted)
        .byte $2C
:       lda #7                      ; black
        sta tmp
        txa
        asl
        asl
        asl
        asl
        ora tmp
        sta PALQ,x
        dex
        bpl :--
        lda #1
        sta palreq
        rts

; ---------------------------------------------------------------- window state
; Per window (X = 0 top, 1 bottom), in zero page:
;   wx, wy      the camera, in world pixels and lines (wx a multiple of 4, wy even)
;   wcx, wcy, wf  wx / 4, wy / 8, wy & 7
;   ringS       the ring character of the window's top-left
;   vcx, vcy    the camera the ring's contents are drawn for
;   cslot, cpos the composed row's spare ring row (20 or 26 rows on), its ring char
; calc_window: wcx, wcy, wf, ringS from wx, wy
        .segment "LOWX"
calc_window:
        lda wxh,x
        lsr
        sta wcxh,x
        lda wxl,x
        ror
        lsr wcxh,x
        ror
        sta wcxl,x
        lda wyl,x
        and #7
        sta wf,x
        lda wyh,x
        lsr
        sta tmp
        lda wyl,x
        ror
        lsr tmp
        ror
        lsr tmp
        ror
        sta wcy,x
        cpx #1                      ; (W1's world row table follows W0's)
        bcc :+
        adc #RMODN-1
:       tay
        clc
        lda RMODL,y
        adc wcxl,x
        sta ringSl,x
        lda RMODH,y
        adc wcxh,x
        sta ringSh,x
        lda ringSl,x                ; folded: less the ring's length if past it
        sec
        sbc RCHL,x
        tay
        lda ringSh,x
        sbc RCH,x
        bcc :+
        sta ringSh,x
        tya
        sta ringSl,x
:       rts

; w16 (a ring char offset, < 2 x RINGCH) -> A (hi), Y (lo) = its CRTC address
        .segment "CODE"
crtc_of:                            ; (X = the window)
        lda w16                     ; folded: less the ring's length if past it
        sec
        sbc RCHL,x
        tay
        lda w16+1
        sbc RCH,x
        bcs :+
        ldy w16
        lda w16+1
:       sta crth
        tya
        clc
        adc RCRTCL,x
        tay
        lda crth
        adc RCRTC,x
        rts

; w16 = ringS(X) + rows * 80, rows in A
ring_plus:
        tay
        clc
        lda ringSl,x
        adc RMULL,y
        sta w16
        lda ringSh,x
        adc RMULH,y
        sta w16+1
        rts

; ---------------------------------------------------------------- commit
; X = the window: its seven or so entry bytes from its state, and its cursor.  The
; top window also sets what the vsync programs; the bottom sets the next-section
; fields of entry 2 (W0's last), which hand the chain over to it.
        .segment "LOWX"
; A = lines -> tmp, tmp+1 = lines x 64 - 2 (a T1 count)
dur:    pha
        lda #0                ; (stz)
        sta tmp+1                ; (stz)
        pla                ; (stz)
        asl
        asl
        rol tmp+1
        asl
        rol tmp+1
        asl
        rol tmp+1
        asl
        rol tmp+1
        asl
        rol tmp+1
        sec
        sbc #2
        sta tmp
        bcs :+
        dec tmp+1
:       rts

commit:
        stx win
        lda #0
        cpx #0
        beq :+
        lda w1x
:       sta cbase                   ; this window's first entry
        ; ---- A: the composed row (f > 0) or row 0
        lda wf,x
        beq @a0
        eor #7
        sta cr9                     ; 7 - f
        lda cposl,x
        sta w16
        lda cposh,x
        sta w16+1
        lda mach                    ; (the Model B: its composed rows are outside
        beq @a1                     ;  the rings, cpos their CRTC address)
        lda cposh,x
        ldy cposl,x
        jmp @a2
@a0:    lda ringSl,x
        sta w16
        lda ringSh,x
        sta w16+1
        lda #7
        sta cr9
@a1:    jsr crtc_of
@a2:    sta caddr
        sty caddr+1
        lda wf,x                    ; A's lines: 8 - f (f = 0: 8)
        eor #7
        clc
        adc #1
        jsr dur                     ; tmp/tmp+1 = the T1 count
        ldx win
        bne @w1a
        lda vsbuf                   ; the vsync's four, in the copy it is not reading
        eor #4
        and #4                      ; (BSS starts as whatever was there)
        tay
        lda tmp
        sta VSB,y
        lda tmp+1
        sta VSB+1,y
        lda caddr
        sta VSB+2,y
        lda caddr+1
        sta VSB+3,y
        sty vsbuf
        jmp @shapeA
@w1a:   ldy cbase                   ; the bottom window's A: the next fields of the
        lda tmp                     ; entry before it (W0's last), LEAD us longer
        clc                         ; (its step fired that early)
        adc #LEAD
        sta SECTAB-8+E_T1L,y
        lda tmp+1
        adc #0
        sta SECTAB-8+E_T1H,y
        lda caddr
        sta SECTAB-8+E_R12,y
        lda caddr+1
        sta SECTAB-8+E_R13,y
@shapeA:
        ldy cbase
        lda #0
        sta SECTAB+E_R4,y
        sta SECTAB+E_R5,y
        lda cr9
        sta SECTAB+E_R9,y
        txa
        ora #30
        sta SECTAB+E_R6,y
        ; ---- P: rows 1..15, then (vertical adjust) row 16's top f lines; its
        ; address and duration go in A's entry.  It ends LEAD us early: the next
        ; step (W1's, or Q's) switches ACCCON D in this line's blanking.
        lda #1
        jsr ring_plus
        jsr crtc_of
        ldx cbase
        sta SECTAB+E_R12,x
        tya
        sta SECTAB+E_R13,x
        ldx win
        lda wf,x
        clc
        adc #120
        jsr dur
        ldx cbase
        lda tmp
        sec
        sbc #LEAD
        sta SECTAB+E_T1L,x
        lda tmp+1
        sbc #0
        sta SECTAB+E_T1H,x
        lda #14
        sta SECTAB+8+E_R4,x
        lda #7
        sta SECTAB+8+E_R9,x
        lda win
        ora #30
        sta SECTAB+8+E_R6,x
        ldy win
        lda wf,y
        sta SECTAB+8+E_R5,x
        ldx win
        lda mach                    ; the Model B: P split where the ring wraps
        beq :+
        jsr split
:       ; ---- the cursor (the glint), computed by the logic
        ldx win
        txa
        asl
        asl
        asl
        asl
        tay
        lda glr14,x
        sta CURS,y
        lda glr15,x
        sta CURS+1,y
        lda glr10,x
        sta CURS+2,y
        lda glr11,x
        sta CURS+3,y
        lda glr14,x                 ; (no lower row without an upper)
        beq :+
        lda g2r14,x
:       sta CURS+4,y
        lda g2r15,x
        sta CURS+5,y
        lda g2r11,x
        sta CURS+6,y
        lda g2tl,x
        sta CURS+7,y
        lda g2th,x
        sta CURS+8,y
        lda CURS,y                  ; (the Model B's P2 step keeps the cursor)
        ldx CURS+9,y
        sta R14V,x
        rts

        .segment "CODE"
; The Model B: no ring has the hardware's wrap, so a window's P section is two, P1
; rows 1..k and P2 the rest, k the row that crosses the ring's end (which reads on
; into the mirror of the ring's first row); P2 starts at the ring's start.  P2
; always has at least one line: k <= 14, or 15 if row 16 shows.  X = window
;   A's entry:  P1's address and duration (8k lines)
;   P1's entry: its shape; P2's address and duration (less LEAD: the next step
;               fires early)
;   P2's entry: its shape (the next section's address and duration are W1's
;               commit's, or init_chain's)
split:  jsr split_of
        sta wk,x
        asl a                       ; P1: 8k lines
        asl a
        asl a
        jsr dur
        ldy cbase
        lda tmp
        sta SECTAB+E_T1L,y
        lda tmp+1
        sta SECTAB+E_T1H,y
        lda wk,x
        sec
        sbc #1
        sta SECTAB+8+E_R4,y         ; P1: k rows
        lda #0
        sta SECTAB+8+E_R5,y
        lda wk,x                    ; P2's address: row k + 1's, folded
        clc
        adc #1
        jsr ring_plus
        jsr crtc_of
        ldx cbase
        sta SECTAB+8+E_R12,x
        tya
        sta SECTAB+8+E_R13,x
        ldx win
        lda #15                     ; n2 = 15 - k full rows, then f lines
        sec
        sbc wk,x
        sta tmp+2
        asl a
        asl a
        asl a
        clc
        adc wf,x
        jsr dur
        ldy cbase
        lda tmp
        sec
        sbc #LEAD
        sta SECTAB+8+E_T1L,y
        lda tmp+1
        sbc #0
        sta SECTAB+8+E_T1H,y
        txa
        ora #30
        sta SECTAB+16+E_R6,y
        lda tmp+2
        beq @one
        sec                         ; n2 rows, then the adjust's f lines
        sbc #1
        sta SECTAB+16+E_R4,y
        lda #7
        sta SECTAB+16+E_R9,y
        lda wf,x
        sta SECTAB+16+E_R5,y
        rts
@one:   lda #0                      ; row 16 alone: f lines (f > 0 here)
        sta SECTAB+16+E_R4,y
        sta SECTAB+16+E_R5,y
        lda wf,x
        sec
        sbc #1
        sta SECTAB+16+E_R9,y
        rts

; X = window (kept): A = k, the row its P section splits after (the Model B): the
; row that crosses its ring's end, if one of rows 1..14 does; 15 for row 15 if
; row 16 shows; else 14 (rows 15 and 16 read on into the mirror); 8 if none does
split_of:
        lda ringSl,x                ; e = length - (ringS + rowch): what of the ring
        clc                         ; is left from row 1's start
        adc rowch
        sta sxl
        lda ringSh,x
        adc #0
        sta sxh
        lda RCHL,x
        sec
        sbc sxl
        sta sxl
        lda RCH,x
        sbc sxh
        sta sxh
        bmi @k8
        ora sxl
        beq @k8
        lda sxl                     ; w = rows that start before the end: ceil(e / 80)
        bne :+                      ; = (e - 1) / 16 / 5 + 1
        dec sxh
:       dec sxl
        lda sxl
        lsr sxh
        ror a
        lsr sxh
        ror a
        lsr sxh
        ror a
        lsr sxh
        ror a
        ldy #1
        sec
@c:     sbc #5
        bcc @w
        iny
        bcs @c
@w:     cpy #15
        bcc @kw
        bne @k14
        lda wf,x
        beq @k14
        lda #15
        rts
@kw:    tya
        rts
@k14:   lda #14
        rts
@k8:    lda #8                      ; (row 0 may cross)
        rts


; ---------------------------------------------------------------- ring access
; X = window: point the CPU's $3000-$7FFF at its ring (ACCCON X: shadow for W1).
; The interrupt writes ACCCON's D bit, so the read-modify-write is atomic.
selwin:
        lda RBASE,x                 ; its ring's parameters, for the drawing
        sta rbase
        lda RTOP,x
        sta rtop
        sec
        sbc #1
        sta rtopm1
        lda RSIZE,x
        sta rsize
        lda RCH,x
        sta rch
        lda RCHL,x
        sta rchl
        lda mach                    ; (the Master: 0)
        beq :+
        lda rbase
        clc
        adc #2
:       sta rmir
        lda #0
        cpx #1
        bcc :+
        lda #RMODN
:       sta rmoff
selacc: cpx selcur                  ; (the Model B: rts, patched)  Only when it
        beq :++                     ; changes: the read-modify-write must hold the
        stx selcur                  ; interrupt off (its steps write ACCCON's D), and
        php                         ; that delays a step
        sei
        lda ACCCON
        and #$FB
        cpx #0
        beq :+
        ora #$04
:       sta ACCCON
        plp
:       rts

; rp = the ring address of map character (cx, cy): RING + 8 x ((cy mod 32) x 80 +
; cx) mod 2560
ringaddr:
        lda cy
        clc
        adc rmoff
        tay
        clc
        lda RMODL,y
        adc cx
        sta rp
        lda RMODH,y
        adc cx+1
        cmp rch                     ; folded: less the ring's length if past it
        bcc @ok
        bne :+
        ldy rp
        cpy rchl
        bcc @ok
:       tay                         ; (C = 1)
        lda rp
        sbc rchl
        sta rp
        tya
        sbc rch
@ok:    asl rp
        rol a
        asl rp
        rol a
        asl rp
        rol a
        adc rbase                   ; C = 0: r x 8 < $8000
        sta rp+1
        rts

; mp = the map byte of (cx, cy); half = 8 for the tile's bottom character row
mapaddr:
        lda cy
        lsr
        tay
        lda #0
        rol a
        asl a
        asl a
        asl a
        sta half
        clc
        lda MAPROWL,y
        adc cx
        sta mp
        lda MAPROWH,y
        adc cx+1
        sta mp+1
        rts

.macro COPY8
        .repeat 7, I
        lda (tp),y
        sta (rp),y
        dey
        .endrepeat
        lda (tp),y
        sta (rp),y
.endmacro
.macro MIRW                         ; (after COPY8: into the mirror too, if need be)
        lda rp+1                    ; (no labels: they would end the routine's @ scope)
        cmp rmir
        bcc *+8                     ; -> jsr
        bne *+9                     ; -> past it
        lda rp
        bmi *+5
        jsr mir8
.endmacro

; the Model B: a character just drawn in its ring's first row, in the mirror too
mir8:   lda rp+1
        pha
        clc
        adc rsize
        sta rp+1
        ldy #7
        COPY8
        pla
        sta rp+1
        rts

; A = a byte just stored at (rp),y: in the mirror too, if rp is in the ring's
; first row (the Model B).  A, X, Y kept
mir1:   sta mv
        lda rp+1
        cmp rmir
        bcc :+
        bne @x
        lda rp
        bmi @x
:       lda rp+1
        clc
        adc rsize
        sta rp+1
        lda mv
        sta (rp),y
        lda rp+1
        sec
        sbc rsize
        sta rp+1
@x:     lda mv
        rts

; draw map character (cx, cy) into the selected ring
draw_char:
        jsr mapaddr
        jsr ringaddr
        ldy #0
        lda (mp),y
        tax
        lda TLO,x
        ora half
        sta tp
        lda THI,x
        sta tp+1
        ldy #7
        COPY8
        MIRW
        rts

; draw rows characters of map column cx from row cy down
draw_col:
        jsr mapaddr
        jsr ringaddr
@lp:    ldy #0
        lda (mp),y
        tax
        lda TLO,x
        ora half
        sta tp
        lda THI,x
        sta tp+1
        ldy #7
        COPY8
        MIRW
        lda half                    ; the tile's other half, or the next tile row
        eor #8
        sta half
        bne :+
        lda mp
        clc
        adc #<MAPW
        sta mp
        lda mp+1
        adc #>MAPW
        sta mp+1
:       lda rp                      ; the next character row: + rowch x 8, folded
        clc
        adc rowb
        sta rp
        lda rp+1
        adc rowb+1
        cmp rtop
        bcc :+
        sbc rsize
:       sta rp+1
        dec rows
        bne @lp
        rts

; draw cnt characters of map row cy from cx rightwards
draw_row:
        jsr mapaddr
        jsr ringaddr
@lp:    ldy #0
        lda (mp),y
        tax
        lda TLO,x
        ora half
        sta tp
        lda THI,x
        sta tp+1
        ldy #7
        COPY8
        MIRW
        inc mp
        bne :+
        inc mp+1
:       lda rp
        clc
        adc #8
        sta rp
        bcc :+
        inc rp+1
        lda rp+1
        cmp rtop
        bcc :+
        lda rbase
        sta rp+1
:       dec cnt
        bne @lp
        rts

; X = window: draw its whole held area (17 rows) and make it valid
redraw_window:
        stx win
        jsr selwin
        ldx win
        lda wcy,x
        sta cy
        lda #HELD
        sta rows
@r:     ldx win
        lda wcxl,x
        sta cx
        lda wcxh,x
        sta cx+1
        lda rowch
        sta cnt
        jsr draw_row
        inc cy
        dec rows
        bne @r
        ldx win
        lda wcxl,x
        sta vcxl,x
        lda wcxh,x
        sta vcxh,x
        lda wcy,x
        sta vcy,x
        rts

; X = window, prep phase: the new row's middle 78 characters, which the frame on
; screen never shows (it is the ring row just below or above the held rows)
prep_window:
        stx win
        lda wcy,x
        cmp vcy,x
        beq @no
        bcc @up
        clc                         ; down: the new bottom row
        adc #HELD-1
@up:    sta cy
        jsr selwin
        ldx win
        clc
        lda wcxl,x
        adc #1
        sta cx
        lda wcxh,x
        adc #0
        sta cx+1
        lda rowm1
        sec
        sbc #1
        sta cnt
        jmp draw_row
@no:    rts

; X = window, its off time: the new column, the new row's two ends, the changed
; tiles; then the composed row, and the commit.
crit_window:
        stx win
        txa
        beq @w0
        ; ---- W1 commits first: entry 1 (read at W0's P step, line ~2) holds its A.
        ; Between line 256 and 300, or wait for the next field's.
:       jsr beam
        cmp #128
        bcc :-
        cmp #150
        bcs :-
        ldx #1
        lda wf+1
        beq :+
        jsr compose_slot
:       ldx #1
        jsr commit
        ldx #1
        jmp @draw
@w0:    lda wf                      ; W0 commits first too (its entries are not
        beq :+                      ; read until the vsync; what they show is drawn
        jsr compose_slot            ; by then, and the composed row by line 312)
:       ldx #0
        jsr commit
        ldx #0
@draw:  jsr selwin
        ldx win
        ; ---- the new column (every held row)
        lda wcxl,x
        cmp vcxl,x
        bne :+
        lda wcxh,x
        cmp vcxh,x
        beq @nocol
:       lda wcxl,x                  ; right: column wcx + 79; left: column wcx
        sec
        sbc vcxl,x
        lda wcxh,x
        sbc vcxh,x
        bmi @left
        lda wcxl,x
        clc
        adc rowm1
        sta cx
        lda wcxh,x
        adc #0
        sta cx+1
        jmp @col
@left:  lda wcxl,x
        sta cx
        lda wcxh,x
        sta cx+1
@col:   lda wcy,x
        sta cy
        lda #HELD
        sta rows
        jsr draw_col
        ldx win
@nocol: ; ---- the new row's ends
        lda wcy,x
        cmp vcy,x
        beq @norow
        bcc :+
        clc
        adc #HELD-1
:       sta cy
        lda wcxl,x
        sta cx
        lda wcxh,x
        sta cx+1
        jsr draw_char
        ldx win
        lda wcxl,x
        clc
        adc rowm1
        sta cx
        lda wcxh,x
        adc #0
        sta cx+1
        jsr draw_char
        ldx win
@norow: lda wcxl,x
        sta vcxl,x
        lda wcxh,x
        sta vcxh,x
        lda wcy,x
        sta vcy,x
        ; ---- the changed tiles in the top rows (the composed row's), and the
        ; glint's black over any head among them; then the composed row, which
        ; is shown first; then the other tiles and the glint, which are shown
        ; 24 lines or more later, so may finish a little after the window starts
        lda #0
        sta ddrawn
        sta dlo
        lda #4
        sta dhi
        jsr draw_dirty
        ldx win
        lda ddrawn
        beq :+
        jsr glint_poke
        ldx win
:       lda wf,x                    ; the composed row, into the row the screen is
        beq :+                      ; not showing
        jsr compose_copy
cc_done:
:       lda #4
        sta dlo
        lda #HELD+1
        sta dhi
        jsr draw_dirty
        ldx win                     ; the glint's black, over the heads just drawn
        jsr glint_poke
        ; ---- the explosion, if any: last, as long as the beam allows (it never
        ; touches row 0, so the composed row stays right)
        jmp fx_window

; the composed row: lines f..7 of the window's top row, at ring row 20 or 26
; below it (alternately, so the one on screen is never written).  Copied in
; chunks of up to 32 characters between the ring's ends, by an unrolled loop of
; absolute,Y pairs whose operands are set per chunk and which is entered at the
; pair for line 7 - f.
compose:
        jsr compose_slot
        jmp compose_copy
compose_slot:                       ; the other spare row: cpos
        lda cslot,x
        eor #1
        sta cslot,x
        tay
        lda mach                    ; the Model B: its row outside the ring (one: it
        beq :+                      ; is written in the window's off time), cpos its
        lda @bl,x                   ; CRTC address
        sta cposl,x
        lda @bh,x
        sta cposh,x
        rts
:       tya
        beq :+
        lda CSL1,x
        jmp :++
:       lda CSL0,x
:       jsr ring_plus
        lda w16+1                   ; fold
        cmp RCH,x
        bcc :+
        sbc RCH,x
        sta w16+1
:       lda w16
        sta cposl,x
        lda w16+1
        sta cposh,x
        rts
@bl:    .byte <(CBUF0B/8), <(CBUF1B/8)
@bh:    .byte >(CBUF0B/8), >(CBUF1B/8)
        .segment "LOWX"
compose_copy:
        lda cposl,x
        sta da
        lda cposh,x
        asl da                      ; da = RING + 8 x cpos
        rol a
        asl da
        rol a
        asl da
        rol a
        sta da+1
        lda mach                    ; (the Model B: cpos x 8 itself)
        bne :+
        lda da+1
        adc rbase
        sta da+1
:
        lda ringSl,x                ; sa = RING + 8 x ringS + f
        sta sa
        lda ringSh,x
        asl sa
        rol a
        asl sa
        rol a
        asl sa
        rol a
        adc rbase
        sta sa+1
        lda sa
        ora wf,x
        sta sa
        lda wf,x                    ; enter at pair f (pairs run line 7 down to 0)
        asl a
        adc wf,x
        asl a                       ; x 6 bytes a pair
        adc #<cpairs
        sta cploop+1
        lda #>cpairs
        adc #0
        sta cploop+2
        lda rowch
        sta cnt                     ; characters left
@chunk: lda #32                     ; this chunk: at most 32, and not past either
        sta rows                    ; pointer's wrap
        lda sa+1
        cmp rtopm1
        bne :+
        lda sa
        lsr a
        lsr a
        lsr a
        eor #$1F
        clc
        adc #1                       ; 32 - (lo >> 3)
        sta rows
:       lda da+1
        cmp rtopm1
        bne :+
        lda da
        lsr a
        lsr a
        lsr a
        eor #$1F
        clc
        adc #1
        cmp rows
        bcs :+
        sta rows
:       lda cnt
        cmp rows
        bcs :+
        sta rows
:       ; the operands: pair l reads sa + l, writes da + l (the pairs run: 7 - f..0)
        ldx win
        lda wf,x
        sta tmp+2
        asl a
        adc tmp+2
        asl a
        tay                         ; pair f's offset: 6f
        lda #7
        sec
        sbc tmp+2
        tax
:       txa
        clc
        adc sa
        sta cpairs+1,y
        lda sa+1
        adc #0
        sta cpairs+2,y
        txa
        clc
        adc da
        sta cpairs+4,y
        lda da+1
        adc #0
        sta cpairs+5,y
        tya
        adc #6
        tay
        dex
        bpl :-
        ldx rows
        ldy #0
        jsr cploop
        ; advance both by the chunk
        lda rows
        asl a
        asl a
        asl a
        sta tmp
        lda #0
        rol a
        sta tmp+1                   ; chunk x 8
        lda sa
        clc
        adc tmp
        sta sa
        lda sa+1
        adc tmp+1
        cmp rtop
        bcc :+
        sbc rsize
:       sta sa+1
        lda da
        clc
        adc tmp
        sta da
        lda da+1
        adc tmp+1
        cmp rtop
        bcc :+
        sbc rsize
:       sta da+1
        lda cnt
        sec
        sbc rows
        sta cnt
        beq :+
        jmp @chunk
:       ldx win
        rts
cploop: jmp cpairs                  ; (patched: the pair for line 7 - f)
cpairs: .repeat 8, L
        lda $FFFF,y
        sta $FFFF,y
        .endrepeat
        tya
        clc
        adc #8
        tay
        dex
        bne cploop
        rts

; X = window: clear its ring (all 32 rows)
        .segment "CODE"
clear_ring:
        jsr selwin
        lda rbase
        sta rp+1
        lda #0                ; (stz)
        sta rp                ; (stz)
        lda #0
        ldy #0
:       sta (rp),y
        iny
        bne :-
        inc rp+1
        ldx rp+1
        cpx rtop
        bne :-
        rts

; the Model B: a window's (X) ring's first characters again after its end, for
; the row that crosses the end (split).  After anything is drawn in the ring.
        .segment "CODEB"
mirror_all:                         ; (both windows, a whole row)
        ldx #0
        lda rowch
        jsr mirror_n
        ldx #1
        lda rowch
mirror_n:                           ; A characters
        ldy mach
        bne :+
        rts
:       sta tmp                     ; x 8 bytes: tmp+1 pages, tmp more
        lda #0
        sta tmp+1
        asl tmp
        rol tmp+1
        asl tmp
        rol tmp+1
        asl tmp
        rol tmp+1
        lda RBASE,x
        sta sa+1
        lda RTOP,x
        sta da+1
        ldy #0
        sty sa
        sty da
        ldx tmp+1
        beq @part
@pg:    .repeat 8
        lda (sa),y
        sta (da),y
        iny
        .endrepeat
        bne @pg
        inc sa+1
        inc da+1
        dex
        bne @pg
@part:  lda tmp
        beq @r
@lp:    .repeat 8
        lda (sa),y
        sta (da),y
        iny
        .endrepeat
        cpy tmp
        bne @lp
@r:     rts

        .segment "CODEB"
; the machine's geometry: the rings, the chain's indices, the tables
geom_init:
        ldy #0                      ; (Y: the Master's values, or the Model B's)
        lda mach
        beq :+
        ldy #@gb-@gm
:       ldx #0
:       lda @gm,y
        sta RBASE,x
        iny
        inx
        cpx #GEOMN
        bne :-
        lda @gm,y                   ; then: Q's blank line (hi, lo), the P2s' R14V
        sta qbl                     ; entries (the Master's: the dummy), FXNEED,
        lda @gm+1,y                 ; GT0, W1's first entry, Q's
        sta qbl+1
        lda @gm+2,y
        sta CURS+9
        lda @gm+3,y
        sta CURS+16+9
        lda @gm+4,y
        sta fxneed
        clc
        adc @gm+9,y
        sta fxneed+1
        lda @gm+5,y
        sta gt0
        lda @gm+6,y
        sta gt0+1
        lda @gm+7,y
        sta w1x
        clc
        adc #8
        sta p1w1
        lda @gm+8,y
        sta qidx
        lda #17                     ; (no split yet)
        sta wk
        sta wk+1
        lda #0
        sta txoff
        lda #ROWCH
        jmp geom_tables
        ; RBASE, RTOP, RSIZE, RCH, RCHL, RCRTC, RCRTCL, CSL0, CSL1 (x 2), then the rest
@gm:    .byte >RING, >RING, $80, $80, >(RINGCH*8), >(RINGCH*8), >RINGCH, >RINGCH
        .byte <RINGCH, <RINGCH, >CRTCB, >CRTCB, <CRTCB, <CRTCB, 19, 19, 21, 21
        .byte >(QBLANK/8), <(QBLANK/8), 7*8, 7*8, FXNEED, <GT0, >GT0, 2*8, 4*8, 0
@gb:    .byte >RING0B, >RING1B, >(RING0B+RINGBCH*8), >(RING1B+RINGBCH*8)
        .byte >(RINGBCH*8), >(RINGBCH*8), >RINGBCH, >RINGBCH
        .byte <RINGBCH, <RINGBCH, >(RING0B/8), >(RING1B/8), <(RING0B/8), <(RING1B/8)
        .byte 0, 0, 0, 0
        .byte >(QBLANKB/8), <(QBLANKB/8), 2*8, 5*8, FXNEEDB, <GT0B, >GT0B, 3*8, 6*8, 6
        ; ---- from here on, any machine: rowch in A
geom_tables:
        sta rowch
        sec
        sbc #1
        sta rowm1
        lda rowch                   ; rowb = rowch x 8, rowb7 = rowb - 7
        sta rowb
        lda #0
        sta rowb+1
        asl rowb
        rol rowb+1
        asl rowb
        rol rowb+1
        asl rowb
        rol rowb+1
        lda rowb
        sec
        sbc #7
        sta rowb7
        lda rowb+1
        sbc #0
        sta rowb7+1
        lda rowch                   ; wpx = rowch x 4, halfw, maxwx = WORLDW - wpx
        sta wpx
        lda #0
        sta wpx+1
        asl wpx
        rol wpx+1
        asl wpx
        rol wpx+1
        lda wpx+1
        lsr a
        lda wpx
        ror a
        sta halfw
        lda #<WORLDW
        sec
        sbc wpx
        sta maxwx
        lda #>WORLDW
        sbc wpx+1
        sta maxwx+1
        ldx #0                      ; RMUL: r x rowch
        stx tmp
        stx tmp+1
:       lda tmp
        sta RMULL,x
        lda tmp+1
        sta RMULH,x
        lda tmp
        clc
        adc rowch
        sta tmp
        bcc :+
        inc tmp+1
:       inx
        cpx #33
        bne :--
        ; RMOD, each window: r x rowch, less the ring's length while it is past it
        ldy #0                      ; (table index)
        ldx #0                      ; (window)
@w:     lda #0
        sta tmp
        sta tmp+1
        lda #RMODN
        sta cnt
@r:     lda tmp
        sta RMODL,y
        lda tmp+1
        sta RMODH,y
        iny
        lda tmp
        clc
        adc rowch
        sta tmp
        bcc :+
        inc tmp+1
:       lda tmp                     ; folded
        sec
        sbc RCHL,x
        pha
        lda tmp+1
        sbc RCH,x
        bcc :+
        sta tmp+1
        pla
        sta tmp
        jmp :++
:       pla
:       dec cnt
        bne @r
        inx
        cpx #2
        bne @w
        rts
