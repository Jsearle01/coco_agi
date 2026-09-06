#!/usr/bin/env python3
"""harness/tools/plane_pair_diff.py -- diff BOTH planes against the oracle, encoding stated. [T-P0-054 AC-5]

★★★★★ WHY THIS EXISTS. Every p3b divergence figure in the record -- 71.5%, 28.8%, 23.9%, 20.7%,
20.6%, 14.8% -- was produced by a scratch script that read ONE file: the VISUAL plane. The priority
plane was dumped on every one of those runs and compared on none of them.

★★★★ AND THE PRIORITY PLANE IS WHAT THE STANDING HYPOTHESIS PREDICTS. P3b.17 §3.D named the windowed
priority walk as "the only path left" -- ungated because pic_probe forces PLANE_PRI_FLAT. **A
hypothesis about the priority walk that has never looked at the priority plane is not yet evidence.**

★★★ ENCODING IS PRINTED, NOT ASSUMED. Three wrong comparisons of one file pair in P3b.15 all came
from asserting an encoding instead of measuring it: a raw byte diff that ignored the guest's nibble
doubling and reported 97.6% on a PERFECT render; a histogram keyed by one type and read by another;
and a re-unpack of already-unpacked data that fabricated a defect. So this tool prints the value
histogram of both sides of both planes BEFORE any percentage, and the percentage is only meaningful
if the histograms agree on what the values mean.

★★ THE GUEST DOUBLES each pixel into both nibbles (visual 15 -> $FF, priority 4 -> $44); the oracle
writes the bare value ($0F, $04). Compare the VALUE, not the byte. A byte whose two nibbles disagree
is a real defect and is counted separately rather than folded into the total.

★ §2P: reads plane dumps and prints counts. No pixels interpreted, no game data written.

usage: python harness/tools/plane_pair_diff.py <guest-dir> <oracle-dir> <picNNN> [--rows]
"""
import argparse
import collections
import pathlib
import sys

W, H = 160, 168
N = W * H


def load(p):
    b = pathlib.Path(p).read_bytes()
    if len(b) != N:
        print("  !! %s is %d bytes, expected %d" % (p, len(b), N))
    return b


def hist(b, k=6):
    c = collections.Counter(b)
    tot = sum(c.values())
    top = c.most_common(k)
    return ", ".join("$%02X:%.1f%%" % (v, 100.0 * n / tot) for v, n in top)


