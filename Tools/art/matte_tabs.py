"""Draws the matte console's chat tabs.

    python3 Tools/art/matte_tabs.py [Media/Textures]

Writes ChatTabMatteOpen[Lines].tga and ChatTabMatteClosed[Lines].tga, laid
out like the leather tabs (chat_tabs.py; Modules/Grimoire/Housing.lua
TAB_ART) so the same code places them: 128x128, the tab's sides at 32 and
96, its top at row 24 and the console's top edge at row 70. Open is the
selected tab, moulded up out of the shell with fillets at its foot;
Closed stands behind the edge, darker and a little lower. The base is the
shell's own black with a dark seam round it; Lines is the lit edge, white
with alpha, tinted by the accent in game.
"""
import sys

import numpy as np
from PIL import Image

out_dir = (sys.argv[1] if len(sys.argv) > 1 else "Media/Textures").rstrip("/\\")
SIZE, SS = 128, 4
X0, X1, FOOT = 32, 96, 70
CORNER, FILLET = 13, 9
# The shell's tone at the console's top edge (panel plus its top light).
SHELL = np.array([31, 32, 35])
BEHIND = np.array([19, 20, 22])
EDGE = 3.0   # the lit edge's width in texels: chunky
SEAM = 2.0   # the dark seam outside it

n = SIZE * SS
c = (np.arange(n) + 0.5) / SS
x, y = np.meshgrid(c, c)


def tab_distance(top, with_fillets):
    """Signed distance to the tab's outline, negative inside."""
    # A box rounded at its top corners, running well below the foot.
    cx, half_w = (X0 + X1) / 2, (X1 - X0) / 2
    cy, half_h = (top + 200) / 2, (200 - top) / 2
    qx, qy = np.abs(x - cx) - (half_w - CORNER), np.abs(y - cy) - (half_h - CORNER)
    box = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - CORNER
    if not with_fillets:
        return box
    # The console below the foot, joined to the box with a round fillet.
    ground = FOOT - y
    k = float(FILLET)
    h = np.clip(0.5 + 0.5 * (ground - box) / k, 0, 1)
    return ground * (1 - h) + box * h - k * h * (1 - h)


def cover(distance, low, high):
    """How much of each texel lies between two distances."""
    inside = (distance > low) & (distance <= high)
    return inside.reshape(SIZE, SS, SIZE, SS).mean(axis=(1, 3))


def save(name, rgb, alpha):
    img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    img[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    img[..., 3] = np.round(np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save("%s/ChatTabMatte%s.tga" % (out_dir, name))


rng = np.random.default_rng(11)
grain = rng.normal(0, 1.6, (SIZE, SIZE, 1))
rows = np.arange(SIZE)[:, None, None]

for kind, top, tone, fillets, lit in (("Open", 24, SHELL, True, 0.34), ("Closed", 30, BEHIND, False, 0.14)):
    d = tab_distance(top, fillets)
    # Open covers the console's own edge line under its mouth; Closed stops
    # at the foot, so that line runs across it.
    bottom = (FOOT + 4 if fillets else FOOT)
    keep = (np.arange(SIZE)[:, None] < bottom)
    body = cover(d, -1e9, 0) * keep
    seam = cover(d, 0, SEAM) * keep * 0.7
    # A touch lighter at the top, as on the shell.
    light = np.clip((FOOT - rows) / (FOOT - top), 0, 1) * 5
    rgb = (tone + light + grain) * (body[..., None] > 0)
    save(kind, rgb, np.maximum(body * 0.98, seam * (body == 0)))
    edge = cover(d, -EDGE, 0) * keep * (np.arange(SIZE)[:, None] < FOOT + (1 if fillets else 0))
    save(kind + "Lines", np.full((SIZE, SIZE, 3), 255.0), edge * lit)
    print(kind, "done")
