"""Cut SlateShadow.tga: the soft drop shadow under each Slate card, black
with alpha. A rounded rectangle (CardFill's 6px corner) INSET texels in
from each side, blurred by BLUR, so nine-sliced at SLICE with the card
inside the slice margins the shadow falls away round it. The alpha peaks
at 255 under the card; Console.lua sets the strength.

Usage: python slate_shadow.py <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 64
INSET = 22
RADIUS = 6
BLUR = 7
SS = 4


def main(out):
    big = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (INSET * SS, INSET * SS, (SIZE - INSET) * SS - 1, (SIZE - INSET) * SS - 1), RADIUS * SS, fill=255)
    small = big.resize((SIZE, SIZE), Image.LANCZOS).filter(ImageFilter.GaussianBlur(BLUR))
    alpha = np.asarray(small, np.float32)
    alpha = alpha / alpha.max() * 255
    rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
    rgba[..., 3] = np.clip(alpha + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(f"{out}/SlateShadow.tga")


if __name__ == "__main__":
    main(sys.argv[1])
