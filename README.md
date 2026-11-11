# Light Bikes

A two-player, split-screen, isometric light-bike game for the BBC Master 128, and
(from the same disc and binary) the Model B with 32K of sideways RAM.  Each player
has their own smoothly scrolling 320x128 MODE 1 window (orange on top, cyan
below).  The game runs at 25 Hz, and every graphic in play is a tile.  The bikes
ride the floor's grid lines.  A Model B with only 16K of sideways RAM gets the
earlier narrow build (160x128 windows, `narrow/`) from the same disc.

```
sh build.sh            # -> tron.ssd (and build/tron.ssd)  (needs cc65 and Python 3 with Pillow; the tests also numpy and Node)
```

Boot `tron.ssd` (SHIFT+BREAK) on a Master 128, or on a Model B with two
16K banks of sideways RAM, in any banks (the loader finds the two highest).  With
one bank the loader runs the narrow build instead.

| | Orange (top) | Cyan (bottom) |
|---|---|---|
| turn left | Z | < (comma) or cursor left |
| turn right | X | > (full stop) or cursor right |

`1` plays against the computer, `2` (or SPACE) is two players, and the first to
five rounds wins.  ESCAPE goes back to the title.

**Attract mode.**  Leave the title alone for 12 seconds and the computer plays
itself for three rounds (each score screen says PRESS 1 OR 2 TO PLAY), then the
title again, and round.  During the demo, `1` or `2` starts that game at once;
SPACE or ESCAPE goes to the title.

Turns are relative to the bike and happen at the next cell centre.  Two presses
queue two turns, so a double tap makes a U-turn.  You crash if you run into any
trail or off the edge of the floor.  When both bikes crash at once, neither scores.

## What is where

| Path | What |
|---|---|
| `src/tron.s` | the start-up, the 25 Hz tick, the game states, the bikes (growth, heads, collisions, the computer player), the cameras, the glint |
| `src/display.s` | the two-window display: the rupture chain's interrupt, the commits, the ring blitters, the composed rows |
| `src/fx.s` | the explosion (filled quads, scheduled against the beam) and the text (drawn once, centred on the whole screen) |
| `src/sound.s` | the keyboard scan and the SN76489: a four-voice sequencer (engines, countdown, turns, crash, round/match stings, title) |
| `src/hw.inc` | hardware and display constants, both machines' memory layouts |
| `src/loader.s` | LOADER: everything that needs the MOS or the disc, then moves the game into place |
| `tron.cfg` | the three images: TRON (main RAM), CODEB (the code bank), CODEA (bank 4's spare room) |
| `narrow/` | the narrow build for a Model B with 16K of sideways RAM (frozen; on the disc as LOAD16 etc.) |
| `tools/geom.py` | the arena's geometry (the memo's formulas, the floor grid) |
| `tools/gen.py` | builds the tile set, the arena map, the transition table, the growth and head tables, and the explosion's frames |
| `tools/sim.py` | a reference model of the trail drawing, checked pixel for pixel against a direct render with the prototype's rules |
| `tools/model.py` | **the frame model**: what every field should look like, from the game's logical state alone |
| `test/frames.mjs` | **the soak**: runs the game under jsbeeb, drives it, and checks every field against `tools/model.py` |
| `test/crtc.mjs` | where every chain step's writes land |
| `test/verify.mjs` | the rings in RAM against the map and tiles |
| `test/run.mjs`, `test/prof2.mjs`, `test/cost.mjs` | scripted keys and screenshots; where each tick's phases fall in the frame; a flat profiler |
| `test/w1worst.mjs`, `test/pcprof.mjs`, `test/critprof.mjs` | the worst ticks' drawing phase by phase; cycles by routine (all of a tick, or the drawing only) |
| `tools/b2/` | `tronb2`, a headless driver for Tom Seddon's b2 emulator (Master or Model B): sync/TV checks, snapshots, video and audio capture |

The tests take `MODEL=B1770` (or `B-DFS1.2`) to run a Model B instead of the Master.

