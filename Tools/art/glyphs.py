"""Draw the small interface glyphs: close cross, plus, minus, chevron, the
Shift arrow and the separator dot. White with alpha, tinted in game, so no
control or separator depends on a symbol the font may or may not carry.

Usage: python glyphs.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SCALE = 8
OUT = sys.argv[1].rstrip("/\\")


def grid(w, h):
    xs = (np.arange(w * SCALE) + 0.5) / (h * SCALE)
    ys = (np.arange(h * SCALE) + 0.5) / (h * SCALE)
    return np.meshgrid(xs, ys)


def stroke(x, y, a, b, half):
    """True within `half` of the segment a-b."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = np.clip(((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(x - ax - t * dx, y - ay - t * dy) <= half


def save(name, mask, w, h, alpha=1.0):
    cover = mask.reshape(h, SCALE, w, SCALE).mean(axis=(1, 3)) * alpha
    img = np.zeros((h, w, 4), dtype=np.uint8)
    img[..., :3] = 255
    img[..., 3] = np.round(cover * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(f"{OUT}/Glyph{name}.tga")


x, y = grid(32, 32)
T = 0.055
save("Cross", stroke(x, y, (0.24, 0.24), (0.76, 0.76), T) | stroke(x, y, (0.76, 0.24), (0.24, 0.76), T), 32, 32)
save("Plus", stroke(x, y, (0.22, 0.5), (0.78, 0.5), T) | stroke(x, y, (0.5, 0.22), (0.5, 0.78), T), 32, 32)
save("Minus", stroke(x, y, (0.22, 0.5), (0.78, 0.5), T), 32, 32)
save("Chevron", stroke(x, y, (0.38, 0.22), (0.66, 0.5), T) | stroke(x, y, (0.66, 0.5), (0.38, 0.78), T), 32, 32)
# Shift: the outlined up arrow from the key.
pts = [(0.5, 0.14), (0.86, 0.52), (0.66, 0.52), (0.66, 0.84), (0.34, 0.84), (0.34, 0.52), (0.14, 0.52)]
arrow = np.zeros_like(x, dtype=bool)
for i, p in enumerate(pts):
    arrow |= stroke(x, y, p, pts[(i + 1) % len(pts)], 0.045)
save("Shift", arrow, 32, 32)
# The separator dot, on a cell half as wide as it is tall so it sits in a
# line of text like a letter. Dimmer than the words beside it.
x, y = grid(16, 32)
save("Dot", np.hypot(x - 0.25, y - 0.52) <= 0.085, 16, 32, alpha=0.6)
