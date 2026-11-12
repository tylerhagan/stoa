"""Draw the docked target plaque's join: the plaque's top edge curving up
into the portrait ring, which rests on the console rim, like the rim flowing
into the console's medallion. White with alpha, tinted in game.

- PlaqueJoin.tga: the filled shape (panel colour in game).
- PlaqueJoinLines.tga: its gold edge (the top line, the curve and the ring,
  not the foot), plus a faint inner ring.

Geometry in UI units (Core/Widgets.lua JOIN_*): ring radius R 34, body
height H 50, curve radius F 12. The texture is 80x72 units at 4 texels per
unit (320x288); its bottom edge is the rim, its left edge 4 units before the
curve starts.

Usage: python plaque_join.py <Media/Textures>
"""
import math
import sys

import numpy as np
from PIL import Image

R, H, F = 34.0, 50.0, 12.0
W_UNITS, H_UNITS, PX, SS = 80, 72, 4, 4
LINE, INNER_R, INNER_A = 2.0, 29.5, 0.45

dy = (H + F) - R
dx = math.sqrt((R + F) ** 2 - dy ** 2)
LEFT_PAD = 4.0
FX = LEFT_PAD          # curve start, from the texture's left edge
CX = FX + dx           # ring centre
CY = R                 # above the rim
FCX, FCY = FX, H + F   # curve centre
# Where the curve meets the ring.
TX = CX + (FCX - CX) * R / (R + F)
TY = CY + (FCY - CY) * R / (R + F)


def grid():
    n_w, n_h = W_UNITS * PX * SS, H_UNITS * PX * SS
    x = (np.arange(n_w) + 0.5) / (PX * SS)
    # Image rows run top down; y is up from the rim.
    y = H_UNITS - (np.arange(n_h) + 0.5) / (PX * SS)
    return np.meshgrid(x, y)


def down(mask):
    h, w = mask.shape
    return mask.reshape(h // SS, SS, w // SS, SS).mean(axis=(1, 3))


def save(alpha, path):
    rgba = np.zeros(alpha.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path)


def main(out):
    x, y = grid()
    dc = np.hypot(x - CX, y - CY)
    df = np.hypot(x - FCX, y - FCY)
    body = (x <= CX) & (y >= 0) & (y <= H)
    ring = dc <= R
    curve = (x >= FX) & (x <= TX) & (y >= H) & (y <= TY) & (df >= F)
    fill = body | ring | curve
    half = LINE / 2
    top = (x <= FX) & (np.abs(y - H) <= half)
    arc = (x >= FX - half) & (x <= TX + half) & (y >= H - half) & (y <= TY + half) & (np.abs(df - F) <= half)
    # The ring's edge from where the curve meets it, over the top and
    # round the right side down to the rim; not inside the body.
    outside_body = ~((x < CX) & (y < TY))
    rim_edge = (np.abs(dc - R) <= half) & outside_body & (y >= 0)
    lines = (top | arc | rim_edge).astype(float)
    inner = (np.abs(dc - INNER_R) <= 0.5).astype(float) * INNER_A
    lines = np.maximum(lines, inner)
    save(down(fill.astype(float)), f"{out}/PlaqueJoin.tga")
    save(down(lines), f"{out}/PlaqueJoinLines.tga")
    print(f"curve start {FX:.2f}, ring centre {CX:.2f},{CY:.2f}, meets ring at {TX:.2f},{TY:.2f}")


if __name__ == "__main__":
    main(sys.argv[1])