## How it works

### Graphics as tiles

A tile is one MODE 1 byte (4 pixels) wide and 16 scanlines tall.  The memo's
geometry repeats every 8 byte columns.  With the arena's origin at a row phase of
7 (`Y0 & 15 = 7`; the memo leaves the phase open), each tile is touched by at most
three blade segments, and each segment is absent, cyan or orange in that byte
column.  So each of the 8 column classes needs at most 27 tiles.

The bikes ride the grid lines: the floor's magenta dots are on the lines i = k and
j = k through the cell centres, which are the lines the blades stand on.  Each line
runs on 3/4 of a cell past the outermost ones.  That way the tiles at the floor's
edge carry the same dots as the interior, which keeps the set to 247 tiles (3.9K).
Without the overhang it is 305, more than 8-bit ids allow.

The generator renders every tile with the prototype's own rules: the 50% columns,
the magenta/yellow dither, the per-pixel depth test, and the additive corners
where the two orientations interleave.  Occlusion between blades is therefore
already solved inside each tile.  One deviation from the prototype: a j-blade
draws 8 columns, not 9.  The ninth, at the far end, belongs to the next segment's
byte span.  `tools/sim.py` reproduces the memo's test scene with zero pixels
different from a direct render.

A bike draws one byte column of trail per tick, a quarter of a cell.  For each
cell that column touches, the map's tile id goes through a transition table:
`TRANS[slot][colour][id]`, 1.5K, generated and checked unambiguous.  The 6502
never composes trail pixels; it only looks up ids.  The bike's head is the newest
column drawn solid: yellow for orange, cyan for cyan.  It uses four dynamic tiles,
which are copied from the static tile and overwritten each tick.  When both heads
fall in the same tile, the second bike's tile carries both heads, and the first
bike's saved tile takes the second's trail column.

The arena is 32x32 cells, a 272x34 map (9.2K) in one sideways RAM bank alongside
the tiles, the transition tables, the font and a 322-byte description of the
empty map, which `reset_map` unpacks for each new round (each tile row is a
period-8 pattern with a few literal tiles at its ends).

### Two windows, one chain

This uses beebgame's display: its rupture-chain interrupt, CRTC set-up, ring
addressing, composed top row for 2-scanline vertical scrolling, keyboard scan and
`sndwrite`.  The code is adapted, not linked.  beebgame drives one double-buffered
window with a status bar; here the same machinery drives two windows with no
status bar:

