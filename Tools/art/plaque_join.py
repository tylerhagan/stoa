"""Draw the docked target plaque's two ends, white with alpha (tinted in
game). The plaque stands on the console rim as tall as the medallion.

- PlaqueJoin.tga / PlaqueJoinLines.tga: the right end, the target's
  portrait ring as tall as the plaque: the gold top edge runs straight on
  into the ring and round its top right; where the ring's side turns
  straight it bends out into a sweep down at 45 degrees that eases into the
  rim like the medallion's flourish (BEND 10, SWEEP 20).
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
SWEEP, BEND = 20.0, 10.0
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
    # The ring is as tall as the plaque: the gold top edge runs straight on
    # into the ring and round its top right. Where the ring's side turns
    # straight down it bends out into a long sweep at 45 degrees, easing into
    # the rim, the way the medallion's flourish does.
    lead = 4.0
    cx, cy = lead + R, R
    r2 = math.sqrt(0.5)
    edge = cx + R
    bcx, bcy = edge + BEND, cy                            # the bend's centre
    bx, by = bcx - BEND * r2, bcy - BEND * r2             # bend ends, sweep starts
    c0 = bx + by                                          # the sweep: x + y = c0
    fcx, fcy = c0 - SWEEP + SWEEP * math.sqrt(2), SWEEP   # the easing curve's centre
    tx, ty = fcx - SWEEP * r2, fcy - SWEEP * r2           # where the sweep meets it
    w, h = int(math.ceil(fcx + 2)), int(H + 2)
    x, y = grid(w, h)
    dc = np.hypot(x - cx, y - cy)
    db = np.hypot(x - bcx, y - bcy)
    de = np.hypot(x - fcx, y - fcy)
    fill = ((x <= cx) & (y <= H)) | (dc <= R) | ((x <= edge) & (y <= cy))
    right = x >= edge
    fill |= right & (y <= cy) & (y >= by) & (db >= BEND) & (x <= bcx)
    fill |= right & (y <= by) & (y >= ty) & (x + y <= c0)
    fill |= right & (y <= ty) & (x <= fcx) & (de >= SWEEP)
    half = LINE / 2
    top = (x <= cx) & (np.abs(y - H) <= half)
    ring = (np.abs(dc - R) <= half) & (x >= cx) & (y >= cy)
    bend = (np.abs(db - BEND) <= half) & (x <= bcx) & (y <= cy) & (bcx - x >= bcy - y)
    # Cut the sweep's ends square to it, so it meets the bend and the ease
    # without a step.
    along = (x - y) / math.sqrt(2)
    sweep = (np.abs(x + y - c0) / math.sqrt(2) <= half) & (along >= (bx - by) / math.sqrt(2)) & (along <= (tx - ty) / math.sqrt(2))
    ease = (np.abs(de - SWEEP) <= half) & (x <= fcx) & (fcy - y >= fcx - x)
    inner = (np.abs(dc - (R - 4.5)) <= 0.5) * INNER_A
    lines = np.maximum((top | ring | bend | sweep | ease).astype(float), inner)
    save(down(fill.astype(float)), f"{out}/PlaqueJoin.tga")
    save(down(lines), f"{out}/PlaqueJoinLines.tga")
    print(f"join: {w}x{h} units, ring centre {cx:.2f},{cy:.2f}, reaches {fcx:.1f}")


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
