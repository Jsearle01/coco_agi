#!/usr/bin/env python3
"""harness/tools/agi_palette.py -- AGI's palette, ONE HOME for the host-side tools. [T-P0-056b]

★★★★★ WHY THIS MODULE EXISTS. Two facts about the palette were each duplicated across the tree,
and one of the duplicates is what put every p3b room in the wrong colours for four tasks [AD-125]:

  THE GIME BYTES   defined in src/harness/pic_probe.s -- a RENDERER PROBE -- so the integration
                   probe could not reach them and hal_globals.s pointed mode 2 somewhere else.
                   Now: content/agi_palette.s, and this module PARSES it rather than restating it.
  THE EGA REFERENCE  written out three times, in pal_check.py, pal_reference.py and
                   comp_render.py. Now: EGA below, imported by all three.

★★★★ THE GIME BYTES ARE PARSED, NEVER RETYPED. A second copy in Python would be a second thing
to keep right, and the whole point of the move is that there is one. `table()` reads the assembly
the guest actually assembles, so a host tool cannot disagree with the shipped table [L-45's
reasoning applied to data: the check must read the artifact, not a transcription of it].

★★★ THE EGA REFERENCE IS NOT THE SAME FACT and is not parsed from anything: it is the published
EGA palette, the INPUT the GIME bytes were derived from, and it is what pal_reference.py renders
so Jay can compare. Keeping both here, side by side, is what lets `verify()` state that they
agree -- which is the desk check behind AC-12.

★★ §2B: content/agi_palette.s is authored, PROTECTED content. This module reads it and never
writes it.

usage:  import agi_palette                      (from harness/tools/)
        python harness/tools/agi_palette.py     (prints the table and verifies it)
"""
import pathlib
import re
import sys

# ★ Repo root from this file, so a caller's working directory cannot change what is read.
ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "content" / "agi_palette.s"

# EGA's standard 16-colour RGB values, 8 bits per channel. 0x00 / 0x55 / 0xAA / 0xFF are the
# only levels EGA uses, which is what makes a 2-bit-per-channel encoding exact rather than
# approximate -- there is no rounding decision hidden anywhere in this conversion.
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

# ★ RGB triples only -- the form comp_render.py wants for rendering.
EGA_RGB = [(r, g, b) for _n, r, g, b in EGA]

LEVEL = {0x00: 0, 0x55: 1, 0xAA: 2, 0xFF: 3}


def gime(r, g, b):
    """Pack three 2-bit levels as R1 G1 B1 R0 G0 B0 [SockmasterGime.md FFB0-FFBF]."""
    lr, lg, lb = LEVEL[r], LEVEL[g], LEVEL[b]
    return (((lr >> 1) & 1) << 5 | ((lg >> 1) & 1) << 4 | ((lb >> 1) & 1) << 3
            | (lr & 1) << 2 | (lg & 1) << 1 | (lb & 1))


def table(path=None):
    """The 16 GIME bytes, read from the assembly so a host tool cannot drift from the guest."""
    text = pathlib.Path(path or SOURCE).read_text(encoding="utf-8", errors="replace")
    if "agi_pal16:" not in text:
        raise SystemExit("agi_pal16 not found in %s" % (path or SOURCE))
    body = text.split("agi_pal16:", 1)[1]
    vals = []
    for line in body.splitlines()[1:]:
        m = re.match(r"\s*fcb\s+\$([0-9A-Fa-f]{2})", line)
        if not m:
            if vals:
                break
            continue
        vals.append(int(m.group(1), 16))
        if len(vals) == 16:
            break
    if len(vals) != 16:
        raise SystemExit("expected 16 entries in %s, got %d" % (path or SOURCE, len(vals)))
    return vals


def verify(path=None):
    """Does the shipped table equal EGA pushed through the documented encoding? Returns rows."""
    got = table(path)
    rows = []
    for i, (name, r, g, b) in enumerate(EGA):
        want = gime(r, g, b)
        rows.append((i, name, want, got[i], want == got[i]))
    return rows


def main():
    print("source: %s" % SOURCE)
    rows = verify()
    print("%-4s %-15s %-8s %-8s %s" % ("idx", "colour", "derived", "shipped", ""))
    for i, name, want, got, ok in rows:
        print("%-4d %-15s $%02X      $%02X      %s"
              % (i, name, want, got, "" if ok else "★★★ MISMATCH"))
    bad = [r for r in rows if not r[4]]
    print("-" * 52)
    if bad:
        print("★★★ %d entr(y/ies) disagree with the EGA derivation" % len(bad))
        return 1
    print("★ 16 of 16 agree with EGA pushed through R1G1B1R0G0B0.")
    print("★★ entry 6 brown = $%02X; the 'double the CGA bit' error would give $32 (dark yellow)"
          % gime(*EGA[6][1:]))   # ★ brown FROM the table, not retyped beside it
    return 0


if __name__ == "__main__":
    sys.exit(main())
