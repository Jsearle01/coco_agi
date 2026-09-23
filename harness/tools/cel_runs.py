#!/usr/bin/env python3
"""Run-length census of VIEW cel data: key runs and opaque runs, separately. [T-P0-142 §4A]

★★★★★ WHY, AND WHAT IT DECIDES. The compositor tests transparency, reads screen priority and
writes two planes ONCE PER PIXEL. Every pixel inside one RLE run has the same colour, so the
transparency test and both writes are run-invariant -- but only if runs are long enough for the
per-run bookkeeping to be cheaper than the per-pixel work it replaces.

★★★★★ THE FORMAT BOUNDS ONE SIDE OF THIS AND NOT THE OTHER [view_cel.s:351-368]:
    cur == 0  -> colour = the cel's transparency key, length = THE REST OF THE ROW  (unbounded)
    cur != 0  -> colour = cur >> 4, length = cur & 15                               (<= 15)
So an opaque run is at most 15 pixels and a trailing key run can be a whole row.

★★★★ AND A RUN'S COLOUR MAY EQUAL THE KEY EVEN WHEN cur != 0, so "key run" is decided by the
colour, not by the encoding. Counting only cur==0 as transparent would undercount.

★★★ Reported separately because they buy different things: a key run is SKIPPED (no write at all)
and an opaque run is FILLED (one address, N stores). A census that merges them answers neither.

§2P: game files are opened read-only; prints counts only.

Usage:
    python harness/tools/cel_runs.py [titles ...] [--games DIR] [--view N] [--cels V,L,C ...]
"""
import argparse
import collections
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from volread import resource   # noqa: E402

PINNED = ["Kingquest1", "Kingquest2", "Kingquest3",
          "PoliceQuest1", "SpaceQuest-1", "larry1"]


def le16(b, i):
    return b[i] | (b[i + 1] << 8)


def cel_starts(payload):
    """-> [(loop, cel, offset)] for every cel in the VIEW."""
    if len(payload) < 5:
        return []
    out = []
    for lp in range(payload[2]):
        off = 5 + lp * 2
        if off + 1 >= len(payload):
            continue
        lo = le16(payload, off)
        if lo >= len(payload):
            continue
        for c in range(payload[lo]):
            co = lo + 1 + c * 2
            if co + 1 >= len(payload):
                continue
            out.append((lp, c, lo + le16(payload, co)))
    return out


def runs_of(payload, start):
    """Walk one cel's RLE exactly as vc_decode_row does. -> (w, h, key, [(len, is_key)])."""
    if start + 2 >= len(payload):
        return None
    w, h, t = payload[start], payload[start + 1], payload[start + 2]
    key = t & 0x0F
    if w == 0 or h == 0:
        return None
    i = start + 3
    out = []
    for _ in range(h):
        remw = w
        while remw > 0:
            if i >= len(payload):
                return (w, h, key, out)
            cur = payload[i]
            i += 1
            if cur == 0:
                # ★ the clear key for the REST of the row -- the unbounded case
                out.append((remw, True))
                remw = 0
            else:
                col, ln = cur >> 4, cur & 15
                if ln == 0:
                    continue          # a zero-length chunk writes nothing
                ln = min(ln, remw)
                out.append((ln, col == key))
                remw -= ln
    return (w, h, key, out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("titles", nargs="*", default=None)
    ap.add_argument("--games", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--cels", default=None,
                    help="restrict to specific cels: 'view,loop,cel;view,loop,cel'")
    a = ap.parse_args()

    want = None
    if a.cels:
        want = set()
        for part in a.cels.split(";"):
            v, l, c = (int(x) for x in part.split(","))
            want.add((v, l, c))

    keylen = collections.Counter()
    opqlen = collections.Counter()
    ncels = 0
    rows = 0
    for t in (a.titles or PINNED):
        d = pathlib.Path(a.games) / t
        if not d.is_dir():
            continue
        g = resource.load_from_files(d)
        for e in g.iter_present(resource.VIEW):
            try:
                payload = g.load(resource.VIEW, e.index)
            except Exception:
                continue
            for lp, c, st in cel_starts(payload):
                if want is not None and (e.index, lp, c) not in want:
                    continue
                r = runs_of(payload, st)
                if not r:
                    continue
                w, h, key, rr = r
                ncels += 1
                rows += h
                for ln, isk in rr:
                    (keylen if isk else opqlen)[ln] += 1

    kn, kp = sum(keylen.values()), sum(l * n for l, n in keylen.items())
    on, op = sum(opqlen.values()), sum(l * n for l, n in opqlen.items())
    tot = kp + op
    if not tot:
        print("no cels matched")
        return 1

    print(f"cels {ncels}   rows {rows}   pixels {tot}")
    print(f"  KEY    runs {kn:>7}  pixels {kp:>8} ({100*kp/tot:5.1f}%)  "
          f"mean run {kp/max(kn,1):5.2f}")
    print(f"  OPAQUE runs {on:>7}  pixels {op:>8} ({100*op/tot:5.1f}%)  "
          f"mean run {op/max(on,1):5.2f}")
    print(f"  runs per row: {(kn+on)/max(rows,1):.2f}")

    def share(cnt, total_px, lo):
        px = sum(l * n for l, n in cnt.items() if l >= lo)
        return 100 * px / max(total_px, 1)

    print()
    print("★ OPAQUE pixels by run length (the fill's denominator):")
    for lo in (1, 2, 4, 8):
        print(f"    in runs >= {lo:>2}: {share(opqlen, op, lo):5.1f}%")
    print("  histogram of OPAQUE run lengths:")
    for l in sorted(opqlen):
        n = opqlen[l]
        print(f"    len {l:>3}  runs {n:>7}  pixels {l*n:>8}  {'#' * min(50, l*n*50//max(op,1))}")
    print()
    print("★ KEY pixels by run length (the skip's denominator):")
    for lo in (1, 2, 4, 8, 16):
        print(f"    in runs >= {lo:>2}: {share(keylen, kp, lo):5.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
