"""Draw the restyled target plaque's pieces, white with alpha (tinted in game):

- TargetBar.tga (512x64): a pill the exact shape of the plaque's health bar
  (228x14 in game), used as a mask on the bar's fill and track, so the bar
  has fully round ends at its real size. The pill fills the width and sits
  centred; the texture is anchored 7.25 above and below the bar.
- TargetBarEdge.tga (512x64): the pill's 1px outline at that size.

Usage: python plaque_dock.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SS = 8
BAR_W, BAR_H = 228, 14
TEX_W, TEX_H = 512, 64


def save(alpha, path):
    h, w = alpha.shape
    rgba = np.zeros((h, w, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path)


def grid(w, h):
    xs = (np.arange(w * SS) + 0.5) / SS
    ys = (np.arange(h * SS) + 0.5) / SS
    return np.meshgrid(xs, ys)


def down(mask, w, h):
    return mask.reshape(h, SS, w, SS).mean(axis=(1, 3))


def pill(inset):
    x, y = grid(TEX_W, TEX_H)
    ph = TEX_W * BAR_H / BAR_W
    r = ph / 2 - inset
    cy = TEX_H / 2
    cx = np.clip(x, ph / 2, TEX_W - ph / 2)
    return down((np.hypot(x - cx, y - cy) <= r).astype(float), TEX_W, TEX_H)


def main(out):
    px = TEX_W / BAR_W
    save(pill(0), f"{out}/TargetBar.tga")
    save(np.clip(pill(0) - pill(px), 0, 1), f"{out}/TargetBarEdge.tga")


if __name__ == "__main__":
    main(sys.argv[1])
