import math
"""Arena geometry shared by the asset generator and the tests.

World coordinates are MODE 1 screen pixels across (x) and scanlines down (y) over
the whole arena image.  Cell (i, j) has its centre at
    x = X0 + (i - j) * 16,   y = Y0 + (i + j) * 8          (the memo's formula)
X0 is a multiple of 32, so a byte column's class is simply bx & 7; Y0 & 15 = 7 is
the row phase at which every 4-pixel x 16-line tile is touched by at most three
blade segments (tools/gen.py checks this).
"""
N = 32                      # cells per side
X0 = N * 16 + 32            # 544 = 17 * 32
Y0 = 23                     # 23 & 15 = 7
MAPW = 2 * X0 // 4          # 272 byte columns (1088 pixels)
MAPH = 34                   # tile rows of 16 lines: the floor ends at y = 527
WORLDW = MAPW * 4
WORLDH = MAPH * 16

def centre(i, j):
    return X0 + (i - j) * 16, Y0 + (i + j) * 8

def edge_pixels(i0, j0, i1, j1):
    """The prototype's draw_segment, minus the far endpoint column of a j blade
    (which belongs to the next segment's byte span): a segment owns exactly the 8 lit
    columns of its own 4 byte columns.  Yields (x, y, depth)."""
    xa, ya = centre(i0, j0)
    xb, yb = centre(i1, j1)
    along_i = (j0 == j1)
    par = 1 if along_i else 0
    lo, hi = sorted((xa, xb))
    for x in range(lo, hi):
        if x & 1 != par:
            continue
        t = (x - xa) / (xb - xa)
        g = int(ya + t * (yb - ya))
        d = (i0 + j0) + t * ((i1 + j1) - (i0 + j0))
        for y in range(g - 7, g + 1):
            yield (x, y, d)

GRIDX = 0.75                # each grid line runs on this far past the outermost ones
def grid_points():
    """The floor: sparse magenta dots (every 4th column) along the grid lines the
    bikes ride, i = k and j = k through the cell centres, k = 0..N-1.  Each line
    runs on 3/4 of a cell past the arena, so the tiles at the floor's edge carry the
    interior's dots (which keeps the tile set under 252)."""
    pts = set()
    for k in range(N):
        for (a0, b0, da, db) in ((k, 0, 0, 1), (0, k, 1, 0)):
            xa, ya = centre(a0 - da * GRIDX, b0 - db * GRIDX)
            xb, yb = centre(a0 + da * (N - 1 + GRIDX), b0 + db * (N - 1 + GRIDX))
            lo, hi = sorted((int(xa), int(xb)))
            for x in range(lo, hi + 1):
                if x % 4:
                    continue
                t = (x - xa) / (xb - xa)
                pts.add((x, round(ya + t * (yb - ya))))
    return pts

def blade_colour(team, x, y):
    """team 1 cyan, 2 orange (magenta/yellow dither keyed on x + y)."""
    if team == 1:
        return 1
    return 2 if (x + y) & 1 else 3

EDGES = [(i, j, di, dj) for i in range(N) for j in range(N)
         for (di, dj) in ((1, 0), (0, 1)) if i + di < N and j + dj < N]

def quad_spans(corners):
    """A convex quad's pixels (those whose centres are inside), as {line: (x0, x1)},
    inclusive.  The explosion's fragments, in tools/gen.py and tools/model.py."""
    ys = [y for _, y in corners]
    out = {}
    n = len(corners)
    for y in range(int(min(ys)) - 1, int(max(ys)) + 2):
        cy = y + 0.5
        xs = []
        for i in range(n):
            (x0, y0), (x1, y1) = corners[i], corners[(i + 1) % n]
            if (y0 <= cy < y1) or (y1 <= cy < y0):
                xs.append(x0 + (cy - y0) * (x1 - x0) / (y1 - y0))
        if len(xs) >= 2:
            a, b = min(xs), max(xs)
            x0, x1 = math.ceil(a - 0.5), math.floor(b - 0.5)
            if x0 <= x1:
                out[y] = (x0, x1)
    return out
