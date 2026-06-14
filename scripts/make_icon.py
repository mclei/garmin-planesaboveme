#!/usr/bin/env python3
"""Generate resources/drawables/launcher_icon.png (70x70 airliner icon).

Pure standard library (zlib + struct), no PIL needed. Renders an anti-aliased
airliner (top-down, nose up) on a sky-blue gradient disc, with vapor trails,
a soft drop shadow, blue belly shading and a red tail-fin accent.

Anti-aliasing is done by 4x4 supersampling per output pixel.
"""
import os
import struct
import zlib

W = H = 70
SS = 4                         # supersampling factor (per axis)
CX = (W - 1) / 2.0
CY = (H - 1) / 2.0
R = 34.0                       # disc radius

# --- colours (r, g, b) -------------------------------------------------------
SKY_TOP = (150, 212, 255)      # light sky near top of disc
SKY_BOT = (28, 104, 200)       # deeper blue near bottom
BODY_TOP = (252, 253, 255)     # plane upper surface (bright white)
BODY_BOT = (196, 214, 236)     # plane lower surface (cool shadow)
ACCENT = (228, 64, 60)         # red tail-fin / nose accent
WINDOW = (60, 96, 140)         # cockpit glass
TRAIL = (255, 255, 255)        # vapour trail
SHADOW = (8, 28, 60)           # drop shadow tint


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def over(dst, src, a):
    """Composite straight-alpha src (rgb) with coverage a over dst (rgba)."""
    da = dst[3]
    out_a = a + da * (1 - a)
    if out_a <= 0:
        return (0.0, 0.0, 0.0, 0.0)
    out = [(src[i] * a + dst[i] * da * (1 - a)) / out_a for i in range(3)]
    return (out[0], out[1], out[2], out_a)


def point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y):
            xint = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < xint:
                inside = not inside
        j = i
    return inside


def mirror(poly):
    """Mirror a polygon across the vertical centre line x = 35."""
    return [(70 - px, py) for (px, py) in poly]


# --- plane geometry (70x70 space, nose up, centred on x=35) ------------------
# Fuselage: tapered capsule from nose (top) to tail (bottom).
FUSELAGE = [
    (35, 7), (33.5, 11), (32, 18), (31.5, 30), (31.5, 46),
    (32.5, 54), (33.5, 58), (35, 59),
    (36.5, 58), (37.5, 54), (38.5, 46), (38.5, 30),
    (38.5, 18), (36.5, 11),
]

# Swept-back main wings.
WING_L = [(32, 30), (10, 45), (10.5, 48.5), (32, 40)]
WING_R = mirror(WING_L)

# Swept-back tailplane (horizontal stabiliser) near the tail.
TAIL_L = [(33, 50), (22, 57), (22.5, 59), (33, 55)]
TAIL_R = mirror(TAIL_L)

# Vertical stabiliser (red accent) — small kite at the very tail.
FIN = [(35, 50), (33.3, 58.5), (35, 60.5), (36.7, 58.5)]

# Cockpit window band near the nose.
WINDOW_BAND = [(33.6, 14), (36.4, 14), (37.0, 19), (33.0, 19)]

# Vapour trails streaming from the two wing engines, downward.
TRAIL_L = [(20.0, 44.0), (22.0, 44.0), (24.5, 70.0), (21.0, 70.0)]
TRAIL_R = mirror(TRAIL_L)


def plane_bits(x, y):
    """Return (is_plane, kind) for a point. kind selects colour/shading."""
    if point_in_poly(x, y, FIN):
        return True, "fin"
    if point_in_poly(x, y, WINDOW_BAND):
        return True, "window"
    if (point_in_poly(x, y, FUSELAGE) or point_in_poly(x, y, WING_L)
            or point_in_poly(x, y, WING_R) or point_in_poly(x, y, TAIL_L)
            or point_in_poly(x, y, TAIL_R)):
        return True, "body"
    return False, None


def in_plane_any(x, y):
    return plane_bits(x, y)[0]


def sample(x, y):
    """Return straight-alpha rgba (0..1 floats) for a sub-sample point."""
    px = (0.0, 0.0, 0.0, 0.0)

    dx, dy = x - CX, y - CY
    d2 = dx * dx + dy * dy
    if d2 > R * R:
        return px  # transparent outside the disc

    # Disc base: vertical sky gradient + soft radial vignette for depth.
    t = (y - (CY - R)) / (2 * R)
    t = min(1.0, max(0.0, t))
    base = lerp(SKY_TOP, SKY_BOT, t)
    vig = (d2 ** 0.5) / R
    base = lerp(base, SKY_BOT, 0.35 * vig * vig)
    px = (base[0], base[1], base[2], 1.0)

    # Vapour trails behind the engines (fade out toward bottom).
    if point_in_poly(x, y, TRAIL_L) or point_in_poly(x, y, TRAIL_R):
        fade = max(0.0, 1.0 - (y - 44.0) / 26.0)
        px = over(px, TRAIL, 0.30 * fade)

    # Soft drop shadow: the plane shape offset down-right.
    if in_plane_any(x - 1.6, y - 1.8):
        px = over(px, SHADOW, 0.28)

    is_plane, kind = plane_bits(x, y)
    if is_plane:
        if kind == "fin":
            px = over(px, ACCENT, 1.0)
        elif kind == "window":
            px = over(px, WINDOW, 1.0)
        else:
            # Body: top-to-bottom white-to-cool-grey shading for volume.
            bt = min(1.0, max(0.0, (y - 8.0) / 50.0))
            col = lerp(BODY_TOP, BODY_BOT, bt)
            px = over(px, (col[0], col[1], col[2]), 1.0)

    return px


def pixel(ix, iy):
    r = g = b = a = 0.0
    step = 1.0 / SS
    for sy in range(SS):
        for sx in range(SS):
            x = ix + (sx + 0.5) * step
            y = iy + (sy + 0.5) * step
            pr, pg, pb, pa = sample(x, y)
            # accumulate premultiplied for correct edge AA
            r += pr * pa
            g += pg * pa
            b += pb * pa
            a += pa
    n = SS * SS
    a /= n
    if a <= 0:
        return (0, 0, 0, 0)
    r = r / n / a
    g = g / n / a
    b = b / n / a
    clamp = lambda v: max(0, min(255, int(round(v))))
    return (clamp(r), clamp(g), clamp(b), clamp(a * 255))


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def main():
    raw = b""
    for y in range(H):
        raw += b"\x00"
        for x in range(W):
            raw += bytes(pixel(x, y))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "resources", "drawables", "launcher_icon.png")
    with open(out, "wb") as fh:
        fh.write(png)
    print("wrote", out, len(png), "bytes")


if __name__ == "__main__":
    main()
