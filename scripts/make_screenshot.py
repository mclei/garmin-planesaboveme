#!/usr/bin/env python3
"""Render store screenshots of Planes Above Me's main screen.

Reproduces MainView.onUpdate geometry (ring = min(w,h)/2 - 10, plane triangles
at sqrt-scaled distance rotated to their ground track, the focused aircraft's
direction arrow coloured by how well you face it, the callsign / route /
altitude / type / speed+distance lines at the same ring fractions, and the
status line) for a plausible scene over Prague. Fonts: Roboto at the Venu X1
font sizes. Output:

    store/screenshot_venux1.png   448x486, as on the Venu X1
    store/screenshot_round.png    454x454 round display set in a generic watch

    python3 scripts/make_screenshot.py --font Roboto.ttf
Roboto: https://github.com/google/fonts/raw/main/ofl/roboto/Roboto%5Bwdth,wght%5D.ttf
"""
import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# Garmin system colours used by MainView.mc
WHITE = (0xFF, 0xFF, 0xFF)
LT_GRAY = (0xAA, 0xAA, 0xAA)
DK_GRAY = (0x55, 0x55, 0x55)
RED = (0xFF, 0x00, 0x00)
GREEN = (0x00, 0xFF, 0x00)
YELLOW = (0xFF, 0xAA, 0x00)
PLANE = (0x00, 0xFF, 0xFF)          # PLANE_COLOR

# Font sizes in px for a ~450 px, 326 ppi display (Venu X1 / fenix 8 class)
FONT_PX = {"xtiny": 31, "tiny": 38, "small": 45, "medium": 52}

HEADING = 225.0      # facing south-west: cardinal labels on the diagonals, clear of the text
RADIUS_M = 10000.0
# (callsign, bearing deg, distance m, track deg). Bearings relative to the heading keep the
# other aircraft above and below the text block, as a clean scene for the store.
PLANES = [
    ("LOT281", 232.0, 6200.0, 272.0),     # +7 deg (focused)
    ("RYR82QK", 190.0, 9000.0, 120.0),     # -35 deg
    ("CSA3PL", 265.0, 8000.0, 230.0),     # +40 deg
    ("WZZ1KM", 15.0, 9500.0, 15.0),     # +150 deg
    ("UAE140", 65.0, 8500.0, 300.0),     # +200 deg
    ("SWR7TR", 55.0, 7000.0, 95.0),     # -170 deg
    ("OKHEL", 200.0, 6000.0, 330.0),     # -25 deg
]
# Labels as PlaneModel builds them (buildRouteLabel / buildTypeLabel)
FOCUSED = {
    "label": "LOT281",
    "route": "WAW/PL -> LHR/GB London",
    "alt": "11280 m",
    "type": "Boeing B38M - LOT Polish Airlines",
    "line": "842 km/h  6.2 km",
}


def norm(d):
    return d % 360.0


def angle_diff(a, b):
    d = (a - b + 540.0) % 360.0 - 180.0
    return d


