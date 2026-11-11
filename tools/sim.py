#!/usr/bin/env python3
"""Reference model of the game's trail drawing, done the way the 6502 does it (map
of tile ids, growth table, transition table), checked against a direct per-pixel
render of the same trails with the prototype's rules.  Writes build/sim_*.png."""
import os, sys, pickle
sys.path.insert(0, os.path.dirname(__file__))
from geom import *
from PIL import Image
G = pickle.load(open(os.path.join(os.path.dirname(__file__), '..', 'build', 'gen.pkl'), 'rb'))
images, trans, GROW = G['images'], G['trans'], G['GROW']
PAL = {0: (0, 0, 0), 1: (0, 255, 255), 2: (255, 0, 255), 3: (255, 255, 0)}

DIRS = [(1, 0), (0, 1), (-1, 0), (0, -1)]          # +i, +j, -i, -j

class World:
    def __init__(self):
        self.map = [row[:] for row in G['initmap']]
    def grow(self, i, j, d, q, team):
        """bike at centre (i, j) heading d has drawn q columns (0..3): draw column q"""
        if d == 0:   e, qq = (i, j, 1), q
        elif d == 2: e, qq = (i - 1, j, 1), 3 - q
        elif d == 1: e, qq = (i, j, 0), 3 - q
        else:        e, qq = (i, j - 1, 0), q
        ei, ej, di = e
        xa, ya = centre(ei, ej)
        p = (ei + ej) & 1
        cells = []
        for (dbx, dty, s, px) in GROW[(di, p, qq)]:
            bx, ty = (xa >> 2) + dbx, (ya >> 4) + dty
            self.map[ty][bx] = trans.get((s, team, self.map[ty][bx]), self.map[ty][bx])
            cells.append((bx, ty))
        return cells
    def image(self):
        img = Image.new('RGB', (WORLDW, WORLDH))
        px = img.load()
        for ty in range(MAPH):
            for bx in range(MAPW):
                im = images[self.map[ty][bx]]
                for y in range(16):
                    for x in range(4):
                        px[bx * 4 + x, ty * 16 + y] = PAL[im[y][x]]
        return img

def direct(trails):
    fb = {}; zb = {}
    for (x, y) in grid_points():
        fb[(x, y)] = 2; zb[(x, y)] = -1e8
    for team, wps in trails:
        for p, q in zip(wps, wps[1:]):
            # segment from p to q, possibly several cells: unit segments
            (i0, j0), (i1, j1) = p, q
            n = abs(i1 - i0) + abs(j1 - j0)
            si, sj = (i1 > i0) - (i1 < i0), (j1 > j0) - (j1 < j0)
            for k in range(n):
                a = (i0 + si * k, j0 + sj * k); b = (a[0] + si, a[1] + sj)
                lo, hi = sorted((a, b))
                for (x, y, d) in edge_pixels(*lo, *hi):
                    if d >= zb.get((x, y), -1e9):
                        zb[(x, y)] = d; fb[(x, y)] = blade_colour(team, x, y)
    img = Image.new('RGB', (WORLDW, WORLDH)); px = img.load()
    for (x, y), c in fb.items():
        if 0 <= x < WORLDW and 0 <= y < WORLDH:
            px[x, y] = PAL[c]
    return img

def run_trails(w, trails):
    for team, wps in trails:
        for p, q in zip(wps, wps[1:]):
            (i0, j0), (i1, j1) = p, q
            n = abs(i1 - i0) + abs(j1 - j0)
            si, sj = (i1 > i0) - (i1 < i0), (j1 > j0) - (j1 < j0)
            d = DIRS.index((si, sj))
            for k in range(n):
                for q4 in range(4):
                    w.grow(i0 + si * k, j0 + sj * k, d, q4, team)

if __name__ == '__main__':
    # the memo's scene, moved into this arena
    o = (9, 9)
    sh = lambda l: [(a + o[0], b + o[1]) for a, b in l]
    trails = [(2, sh([(1, 2), (6, 2), (6, 7), (10, 7), (10, 4), (12, 4)])),
              (1, sh([(2, 12), (2, 9), (8, 9), (8, 11), (12, 11), (12, 8)]))]
    w = World(); run_trails(w, trails)
    a = w.image(); b = direct(trails)
    diff = [(x, y) for y in range(WORLDH) for x in range(WORLDW) if a.getpixel((x, y)) != b.getpixel((x, y))]
    print("sim: %d pixels differ from the direct render" % len(diff), diff[:10])
    out = os.path.join(os.path.dirname(__file__), '..', 'build')
    cx, cy = centre(o[0] + 7, o[1] + 7)
    box = (cx - 160, cy - 128, cx + 160, cy + 128)
    a.crop(box).resize((960, 768), Image.NEAREST).save(os.path.join(out, 'sim_scene.png'))
    # every combination: random trails all over
    import random
    random.seed(1)
    trails = []
    for t in range(60):
        i, j = random.randrange(N), random.randrange(N); wp = [(i, j)]
        for s in range(6):
            d = random.choice(DIRS); n = random.randint(1, 5)
            ni, nj = i + d[0] * n, j + d[1] * n
            if 0 <= ni < N and 0 <= nj < N:
                i, j = ni, nj; wp.append((i, j))
        trails.append((random.choice((1, 2)), wp))
    w = World(); run_trails(w, trails)
    a = w.image(); b = direct(trails)
    diff = sum(1 for y in range(WORLDH) for x in range(WORLDW) if a.getpixel((x, y)) != b.getpixel((x, y)))
    print("sim: random trails, %d pixels differ (overlap order may differ)" % diff)
    a.save(os.path.join(out, 'sim_world.png'))
