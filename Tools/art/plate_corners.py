"""Cut the small rounded pieces nameplates use: PlateFill.tga (a filled
rounded square) and PlateEdge.tga (its 1px outline), 16x16 with a 3px corner
radius, white with alpha so the theme tints them. Nine-sliced in game with
5px margins, so the corners keep their shape on a bar only ~10px tall.

Usage: python plate_corners.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SIZE, RADIUS, SCALE = 16, 3.0, 8


def coverage(inset):
    """Supersampled alpha of a rounded square shrunk by `inset` pixels."""
    n = SIZE * SCALE
    c = (np.arange(n) + 0.5) / SCALE
    x, y = np.meshgrid(c, c)
    lo, hi = inset, SIZE - inset
    r = max(RADIUS - inset, 0.0)
    # Distance outside the rounded rectangle (negative inside).
    qx = np.maximum(np.maximum(lo + r - x, x - (hi - r)), 0)
    qy = np.maximum(np.maximum(lo + r - y, y - (hi - r)), 0)
    inside = (np.hypot(qx, qy) <= r) & (x >= lo) & (x <= hi) & (y >= lo) & (y <= hi)
    return inside.reshape(SIZE, SCALE, SIZE, SCALE).mean(axis=(1, 3))


def save(alpha, path):
    rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path)


def main(out):
    fill = coverage(0)
    edge = np.clip(fill - coverage(1), 0, 1)
    save(fill, f"{out}/PlateFill.tga")
    save(edge, f"{out}/PlateEdge.tga")


if __name__ == "__main__":
    main(sys.argv[1])
