"""Cut the ground line's flared masks (Slate): a blade that tapers the whole
way, 6 tall at its round outer tip and widening steadily to 14 at the
signature, where a circle around the signature bites its end. There is no
point where the swell begins, so it reads as one shape and not a bar with a
limb. LineFlareRight.tga is the right-hand bar (inner end on the left) and
LineFlareLeft.tga its mirror: the game does not flip a mask by its texture
coordinates. Each is 256x32 for a 128x16 space laid flush with the bar's
outer end, so its left edge is 20 from the signature's centre.

Usage: python line_flare.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

W, H, SCALE, UNIT = 256, 32, 4, 2
INNER, THIN, WIDE, EASE = 7, 3, 7, 1.4
CENTRE, BITE = -20, 28

n = SCALE * UNIT
x, y = np.meshgrid((np.arange(W * SCALE) + 0.5) / n, (np.arange(H * SCALE) + 0.5) / n)
y = y - H / UNIT / 2
length = W / UNIT
s = np.clip(1 - (x - INNER) / (length - THIN - INNER), 0, 1)
half = THIN + (WIDE - THIN) * s ** EASE
body = (x >= INNER) & (x <= length - THIN) & (np.abs(y) <= half)
cap = np.hypot(x - (length - THIN), y) <= THIN
bite = np.hypot(x - CENTRE, y) <= BITE
inside = (body | cap) & ~bite
alpha = inside.reshape(H, SCALE, W, SCALE).mean(axis=(1, 3))
img = np.zeros((H, W, 4), dtype=np.uint8)
img[..., :3] = 255
img[..., 3] = np.round(alpha * 255).astype(np.uint8)
out = sys.argv[1].rstrip("/\\")
Image.fromarray(img, "RGBA").save(out + "/LineFlareRight.tga")
Image.fromarray(img[:, ::-1].copy(), "RGBA").save(out + "/LineFlareLeft.tga")
