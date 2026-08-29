#!/usr/bin/env python3
"""harness/tools/comp_render.py -- AC-9: render a composited frame and its priority bands.

★★★ THREE IMAGES, AND THE MIDDLE ONE IS THE POINT. A human looking at a composited frame can
only judge whether it looks plausible. Showing the PRIORITY BUFFER beside it -- one colour per
band -- shows the depth boundary the sprite was actually tested against, so the question becomes
"is the sprite drawn on the near side of that boundary and not the far side", which is
answerable. That is the AC-12 pattern: pair the artifact with the thing that makes it legible.

  1  <frame>.coco3.png      the 6809's own visual plane, EGA/GIME palette   ★ GAME CONTENT
  2  <frame>.priority.png   the 6809's priority plane, one colour per band  ★ ours
  3  <frame>.oracle.png     the oracle's visual plane, same palette         ★ GAME CONTENT

★★ §2P AND JAY'S RULING. A composited frame is copyrighted game content and is NOT committed;
it is written under build/ and its path surfaced. The priority visualisation is our buffer
rendered as sixteen flat bands -- Jay ruled it is not game content -- and IS committed to
docs/gates/. Which is which is stated at the point of writing, not left to be inferred.

★★★ §3: this tool WRITES images. It never reads one back, and nothing here interprets pixel
content. The images are surfaced for Jay; any conclusion about them is his.

★ The palette: EGA's sixteen colours. The GIME's four levels per channel land exactly on EGA's
0x00/0x55/0xAA/0xFF, so for these indices the CoCo3's rendering is the same RGB -- pal_check.py
derives that and pal_reference.py's header says so. The pairing is therefore about PROVENANCE
(6809 buffer vs oracle buffer), which is what AC-3 already proved identical.
"""
import argparse
import pathlib
import struct
import sys
import zlib

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

W, H = 160, 168
SCALE = 3          # ★ 160x168 is small on a modern display; nearest-neighbour, no smoothing

EGA = [(0x00, 0x00, 0x00), (0x00, 0x00, 0xAA), (0x00, 0xAA, 0x00), (0x00, 0xAA, 0xAA),
       (0xAA, 0x00, 0x00), (0xAA, 0x00, 0xAA), (0xAA, 0x55, 0x00), (0xAA, 0xAA, 0xAA),
       (0x55, 0x55, 0x55), (0x55, 0x55, 0xFF), (0x55, 0xFF, 0x55), (0x55, 0xFF, 0xFF),
       (0xFF, 0x55, 0x55), (0xFF, 0x55, 0xFF), (0xFF, 0xFF, 0x55), (0xFF, 0xFF, 0xFF)]

# ★★ THE PRIORITY RAMP IS DELIBERATELY NOT THE EGA PALETTE. Priority is depth, not colour, and
# reusing the picture palette would invite reading it as a picture. Bands 0-2 are CONTROL data
# and are shown in strong reds so they cannot be mistaken for depth; 3-15 are a cold-to-warm
# ramp, near the viewer being warm.
PRI_RAMP = [(0xFF, 0x00, 0x00), (0xFF, 0x40, 0x00), (0xFF, 0x80, 0x00),
            (0x10, 0x10, 0x40), (0x18, 0x20, 0x60), (0x20, 0x30, 0x80),
            (0x28, 0x48, 0xA0), (0x30, 0x60, 0xB8), (0x38, 0x80, 0xC8),
            (0x48, 0x98, 0xC0), (0x60, 0xB0, 0xB0), (0x80, 0xC0, 0x90),
            (0xA8, 0xC8, 0x70), (0xC8, 0xC0, 0x58), (0xE0, 0xB0, 0x48),
            (0xF8, 0xF8, 0xF8)]


def write_png(path, width, height, rows):
    """Minimal RGB PNG. Same shape as pal_reference.py's writer, one home per fact aside."""
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    pathlib.Path(path).write_bytes(png)


def render(plane, palette, path):
    rows = []
    for y in range(H):
        row = bytearray()
        for x in range(W):
            r, g, b = palette[plane[y * W + x] & 0x0F]
            row += bytes((r, g, b)) * SCALE
        for _ in range(SCALE):
            rows.append(row)
    write_png(path, W * SCALE, H * SCALE, rows)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--guest-visual", required=True)
    ap.add_argument("--guest-priority", required=True)
    ap.add_argument("--oracle-visual", required=True)
    ap.add_argument("--out-content", required=True, help="build/ -- game content, NOT committed")
    ap.add_argument("--out-gate", required=True, help="docs/gates/ -- ours, committed")
    ap.add_argument("--tag", required=True)
    a = ap.parse_args()

    gv = pathlib.Path(a.guest_visual).read_bytes()
    gp = pathlib.Path(a.guest_priority).read_bytes()
    ov = pathlib.Path(a.oracle_visual).read_bytes()
    for n, b in (("guest visual", gv), ("guest priority", gp), ("oracle visual", ov)):
        if len(b) != W * H:
            print("★★★ %s is %d bytes, expected %d" % (n, len(b), W * H))
            return 1

    content = pathlib.Path(a.out_content)
    gate = pathlib.Path(a.out_gate)
    content.mkdir(parents=True, exist_ok=True)
    gate.mkdir(parents=True, exist_ok=True)

    p1 = render(gv, EGA, content / ("%s.coco3.png" % a.tag))
    p3 = render(ov, EGA, content / ("%s.oracle.png" % a.tag))
    p2 = render(gp, PRI_RAMP, gate / ("%s.priority.png" % a.tag))

    # ★ A byte-level statement about the pair, so the visual is not the only evidence.
    same = "IDENTICAL" if gv == ov else "★★★ DIFFER"
    print("frame %s" % a.tag)
    print("  guest visual vs oracle visual: %s" % same)
    print()
    print("  ★ GAME CONTENT -- NOT committed (§2P), surfaced for Jay:")
    print("      %s" % p1)
    print("      %s" % p3)
    print("  ★ OURS -- committed to docs/gates/:")
    print("      %s" % p2)
    print()
    print("  priority bands present in this frame:")
    seen = sorted({b for b in gp})
    for v in seen:
        kind = "CONTROL" if v <= 2 else "depth"
        print("      %2d  %-8s %6d px" % (v, kind, sum(1 for b in gp if b == v)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
