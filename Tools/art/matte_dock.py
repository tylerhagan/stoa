"""Draws the Matte material's ends for the docked target plaque.

    python3 Tools/art/matte_dock.py [Media/Textures]

In matte the resting target is a moulded block standing on the console's
rim beside the mana block, and the target of target a lower block behind
it. These are the same pieces as the leather's (plaque_join.py), on the
same canvases so Core/Widgets.lua places them with the same numbers, but
square hardware: a small rounded top corner and a straight side.

- PlaqueJoinMatte.tga: the right end (131x70 units, the side at 72).
- PlaqueSocketMatte.tga: the left end (56x70 units).
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


piece("PlaqueJoinMatte", 131, 70, 68.0, 72.0, 10.0)
# The socket is the same end, mirrored, filling its whole width.
piece("PlaqueSocketMatte", 56, 70, 68.0, 56.0, 10.0, mirror=True)
piece("PlaqueStepMatte", 87, 46, 44.0, 48.0, 8.0)
