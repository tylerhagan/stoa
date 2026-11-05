"""Cut RingGlow.tga: a soft halo for the console medallion's moments, white
with alpha so the theme tints it. The light peaks at INNER (the portrait's
edge, as a share of the radius) and fades out to nothing at the rim, and is
empty inside, so it never lies over the face.

Usage: python ring_glow.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SIZE = 256
# Portrait radius / glow radius: 55 / (55 + 22) in Console.lua.
INNER = 55 / 77


def main(out):
    c = (np.arange(SIZE) + 0.5) / SIZE * 2 - 1
    x, y = np.meshgrid(c, c)
    r = np.hypot(x, y)
    outside = np.clip((r - INNER) / (1 - INNER), 0, 1)
    alpha = np.where(r < INNER, np.clip((r - INNER + 0.04) / 0.04, 0, 1), (1 - outside) ** 2.2)
    alpha[r >= 1] = 0
    rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(f"{out}/RingGlow.tga")


if __name__ == "__main__":
    main(sys.argv[1])