* **Two hardware-wrapped rings.**  The top window's ring is in main RAM at $4000
  and the bottom window's is in shadow RAM at the same addresses: 16K each (2,048
  characters, 25.6 rows of 80; the windows need 21), with the hardware wrap set to
  16K.  The chain
  switches ACCCON D at the boundary.  A section's D is bit 0 of its R6.  The step
  that crosses a boundary fires 10 us early (beebgame's BARLEAD trick), so D
  changes in the horizontal blanking.
* **Five fixed sections:** A and P for each window, then Q.  A is the composed row
  (8 - f lines) or row 0.  P is rows 1 to 15, then the top f lines of row 16 shown
  in the 6845's **vertical adjust** (R5 = f).  There is no third, partial section
  at the bottom of a window.  Such a section is 2 lines when f = 2, and the step
  after it is the one that switches D.  The previous step's interrupt was still
  running when it fired, so D flipped about 10 characters into the next window's
  first line.  With vertical adjust, every D switch follows a section of at least
  120 lines.  Because the count never changes, each window owns its own entries.
* **No double buffering.**  Two windows of 18 rows, twice over, won't fit in 32K.
  Instead each window is drawn while the beam isn't in it:
  * the top window from line 128 to the vsync (line 280), committing at the end;
  * the bottom window commits first, between line 256 and 300, because its A
    address is read at the top window's P step (line ~2).  It then draws until
    line 128 of the next field.

  Everything a scroll exposes that the current frame doesn't show is drawn at any
  time.  That covers the new row (78 of its 80 characters) and the composed row,
  which alternates between two spare ring rows.  Only the new column, the changed
  tiles and the explosion touch the visible screen, and those are drawn in the
  window's off time.
* **A beam clock.**  The vsync restarts System VIA T2 at $FFFF, so `beam` gives the
  current line (in half lines) from T2 at any moment.  The bottom window's commit
  and the explosion's scheduling use it.
* **Cameras** move one character across and 2 scanlines down per tick.  That is
  exactly a bike's step along an isometric axis, so each window stays centred on
  its bike.
* **Palette changes** (the crash's flash) are queued and loaded by the vsync
  interrupt, so they never change mid-field.

### The Model B

The B has no shadow RAM, and its 6845 can only show main RAM, so both windows'
rings share the B's 32K.  Its hardware wrap only works for a ring that ends at
$7FFF (every jump in its address mapping starts there), so at most one ring could
have it, and a 16K hardware ring is more than a window needs.  Neither ring uses
it:

* **Two plain rings of exactly 18 rows** (1,440 characters, 11.25K: the 17 rows a
  window shows and the new row being drawn), W0's at $2000 and W1's at $5000, each
  followed by a **mirror** of its first row (640 bytes).  A window's P section is
  split into two chain sections where its ring wraps (`split`): P1 ends with the row
  that crosses the ring's end, which reads on into the mirror, and P2 starts at the
  ring's start.  So the B's chain has seven sections: A, P1, P2 for each window,
  then Q.  The ring length isn't a multiple of 256 characters, so every fold
  (`ringaddr`, `crtc_of`, `calc_window`, the row tables) compares 16 bits.
* **Write-through mirrors.**  Every write into a ring's first row also goes to its
  mirror: `MIRW` after each character drawn, `mir1` for single bytes (explosion,
  text, glint).  The first version copied the part of the mirror each frame needed
  after each window's drawing; that took up to 76 lines a tick, enough to miss W1's
  deadline.
* Each window's composed row is outside its ring (one buffer each, written only
  while the window isn't shown), at $1B00 and $1D80; Q's blank line is at $1880.
* There is no ACCCON on a B ($FE34 is its ROM latch): at start-up `patch_b` points
  the interrupt's ACCCON accesses at a RAM byte and turns `selwin`'s part into an
  `rts`.
* The glint's cursor addresses follow the split, and each P2 step re-writes R14
  with its window's cursor instead of clearing it (`CURS+9`: the P2's R14V entry).

**Code in sideways RAM.**  With the screen at $1880-$7F7F there are 4K of main RAM
for code ($0800-$187F).  So the code is in three places, on both machines:

* **main RAM:** the interrupt, the display core (commit, split, the ring folds,
  compose), the tile drawing, the tick loop, the growth of the trails: everything
  that runs while bank 4 (map, tiles) is paged in, or in an interrupt;
* **bank 4's spare 700 bytes:** `reset_map` and the growth tables;
* **the code bank** (the Master's bank 5, the B's other bank), after the explosion
  frames and the font: the game logic, the AI, the title and attract mode, the
  text, the sound, the start-up.

The tick loop pages bank 4 in for the drawing and the code bank for the logic.
Code-bank routines reach map-reading ones through `callA` (and the reverse through
`callB`), which page, call and restore.  The vsync interrupt pages the code bank in
for the keys and the sound and puts back whatever was paged.

Everything else (the tiles, the map, the logic, the explosion, the timing) is the
same code, with the ring geometry in per-window tables (`geom_init`).  The code is
plain 6502 (the B has an NMOS CPU).

### Drawing to time

All of a tick's on-screen drawing must fall between W0's end (line 128) and W1's
start in the next field (line 440): one field, shared by both windows, less the
interrupts.  A heavy tick (both bikes in both windows, a 6-line composed row) needs
about 150 lines a window on the Master and 165 on the B, so the order matters:

* each window commits first (its chain entries don't depend on its drawing: W0's
  are read at the vsync, W1's at W0's P step), so neither waits on its drawing;
* then the new column, the changed tiles in its top rows, and the composed row
  (shown first);
* then the other changed tiles and the glint's black, which are shown 24 or more
  lines into the window, so may finish a little after it starts;
* then the explosion, if `fx_time` says the beam allows it.  Under load W0 and W1
  take turns (`fxsk`): a window that missed its last update goes first;
* W0 starts only between lines 128 and 143: a tick whose logic ran long waits a
  field rather than draw W0 late.

The changed tiles are listed once each (a head's cell restored and regrown is one
entry) and drawn a cell (two characters) at a time.

### Memory

| | Master 128 | Model B |
|---|---|---|
| $0400-$07FF | variables (OCC, the collision grid, is a bit a cell) | the same |
| $0800-$187F | the interrupt, the display, the drawing (TRON); $0D00 is RTI for any NMI | the same |
| $1880-$1FFF | (free) | Q's blank line, the two composed rows |
| $2000-$4F7F | (free; QBLANK at $3D80) | W0's ring + mirror |
| $4000-$7FFF | W0's ring (main), W1's ring (shadow): 16K each | (from $5000) W1's ring + mirror |
| bank A | bank 4: map, tiles, tables, `reset_map` | the higher of the two banks less one: the same |
| code bank | bank 5: explosion frames, font, the rest of the code | the highest bank: the same |

On the Master, shadow RAM replaces main RAM at $3000-$7FFF while W1 is being drawn,
so main-RAM code must stay below $3000 (it is below $1880 for the B anyway).

**Loading.**  A Model B's DFS keeps its workspace at $0E00-$18FF, under the game.
So `!BOOT` runs LOADER at $1900, which does everything that needs the MOS or the
disc: it finds the machine (OSBYTE 0) and the B's two banks (or runs LOAD16, the
narrow build, if there is one or none), marks them empty in the MOS's ROM table,
selects MODE 1 and blanks the palette, loads BANK4 into bank A, loads BANKB
(explosion frames, room for the font, the code-bank code), puts the MOS's font
into it and copies it to the code bank, and loads TRON at $3000.  Then, with
interrupts off, a mover in page 1 copies TRON to $0800 and jumps to it.  The game
never calls the MOS.

