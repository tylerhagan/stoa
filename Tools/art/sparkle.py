"""Cut the sparkle art for things up close (Modules/QoL/Sparkle.lua), white
with alpha so it can be tinted:
  Sparkle.tga      a four-point star with a bright core and long thin rays;
  SparkleGlow.tga  a soft round glow, brightest in the middle.

Usage: python sparkle.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

SIZE = 64


def save(alpha, path):
    rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path)


def main(out):
    c = (np.arange(SIZE) + 0.5) / SIZE * 2 - 1
    x, y = np.meshgrid(c, c)
    r = np.hypot(x, y)
    # Rays: thin along each axis, fading toward the tips.
    ray_x = np.exp(-(y / 0.035) ** 2) * np.clip(1 - np.abs(x), 0, 1) ** 1.6
    ray_y = np.exp(-(x / 0.035) ** 2) * np.clip(1 - np.abs(y), 0, 1) ** 1.6
    core = np.exp(-(r / 0.12) ** 2)
    halo = np.exp(-(r / 0.3) ** 2) * 0.35
    star = np.clip(np.maximum(ray_x, ray_y) + core + halo, 0, 1)
    star[r >= 1] = 0
    save(star, f"{out}/Sparkle.tga")
    glow = np.clip(1 - r, 0, 1) ** 2.4
    save(glow, f"{out}/SparkleGlow.tga")


if __name__ == "__main__":
    main(sys.argv[1])
