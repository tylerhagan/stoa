"""Draws the Matte material's small key (menu buttons and other small parts).

    python3 Tools/art/matte_key.py [Media/Textures]

Both are 16x16 and nine-sliced at 5, with a 2 pixel corner:

- MatteKey.tga: a flat plate with no gloss, carrying its own black and
  white (drawn untinted): a faint face, a line of light along its top
  edge, a line of shade along its foot, and a dark line under it where
  it meets the block. The lines follow the corner.
- MatteKeyEdge.tga: the plate's outline alone, in white, for the hover.
"""
import sys

import numpy as np
from PIL import Image

out_dir = (sys.argv[1] if len(sys.argv) > 1 else "Media/Textures").rstrip("/\\")
SIZE, SS, RADIUS, UNDER = 16, 8, 2, 2

n = SIZE * SS
c = (np.arange(n) + 0.5) / SS
x, y = np.meshgrid(c, c)


def box(top, bottom):
    """Signed distance to a rounded rectangle spanning the full width."""
    cx, cy = SIZE / 2, (top + bottom) / 2
    qx, qy = np.abs(x - cx) - (SIZE / 2 - RADIUS), np.abs(y - cy) - ((bottom - top) / 2 - RADIUS)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - RADIUS


def save(name, layers):
    colour, alpha = np.zeros((n, n)), np.zeros((n, n))
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


plate = box(0, SIZE - UNDER)
shadow = box(UNDER, SIZE)
inside = plate < 0
rim = inside & (plate > -1)
save("MatteKey", [
    (shadow < 0, False, 0.75),
    (inside, True, 0.055),
    # Light where the rim faces up, shade where it faces down; the sides
    # keep a faint line so the plate's ends read.
    (rim, True, 0.05),
    (rim & (y < RADIUS), True, 0.17),
    (rim & (y > SIZE - UNDER - RADIUS), False, 0.5),
])
full = box(0, SIZE - UNDER)
save("MatteKeyEdge", [((full < 0) & (full > -1), True, 1.0)])
