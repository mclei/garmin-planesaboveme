#!/usr/bin/env python3
"""Generate resources/drawables/launcher_icon.png (70x70 plane icon).

Pure standard library (zlib + struct), no PIL needed. Draws a white plane
silhouette (pointing up) on a dark navy disc.
"""
import os
import struct
import zlib

W = H = 70
CX = (W - 1) / 2.0
CY = (H - 1) / 2.0
R = 33.0

BG = (0, 0, 0, 0)             # transparent corners
FACE = (16, 32, 64, 255)      # dark navy disc
PLANE = (235, 240, 255, 255)  # white plane


def in_tri(p, a, b, c):
    def sign(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
    d1, d2, d3 = sign(p, a, b), sign(p, b, c), sign(p, c, a)
    return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))


def in_rect(x, y, x0, y0, x1, y1):
    return x0 <= x <= x1 and y0 <= y <= y1


def is_plane(x, y):
    # nose
    if in_tri((x, y), (35, 9), (30, 22), (40, 22)):
        return True
    # fuselage
    if in_rect(x, y, 32, 20, 38, 56):
        return True
    # wings
    if in_rect(x, y, 14, 31, 56, 38):
        return True
    # tailplane
    if in_rect(x, y, 26, 50, 44, 56):
        return True
    return False


def pixel(x, y):
    dx, dy = x - CX, y - CY
    if dx * dx + dy * dy > R * R:
        return BG
    if is_plane(x, y):
        return PLANE
    return FACE


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