def cardinal(deg):
    dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    return dirs[int((deg + 22.5) // 45) % 8]


class Screen:
    def __init__(self, w, h, font_path):
        self.w, self.h = w, h
        self.img = Image.new("RGB", (w, h), (0, 0, 0))
        self.d = ImageDraw.Draw(self.img)
        self.fonts = {}
        for k, px in FONT_PX.items():
            f = ImageFont.truetype(font_path, px)
            try:
                f.set_variation_by_name("Regular")
            except Exception:
                pass
            self.fonts[k] = f

    def text(self, x, y, font, s, color):
        """TEXT_JUSTIFY_CENTER | TEXT_JUSTIFY_VCENTER"""
        self.d.text((x, y), s, font=self.fonts[font], fill=color, anchor="mm")

    def fit(self, s, font, max_w):
        f = self.fonts[font]
        if f.getlength(s) <= max_w:
            return s
        while len(s) > 2 and f.getlength(s + "..") > max_w:
            s = s[:-1]
        return s + ".."

    def triangle(self, x, y, ang, size, color):
        a = math.radians(ang)
        s, c = math.sin(a), math.cos(a)
        pts = [(0.0, -size), (0.62 * size, 0.55 * size), (0.0, 0.22 * size), (-0.62 * size, 0.55 * size)]
        self.d.polygon([(int(x + px * c - py * s), int(y + px * s + py * c)) for px, py in pts], fill=color)

    def draw(self):
        w, h = self.w, self.h
        cx, cy = w // 2, h // 2
        ring = min(w, h) // 2 - 10
        d = self.d
        # compass ring
        d.ellipse([cx - ring, cy - ring, cx + ring, cy + ring], outline=DK_GRAY, width=2)
        for deg in range(0, 360, 45):
            a = math.radians(norm(deg - HEADING))
            sx, sy = math.sin(a), math.cos(a)
            if deg % 90 == 0:
                self.text(int(cx + (ring - 18) * sx), int(cy - (ring - 18) * sy), "tiny",
                          "NESW"[deg // 90], RED if deg == 0 else LT_GRAY)
            else:
                d.line([int(cx + (ring - 8) * sx), int(cy - (ring - 8) * sy),
                        int(cx + ring * sx), int(cy - ring * sy)], fill=DK_GRAY)
        # aircraft
        for cs, brg, dist, trk in reversed(PLANES):
            rr = math.sqrt(min(1.0, dist / RADIUS_M))
            rpx = (ring - 28) * rr
            a = math.radians(norm(brg - HEADING))
            self.triangle(cx + rpx * math.sin(a), cy - rpx * math.cos(a), norm(trk - HEADING), 9.0, PLANE)
        # focused aircraft
        brg = PLANES[0][1]
        rel = angle_diff(brg, HEADING)
        col = GREEN if abs(rel) <= 20 else (YELLOW if abs(rel) <= 60 else LT_GRAY)
        self.triangle(cx, cy - ring * 0.45, norm(rel), ring * 0.17, col)
        max_w = int(ring * 1.8)
        self.text(cx, cy - int(ring * 0.22), "tiny", self.fit(FOCUSED["label"], "tiny", max_w), WHITE)
        self.text(cx, cy - int(ring * 0.04), "small", self.fit(FOCUSED["route"], "small", max_w), PLANE)
        self.text(cx, cy + int(ring * 0.15), "small", FOCUSED["alt"], WHITE)
        self.text(cx, cy + int(ring * 0.34), "xtiny", self.fit(FOCUSED["type"], "xtiny", max_w), LT_GRAY)
        self.text(cx, cy + int(ring * 0.50), "xtiny", self.fit(FOCUSED["line"], "xtiny", max_w), DK_GRAY)
        # status line
        s = f"{int(HEADING)} {cardinal(HEADING)} | {len(PLANES)} aircraft"
        bottom = h - (cy + ring)
        sy = cy + ring + bottom // 2
        if bottom < 20:
            sy = cy + int(ring * 0.82)
            r = min(w, h) // 2
            asc, desc = self.fonts["xtiny"].getmetrics()
            dy = sy - cy + (asc + desc) // 2
            chord = int(2.0 * math.sqrt(r * r - dy * dy)) - 12 if dy < r else 0
            if " aircraft" in s and self.fonts["xtiny"].getlength(s) > chord:
                s = s[:s.index(" aircraft")]
            s = self.fit(s, "xtiny", chord)
        self.text(cx, sy, "xtiny", s, LT_GRAY)
        return self.img


def watch_frame(screen):
    """Round display set in a generic sports watch (case, bezel, buttons, strap stubs)
    on a transparent background; same frame as the Zenith store screenshots."""
    k = 2
    d = screen.width
    R = d // 2
    W, H = int(R * 2.7), int(R * 2.75)
    cx, cy = W // 2, H // 2
    big = Image.new("RGBA", (W * k, H * k), (0, 0, 0, 0))
    g = ImageDraw.Draw(big)

    def ell(r, fill):
        g.ellipse([(cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k], fill=fill)

    sw = int(R * 1.2)
    for sgn in (-1, 1):
        y0, y1 = cy + sgn * int(R * 1.05), (0 if sgn < 0 else H)
        g.rounded_rectangle([(cx - sw // 2) * k, min(y0, y1) * k, (cx + sw // 2) * k, max(y0, y1) * k],
                            radius=24 * k, fill=(34, 36, 40, 255))
        for i in range(1, 6):
            yy = y0 + sgn * i * int(R * 0.22)
            if 0 < yy < H:
                g.line([(cx - sw // 2 + 18) * k, yy * k, (cx + sw // 2 - 18) * k, yy * k],
                       fill=(26, 27, 30, 255), width=3 * k)
        lw, lh = int(R * 0.98), int(R * 0.32)
        ly = cy + sgn * int(R * 1.02)
        g.rounded_rectangle([(cx - lw // 2) * k, (ly - lh // 2) * k, (cx + lw // 2) * k, (ly + lh // 2) * k],
                            radius=30 * k, fill=(70, 73, 78, 255))
    for side, angs in ((-1, (-40, 40)), (1, (-40, 0, 40))):
        for a in angs:
            r = R * 1.2
            bx = cx + side * r * math.cos(math.radians(a))
            by = cy + r * math.sin(math.radians(a))
            g.rounded_rectangle([(bx - 16) * k, (by - 22) * k, (bx + 16) * k, (by + 22) * k],
                                radius=8 * k, fill=(92, 96, 102, 255))
    case_r = int(R * 1.2)
    case = Image.new("L", (W * k, H * k), 0)
    ImageDraw.Draw(case).ellipse([(cx - case_r) * k, (cy - case_r) * k, (cx + case_r) * k, (cy + case_r) * k], fill=255)
    grad = Image.new("RGBA", (2, 2))
    grad.putdata([(168, 172, 178, 255), (112, 115, 120, 255), (100, 103, 108, 255), (52, 54, 58, 255)])
    metal = Image.new("RGBA", (W * k, H * k), (0, 0, 0, 0))
    metal.paste(grad.resize((2 * case_r * k, 2 * case_r * k), Image.BILINEAR), ((cx - case_r) * k, (cy - case_r) * k))
    big.paste(metal, (0, 0), case)
    rim_r = int(R * 1.15)
    rim = Image.new("L", (W * k, H * k), 0)
    ImageDraw.Draw(rim).ellipse([(cx - rim_r) * k, (cy - rim_r) * k, (cx + rim_r) * k, (cy + rim_r) * k], fill=255)
    big.paste(metal.transpose(Image.ROTATE_180), (0, 0), rim)
    ell(int(R * 1.1), (24, 25, 28, 255))
    for i in range(60):
        a = math.radians(i * 6)
        r1, r2 = R * 1.035, R * (1.085 if i % 5 == 0 else 1.06)
        g.line([(cx + r1 * math.cos(a)) * k, (cy + r1 * math.sin(a)) * k,
                (cx + r2 * math.cos(a)) * k, (cy + r2 * math.sin(a)) * k],
               fill=(120, 124, 130, 255), width=(3 if i % 5 == 0 else 1) * k)
    ell(R + 6, (0, 0, 0, 255))
    out = big.resize((W, H), Image.LANCZOS)
    mask = Image.new("L", (d * 4, d * 4), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, d * 4 - 1, d * 4 - 1], fill=255)
    out.paste(screen.convert("RGB"), (cx - R, cy - R), mask.resize((d, d), Image.LANCZOS))
    sh = out.getchannel("A").filter(ImageFilter.GaussianBlur(14)).point(lambda v: v * 90 // 255)
    res = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    res.paste(Image.new("RGBA", (W, H), (0, 0, 0, 255)), (8, 8), sh)
    res.alpha_composite(out, (0, 0))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True, help="Roboto TTF (variable or Regular)")
    ap.add_argument("--out", default=os.path.join(ROOT, "store"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    Screen(448, 486, args.font).draw().save(os.path.join(args.out, "screenshot_venux1.png"))
    watch_frame(Screen(454, 454, args.font).draw()).save(os.path.join(args.out, "screenshot_round.png"))
    print("written store/screenshot_venux1.png, store/screenshot_round.png")


if __name__ == "__main__":
    main()
