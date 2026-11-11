; ============================================================================
; Effects drawn straight into the rings: the explosion's squares (XOR lines) and
; text.  Both are drawn only while nothing scrolls or grows: after a crash, and on
; the still screens.
; ============================================================================

; ---------------------------------------------------------------- explosion
; EXN fragments of the crashed bike: small filled quads thrown up and out, falling
; under gravity, bouncing and sliding to rest (tools/gen.py simulates them and
; rasterises each frame to spans).  Each window, each tick, in one go if the beam
; allows: every fragment it shows put back to the floor (its box of characters
; redrawn from the map), then this tick's drawn with the memo's replace rule.

; this tick's fragments from bank 5 into EXNEW
        .segment "CODEB"
fx_load:                            ; (in the code bank, with them)
        lda fxt                     ; sa = exbase + fxt x 96 (EXN x EXW)
        sta sa
        lda #0
        sta sa+1
        asl sa                      ; x 32
        rol sa+1
        asl sa
        rol sa+1
        asl sa
        rol sa+1
        asl sa
        rol sa+1
        asl sa
        rol sa+1
        lda sa                      ; x 3
        asl a
        sta tmp
        lda sa+1
        rol a
        sta tmp+1
        lda sa
        clc
        adc tmp
        sta sa
        lda sa+1
        adc tmp+1
        clc
        adc exbase
        sta sa+1
        ldy #EXN*EXW-1
:       lda (sa),y
        sta EXNEW,y
        dey
        bpl :-
        rts

; the logic's step: the next frame; at the end, nothing new until both windows
; have put theirs back, then off
fx_tick:
        lda fxt
        cmp #$FF
        beq @r
        cmp #EXT
        bcc @adv
        ldx #2*EXN-1
:       lda EXFRM,x
        cmp #$FF
        bne @r
        dex
        bpl :-
        lda #$FF
        sta fxt
        rts
@adv:   clc
        adc #1
        sta fxt
        cmp #EXT
        bcs @none
        cmp #2
        bne :+
        jsr set_palette             ; the flash is two ticks
:       jmp fx_load
@none:  ldy #EXN*EXW-1
        lda #0
:       sta EXNEW,y
        dey
        bpl :-
@r:     rts

; X = window (win)
        .segment "CODE"
fx_window:
        lda fxt
        cmp #$FF
        bne :+
        rts
:       jsr fx_time                 ; no time: this window keeps last tick's frame
        bcc @sk
        ldx win                     ; (and W0 gives way to W1 if W1 missed its last
        bne :+                      ;  and W0 did not: under load they take turns)
        lda fxsk+1
        beq :+
        lda fxsk
        beq @sk
:       lda #0
        sta fxsk,x
        jmp @go
@sk:    ldx win
        inc fxsk,x
        rts
@go:    pha                         ; ---- what it shows, back to the floor
        lda #0                ; (stz)
        sta glph                ; (stz)
        pla                ; (stz)
@er:    jsr fx_idx
        lda EXFRM,x
        cmp #$FF
        beq @ne
        lda #$FF
        sta EXFRM,x
        txa
        asl a
        asl a
        tax
        lda EXBOX+3,x
        sta fxe                     ; last char row
        lda EXBOX+2,x
        sta fxc                     ; char row
        lda EXBOX+1,x
        sec
        sbc EXBOX,x
        clc
        adc #1
        sta fxn                     ; chars a row
        lda EXBOX,x
        sta btmp                    ; first column
@row:   ldx win
        lda btmp
        clc
        adc wcxl,x
        sta cx
        lda wcxh,x
        adc #0
        sta cx+1
        lda fxc
        clc
        adc wcy,x
        sta cy
        lda fxn
        sta cnt
        jsr draw_row
        lda fxc
        inc fxc
        cmp fxe
        bcc @row
@ne:    inc glph
        lda glph
        cmp #EXN
        bcc @er
        pha                         ; ---- this tick's
        lda #0                ; (stz)
        sta glph                ; (stz)
        pla                ; (stz)
@dr:    CALLB fx_frag
        inc glph
        lda glph
        cmp #EXN
        bcc @dr
        rts

; X = this window's fragment glph (win x EXN + glph)
fx_idx: lda win
        beq :+
        lda #EXN
