"""Cut the ground line's flared mask (Slate): a bar 8 tall with a round outer
end that swells to 14 over its last 48 toward the signature, where a circle
around the signature bites its end. Drawn for the right-hand bar (inner end
on the left); the left-hand bar flips it. 256x32 for a 128x16 space, in
which the bar starts 2 in from the left and the signature's centre is
SIGNATURE_GAP further left.

Usage: python line_flare.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

W, H, SCALE, UNIT = 256, 32, 4, 2
INNER, THIN, WIDE, SWELL = 2, 4, 7, 48
SIGNATURE_GAP, BITE = 21, 23

n = SCALE * UNIT
x, y = np.meshgrid((np.arange(W * SCALE) + 0.5) / n, (np.arange(H * SCALE) + 0.5) / n)
y = y - H / UNIT / 2
length = W / UNIT
s = np.clip(1 - (x - INNER) / SWELL, 0, 1)
half = THIN + (WIDE - THIN) * s * s
body = (x >= INNER) & (x <= length - THIN) & (np.abs(y) <= half)
cap = np.hypot(x - (length - THIN), y) <= THIN
bite = np.hypot(x - (INNER - SIGNATURE_GAP), y) <= BITE
inside = (body | cap) & ~bite
alpha = inside.reshape(H, SCALE, W, SCALE).mean(axis=(1, 3))
img = np.zeros((H, W, 4), dtype=np.uint8)
img[..., :3] = 255
img[..., 3] = np.round(alpha * 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(sys.argv[1].rstrip("/\\") + "/LineFlare.tga")
