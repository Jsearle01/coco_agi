#!/usr/bin/env python3
"""harness/tools/pal_reference.py -- AC-12's OTHER HALF: the oracle's 16 indices, rendered.

★★★ AC-12 asks for the CoCo3 swatches "beside the oracle's rendering of the same 16 indices".
The first attempt produced only the CoCo3 side, which is not a comparison -- it is a picture of
one thing. This synthesises the reference strip so the two can be viewed together.

★★ §3 COMPLIANCE, AND IT IS THE REASON THIS IS A SEPARATE FILE RATHER THAN A COMPOSITE. I may
not read, analyse or interpret PNG pixel content. Compositing the CoCo3 capture with this strip
would require reading its pixels. So this writes an INDEPENDENT image of identical geometry and
identical band order, and the comparison is Jay's to make by looking at both.
★ The only thing read from the capture is its IHDR width/height -- image dimensions, not pixel
content. Stated explicitly rather than glossed.

★★★ THE BANDS DO NOT LINE UP HORIZONTALLY, AND CLAIMING THEY DID WAS WRONG. The CoCo3 capture
is the whole MAME screen INCLUDING THE BORDER; the AGI picture is 320 px wide inside it. Making
this strip the same OUTER size therefore does not put band 6 at the same x in both images, and
finding the inset would mean reading pixels -- which §3 forbids. So the two images share the
ORDER and the COUNT, not the geometry, and the comparison AC-12 needs ("is band 6 brown or dark
yellow") works fine on that basis: count six bands in from the left in each.

★★ THE REFERENCE IS EGA's PALETTE, WHICH IS WHAT AGI TARGETS. These are the 8-bit-per-channel
values EGA actually produces; the CoCo3 side shows what the GIME makes of the 2-bit-per-channel
encoding of the same colours. ★ A visible difference in SATURATION is expected -- the GIME has
4 levels per channel and EGA's values land exactly on them, so a difference in HUE is not.

★ No game data is involved: sixteen blocks of a known index (the note says so explicitly), so
this capture is not copyrighted content.
"""
import argparse
import io
import pathlib
import struct
import sys
import zlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# The same table pal_check.py derives from; EGA's 16 colours, 8 bits per channel.
EGA = [
    ("black",         0x00, 0x00, 0x00),
    ("blue",          0x00, 0x00, 0xAA),
    ("green",         0x00, 0xAA, 0x00),
    ("cyan",          0x00, 0xAA, 0xAA),
    ("red",           0xAA, 0x00, 0x00),
    ("magenta",       0xAA, 0x00, 0xAA),
    ("brown",         0xAA, 0x55, 0x00),
    ("light grey",    0xAA, 0xAA, 0xAA),
    ("dark grey",     0x55, 0x55, 0x55),
    ("light blue",    0x55, 0x55, 0xFF),
    ("light green",   0x55, 0xFF, 0x55),
    ("light cyan",    0x55, 0xFF, 0xFF),
    ("light red",     0xFF, 0x55, 0x55),
    ("light magenta", 0xFF, 0x55, 0xFF),
    ("yellow",        0xFF, 0xFF, 0x55),
    ("white",         0xFF, 0xFF, 0xFF),
]


def ihdr_size(path):
    """Width and height from the PNG header. ★ DIMENSIONS ONLY -- no pixel data is read."""
    with open(path, "rb") as f:
        sig = f.read(8)
        if sig != b"\x89PNG\r\n\x1a\n":
            raise ValueError("%s is not a PNG" % path)
        f.read(4)                       # IHDR length
        if f.read(4) != b"IHDR":
            raise ValueError("%s: first chunk is not IHDR" % path)
        w, h = struct.unpack(">II", f.read(8))
    return w, h


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    pathlib.Path(path).write_bytes(png)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--match", default="", help="a PNG whose WIDTH/HEIGHT to match (IHDR only)")
    ap.add_argument("--width", type=int, default=640)
    ap.add_argument("--height", type=int, default=225)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    w, h = a.width, a.height
    src = "defaults"
    if a.match:
        w, h = ihdr_size(a.match)
        src = "%s (IHDR only)" % a.match

    # ★ Same ORDER as pal_swatch: index 0 leftmost, equal widths, full height. NOT the same
    # x-positions -- see the module docstring; the capture carries a border this does not.
    band = w // 16
    row = bytearray()
    for x in range(w):
        i = min(15, x // band) if band else 15
        _n, r, g, b = EGA[i]
        row += bytes((r, g, b))
    write_png(a.out, w, h, [row] * h)

    print("AC-12 reference strip written: %s" % a.out)
    print("  geometry %dx%d, from %s" % (w, h, src))
    print("  %d px per band, index 0 leftmost -- the same order pal_swatch paints" % band)
    print()
    print("  idx  name            EGA RGB")
    for i, (n, r, g, b) in enumerate(EGA):
        print("   %2d  %-14s #%02X%02X%02X" % (i, n, r, g, b))
    print()
    print("★ §3: this image was SYNTHESISED. No pixel of the CoCo3 capture was read -- only its")
    print("  IHDR width and height.")
    print("★★ The bands do NOT line up horizontally: the capture includes the CoCo3 border and")
    print("   this strip does not. Same ORDER and COUNT -- count six in from the left in each.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
