#!/usr/bin/env python3
"""harness/tools/pal_check.py -- AC-12 support: derive the 16 GIME values and diff the table.

★★★ THIS DOES NOT REPLACE THE EYE GATE. It answers the arithmetic half of the note's question:
"are these the values the documented bit layout implies for EGA's 16 colours?" An eye gate
answers "do they look right on a real display", and only Jay can run that. Both are needed --
this one is cheap, reproducible and citable, and it is the half that can be wrong silently.

★★ THE BIT LAYOUT IS NOW CITED, NOT ASSUMED [ref: docs/ground-truth/SockmasterGime.md,
"FFB0-FFBF Color palette registers"]:
        bit 5 = high order Red     bit 2 = low order Red
        bit 4 = high order Green   bit 1 = low order Green
        bit 3 = high order Blue    bit 0 = low order Blue
so each channel is a 2-bit level packed as (high<<k+3) | (low<<k). ★ That is R1 G1 B1 R0 G0 B0,
which is what CLAUDE.md §2.2's table asserts -- and it was Orchestrator arithmetic until now.

★★★ EGA's 16 colours are NOT full-intensity primaries. Blue is 0x0000AA, not 0x0000FF -- level
2 of 3, not 3 of 3. That single fact is what makes the table look wrong at a glance and right on
inspection, and it is why entry 6 (brown, 0xAA5500 -> R=2 G=1 B=0 -> $22) is the odd one out
rather than an error. A "double the CGA bit" conversion produces $32 there (dark yellow), which
is exactly the failure the note names.

★ §2.2: docs/ground-truth/ in THIS repo is empty (a .gitkeep only). The GIME reference is
present in both sibling trees, untracked -- §2S: absence in what is fetchable is not absence.
The citation above is executor-verifiable and orchestrator-unverifiable, per §2.2.
"""
import argparse
import io
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

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

LEVEL = {0x00: 0, 0x55: 1, 0xAA: 2, 0xFF: 3}


def gime(r, g, b):
    """Pack three 2-bit levels as R1 G1 B1 R0 G0 B0 [SockmasterGime.md FFB0-FFBF]."""
    lr, lg, lb = LEVEL[r], LEVEL[g], LEVEL[b]
    return (((lr >> 1) & 1) << 5 | ((lg >> 1) & 1) << 4 | ((lb >> 1) & 1) << 3
            | (lr & 1) << 2 | (lg & 1) << 1 | (lb & 1))


def table_from_source(path):
    """Read agi_pal16 out of the assembly, so the check cannot drift from the shipped table."""
    text = pathlib.Path(path).read_text(encoding="utf-8", errors="replace")
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
    return vals


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=str(ROOT / "src" / "harness" / "pic_probe.s"))
    ap.add_argument("--readback", default="",
                    help="AC-11: build/pal/readback.txt from pal_gate.lua")
    a = ap.parse_args()

    have = table_from_source(a.source)
    print("agi_pal16 read from %s" % a.source)
    print()
    print("  # name            EGA RGB      levels   derived  in table")
    bad = []
    for i, (name, r, g, b) in enumerate(EGA):
        want = gime(r, g, b)
        got = have[i] if i < len(have) else None
        mark = "" if got == want else "   ★★★ MISMATCH"
        if got != want:
            bad.append((i, name, want, got))
        print("  %2d %-14s #%02X%02X%02X   %d,%d,%d     $%02X      $%02X%s"
              % (i, name, r, g, b, LEVEL[r], LEVEL[g], LEVEL[b], want,
                 got if got is not None else 0xFF, mark))
    print()
    print("★ entry 6 (brown) derives as $%02X. A 'double the CGA bit' conversion would give $32"
          % gime(0xAA, 0x55, 0x00))
    print("  (dark yellow) -- the note's named failure mode. The table has $%02X." % have[6])
    print()
    print("desk check: %s"
          % ("all 16 entries match the documented bit layout" if not bad
             else "★★★ %d entries DIFFER -- the transcription is wrong" % len(bad)))
    print("★★ This proves the ARITHMETIC. It does not prove the display. AC-12's eye gate is")
    print("   the other half and is Jay's (CLAUDE.md §3, §4).")

    rb_bad = 0
    if a.readback:
        got = []
        for line in pathlib.Path(a.readback).read_text().splitlines():
            parts = line.split()
            if len(parts) == 2:
                got.append(int(parts[1], 16))
        print()
        print("AC-11 -- what the GIME registers actually hold after pal_load")
        print("  ★ read back from $FFB0-$FFBF BY THE GUEST, bits 7-6 masked")
        print("    [ref: SockmasterGime.md -- 'the upper 2 bits must be masked out']")
        print()
        print("   idx  table  register")
        for i in range(16):
            g = got[i] if i < len(got) else None
            mark = "" if g == have[i] else "   ★★★ MISMATCH"
            if g != have[i]:
                rb_bad += 1
            print("    %2d    $%02X     $%02X%s"
                  % (i, have[i], g if g is not None else 0xFF, mark))
        print()
        print("AC-11: %d of 16 registers hold the intended value" % (16 - rb_bad))
        print("★ This proves the values LANDED. It does NOT prove they are the right colours.")

    return 0 if not (bad or rb_bad) else 1


if __name__ == "__main__":
    sys.exit(main())
