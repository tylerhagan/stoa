"""Draw the hatch: fine dark diagonal stripes that tile, for damage that is
on its way (the DoT stretch on the target bar and nameplates). The stripes
are black and the gaps a faint black wash, so the bar's own colour shows
between them, a little dimmed.

Usage: python hatch.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SIZE, SCALE = 16, 8
PERIOD, WIDTH = 8, 2

# Drawn large and averaged down, so the stripes' edges are smooth. Rising
# to the right, and whole periods across the tile so it repeats.
n = SIZE * SCALE
c = (np.arange(n) + 0.5) / SCALE
x, y = np.meshgrid(c, c)
# x + y runs along the diagonal at root two to the texel, so the band is
# widened to keep the stripe two texels across.
on = ((x + y) % PERIOD) < WIDTH * 2 ** 0.5
alpha = on.reshape(SIZE, SCALE, SIZE, SCALE).mean(axis=(1, 3))
img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
# A faint black wash between the stripes dims the stretch as a whole.
WASH, LINE = 0.15, 0.72
img[..., 3] = np.round((WASH + (LINE - WASH) * alpha) * 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(sys.argv[1].rstrip("/\\") + "/Hatch.tga")
