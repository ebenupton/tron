#!/usr/bin/env python3
"""The reference model: what every field of the game should look like.

test/frames.mjs runs the game under jsbeeb and streams to this script's stdin:
  * a snapshot of the game's logical state after every tick's logic (the bikes'
    cells, headings and progress, the cameras, the explosion's tick), and
  * every field jsbeeb displays, decoded to physical colours.

From the snapshots alone this model rebuilds the arena with the prototype's rules
(tools/geom.py: the floor dots, each blade's lit columns, the per-pixel depth test,
the magenta/yellow dither), the bikes' solid heads, the 6845 cursor over each
window's own head, and the explosion's XOR squares.  It shares nothing with the
6502's tiles, map or transition tables.  Each window of each field must equal the
model's picture of one recent tick exactly; anything else is reported, and the
first few failures are written out as images (build/frames/).

usage: node test/frames.mjs ...   (which starts this)
"""
import sys, os, json, struct
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from geom import *

OUT = os.path.join(os.path.dirname(__file__), '..', 'build', 'frames')
os.makedirs(OUT, exist_ok=True)
DI = (1, 0, -1, 0)
DJ = (0, 1, 0, -1)
ST_TITLE, ST_COUNT, ST_PLAY, ST_CRASH, ST_OVER = 0, 2, 4, 6, 8
FW = 328                                   # pixels sent a line (the picture and a margin)
PHYS = {0: (0, 0), 6: (1, 0), 5: (2, 0), 3: (3, 0), 7: (0, 1), 1: (1, 1), 2: (2, 1), 4: (3, 1)}
LUT_L = np.zeros(256, np.uint8); LUT_C = np.zeros(256, np.uint8)
for p, (l, c) in PHYS.items():
    LUT_L[p] = l; LUT_C[p] = c

# ---------------------------------------------------------------- the arena
WW = int(sys.argv[sys.argv.index('--width') + 1]) if '--width' in sys.argv else 320   # a window's width (the Model B: 160)
BASE = np.zeros((WORLDH, WORLDW), np.uint8)
for (x, y) in grid_points():
    BASE[y, x] = 2

class Arena:
    def __init__(self):
        self.img = BASE.copy()
        self.z = np.full((WORLDH, WORLDW), -1e9)
        self.z[BASE == 2] = -1e8
        self.head = [None, None]            # (bx, top, bottom) of each bike's newest column

    def column(self, b, i, j, d, q):
        """bike b, in the segment from centre (i, j) heading d, draws its column q"""
        team = 2 if b == 0 else 1
        ni, nj = i + DI[d], j + DJ[d]
        li, lj = min(i, ni), min(j, nj)
        di, dj = abs(DI[d]), abs(DJ[d])
        xs = centre(i, j)[0]
        xl, xr = sorted((centre(li, lj)[0], centre(li + di, lj + dj)[0]))
        bx = (xl >> 2) + q if xs == xl else (xr >> 2) - 1 - q
        ys = []
        for (x, y, dep) in edge_pixels(li, lj, li + di, lj + dj):
            if x >> 2 != bx:
                continue
            ys.append(y)
            if dep >= self.z[y, x]:
                self.z[y, x] = dep
                self.img[y, x] = blade_colour(team, x, y)
        self.head[b] = (bx, min(ys), max(ys))

def cursor_rows(top, bot):
    """the head's lines in each character row it touches: the cursor takes the first
    from the P step and the second from the User VIA interrupt"""
    return [(r, max(top, 8 * r), min(bot, 8 * r + 7)) for r in range(top >> 3, (bot >> 3) + 1)]

