# Painted minimap frames: a lean leather-and-brass rounded square and ring
# (the starred and pointed versions are kept as -stars and -points), each as a grey base plus white-with-alpha brass lines
# (the theme accent tints the lines in game, as on the console).
#
#   python3 minimap_frames.py source ../../Media/Textures
#
# Reads source/minimap-square.png and source/minimap-ring.png, centres each
# on its opening, and prints how much wider than the map each frame is
# (Modules/Grimoire/Minimap.lua uses it).
import sys
from PIL import Image
import numpy as np
from scipy import ndimage

src, out_dir = sys.argv[1], sys.argv[2]
SIZE = 512


def brass(px):
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    chroma = np.clip((r - b - 12) / 48, 0, 1)
    lum = 0.30 * r + 0.59 * g + 0.11 * b
    return chroma * np.clip(lum / 190, 0, 1) ** 1.1


for name, out in (("minimap-square", "MinimapFrameSquare"), ("minimap-ring", "MinimapFrameRing")):
    a = np.array(Image.open(f"{src}/{name}.png").convert("RGBA")).astype(float)
    h, w = a.shape[:2]
    # Drop stray specks outside the frame body: keep only large solid parts.
    solid = ndimage.binary_opening(a[..., 3] > 40, iterations=2)
    lab, n = ndimage.label(solid)
    sizes = ndimage.sum(solid, lab, range(1, n + 1))
    keep = ndimage.binary_dilation(np.isin(lab, 1 + np.where(sizes > 5000)[0]), iterations=3)
    # and the reddish fringe some generated art carries
    r, g = a[..., 0], a[..., 1]
    fringe = (r > 120) & (g < 0.45 * r) & (a[..., 3] < 250)
    a[..., 3] = np.where(keep & ~fringe, a[..., 3], 0)
    # The opening: the clear region holding the centre.
    lab, _ = ndimage.label(a[..., 3] < 128)
    ys, xs = np.where(lab == lab[h // 2, w // 2])
    ox, oy = (xs.min() + xs.max() + 1) / 2, (ys.min() + ys.max() + 1) / 2
    open_w = xs.max() + 1 - xs.min()
    # Square canvas centred on the opening, wide enough for the whole frame.
    half = int(np.ceil(max(ox, w - ox, oy, h - oy)))
    canvas = np.zeros((2 * half, 2 * half, 4))
    x0, y0 = int(round(half - ox)), int(round(half - oy))
    canvas[y0:y0 + h, x0:x0 + w] = a
    canvas[..., :3] *= canvas[..., 3:4] / 255  # premultiply for the resize
    im = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8), "RGBA")
    px = np.array(im.resize((SIZE, SIZE), Image.LANCZOS)).astype(float)
    al = px[..., 3:4]
    px[..., :3] = np.where(al > 0, px[..., :3] * 255 / np.maximum(al, 1e-6), 0)
    lum = 0.30 * px[..., 0] + 0.59 * px[..., 1] + 0.11 * px[..., 2]
    base = np.dstack([lum, lum, lum, px[..., 3]])
    white = np.full(lum.shape, 255.0)
    lines = np.dstack([white, white, white, brass(px) * px[..., 3]])
    Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGBA").save(f"{out_dir}/{out}.tga")
    Image.fromarray(np.clip(lines, 0, 255).astype(np.uint8), "RGBA").save(f"{out_dir}/{out}Lines.tga")
    print(f"{out}: frame is {2 * half / open_w:.3f} x the opening's width")
