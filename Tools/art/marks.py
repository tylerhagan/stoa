"""Draw the class marks: plain silhouettes, white with alpha, for the mark
at the top of the medallion and under the Halo's power number. Like the
shield, the game fills each from the foot up by how much is left
(Core/Widgets.lua, Modules/Halo/Mark.lua). Stand-ins until there is
painted art.

  MarkHorn    Battle Shout (warrior): a curled war horn
  MarkDagger  Slice and Dice (rogue): a dagger, point up
  MarkSeal    the paladin's seal: a round seal with a cross cut through
  MarkOrb     Lightning and Water Shield (shaman): an orb ringed by three charges
  MarkFlame   Inner Fire (priest): a flame

Usage: python marks.py <Media/Textures>
"""
import math
import sys

from PIL import Image, ImageDraw

SIZE, SCALE = 64, 8
N = SIZE * SCALE


def canvas():
    return Image.new("L", (N, N), 0)


def p(x, y):
    return (x * N, y * N)


def horn():
    img = canvas()
    d = ImageDraw.Draw(img)
    # A horn curving up from a thin mouthpiece at the lower left to a wide
    # bell at the right: circles growing along an arc.
    def along(t):
        angle = math.radians(215 - 175 * t)
        return 0.46 + 0.34 * math.cos(angle), 0.74 - 0.40 * math.sin(angle), 0.04 + 0.13 * t ** 1.7

    steps = 200
    for i in range(steps + 1):
        cx, cy, r = along(i / steps)
        d.ellipse([p(cx - r, cy - r), p(cx + r, cy + r)], fill=255)
    # The bell's mouth, flared.
    cx, cy, r = along(1)
    d.ellipse([p(cx - r * 0.8, cy - r * 1.4), p(cx + r * 0.7, cy + r * 1.4)], fill=255)
    # The mouthpiece's rim.
    cx, cy, r = along(0)
    d.ellipse([p(cx - r * 1.5, cy - r * 1.5), p(cx + r * 1.5, cy + r * 1.5)], fill=255)
    # A thin band cut round the body.
    cx, cy, r = along(0.45)
    d.line([p(cx - r * 1.1, cy - r * 0.8), p(cx + r * 1.1, cy + r * 0.8)], fill=0, width=int(0.03 * N))
    return img


def dagger():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.polygon([p(0.5, 0.03), p(0.60, 0.20), p(0.58, 0.62), p(0.42, 0.62), p(0.40, 0.20)], fill=255)
    d.rounded_rectangle([p(0.24, 0.62), p(0.76, 0.70)], radius=0.03 * N, fill=255)
    d.rectangle([p(0.45, 0.70), p(0.55, 0.88)], fill=255)
    d.ellipse([p(0.42, 0.86), p(0.58, 0.98)], fill=255)
    return img


def seal():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.ellipse([p(0.06, 0.06), p(0.94, 0.94)], fill=255)
    # A cross cut through, and a thin ring inside the rim.
    d.ellipse([p(0.16, 0.16), p(0.84, 0.84)], fill=0)
    d.ellipse([p(0.20, 0.20), p(0.80, 0.80)], fill=255)
    d.rectangle([p(0.45, 0.28), p(0.55, 0.72)], fill=0)
    d.rectangle([p(0.30, 0.42), p(0.70, 0.52)], fill=0)
    return img


def orb():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.ellipse([p(0.24, 0.24), p(0.76, 0.76)], fill=255)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        cx, cy = 0.5 + 0.38 * math.cos(a), 0.5 - 0.38 * math.sin(a)
        r = 0.09
        d.ellipse([p(cx - r, cy - r), p(cx + r, cy + r)], fill=255)
    return img


def flame():
    img = canvas()
    d = ImageDraw.Draw(img)
    # A round base rising into a tall tongue with a smaller one at its side.
    outline = [
        (0.50, 0.03), (0.58, 0.18), (0.66, 0.30), (0.74, 0.40), (0.80, 0.52),
        (0.82, 0.64), (0.78, 0.78), (0.68, 0.90), (0.56, 0.96), (0.44, 0.96),
        (0.32, 0.90), (0.22, 0.78), (0.18, 0.64), (0.20, 0.50), (0.26, 0.38),
        (0.30, 0.46), (0.34, 0.52), (0.38, 0.40), (0.42, 0.26), (0.46, 0.14),
    ]
    d.polygon([p(x, y) for x, y in outline], fill=255)
    # The heart of the fire, cut out as a smaller flame.
    heart = [(0.52, 0.48), (0.60, 0.62), (0.62, 0.74), (0.56, 0.84), (0.44, 0.84), (0.38, 0.74), (0.42, 0.62), (0.46, 0.66)]
    d.polygon([p(x, y) for x, y in heart], fill=0)
    return img


def save(img, out, name):
    small = img.resize((SIZE, SIZE), Image.LANCZOS)
    rgba = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    rgba.putalpha(small)
    rgba.save(f"{out}/{name}.tga")


if __name__ == "__main__":
    out = sys.argv[1].rstrip("/\\")
    for name, draw in (("MarkHorn", horn), ("MarkDagger", dagger), ("MarkSeal", seal), ("MarkOrb", orb), ("MarkFlame", flame)):
        save(draw(), out, name)
