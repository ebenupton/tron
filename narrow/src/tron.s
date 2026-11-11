; ============================================================================
; LIGHT BIKES -- two players, split screen, isometric, for the BBC Master 128
;
;   the top window follows the orange bike (Z left, X right), the bottom the
;   cyan one (< left, > right; or the cursor keys).  25 Hz.
;
; Everything in play is a tile (tools/gen.py): 4 pixels by 16 lines, one byte
; column of the arena, chosen by which blade segments cross it and in what colour.
; A bike draws one byte column of trail a tick -- a quarter of a cell -- which is
; exactly the scroll step, so the trail, the bike and both cameras move together.
; ============================================================================
        .setcpu "65C02"
        .include "hw.inc"
        .include "../build/gen.inc"

        .zeropage
dummyz:   .res 1                    ; always 0 (the interrupt's timing pad reads it)
irq_x:    .res 1
irq_y:    .res 1
SECIDX:   .res 1                    ; the next section's entry
SECCUR:   .res 1                    ; the section the beam is in ($F8: after the vsync)
curR7:    .res 1
vsyncs:   .res 1
keys:     .res 1                    ; keys down
keyhit:   .res 1                    ; keys gone down since the logic last looked
knew:     .res 1
tickvs:   .res 1
win:      .res 1
cbase:    .res 1
cr9:      .res 1
caddr:    .res 2
tmp:      .res 4
jv:       .res 2                    ; (a jump vector)
nm_y:     .res 1
qidx:     .res 1                    ; Q's entry: 4 x 8, or 5 x 8 (the Model B)
rbase:    .res 1                    ; the selected window's ring (selwin): its base,
rtop:     .res 1                    ; end (exclusive) and size, as high bytes; its
rsize:    .res 1                    ; length in characters (high byte), and its world
rch:      .res 1                    ; row table's offset (RMODL: 0 or RMODN)
rmoff:    .res 1
rowch:    .res 1                    ; characters a row: 80 (Master), 40 (Model B)
rowm1:    .res 1                    ; rowch - 1
rowb:     .res 2                    ; rowch x 8
rowb7:    .res 2                    ; rowch x 8 - 7
nm_a:     .res 1                    ; (6502: phx and the like keep A here)
itmp:     .res 4                    ; the interrupt's own (sound_tick)
w16:      .res 2
rp:       .res 2
mp:       .res 2
tp:       .res 2
sa:       .res 2
da:       .res 2
half:     .res 1
cnt:      .res 1
rows:     .res 1
cx:       .res 2
cy:       .res 1
; per window
wxl:      .res 2
wxh:      .res 2
wyl:      .res 2
wyh:      .res 2
wcxl:     .res 2
wcxh:     .res 2
wcy:      .res 2
wf:       .res 2
ringSl:   .res 2
ringSh:   .res 2
vcxl:     .res 2
vcxh:     .res 2
vcy:      .res 2
cslot:    .res 2
cposl:    .res 2
cposh:    .res 2
glr14:    .res 2
glr15:    .res 2
glr10:    .res 2
glr11:    .res 2
; per bike
bi:       .res 2                    ; the cell the bike's segment starts from
bj:       .res 2
bd:       .res 2                    ; heading: 0 +i, 1 +j, 2 -i, 3 -j
bq:       .res 2                    ; columns of the segment drawn (0..4)
bturn:    .res 2                    ; turns asked for: 0, 1 left, 2 right
bturn2:   .res 2
bcrq:     .res 2                    ; crash when bq reaches this ($FF: none)
bdead:    .res 2
bcpu:     .res 2                    ; driven by the computer
bti:      .res 2                    ; the target cell
btj:      .res 2
hxl:      .res 2                    ; the head: world x of its leading point, ground y
hxh:      .res 2
hyl:      .res 2
hyh:      .res 2
hbxl:     .res 2                    ; the head's byte column
hbxh:     .res 2
hn:       .res 2                    ; head cells held (0..2) and what they were
hc0l:     .res 2
hc0h:     .res 2
hc1l:     .res 2
hc1h:     .res 2
hid0:     .res 2
hid1:     .res 2
hb0l:     .res 2
hb0h:     .res 2
ht0:      .res 2
hb1l:     .res 2
hb1h:     .res 2
ht1:      .res 2
htopl:    .res 2                    ; the head's top and bottom world lines
htoph:    .res 2
hbotl:    .res 2
hboth:    .res 2
hsl:      .res 1
hsh:      .res 1
hst:      .res 1
hsc:      .res 1
ovf:      .res 1                    ; growing into the other head's cell
ovc:      .res 1
ovt:      .res 1
hrt:      .res 4                    ; head rows per bike and cell
hrb:      .res 4
; the growth step
gidx:     .res 1
gbxl:     .res 1
gbxh:     .res 1
gty:      .res 1
gteam:    .res 1
gb:       .res 1
ndirty:   .res 1
state:    .res 1
timer:    .res 1
score:    .res 2
players:  .res 1                    ; 1 or 2; 0 the demo
idle:     .res 2
rnd:      .res 2
fxt:      .res 1                    ; explosion tick ($FF: none)
fxox:     .res 4                    ; impact points (x lo/hi), two bikes
fxoy:     .res 4
fxmask:   .res 1
glph:     .res 1
lx0:      .res 2                    ; the line routine
ly0:      .res 1
ldy_:     .res 1
lsy:      .res 1
lerr:     .res 1
lcol:     .res 1
lcnt:     .res 1
txp:      .res 2
txcol:    .res 1
txsc:      .res 1
fxn:      .res 1
fxe:      .res 1
fxc:      .res 1
btmp:     .res 1
palreq:   .res 1
EXFRM:    .res 2*EXN                ; the frame each fragment shows ($FF: none)
fxteam:   .res 2                    ; each impact's bike's colour
fxm:      .res 1
xlmc:     .res 4                    ; the line's colour for each pixel of a byte

        .segment "BSS"
OCC:      .res 128                  ; cells taken, 32 x 32, a bit each
occm:     .res 1                    ; (occ_ij: the cell's bit)
btiles:   .res 1                    ; the sideways RAM bank of the map and tiles
bspare:   .res 1                    ; and of the explosion's frames (the Model B: btiles)
exbase:   .res 1                    ; where the frames are (high byte)
mach:     .res 1                    ; 0 the Master, 1 the Model B
dummyacc: .res 1                    ; (the Model B's ACCCON)
rtopm1:   .res 1                    ; rtop - 1 (the selected ring's)
txoff:    .res 1                    ; text columns less this (the Model B: 20)
DIRTYL:   .res 16                   ; changed map cells this tick: bx lo, hi, ty
DIRTYH:   .res 16
DIRTYT:   .res 16
EXNEW:    .res EXN*EXW              ; this tick's fragments (from bank 5)
EXBOX:    .res 2*EXN*4              ; per window and fragment: the characters drawn
SNDBSS:   .res 32
g2r14:    .res 2                    ; the glint's lower character row, if it has one:
g2r15:    .res 2                    ; R14 (0: none), R15, R11 (R10 = 0), and the User
g2r11:    .res 2                    ; VIA T1 count from the P step to its reprogramming
g2tl:     .res 2
g2th:     .res 2
txy:      .res 1                    ; (text: screen line, line drawn, glyph line, its
txl:      .res 1                    ;  byte, repeats, column, offset, value, line in
txg:      .res 1                    ;  the character, columns to erase)
txb:      .res 1
txr:      .res 1
txc:      .res 1
txx:      .res 1
txv:      .res 1
txw:      .res 1
txn:      .res 1
txpl:     .res 1                    ; (@put: the line, column and line-in-character
txpc:     .res 1                    ;  last written)
txpw:     .res 1
drounds:  .res 1                    ; the demo's rounds so far
gk:       .res 1                    ; (glint: the split row, and P2's address here)
gp2:      .res 2

        .segment "CODE"
; ---------------------------------------------------------------- start-up
start:  sei                         ; (LOADER has done all the MOS's part)
        ldx #$FF
        txs
        lda #$40                    ; NMIs: RTI (the MOS's vector is $0D00)
        sta $0D00
        lda #$FF                    ; (selwin: no window selected yet)
        sta selcur

        jsr machine                 ; which machine: the banks, the geometry
        ; the machine is ours from here
        sei
        jsr blank_palette
        lda btiles
        sta ROMSEL_CPY
        sta ROMSEL
        jsr set_wrap
        lda #$98                    ; MODE 1's ULA setting, with one cursor segment
        sta ULA_CTRL                ; (one byte: 4 pixels)
        jsr geom_init
        jsr crtc_init
        ldx #0
        lda #0                ; (stz)
        sta dummyz                ; (stz)
        lda #$9F                    ; silence
        jsr sndwrite
        lda #$BF
        jsr sndwrite
        lda #$DF
        jsr sndwrite
        lda #$FF
        jsr sndwrite
        jsr snd_init
        ldx #1
        jsr clear_ring
        ldx #0
        jsr clear_ring
        lda #1
        sta players
        lda #$5A
        sta rnd
        sta rnd+1
        lda #$FF
        sta fxt
        jsr fx_clear
        pha
        lda #0                ; (stz)
        sta ndirty                ; (stz)
        pla                ; (stz)
        jsr init_chain
        jsr take_over
        jmp title

; the machine, as LOADER found it
machine:
        lda HANDOFF
        sta mach
        lda HANDOFF+1
        sta btiles
        lda HANDOFF+2
        sta bspare
        lda #4*8                    ; Q's entry (the Model B: one more section)
        sta qidx
        lda #>EXPL
        sta exbase
        lda mach
        beq :+
        lda #>EXPLB
        sta exbase
        lda #5*8
        sta qidx
        jsr patch_b
:       rts

; the Model B has no ACCCON ($FE34 is its ROM latch): the interrupt's loads and
; stores of it go to a RAM byte, and selwin's part returns at once
patch_b:
        lda #<irq_handler
        sta sa
        lda #>irq_handler
        sta sa+1
        ldy #0
@s:     lda (sa),y
        cmp #$AD                    ; lda abs
        beq :+
        cmp #$8D                    ; sta abs
        bne @n
:       iny
        lda (sa),y
        cmp #<ACCCON
        bne @n0
        iny
        lda (sa),y
        dey
        cmp #>ACCCON
        bne @n0
        lda #<dummyacc
        sta (sa),y
        iny
        lda #>dummyacc
        sta (sa),y
        dey
@n0:    dey
@n:     iny
        bne @s
        inc sa+1                    ; (the handler is longer than a page)
        lda sa+1
        cmp #>irq_handler+2
        bne @s
        lda #$60                    ; rts
        sta selacc
        rts

; the screen's hardware wrap (the addressable latch's C0, C1): the Master's rings
; are 16K, $4000-$7FFF
set_wrap:
        lda #$04                    ; C0 = 0
        ldx mach
        beq :+
        lda #$0C                    ; (the Model B's W0: 8K, $6000-$7FFF: C0 = 1)
:       sta VIA_ORB
        lda #$05                    ; C1 = 0
        sta VIA_ORB
        rts

; ---------------------------------------------------------------- the tick
; 25 Hz: each tick is two fields.  W0 is drawn once the beam has left it, W1 once
; the beam has left that, then the logic and the next tick's new rows.
tick:
:       lda vsyncs                  ; two vsyncs after the last tick
        sec
        sbc tickvs
        cmp #2
        bcc :-
:       lda SECCUR                  ; the beam below W0: W1's sections, or Q
        cmp #2*8
        bcc :-
        cmp qidx
        beq :+
        bcs :-
:
        lda vsyncs
        sta tickvs
        ldx #0
        jsr crit_window
tk_c0:
:       lda SECCUR                  ; the beam below W1: Q, or past the vsync
        cmp qidx
        bcc :-
tk_w1:  ldx #1
        jsr crit_window
tk_c1:  pha
        lda #0                ; (stz)
        sta ndirty                ; (stz)
        pla                ; (stz)
        jsr run_state
tk_lg:  ldx #0
        jsr prep_window
        ldx #1
        jsr prep_window
tk_end: jmp tick

run_state:
        lda players                 ; the demo: 1 or 2 plays that game, SPACE or
        bne :+                      ; ESCAPE goes to the title
        lda keyhit
        and #K_ONE|K_TWO
        beq :++
        jmp title_keys
:       jmp :++
:       lda keyhit
        and #K_GO|K_ESC
        beq :+
        lda #0
        sta keyhit
        jmp title_again
:       lda keyhit                  ; ESCAPE: back to the title from anywhere
        bpl :+
        lda #0                ; (stz)
        sta keyhit                ; (stz)
        lda state
        beq :+
        jmp title_again
:       ldx state
        lda stab,x
        sta jv
        lda stab+1,x
        sta jv+1
        jmp (jv)
stab:   .word st_title, st_count, st_play, st_crash, st_over

ST_TITLE = 0
ST_COUNT = 2
ST_PLAY  = 4
ST_CRASH = 6
ST_OVER  = 8
DEMOROUNDS = 3

; ---------------------------------------------------------------- title
title:  lda #0                ; (stz)
        sta score                ; (stz)
        sta score+1                ; (stz)
        sta idle                ; (stz)
        sta idle+1                ; (stz)
        lda #ST_TITLE
        sta state
        jsr new_round               ; an arena to stand behind the words
        lda #ST_TITLE
        sta state
        jsr full_draw
        jsr title_text
        jsr mirror_all
        jsr wait2
        jsr set_palette
        lda #9
        jsr sfx
        lda vsyncs
        sta tickvs
        jmp tick

wait2:  lda vsyncs                  ; two vsyncs: both windows' entries in use
        clc
        adc #3
:       cmp vsyncs
        bne :-
        rts

st_title:
        inc idle                    ; a while on the title: the computer plays itself
        bne :+
        inc idle+1
:       lda idle+1
        cmp #>300
        bcc :+
        lda idle
        cmp #<300
        bcc :+
        lda #0                      ; the attract mode: DEMOROUNDS rounds of the
        sta players                 ; computer against itself, then the title again
        jmp t_go
:
title_keys:                         ; (the demo's too: 1 or 2 starts that game)
        lda keyhit
        and #K_ONE
        bne t_one
        lda keyhit
        and #K_TWO|K_GO
        bne t_two
        rts
t_one:  lda #1
        .byte $2C
t_two:  lda #2
        sta players
t_go:   lda #0
        sta keyhit
        sta score
        sta score+1
        sta drounds
start_round:
        lda #ST_COUNT
        sta state
        jsr new_round
        jsr full_draw
        jsr wait2
        jsr set_palette
        lda #75
        sta timer
        rts

; the countdown: 3, 2, 1 in both windows with a beep each, then go
st_count:
        lda timer
        ldx #3
        cmp #75
        beq @beep
        dex
        cmp #50
        beq @beep
        dex
        cmp #25
        beq @beep
@dec:   dec timer
        bne :+
        jsr count_erase
        lda #ST_PLAY
        sta state
        lda #2
        jsr sfx
        jsr eng_on
:       pha
        lda #0                ; (stz)
        sta keyhit                ; (stz)
        pla                ; (stz)
        rts
@beep:  txa
        ora #'0'
        sta t_digit
        lda #1
        jsr sfx
        lda #<t_digit               ; once, across the windows' join
        sta txp
        lda #>t_digit
        sta txp+1
        lda #CDY
        sta txy
        lda #3
        sta txcol
        lda #2
        sta txsc
        jsr draw_text
        jmp @dec

; the digit's characters back to the map's (16 lines from CDY, 4 columns)
CDY = 120                           ; (the digit's top: centred on the screen)
count_erase:
        lda #CDY
        sta txy
        lda rowch
        sec
        sbc #4
        lsr a
        sta txc
        lda #4
        sta txn
        lda #16
        jmp text_erase

t_digit: .byte "3", 0

st_play:
        jsr play_tick
        rts

st_crash:
        jsr fx_tick
        dec timer
        bne :+
        lda #ST_OVER
        sta state
        lda #100
        sta timer
        jsr snd_over
        jsr over_text
:       rts

st_over:
        lda keyhit
        and #K_GO
        bne @next
        dec timer
        bne @r
@next:  lda #0                ; (stz)
        sta keyhit                ; (stz)
        lda players                 ; (the demo: DEMOROUNDS, then the title)
        bne :+
        inc drounds
        lda drounds
        cmp #DEMOROUNDS
        bcs @end
:       lda score
        cmp #5
        bcs @end
        lda score+1
        cmp #5
        bcs @end
        jmp start_round
@end:   jmp title_again
@r:     rts
title_again:
        ldx #$FF                    ; (from inside the tick: drop its return)
        txs
        jsr eng_off
        jmp title

; ---------------------------------------------------------------- a new round
new_round:
        jsr eng_off
        lda #0                ; (stz)
        sta glr14                ; (stz)
        sta glr14+1                ; (stz)
        sta glr15                ; (stz)
        sta glr15+1                ; (stz)
        sta g2r14                ; (stz)
        sta g2r14+1                ; (stz)
        lda #$FF
        sta fxt
        jsr fx_clear
        pha
        lda #0                ; (stz)
        sta ndirty                ; (stz)
        pla                ; (stz)
        jsr reset_map
        ldx #127                    ; occupancy clear
        lda #0
:       sta OCC,x
        dex
        bpl :-
        ldx #1
@b:     lda start_i,x
        sta bi,x
        lda start_j,x
        sta bj,x
        lda start_d,x
        sta bd,x
        lda #0                ; (stz)
        sta bq,x                ; (stz)
        sta bturn,x                ; (stz)
        sta bturn2,x                ; (stz)
        lda #$FF
        sta bcrq,x
        pha
        lda #0                ; (stz)
        sta bdead,x                ; (stz)
        sta hn,x                ; (stz)
        sta bcpu,x                ; (stz)
        pla                ; (stz)
        jsr occ_set_bike
        clc                         ; the first segment's target, taken
        ldy bd,x
        lda bi,x
        adc DI,y
        sta bti,x
        lda bj,x
        clc
        adc DJ,y
        sta btj,x
        jsr occ_target
        jsr occ_set
        lda state                   ; (not on the title: the words go there)
        beq :+
        sta nm_a
        txa                ; (phx)
        pha                ; (phx)
        lda nm_a                ; (phx)
        jsr grow                    ; one column: the bike is on the grid from the start
        sta nm_a
        pla                ; (plx)
        tax                ; (plx)
        lda nm_a                ; (plx)
:
        jsr head_pos
        jsr camera
        dex
        bpl @b
        lda #0                ; (stz)
        sta ndirty                ; (stz)
        lda players                 ; one player: the computer has the cyan bike;
        cmp #2                      ; none (the demo): both
        beq :+
        lda #1
        sta bcpu+1
        lda players
        bne :+
        lda #1
        sta bcpu
:       rts

start_i: .byte 6, N-7
start_j: .byte 13, N-14
start_d: .byte 0, 2

        .segment "LOWX"            ; (runs in low RAM: tron.cfg)
; the arena's map, unpacked from its description in bank 4 (tools/gen.py, MAPD):
; each tile row zeroed, then its span filled with its period-8 pattern, its end
; runs and any other tiles put in
reset_map:
        lda #<(MAPD+MAPDP)
        sta da
        lda #>(MAPD+MAPDP)
        sta da+1
        lda #0
        sta cy
@row:   ldx cy
        lda MAPROWL,x
        sta mp
        lda MAPROWH,x
        sta mp+1
        ldy #0                      ; zero the row: 256 + 16
        tya
:       sta (mp),y
        iny
        bne :-
        inc mp+1
        ldy #MAPW-257
:       sta (mp),y
        dey
        bpl :-
        dec mp+1
        ldy #0
        lda (da),y
        cmp #$FF
        bne @span
        lda #1
        jmp @adv
@span:  lda (da),y                  ; sa = the span's start, tmp = its length
        clc
        adc mp
        sta sa
        iny
        lda (da),y
        adc mp+1
        sta sa+1
        ldy #2
        lda (da),y
        ldy #0
        sec
        sbc (da),y
        sta tmp
        ldy #3
        lda (da),y
        ldy #1
        sbc (da),y
        sta tmp+1
        inc tmp                     ; (+ 1: the last is in it)
        bne :+
        inc tmp+1
:       ldy #4
        lda (da),y
        sta tmp+2                   ; the pattern
        ldy #0
        lda (da),y
        sta tmp+3                   ; the phase: the column's low 3 bits
        lda sa
        sta rp
        lda sa+1
        sta rp+1
@fill:  lda tmp+3
        and #7
        clc
        adc tmp+2
        tax
        lda MAPD,x
        ldy #0
        sta (rp),y
        inc tmp+3
        inc rp
        bne :+
        inc rp+1
:       lda tmp
        bne :+
        dec tmp+1
:       dec tmp
        lda tmp
        ora tmp+1
        bne @fill
        ldy #5                      ; the left run, from the first column
        lda (da),y
        tax
        lda MAPD,x
        beq @rr
        sta cnt
        ldy #0
:       inx
        lda MAPD,x
        sta (sa),y
        iny
        dec cnt
        bne :-
@rr:    ldy #6                      ; the right run, from the last column leftwards:
        lda (da),y                  ; rp is one past it
        tax
        lda MAPD,x
        beq @mid
        sta cnt
:       lda rp
        bne :+
        dec rp+1
:       dec rp
        inx
        lda MAPD,x
        ldy #0
        sta (rp),y
        dec cnt
        bne :--
@mid:   ldy #7                      ; the others
        lda (da),y
        sta cnt
        beq @done
:       iny
        lda (da),y
        sta tmp
        iny
        lda (da),y
        sty tmp+1
        ldy tmp
        sta (sa),y
        ldy tmp+1
        dec cnt
        bne :-
@done:  ldy #7
        lda (da),y
        asl a
        adc #8
@adv:   clc
        adc da
        sta da
        bcc :+
        inc da+1
:       inc cy
        lda cy
        cmp #MAPH
        beq :+
        jmp @row
:       rts

        .segment "CODE"

; both windows drawn whole for their cameras, the palette black meanwhile
full_draw:
        jsr blank_palette
        ldx #0
        jsr fd1
        ldx #1
fd1:    stx win
        jsr calc_window
        ldx win
        jsr redraw_window
        ldx win
        lda wf,x
        beq :+
        jsr compose
:       ldx win                     ; commit where the beam allows, as crit_window
        bne @c1                     ; does: W0 between its end and the vsync, W1
:       jsr beam                    ; between its end and line 300
        cmp #70
        bcc :-
        cmp #130
        bcs :-
        ldx #0
        jmp commit
@c1:    jsr mirror_all              ; (the Model B's W1)
:       jsr beam
        cmp #128
        bcc :-
        cmp #150
        bcs :-
        ldx #1
        jmp commit

; ---------------------------------------------------------------- play
play_tick:
        inc glph
        jsr read_turns
        ; ---- arrivals
        ldx #1
@arr:   lda bq,x
        cmp #4
        bne @na
        lda #0                ; (stz)
        sta bq,x                ; (stz)
        lda bti,x
        sta bi,x
        lda btj,x
        sta bj,x
        lda bcrq,x
        cmp #4
        bne @na
        lda #1
        sta bdead,x
@na:    dex
        bpl @arr
        lda bdead
        ora bdead+1
        beq :+
        jmp crash
:       ; ---- decisions at the centres
        ldx #1
@dec:   lda bq,x
        bne @nd
        lda bcpu,x
        beq :+
        jsr ai_turn
:       lda bturn,x
        beq @st
        cmp #1
        beq :+
        lda bd,x                    ; right
        clc
        adc #1
        jmp :++
:       lda bd,x                    ; left
        clc
        adc #3
:       and #3
        sta bd,x
        lda bturn2,x
        sta bturn,x
        lda #0                ; (stz)
        sta bturn2,x                ; (stz)
        jsr snd_turn
@st:    clc
        ldy bd,x
        lda bi,x
        adc DI,y
        sta bti,x
        lda bj,x
        clc
        adc DJ,y
        sta btj,x
@nd:    dex
        bpl @dec
        ; ---- crash checks for the bikes leaving a centre
        ldx #1
@chk:   lda bq,x
        bne @nc
        lda #$FF
        sta bcrq,x
        lda bti,x
        cmp #N
        bcs @out
        lda btj,x
        cmp #N
        bcs @out
        jsr occ_target
        jsr occ_test
        beq :+
        lda #4                      ; into a trail: at the centre it runs through
        sta bcrq,x
:       txa                         ; the other bike
        eor #1
        tay
        lda bq,y
        bne @nc
        lda bti,x                   ; the same target: both, at the centre
        cmp bti,y
        bne :+
        lda btj,x
        cmp btj,y
        bne :+
        lda #4
        sta bcrq,x
        jmp @nc
:       lda bti,x                   ; head on along one segment: in the middle
        cmp bi,y
        bne @nc
        lda btj,x
        cmp bj,y
        bne @nc
        lda bti,y
        cmp bi,x
        bne @nc
        lda btj,y
        cmp bj,x
        bne @nc
        lda #2
        sta bcrq,x
        jmp @nc
@out:   lda #1                      ; off the arena: at once, where it stands
        sta bdead,x
@nc:    dex
        bpl @chk
        lda bdead
        ora bdead+1
        beq :+
        jmp crash
:       ldx #1                      ; the targets are taken
@tk:    lda bq,x
        bne :+
        jsr occ_target
        jsr occ_set
:       dex
        bpl @tk
        ; ---- the heads off, a column of trail each, the heads back on
        ldx #1
        jsr head_restore
        ldx #0
        jsr head_restore
        ldx #0
        jsr grow
        ldx #1
        jsr grow
        ldx #1
@hd:    jsr head_pos
        jsr camera
        jsr glint
        lda bcrq,x
        cmp bq,x
        bne :+
        cmp #2
        bne :+
        lda #1                      ; met head on
        sta bdead,x
:       dex
        bpl @hd
        jsr eng_pitch
        lda bdead
        ora bdead+1
        beq :+
        jmp crash
:       rts

DI:     .byte 1, 0, $FF, 0
DJ:     .byte 0, 1, 0, $FF
HDX:    .byte 1, $FF, $FF, 1            ; the head's step a column: x (bytes)
HDY:    .byte 2, 2, $FE, $FE            ; and y (lines)

; turns from the keys (each player's two); the computer's from ai_turn
read_turns:
        lda keyhit
        sta tmp
        php                         ; (atomic: the vsync sets keyhit's bits)
        sei
        lda #$FF-(K_1L|K_1R|K_2L|K_2R)
        and keyhit
        sta keyhit
        plp
        ldx #0
        lda tmp
        and #K_1L
        beq :+
        lda #1
        jsr add_turn
:       lda tmp
        and #K_1R
        beq :+
        lda #2
        jsr add_turn
:       inx
        lda bcpu+1
        bne @r
        lda tmp
        and #K_2L
        beq :+
        lda #1
        jsr add_turn
:       lda tmp
        and #K_2R
        beq @r
        lda #2
        jmp add_turn
@r:     rts
add_turn:
        ldy bcpu,x
        bne @r
        ldy bturn,x
        bne :+
        sta bturn,x
        rts
:       sta bturn2,x
@r:     rts

; tp = OCC + target cell of bike X
occ_target:
        lda bti,x
        sta tmp+2
        lda btj,x
occ_ij: sta tmp+3                   ; A = j, tmp+2 = i: tp = OCC + j x 4 + i / 8,
        asl a                       ; occm = the cell's bit (OCC's a bit a cell)
        asl a
        sta tp
        lda tmp+2
        lsr a
        lsr a
        lsr a
        ora tp
        clc
        adc #<OCC
        sta tp
        lda #>OCC
        adc #0
        sta tp+1
        lda tmp+2
        and #7
        sty occm
        tay
        lda occbit,y
        ldy occm
        sta occm
        rts
occbit: .byte 1, 2, 4, 8, 16, 32, 64, 128
; the cell at tp/occm taken (Y kept)
occ_set:
        sty nm_y
        ldy #0
        lda (tp),y
        ora occm
        sta (tp),y
        ldy nm_y
        rts
; Z = 1 if the cell at tp/occm is free (Y kept)
occ_test:
        sty nm_y
        ldy #0
        lda (tp),y
        ldy nm_y
        and occm
        rts
occ_set_bike:
        lda bi,x
        sta tmp+2
        lda bj,x
        jsr occ_ij
        jsr occ_set
        rts

; ---------------------------------------------------------------- the computer
; at a centre: straight on while there is room, else the side with more of it;
; now and then a turn for its own sake
ai_turn:
        lda #0                ; (stz)
        sta bturn,x                ; (stz)
        sta bturn2,x                ; (stz)
        lda bd,x
        jsr ai_run
        sta tmp+1                   ; straight
        cmp #4
        bcc @turn
        jsr random
        and #31
        bne @r
@turn:  lda bd,x
        clc
        adc #3
        and #3
        jsr ai_run
        sta tmp                     ; left
        lda bd,x
        clc
        adc #1
        and #3
        jsr ai_run                  ; right
        cmp tmp
        beq @tie
        bcc @left
@right: cmp tmp+1
        bcc @r
        lda #2
        sta bturn,x
        rts
@left:  lda tmp
        cmp tmp+1
        bcc @r
        lda #1
        sta bturn,x
@r:     rts
@tie:   cmp tmp+1
        bcc @r
        jsr random
        and #1
        clc
        adc #1
        sta bturn,x
        rts

; A = heading: free cells that way from bike X's next centre... from its cell, up to 12
ai_run:
        tay
        lda bi,x
        sta tmp+2
        lda bj,x
        sta tmp+3
        lda #0                ; (stz)
        sta cnt                ; (stz)
@l:     lda tmp+2
        clc
        adc DI,y
        sta tmp+2
        cmp #N
        bcs @e
        lda tmp+3
        clc
        adc DJ,y
        sta tmp+3
        cmp #N
        bcs @e
        tya                ; (phy)
        pha                ; (phy)
        lda tmp+3
        pha
        jsr occ_ij
        pla
        sta tmp+3
        pla                ; (ply)
        tay                ; (ply)
        jsr occ_test
        bne @e
        inc cnt
        lda cnt
        cmp #12
        bcc @l
@e:     lda cnt
        rts

random:                             ; 16-bit xorshift
        lda rnd+1
        lsr
        lda rnd
        ror
        eor rnd+1
        sta rnd+1
        ror
        eor rnd
        sta rnd
        eor rnd+1
        sta rnd+1
        rts

; ---------------------------------------------------------------- growth
; bike X draws column bq of its segment and moves its head there
grow:   stx gb
        lda #2                      ; team: orange (2) for bike 0, cyan (1) for 1
        cpx #0
        beq :+
        lda #1
:       sta gteam
        ; the segment's anchor (its low end), direction and column
        ldy bd,x
        lda bi,x
        sta tmp
        lda bj,x
        sta tmp+1
        lda bq,x
        sta tmp+2                   ; q
        cpy #2
        bne :+
        dec tmp                     ; -i: anchor i - 1
:       cpy #3
        bne :+
        dec tmp+1                   ; -j: anchor j - 1
:       cpy #1                      ; +j and -i count from the far end
        beq @rev
        cpy #2
        bne :+
@rev:   lda #3
        sec
        sbc tmp+2
        sta tmp+2
:       tya                         ; I (1) for +-i, J (0) for +-j
        and #1
        eor #1
        asl
        asl
        asl
        sta gidx
        lda tmp
        clc
        adc tmp+1
        and #1
        asl
        asl
        ora tmp+2
        ora gidx
        sta gidx                    ; di*8 + p*4 + qq
        ; anchor's tile: bx = X0/4 + 4(i - j), ty = (Y0 + 8(i + j)) >> 4
        lda tmp
        sec
        sbc tmp+1                   ; i - j, signed
        sta tmp+3
        pha
        lda #0                ; (stz)
        sta gbxh                ; (stz)
        pla                ; (stz)
        asl a
        asl a
        sta gbxl
        lda tmp+3
        bpl :+
        dec gbxh
:       lda gbxl
        clc
        adc #<(X0/4)
        sta gbxl
        lda gbxh
        adc #>(X0/4)
        sta gbxh
        lda tmp                     ; ty = (Y0 + 8(i + j)) >> 4 = (i + j) / 2 + 1
        clc                         ; (Y0 = 23)
        adc tmp+1
        lsr a
        clc
        adc #1
        sta gty
@ty:    ; the cells
        ldx gb
        lda #0                ; (stz)
        sta hn,x                ; (stz)
        lda #$FF                    ; the head's span: empty
        sta htopl,x
        sta htoph,x
        lda #0                ; (stz)
        sta hbotl,x                ; (stz)
        sta hboth,x                ; (stz)
        ldy gidx
        lda GR_DBX0,y
        ldx GR_DTY0,y
        pha
        lda GR_S0,y
        tay
        pla
        jsr grow_cell
        ldy gidx
        lda GR_N,y
        cmp #2
        bcc @hd
        lda GR_DBX1,y
        ldx GR_DTY1,y
        pha
        lda GR_S1,y
        tay
        pla
        jsr grow_cell
@hd:    ldx gb
        inc bq,x
        rts

; A = dbx (signed), X = dty, Y = slot: the cell's transition, then its head
grow_cell:
        sty tmp+3
        pha                         ; bx = gbx + dbx
        lda #0                ; (stz)
        sta tmp+2                ; (stz)
        pla                ; (stz)
        cmp #$80
        bcc :+
        dec tmp+2
:       clc
        adc gbxl
        sta cx
        lda gbxh
        adc tmp+2
        sta cx+1
        txa
        clc
        adc gty
        sta tmp+2                   ; ty
        tay
        clc
        lda MAPROWL,y
        adc cx
        sta mp
        lda MAPROWH,y
        adc cx+1
        sta mp+1
        ; the transition: TRANS + (slot * 2 + team - 1) pages, indexed by the id
        lda tmp+3
        asl a
        adc gteam                   ; (C = 0)
        adc #>TRANS-1
        sta tp+1
        lda #0                ; (stz)
        sta tp                ; (stz)
        sta ovf                ; (stz)
        sty nm_y
        ldy #0
        lda (mp),y
        ldy nm_y
        ora #0                      ; (the flags, as lda (zp))
        cmp #DYN0
        bcc :+
        and #1                      ; (bike 1 only, into the cell bike 0's head holds:
        sta ovc                     ;  the static tile under it, which takes the
        asl a                       ;  column too, for bike 0's restore)
        tay
        lda hid0,y
        inc ovf
:       tay
        lda (tp),y
        sty nm_y
        ldy #0
        sta (mp),y
        ldy nm_y
        ldy ovf
        beq :+
        pha
        lda ovc
        asl a
        tay
        pla
        sta hid0,y
:       ; the head: save the static id and where, compose the dynamic tile, map it
        ldx gb
        ldy hn,x
        bne @c1
        sta hid0,x
        lda mp
        sta hc0l,x
        lda mp+1
        sta hc0h,x
        lda cx
        sta hb0l,x
        lda cx+1
        sta hb0h,x
        lda tmp+2
        sta ht0,x
        lda hid0,x
        jmp @cc
@c1:    sta hid1,x
        lda mp
        sta hc1l,x
        lda mp+1
        sta hc1h,x
        lda cx
        sta hb1l,x
        lda cx+1
        sta hb1h,x
        lda tmp+2
        sta ht1,x
        lda hid1,x
@cc:    tay                         ; the static tile
        lda TLO,y
        sta sa
        lda THI,y
        sta sa+1
        txa                         ; dynamic id = DYN0 + bike * 2 + cell
        asl a
        ora hn,x
        clc
        adc #<DYN0
        sta tmp
        tay
        lda TLO,y
        sta da
        lda THI,y
        sta da+1
        ldy #15
@cp:    lda (sa),y
        sta (da),y
        dey
        bpl @cp
        ldy gidx                    ; the head's rows, solid
        lda hn,x
        bne @r1
        lda HD_TOP0,y
        sta tmp+1
        lda HD_BOT0,y
        jmp @rr
@r1:    lda HD_TOP1,y
        sta tmp+1
        lda HD_BOT1,y
@rr:    sta tmp+3
        jsr head_span
        txa                         ; this cell's head rows, kept
        asl a
        ora hn,x
        tay
        lda tmp+1
        sta hrt,y
        lda tmp+3
        sta hrb,y
        lda ovf                     ; bike 0's head in the same cell: drawn first
        beq @own
        ldy ovc
        lda hrt,y
        sta ovt
        lda hrb,y
        tay
        lda headcol
@ov:    cpy ovt
        bcc @own
        cpy #16
        bcs @own
        sta (da),y
        dey
        bpl @ov
@own:   ldy tmp+3
        lda headcol,x
@hr:    cpy tmp+1
        bcc @hx
        sta (da),y
        dey
        bpl @hr
@hx:    lda tmp
        sty nm_y
        ldy #0
        sta (mp),y
        ldy nm_y
        inc hn,x
        lda cx                      ; this column is the head's
        sta hbxl,x
        lda cx+1
        sta hbxh,x
        jmp dirty_cell              ; cx = bx, tmp+2 = ty

headcol: .byte $FF, $0F             ; orange's head yellow, cyan's cyan

; the head's lines in tile row tmp+2 are tmp+1..tmp+3: into its world span (bike X)
head_span:
        lda tmp+1
        cmp #16
        bcs @r                      ; none in this cell
        lda tmp+2
        pha
        lda #0                ; (stz)
        sta hsh                ; (stz)
        pla                ; (stz)
        asl a
        rol hsh
        asl a
        rol hsh
        asl a
        rol hsh
        asl a
        rol hsh
        sta hsl
        clc                         ; top = ty x 16 + tmp+1
        adc tmp+1
        sta hst
        lda hsh
        adc #0
        sta hsc
        lda hst                     ; (the higher top of the cells')
        cmp htopl,x
        lda hsc
        sbc htoph,x
        bcs @bot
@top:   lda hsc
        sta htoph,x
        lda hst
        sta htopl,x
@bot:   lda hsl                     ; bottom = ty x 16 + tmp+3
        clc
        adc tmp+3
        sta hst
        lda hsh
        adc #0
        sta hsc
        lda hbotl,x
        cmp hst
        lda hboth,x
        sbc hsc
        bcs @r
@set:   lda hsc
        sta hboth,x
        lda hst
        sta hbotl,x
@r:     rts

; bike X's head cells back to what they were
head_restore:
        lda hn,x
        beq @r
        cmp #2
        bcc :+
        lda hc1l,x
        sta mp
        lda hc1h,x
        sta mp+1
        lda hid1,x
        sty nm_y
        ldy #0
        sta (mp),y
        ldy nm_y
        lda hb1l,x
        sta cx
        lda hb1h,x
        sta cx+1
        lda ht1,x
        sta tmp+2
        jsr dirty_cell
:       lda hc0l,x
        sta mp
        lda hc0h,x
        sta mp+1
        lda hid0,x
        sty nm_y
        ldy #0
        sta (mp),y
        ldy nm_y
        lda hb0l,x
        sta cx
        lda hb0h,x
        sta cx+1
        lda ht0,x
        sta tmp+2
        jsr dirty_cell
        pha
        lda #0                ; (stz)
        sta hn,x                ; (stz)
        pla                ; (stz)
@r:     rts

; bike X's head cells, to be redrawn (its tiles as they are)
head_dirty:
        lda hn,x
        beq @r
        cmp #2
        bcc :+
        lda hb1l,x
        sta cx
        lda hb1h,x
        sta cx+1
        lda ht1,x
        sta tmp+2
        jsr dirty_cell
:       lda hb0l,x
        sta cx
        lda hb0h,x
        sta cx+1
        lda ht0,x
        sta tmp+2
        jsr dirty_cell
@r:     rts

; X = window, its ring selected: the head's lines under the cursor black, so the
; cursor's inversion shows them white (the other window, with no cursor there,
; keeps the solid head; the head's cells are redrawn every tick)
glint_poke:
        lda glr14,x
        beq @r
        lda glr11,x
        sta tmp
        lda glr15,x
        sta rp
        ldy glr10,x
        lda glr14,x
        jsr @poke
        lda g2r14,x                 ; and the lower row's, from line 0
        beq @r
        lda g2r11,x
        sta tmp
        lda g2r15,x
        sta rp
        ldy #0
        lda g2r14,x
@poke:  sta crth                    ; ring char = address - the CRTC's base, folded
        lda rp
        sec
        sbc RCRTCL,x
        sta rp
        lda crth
        sbc RCRTC,x
        cmp RCH,x
        bcc :+
        sbc RCH,x
:       asl rp                      ; x 8 + the ring's base
        rol a
        asl rp
        rol a
        asl rp
        rol a
        adc rbase
        sta rp+1
        lda #0
:       sta (rp),y
        iny
        cpy tmp
        bcc :-
        beq :-
@r:     rts

; cx = bx, tmp+2 = ty
dirty_cell:
        ldy ndirty
        cpy #16
        bcs :+
        lda cx
        sta DIRTYL,y
        lda cx+1
        sta DIRTYH,y
        lda tmp+2
        sta DIRTYT,y
        inc ndirty
:       rts

; X = window: draw the dirty cells it holds
draw_dirty:
        lda ndirty
        beq @r
        sta rows
@d:     ldy rows
        dey
        ldx win
        lda DIRTYL,y                ; bx - wcx < 80 ?
        sec
        sbc wcxl,x
        sta tmp
        lda DIRTYH,y
        sbc wcxh,x
        bne @n
        lda tmp
        cmp rowch
        bcs @n
        lda DIRTYL,y
        sta cx
        lda DIRTYH,y
        sta cx+1
        lda DIRTYT,y
        asl a
        sta cy
        sec
        sbc wcy,x
        cmp #HELD
        bcs :+
        sta nm_a
        tya                ; (phy)
        pha                ; (phy)
        lda nm_a                ; (phy)
        jsr draw_char
        pla                ; (ply)
        tay                ; (ply)
:       ldx win
        inc cy
        lda cy
        sec
        sbc wcy,x
        cmp #HELD
        bcs @n
        jsr draw_char
@n:     dec rows
        bne @d
@r:     rts

; bike X's head point: the cell centre, plus a column step for each drawn
head_pos:
        ; centre: x = X0 + 16(i - j), y = Y0 + 8(i + j)
        lda bi,x
        sec
        sbc bj,x
        sta tmp
        pha
        lda #0                ; (stz)
        sta tmp+1                ; (stz)
        pla                ; (stz)
        bpl :+
        dec tmp+1
:       lda tmp
        asl a
        rol tmp+1
        asl a
        rol tmp+1
        asl a
        rol tmp+1
        asl a
        rol tmp+1
        clc
        adc #<X0
        sta hxl,x
        lda tmp+1
        adc #>X0
        sta hxh,x
        lda bi,x
        clc
        adc bj,x
        pha
        lda #0                ; (stz)
        sta tmp+1                ; (stz)
        pla                ; (stz)
        asl a
        asl a
        asl a
        rol tmp+1
        clc
        adc #<Y0
        sta hyl,x
        lda tmp+1
        adc #>Y0
        sta hyh,x
        ; + bq columns along the heading
        ldy bd,x
        lda bq,x
        beq @r
        sta cnt
@s:     lda HDX,y                   ; x += 4 * step
        asl a
        asl a
        pha
        lda #0                ; (stz)
        sta tmp                ; (stz)
        pla                ; (stz)
        bpl :+
        dec tmp
:       clc
        adc hxl,x
        sta hxl,x
        lda hxh,x
        adc tmp
        sta hxh,x
        lda HDY,y
        pha
        lda #0                ; (stz)
        sta tmp                ; (stz)
        pla                ; (stz)
        bpl :+
        dec tmp
:       clc
        adc hyl,x
        sta hyl,x
        lda hyh,x
        adc tmp
        sta hyh,x
        dec cnt
        bne @s
@r:     rts

; window X follows bike X: wx = hx - 160, wy = hy - 63, clamped
camera:
        lda hxl,x
        sec
        sbc halfw
        sta wxl,x
        lda hxh,x
        sbc #0
        sta wxh,x
        bpl :+
        lda #0                ; (stz)
        sta wxl,x                ; (stz)
        sta wxh,x                ; (stz)
:       lda wxl,x                   ; <= WORLDW - the window's width
        cmp maxwx
        lda wxh,x
        sbc maxwx+1
        bcc :+
        lda maxwx
        sta wxl,x
        lda maxwx+1
        sta wxh,x
:       lda wxl,x
        and #$FC
        sta wxl,x
        lda hyl,x
        sec
        sbc #63
        sta wyl,x
        lda hyh,x
        sbc #0
        sta wyh,x
        bpl :+
        lda #0                ; (stz)
        sta wyl,x                ; (stz)
        sta wyh,x                ; (stz)
:       lda wyl,x
        cmp #<(WORLDH-136)
        lda wyh,x
        sbc #>(WORLDH-136)
        bcc :+
        lda #<(WORLDH-136)
        sta wyl,x
        lda #>(WORLDH-136)
        sta wyh,x
:       lda wyl,x
        and #$FE
        sta wyl,x
        sta nm_a
        txa                ; (phx)
        pha                ; (phx)
        lda nm_a                ; (phx)
        jsr calc_window
        sta nm_a
        pla                ; (plx)
        tax                ; (plx)
        lda nm_a                ; (plx)
        rts

; the glint: the 6845's cursor over bike X's head, in its own window.  The cursor
; covers lines R10..R11 of one character, so a head across two character rows takes
; two: the upper row's lines t..7 from the P step, and the lower's 0..b from a User
; VIA T1 interrupt in the upper row's last line, which moves the cursor down a row
; (display.s, CURS2).  Row 0 (the A section) and row 17 have no cursor.
glint:  lda #0                ; (stz)
        sta glr14,x                ; (stz)
        sta glr15,x                ; (stz)
        sta g2r14,x                ; (stz)
        lda bdead,x
        beq :+
@r:     rts
:       lda hbxl,x                  ; column: - wcx
        sec
        sbc wcxl,x
        sta tmp+2
        lda hbxh,x
        sbc wcxh,x
        bne @r
        lda tmp+2
        cmp rowch
        bcs @r
        lda htoph,x                 ; rt = top >> 3 - wcy, rb = bottom >> 3 - wcy
        lsr a
        lda htopl,x
        ror a
        lsr a
        lsr a
        sec
        sbc wcy,x
        sta tmp
        lda hboth,x
        lsr a
        lda hbotl,x
        ror a
        lsr a
        lsr a
        sec
        sbc wcy,x
        sta tmp+1
        lda htopl,x
        and #7
        sta glr10,x
        lda hbotl,x
        and #7
        sta glr11,x
        ; the 6845's own address of row 1, this column: the P section's start (folded
        ; into the ring as commit gives it), then counting on unfolded -- the CRTC
        ; does not wrap at the ring's end, only the memory decode does
        lda #1
        jsr ring_plus
        sta nm_a
        txa                ; (phx)
        pha                ; (phx)
        lda nm_a                ; (phx)
        jsr crtc_of
        sta nm_a
        pla                ; (plx)
        tax                ; (plx)
        lda nm_a                ; (plx)
        sta tmp+3                   ; P's start: A (hi), Y (lo)
        tya
        clc
        adc tmp+2
        sta w16
        lda tmp+3
        adc #0
        sta w16+1
        lda #17                     ; the Model B's W1: rows after its split are P2's,
        sta gk                      ; from the ring's start
        txa
        and mach
        beq :++
        jsr split_of
        sta gk
        lda w16
        pha
        lda w16+1
        pha
        lda gk
        clc
        adc #1
        jsr ring_plus
        jsr crtc_of
        sta gp2+1
        tya
        clc
        adc tmp+2
        sta gp2
        bcc :+
        inc gp2+1
:       pla
        sta w16+1
        pla
        sta w16
:       lda tmp+1
        cmp tmp
        beq @one                    ; all in one row
        ; ---- two rows
        lda tmp
        beq @low1                   ; upper row 0: only the lower, row 1
        cmp #HELD
        bcs @r2
        lda #7                      ; upper: lines t..7
        pha
        lda glr11,x
        sta g2r11,x
        pla
        sta glr11,x
        lda tmp
        jsr @addr
        lda tmp
        cmp #HELD-1
        bcs @r2                     ; lower row 17: not shown
        ; the lower row, and the count from the P step to row tmp's line 7
        lda tmp+1
        jsr @at
        sta g2r14,x
        tya
        sta g2r15,x
        lda tmp                     ; (tmp - 1) x 512 + column / 4 + GT0
        sec
        sbc #1
        asl a
        sta tmp+3
        lda tmp+2
        lsr a
        lsr a
        clc
        adc gt0
        sta g2tl,x
        lda tmp+3
        adc gt0+1
        sta g2th,x
        rts
@low1:  lda #0                ; (stz)
        sta glr10,x                ; (stz)
        lda #1
        jmp @addr
@one:   lda tmp
        beq @r2
        cmp #HELD
        bcs @r2
; A = window row 1..16: glr14/15 = its address, this column
@addr:  jsr @at
        sta glr14,x
        tya
        sta glr15,x
@r2:    rts
; A = window row 1..16: A (hi), Y (lo) = w16 + (row - 1) x rowch, or past the
; Model B's split, gp2 + (row - k - 1) x rowch
@at:    cmp gk
        beq :+
        bcs @p2
:       tay
        dey
        lda w16
        clc
        adc RMULL,y
        pha
        lda w16+1
        adc RMULH,y
        tay
        pla
        sta nm_a
        tya
        ldy nm_a
        rts
@p2:    sec
        sbc gk
        tay
        dey
        lda gp2
        clc
        adc RMULL,y
        pha
        lda gp2+1
        adc RMULH,y
        tay
        pla
        sta nm_a
        tya
        ldy nm_a
        rts

; ---------------------------------------------------------------- crash
crash:  lda #ST_CRASH
        sta state
        lda #EXT+10
        sta timer
        jsr eng_off
        lda #5
        jsr sfx
        ; the points: the other bike's, unless both
        lda bdead
        and bdead+1
        bne @both
        lda bdead
        beq :+
        inc score+1
        jmp @pts
:       inc score
        jmp @pts
@both:
@pts:   ; the impacts
        ldx #1
:       pha
        lda #0                ; (stz)
        sta glr14,x                ; (stz)
        sta glr15,x                ; (stz)
        sta g2r14,x                ; (stz)
        pla                ; (stz)
        dex
        bpl :-
        ldx #0
        ldy #0
@o:     lda bdead,x
        beq :+
        lda hxl,x
        sta fxox,y
        lda hxh,x
        sta fxox+1,y
        lda hyl,x
        sta fxoy,y
        lda hyh,x
        sta fxoy+1,y
        tya                ; (phy)
        pha                ; (phy)
        tya
        lsr a
        tay
        lda #2
        cpx #0
        beq @tm
        lda #1
@tm:    sta fxteam,y
        sta nm_a
        pla                ; (ply)
        tay                ; (ply)
        lda nm_a                ; (ply)
        iny
        iny
:       inx
        cpx #2
        bne @o
        ldx #1                      ; the heads redrawn: no glint's black left in them
:       jsr head_dirty
        dex
        bpl :-
        lda #0                      ; one impact: every fragment from it
        cpy #4
        bne :+
        lda #1
:       sta fxmask
        jsr fx_clear
        pha
        lda #0                ; (stz)
        sta fxt                ; (stz)
        pla                ; (stz)
        jsr fx_load
        jmp flash_palette

        .include "display.s"
        .include "fx.s"
        .include "sound.s"
