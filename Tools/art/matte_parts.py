"""Draws the Matte material's moulded pieces.

    python3 Tools/art/matte_parts.py [Media/Textures]

Both are 32x32 and nine-sliced at 12, with the windows' corner
(window_corners.py RADIUS), and carry their own black and white, so they
are drawn untinted:

- MatteBlock.tga: the bevel laid over a card, plaque or window to make it
  a moulded block: a lit band along the top, a dark one along the bottom,
  a fine dark line round the sides, clear in the middle.
- MatteWell.tga: a recess sunk into the console's shell: a dark smooth
  ground, a shadow under its top lip and a lit line under its bottom edge.
"""
import sys

import numpy as np
from PIL import Image

out_dir = (sys.argv[1] if len(sys.argv) > 1 else "Media/Textures").rstrip("/\\")
SIZE, SS, RADIUS = 32, 8, 7

n = SIZE * SS
c = (np.arange(n) + 0.5) / SS
x, y = np.meshgrid(c, c)


def box(shift=0.0, bottom=SIZE):
    """Signed distance to the rounded square, moved down by `shift`."""
    top = shift
    cx, cy = SIZE / 2, (top + bottom + shift) / 2
    half_w, half_h = SIZE / 2, (bottom + shift - top) / 2
    qx, qy = np.abs(x - cx) - (half_w - RADIUS), np.abs(y - cy) - (half_h - RADIUS)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - RADIUS


def save(name, layers):
    """`layers` are (mask, white?, alpha), later ones over earlier ones."""
    colour = np.zeros((n, n))
    alpha = np.zeros((n, n))
    for mask, white, strength in layers:
        colour = np.where(mask, 1.0 if white else 0.0, colour)
        alpha = np.where(mask, strength, alpha)

    def down(a):
        return a.reshape(SIZE, SS, SIZE, SS).mean(axis=(1, 3))

    a = down(alpha)
    tone = np.divide(down(colour * alpha), a, out=np.zeros_like(a), where=a > 0)
    img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    img[..., :3] = np.round(tone * 255)[..., None]
    img[..., 3] = np.round(a * 255)
    Image.fromarray(img, "RGBA").save("%s/%s.tga" % (out_dir, name))
    print(name, "alpha", int(img[..., 3].min()), int(img[..., 3].max()))


block = box()
save("MatteBlock", [
    ((block <= 0) & (block > -1.0), False, 0.4),
    ((block <= 0) & (box(-2.6) > 0), False, 0.6),
    ((block <= 0) & (box(2.4) > 0), True, 0.22),
])

# The well keeps its last row for the lit line under its bottom edge.
well = box(bottom=SIZE - 1)
save("MatteWell", [
    ((well > 0) & (box(1.0, bottom=SIZE - 1) <= 0), True, 0.14),
    (well <= 0, False, 0.5),
    ((well <= 0) & (box(3.0, bottom=SIZE - 1) > 0), False, 0.78),
])
