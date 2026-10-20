"""Textures of ElvUI_Forever, drawn from shapes (same look as the Forever Modern
nameplates of the TidyPlates_WoTLK fork). Needs Pillow.
Usage: python tools/textures.py [outdir]   (default ElvUI_Forever/media)

Bar.tga     dark, nearly opaque background (unit frames sit on the game world; the
            nameplates' 60-80 % let the ground show through on large castbars) with a
            1.5 px light gray rim, rounded corners (radius 4) and a thin dark outline;
            region 88,0 - 220,18, nine-slice margins 6/9/6/8
Rim.tga     the same rim and outline without the background, drawn above the fill:
            it covers the fill's square corners, so the fill looks rounded at any size
UnitFill    left-to-right gradient 53 % -> 100 %, tinted by the bar color
CastFill    castbar: glossy fill (bright band at the top, darker towards the bottom,
            70 -> 100 % left to right), plain without brush strokes"""
import math
import sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "ElvUI_Forever/media"
SS = 4  # supersampling per axis


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def rrect_sdf(px, py, x0, y0, x1, y1, r):
    """Signed distance to a rounded rectangle (negative inside)."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = abs(px - cx) - hx, abs(py - cy) - hy
    out = math.hypot(max(qx, 0), max(qy, 0))
    return out + min(max(qx, qy), 0) - r


def coverage(fn, x, y):
    n = 0
    for i in range(SS):
        for j in range(SS):
            if fn(x + (i + 0.5) / SS, y + (j + 0.5) / SS):
                n += 1
    return n / (SS * SS)


def over(dst, src):
    """Straight-alpha 'over' of two (r, g, b, a) float tuples (0..1)."""
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    oa = sa + da * (1 - sa)
    if oa <= 0:
        return (sr, sg, sb, 0.0)
    f = da * (1 - sa)
    return ((sr * sa + dr * f) / oa, (sg * sa + dg * f) / oa, (sb * sa + db * f) / oa, oa)


def put(im, x, y, c):
    im.putpixel((x, y), tuple(int(round(clamp(v) * 255)) for v in c))


def save(im, name):
    # Pillow writes uncompressed TGA with bottom-left origin, which this client loads
    im.save(f"{OUT}/{name}.tga")


# Region 88,0 - 220,18 (132 x 18) in a 256 x 32 texture. Placed around a bar with the
# outsets 3/5/3/5 the rim lies 1.5 px outside the bar.
X0, W, H = 88, 132, 18
RECT = (1.5, 1.5, W - 3.5, 14.5)
R = 4
RIM = 1.5
RIM_COL = (0.62, 0.6, 0.56)


def frame_texture(with_background):
    im = Image.new("RGBA", (256, 32), (0, 0, 0, 0))
    for y in range(H):
        for x in range(W):
            px, py = x + 0.5, y + 0.5
            d = rrect_sdf(px, py, *RECT, R)
            c = (0, 0, 0, 0)
            rim = coverage(lambda u, v: -RIM <= rrect_sdf(u, v, *RECT, R) < 0, x, y)
            inside = coverage(lambda u, v: rrect_sdf(u, v, *RECT, R) < -RIM, x, y)
            edge = coverage(lambda u, v: 0 <= rrect_sdf(u, v, *RECT, R) < 1, x, y)
            if edge:
                c = over(c, (0, 0, 0, 0.55 * edge))
            if inside and with_background:
                t = clamp((py - 3.5) / 9.0)
                base = 0.88 + 0.08 * (2 * t - 1) ** 2
                dd = max(0.0, -d - 1.5)
                a = base + (1 - base) * 0.78 * 0.5 ** dd
                c = over(c, (0.01, 0.01, 0.01, a * inside))
            if rim:
                c = over(c, RIM_COL + (rim,))
            put(im, X0 + x, y, c)
    save(im, "Bar" if with_background else "Rim")


def unit_fill():
    im = Image.new("RGBA", (128, 16))
    for x in range(128):
        v = 0.53 + 0.47 * x / 127
        for y in range(16):
            put(im, x, y, (v, v, v, 1))
    save(im, "UnitFill")


def cast_fill():
    W2, H2 = 512, 16
    # vertical gloss profile: thin highlight just below the top edge, then a soft fall-off
    gloss = [0.82, 1.0, 1.0, 0.9, 0.82, 0.78, 0.76, 0.75, 0.74, 0.73, 0.72, 0.71, 0.7, 0.68, 0.65, 0.6]
    im = Image.new("RGBA", (W2, H2))
    for y in range(H2):
        for x in range(W2):
            v = gloss[y] * (0.7 + 0.3 * x / (W2 - 1))
            put(im, x, y, (v, v, v, 1))
    save(im, "CastFill")


frame_texture(True)
frame_texture(False)
unit_fill()
cast_fill()