### Text

Every piece of text is drawn once, centred across the whole screen, at a screen
line from 0 to 255: W0 shows lines 0-127 and W1 128-255.  A screen line belongs to
whichever window shows it, and within that window to ring row (line + f) >> 3 from
its top, line (line + f) & 7, where f is that window's fine scroll.  Row 0's lines
are what the composed row is copied from, so this holds across the A section too.
So the countdown's 16-line digit sits across the windows' join (lines 120-135),
half in each window's ring, and its erase redraws exactly the cells it covered.
The score screen is two (in the demo three) centred lines around the middle.

### Sound

`src/sound.s` is a small sequencer (by Fable): four voices (the three tones and
the noise), each with a period, slide, attenuation and fade, stepped every vsync
from tables in the code bank.  The engines borrow voices 0 and 1 while they run.

| | |
|---|---|
| countdown 3-2-1 | a G4+D4 power fifth over a sagging bass drum (periodic noise clocked by a silent channel 2) |
| go | a C5-G5-C6 arpeggio in a hiss while the engines rev up |
| engines | rev from ~125 Hz to cruise in under half a second, then creep up over ~40 s so long rounds get tenser; a 25 Hz wobble buzz |
| turn | the turning bike's engine screeches up and back, with a zap pitched per bike |
| crash | a white crack, two falling tones, then a boom whose noise pitch sinks, with two echoes |
| round won / draw | three G4s landing on a C chord / thirds descending |
| match won | a fanfare ending on a C chord over a C2 bass, ringing into the title |
| title | two low Cs beating about 0.8 Hz apart over a C1 bass, fading over ~5 s |

`sound_tick` runs in the vsync interrupt: at most ~1,350 cycles (measured over a
minute of play, crashes and fanfares), using only the interrupt's own scratch.

### The 6845 cursor: the glint

