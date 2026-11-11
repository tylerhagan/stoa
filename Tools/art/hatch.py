"""Draw the hatch: fine dark diagonal stripes that tile, for damage that is
on its way (the DoT stretch on the target bar and nameplates). The stripes
are black and the gaps a faint black wash, so the bar's own colour shows
between them, a little dimmed.

Usage: python hatch.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SIZE, PERIOD, WIDTH = 16, 8, 2

# Two texels wide, on whole texels, with no smoothing of our own: the game
# smooths once as it scales the tile, and twice reads as blur. Rising to the right, and whole
# periods across the tile so it repeats.
x, y = np.meshgrid(np.arange(SIZE), np.arange(SIZE))
alpha = (((x + y) % PERIOD) < WIDTH).astype(float)
img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
# A faint black wash between the stripes dims the stretch as a whole.
WASH, LINE = 0.15, 0.72
img[..., 3] = np.round((WASH + (LINE - WASH) * alpha) * 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(sys.argv[1].rstrip("/\\") + "/Hatch.tga")
