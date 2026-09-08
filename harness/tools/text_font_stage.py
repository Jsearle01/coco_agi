"""harness/tools/text_font_stage.py -- a font for the EYE GATE, to build/ and nowhere else.

★★★★★ THIS IS NOT content/'s AUTHORED FONT AND MUST NEVER BECOME IT. §2B protects "the authored
8x8 40-column font" as unreproducible hand-tuned work; that asset does not exist yet, and this tool
does not create it. What it does is extract the 8x8 glyph table the ORACLE renders with, into
build/ (gitignored), so AC-1's eye gate can show the ported engine placing and drawing real glyphs
instead of blocks.

★★★★ WHY THAT IS THE RIGHT CHOICE RATHER THAN A CONVENIENT ONE: an eye gate exists so a human can
answer "is this right?", and a placeholder font makes the answer "I cannot tell". Using the
oracle's own glyphs means anything Jay sees wrong is the ENGINE, not the letterforms.
★★★ And it stays out of the repository: the extraction runs at gate time, the output lands in
build/, and nothing third-party is committed. When §2B's font is authored, this tool is deleted.

★★ Source: ScummVM's shared PC-BIOS table, graphics/fonts/dosfont.cpp `fontData_PCBIOS[256*8]`,
which is what engines/agi loads for a DOS-render AGI game (font.cpp init -> loadFontScummVMFile
falls through to the built-in).

usage:  python harness/tools/text_font_stage.py [out.bin]
"""
import os
import re
import sys

SRC = r"C:\Projects\scummvm\graphics\fonts\dosfont.cpp"
MARK = "fontData_PCBIOS[256 * 8] = {"


def main(argv):
    out = argv[1] if len(argv) > 1 else "build/text_font.bin"
    if not os.path.isfile(SRC):
        print("★★★ no %s -- the oracle tree is where this comes from" % SRC)
        return 1
    text = open(SRC, "r", errors="replace").read()
    i = text.find(MARK)
    if i < 0:
        print("★★★ %s not found in %s -- the table was renamed and this tool is now guessing"
              % (MARK, SRC))
        return 1
    j = text.find("};", i)
    body = text[i + len(MARK):j]
    # ★★ Strip comments before scanning for numbers: dosfont.cpp annotates each glyph with its
    # character, and a stray decimal in a comment would land in the table as a glyph row.
    body = re.sub(r"/\*.*?\*/", " ", body, flags=re.S)
    body = re.sub(r"//[^\n]*", " ", body)
    vals = [int(v, 0) for v in re.findall(r"0x[0-9A-Fa-f]+|\b\d+\b", body)]
    if len(vals) != 256 * 8:
        print("★★★ parsed %d bytes, expected 2048 -- refusing to write a font that is the wrong "
              "shape [a wrong table assembles fine and means something else, AD-125]" % len(vals))
        return 1
    if any(v > 255 for v in vals):
        print("★★★ a parsed value exceeds 255 -- this is not a byte table")
        return 1
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "wb") as f:
        f.write(bytes(vals))
    nz = sum(1 for v in vals if v)
    print("  %s: 2048 bytes, %d non-zero rows (%d glyphs have ink)"
          % (out, nz, sum(1 for c in range(256) if any(vals[c * 8:c * 8 + 8]))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
