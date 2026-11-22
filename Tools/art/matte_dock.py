"""Draws the Matte material's ends for the docked target plaque.

    python3 Tools/art/matte_dock.py [Media/Textures]

In matte the resting target is a moulded block that comes out of the
console's dial: as tall as the dial's round body and starting at its
centre, so the two read as one pill-shaped piece. The target of target is
a lower block behind it. The pieces are laid out like the leather's
(plaque_join.py), so Core/Widgets.lua places them with the same numbers
across, but taller (MATTE_DOCK_H there) and square: a small rounded top
corner and a straight side.

- PlaqueJoinMatte.tga: the right end (131x77 units, the side at 72).
- PlaqueSocketMatte.tga: the left end (56x77 units), cut round the dial.
- PlaqueStepMatte.tga: the target of target's right end (87x46, side at 48).

Each is white with a dark seam down its side and takes the panel colour;
its Lines file is the lit bevel along the top edge and round the corner,
white with alpha, drawn faint. 2 texels per unit.
"""
import sys

import numpy as np
from PIL import Image

out_dir = (sys.argv[1] if len(sys.argv) > 1 else "Media/Textures").rstrip("/\\")
PX, SS = 2, 4
BEVEL, SEAM = 3.0, 1.5


# The matte dial: the round body the bezel stands on, as the target's art
# sees it (Console.lua MATTE_ARCH, MATTE_SEAL_Y; the art's bottom edge is
# one unit under the rim). The plaque is as tall as the dial, so the two
# read as one pill-shaped piece.
DIAL_R, DIAL_Y, DOCK_TOP, DOCK_ART_H = 54.0, 21.0, 75.0, 77


def socket(name, w):
    """The left end: a block whose left edge is at the dial's centre, with
    the dial's circle cut out of it (a unit inside, so no seam shows)."""
    h = DOCK_ART_H
    n_x, n_y = w * PX * SS, h * PX * SS
    x = (np.arange(n_x) + 0.5) / (PX * SS)
    y = h - (np.arange(n_y) + 0.5) / (PX * SS)
    x, y = np.meshgrid(x, y)
    fill = (y <= DOCK_TOP) & (np.hypot(x, y - DIAL_Y) > DIAL_R - 1)
    bevel = fill & (DOCK_TOP - y <= BEVEL)

    def down(a):
        return a.reshape(h * PX, SS, w * PX, SS).mean(axis=(1, 3))

    for suffix, alpha in (("", down(fill * 1.0)), ("Lines", down(bevel * 1.0))):
        img = np.full((h * PX, w * PX, 4), 255, dtype=np.uint8)
        img[..., 3] = np.round(alpha * 255)
        Image.fromarray(img, "RGBA").save("%s/%s%s.tga" % (out_dir, name, suffix))
    print(name, w, h)


def piece(name, w, h, top, side, corner, mirror=False):
    """A block end `top` tall whose side stands at x = `side`."""
    n_x, n_y = w * PX * SS, h * PX * SS
    x = (np.arange(n_x) + 0.5) / (PX * SS)
    y = h - (np.arange(n_y) + 0.5) / (PX * SS)
    x, y = np.meshgrid(x, y)
    cx, cy = side - corner, top - corner
    in_corner = (x > cx) & (y > cy)
    radial = np.hypot(x - cx, y - cy)
    fill = (x <= side) & (y <= top) & (~in_corner | (radial <= corner))
    # How far inside the outline, and how much the edge there faces up.
    depth = np.where(in_corner, corner - radial, np.minimum(top - y, side - x))
    up = np.where(in_corner, np.divide(y - cy, radial, out=np.ones_like(radial), where=radial > 0), (top - y <= side - x) * 1.0)
    bevel = fill & (depth <= BEVEL)
    tone = np.where(fill & (side - x <= SEAM) & (y <= cy), 0.3, 1.0)

    def down(a):
        return a.reshape(h * PX, SS, w * PX, SS).mean(axis=(1, 3))

    def save(suffix, rgb, alpha):
        img = np.zeros((h * PX, w * PX, 4), dtype=np.uint8)
        img[..., :3] = np.round(np.clip(rgb, 0, 1) * 255)[..., None]
        img[..., 3] = np.round(np.clip(alpha, 0, 1) * 255)
        if mirror:
            img = img[:, ::-1].copy()
        Image.fromarray(img, "RGBA").save("%s/%s%s.tga" % (out_dir, name, suffix))

    a = down(fill * 1.0)
    save("", np.divide(down(tone * fill), a, out=np.ones_like(a), where=a > 0), a)
    save("Lines", np.ones_like(a), down(bevel * np.clip(up, 0, 1)))
    print(name, w, h)


piece("PlaqueJoinMatte", 131, DOCK_ART_H, DOCK_TOP, 72.0, 12.0)
socket("PlaqueSocketMatte", 56)
piece("PlaqueStepMatte", 87, 46, 44.0, 48.0, 8.0)
