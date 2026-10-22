# Chat tab art: the console's top edge profile bent up around a rounded tab.
# Open = selected (the edge flows up and round it, fillets at the foot);
# Closed = behind the console (the console's edge runs across its foot).
import sys, math
from PIL import Image
import numpy as np
tex_dir = sys.argv[1]
# Optional: output prefix and tab height in texture rows. "ResourceTab 70"
# cuts the taller open tab that holds health and mana.
PREFIX = sys.argv[2] if len(sys.argv) > 2 else "ChatTab"
RISE = int(sys.argv[3]) if len(sys.argv) > 3 else 46
W, H = 128, 128
YT = 24 if RISE <= 46 else 14   # tab top
YC = YT + RISE                   # console top
X0, X1 = 32, 96          # tab sides
RC, RF = 16, 9           # corner radius, fillet radius
EDGE0 = 37               # edge texture row where the leather starts
SHADOW = 14              # tab shadow rows (console's own is 37)

edge = np.array(Image.open(f"{tex_dir}/ConsoleEdge.tga").convert("RGBA")).astype(float)[:, 8]
lines = np.array(Image.open(f"{tex_dir}/ConsoleEdgeLines.tga").convert("RGBA")).astype(float)[:, 8, 3]
FLAT = 22.0  # the leather's mean tone, for the tab body

def sample(arr, row):
    row = np.clip(row, 0, 63)
    r0 = np.floor(row).astype(int); r1 = np.minimum(r0 + 1, 63); f = row - r0
    if arr.ndim == 1:
        return arr[r0] * (1 - f) + arr[r1] * f
    return arr[r0] * (1 - f)[..., None] + arr[r1] * f[..., None]

def profile(d):
    """Grey, alpha and gold alpha for depth d (positive inside the leather)."""
    row = np.where(d >= 0, EDGE0 + d, EDGE0 + d * EDGE0 / SHADOW)
    px = sample(edge, row)
    grey, alpha = px[..., 0], px[..., 3]
    gold = np.where(d >= 0, sample(lines, row), 0)
    alpha = np.where(row < 0, 0, np.where(d < 0, alpha * 0.7, alpha))
    # Deep inside: flat leather, opaque (the edge texture itself fades there).
    w = np.clip((d - 17) / 4, 0, 1)
    grey = grey * (1 - w) + FLAT * w
    alpha = np.where(d >= 17, 253, alpha)
    return grey, alpha, gold

def console_shadow(y):
    d = y - YC
    return np.where(d < 0, np.where(EDGE0 + d >= 0, sample(edge, EDGE0 + d)[..., 3], 0), 0)

def boundary(open_):
    pts = []
    def line(a, b, n):
        for t in np.linspace(0, 1, n): pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    def arc(c, r, a0, a1, n=60):
        for t in np.linspace(a0, a1, n): pts.append((c[0] + r * math.cos(t), c[1] + r * math.sin(t)))
    if open_:
        line((-60, YC), (X0 - RF, YC), 300)
        arc((X0 - RF, YC - RF), RF, math.pi / 2, 0)
        line((X0, YC - RF), (X0, YT + RC), 80)
    else:
        line((X0, H + 60), (X0, YT + RC), 300)
    arc((X0 + RC, YT + RC), RC, math.pi, 1.5 * math.pi)
    line((X0 + RC, YT), (X1 - RC, YT), 120)
    arc((X1 - RC, YT + RC), RC, 1.5 * math.pi, 2 * math.pi)
    if open_:
        line((X1, YT + RC), (X1, YC - RF), 80)
        arc((X1 + RF, YC - RF), RF, math.pi, math.pi / 2)
        line((X1 + RF, YC), (W + 60, YC), 300)
    else:
        line((X1, YT + RC), (X1, H + 60), 300)
    return np.array(pts)

def inside(x, y, open_):
    def rounded(x, y):
        ok = (x >= X0) & (x <= X1) & (y >= YT)
        for cx in (X0 + RC, X1 - RC):
            corner = (np.abs(x - cx) > 0) & (y < YT + RC) & (((x < X0 + RC) & (cx == X0 + RC)) | ((x > X1 - RC) & (cx == X1 - RC)))
            ok &= ~(corner & (np.hypot(x - cx, y - (YT + RC)) > RC))
        return ok
    m = rounded(x, y)
    if open_:
        m |= y >= YC
        for cx in (X0 - RF, X1 + RF):
            fil = (np.abs(x - cx) <= RF) & (y >= YC - RF) & (y < YC) & (np.hypot(x - cx, y - (YC - RF)) >= RF)
            near = ((cx < X0) & (x >= cx) & (x <= X0)) | ((cx > X1) & (x <= cx) & (x >= X1))
            m |= fil & near
    return m

def depth(open_):
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    pts = boundary(open_)
    d = np.full(xx.shape, 1e9)
    for chunk in np.array_split(pts, 20):
        dd = np.hypot(xx[..., None] - chunk[:, 0], yy[..., None] - chunk[:, 1]).min(-1)
        d = np.minimum(d, dd)
    return np.where(inside(xx, yy, open_), d, -d), xx, yy

def over(top, bot):
    """Alpha-composite (grey, alpha) top over bottom; alphas 0..255."""
    ta, ba = top[1] / 255, bot[1] / 255
    a = ta + ba * (1 - ta)
    g = np.where(a > 0, (top[0] * ta + bot[0] * ba * (1 - ta)) / np.maximum(a, 1e-6), 0)
    return g, a * 255

def foot_fade(y):
    return np.clip((YC + 23 - y) / 4, 0, 1)

def save(name, grey, alpha):
    img = np.zeros((H, W, 4), np.uint8)
    img[..., 0] = img[..., 1] = img[..., 2] = np.clip(grey, 0, 255)
    img[..., 3] = np.clip(alpha, 0, 255)
    Image.fromarray(img, "RGBA").save(f"{tex_dir}/{name}.tga")

def gold_out(gold):
    return np.full(gold.shape, 255.0), gold

def shadow_only_outside(d, alpha, y):
    # Outside the shape the console already casts its own shadow; add only
    # what the tab casts beyond it.
    ac = console_shadow(y) / 255
    a = alpha / 255
    extra = np.clip((a - ac) / np.maximum(1 - ac, 1e-6), 0, 1) * 255
    return np.where(d < 0, extra, alpha)

# Open.
d, xx, yy = depth(True)
g, a, gold = profile(d)
a = shadow_only_outside(d, a, yy) * foot_fade(yy)
gold = gold * foot_fade(yy)
save(PREFIX + "Open", g, a)
save(PREFIX + "OpenLines", *gold_out(gold))

if PREFIX != "ChatTab":
    sys.exit(0)

# Closed: a dimmer tab body, the console's edge laid over its foot.
d, xx, yy = depth(False)
g, a, gold = profile(d)
g = g * 0.8
gold = gold * 0.5
a = shadow_only_outside(d, a, yy)
cover = np.clip(d + 0.5, 0, 1)  # the tab's own coverage
pd = yy - YC
cg, ca, cgold = profile(pd)
ca = np.where(pd < 0, ca * cover, ca * cover)  # only over the tab's columns
g, a = over((cg, ca), (g, a))
gold = cgold * cover + gold * (1 - ca / 255)
a = a * foot_fade(yy)
gold = gold * foot_fade(yy)
save("ChatTabClosed", g, a)
save("ChatTabClosedLines", *gold_out(gold))
