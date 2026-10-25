import sys
from PIL import Image
import numpy as np

# Cuts WindowStone.tga from Tyler's stone art: the rings and the stone's
# grain as white with alpha, so the theme's text colour tints them over
# each window's own panel colour. The art's dark ground becomes clear.
src, out = sys.argv[1], sys.argv[2]
SIZE = 1024

im = Image.open(src).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
lum = np.asarray(im).astype(float).mean(axis=2)
ground = np.percentile(lum, 5)
peak = np.percentile(lum, 99.98)
alpha = np.clip((lum - ground) / (peak - ground), 0, 1)
# A gentle curve keeps the rings crisp and the grain faint.
alpha = alpha ** 1.15
rgba = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
rgba[..., :3] = 255
rgba[..., 3] = (alpha * 255).round().astype(np.uint8)
Image.fromarray(rgba, "RGBA").save(out)
print(f"ground {ground:.1f}, peak {peak:.1f}, mean alpha {alpha.mean():.3f}")