def camera(s, b):
    i, j, d, q = s['bi'][b], s['bj'][b], s['bd'][b], s['bq'][b]
    hx, hy = centre(i, j)
    hx += q * 4 * (1, -1, -1, 1)[d]
    hy += q * 2 * (1, 1, -1, -1)[d]
    wx = min(max(hx - WW // 2, 0), WORLDW - WW) & ~3
    wy = min(max(hy - 63, 0), WORLDH - 136) & ~1
    return wx, wy, hx, hy

G = {}
for line in open(os.path.join(os.path.dirname(__file__), '..', 'build', 'gen.inc')):
    if '=' in line and not line.startswith(' ') and ':' not in line:
        k, v = [t.strip() for t in line.split('=')]
        G[k] = int(v[1:], 16) if v.startswith('$') else int(v)
EXT, EXN = G['EXT'], G['EXN']
import pickle
EXC = pickle.load(open(os.path.join(os.path.dirname(__file__), '..', 'build', 'gen.pkl'), 'rb'))['EXC']

def fragment(s, t, k, wcx, wcy):
    """fragment k of frame t: {(x, y) window-relative to (4 wcx, 8 wcy): colour}, or
    None if it does not lie wholly in the window below its top character row"""
    if (t, k) not in EXC:
        return None
    o = k & s['fxmask']
    ox, oy = s['fxox'][o] - 4 * wcx, s['fxoy'][o] - 8 * wcy
    sp = quad_spans(EXC[(t, k)])
    ys = [oy + y for y in sp]
    if min(ys) < 8 or max(ys) > 135 or min(ox + a for a, _ in sp.values()) < 0 or max(ox + b for _, b in sp.values()) > WW - 1:
        return None
    team = s['fxteam'][o]
    out = {}
    for y, (a, b) in sp.items():
        for x in range(a, b + 1):
            X, Y = ox + x, oy + y
            out[(X, Y)] = blade_colour(team, X, Y)     # (the window origin is 4- and 8-aligned)
    return out

def explosion(s, b, wcx, wcy, frames, problems):
    """the fragments as the program says this window shows them (EXFRM), each
    checked to be a frame it could show, painted in order"""
    out = {}
    for k in range(EXN):
        t = frames[b * EXN + k]
        if t == 255:
            continue
        if not (s['fxt'] - 3 <= t <= s['fxt']) or t >= EXT:
            problems.append('window %d fragment %d shows frame %d at fxt %d' % (b, k, t, s['fxt']))
            continue
        px = fragment(s, t, k, wcx, wcy)
        if px is None:
            problems.append('window %d fragment %d frame %d claimed but not drawable' % (b, k, t))
            continue
        out.update(px)
    return out

# ---------------------------------------------------------------- per tick
def picture(arena, s, b, frames=None, problems=None):
    """window b's WW x 128 picture for snapshot s: (logical colours, cursor flags)"""
    wx, wy, hx, hy = camera(s, b)
    img = arena.img
    pic = img[wy:wy + 128, wx:wx + WW].copy()
    cur = np.zeros_like(pic)
    for hb in (0, 1):
        h = arena.head[hb]
        if h is None:
            continue
        bx, top, bot = h
        x = 4 * bx - wx
        if -4 < x < WW:
            y0, y1 = max(top - wy, 0), min(bot - wy + 1, 128)
            if y0 < y1:
                x0, x1 = max(x, 0), min(x + 4, WW)
                if hb == 0:                 # orange: the blades' dither, on x + y
                    yy, xx = np.mgrid[y0:y1, x0:x1]
                    pic[y0:y1, x0:x1] = np.where((xx + wx + yy + wy) & 1, 2, 3)
                else:
                    pic[y0:y1, x0:x1] = 1
    wcx, wcy = wx >> 2, wy >> 3
    if s['state'] == ST_PLAY and not s['bdead'][b] and arena.head[b]:
        bx, top, bot = arena.head[b]
        for r, a, c in cursor_rows(top, bot):
            if 1 <= r - wcy <= 16:
                x = 4 * bx - wx
                y0, y1 = max(a - wy, 0), min(c - wy + 1, 128)
                if 0 <= x < WW and y0 < y1:
                    cur[y0:y1, x:x + 4] = 1
                    pic[y0:y1, x:x + 4] = 0         # black under it: the glint shows white
    if frames:
        for (x, y), c in explosion(s, b, wcx, wcy, frames, problems).items():
            yy = y + 8 * wcy - wy
            if 0 <= yy < 128:
                pic[yy, x] = c
    return pic, cur, (wx, wy)

# ---------------------------------------------------------------- the stream
def records(f):
    while True:
        h = f.read(5)
        if len(h) < 5:
            return
        t, n = h[0:1], struct.unpack('<I', h[1:])[0]
        yield t, f.read(n)

def main():
    args = sys.argv[1:]
    nocur = '--nocursor' in args
    maxbad = 12
    arena = Arena()
    hist = [[], []]                 # per window: recent (snapshot, picture)
    prev = None
    pending = None
    recent = []
    stats = dict(fields=0, checked=0, bad=0, skipped=0, ticks=0, rounds=0, camera_bad=0)
    lags = {}
    xoff = None
    shown = 0
    last_lag = [None, None]
    badlog = []
    for t, data in records(sys.stdin.buffer):
        if t == b'R':
            arena = Arena(); prev = None; hist = [[], []]; pending = None
            stats['rounds'] += 1
        elif t == b'S':
            s = json.loads(data)
            stats['ticks'] += 1
            for b in (0, 1):
                key = (s['bi'][b], s['bj'][b], s['bd'][b], s['bq'][b])
                if s['bq'][b] >= 1 and (prev is None or key != prev[b]) and s['state'] != ST_TITLE:
                    arena.column(b, s['bi'][b], s['bj'][b], s['bd'][b], s['bq'][b] - 1)
            prev = [(s['bi'][b], s['bj'][b], s['bd'][b], s['bq'][b]) for b in (0, 1)]
            recent.append((stats['fields'], prev, s['wx'], s['wy']))
            del recent[:-8]
            for b in (0, 1):
                wx, wy, _, _ = camera(s, b)
                if (wx, wy) != (s['wx'][b], s['wy'][b]) and s['state'] != ST_TITLE:
                    stats['camera_bad'] += 1
            pending = s
        elif t == b'X':
            x = json.loads(data)
            w = x['w']
            if pending is None:
                continue
            s = pending
            if w == 1:
                pending = None
            fr = x['exfrm']
            probs = []
            pic = picture(arena, s, w, fr, probs)
            for p_ in probs:
                stats['fx_bad'] = stats.get('fx_bad', 0) + 1
                if stats['fx_bad'] < 10:
                    print('FX', p_, flush=True)
            s['_fr'] = fr
            s['_head'] = list(arena.head)
            hist[w].append((s, pic))
            hist[w] = hist[w][-4:]
        elif t == b'F':
            stats['fields'] += 1
            normal = data[0]
            live = data[1]
            fr = np.frombuffer(data[2:], np.uint8).reshape(264, FW)
            below = int((fr[256:264] != 0).sum())
            if below and normal:
                stats['below_bad'] = stats.get('below_bad', 0) + 1
                if stats['below_bad'] <= 3:
                    print('BELOW field %d: %d pixels lit under the bottom window, first at %s' % (stats['fields'], below, np.argwhere(fr[256:264] != 0)[0].tolist()), [(int(y), int(x), int(fr[256+y, x])) for y, x in np.argwhere(fr[256:264] != 0)], 'rows 250-255 at x:', fr[248:256, 0:12].tolist(), 'state', live, 'glr', hist[1][-1][0].get('glr') if hist[1] else None, 'htop', hist[1][-1][0].get('htop') if hist[1] else None, 'wy', hist[1][-1][0].get('wy') if hist[1] else None, flush=True)
            if not normal or min(len(hist[0]), len(hist[1])) < 3:
                stats['skipped'] += 1
                continue
            ok_states = (ST_PLAY, ST_CRASH)
            if any(h[0]['state'] not in ok_states for w in (0, 1) for h in hist[w][-3:]) or (pending and pending['state'] not in ok_states) or live not in ok_states:
                stats['skipped'] += 1
                continue
            if xoff is None:        # where the picture starts in what was sent
                best = None
                for xo in range(0, FW - WW + 1):
                    sc = sum(int((LUT_L[fr[128 * b:128 * b + 128, xo:xo + WW]] == hist[b][-1][1][0]).sum()) for b in (0, 1))
                    if best is None or sc > best[0]:
                        best = (sc, xo)
                xoff = best[1]
                print('model: picture at offset', xoff, best[0], '/', 2 * 128 * WW, flush=True)
            for b in (0, 1):
                got = fr[128 * b:128 * b + 128, xoff:xoff + WW]
                gl, gc = LUT_L[got], LUT_C[got]
                stats['checked'] += 1
                match = None
                for lag in range(1, min(4, len(hist[b])) + 1):
                    pic, cur, cam = hist[b][-lag][1]
                    if (gl == pic).all() and (nocur or (gc == cur).all()):
                        match = lag
                        break
                if match is not None:
                    lags[(b, match)] = lags.get((b, match), 0) + 1
                    continue
                stats['bad'] += 1
                # the nearest
                best = None
                for lag in range(1, min(4, len(hist[b])) + 1):
                    pic, cur, cam = hist[b][-lag][1]
                    n = int((gl != pic).sum()) + (0 if nocur else int((gc != cur).sum()))
                    if best is None or n < best[0]:
                        best = (n, lag)
                n, lag = best
                pic, cur, cam = hist[b][-lag][1]
                s = hist[b][-lag][0]
                dl = np.argwhere(gl != pic)
                dc = np.argwhere(gc != cur) if not nocur else np.zeros((0, 2), int)
                msg = ('BAD field %d window %d: nearest tick lag %d, %d pixels differ (%d colour, %d cursor); '
                       'state %d camera %s; first at %s' % (stats['fields'], b, lag, n, len(dl), len(dc), s['state'], cam,
                       (dl[0].tolist() if len(dl) else dc[0].tolist())))
                msg += ' glr %s htop %s hbot %s hbx %s modelhead %s' % (s.get('glr'), s.get('htop'), s.get('hbot'), s.get('hbx'), s.get('_head'))
                msg += ' fxt %s frames %s' % ([h[0]['fxt'] for h in hist[b]], [h[0].get('_fr', [])[8*b:8*b+8] for h in hist[b][-2:]])
                msg += ' recent %s' % recent
                badlog.append(msg)
                if shown < maxbad:
                    print(msg, flush=True)
                    dump(stats['fields'], b, gl, gc, pic, cur)
                    shown += 1
    print('model:', json.dumps(stats), 'lags', {'w%d lag%d' % k: v for k, v in sorted(lags.items())}, flush=True)
    open(os.path.join(OUT, 'bad.txt'), 'w').write('\n'.join(badlog) + '\n')

PAL = np.array([(0, 0, 0), (0, 255, 255), (255, 0, 255), (255, 255, 0)], np.uint8)

def dump(n, b, gl, gc, pic, cur):
    from PIL import Image
    def rgb(l, c):
        a = PAL[l].copy()
        a[c == 1] ^= 255
        return a
    diff = np.zeros((128, WW, 3), np.uint8)
    diff[(gl != pic) | (gc != cur)] = (255, 255, 255)
    im = np.concatenate([rgb(gl, gc), np.full((4, WW, 3), 80, np.uint8), rgb(pic, cur),
                         np.full((4, WW, 3), 80, np.uint8), diff])
    Image.fromarray(im).resize((960, im.shape[0] * 3), Image.NEAREST).save(
        os.path.join(OUT, 'bad_%05d_w%d.png' % (n, b)))

if __name__ == '__main__':
    main()