def compare(name, guest, ref, show_rows, clear):
    print("  -- %s --" % name)
    print("     guest bytes : %s" % hist(guest))
    print("     oracle bytes: %s" % hist(ref))

    # ★★ Is the guest doubled? Measure it; do not assume it.
    unpaired = sum(1 for g in guest if (g >> 4) != (g & 0x0F))
    print("     guest bytes whose two nibbles DISAGREE: %d (%.2f%%)"
          % (unpaired, 100.0 * unpaired / len(guest)))
    ref_high = sum(1 for r in ref if (r >> 4) != 0)
    print("     oracle bytes with a non-zero HIGH nibble: %d" % ref_high)
    if ref_high:
        print("     !! oracle is not bare-valued; this comparison is not defined -- STOP")
        return None

    # ★★★★★ DECIDE THE GUEST'S ENCODING FROM THE DATA, PER PLANE, AND SAY WHICH WAS CHOSEN.
    # The two planes do NOT share an encoding: the guest's VISUAL dump is doubled ($FF for white-15)
    # and its PRIORITY dump comes back BARE ($04 for priority 4). Reading the priority plane as
    # doubled scores 99.2% divergence on any picture whatsoever -- an instrument artifact that looks
    # exactly like a catastrophic finding. This is the P3b.15 failure class and it is why the
    # encoding is measured here instead of carried over from the visual plane's convention.
    doubled = unpaired < len(guest) // 2
    if doubled:
        print("     -> guest is DOUBLED; comparing guest HIGH nibble against oracle low nibble")
        gval = lambda b: b >> 4                                          # noqa: E731
    else:
        print("     -> guest is BARE; comparing guest low nibble against oracle low nibble")
        gval = lambda b: b & 0x0F                                        # noqa: E731

    # ★★★★★ SPLIT THE DIVERGENCE BY KIND. "71.5% differ" cannot distinguish a fill that never ran
    # from a fill that ran and escaped, and those are opposite defects with opposite fixes.
    #   UNDER-FILL   guest still holds the CLEAR value where the oracle holds a painted one
    #                -- the fill did not reach here.
    #   WRONG-COLOUR guest is painted, oracle is painted, and they disagree
    #                -- the fill reached here and should not have, or carried the wrong value.
    #   OVER-FILL    guest is painted where the oracle left the clear value -- the fill escaped.
    diff_rows, total = [], 0
    under = wrong = over = 0
    for y in range(H):
        row_d = 0
        base = y * W
        for x in range(W):
            i = base + x
            gv, rv = gval(guest[i]), ref[i] & 0x0F
            if gv != rv:
                row_d += 1
                if gv == clear and rv != clear:
                    under += 1
                elif gv != clear and rv == clear:
                    over += 1
                else:
                    wrong += 1
        if row_d:
            diff_rows.append((y, row_d))
        total += row_d
    print("     DIFFERING: %d of %d (%.1f%%) over %d of %d rows"
          % (total, N, 100.0 * total / N, len(diff_rows), H))
    if total:
        print("     BY KIND (clear=%d): UNDER-FILL %d (%.1f%% of diff) | "
              "WRONG-COLOUR %d (%.1f%%) | OVER-FILL %d (%.1f%%)"
              % (clear, under, 100.0 * under / total, wrong, 100.0 * wrong / total,
                 over, 100.0 * over / total))
        # ★★★★ SPLIT AT THE PLANE'S 8 KB SLICE BOUNDARY. A defect that is an APERTURE OVERFLOW
        # -- an address computed flat, running past the end of the 8,192-byte window -- can only
        # damage rows at or beyond the boundary, and must leave everything before it intact. A
        # defect in the MAPPING damages rows on both sides. The two need different fixes, and the
        # row band is what tells them apart without guessing from source.
        # ★ Packed priority is 80 B/row, so byte 8192 is row 102.4; visual is 160 B/row, row 51.2.
        bnd = int(8192 // (W // 2)) if clear == 4 else int(8192 // W)
        before = sum(d for y, d in diff_rows if y < bnd)
        after = sum(d for y, d in diff_rows if y >= bnd)
        print("     SLICE BOUNDARY at row %d: %d differing BEFORE it, %d at/after"
              % (bnd, before, after))
    if show_rows and diff_rows:
        for y, d in diff_rows[:24]:
            print("        row %3d  %5d  %s" % (y, d, "#" * min(50, d * 50 // W)))
        if len(diff_rows) > 24:
            print("        ... %d more differing rows" % (len(diff_rows) - 24))
    return 100.0 * total / N


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("guest_dir")
    ap.add_argument("oracle_dir")
    ap.add_argument("pic")
    ap.add_argument("--rows", action="store_true")
    a = ap.parse_args()

    g = pathlib.Path(a.guest_dir)
    o = pathlib.Path(a.oracle_dir)
    print("=== %s : guest %s vs oracle %s ===" % (a.pic, g.name, o.name))

    # ★ AGI's defaults, and the two values p3_clear_planes writes: visual 15 (white), priority 4.
    vis = compare("VISUAL", load(g / "guest.visual.bin"),
                  load(o / ("%s.visual.bin" % a.pic)), a.rows, 15)
    pri = compare("PRIORITY", load(g / "guest.priority.bin"),
                  load(o / ("%s.priority.bin" % a.pic)), a.rows, 4)
    print("  SUMMARY %s: visual %.1f%%   priority %.1f%%" % (a.pic, vis, pri))
    return 0


if __name__ == "__main__":
    sys.exit(main())
