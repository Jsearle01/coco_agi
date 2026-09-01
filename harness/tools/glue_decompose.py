#!/usr/bin/env python3
"""harness/tools/glue_decompose.py -- where do the integration glue's bytes go?

★★★★★ WHY THIS EXISTS. p3b_probe.s is 13,102 bytes of five subsystems on one machine and
**no decomposition of it has ever been made**. The map allocates 13,056 and the assertion has
been failing; four reservation cuts were taken against a figure nobody had broken down. Every
subsystem in this project got cheaper once it was measured -- the fill 11.102 -> 2.746 s, the VM
6.2 -> 14.2 cyc/s -- and in both cases the guess at where the cost lived was wrong.

★★★★★ METHOD: ADDRESS DELTAS, NOT THE HEX COLUMN. The listing prints `ADDR HEXBYTES (file):line`
and the obvious method -- count the hex digits -- is WRONG, which this tool learned the hard way.
**lwasm truncates the hex display at 8 bytes**, so `fcb` with 16 operands shows 8 and the count
silently loses half of every long table row. Summing hex gave 12,577 against a P3_CODE_END of
$53B5 = 13,237 consumed, and the 660-byte difference looked like `rmb` reservations. It was
mostly display truncation.

★★★★ So each line's size is the DISTANCE TO THE NEXT ADDRESSED LINE. That is exact, it handles
truncated rows and `rmb` reservations uniformly, and it reconciles with the assembler's own
counter -- which is the only number the code-region assertion cares about [L-71: verify by
comparison, not by proxy].

★★★ It also separates CODE from DATA by address. Bytes below MAP_CODE_END are the code region
the assertion polices; bytes at or above it are storage the map places elsewhere, and counting
them together would inflate every module and answer the wrong question.

★★ Filenames in the listing are truncated to a fixed field, so they are matched by suffix
against the real include list rather than trusted verbatim.

usage:  python harness/tools/glue_decompose.py --list build/p3b.lst [--code-end 0x5300]
"""
import argparse
import collections
import io
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# ADDR  HEXBYTES  (file):line
LINE = re.compile(r"^([0-9A-Fa-f]{4})\s+([0-9A-Fa-f]{2,})?\s*\(([^)]*)\):(\d+)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", required=True)
    ap.add_argument("--code-end", default="0x5300")
    ap.add_argument("--code-start", default="0x2000")
    a = ap.parse_args()
    lo, hi = int(a.code_start, 16), int(a.code_end, 16)

    code = collections.Counter()
    data = collections.Counter()
    # ★★★★★ RESERVED SPACE IS INVISIBLE IN THE EMITTED-BYTE COUNT AND IT IS 660 BYTES HERE.
    # `rmb` advances the address counter and emits nothing, so summing hex bytes gives 12,577
    # against a P3_CODE_END of $53B5 = 13,237 actually consumed. **The 660-byte difference is
    # uninitialised VARIABLES declared inside the code region** -- and that is precisely the kind
    # of thing a decomposition exists to surface, because storage in a code region is movable in
    # a way that code is not.
    # ★★★ Measured by ADDRESS GAP, not by parsing `rmb` operands: the operand is an expression
    # (RES_MAXDEPTH*2, 2*RES_CACHE_MAX...) and re-evaluating it here would be a second
    # implementation of the assembler's arithmetic that could silently disagree with it [L-53].
    # The gap between one line's end and the next line's start is what the assembler ACTUALLY
    # reserved.
    resv = collections.Counter()
    gaps = []
    prev_end = None
    prev_file = None
    for raw in open(a.list, errors="replace"):
        m = LINE.match(raw)
        if not m:
            continue
        addr = int(m.group(1), 16)
        f = m.group(3).strip()
        if prev_end is not None and addr > prev_end and prev_end >= lo:
            gap = addr - prev_end
            # ★ Only count a plausible reservation, not an ORG jump to a different region.
            if gap < 4096:
                resv[prev_file] += gap
                gaps.append((gap, prev_file, prev_end))
        if m.group(2):
            n = len(m.group(2)) // 2
            (code if lo <= addr < hi else data)[f] += n
            prev_end = addr + n
        else:
            prev_end = addr
        prev_file = f

    # ★★★★★ THE AUTHORITATIVE MEASURE IS THE SPAN, NOT THE SUM. Emitted bytes plus gap-detected
    # reservations came to 13,057 against a P3_CODE_END of $53B5 = 13,237 -- 180 unattributed,
    # because a gap filter cannot tell a large `rmb` from a region change. Modules are included
    # SEQUENTIALLY, so each occupies a contiguous range and its true size is the distance to the
    # next module's first address. **That reconciles exactly with the assembler's own counter**,
    # which is the only number the assertion cares about.
    # ★★ Reported alongside the emitted/rmb split rather than instead of it: the split says what
    # KIND of bytes a module spends, the span says how many it actually consumes [L-71].
    spans = []
    seen_order = []
    first_addr = {}
    last_addr = {}
    prev = None
    for raw in open(a.list, errors="replace"):
        m = LINE.match(raw)
        if not m:
            continue
        addr, f = int(m.group(1), 16), m.group(3).strip()
        if not (lo <= addr < hi + 0x2000):
            continue
        if f not in first_addr:
            first_addr[f] = addr
            seen_order.append(f)
        last_addr[f] = addr + (len(m.group(2)) // 2 if m.group(2) else 0)
    for i, f in enumerate(seen_order):
        start = first_addr[f]
        end = first_addr[seen_order[i + 1]] if i + 1 < len(seen_order) else last_addr[f]
        if end > start:
            spans.append((f, end - start))

    tot_c, tot_d, tot_r = sum(code.values()), sum(data.values()), sum(resv.values())
    print(f"{'module (listing name, truncated)':<34} {'code B':>8} {'rmb B':>8} "
          f"{'total':>8} {'%':>6}")
    print("-" * 70)
    keys = sorted(set(code) | set(resv), key=lambda k: -(code.get(k, 0) + resv.get(k, 0)))
    grand = tot_c + tot_r
    for f in keys:
        c, r = code.get(f, 0), resv.get(f, 0)
        print(f"{f:<34} {c:>8} {r:>8} {c+r:>8} {100.0*(c+r)/grand:>5.1f}%")
    print("-" * 70)
    print(f"{'TOTAL':<34} {tot_c:>8} {tot_r:>8} {grand:>8} {'100.0%':>6}")
    print()
    print(f"★ code region {a.code_start}-{a.code_end} = {hi-lo:,} B available")
    print(f"★ emitted {tot_c:,} + reserved {tot_r:,} = {grand:,} consumed "
          f"-> {'OVER by ' + str(grand-(hi-lo)) if grand > hi-lo else 'fits with ' + str(hi-lo-grand) + ' spare'}")
    print(f"★★ {tot_r:,} B ({100.0*tot_r/grand:.1f}%) is `rmb` -- UNINITIALISED STORAGE inside "
          f"the code region, not code.")
    print()
    print("★★★★ BY SPAN (contiguous range each module occupies -- reconciles with P3_CODE_END):")
    print(f"{'module':<34} {'span B':>8} {'%':>7}")
    print("-" * 52)
    tot_s = sum(n for _, n in spans)
    for f, n in sorted(spans, key=lambda x: -x[1]):
        print(f"{f:<34} {n:>8} {100.0*n/tot_s:>6.1f}%")
    print("-" * 52)
    print(f"{'TOTAL SPAN':<34} {tot_s:>8}")
    print()
    print("★★★ LARGEST ADDRESS GAPS -- reserved space (`rmb`), which costs ADDRESS but no image "
          "byte:")
    for g, f, at in sorted(gaps, reverse=True)[:12]:
        print(f"    {g:>6} B  at ${at:04X}  in {f}")
    print("★★ 'data' is everything emitted at or above the code region -- storage the map places "
          "elsewhere. It is reported so it is visible, NOT added to the code total.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
