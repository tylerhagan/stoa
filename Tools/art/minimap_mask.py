"""Cut the minimap's mask: a white square with rounded corners, the same
corner as Stoa's windows at the minimap's usual size (about 14px on a 200px
map). The game shows the map only where the mask is opaque.

Usage: python minimap_mask.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SIZE, SCALE, RADIUS = 256, 4, 18

n = SIZE * SCALE
c = (np.arange(n) + 0.5) / SCALE
x, y = np.meshgrid(c, c)
qx = np.maximum(np.maximum(RADIUS - x, x - (SIZE - RADIUS)), 0)
qy = np.maximum(np.maximum(RADIUS - y, y - (SIZE - RADIUS)), 0)
inside = np.hypot(qx, qy) <= RADIUS
alpha = inside.reshape(SIZE, SCALE, SIZE, SCALE).mean(axis=(1, 3))
img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
img[..., :3] = 255
img[..., 3] = np.round(alpha * 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(sys.argv[1].rstrip("/\\") + "/MinimapMask.tga")
