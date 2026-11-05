"""Cuts the console's leather tile from Tyler's leather texture.

    python3 Tools/art/leather_tile.py [source] [out]

The source (Tools/art/source/console-leather.png) is resized to 2048x512,
its slow light changes are levelled out so the repeat doesn't show as a
light or dark band, and its edges are cross-faded into the opposite edges
so it tiles without a seam. Written as Media/Textures/ConsoleLeather.tga.
Console.lua draws it one texel per screen pixel. Textures need a full game
restart to load.
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

W, H = 2048, 512
# How much of the grain's contrast is kept (1 = as painted), and a slight
# blur in tile pixels: in game the full-contrast grain read too crisp.
GRAIN = 0.55
SOFTEN = 0.8
OVERLAP_X, OVERLAP_Y = 256, 96

src = sys.argv[1] if len(sys.argv) > 1 else "Tools/art/source/console-leather.png"
out = sys.argv[2] if len(sys.argv) > 2 else "Media/Textures/ConsoleLeather.tga"

im = Image.open(src).convert("RGB")
# Resize a little larger than the tile so the cross-fades have room.
big = im.resize((W + OVERLAP_X, H + OVERLAP_Y), Image.LANCZOS)
a = np.asarray(big).astype(np.float64)

# Level slow light changes: divide the brightness by a heavy blur of itself,
# keeping the overall tone. The blur is done in floats (shrink, then grow
# smoothly back): an 8-bit blur of a near-black image steps in 4% bands that
# show up as outlines once divided out.
luma = a @ np.array([0.299, 0.587, 0.114])
small = Image.fromarray(luma.astype(np.float32), "F").resize(
    (max(1, luma.shape[1] // 96), max(1, luma.shape[0] // 96)), Image.BOX)
slow = np.asarray(small.resize((luma.shape[1], luma.shape[0]), Image.BICUBIC)).astype(np.float64)
a = a * (luma.mean() / np.maximum(slow, 1))[:, :, None]


def fade(n):
    t = np.linspace(0, 1, n)
    return t * t * (3 - 2 * t)  # smoothstep


# Horizontal seam: the last OVERLAP_X columns fade into the first ones.
w = fade(OVERLAP_X)[None, :, None]
head = a[:, :OVERLAP_X]
tail = a[:, W:W + OVERLAP_X]
a = a[:, :W].copy()
a[:, :OVERLAP_X] = tail * (1 - w) + head * w

# Vertical seam, the same way.
h = fade(OVERLAP_Y)[:, None, None]
top = a[:OVERLAP_Y]
bottom = a[H:H + OVERLAP_Y]
a = a[:H].copy()
a[:OVERLAP_Y] = bottom * (1 - h) + top * h

# Softer grain: pull every pixel part way to the overall tone, then a touch
# of blur.
tone = a.reshape(-1, 3).mean(axis=0)
a = tone + (a - tone) * GRAIN
rgb = np.clip(a, 0, 255).astype(np.uint8)
if SOFTEN > 0:
    # Blur a 3x3 tiled copy so the edges still meet.
    tiled = Image.fromarray(np.tile(rgb, (3, 3, 1)))
    blurred = np.asarray(tiled.filter(ImageFilter.GaussianBlur(SOFTEN)))
    rgb = blurred[H:2 * H, W:2 * W].copy()
alpha = np.full((H, W, 1), 255, np.uint8)
Image.fromarray(np.concatenate([rgb, alpha], axis=2), "RGBA").save(out)
print(out, W, H, "mean", rgb.reshape(-1, 3).mean(axis=0).round(1))
