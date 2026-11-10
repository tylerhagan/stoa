"""Cut GuideArrow.tga: STOA's arrow for RestedXP's waypoint pointer. A matte
black arrowhead, lit a little on its left half, with a fine pale edge and a
soft glow round it so it still reads against dark ground and night skies.
Drawn from scratch (not RestedXP's art), pointing up, centred so RestedXP
can spin it about the middle.

Usage: python guide_arrow.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 128
SS = 8                      # supersample
# Arrowhead as shares of the texture, inset so the glow fits inside.
TIP, WING_Y, NOTCH_Y, HALF = 0.11, 0.86, 0.70, 0.37
ROUND = 0.055               # corner rounding
EDGE = 0.032                # pale edge width
GLOW = 0.07                 # glow reach
LEFT, RIGHT = 0x30, 0x24    # body greys (lifted from near black)
EDGE_GREY, EDGE_ALPHA = 0xE8, 0.92
GLOW_ALPHA = 0.45


def shape(inset):
    big = SIZE * SS
    img = Image.new("L", (big, big), 0)
    pts = [(0.5, TIP), (0.5 + HALF, WING_Y), (0.5, NOTCH_Y), (0.5 - HALF, WING_Y)]
    ImageDraw.Draw(img).polygon([(x * big, y * big) for x, y in pts], fill=255)
    # Round the corners: shrink, then grow back with a round brush.
    r = int(ROUND * big) | 1
    img = img.filter(ImageFilter.MinFilter(r)).filter(ImageFilter.MaxFilter(r))
    if inset > 0:
        img = img.filter(ImageFilter.MinFilter(int(inset * big) | 1))
    elif inset < 0:
        img = img.filter(ImageFilter.MaxFilter(int(-inset * big) | 1))
    return np.asarray(img.resize((SIZE, SIZE), Image.LANCZOS), np.float32) / 255


def main(out):
    outer = shape(0)
    inner = shape(EDGE)
    glow = np.asarray(
        Image.fromarray((shape(-GLOW * 0.4) * 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(GLOW * SIZE * 0.45)), np.float32) / 255
    x = np.arange(SIZE)[None, :].repeat(SIZE, 0)
    body = np.where(x < SIZE / 2, LEFT, RIGHT).astype(np.float32)

    # Layers, back to front: glow, pale edge (the whole shape), body.
    rgb = np.full((SIZE, SIZE), 255.0)
    a = glow * GLOW_ALPHA
    edge_a = outer * EDGE_ALPHA
    rgb = (rgb * a * (1 - edge_a) + EDGE_GREY * edge_a) / np.maximum(a * (1 - edge_a) + edge_a, 1e-6)
    a = a * (1 - edge_a) + edge_a
    rgb = (rgb * a * (1 - inner) + body * inner) / np.maximum(a * (1 - inner) + inner, 1e-6)
    a = a * (1 - inner) + inner

    rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
    rgba[..., :3] = np.clip(rgb + 0.5, 0, 255).astype(np.uint8)[..., None]
    rgba[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(f"{out}/GuideArrow.tga")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Media/Textures")
