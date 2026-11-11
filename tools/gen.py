#!/usr/bin/env python3
"""Generate the tile set, the arena map and the logic's tables.

Every graphic in play is a tile: 4 screen pixels (one MODE 1 byte) wide and 16
scanlines (two character rows) tall, 16 bytes stored top to bottom.  The arena's
geometry repeats every 8 byte columns, so a tile's class is bx & 7, and with
Y0 & 15 = 7 each tile is touched by at most three blade segments ("slots").  A
segment's byte column is either absent or lit in one of two colours, so a class
needs at most 27 tiles; with the floor's edge variants the set is about 240.

Outputs:
  build/bank4.bin  sideways RAM bank 4 image: map, tiles, transition table, tile
                   address tables
  build/gen.inc    constants and the small tables the 6502 logic reads
"""
import itertools, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from geom import *

OUT = os.path.join(os.path.dirname(__file__), '..', 'build')
os.makedirs(OUT, exist_ok=True)

MAP = 0x8000                 # bank 4 layout (the one sideways RAM bank a Model B has)
TILES = 0xA420               # (16-aligned: a tile's halves are TLO | 0 and | 8)
FONTB = 0x8F00               # the MOS's font, characters 32..127: in the code bank, after EXPL
DYNA = 0xB390                # the dynamic tiles (the heads)
CODEA = 0xB400               # bank 4's code (tron.cfg: CODEA, $200) and tables (TABA, $BF50)
TRANS = 0xB600               # 6 pages: slot*2 + (colour-1)
TLO = 0xBC00
THI = 0xBD00
MAPD = 0xBE00                # the map's description, which reset_map unpacks
NDYN = 4                     # dynamic tiles (the bike heads): ids 252..255
DYN0 = 256 - NDYN
assert MAP + MAPW * MAPH <= TILES

# ---------------------------------------------------------------- features
feat = {}       # (bx, ty) -> {edge: [(px, row, depth)]}
for e in EDGES:
    i, j, di, dj = e
    for (x, y, d) in edge_pixels(i, j, i + di, j + dj):
        feat.setdefault((x >> 2, y >> 4), {}).setdefault(e, []).append((x & 3, y & 15, d))
bg = {}
for (x, y) in grid_points():
    bg.setdefault((x >> 2, y >> 4), set()).add((x & 3, y & 15))

def slotkey(e, bx, ty):
    i, j, di, dj = e
    xa, ya = centre(i, j)
    return (di, xa - 4 * bx, ya - 16 * ty)

slotkeys = {}
for t, fs in feat.items():
    for e in fs:
        slotkeys.setdefault(t[0] & 7, set()).add(slotkey(e, *t))
SLOTS = {c: sorted(v) for c, v in slotkeys.items()}
assert all(len(v) == 3 for v in SLOTS.values()), SLOTS

def render(t, states):
    """states: {slot: colour}.  The prototype's per-pixel depth test, in one tile."""
    img = [[0] * 4 for _ in range(16)]
    z = [[-1e9] * 4 for _ in range(16)]
    for (x, y) in bg.get(t, ()):
        img[y][x] = 2
    fs = feat.get(t, {})
    for e, px in sorted(fs.items()):
        s = SLOTS[t[0] & 7].index(slotkey(e, *t))
        c = states.get(s, 0)
        if not c:
            continue
        for (x, y, d) in px:
            if d >= z[y][x]:
                z[y][x] = d
                img[y][x] = blade_colour(c, x, y)   # tiles are 4- and 16-aligned
    return tuple(tuple(r) for r in img)

def tile_slots(t):
    fs = feat.get(t, {})
    return sorted(SLOTS[t[0] & 7].index(slotkey(e, *t)) for e in fs)

# ---------------------------------------------------------------- tile ids
images = [tuple(tuple([0] * 4) for _ in range(16))]   # id 0: black, outside everything
ids = {}            # (class, image) -> id
trans = {}          # (slot, colour, id) -> id
def idof(c, im):
    k = (c, im)
    if k not in ids:
        ids[k] = len(images)
        images.append(im)
    return ids[k]
initmap = [[0] * MAPW for _ in range(MAPH)]
for ty in range(MAPH):
    for bx in range(MAPW):
        t = (bx, ty)
        if t not in feat and t not in bg:
            continue
        c = bx & 7
        sl = tile_slots(t)
        initmap[ty][bx] = idof(c, render(t, {}))
        for st in itertools.product((0, 1, 2), repeat=len(sl)):
            S = dict(zip(sl, st))
            a = idof(c, render(t, S))
            for s in sl:
                if S[s]:
                    continue
                for col in (1, 2):
                    S2 = dict(S); S2[s] = col
                    b = idof(c, render(t, S2))
                    k = (s, col, a)
                    assert trans.get(k, b) == b, "ambiguous transition"
                    trans[k] = b
