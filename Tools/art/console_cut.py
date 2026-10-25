# Console art from one painting: the top edge strip and the medallion,
# each as a grey base plus white-with-alpha brass lines (the theme accent
# tints the lines in game).
#
#   python3 console_cut.py source/console-basis.png ../../Media/Textures
#
# The painting is scaled so the medallion's inner ring has a 122 texel
# radius, and its slightly wide ring is pulled into a true circle. The
# medallion keeps both brass rings all the way round: the outer one runs
# from the flares down under the seal and back up. Prints the rows the
# console code needs (Modules/Grimoire/Console.lua).
import sys
from PIL import Image
import numpy as np

src, out_dir = sys.argv[1], sys.argv[2]
RING = 122.0          # inner ring radius in texels
EDGE_LINE = 43        # edge strip row of the brass line's centre
MED_LINE = 263        # medallion row of the same line
MED_CX = 255.5

img = Image.open(src).convert("RGBA")
a = np.array(img).astype(float)


def brass(px):
    # warm, lit pixels: chroma (red over blue) times brightness
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    chroma = np.clip((r - b - 12) / 48, 0, 1)
    lum = 0.30 * r + 0.59 * g + 0.11 * b
    return chroma * np.clip(lum / 190, 0, 1) ** 1.1


# Find the ring in the painting: the inner ring's brass ridge along rays
# from a rough centre, then an axis-aligned ellipse through it.
B = brass(a) * (a[..., 3] > 200)
cx0, cy0 = a.shape[1] / 2 - 1, 446.0
pts = []
for t in np.radians(np.r_[200:340:4, 25:155:4]):  # below the line, and the dome
    rs = np.arange(85, 118, 0.5)
    xs, ys = cx0 + rs * np.cos(t), cy0 + rs * np.sin(t)
    v = B[ys.astype(int), xs.astype(int)]
    if v.max() > 0.3:
        # the inner ring is the first ridge going out
        i = np.argmax(v > 0.3 * v.max())
        j = i + np.argmax(v[i:i + 8])
        pts.append((xs[j], ys[j]))
pts = np.array(pts)
# x^2 A + y^2 C + x D + y E = 1
M = np.c_[pts[:, 0] ** 2, pts[:, 1] ** 2, pts[:, 0], pts[:, 1]]
A_, C_, D_, E_ = np.linalg.lstsq(M, np.ones(len(pts)), rcond=None)[0]
cx, cy = -D_ / (2 * A_), -E_ / (2 * C_)
k = 1 + D_ ** 2 / (4 * A_) + E_ ** 2 / (4 * C_)
rx, ry = np.sqrt(k / A_), np.sqrt(k / C_)

# The brass line along the top: weighted row over the plain panel.
col = B[:, 200:int(cx - 400)].mean(1)
band = np.arange(int(cy), int(cy) + 30)
yl = (band * col[band] ** 2).sum() / (col[band] ** 2).sum()

# and the bottom line, the first strong brass row under the ring
colb = B[:, 200:int(cx - 400)].mean(1)
yb = int(cy + ry) + np.argmax(colb[int(cy + ry):] > 0.3)

s = RING / rx
print(f"painting ring centre {cx:.1f},{cy:.1f} radii {rx:.1f}x{ry:.1f}, line row {yl:.1f}, scale {s:.3f}")

# premultiplied, so soft edges don't pick up dark fringes
pm = a.copy()
pm[..., :3] *= pm[..., 3:4] / 255


def sample(xx, yy):
    # bilinear sample of the premultiplied painting at painting coords
    h, w = pm.shape[:2]
    x0 = np.clip(np.floor(xx).astype(int), 0, w - 2); fx = np.clip(xx - x0, 0, 1)[..., None]
    y0 = np.clip(np.floor(yy).astype(int), 0, h - 2); fy = np.clip(yy - y0, 0, 1)[..., None]
    top = pm[y0, x0] * (1 - fx) + pm[y0, x0 + 1] * fx
    bot = pm[y0 + 1, x0] * (1 - fx) + pm[y0 + 1, x0 + 1] * fx
    return top * (1 - fy) + bot * fy


def unpremultiply(px):
    al = px[..., 3:4]
    px[..., :3] = np.where(al > 0, px[..., :3] * 255 / np.maximum(al, 1e-6), 0)
    return px


def haze(alpha):
    # The painting's drop shadow above the panel is long; over the world it
    # reads as haze, so keep only its last soft few texels.
    return np.clip((alpha - 222) / 28, 0, 1) * 255


def save(px, lines_alpha, name):
    lum = 0.30 * px[..., 0] + 0.59 * px[..., 1] + 0.11 * px[..., 2]
    base = np.dstack([lum, lum, lum, px[..., 3]])
    Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGBA").save(f"{out_dir}/{name}.tga")
    white = np.full(px.shape[:2], 255.0)
    lines = np.dstack([white, white, white, lines_alpha * px[..., 3]])
    Image.fromarray(np.clip(lines, 0, 255).astype(np.uint8), "RGBA").save(f"{out_dir}/{name}Lines.tga")


# Edge strip: 16x64, the panel's profile averaged along the plain stretch.
rows = np.arange(64, dtype=float)
py = yl + (rows - EDGE_LINE) / s
xs = np.arange(200, int(cx - 400), 2, dtype=float)
XX, YY = np.meshgrid(xs, py)
strip = sample(XX, YY).mean(1)
strip = unpremultiply(strip[:, None, :].repeat(1, 1))[:, 0]
strip[:, 3] = haze(strip[:, 3])
edge = np.repeat(strip[:, None, :], 16, 1)
save(edge, brass(edge), "ConsoleEdge")

# Medallion: 512x512 around the ring, at the same scale and line row.
yy, xx = np.mgrid[0:512, 0:512].astype(float)
MED_CY = MED_LINE - (yl - cy) * s
dx, dy = xx - MED_CX, yy - MED_CY
d = np.hypot(dx, dy)
# pull the ring round: squash the wide axis near the ring, fading out
# past the outer ring so the flares meet the line where they did
w = np.clip((172 - d) / 18, 0, 1)
px_x = cx + dx / s
px_y = cy + dy / s * ((ry / rx) * w + (1 - w))
med = unpremultiply(sample(px_x, px_y))
med[..., 3] = haze(med[..., 3])
# Below the panel top only the rings and their shading stay; the leather
# tile shows around them. The line band itself stays, fading at the sides
# where the edge strip carries on.
line_d = yy - MED_LINE
band_keep = np.clip((9 - line_d) / 4, 0, 1)
ring_keep = np.clip((150 - d) / 8, 0, 1)
side = np.clip((252 - np.abs(dx)) / 22, 0, 1)
# The painting's bottom line runs just under the rings; the console has
# no line there, so stop above it.
foot = np.clip((yb - 2.5 - px_y) * s / 2, 0, 1)
med[..., 3] *= np.maximum(band_keep, ring_keep * foot) * side
save(med, brass(med), "ConsoleMedallion")

print(f"MEDALLION_CENTRE = {MED_CY:.1f}")
# how far the flares reach along the line, for the console's layout
reach = np.where(brass(med)[MED_LINE - 14] > 0.25)[0]
if len(reach):
    print(f"MEDALLION_REACH ~ {max(MED_CX - reach.min(), reach.max() - MED_CX):.0f}")
# where the panel goes solid in the edge strip
print("EDGE_TOP ~", int(np.argmax(edge[:, 8, 3] > 200)))