:       clc
        adc glph
        tax
        rts

; C = 1 if there is time to redo window win's fragments before it is shown
FXNEED = 60                         ; half lines (120 lines: measured at most 111)
FXNEEDB = FXNEED + 6                ; (the Model B: the mirror's writes too)
fx_time:
        jsr beam
        sta tmp
        ldx win
        lda fxdl,x
        sec
        sbc tmp
        bcs :+
        adc #156
:       cmp fxmax,x                 ; beyond: the beam is in (or before) the window
        bcs @no
        cmp fxneed,x
        rts
@no:    clc
        rts
fxdl:   .byte 144, 56               ; deadlines (half lines): W0 line 288, W1 line 112
fxmax:  .byte 81, 85                ; how far ahead of them the off time starts

; fragment glph: drawn if it lies wholly in the window below its top character row
        .segment "CODEB"
fx_frag:
        ldx glph
        ldy fxoff,x
        lda EXNEW,y
        bne :+
        rts
:       sta lcnt                    ; lines
        sty fxe
        lda glph                    ; the impact, and its bike's colour
        and fxmask
        tax
        lda #$0F                    ; cyan
        sta xlmc
        sta xlmc+1
        lda fxteam,x
        cmp #2
        bne :+
        lda #$FA                    ; orange: yellow on even pixels of even lines,
        sta xlmc                    ; magenta on odd (the blades' dither)
        lda #$F5
        sta xlmc+1
:       txa
        asl a
        tax
        lda fxox,x                  ; w16 = impact x - 4 wcx, tmp = impact y - 8 wcy
        sta w16
        lda fxox+1,x
        sta w16+1
        lda fxoy,x
        sta tmp
        lda fxoy+1,x
        sta tmp+1
        ldx win
        lda wcxl,x
        sta tmp+2
        lda wcxh,x
        asl tmp+2
        rol a
        asl tmp+2
        rol a
        sta cnt
        lda w16
        sec
        sbc tmp+2
        sta w16
        lda w16+1
        sbc cnt
        sta w16+1
        lda wcy,x                   ; (< 64)
        pha
        lda #0                ; (stz)
        sta cnt                ; (stz)
        pla                ; (stz)
        asl a
        asl a
        asl a
        rol cnt
        sta tmp+2
        lda tmp
        sec
        sbc tmp+2
        sta tmp
        lda tmp+1
        sbc cnt
        sta tmp+1
        jmp @box
@rx:    rts
@box:
        ldy fxe                     ; ---- the box: lines 8..135, x 0..319
        lda EXNEW+1,y
        ldx #0
        cmp #$80
        bcc :+
        dex
:       clc
        adc tmp
        sta ly0
        txa
        adc tmp+1
        bne @rx
        lda ly0
        cmp #8
        bcc @rx
        clc
        adc lcnt
        bcs @rx
        cmp #HELD*8+1
        bcs @rx
        lda EXNEW+2,y
        jsr fx_x
        bcs @rx
        jsr fx_col
        sta btmp
        lda EXNEW+3,y
        jsr fx_x
        bcs @rx
        jsr fx_col
        sta fxc
        jsr fx_idx                  ; drawn: its frame and box of characters
        lda fxt
        sta EXFRM,x
        txa
        asl a
        asl a
        tax
        lda btmp
        sta EXBOX,x
        lda fxc
        sta EXBOX+1,x
        lda ly0
        lsr a
        lsr a
        lsr a
        sta EXBOX+2,x
        lda ly0
        clc
        adc lcnt
        sbc #0                      ; (C = 0: - 1)
        lsr a
        lsr a
        lsr a
        sta EXBOX+3,x
        lda fxe
        clc
        adc #4
        sta fxe
        ; ---- the spans: rp steps down the box's first byte column, line by line
        ldx win
        lda btmp
        clc
        adc wcxl,x
        sta cx
        lda wcxh,x
        adc #0
        sta cx+1
        lda ly0
        lsr a
        lsr a
        lsr a
        clc
        adc wcy,x
        sta cy
        jsr ringaddr
        lda ly0
        and #7
        sta lsy                     ; the line in the character
        ora rp
        sta lx0                     ; lx0: the line's start
        lda rp+1
        sta lx0+1
        lda ly0
        and #1
        tax
        lda xlmc,x
        sta lcol
@sp:    ldy fxe
        lda EXNEW,y                 ; rp = the line's start + 8 x first byte
        asl a
        asl a
        asl a
        clc
        adc lx0
        sta rp
        lda lx0+1
        adc #0
        cmp rtop
        bcc :+
        sbc rsize
:       sta rp+1
        lda EXNEW+1,y
        tay
        lsr a
        lsr a
        lsr a
        lsr a
        sta lerr                    ; bytes - 1
        tya
        and #3
        tax
        lda fxrm,x
        sta ldy_                    ; the last byte's mask
        tya
        lsr a
        lsr a
        and #3
        tax
        lda fxlm,x                  ; the first's
        ldy lerr
        bne @multi
        and ldy_
        jsr @plot
        jmp @next
@multi: jsr @plot
@mid:   jsr @step
        dec lerr
        beq @last
        lda #$FF
        jsr @plot
        jmp @mid
@last:  lda ldy_
        jsr @plot
@next:  lda lcol                    ; the dither's other line
        cmp #$0F
        beq :+
        eor #$0F
        sta lcol
:       inc lsy                     ; the next line: + 1, or + 633 into the next row
        lda lsy
        cmp #8
        bcs @row8
        inc lx0
        jmp @nl
@row8:  lda #0                ; (stz)
        sta lsy                ; (stz)
        lda lx0                     ; (+ rowch x 8 - 7)
        clc
        adc rowb7
        sta lx0
        lda lx0+1
        adc rowb7+1
        cmp rtop
        bcc :+
        sbc rsize
:       sta lx0+1
@nl:    inc fxe
        inc fxe
        dec lcnt
        beq @off
        jmp @sp
@off:   rts
@plot:  sta fxm                     ; the memo's rule: (screen AND NOT m) OR (colour AND m)
        sty nm_y
        ldy #0
        lda (rp),y
        eor lcol
        and fxm
        eor (rp),y
        sta (rp),y
        ldy rp+1                    ; (the Model B: in the ring's first row, the
        cpy rmir                    ;  mirror's too)
        bcc @pm
        beq @pq
@px:    ldy nm_y
        rts
@pq:    ldy rp
        bmi @px
@pm:    ldy #0
        jsr mir1
        ldy nm_y
        rts
@step:  lda rp
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
:       rts
fxlm:   .byte $FF, $77, $33, $11    ; pixels from n to 3
fxrm:   .byte $88, $CC, $EE, $FF    ; pixels from 0 to n
fxoff:  .repeat EXN, I
        .byte I * EXW
        .endrepeat

; A = a signed offset: lx0 = w16 + A; C = 1 if outside 0..319 (X used)
fx_x:   ldx #0
        cmp #$80
        bcc :+
        dex
:       clc
        adc w16
        sta lx0
        txa
        adc w16+1
        sta lx0+1
        bmi @no
        lda lx0                     ; < wpx
        cmp wpx
        lda lx0+1
        sbc wpx+1
        bcs @no
        clc
        rts
@no:    sec
        rts
; A = lx0 >> 2 (the byte column)
fx_col: lda lx0+1
        lsr a
        lda lx0
        ror a
        lsr a
        rts

; no fragments drawn anywhere (a new round, a new crash: the rings are clean of them)
fx_clear:
        ldx #2*EXN-1
        lda #$FF
:       sta EXFRM,x
        dex
        bpl :-
        rts

; A = the beam's half line, 0..155 (line 0: the top window's first), from VIA T2,
; which the vsync restarts at $FFFF
VSHALF = 142
        .segment "CODE"
beam:   lda VIA_T2CH
        ldx VIA_T2CL
        cmp VIA_T2CH
        beq :+
        lda VIA_T2CH                ; (the low byte rolled over between)
        ldx #$FF
:       eor #$FF                    ; elapsed us = $FFFF - T2
        sta btmp
        txa
        eor #$FF
        asl a                       ; elapsed / 128
        rol btmp
        lda btmp                    ; + VSHALF, mod 156 (elapsed < 156)
        sec
        sbc #156-VSHALF
        bcs :+
        adc #156
:       rts

; ---------------------------------------------------------------- text
; Text is drawn once, in screen coordinates, and centred across: a record is the
; screen line of its top (0..255: W0 shows lines 0..127, W1 128..255), its colour
; (1..3), its scale (1: 8x8, 2: 16x16), the string, 0.  $FF ends a list.  A screen
; line belongs to whichever window shows it, and in that window to ring row
; (line + f) >> 3 from its top, line (line + f) & 7 (row 0's lines are what the
; composed row is copied from), so text may lie across the windows' join.
        .segment "CODEB"
text_list:                          ; txp = the list
        ldy #0
        lda (txp),y
        cmp #$FF
        bne :+
        rts
:       sta txy
        iny
        lda (txp),y
        sta txcol
        iny
        lda (txp),y
        sta txsc
        lda txp
        clc
        adc #3
        sta txp
        bcc :+
        inc txp+1
:       jsr draw_text
        jmp text_list

; the string at txp (left past its 0) from screen line txy, colour txcol, scale
; txsc, centred
draw_text:
        lda #$FF                    ; (@put: no line written yet)
        sta txpl
        ldy #0                      ; its width: characters x 2 x scale bytes
:       lda (txp),y
        beq :+
        iny
        bne :-
:       tya
        asl a
        ldx txsc
        cpx #2
        bne :+
        asl a
:       sta tmp
        lda rowch
        sec
        sbc tmp
        lsr a
        sta txc                     ; its first column
@ch:    ldy #0
        lda (txp),y
        inc txp
        bne :+
        inc txp+1
:       cmp #0
        bne :+
        rts
:       sec                         ; the glyph: FONTB + (c - 32) x 8
        sbc #32
        ldx #0
        stx sa+1
        asl a
        rol sa+1
        asl a
        rol sa+1
        asl a
        rol sa+1
        adc #<FONTB                 ; (C = 0)
        sta sa
        lda sa+1
        adc #>FONTB
        sta sa+1
        lda txy
        sta txl                     ; the screen line being drawn
        lda #0
        sta txg                     ; the glyph's line
@gl:    ldy txg
        lda (sa),y
        sta txb
        lda txsc
        sta txr                     ; (scale 2: each line twice)
@rep:   lda txsc
        cmp #2
        beq @wide
        lda txb                     ; scale 1: a byte a nibble
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @expand
        ldx #0
        jsr @put
        lda txb
        and #15
        jsr @expand
        ldx #1
        jsr @put
        jmp @nl
@wide:  lda txb                     ; scale 2: a byte a pixel pair
        sta tmp+2
        ldx #0
@wb:    lda tmp+2
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        tay
        lda @dbl,y
        jsr @expand
        jsr @put
        asl tmp+2
        asl tmp+2
        inx
        cpx #4
        bne @wb
@nl:    inc txl
        dec txr
        bne @rep
        inc txg
        lda txg
        cmp #8
        bne @gl
        lda txsc                    ; the next character: 2 or 4 columns on
        asl a
        clc
        adc txc
        sta txc
        jmp @ch
@dbl:   .byte 0, 3, 12, 15
; A = the byte for column txc + X of screen line txl (X kept).  The next column
; of the line last written is the ring's next character: rp + 8, folded
@put:   sta txv
        stx txx
        txa
        clc
        adc txc
        tax                         ; (the column)
        dex
        cpx txpc
        bne @full
        lda txl
        cmp txpl
        bne @full
        inx
        stx txpc
        lda rp
        clc
        adc #8
        sta rp
        bcc @wr
        inc rp+1
        lda rp+1
        cmp rtop
        bcc @wr
        lda rbase
        sta rp+1
        jmp @wr
@full:  inx
        stx txpc
        lda txl
        sta txpl
        lda txl
        ldx #0
        cmp #128
        bcc :+
        inx
        sbc #128
:       clc
        adc wf,x
        pha
        and #7
        sta txw                     ; the line in its character
        pla
        lsr a
        lsr a
        lsr a
        clc
        adc wcy,x
        sta cy
        lda txc
        clc
        adc txx
        clc
        adc wcxl,x
        sta cx
        lda wcxh,x
        adc #0
        sta cx+1
        jsr selwin
        jsr ringaddr
        lda txw
        sta txpw
@wr:    ldy txpw
        lda txv
        sta (rp),y
        jsr mir1
        ldx txx
        rts
; nibble -> the byte of txcol: high plane if colour bit 1, low if bit 0
@expand:
        sta tmp
        lda txcol
        lsr a
        lda #0
        bcc :+
        lda tmp
:       pha
        lda txcol
        and #2
        beq :+
        lda tmp
        asl a
        asl a
        asl a
        asl a
        sta tmp
        pla
        ora tmp
        rts
:       pla
        rts

; screen lines txy..txy+A-1, columns txc..txc+txn-1: the map's characters back
; (each window row those lines fall in, once)
text_erase:
        sta txr
        lda txy
        sta txl
        lda #$FF
        sta txg                     ; the last row redrawn (window x $80 + row)
@l:     lda txl
        ldx #0
        cmp #128
        bcc :+
        inx
        sbc #128
:       clc
        adc wf,x
        lsr a
        lsr a
        lsr a
        sta txw                     ; the row
        cpx #1
        bcc :+
        ora #$80
:       cmp txg
        beq @n
        sta txg
        stx win
        jsr selwin
        ldx win
        lda txw
        clc
        adc wcy,x
        sta cy
        lda txc
        clc
        adc wcxl,x
        sta cx
        lda wcxh,x
        adc #0
        sta cx+1
        lda txn
        sta cnt
        CALLA draw_row
@n:     inc txl
        dec txr
        bne @l
        rts

title_text:
        lda #<titles
        ldy #>titles
        sta txp
        sty txp+1
        jmp text_list

titles: .byte 24, 3, 2, "TRON Lightcycle Run", 0
        .byte 64, 2, 1, "ORANGE:  Z LEFT  X RIGHT", 0
        .byte 88, 1, 1, "FIRST TO FIVE", 0
        .byte 152, 1, 1, "CYAN:  < LEFT  > RIGHT", 0
        .byte 184, 3, 1, "1  ONE PLAYER (VS COMPUTER)", 0
        .byte 200, 3, 1, "2  TWO PLAYERS", 0
        .byte $FF

; the round's end, in both windows: who, and the score
over_text:                          ; (once, across the middle of the screen)
        lda bdead
        and bdead+1
        beq :+
        lda #<t_draw
        ldy #>t_draw
        jmp @t
:       lda bdead
        beq :+
        lda #<t_cyan
        ldy #>t_cyan
        ldx score+1
        cpx #5
        bcc @t
        lda #<t_cwin
        ldy #>t_cwin
        jmp @t
:       lda #<t_orange
        ldy #>t_orange
        ldx score
        cpx #5
        bcc @t
        lda #<t_owin
        ldy #>t_owin
@t:     sta txp
        sty txp+1
        ldy #0
        lda (txp),y
        sta txcol
        inc txp
        bne :+
        inc txp+1
:       lda #112
        sta txy
        lda #1
        sta txsc
        jsr draw_text
        lda score                   ; the score: ORANGE n  CYAN n
        ora #'0'
        sta sc_o
        lda score+1
        ora #'0'
        sta sc_c
        lda #<t_score
        sta txp
        lda #>t_score
        sta txp+1
        lda #2
        sta txcol
        lda #136
        sta txy
        jsr draw_text
        lda players                 ; the demo: how to stop it
        bne :+
        lda #<t_press
        sta txp
        lda #>t_press
        sta txp+1
        lda #3
        sta txcol
        lda #176
        sta txy
        jmp draw_text
:       rts
t_press:  .byte "PRESS 1 OR 2 TO PLAY", 0

t_orange: .byte 3, "  ORANGE SCORES ", 0
t_cyan:   .byte 1, "   CYAN SCORES  ", 0
t_draw:   .byte 2, "  BOTH CRASHED  ", 0
t_owin:   .byte 3, "ORANGE WINS!!!  ", 0
t_cwin:   .byte 1, " CYAN WINS!!!   ", 0
t_score:  .byte "ORANGE "
sc_o:     .byte "0   CYAN "
sc_c:     .byte "0", 0
