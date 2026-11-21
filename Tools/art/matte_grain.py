"""Draws the matte console's grain tile.

    python3 Tools/art/matte_grain.py [out]

A fine pebble grain, the kind moulded into matte black plastic: 128x128,
each texel either white or black with its strength in the alpha, so one
texture both lifts and sinks the panel under it. Made from noise filtered
in the frequency domain, which repeats without a seam by construction.
Written as Media/Textures/MatteGrain.tga; Console.lua draws it one texel
per screen pixel and sets how strong it is. Textures need a full game
restart to load.
"""
import sys

import numpy as np
from PIL import Image

SIZE = 128
# The grain's bumps are about this many texels across.
BUMP = 2.6
# Light falls from above, so each bump is lit on its top side.
RELIEF = 0.7

out = sys.argv[1] if len(sys.argv) > 1 else "Media/Textures/MatteGrain.tga"

rng = np.random.default_rng(7)
freq = np.fft.fftfreq(SIZE)
fx, fy = np.meshgrid(freq, freq)
radius = np.hypot(fx, fy)
# A band of frequencies round one bump per BUMP texels.
centre = 1 / BUMP
band = np.exp(-((radius - centre) / (centre * 0.45)) ** 2)
height = np.fft.ifft2(np.fft.fft2(rng.standard_normal((SIZE, SIZE))) * band).real
height /= height.std()

# Shade the height field from above (wrapping, so the tile still repeats),
# and keep a little of the height itself so pits read darker than bumps.
slope = np.roll(height, 1, axis=0) - np.roll(height, -1, axis=0)
shade = RELIEF * slope / slope.std() + (1 - RELIEF) * height
shade = np.clip(shade / 2.5, -1, 1)

img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
img[..., :3] = np.where(shade > 0, 255, 0)[..., None]
img[..., 3] = np.round(np.abs(shade) * 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(out)
print(out, SIZE, SIZE, "mean alpha", img[..., 3].mean().round(1))
