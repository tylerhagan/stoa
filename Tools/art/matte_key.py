"""Draws the Matte material's small plates: the key (menu buttons) and the
card (party cards, target, tank watch, pet and target-of-target blocks).

    python3 Tools/art/matte_key.py [Media/Textures]

The key is 16x16, nine-sliced at 5, with a 2 pixel corner; the card is
24x24, nine-sliced at 8, with a 4 pixel corner. Otherwise they match:

- MatteKey.tga / MatteCard.tga: a flat plate with no gloss, carrying its
  own black and white (drawn untinted): a faint face, a line of light
  along its top edge, a line of shade along its foot, and a dark line
  under it where it meets the block. The lines follow the corner.
- MatteKeyEdge.tga: the key's outline alone, in white, for the hover.
- MatteCardFill.tga: the whole card's shape (plate and the line under
  it) in solid white, for the panel colour behind MatteCard.
- MatteCardState.tga: a 2 pixel outline around that whole shape, in
  white, for a card's state (dispel, danger, your target).
- MatteBarCorners.tga: 8x8, nine-sliced at 3: everything outside a
  2 pixel corner, in white. Tinted to the card's colour and laid over a
  square health bar, it rounds the bar's corners without a mask.
"""
import sys

import numpy as np
from PIL import Image

out_dir = (sys.argv[1] if len(sys.argv) > 1 else "Media/Textures").rstrip("/\\")
SS, UNDER = 8, 2


def grid(size):
    c = (np.arange(size * SS) + 0.5) / SS
    return np.meshgrid(c, c)


def box(size, radius, top, bottom):
    """Signed distance to a rounded rectangle spanning the full width."""
    x, y = grid(size)
    cx, cy = size / 2, (top + bottom) / 2
    qx, qy = np.abs(x - cx) - (size / 2 - radius), np.abs(y - cy) - ((bottom - top) / 2 - radius)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - radius


def save(name, size, layers):
    n = size * SS
    colour, alpha = np.zeros((n, n)), np.zeros((n, n))
    for mask, white, strength in layers:
        colour = np.where(mask, 1.0 if white else 0.0, colour)
        alpha = np.where(mask, strength, alpha)

    def down(a):
        return a.reshape(size, SS, size, SS).mean(axis=(1, 3))

    a = down(alpha)
    tone = np.divide(down(colour * alpha), a, out=np.zeros_like(a), where=a > 0)
    img = np.zeros((size, size, 4), dtype=np.uint8)
    img[..., :3] = np.round(tone * 255)[..., None]
    img[..., 3] = np.round(a * 255)
    Image.fromarray(img, "RGBA").save("%s/%s.tga" % (out_dir, name))
    print(name, "alpha", int(img[..., 3].min()), int(img[..., 3].max()))


def plate_set(name, size, radius, card):
    _, y = grid(size)
    plate = box(size, radius, 0, size - UNDER)
    shadow = box(size, radius, UNDER, size)
    inside = plate < 0
    rim = inside & (plate > -1)
    save(name, size, [
        (shadow < 0, False, 0.75),
        (inside, True, 0.055),
        # Light where the rim faces up, shade where it faces down; the
        # sides keep a faint line so the plate's ends read.
        (rim, True, 0.05),
        (rim & (y < radius), True, 0.17),
        (rim & (y > size - UNDER - radius), False, 0.5),
    ])
    if card:
        whole = np.minimum(plate, shadow)
        save(name + "Fill", size, [(whole < 0, True, 1.0)])
        save(name + "State", size, [((whole < 0) & (whole > -2), True, 1.0)])
    else:
        save(name + "Edge", size, [(rim, True, 1.0)])


plate_set("MatteKey", 16, 2, False)
plate_set("MatteCard", 24, 4, True)
save("MatteBarCorners", 8, [(box(8, 2, 0, 8) >= 0, True, 1.0)])
