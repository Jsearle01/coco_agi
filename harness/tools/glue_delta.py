#!/usr/bin/env python3
"""harness/tools/glue_delta.py -- per-module consumption of the code region, by address delta.

★★★★★ THE CORRECT MEASURE, AND THE THIRD METHOD TRIED. Counting the listing's hex column
undercounts, because lwasm truncates it at 8 bytes and this build's tables are full of 16-operand
`fcb` rows -- 12,577 counted against 13,237 actually consumed. Spans between module starts break
on NESTED includes (pic_core.s wraps pic_draw.s and pic_fill.s, so its own code is split around
them and the span reads 145 instead of 588).

★★★★ Address delta has neither failure. Each addressed listing line consumes
`next_addressed_line.addr - this.addr`, which is exactly what the assembler advanced, whether the
line emitted bytes, emitted more than the column showed, or reserved space with `rmb`. Attribute
that to the file the line came from and nesting stops mattering: bytes go to whoever emitted
them, not to whoever contains them.

★ Reconciliation against P3_CODE_END is printed, and a mismatch is the tool's own failure rather
than a rounding note.

usage:  python harness/tools/glue_delta.py --list build/p3b.lst [--code-end 0x5300]
"""
import argparse
import collections
import io
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
LINE = re.compile(r"^([0-9A-Fa-f]{4})\s+(?:[0-9A-Fa-f]{2,})?\s*\(([^)]*)\):(\d+)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", required=True)
    ap.add_argument("--code-start", default="0x2000")
    ap.add_argument("--code-end", default="0x5300")
    a = ap.parse_args()
    lo, hi = int(a.code_start, 16), int(a.code_end, 16)

    rows = []
    for raw in open(a.list, errors="replace"):
        m = LINE.match(raw)
        if m:
            rows.append((int(m.group(1), 16), m.group(2).strip()))

    per = collections.Counter()
    peak = lo
    for i, (addr, f) in enumerate(rows):
        nxt = rows[i + 1][0] if i + 1 < len(rows) else addr
        # ★ Only forward motion inside the code region counts. A backward step is a new ORG
        # (the map's data regions), not a negative size.
        if lo <= addr < hi + 0x2000 and nxt > addr:
            per[f] += nxt - addr
            peak = max(peak, nxt)

    tot = sum(per.values())
    print(f"{'module':<34} {'bytes':>8} {'%':>7}")
    print("-" * 52)
    for f, n in per.most_common():
        print(f"{f:<34} {n:>8} {100.0*n/tot:>6.1f}%")
    print("-" * 52)
    print(f"{'TOTAL':<34} {tot:>8}")
    print()
    print(f"★ code region {a.code_start}-{a.code_end} = {hi-lo:,} B available")
    print(f"★ consumed {tot:,}  -> "
          f"{'OVER by ' + str(tot - (hi-lo)) if tot > hi-lo else 'fits, ' + str(hi-lo-tot) + ' spare'}")
    print(f"★ highest address reached: ${peak:04X}   (P3_CODE_END should equal this)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
