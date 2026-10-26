# The small leather and brass ring for portrait coins and the Halo's
# signature slot, cut from source/coin-ring.png (Tyler's painting, made with
# a slim inner rim; the hairline, leather and bold versions are kept beside it).
#
#   python3 coin_frame.py source ../../Media/Textures
#
# 128x128, centred on the opening, which is 88 texels across unless the
# ring needs more room. Grey base plus white-with-alpha lines, as on the
# console. Prints how much wider than the opening the frame is
# (COIN_FRAME_SCALE in Core/Widgets.lua).
import sys
from PIL import Image
import numpy as np
from scipy import ndimage

src, out_dir = sys.argv[1], sys.argv[2]
SIZE, OPEN = 128, 88

a = np.array(Image.open(f"{src}/coin-ring.png").convert("RGBA")).astype(float)
h, w = a.shape[:2]
# Drop stray specks and the reddish fringe some generated art carries.
solid = ndimage.binary_opening(a[..., 3] > 40, iterations=2)
lab, n = ndimage.label(solid)
sizes = ndimage.sum(solid, lab, range(1, n + 1))
keep = ndimage.binary_dilation(np.isin(lab, 1 + np.where(sizes > 5000)[0]), iterations=3)
r, g = a[..., 0], a[..., 1]
fringe = (r > 120) & (g < 0.45 * r) & (a[..., 3] < 250)
a[..., 3] = np.where(keep & ~fringe, a[..., 3], 0)

# The opening: the clear region holding the centre.
lab, _ = ndimage.label(a[..., 3] < 128)
ys, xs = np.where(lab == lab[h // 2, w // 2])
ox, oy = (xs.min() + xs.max() + 1) / 2, (ys.min() + ys.max() + 1) / 2
open_w = xs.max() + 1 - xs.min()
yy, xx = np.nonzero(a[..., 3] > 8)
half = max(open_w / 2 * SIZE / OPEN, np.hypot(xx - ox, yy - oy).max() + 2)

# Square canvas centred on the opening.
H = int(np.ceil(2 * half)) + 2
canvas = np.zeros((H, H, 4))
x0, y0 = int(round(H / 2 - ox)), int(round(H / 2 - oy))
sx, sy, dx, dy = max(0, -x0), max(0, -y0), max(0, x0), max(0, y0)
cw, ch = min(w - sx, H - dx), min(h - sy, H - dy)
canvas[dy:dy + ch, dx:dx + cw] = a[sy:sy + ch, sx:sx + cw]
c0 = int(round(H / 2 - half))
canvas = canvas[c0:c0 + int(round(2 * half)), c0:c0 + int(round(2 * half))]
canvas[..., :3] *= canvas[..., 3:4] / 255
im = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8), "RGBA")
px = np.array(im.resize((SIZE, SIZE), Image.LANCZOS)).astype(float)
al = px[..., 3:4]
px[..., :3] = np.where(al > 0, px[..., :3] * 255 / np.maximum(al, 1e-6), 0)


def brass(p):
    r, g, b = p[..., 0], p[..., 1], p[..., 2]
    chroma = np.clip((r - b - 12) / 48, 0, 1)
    lum = 0.30 * r + 0.59 * g + 0.11 * b
    return chroma * np.clip(lum / 190, 0, 1) ** 1.1


lum = 0.30 * px[..., 0] + 0.59 * px[..., 1] + 0.11 * px[..., 2]
base = np.dstack([lum, lum, lum, px[..., 3]])
white = np.full(lum.shape, 255.0)
lines = np.dstack([white, white, white, brass(px) * px[..., 3]])
Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGBA").save(f"{out_dir}/CoinFrame.tga")
Image.fromarray(np.clip(lines, 0, 255).astype(np.uint8), "RGBA").save(f"{out_dir}/CoinFrameLines.tga")
print(f"CoinFrame: frame is {2 * half / open_w:.3f} x the opening's width")
