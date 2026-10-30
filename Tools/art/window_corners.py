"""Cut the rounded pieces Stoa windows and tooltips are dressed with, 32x32
white with alpha so the theme tints them, nine-sliced in game at 12px:

- WindowFill.tga / WindowEdge.tga: a window's panel and its 1px outline,
  10px corners (a touch rounder than cards, which are ~7px).
- WindowTop.tga: the header band, only the top corners rounded.
- WindowBottom.tga: the footer tray, only the bottom corners rounded.
- CardTop.tga: a tooltip's header band, 7px top corners to match its card.
- TabFill.tga / TabEdge.tga: a window tab hanging under the window, square
  on top (it tucks under the window's edge), 6px corners below, and its
  outline without the top line.

Usage: python window_corners.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SIZE, SCALE = 32, 8


def coverage(radius, inset=0.0, top=True, bottom=True):
    """Supersampled alpha of a square with rounded corners, shrunk by inset;
    `top`/`bottom` pick which corners are rounded."""
    n = SIZE * SCALE
    c = (np.arange(n) + 0.5) / SCALE
    x, y = np.meshgrid(c, c)
    lo, hi = inset, SIZE - inset
    r = max(radius - inset, 0.0)
    qx = np.maximum(np.maximum(lo + r - x, x - (hi - r)), 0)
    qy = np.maximum(np.maximum(lo + r - y, y - (hi - r)), 0)
    rounded = np.hypot(qx, qy) <= r
    square = np.ones_like(rounded)
    pick = np.where(y < SIZE / 2, rounded if top else square, rounded if bottom else square)
    inside = pick & (x >= lo) & (x <= hi) & (y >= lo) & (y <= hi)
    return inside.reshape(SIZE, SCALE, SIZE, SCALE).mean(axis=(1, 3))


def save(alpha, path):
    rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path)


def main(out):
    fill = coverage(10)
    save(fill, f"{out}/WindowFill.tga")
    save(np.clip(fill - coverage(10, 1), 0, 1), f"{out}/WindowEdge.tga")
    save(coverage(10, bottom=False), f"{out}/WindowTop.tga")
    save(coverage(10, top=False), f"{out}/WindowBottom.tga")
    save(coverage(7, bottom=False), f"{out}/CardTop.tga")
    tab = coverage(6, top=False)
    save(tab, f"{out}/TabFill.tga")
    edge = np.clip(tab - coverage(6, 1, top=False), 0, 1)
    # The inset shape is also pulled down from the top; clear that top line.
    edge[0, :] = 0
    save(edge, f"{out}/TabEdge.tga")


if __name__ == "__main__":
    main(sys.argv[1])
