"""Draws the Matte material's moulded pieces.

    python3 Tools/art/matte_parts.py [Media/Textures]

Both are 32x32 and nine-sliced at 12, with the windows' corner
(window_corners.py RADIUS), and carry their own black and white, so they
are drawn untinted:

- MatteBlock.tga: the shading laid over a card, plaque or window to make
  it a moulded block: light falling off its top, shade gathering at its
  bottom, clear in the middle and no lines.
- MatteWell.tga: a recess sunk into the console's shell, with a 4 pixel
  corner: a flat dark ground, a dark line under its top lip and a line of
  light where its bottom lip catches it.
- SharpBlock.tga: MatteBlock's place on windows and tooltips, in the
  language of the small key and the card: a 4 pixel corner, a line of
  light along the top edge, a faint line down the sides and a dark line
  two pixels deep along the foot. No gradients.
"""
import sys

import numpy as np
from PIL import Image

out_dir = (sys.argv[1] if len(sys.argv) > 1 else "Media/Textures").rstrip("/\\")
SIZE, SS, RADIUS = 32, 8, 7

n = SIZE * SS
c = (np.arange(n) + 0.5) / SS
x, y = np.meshgrid(c, c)


SHARP = 4


def box(shift=0.0, bottom=SIZE, radius=RADIUS):
    """Signed distance to the rounded square, moved down by `shift`."""
    top = shift
    cx, cy = SIZE / 2, (top + bottom + shift) / 2
    half_w, half_h = SIZE / 2, (bottom + shift - top) / 2
    qx, qy = np.abs(x - cx) - (half_w - radius), np.abs(y - cy) - (half_h - radius)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - radius


def save(name, layers):
    """`layers` are (mask, white?, alpha), later ones over earlier ones.
    `alpha` may be an array, for shading that falls away."""
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


def fall(distance, reach):
    """1 at the edge, easing to nothing `reach` texels in."""
    return np.clip(1 - distance / reach, 0, 1) ** 2


# No lines anywhere: like moulded matte plastic, a shape shows only by the
# light falling off its top and the shade gathering under it.
block = box()
inside = block <= 0
save("MatteBlock", [
    (inside & (y > SIZE / 2), False, 0.3 * fall(SIZE - y, 5.0)),
    (inside & (y <= SIZE / 2), True, 0.09 * fall(y, 4.0)),
])

well = box(radius=SHARP)
inside = well <= 0
rim = inside & (well > -1)
save("MatteWell", [
    (inside, False, 0.5),
    (rim & (y < SHARP), False, 0.82),
    (rim & (y > SIZE - SHARP), True, 0.10),
])

sharp = box(radius=SHARP)
inside = sharp <= 0
rim = inside & (sharp > -1)
save("SharpBlock", [
    (rim, True, 0.05),
    (rim & (y < SHARP), True, 0.17),
    (inside & (sharp > -2) & (y > SIZE - SHARP), False, 0.6),
])
