; Hardware (as beebgame's engine.s names it)
CRTC_IDX  = $FE00
CRTC_DAT  = $FE01
ULA_CTRL  = $FE20
ULA_PAL   = $FE21
ROMSEL    = $FE30
ACCCON    = $FE34
VIA_ORB   = $FE40
VIA_ORA   = $FE41
VIA_DDRB  = $FE42
VIA_DDRA  = $FE43
VIA_T1CL  = $FE44
VIA_T1CH  = $FE45
VIA_T1LL  = $FE46
VIA_T1LH  = $FE47
VIA_T2CL  = $FE48
VIA_T2CH  = $FE49
VIA_ACR   = $FE4B
VIA_PCR   = $FE4C
VIA_IFR   = $FE4D
VIA_IER   = $FE4E
VIA_ORANH = $FE4F
UVIA_T1CL = $FE64
UVIA_T1CH = $FE65
UVIA_ACR  = $FE6B
UVIA_IFR  = $FE6D
UVIA_IER  = $FE6E
IRQ1V     = $0204
ROMSEL_CPY= $F4
OSWRCH    = $FFEE
OSWORD    = $FFF1
OSBYTE    = $FFF4

BANK_TILES = 4                    ; map, tiles, transitions (tools/gen.py)
BANK_SPARE = 5                    ; the pristine map, the explosion's frames

; ---------------------------------------------------------------- the display
; Two windows, each 80 characters (320 pixels) by 16 character rows (128 lines),
; stacked.  Each has its own ring of 32 character rows that the CRTC wraps for
; free: the top window's in main RAM, the bottom's in shadow RAM at the same
; addresses, the CRTC switched between them (ACCCON D) at the boundary.
RING      = $4000                 ; the Master's rings: 16K, the hardware wrap's
RINGCH    = 2048                  ; characters in a ring (25.6 rows of 80)
CRTCB     = RING / 8              ; the ring's start as the CRTC counts
ROWCH     = 80
WROWS     = 16                    ; character rows a window shows
HELD      = 17                    ; rows a window keeps drawn (the bottom partial's too)
LINE      = 64                    ; us a scanline
QROWS     = 7                     ; blanking rows: 2 x 128 + 56 = 312 lines
QVSYNC    = 3                     ; vsync on Q's row 3: the picture 32 lines after it,
                                  ; where the Master MOS's own MODE 1 frame puts it
LEAD      = 10                    ; the bottom window's first step fires this many us
                                  ; early, so ACCCON D lands in the horizontal blanking
                                  ; of the top window's last line (beebgame's BARLEAD)
; key bits (keys, keyhit)
K_1L   = $01
K_1R   = $02
K_2L   = $04
K_2R   = $08
K_GO   = $10                      ; SPACE / RETURN
K_ONE  = $20                      ; "1": one player
K_TWO  = $40                      ; "2": two players
K_ESC  = $80

HANDOFF   = $0380                 ; LOADER's findings: mach, btiles, bspare
; The Model B (32K of sideways RAM): no shadow RAM, so both windows' rings share
; main RAM, and only a ring ending at $7FFF can have the hardware's wrap.  So
; neither has it: each is a plain ring of 18 rows (1440 characters, exactly what a
; window needs: the 17 it shows and the new one), with its first row mirrored
; after its end, and its P section split in two where it wraps (split).  Below
; them, the composed rows and Q's blank line.
RINGBCH   = 1440                  ; characters in a Model B ring
RING0B    = $2000                 ; W0's: $2000-$4CFF, its mirror $4D00-$4F7F
RING1B    = $5000                 ; W1's: $5000-$7CFF, its mirror $7D00-$7F7F
QBLANKB   = $1880                 ; 640 bytes kept zero
CBUF0B    = $1B00                 ; W0's composed row (640 bytes)
CBUF1B    = $1D80                 ; W1's
QBLANK    = $3D80                 ; the Master's (main RAM, below its rings)
