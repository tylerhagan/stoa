"""Draw the docked target plaque's two ends, white with alpha (tinted in
game). The plaque stands on the console rim as tall as the medallion.

- PlaqueJoin.tga / PlaqueJoinLines.tga: the right end, the target's
  portrait ring as tall as the plaque: the gold top edge runs straight on
  into the ring, round its top right, straight down, then sweeps out to
  the right into the rim like the medallion's flourish (FLARE 16).
- PlaqueSocket.tga / PlaqueSocketLines.tga: the left end, cut round the
  console's medallion with a gold line following its ring, so the plaque
  sits against the medallion like a socket.

Geometry in UI units, matching Core/Widgets.lua (JOIN_*, SOCKET_*): body
height H 68, ring radius R 34. The medallion's outer
ring is 74 (133 texels of ConsoleMedallion at 0.556), its centre 5.9 under
the rim; the socket keeps 4 clear of it and starts 24 right of its centre.
4 texels per unit.

Usage: python plaque_join.py <Media/Textures>
"""
import math
import sys

import numpy as np
from PIL import Image

PX, SS = 4, 4
H, R = 68.0, 34.0
FLARE = 16.0
LINE, INNER_A = 2.0, 0.45
MED_R, MED_DROP, SOCKET_GAP, SOCKET_X, SOCKET_W = 74.0, 5.9, 4.0, 24.0, 56


def grid(w, h):
    x = (np.arange(w * PX * SS) + 0.5) / (PX * SS)
    y = h - (np.arange(h * PX * SS) + 0.5) / (PX * SS)
    return np.meshgrid(x, y)


def down(mask):
    h, w = mask.shape
    return mask.reshape(h // SS, SS, w // SS, SS).mean(axis=(1, 3))


def save(alpha, path):
    rgba = np.zeros(alpha.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path)


def join(out):
    # The ring is as tall as the plaque: the top line runs straight on into
    # the ring's top and round its right side down to the rim.
    lead = 4.0
    cx, cy = lead + R, R
    edge = cx + R
    w, h = int(math.ceil(edge + FLARE + 2)), int(H + 2)
    x, y = grid(w, h)
    dc = np.hypot(x - cx, y - cy)
    # The flare's centre: the edge sweeps out round it into the rim.
    fx, fy = edge + FLARE, FLARE
    dfl = np.hypot(x - fx, y - fy)
    # Round over the top right; below the ring's middle its edge drops
    # straight down, then sweeps out to the right into the rim, the way the
    # medallion's flourish does.
    fill = ((x <= cx) & (y <= H)) | (dc <= R) | ((x <= edge) & (y <= cy))
    fill |= (x >= edge) & (x <= fx) & (y <= fy) & (dfl >= FLARE)
    half = LINE / 2
    top = (x <= cx) & (np.abs(y - H) <= half)
    ring = (np.abs(dc - R) <= half) & (x >= cx) & (y >= cy)
    ring |= (np.abs(x - edge) <= half) & (y <= cy) & (y >= fy)
    ring |= (np.abs(dfl - FLARE) <= half) & (x <= fx + half) & (y <= fy + half) & (x >= edge - half)
    inner = (np.abs(dc - (R - 4.5)) <= 0.5) * INNER_A
    lines = np.maximum((top | ring).astype(float), inner)
    save(down(fill.astype(float)), f"{out}/PlaqueJoin.tga")
    save(down(lines), f"{out}/PlaqueJoinLines.tga")
    print(f"join: {w}x{h} units, ring centre {cx:.2f},{cy:.2f}")


def socket(out):
    w, h = SOCKET_W, int(H + 2)
    x, y = grid(w, h)
    d = np.hypot(x + SOCKET_X, y + MED_DROP)
    rr = MED_R + SOCKET_GAP
    fill = (d >= rr) & (y <= H)
    half = LINE / 2
    top = (d >= rr) & (np.abs(y - H) <= half)
    arc = (np.abs(d - rr) <= 0.75) & (y <= H + half)
    save(down(fill.astype(float)), f"{out}/PlaqueSocket.tga")
    save(down((top | arc).astype(float)), f"{out}/PlaqueSocketLines.tga")
    print(f"socket: {w}x{h} units")


if __name__ == "__main__":
    join(sys.argv[1])
    socket(sys.argv[1])