The glint is a white block on each bike's head, in its own window.

* **Where:** the byte column of the fat block, all 9 of its lines.  A cursor spans
  one character, lines R10 to R11 of one row, and the head usually straddles two
  rows.  So the cursor is programmed twice in a field (see "two rows" below).
* **Why it's white:** a cursor inverts what is under it.  So after drawing its
  changed tiles, the window writes those head bytes black in its own ring, and the
  cursor shows them white.  The other window has no cursor there and keeps the
  solid head.  The head's cells are redrawn every tick, and at a crash, so the
  black never outlives the cursor.
* **When it's set:** R14/R15/R10/R11 are written at the end of each window's P
  step, with the ULA set to a 1-byte cursor.  That covers the upper row's lines
  t..7 (or the whole head, if it fits in one row).
* **Two rows:** if the head carries on into the next row, the P step also starts
  the User VIA's T1 as a one-shot.  It fires in the upper row's last line, and its
  interrupt writes R10 = 0, R11 = b and the address one row (80) on.  The 6845
  latches the cursor's start at the start of a line and its end at the end of one.
  So R10 and R11 can land anywhere in that last line; the address must land after
  the beam has passed the cursor's column on that line and before it comes back
  on the next.  The count is `GT0 + (row - 1) x 512 + column / 4` (`GT0` in
  `display.s`, calibrated under jsbeeb), which aims the first write about 20 µs
  into the line, later for columns further right.  Over the soaks the address
  writes have 33-47 characters (16-23 µs) to spare either way, and R10/R11 always
  land in that line.  Row 0 (the composed A section) never has a cursor: a head
  across rows 0 and 1 gets only its row-1 lines.
* **When it's cleared:** every step begins by writing R14 = 0, in place of 10 of
  the hold loop's cycles, so neither window's cursor reaches the next section.
* **The address:** the 6845's own memory address is used: the P section's start
  plus the offset, *not* folded into the ring.  The CRTC's counter runs on past
  the ring's end; only the memory decode wraps.

### The explosion

Four fragments of the crashed bike, small filled quads in its colour, are thrown up
and out from the impact.

* **Physics:** they fall under gravity, bounce on the floor (losing most of their
  speed each time) and slide to rest. They tumble in the air and lie flat, as
  isometric diamonds, once down.  They burn away over the last 8 of the 40 ticks.
  When both bikes crash, each impact throws two.
* **Precomputation:** `tools/gen.py` simulates them and rasterises each frame to
  spans, as a pixel-centre-inside rule shared with the model (`geom.quad_spans`).
  The impact is always byte-aligned, so each line is stored as its first byte, its
  byte count and its two edge masks.
* **Drawing:** each tick, in each window, every fragment the window shows is put
  back to the floor by redrawing its box of characters from the map.  Then this
  tick's fragments are drawn with the memo's replace rule: cyan, or the blades'
  magenta/yellow dither for orange.  A fragment is drawn only if it lies wholly in
  the window below its top character row, so the composed row (a copy of that row)
  never needs refreshing during a crash.
* **Timing:** an update costs at most about 14K cycles (111 lines).  It is done in
  one go, and only if the beam clock says it will finish before the window is shown
  (line 288 for the top window, line 112 for the bottom).  Otherwise the window
  keeps last tick's frame.  In the soaks that never happened.  `EXFRM` records
  which frame each fragment shows.

The crash also flashes the palette white for two ticks.

## Testing

### The frame model (`tools/model.py`, `test/frames.mjs`)

```
node test/frames.mjs 150 1 7      # seconds, mode (1, 2 or demo), seed
```

**The harness:** jsbeeb runs the game while the harness steers at random (in
one- and two-player modes) and continues after each round.

**What it streams:** every field jsbeeb displays, decoded to physical colours, plus
the game's logical state after every tick: the bikes' cells, headings and
progress, the cameras, the explosion's tick and impacts, and which frame each
fragment shows.

