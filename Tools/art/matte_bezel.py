"""Draws the Matte console's portrait bezel.

    python3 Tools/art/matte_bezel.py [out]

A moulded ring of hardware round the seal, the housing of a thumbstick:
from the portrait outwards, a deep lip, a smooth channel the level ring's
ticks sit in, and a raised rim lit from above, with its shadow on the
shell below. 256x256, carrying its own black and white, drawn untinted
128 px across by Console.lua's BuildSeal (BEZEL_SPREAD) round the 76 px
portrait; clear in the middle. Radii below are screen pixels.
"""
import sys

import numpy as np
from PIL import Image

out = sys.argv[1] if len(sys.argv) > 1 else "Media/Textures/MatteBezel.tga"
SIZE, SS, SHOWN = 256, 4, 128.0
PORTRAIT = 38.0
LIP, CHANNEL, RIM_IN, RIM_FACE, RIM_OUT = 42.0, 49.0, 51.0, 55.5, 59.5

n = SIZE * SS
c = ((np.arange(n) + 0.5) / n - 0.5) * SHOWN
x, y = np.meshgrid(c, -c)
r = np.hypot(x, y)
up = np.divide(y, r, out=np.zeros_like(r), where=r > 0)  # 1 at the top

white = np.zeros((n, n))  # light laid on
black = np.zeros((n, n))  # shade laid on


def ring(a, b):
    return (r >= a) & (r < b)


# The rim's shadow on the shell, falling a little downwards.
drop = np.hypot(x, y + 2.0)
black = np.where(r >= RIM_OUT, np.clip(1 - (drop - RIM_OUT) / 4.5, 0, 1) * 0.35, black)
# The rim: an outer chamfer facing out, a flat face, an inner wall facing in.
m = ring(RIM_FACE, RIM_OUT)
white = np.where(m, np.clip(up, 0, 1) * 0.2 + 0.02, white)
black = np.where(m, np.clip(-up, 0, 1) * 0.4, black)
m = ring(RIM_IN, RIM_FACE)
white = np.where(m, 0.045 + np.clip(up, 0, 1) * 0.025, white)
m = ring(CHANNEL, RIM_IN)
black = np.where(m, 0.3 + np.clip(up, 0, 1) * 0.3, black)
white = np.where(m, np.clip(-up, 0, 1) * 0.12, white)
# The channel's smooth floor, shaded under the rim's upper wall.
m = ring(LIP, CHANNEL)
black = np.where(m, 0.62 + np.clip(up, 0, 1) * np.clip((r - (CHANNEL - 3)) / 3, 0, 1) * 0.25, black)
# The lip down to the portrait: dark above, catching light below.
m = ring(PORTRAIT - 1, LIP)
black = np.where(m, 0.9 - np.clip(-up, 0, 1) * 0.25, black)
white = np.where(m & (r >= LIP - 1.2), np.clip(-up, 0, 1) * 0.14, white)

# One layer: black under white.
alpha = black + white - black * white
tone = np.divide(white, alpha, out=np.zeros_like(alpha), where=alpha > 0)


def down(a):
    return a.reshape(SIZE, SS, SIZE, SS).mean(axis=(1, 3))


a = down(alpha)
t = np.divide(down(tone * alpha), a, out=np.zeros_like(a), where=a > 0)
img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
img[..., :3] = np.round(t * 255)[..., None]
img[..., 3] = np.round(a * 255)
Image.fromarray(img, "RGBA").save(out)
print(out, "alpha", img[..., 3].min(), img[..., 3].max(), "centre", img[SIZE // 2, SIZE // 2, 3])
