"""Draws the Halo's other arc styles.

    python3 Tools/art/halo_arcs.py [Media/Textures]

Writes HaloArc<Style>Left.tga and HaloArc<Style>Right.tga (128x256, white
with alpha, the right a mirror of the left) for Blade, Visor, Gauge and
Tube. The plain line (HaloArcLeft/Right.tga) is the first drawing and is
left alone. Each file is one status bar's art in Modules/Halo/Halo.lua: it
is shown 150x300, fills upwards and takes the bar's colour, so fainter
parts are written as lower alpha. Measures below are in screen pixels
from the Halo's centre, which is the middle of the texture's inner edge.
"""
import sys

import numpy as np
from PIL import Image

W, H, SHOWN = 128, 256, 150.0
SS = 4
OUTER = 145.0
out_dir = (sys.argv[1] if len(sys.argv) > 1 else "Media/Textures").rstrip("/\\")


def cosine(a, span, power):
    """1 at the middle of the arc, 0 at `span` degrees either side."""
    return np.cos(np.radians(np.clip(a * 90.0 / span, -90, 90))) ** power


# Each part: the angles it covers (degrees from level, up positive), its
# outer radius, its thickness by angle, and its alpha.
def blade():
    return OUTER, [(-60, 60, OUTER, lambda a: 1.2 + 9 * cosine(a, 60, 1.5), 1.0)]


# The visor's arcs are cut from a circle this wide, far wider than the
# Halo, so they bow only a little: marks on a wide curved pane, not a
# ring.
VISOR_RADIUS = 230.0
VISOR_HALF_HEIGHT = 123.0
# The whole drawing is then squashed to this share of its height: the bow
# stays as deep, the arcs end sooner.
VISOR_SQUASH = 0.8


def visor():
    # A band that pinches to its ends, a gloss line inside it and a faint
    # rim outside.
    span = float(np.degrees(np.arcsin(VISOR_HALF_HEIGHT / VISOR_RADIUS)))
    return VISOR_RADIUS, [
        (-span, span, VISOR_RADIUS, lambda a: 1.5 + 10 * cosine(a, span, 1.6), 1.0),
        (-span * 0.72, span * 0.72, VISOR_RADIUS - 14, lambda a: 1.3 + 0 * a, 0.5),
        (-span * 1.2, span * 1.2, VISOR_RADIUS + 4.5, lambda a: 0.9 + 0 * a, 0.18),
    ]


def gauge():
    parts = []
    for i in range(10):
        start = -60 + i * 12
        parts.append((start + 1, start + 11, OUTER, lambda a: 9 + 0 * a, 1.0))
    for tick in (-30, 0, 30):
        parts.append((tick - 0.6, tick + 0.6, 150, lambda a: 4 + 0 * a, 0.5))
    return OUTER, parts


def tube():
    return OUTER, [
        (-60, 60, OUTER, lambda a: 12 + 0 * a, 0.3),
        (-60, 60, OUTER, lambda a: 2.6 + 0 * a, 1.0),
    ]


def draw(circle, parts, squash=1.0):
    """`circle` is the radius the parts are measured on; its outer edge
    always meets the Halo's own (OUTER) at the arc's middle."""
    n_x, n_y = W * SS, H * SS
    # Sample centres in screen pixels, x measured leftwards from the centre.
    x = (n_x - (np.arange(n_x) + 0.5)) * SHOWN / n_x
    y = (n_y / 2 - (np.arange(n_y) + 0.5)) * SHOWN / (n_x)
    xx, yy = np.meshgrid(x, y)
    xx = xx + (circle - OUTER)
    yy = yy / squash
    radius = np.hypot(xx, yy)
    angle = np.degrees(np.arctan2(yy, xx))
    alpha = np.zeros((n_y, n_x))
    for start, end, outer, thickness, strength in parts:
        inside = (angle >= start) & (angle <= end) & (radius <= outer) & (radius >= outer - thickness(angle))
        alpha = np.maximum(alpha, inside * strength)
    return alpha.reshape(H, SS, W, SS).mean(axis=(1, 3))


for name, style in (("Blade", blade), ("Visor", visor), ("Gauge", gauge), ("Tube", tube)):
    alpha = draw(*style(), squash=VISOR_SQUASH if name == "Visor" else 1.0)
    img = np.full((H, W, 4), 255, dtype=np.uint8)
    img[..., 3] = np.round(alpha * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save("%s/HaloArc%sLeft.tga" % (out_dir, name))
    Image.fromarray(img[:, ::-1].copy(), "RGBA").save("%s/HaloArc%sRight.tga" % (out_dir, name))
    print(name, "rows", np.nonzero(alpha.max(axis=1))[0][[0, -1]], "cols", np.nonzero(alpha.max(axis=0))[0][[0, -1]])
