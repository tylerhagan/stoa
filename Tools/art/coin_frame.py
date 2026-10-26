# A small brass ring without points, for portrait coins and the Halo's
# signature slot, swept from the band of the painted minimap ring
# (source/minimap-ring.png). At coin size the painting's thin brass would
# fade, so its two brass lines get a bigger share of the band.
#
#   python3 coin_frame.py source ../../Media/Textures
#
# 128x128: the opening (the portrait or icon) is 88 texels across, the band
# runs out to 124. Grey base plus white-with-alpha lines, as on the console.
import sys
from PIL import Image
import numpy as np

src, out_dir = sys.argv[1], sys.argv[2]
SIZE, R_IN, R_OUT = 128, 44.0, 62.0
SS = 4  # supersampling

a = np.array(Image.open(f"{src}/minimap-ring.png").convert("RGBA")).astype(float)
CX, CY = 627.0, 612.5
# The band's parts in the painting, in pixels from the centre: a shadow
# edge, the inner brass, the leather, the outer brass.
STOPS = [446.0, 452.0, 467.0, 505.0, 520.0]
SHARES = [0.05, 0.30, 0.33, 0.32]  # of the new band, inside to out

# Average the band's profile over the stretches between the points.
rs = np.linspace(STOPS[0], STOPS[-1], 300)
angles = np.radians(np.concatenate([np.arange(q + 22, q + 68, 1.0) for q in (0, 90, 180, 270)]))
xs = CX + rs[None, :] * np.cos(angles[:, None])
ys = CY + rs[None, :] * np.sin(angles[:, None])
samples = a[ys.astype(int), xs.astype(int)]
samples[..., :3] *= samples[..., 3:4] / 255
profile = samples.mean(0)

# Map the new band onto the painting's, part by part.
new_edges = R_IN + (R_OUT - R_IN) * np.concatenate([[0], np.cumsum(SHARES)])
n = SIZE * SS
yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / SS
d = np.hypot(xx - SIZE / 2, yy - SIZE / 2)
src_r = np.interp(d, new_edges, STOPS, left=-1, right=-1)
idx = np.clip((src_r - STOPS[0]) / (STOPS[-1] - STOPS[0]) * (len(rs) - 1), 0, len(rs) - 1)
px = profile[np.round(idx).astype(int)]
px[(src_r < 0)] = 0
px = px.reshape(SIZE, SS, SIZE, SS, 4).mean((1, 3))
al = px[..., 3:4]
px[..., :3] = np.where(al > 0, px[..., :3] * 255 / np.maximum(al, 1e-6), 0)


def brass(p):
    r, g, b = p[..., 0], p[..., 1], p[..., 2]
    chroma = np.clip((r - b - 12) / 48, 0, 1)
    lum = 0.30 * r + 0.59 * g + 0.11 * b
    return chroma * np.clip(lum / 190, 0, 1) ** 1.1


lum = 0.30 * px[..., 0] + 0.59 * px[..., 1] + 0.11 * px[..., 2]
base = np.dstack([lum, lum, lum, px[..., 3]])
white = np.full(lum.shape, 255.0)
lines = np.dstack([white, white, white, brass(px) * px[..., 3]])
Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGBA").save(f"{out_dir}/CoinFrame.tga")
Image.fromarray(np.clip(lines, 0, 255).astype(np.uint8), "RGBA").save(f"{out_dir}/CoinFrameLines.tga")
print(f"CoinFrame: frame is {SIZE / (2 * R_IN):.3f} x the opening's width")
