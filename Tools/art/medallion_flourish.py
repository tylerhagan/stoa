# Tyler's medallion flourish: a brass line that runs in along the console's
# top edge and opens into a bracket hugging the medallion, mirrored either
# side. From his drawing (source/medallion-flourish.png): smoothed into a
# clean mask, scaled so the bracket's curve sits a little outside the ring,
# and rendered as brass with a soft bevel and a dark edge, like the
# painting's own lines.
#
#   python3 medallion_flourish.py source/medallion-flourish.png source/console-basis.png out_dir [gap]
#
# Writes flourish-mask.png (white with alpha, both sides, at the painting's
# scale), flourish-brass.png (the brass alone), flourish-mock.png (on the
# painting, its shoulder curves taken away) and flourish-guide.png (flat
# lines on dark, to hand an image model as a guide).
import sys
from PIL import Image, ImageFilter, ImageChops, ImageDraw
import numpy as np

src, basis_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
GAP = float(sys.argv[4]) if len(sys.argv) > 4 else 16.0
UP = 8  # work at eight times the drawing's size, then come down

draw = Image.open(src).convert("RGBA")
alpha = np.array(draw)[..., 3].astype(float)

# The bracket's circle, from the drawing's curve (not the straight lines).
ys, xs = np.nonzero(alpha > 128)
curve = (xs > 175) | (ys < 55) | (ys > 80)
x, y = xs[curve].astype(float), ys[curve].astype(float)
D, E, F = np.linalg.lstsq(np.c_[x, y, np.ones_like(x)], -(x ** 2 + y ** 2), rcond=None)[0]
fcx, fcy = -D / 2, -E / 2
fr = np.sqrt(fcx ** 2 + fcy ** 2 - F)

# The ring in the painting: centre and outer radius along its middle row.
basis = Image.open(basis_path).convert("RGBA")
B = np.array(basis).astype(float)
CX, CY = B.shape[1] / 2 - 0.5, 446.0
row = B[int(CY), :, 0] - B[int(CY), :, 2]
warm = np.nonzero(row > 60)[0]
left = warm[(warm > CX - 140) & (warm < CX)].min()
right = warm[(warm > CX) & (warm < CX + 140)].max()
CX, RING = (left + right) / 2, (right - left) / 2

scale = (RING + GAP) / fr

# A smooth mask: up, soften, cut, then down to the painting's scale.
big = Image.fromarray(alpha.astype(np.uint8)).resize((draw.width * UP, draw.height * UP), Image.BICUBIC)
big = big.filter(ImageFilter.GaussianBlur(UP * 0.6))
big = big.point(lambda v: max(0, min(255, (v - 96) * 4)))
w, h = round(draw.width * scale), round(draw.height * scale)
side = big.resize((w, h), Image.LANCZOS)

H, W = B.shape[:2]
mask = Image.new("L", (W, H), 0)
LIFT = 5  # puts the drawing's main line on the painting's top line
ox, oy = round(CX - fcx * scale), round(CY - fcy * scale) - LIFT
mask.paste(side, (ox, oy), side)
flipped = side.transpose(Image.FLIP_LEFT_RIGHT)
mask.paste(flipped, (round(CX + fcx * scale) - w, oy), flipped)
M = np.array(mask).astype(float) / 255

# Brass: a bevel lit from the upper left over a warm ramp, with wear.
soft = np.array(mask.filter(ImageFilter.GaussianBlur(2.2))).astype(float) / 255
gy, gx = np.gradient(soft)
light = np.clip(0.55 + (-gx * 0.7 - gy * 1.0) * 9, 0, 1)
ramp = np.array([[92, 58, 18], [168, 112, 38], [214, 160, 64], [246, 214, 130]], float)
t = light * (len(ramp) - 1)
i = np.clip(t.astype(int), 0, len(ramp) - 2)
f = (t - i)[..., None]
col = ramp[i] * (1 - f) + ramp[i + 1] * f
rng = np.random.default_rng(7)
grain = Image.fromarray((rng.random((H, W)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
col *= (0.9 + 0.2 * np.array(grain)[..., None] / 255)
brass = np.dstack([np.clip(col, 0, 255), M * 255]).astype(np.uint8)
Image.fromarray(brass, "RGBA").save(f"{out}/flourish-brass.png")
Image.fromarray(np.dstack([np.full((H, W, 3), 255), M * 255]).astype(np.uint8), "RGBA").save(f"{out}/flourish-mask.png")

# The mock: the painting with its shoulder curves taken off (everything
# above the top line outside the ring), then a dark edge and the brass.
yy, xx = np.mgrid[0:H, 0:W]
dist = np.hypot(xx - CX, yy - CY)
cut = (yy < CY - 2) & (dist > RING + 3)
P = B.copy()
P[cut, 3] = 0
# The painting's own top line runs on under the flourish's thin line and
# gives way to the flourish over the last stretch before the bracket, where
# the drawn line thickens into it.
end = int(CX - RING - GAP)
span = 70
for x0 in range(end - span, int(CX - RING - 2)):
    k = min(1.0, (x0 - (end - span)) / span)
    for xs_ in (x0, int(2 * CX - x0)):
        for y0 in range(int(CY) - 8, int(CY) + 12):
            if y0 < CY + 4:
                P[y0, xs_, 3] *= (1 - k)
            else:
                P[y0, xs_] = P[y0, xs_] * (1 - k) + B[y0 + 24, xs_] * k
# The dark edge and shadow only round the bracket, and the drawn line fades
# in from its thin end, so it lies on the painting's line without a step.
near = np.abs(xx - CX)
ramp_edge = np.clip(((RING + GAP + 150) - near) / 110, 0, 1)
tail = (near > RING + GAP + 20) & (np.abs(yy - CY) < 14)
M = np.where(tail, M * np.clip(((RING + GAP + 260) - near) / 120, 0.25, 1), M)
edge = np.array(mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.5))).astype(float) / 255
shadow = np.array(mask.filter(ImageFilter.GaussianBlur(5))).astype(float) / 255
for k, a in ((None, np.clip(shadow * 0.7, 0, 1) * ramp_edge), (None, edge * 0.9 * ramp_edge)):
    P[..., :3] = P[..., :3] * (1 - a[..., None]) + 12 * a[..., None]
    P[..., 3] = np.maximum(P[..., 3], a * 255)
P[..., :3] = P[..., :3] * (1 - M[..., None]) + col * M[..., None]
P[..., 3] = np.maximum(P[..., 3], M * 255)
Image.fromarray(P.astype(np.uint8), "RGBA").save(f"{out}/flourish-mock.png")

# The guide: flat lines on dark, the band, the ring and the flourish.
g = Image.new("RGB", (W, H), (17, 17, 17))
d = ImageDraw.Draw(g)
d.rectangle((40, CY + 1, W - 40, CY + 104), fill=(40, 40, 40), outline=(212, 168, 80), width=4)
d.ellipse((CX - RING, CY - RING, CX + RING, CY + RING), fill=(40, 40, 40), outline=(212, 168, 80), width=6)
d.ellipse((CX - RING + 16, CY - RING + 16, CX + RING - 16, CY + RING - 16), outline=(150, 120, 60), width=3)
gold = Image.new("RGB", (W, H), (226, 178, 86))
g.paste(gold, (0, 0), mask)
g.save(f"{out}/flourish-guide.png")
print("ring", CX, CY, RING, "scale", round(scale, 3), "flourish circle", round(fr * scale, 1))