NT = len(images)
assert NT <= DYN0, NT
print("gen: %d tiles, map %dx%d" % (NT, MAPW, MAPH))

def tilebytes(im):
    out = bytearray()
    for row in im:
        b = 0
        for px, col in enumerate(row):
            b |= ((col >> 1) & 1) << (7 - px) | (col & 1) << (3 - px)
        out.append(b)
    return out

# ---------------------------------------------------------------- growth table
# A bike draws one byte column of its segment per tick.  For a segment anchored at
# centre (i, j) (its low end), direction I (along i) or J, parity p = (i + j) & 1 and
# column qq (0 = leftmost), the map cells it touches, relative to the anchor's
# (xa >> 2, ya >> 4), and the slot it fills in each.
GROW = {}
def grow_entries(e, qq):
    i, j, di, dj = e
    xa, ya = centre(i, j)
    bx = (xa >> 2) + qq if di else (xa >> 2) - 4 + qq
    cells = {}
    for (x, y, d) in edge_pixels(i, j, i + di, j + dj):
        if x >> 2 == bx:
            cells.setdefault(y >> 4, []).append((x & 3, y & 15))
    out = []
    for ty, px in sorted(cells.items()):
        s = SLOTS[bx & 7].index(slotkey(e, bx, ty))
        out.append((bx - (xa >> 2), ty - (ya >> 4), s, px))
    return out
for di in (1, 0):
    for p in (0, 1):
        e = (10 + p, 10, di, 1 - di)
        for qq in range(4):
            GROW[(di, p, qq)] = grow_entries(e, qq)
            for i in range(N - 1):            # the same everywhere (checked)
                for j in range(N - 1):
                    if (i + j) & 1 == p:
                        g = grow_entries((i, j, di, 1 - di), qq)
                        assert [x[:3] for x in g] == [x[:3] for x in GROW[(di, p, qq)]]

# ---------------------------------------------------------------- head overlay
# The bike's head is its newest byte column drawn solid, one row taller than the
# blade.  Per growth entry: the rows of that tile it covers.
def head_rows(di, p, qq):
    e = (10 + p, 10, di, 1 - di)
    i, j, _, _ = e
    xa, ya = centre(i, j)
    bx = (xa >> 2) + qq if di else (xa >> 2) - 4 + qq
    ys = [y for (x, y, d) in edge_pixels(i, j, i + di, j + dj_(di)) if x >> 2 == bx]
    top, bot = min(ys), max(ys)
    rows = {}
    for y in range(top, bot + 1):
        rows.setdefault((y >> 4) - (ya >> 4), []).append(y & 15)
    return rows
def dj_(di): return 1 - di

# ---------------------------------------------------------------- outputs
bank = bytearray(0x4000)
for ty in range(MAPH):
    for bx in range(MAPW):
        bank[MAP - 0x8000 + ty * MAPW + bx] = initmap[ty][bx]
for n, im in enumerate(images):
    o = TILES - 0x8000 + n * 16
    bank[o:o + 16] = tilebytes(im)
for s in range(3):
    for col in (1, 2):
        o = TRANS - 0x8000 + (s * 2 + col - 1) * 256
        for a in range(256):
            bank[o + a] = trans.get((s, col, a), a)
for n in range(256):
    a = TILES + n * 16 if n < DYN0 else DYNA + (n - DYN0) * 16
    bank[TLO - 0x8000 + n] = a & 0xFF
    bank[THI - 0x8000 + n] = a >> 8
assert TILES + NT * 16 <= DYNA and NT <= DYN0 and DYNA & 15 == 0 and DYNA + NDYN * 16 <= CODEA
# the map's description, which reset_map unpacks.  First the period-8 patterns
# (8 bytes each), then the end runs (count, tiles), then per tile row: $FF (empty)
# or the span's first and last byte columns (2 bytes each), its pattern's offset,
# the offsets of its left run (tiles from the first column rightwards) and right
# run (from the last leftwards), and the others (count, then offset from the
# first column, tile).
from collections import Counter
pats, runs, rowsd = [], [], []
for ty in range(MAPH):
    r = initmap[ty]
    nz = [x for x in range(MAPW) if r[x]]
    if not nz:
        rowsd.append(None)
        continue
    a, b = nz[0], nz[-1]
    pat = [Counter(r[x] for x in range(a, b + 1) if x % 8 == k).most_common(1)[0][0] for k in range(8)]
    if pat not in pats:
        pats.append(pat)
    ln = 0
    while a + ln <= b and r[a + ln] != pat[(a + ln) % 8]:
        ln += 1
    rn = 0
    while b - rn >= a + ln and r[b - rn] != pat[(b - rn) % 8]:
        rn += 1
    lrun = tuple(r[a + i] for i in range(ln))
    rrun = tuple(r[b - i] for i in range(rn))
    for run in (lrun, rrun):
        if run not in runs:
            runs.append(run)
    mid = [x for x in range(a + ln, b - rn + 1) if r[x] != pat[x % 8]]
    assert all(x - a < 256 for x in mid)
    rowsd.append((a, b, pats.index(pat), lrun, rrun, mid))
