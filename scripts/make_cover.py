#!/usr/bin/env python3
"""Generate the Connect IQ Store cover image (500x500) for Planes Above Me.

Same style as the cover of the sister app Ahead: a dark gradient, the app's
compass ring, nearby aircraft as cyan triangles pointing along their ground
track, and the green arrow pointing at the aircraft you are facing, with its
contrail. Rendered at 4x and downsampled with LANCZOS. Pure Pillow, no network.

    python3 scripts/make_cover.py --font Quicksand.ttf   # -> store/cover_500.png
Quicksand (OFL): https://github.com/google/fonts/raw/main/ofl/quicksand/Quicksand%5Bwght%5D.ttf
"""
import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SS = 4
S = 500 * SS
CX, CY = 250 * SS, 198 * SS
R = 150 * SS

PLANE = (0x00, 0xFF, 0xFF)       # PLANE_COLOR in MainView.mc
GREEN = (0x33, 0xDD, 0x33)
RED = (0xFF, 0x3B, 0x3B)
RING = (0x3A, 0x4E, 0x63)
RING_HI = (0x5E, 0x79, 0x92)
WHITE = (0xFF, 0xFF, 0xFF)
TAGCOL = (0x9F, 0xB3, 0xC8)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def polar(bearing_deg, dist):
    th = math.radians(bearing_deg)
    return (CX + dist * math.sin(th), CY - dist * math.cos(th))


def triangle(d, x, y, ang, size, color):
    """MainView.drawTriangle: arrowhead pointing at ang (0 = up, clockwise)."""
    a = math.radians(ang)
    s, c = math.sin(a), math.cos(a)
    pts = [(0.0, -size), (0.62 * size, 0.55 * size), (0.0, 0.22 * size), (-0.62 * size, 0.55 * size)]
    d.polygon([(x + px * c - py * s, y + px * s + py * c) for px, py in pts], fill=color)


def font(path, weight, px):
    f = ImageFont.truetype(path, px)
    f.set_variation_by_name(weight)
    return f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True, help="variable Quicksand TTF")
    ap.add_argument("--out", default=os.path.join(ROOT, "store", "cover_500.png"))
    args = ap.parse_args()

    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    top, bot = (0x10, 0x27, 0x3C), (0x05, 0x08, 0x0D)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(top, bot, y / S))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(28, 0, -1):
        rr = R * (1.7 * i / 28)
        gd.ellipse([CX - rr, CY - rr, CX + rr, CY + rr], fill=(0x1E, 0x4D, 0x78, int(46 * (i / 28) ** 2)))
    img = Image.alpha_composite(img.convert("RGBA"), glow)
    d = ImageDraw.Draw(img)

    # compass ring with ticks and cardinal letters
    d.ellipse([CX - R, CY - R, CX + R, CY + R], outline=RING, width=3 * SS)
    rin = R - 9 * SS
    d.ellipse([CX - rin, CY - rin, CX + rin, CY + rin], outline=(0x21, 0x2F, 0x3E), width=SS)
    for b in range(0, 360, 10):
        major = b % 90 == 0
        p1, p2 = polar(b, R - 3 * SS), polar(b, R - (20 if major else 11) * SS)
        d.line([p1, p2], fill=RED if b == 0 else (RING_HI if major else RING), width=(3 if major else 1) * SS)
    cf = font(args.font, "Medium", 26 * SS)
    for b, label, col in [(0, "N", RED), (90, "E", TAGCOL), (180, "S", TAGCOL), (270, "W", TAGCOL)]:
        x, y = polar(b, R - 36 * SS)
        d.text((x, y), label, font=cf, fill=col, anchor="mm")

    # nearby aircraft (bearing, distance fraction, track)
    for b, frac, trk in [(58, 0.70, 250), (118, 0.52, 20), (150, 0.80, 300), (212, 0.62, 95),
                         (248, 0.78, 160), (300, 0.50, 40)]:
        x, y = polar(b, R * frac)
        gl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(gl).ellipse([x - 16 * SS, y - 16 * SS, x + 16 * SS, y + 16 * SS], fill=PLANE + (45,))
        img = Image.alpha_composite(img, gl)
        d = ImageDraw.Draw(img)
        triangle(d, x, y, trk, 11 * SS, PLANE)

    # the aircraft you are facing: contrail, glow and the larger triangle
    fb, frac, trk = -30, 0.66, 62
    fx, fy = polar(fb, R * frac)
    th = math.radians(trk)
    ux, uy = math.sin(th), -math.cos(th)
    trail = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(trail)
    for i in range(40):
        t0, t1 = i / 40, (i + 1) / 40
        L = 120 * SS
        a = int(150 * (1 - t0) ** 1.5)
        td.line([(fx - ux * (14 * SS + L * t0), fy - uy * (14 * SS + L * t0)),
                 (fx - ux * (14 * SS + L * t1), fy - uy * (14 * SS + L * t1))],
                fill=(0xE8, 0xF4, 0xFF, a), width=int((5 - 3 * t0) * SS))
    img = Image.alpha_composite(img, trail.filter(ImageFilter.GaussianBlur(2 * SS)))
    gl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gld = ImageDraw.Draw(gl)
    for i in range(10, 0, -1):
        rr = 26 * SS * i / 10
        gld.ellipse([fx - rr, fy - rr, fx + rr, fy + rr], fill=GREEN + (int(70 * (i / 10) ** 2),))
    img = Image.alpha_composite(img, gl)
    d = ImageDraw.Draw(img)
    triangle(d, fx, fy, trk, 17 * SS, (0xE0, 0xFF, 0xFF))

    # green direction arrow from the centre toward it (as MainView's arrow)
    tb = math.radians(fb)
    ax, ay = math.sin(tb), -math.cos(tb)
    px, py = math.cos(tb), math.sin(tb)
    L = R * frac - 30 * SS
    w = 13 * SS

    def pt(f, side):
        return (CX + ax * f + px * side, CY + ay * f + py * side)
    d.polygon([pt(L, 0), pt(0.16 * L, w), pt(-0.2 * L, 0), pt(0.16 * L, -w)], fill=GREEN)
    hr = 7 * SS
    d.ellipse([CX - hr, CY - hr, CX + hr, CY + hr], fill=RING_HI)

    # title and tagline
    for text, f, y, col in [("Planes Above Me", font(args.font, "Bold", 58 * SS), 428, WHITE),
                            ("What plane is that?", font(args.font, "Medium", 25 * SS), 474, TAGCOL)]:
        w = d.textlength(text, font=f)
        d.text(((S - w) / 2, y * SS), text, font=f, fill=col, anchor="ls")

    img.convert("RGB").resize((500, 500), Image.LANCZOS).save(args.out)
    print("wrote", os.path.relpath(args.out, ROOT))


if __name__ == "__main__":
    main()