**The model:** from that alone, the Python model rebuilds the arena with the
prototype's rules from `tools/geom.py`. It covers:
* the dots;
* each blade's lit columns, with the depth test and dither;
* the solid heads;
* the cursor over each window's own head;
* the explosion's fragments.

It shares nothing with the 6502's tiles, map or transition tables.

**The check:** every window of every field during play and crashes must equal the
model's picture of a recent tick exactly. The cursor and the line under the bottom
window (which must be black) are checked too. Failures are written to
`build/frames/` as actual/model/difference images.

Current results, all under jsbeeb:

* 120- to 150-second runs in one-player, two-player and demo modes, several seeds
  each: **0 bad fields** in about 6,000-8,000 window checks per run, with the full
  9-line glint and nothing lit below the bottom window.
* Every field during the game is exactly 312 lines, and the PC never leaves the
  code.
* `test/crtc.mjs`: over 5,000 chain steps, every D switch lands before its
  section, every section's shape (R9) in its first line, and every next address
  (R13) by the end of its second line, the shortest section's last.
* `test/verify.mjs`: the rings in RAM match the map and tiles exactly; the only
  differences are the countdown digits.
* `python3 tools/sim.py`: the memo's scene through the map, growth and transition
  tables at this arena's origin equals a direct render, 0 pixels different.
* The Model B (`MODEL=B1770` or `B-DFS1.2`, full width): 90- and 120-second runs in
  one-player, two-player and demo modes, **0 bad fields**, every field 312 lines,
  no long ticks, the glint's writes 18+ characters inside their window, the
  explosion drawn in about 85-90% of window ticks.