ptab = bytes(sum(pats, []))
roff = {}
rtab = bytearray()
for run in runs:
    roff[run] = len(ptab) + len(rtab)
    rtab += bytes([len(run)]) + bytes(run)
md = bytearray(ptab + rtab)
MAPDP = len(md)                                # (where the rows start)
for rd in rowsd:
    if rd is None:
        md.append(0xFF)
        continue
    a, b, p, lrun, rrun, mid = rd
    md += bytes([a & 255, a >> 8, b & 255, b >> 8, p * 8, roff[lrun], roff[rrun], len(mid)])
    for x in mid:
        md += bytes([x - a, initmap[rowsd.index(rd)][x]])
assert all(v < 256 for v in roff.values())
assert MAPD + len(md) <= 0xBF50, len(md)
bank[MAPD - 0x8000:MAPD - 0x8000 + len(md)] = md
open(os.path.join(OUT, 'bank4.bin'), 'wb').write(bank)

L = []
w = L.append
w('; generated by tools/gen.py -- do not edit')
for k in ('N', 'X0', 'Y0', 'MAPW', 'MAPH', 'WORLDW', 'WORLDH', 'MAPDP'):
    w('%s = %d' % (k, globals()[k]))
assert TILES >= MAP + MAPW * MAPH and TILES & 15 == 0
for k in ('MAP', 'TILES', 'FONTB', 'TRANS', 'TLO', 'THI', 'MAPD', 'DYN0'):
    w('%s = $%04X' % (k, globals()[k]))
w('NTILES = %d' % NT)
# growth: index = di*32 + p*16 + qq*4 (+0..3): count, then up to 2 x (dbx, dty, slot)
# laid out as parallel byte tables of 64 entries: GR_N, GR_DBX0, GR_DTY0, GR_S0, GR_DBX1...
rows = {k: [] for k in ('GR_N', 'GR_DBX0', 'GR_DTY0', 'GR_S0', 'GR_DBX1', 'GR_DTY1', 'GR_S1')}
hd = []
for di in (0, 1):
    for p in (0, 1):
        for qq in range(4):
            g = GROW[(di, p, qq)]
            assert 1 <= len(g) <= 2
            rows['GR_N'].append(len(g))
            for k in (0, 1):
                dbx, dty, s = g[k][:3] if k < len(g) else (0, 0, 0)
                rows['GR_DBX%d' % k].append(dbx & 255)
                rows['GR_DTY%d' % k].append(dty & 255)
                rows['GR_S%d' % k].append(s)
            hr = head_rows(di, p, qq)
            # per cell k: first row, last row (rows are contiguous)
            for k in (0, 1):
                if k < len(g):
                    rr = hr.get(g[k][1], [])
                    hd.append((min(rr), max(rr)) if rr else (16, 15))
                else:
                    hd.append((16, 15))
            assert set(hr) <= {x[1] for x in g}, (di, p, qq, hr, g)
w('        .pushseg')
w("        .segment \"CODEA\"")
for k, v in rows.items():
    w('%s: .byte %s' % (k, ','.join(str(x) for x in v)))
w("        .segment \"TABA\"")
w('HD_TOP0: .byte %s' % ','.join(str(hd[2 * n][0]) for n in range(16)))
w('HD_BOT0: .byte %s' % ','.join(str(hd[2 * n][1]) for n in range(16)))
w('HD_TOP1: .byte %s' % ','.join(str(hd[2 * n + 1][0]) for n in range(16)))
w('HD_BOT1: .byte %s' % ','.join(str(hd[2 * n + 1][1]) for n in range(16)))
w('MAPROWL: .byte %s' % ','.join(str((MAP + r * MAPW) & 255) for r in range(MAPH)))
w('MAPROWH: .byte %s' % ','.join(str((MAP + r * MAPW) >> 8) for r in range(MAPH)))
w('        .popseg')
open(os.path.join(OUT, 'gen.inc'), 'w').write('\n'.join(L) + '\n')

# for the tests
import pickle
pickle.dump(dict(images=images, initmap=initmap, trans=trans, GROW=GROW, hd=hd,
                 SLOTS=SLOTS), open(os.path.join(OUT, 'gen.pkl'), 'wb'))

