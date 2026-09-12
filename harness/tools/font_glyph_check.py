#!/usr/bin/env python3
"""harness/tools/font_glyph_check.py -- do the codepoints a title uses have real glyphs? [T-P0-089]

★★★★★ WHAT AC-3 ACTUALLY NEEDS TO SHOW. The 128-glyph font folded every codepoint >= 128 to space,
so 13 fan titles rendered blanks where they meant box-drawing and accented characters. With 256
glyphs staged the fold is compiled out -- but "the fold is gone" is a statement about the BUILD.
**The question is whether those codepoints now render as themselves**, and that is a property of
the font file: a glyph that is blank, or identical to space, would still render as a blank.

★★★★ SO IT CHECKS TWO THINGS PER CODEPOINT, and the second is the one that can fail quietly:
    non-blank   -- the glyph has at least one set pixel
    != space    -- the glyph differs from glyph 32
A glyph can be non-blank and still be wrong, but a glyph that is blank or equal to space renders
EXACTLY as the fold did, and the fix would have changed nothing visible.

★★★ It reads build/text_font.bin -- the file the harness stages -- not the source that generates
it, so it certifies what actually reaches the machine.

★★ §2P: codepoint numbers and pixel counts. No message text.

usage:
  python harness/tools/font_glyph_check.py --codepoints 128,129,130 [--font build/text_font.bin]
"""
import argparse
import io
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", default="build/text_font.bin")
    ap.add_argument("--codepoints", required=True)
    ap.add_argument("--staged", type=int, default=0,
                    help="bytes the build actually stages (P3_FONT_BYTES); 0 = whole file")
    a = ap.parse_args()

    data = pathlib.Path(a.font).read_bytes()
    staged = a.staged or len(data)
    print("font %s: %d bytes (%d glyphs); build stages %d bytes (%d glyphs)"
          % (a.font, len(data), len(data) // 8, staged, staged // 8))
    space = data[32 * 8:33 * 8]

    bad = 0
    print("%-6s %-10s %-9s %-9s %s" % ("cp", "staged?", "non-blank", "!= space", "set pixels"))
    for s in [x.strip() for x in a.codepoints.split(",") if x.strip()]:
        cp = int(s)
        off = cp * 8
        in_range = off + 8 <= staged
        if not in_range:
            # ★★ A codepoint outside the staged range does not read the font at all -- it reads
            #    whatever follows it, which is worse than a blank and is why this is checked first.
            print("%-6d %-10s %-9s %-9s %s" % (cp, "NO", "-", "-", "★★★ OUTSIDE THE STAGED FONT"))
            bad += 1
            continue
        g = data[off:off + 8]
        pixels = sum(bin(b).count("1") for b in g)
        nonblank = pixels > 0
        notspace = g != space
        if not (nonblank and notspace):
            bad += 1
        print("%-6d %-10s %-9s %-9s %d"
              % (cp, "yes", "yes" if nonblank else "★★★NO", "yes" if notspace else "★★★NO", pixels))

    print("")
    if bad:
        print("★★★ %d codepoint(s) would still render as a blank -- the fold's behaviour, without"
              " the fold." % bad)
        return 1
    print("★ every codepoint checked has a distinct, non-blank glyph inside the staged font.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
