"""Draw the shield: a plain heater shield, white with alpha, for the tag
that shows how much of a shield is left (Core/Widgets.lua fills it from the
foot up). A stand-in until there is painted art for it.

Usage: python shield.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SIZE, SCALE = 32, 8
TOP, SHOULDER, FOOT, HALF = 0.06, 0.42, 0.97, 0.40

n = SIZE * SCALE
c = (np.arange(n) + 0.5) / n
x, y = np.meshgrid(c, c)
# Straight sides down to the shoulder, then drawing in to a point.
t = np.clip((y - SHOULDER) / (FOOT - SHOULDER), 0, 1)
half = HALF * (1 - t ** 1.7)
inside = (y >= TOP) & (y <= FOOT) & (np.abs(x - 0.5) <= half)
alpha = inside.reshape(SIZE, SCALE, SIZE, SCALE).mean(axis=(1, 3))
img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
img[..., :3] = 255
img[..., 3] = np.round(alpha * 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(sys.argv[1].rstrip("/\\") + "/Shield.tga")
