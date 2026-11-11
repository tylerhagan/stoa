"""Draw the hatch: diagonal stripes that tile, white with alpha, for damage
that is on its way (the DoT stretch on the target bar and nameplates). The
game tints it; the gaps are clear so a shade laid under it shows through.

Usage: python hatch.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SIZE, SCALE = 16, 8
PERIOD, STRIPE = 8, 3.5

n = SIZE * SCALE
c = (np.arange(n) + 0.5) / SCALE
x, y = np.meshgrid(c, c)
# Rising to the right, and whole periods across the tile so it repeats.
on = ((x + y) % PERIOD) < STRIPE
alpha = on.reshape(SIZE, SCALE, SIZE, SCALE).mean(axis=(1, 3))
img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
img[..., :3] = 255
img[..., 3] = np.round(alpha * 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(sys.argv[1].rstrip("/\\") + "/Hatch.tga")
