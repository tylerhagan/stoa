"""Cut the ground line's mask: a white pill, 16 to 1, with fully round ends.
The Halo's straight bars lay it over a bar twice as tall as they are long
by sixteen, flush with the bar's outer end, so only that end is rounded and
the inner end (which runs past the mask's own far cap) stays square.

Usage: python line_cap.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

W, H, SCALE = 256, 16, 4
R = H / 2

x, y = np.meshgrid((np.arange(W * SCALE) + 0.5) / SCALE, (np.arange(H * SCALE) + 0.5) / SCALE)
qx = np.maximum(np.maximum(R - x, x - (W - R)), 0)
inside = np.hypot(qx, y - R) <= R
alpha = inside.reshape(H, SCALE, W, SCALE).mean(axis=(1, 3))
img = np.zeros((H, W, 4), dtype=np.uint8)
img[..., :3] = 255
img[..., 3] = np.round(alpha * 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(sys.argv[1].rstrip("/\\") + "/LineCap.tga")
