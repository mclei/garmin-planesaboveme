#!/usr/bin/env python3
"""Generate resources/drawables/launcher_icon.png (70x70 compass + plane icon).

Pure standard library (zlib + struct), no PIL needed. Renders an anti-aliased
navigation compass -- a steel bezel with tick marks and a red north marker
around a sky-blue face -- with a white airliner (nose up = north) as the
needle in the centre.

Anti-aliasing is done by 4x4 supersampling per output pixel.
"""
import math
import os
import struct
import zlib

W = H = 70
SS = 4                         # supersampling factor (per axis)
CX = (W - 1) / 2.0
CY = (H - 1) / 2.0
R = 34.0                       # outer radius
R_BEZEL = 28.5                 # bezel inner edge (face radius)

# --- colours (r, g, b) -------------------------------------------------------
BEZEL_OUT = (38, 64, 104)      # steel bezel, lit outer
BEZEL_IN = (16, 32, 60)        # steel bezel, shaded inner
FACE_CTR = (196, 228, 255)     # sky face, bright centre
FACE_EDGE = (44, 120, 208)     # sky face, deeper toward rim
TICK = (214, 228, 248)         # minor/major ticks
NORTH = (228, 64, 60)          # red north marker
BODY_TOP = (252, 253, 255)     # plane upper surface
BODY_BOT = (198, 216, 238)     # plane lower surface (cool shadow)
WINDOW = (54, 90, 134)         # cockpit glass
SHADOW = (8, 26, 56)           # drop shadow tint


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


# --- plane geometry (70x70 space, nose up, centred near 35,36) ---------------
FUSELAGE = [
    (35, 15), (33.7, 19), (32.8, 25), (32.4, 34), (32.4, 47),
    (33.2, 53), (34, 56), (35, 56.5),
    (36, 56), (36.8, 53), (37.6, 47), (37.6, 34),
    (37.2, 25), (36.3, 19),
]
WING_L = [(32.6, 34), (15.5, 46.5), (16, 49.5), (32.6, 41.5)]
WING_R = mirror(WING_L)
TAIL_L = [(33, 49), (25, 54.5), (25.3, 56.5), (33, 52.5)]
TAIL_R = mirror(TAIL_L)
FIN = [(35, 49), (33.6, 55.5), (35, 57.5), (36.4, 55.5)]      # red tail fin
WINDOW_BAND = [(34, 20), (36, 20), (36.6, 24.5), (33.4, 24.5)]


def plane_bits(x, y):
    """Return (is_plane, kind). kind selects colour/shading."""
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


def tick_color(dx, dy, dist):
    """Return (color, coverage) for compass ticks on the bezel, else None.

    Ticks sit just inside the bezel. 12 every 30 deg; N/E/S/W are longer.
    North (top) tick is red.
    """
    if dist < R_BEZEL - 5.0 or dist > R_BEZEL + 0.5:
        return None
    ang = math.degrees(math.atan2(dx, -dy)) % 360.0   # 0 = up, CW
    step = round(ang / 30.0) * 30.0
    da = abs(((ang - step + 180.0) % 360.0) - 180.0)  # angular gap to tick
    # tangential half-width in degrees scales so ticks stay ~1.2px wide
    halfdeg = math.degrees(1.2 / max(dist, 1.0))
    if da > halfdeg:
        return None
    major = (step % 90.0) < 0.001
    inner = R_BEZEL - (5.0 if major else 3.0)
    if dist < inner:
        return None
    col = NORTH if step < 0.001 else TICK
    return col, 1.0


def sample(x, y):
    """Return straight-alpha rgba (0..1 floats) for a sub-sample point."""
    dx, dy = x - CX, y - CY
    dist = math.sqrt(dx * dx + dy * dy)
    if dist > R:
        return (0.0, 0.0, 0.0, 0.0)   # transparent outside

    if dist >= R_BEZEL:
        # Bezel ring: shade from lit (top-left) to dark (bottom-right).
        f = 0.5 + 0.5 * ((dx + dy) / (R * 1.6))
        f = min(1.0, max(0.0, f))
        base = lerp(BEZEL_OUT, BEZEL_IN, f)
        px = (base[0], base[1], base[2], 1.0)
    else:
        # Face: radial sky gradient, bright centre to deep rim.
        t = dist / R_BEZEL
        base = lerp(FACE_CTR, FACE_EDGE, t * t)
        px = (base[0], base[1], base[2], 1.0)

    # Compass ticks on the bezel.
    tc = tick_color(dx, dy, dist)
    if tc is not None:
        px = over(px, tc[0], tc[1])

    # North marker: red triangle pointing inward at the top of the face.
    if point_in_poly(x, y, [(35, 17), (31.5, 6.5), (38.5, 6.5)]):
        px = over(px, NORTH, 1.0)

    # Soft drop shadow under the plane.
    if dist < R_BEZEL and in_plane_any(x - 1.4, y - 1.6):
        px = over(px, SHADOW, 0.26)

    # The plane (needle).
    is_plane, kind = plane_bits(x, y)
    if is_plane:
        if kind == "fin":
            px = over(px, NORTH, 1.0)
        elif kind == "window":
            px = over(px, WINDOW, 1.0)
        else:
            bt = min(1.0, max(0.0, (y - 15.0) / 42.0))
            col = lerp(BODY_TOP, BODY_BOT, bt)
            px = over(px, (col[0], col[1], col[2]), 1.0)

    return px


def pixel(ix, iy):
    r = g = b = a = 0.0
    step = 1.0 / SS
    for sy in range(SS):
        for sx in range(SS):
            pr, pg, pb, pa = sample(ix + (sx + 0.5) * step,
                                    iy + (sy + 0.5) * step)
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
