"""Draw the hatch: thin dark diagonal stripes that tile, for damage that is
on its way (the DoT stretch on the target bar and nameplates). The stripes
are black and the gaps a faint black wash, so the bar's own colour shows
between them, a little dimmed.

Usage: python hatch.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SIZE, SCALE = 16, 8
PERIOD, STRIPE = 8, 2.2

n = SIZE * SCALE
c = (np.arange(n) + 0.5) / SCALE
x, y = np.meshgrid(c, c)
# Rising to the right, and whole periods across the tile so it repeats.
on = ((x + y) % PERIOD) < STRIPE
alpha = on.reshape(SIZE, SCALE, SIZE, SCALE).mean(axis=(1, 3))
# Hard edges: the game stretches the tile a little on most screens, and a
# soft edge stretched reads as blur.
alpha = np.clip((alpha - 0.3) * 2.5, 0, 1)
img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
# A faint black wash between the stripes dims the stretch as a whole.
WASH, LINE = 0.14, 0.66
img[..., 3] = np.round((WASH + (LINE - WASH) * alpha) * 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(sys.argv[1].rstrip("/\\") + "/Hatch.tga")
