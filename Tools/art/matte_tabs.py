"""Draws the matte console's chat tabs: a bank of keys, as on a cassette deck.

    python3 Tools/art/matte_tabs.py [Media/Textures]

Writes ChatTabMatteOpen[Lines].tga and ChatTabMatteClosed[Lines].tga, laid
out like the leather tabs (chat_tabs.py; Modules/Grimoire/Housing.lua
TAB_ART) so the same code places them: 128x128, the key's sides at 32 and
96 and the console's top edge at row 70. The keys stand side by side with
no gap, so each is square-sided with a soft seam down each side. Closed is
a key standing up: light falling off its top, shade at its foot, no lines. Open is the
key pressed in (the selected window, or one under a click): lower, darker,
shadowed under its top lip. The base carries its own tones; Lines is the
lamp lit over a pressed key, white with alpha, tinted by the accent.
"""
import sys

import numpy as np
from PIL import Image

out_dir = (sys.argv[1] if len(sys.argv) > 1 else "Media/Textures").rstrip("/\\")
SIZE, SS = 128, 4
X0, X1, FOOT = 32, 96, 70
CORNER = 4
SEAM = 1.5

n = SIZE * SS
c = (np.arange(n) + 0.5) / SS
x, y = np.meshgrid(c, c)


def key(top):
    """Signed distance to a key from `top` down past the foot."""
    cx, half_w = (X0 + X1) / 2, (X1 - X0) / 2
    cy, half_h = (top + 200) / 2, (200 - top) / 2
    qx, qy = np.abs(x - cx) - (half_w - CORNER), np.abs(y - cy) - (half_h - CORNER)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - CORNER


def down(a):
    return a.reshape(SIZE, SS, SIZE, SS).mean(axis=(1, 3))


def save(name, rgb, alpha):
    img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    img[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    img[..., 3] = np.round(np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save("%s/ChatTabMatte%s.tga" % (out_dir, name))


rng = np.random.default_rng(11)
grain = np.repeat(np.repeat(rng.normal(0, 1.5, (SIZE, SIZE)), SS, axis=0), SS, axis=1)
above = y < FOOT

# Closed: the key standing up.
d = key(26)
body = (d <= 0) & above
tone = np.full((n, n), 38.0) + grain
# No lines: light falls off the top, shade gathers at the foot and in the
# seams between keys.
tone = tone + 20.0 * np.clip(1 - (y - 26) / 7.0, 0, 1) ** 2
tone = tone - 16.0 * np.clip(1 - (FOOT - y) / 7.0, 0, 1) ** 2
tone = tone - 14.0 * np.clip(1 + d / (SEAM * 2), 0, 1) * (y >= 26 + CORNER)
alpha = down(body * 1.0)
rgb = np.divide(down(tone * body), alpha, out=np.zeros((SIZE, SIZE)), where=alpha > 0)
save("Closed", np.stack([rgb, rgb + 1, rgb + 3], axis=2), alpha)
save("ClosedLines", np.full((SIZE, SIZE, 3), 255.0), np.zeros((SIZE, SIZE)))

# Open: the key pressed in, its housing showing as a dark slot above it.
slot = (key(26) <= 0) & above
d = key(31)
body = (d <= 0) & above
tone = np.full((n, n), 6.0)
tone = np.where(body, 21.0 + grain, tone)
shadow = np.clip(1 - (y - 31) / 7.0, 0, 1)
tone = np.where(body, tone * (1 - 0.7 * shadow), tone)       # under the lip
tone = np.where(body & (d > -SEAM), 6.0, tone)
alpha = down(slot * 1.0)
rgb = np.divide(down(tone * slot), alpha, out=np.zeros((SIZE, SIZE)), where=alpha > 0)
save("Open", np.stack([rgb, rgb + 1, rgb + 2], axis=2), alpha)
# The light: a lamp in the slot over the pressed key, a bright bar with a
# soft glow round it. The middle column of the texture is stretched, so it
# is drawn only there and in the caps' inner edges, and grows with the key.
LAMP = 28.5
ends = np.clip((x - 42) / 6.0, 0, 1) * np.clip((86 - x) / 6.0, 0, 1)
core = np.clip(1.6 - np.abs(y - LAMP), 0, 1)
glow = np.exp(-((y - LAMP) / 3.2) ** 2) * 0.4
light = np.maximum(core, glow) * ends * (y < FOOT)
save("OpenLines", np.full((SIZE, SIZE, 3), 255.0), down(light))
print("done")