* `test/w1worst.mjs` (the worst ticks' drawing, phase by phase), `test/pcprof.mjs`
  and `test/critprof.mjs` (cycles by routine: all of a tick, or the drawing only).

### b2 (`tools/b2/`)

`sh tools/b2/build.sh` builds `tronb2` against a b2 checkout (default
`~/b2src/b2`, in its own build directory).  It is derived from the Model B Elite
port's headless `b2drive` harness, with a Master 128 configuration, a RAM dump
command, and video (ffmpeg) and audio (WAV) capture added.

```
tronb2 --master --disc build/tron.ssd --roms ~/b2src/b2/etc/roms --out DIR --script S --secs 160 --judge-ula 98
tronb2 --disc build/tron.ssd --roms ~/b2src/b2/etc/roms --out DIR --script S --secs 65 --ram 4,5 --judge-after 8
```

* **Master:** from the game's first ULA write, 160 seconds through the title, a
  two-player match and the demo: every line 128 cycles, every field 312 lines, b2's
  TV model never loses sync (`B2SYNC PASS`); the snapshots match jsbeeb's.
* **Model B with two banks** (`--ram 4,5`, full width) and **with one** (`--ram 4`,
  the narrow build): `B2SYNC PASS` from 8 seconds in.

### The memo's acceptance checks

* **Same scene as the prototype, pixel for pixel:** `tools/sim.py`, above.  The
  floor's dots are now on the riding lines, so the comparison uses the same dots on
  both sides.
* **Full-density triangles at inward-folding corners; outward turns stay at 50%:**
  built into the tiles; see `build/sim_scene.png`.
* **Floor dots show through blades along i:** the same.
* **No colour appears that neither the blade nor the grid uses:** every tile pixel
  is written with the memo's per-pixel replace rule and the depth test.
* **Cycles to draw a cell:** the 6502 never draws a cell.  A bike's quarter cell
  is one or two table lookups plus the head's 16-byte copy, about 1.2K cycles.
  Each window then redraws the changed characters at about 130 cycles each.

## Timing

Worst ticks seen (`test/w1worst.mjs`, `test/frames.mjs`), demo mode, both bikes in
both windows, in lines:

| | Master | Model B |
|---|---|---|
| W0's drawing (from line 128) | 150 | 165-180 |
| W1's commit (limit 256+58) | 256+43 | 256+43 |
| W1's top rows and composed row done (deadline 256+184) | ~256+160 | ~256+175 |
| W1's last changed tiles and glint (shown from ~256+210) | 256+198 | 256+210 |

The composed row (up to 6 lines of 80 characters) is the largest single item, about
65 lines; the changed tiles about 40; the new column about 30.  In a crash, the
explosion's update takes at most ~111 lines on the Master.

## Known issues

* None of this has run on real hardware.
  * **Timing:** the chain's constants are beebgame's, which were tuned on real
    machines. jsbeeb is cycle-exact enough that the chain's failures were
    reproducible and are now measured by `test/crtc.mjs`.
  * **Vertical adjust:** using R5 to show a partial row is standard 6845 behaviour,
    but this game hasn't been tried on a real Master's CRTC.
  * **The cursor in adjust lines:** whether a real 6845 shows the cursor there is
    also untested. It only matters when a window's camera is clamped at the
    arena's bottom edge with the head in row 16.
* The glint's second-row timing (`GT0`) is calibrated under jsbeeb.  Its window is
  about 40 µs wide, so a few µs of difference on real hardware won't matter.
* The Model B needs 32K of sideways RAM for full width; with 16K it runs the narrow
  build (`narrow/`, frozen: fixes to the main build don't reach it).
* Main RAM for code is full (about 140 bytes free below $1880); the code bank has
  about 6K free.
* On the Model B a chain step occasionally (about 1 in 800) lands a line late: when
  the glint's lower row starts right after a window's ring split, its User VIA
  interrupt delays the P2 step.  The late write is R9 = 7, which P2 already has; it
  would only show if that P2 were 2 lines long.  `test/crtc.mjs` reports it; the
  frame model has never seen it.
* Text (title, countdown, scores) isn't in the frame model; those screens are
  checked by eye (`test/shots.mjs`).
* On the Model B, 10-15% of explosion updates are skipped (the windows take turns
  under load).  The game logic is unaffected; the fragments just move less
  smoothly.

## Bugs the frame model found

* The vsync interrupt's sound code used the main program's `tmp` bytes.  Every
  vsync during play could corrupt whatever the game was computing.  That includes
  the computer player's occupancy pointer, which is written through, so this is
  the likely cause of the one-player crash.
* The explosion drew 3x slower than its off-screen budget, so it tore.  Its frames
  32-39 replayed frames 0-7 (an 8-bit overflow), and its corner store didn't carry
  across a page.
* D switched late after 2-line sections (flecks on the bottom window's first line
  and below it).  Fixed by the vertical-adjust chain above.
* The glint's address was folded into the ring, which the CRTC never does.  The
  top window's cursor could also show in the bottom window's top row.
* Two heads in one tile left a permanent gap in a trail.
* Interrupts held off for longer than the LEAD-early steps can bear.  `commit`
  wrapped its write of the vsync's four bytes in `sei`.  When W0 committed just as
  Q's step fell due, that step came ~15 µs late, and a line of the bottom window
  showed below it (once in ~6,000 fields, after the glint's interrupt moved the
  main loop's timing).  `sfx` held interrupts off for ~25 µs on every turn.  The
  vsync's bytes are now double-buffered behind a one-store flip, and `sfx`
  switches its effect off while it changes it.  `test/frames.mjs` now reports how
  late those two steps ever start: by character 67, where the leak began at 92.
* The crash flash could change the palette mid-field.
* Two start-up faults, found by b2 (both while the screen is black): a chain step
  could run before the first vsync with a garbage SECIDX and skip Q (a ~2,000-line
  field), and `take_over` now waits for a vsync with interrupts off so the vsync
  handler phases the chain first.  And the heads' dynamic tiles overlapped the
  font once it moved into sideways RAM, garbling the digits.
* `selwin`'s ACCCON update now writes only when the window changes, so its short
  interrupt-off window rarely delays a step (worst start now ~70, was 83).
* The collision grid wasn't page-aligned though its indexing assumed it, so cells
  on one edge of the arena aliased the first seven variables (the sideways RAM
  bank number among them).  Found while packing it into bits for the Model B port.