# ---------------------------------------------------------------- bank 5
# The pristine map (copied over bank 4's at every round), and the explosion: EXN
# fragments of the bike, small quads thrown up and out from the impact, falling
# under gravity, bouncing on the floor and sliding to rest, tumbling while in the
# air and lying flat (an isometric diamond) once down; they shrink away at the end.
# Positions are screen pixels from the impact: across, and down the floor plane
# (at half speed: the floor is foreshortened), less the height.  Each fragment's
# frame is rasterised to spans; entry (t, k) is 24 bytes: lines n (0: not drawn),
# the first line's dy, the box's dx min and max, then per line its first byte (from
# the box's first byte column) and bytes - 1 << 4 | first pixel << 2 | last pixel.
# (The impact is always byte-aligned, so the bytes and masks are the same anywhere.)
import math
EXT, EXN, EXW = 40, 4, 24
EXPL = 0x8000                 # the Master: bank 5 (the Model B: main RAM, EXPLB)
G_ = 0.42
rng = __import__('random').Random(7)
frags = []
for k in range(EXN):
    th = math.radians(k * 360 / EXN + 25 + rng.uniform(-18, 18))
    sp = rng.uniform(1.7, 2.8)
    frags.append(dict(x=0.0, f=0.0, h=5.0, vx=sp * math.cos(th), vf=sp * math.sin(th) / 2,
                      vh=rng.uniform(3.6, 5.0), L=rng.uniform(5.8, 7.0), phi=rng.uniform(0, 6.3),
                      w=rng.uniform(0.25, 0.45) * (1 if k & 1 else -1), psi=rng.uniform(0, 6.3),
                      w2=rng.uniform(0.3, 0.5), down=False))
EXC = {}                                  # (t, k) -> corners, for the tests
ex = bytearray()
for t in range(EXT):
    for k, q in enumerate(frags):
        L = q['L'] * min(1.0, (EXT - t) / 8)          # the last 8 ticks: burning away
        if q['down']:
            ys = 0.5                                  # flat on the floor
        else:
            ys = 0.35 + 0.65 * abs(math.cos(q['psi']))
        pts = []
        for m in range(4):
            a = q['phi'] + m * math.pi / 2
            pts.append((q['x'] + L * 0.7071 * math.cos(a), q['f'] - q['h'] + L * 0.7071 * math.sin(a) * ys))
        sp = quad_spans(pts) if L >= 1.5 else {}
        rec = bytearray(EXW)
        if sp:
            lines = sorted(sp)
            assert lines == list(range(lines[0], lines[-1] + 1)) and len(lines) <= 10, (t, k, len(lines))
            rec[0] = len(lines)
            rec[1] = lines[0] & 255
            rec[2] = min(v[0] for v in sp.values()) & 255
            rec[3] = max(v[1] for v in sp.values()) & 255
            b0 = min(v[0] for v in sp.values()) >> 2      # the box's first byte column
            for i, y in enumerate(lines):
                xl, xr = sp[y]
                nb = (xr >> 2) - (xl >> 2)
                assert 0 <= nb < 16
                rec[4 + 2 * i] = (xl >> 2) - b0               # bytes from the box's left
                rec[5 + 2 * i] = nb << 4 | (xl & 3) << 2 | (xr & 3)
            EXC[(t, k)] = pts
        ex += rec
        # the step: gravity, the floor's bounce and friction, the tumble
        q['x'] += q['vx']; q['f'] += q['vf']
        if not q['down']:
            q['vh'] -= G_; q['h'] += q['vh']
            q['phi'] += q['w']; q['psi'] += q['w2']
            if q['h'] <= 0:
                q['h'] = 0
                if abs(q['vh']) < 1.3:
                    q['down'] = True; q['vh'] = 0
                else:
                    q['vh'] = -q['vh'] * 0.38
                q['vx'] *= 0.55; q['vf'] *= 0.55; q['w'] *= 0.5
        else:
            q['vx'] *= 0.6; q['vf'] *= 0.6
assert len(ex) == EXT * EXN * EXW == 0xF00
open(os.path.join(OUT, 'expl.bin'), 'wb').write(ex)
with open(os.path.join(OUT, 'gen.inc'), 'a') as f:
    f.write('EXPL = $%04X\nEXT = %d\nEXN = %d\nEXW = %d\n' % (EXPL, EXT, EXN, EXW))
pickle.dump(dict(images=images, initmap=initmap, trans=trans, GROW=GROW, hd=hd,
                 SLOTS=SLOTS, EXC=EXC), open(os.path.join(OUT, 'gen.pkl'), 'wb'))
