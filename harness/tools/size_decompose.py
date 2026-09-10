"""harness/tools/size_decompose.py -- where a probe's bytes actually go. [T-P0-084g §4A]

★★★★★ THE PROJECT HAS NEVER HAD ONE OF THESE, and four tasks have now argued about p3b_probe.s's
size without one. AD-97 is the precedent and the warning: four cuts were taken against a number
nobody had decomposed, and the decomposition -- when it was finally run -- found 927 bytes of table
padding sitting in plain sight.

★★★★ IT READS lwasm's LISTING, NOT THE MAP. A map gives symbol addresses, from which per-symbol
extents can only be INFERRED by subtracting neighbours -- and that inference is wrong wherever data
and code interleave or a symbol is an `equ`. The listing states, per source line, exactly which
bytes were emitted. **The difference matters: one is a measurement, the other is arithmetic on
addresses that happen to be adjacent.**

★★★ Restricted to a byte RANGE by default, because a probe's org'd tails (the parser at $E000, the
vocabulary window) are not competing for the region under pressure and would dominate the table.

usage:
    lwasm ... --list=build/x.lst --output=build/x.bin src/harness/p3b_probe.s
    python harness/tools/size_decompose.py build/x.lst [--lo 0x2000] [--hi 0x5300] [--top 15]
"""
import argparse
import collections
import re
import sys

# ADDR BYTES...  (file):line  text
LINE = re.compile(r"^([0-9A-F]{4}) ((?:[0-9A-F]{2})+)\s+\((.+?)\):(\d+)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("listing")
    ap.add_argument("--lo", type=lambda s: int(s, 0), default=0x2000)
    ap.add_argument("--hi", type=lambda s: int(s, 0), default=0x5300)
    ap.add_argument("--top", type=int, default=15)
    a = ap.parse_args()

    per_file = collections.Counter()
    per_line = []
    total = 0
    for raw in open(a.listing, encoding="utf-8", errors="replace"):
        m = LINE.match(raw)
        if not m:
            continue
        addr = int(m.group(1), 16)
        n = len(m.group(2)) // 2
        if not (a.lo <= addr < a.hi):
            continue
        per_file[m.group(3)] += n
        per_line.append((n, m.group(3), int(m.group(4)), raw.split("\n")[0][40:110].rstrip()))
        total += n

    print("decomposition of %s over $%04X-$%04X" % (a.listing, a.lo, a.hi))
    print("total emitted in range: %d bytes\n" % total)
    print("  bytes   share  source file")
    for f, n in per_file.most_common(a.top):
        print("  %6d  %5.1f%%  %s" % (n, 100.0 * n / total if total else 0, f))

    # ★★ The single fattest LINES as well as the fattest files: a 768-byte `fill` is one line and
    # a 900-byte routine is two hundred, and a reader looking for a cheap saving needs both views.
    print("\n  the 12 largest single source lines in range")
    per_line.sort(reverse=True)
    for n, f, ln, txt in per_line[:12]:
        print("  %6d  %s:%d  %s" % (n, f, ln, txt))
    return 0


if __name__ == "__main__":
    sys.exit(main())
