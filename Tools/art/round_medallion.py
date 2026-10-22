import sys
from PIL import Image
import numpy as np
src_dir, out_dir = sys.argv[1], sys.argv[2]
CX, CY0 = 255.5, 125.5
RX, RY = 122.0, 109.5
PAD = 128
CY = CY0 + PAD
def remap(name):
    a = np.array(Image.open(f"{src_dir}/{name}.tga").convert("RGBA")).astype(float)
    # premultiply so feathered edges don't pick up dark fringes
    a[..., :3] *= a[..., 3:4] / 255
    canvas = np.zeros((512, 512, 4))
    canvas[PAD:PAD + 256] = a
    yy, xx = np.mgrid[0:512, 0:512].astype(float)
    d = np.hypot(xx - CX, yy - CY)
    w = np.clip((146 - d) / 14, 0, 1)  # 1 inside the ring and its rim, feathered out
    sy = CY + (yy - CY) * (RY / RX) * w + (yy - CY) * (1 - w)
    y0 = np.clip(np.floor(sy).astype(int), 0, 510); f = np.clip(sy - y0, 0, 1)[..., None]
    xi = xx.astype(int)
    out = canvas[y0, xi] * (1 - f) + canvas[y0 + 1, xi] * f
    al = out[..., 3:4]
    out[..., :3] = np.where(al > 0, out[..., :3] * 255 / np.maximum(al, 1e-6), 0)
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA").save(f"{out_dir}/{name}.tga")
for n in ("ConsoleMedallion", "ConsoleMedallionLines"):
    remap(n)
