"""Cut the painted silver marks from Tyler's sheet (source/marks-silver.png:
six emblems in a row on a clear background) into square 128x128 textures,
each centred with a little margin. The game shows them as painted (the
drained part a darkened copy) and fills them from the foot up.

  MarkShield  your shield (the medallion and the Halo)
  MarkFlame   Inner Fire       MarkHorn   Battle Shout
  MarkDagger  Slice and Dice   MarkSeal   paladin seals
  MarkOrb     Lightning and Water Shield

Usage: python cut_marks.py <source png> <Media/Textures>
"""
import sys

import numpy as np
from PIL import Image

NAMES = ["MarkShield", "MarkFlame", "MarkHorn", "MarkDagger", "MarkSeal", "MarkOrb"]
SIZE = 128
MARGIN = 0.04

src = Image.open(sys.argv[1]).convert("RGBA")
out = sys.argv[2].rstrip("/\\")
alpha = np.array(src)[..., 3]
cols = alpha.max(axis=0) > 40
# Runs of columns with paint in them, one per emblem.
runs, start = [], None
for x, on in enumerate(cols):
    if on and start is None:
        start = x
    elif not on and start is not None:
        runs.append((start, x))
        start = None
if start is not None:
    runs.append((start, len(cols)))
runs = [r for r in runs if r[1] - r[0] > 20]
assert len(runs) == len(NAMES), runs
for name, (x0, x1) in zip(NAMES, runs):
    rows = np.where(alpha[:, x0:x1].max(axis=1) > 40)[0]
    y0, y1 = rows[0], rows[-1] + 1
    piece = src.crop((x0, y0, x1, y1))
    side = int(max(x1 - x0, y1 - y0) * (1 + 2 * MARGIN))
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(piece, ((side - (x1 - x0)) // 2, (side - (y1 - y0)) // 2))
    square.resize((SIZE, SIZE), Image.LANCZOS).save(f"{out}/{name}.tga")
    print(name, x1 - x0, y1 - y0)
