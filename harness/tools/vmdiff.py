#!/usr/bin/env python3
"""Per-cycle VM state diff: our VM against the PINNED oracle.

★★ THE BASELINE IS THE ORACLE, NEVER OUR OWN EARLIER OUTPUT (CLAUDE.md §2O.1). There is no
golden file in this tool and there must never be one: if the CoCo3 side were compared against
a stored copy of our own run, both could be wrong the same way and the suite would report green
forever. Precedent: a rule-derived validation that passed 109/109 while the rule was wrong.

Reports the FIRST DIVERGENT CYCLE and what diverged there, because that is the only cycle whose
divergence has a single cause -- everything after it is downstream.

Usage:
    python harness/tools/vmdiff.py <oracle-vmstate.txt> <ours-vmstate.txt> [--exclude-vars L]
    python harness/tools/vmdiff.py --self-test
"""
import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "tools"))
from agivm.trace import parse_line  # noqa: E402


def load(path):
    out = []
    for i, line in enumerate(pathlib.Path(path).read_text(encoding="ascii").splitlines()):
        if not line.strip():
            continue
        try:
            out.append(parse_line(line))
        except ValueError as exc:
            raise SystemExit("%s line %d: %s" % (path, i + 1, exc))
    return out


def compare(a, b, exclude_vars=()):
    """Return (first_divergent_index, detail) or (None, summary)."""
    ex = set(exclude_vars)
    n = min(len(a), len(b))
    for i in range(n):
        (ca, fa, va), (cb, fb, vb) = a[i], b[i]
        if ca != cb:
            return i, ["cycle numbering desynchronised: oracle %d vs ours %d" % (ca, cb)]
        detail = []
        for k in range(32):
            if fa[k] != fb[k]:
                bits = [k * 8 + j for j in range(8)
                        if ((fa[k] >> j) & 1) != ((fb[k] >> j) & 1)]
                detail.append("flag byte %d (flags %s): oracle %02x ours %02x"
                              % (k, bits, fa[k], fb[k]))
        for k in range(256):
            if k in ex:
                continue
            if va[k] != vb[k]:
                detail.append("var %d: oracle %d ours %d" % (k, va[k], vb[k]))
        if detail:
            return i, detail
    return None, ["%d cycles compared, no divergence "
                  "(oracle has %d, ours %d)" % (n, len(a), len(b))]


def self_test():
    """★ L-27: prove the instrument by breaking it. A differ that cannot report a difference
    is worse than no differ, because it reports success."""
    import io
    from agivm.trace import Trace

    ok = True
    buf = pathlib.Path("__vmdiff_selftest.txt")

    flags = bytes(range(32))
    vars0 = bytes((i * 7) & 0xFF for i in range(256))

    with Trace(str(buf)) as t:
        t.emit(0, bytearray(flags), bytearray(vars0))
    line = buf.read_text(encoding="ascii").strip()

    # 1. round-trip: our emitter -> the shared parser
    c, f, v = parse_line(line)
    if (c, f, v) != (0, flags, vars0):
        print("  FAIL round-trip"); ok = False
    else:
        print("  ok  emitter round-trips through the parser")

    # 2. the format matches the oracle patch's literal format string
    expect = "cycle %06u flags %s vars %s" % (0, flags.hex(), vars0.hex())
    if line != expect:
        print("  FAIL format: %r != %r" % (line[:60], expect[:60])); ok = False
    else:
        print("  ok  line format matches oracle patch 0002")

    # 3. an identical pair reports no divergence
    a = [(0, flags, vars0)]
    idx, _ = compare(a, list(a))
    if idx is not None:
        print("  FAIL identical pair reported divergent"); ok = False
    else:
        print("  ok  identical pair -> no divergence")

    # 4. ONE flipped var is caught (this is the check that matters)
    mutated = bytearray(vars0); mutated[137] ^= 0x01
    idx, detail = compare(a, [(0, flags, bytes(mutated))])
    if idx != 0 or not any("var 137" in d for d in detail):
        print("  FAIL single flipped var NOT caught: %s" % detail); ok = False
    else:
        print("  ok  single flipped var caught: %s" % detail[0])

    # 5. ONE flipped flag bit is caught
    mf = bytearray(flags); mf[9] ^= 0x04
    idx, detail = compare(a, [(0, bytes(mf), vars0)])
    if idx != 0 or not any("flag byte 9" in d for d in detail):
        print("  FAIL single flipped flag NOT caught: %s" % detail); ok = False
    else:
        print("  ok  single flipped flag caught: %s" % detail[0])

    # 6. an excluded var is NOT caught -- so exclusion genuinely narrows the gate, and the
    #    cost of adding one to the list is visible
    idx, _ = compare(a, [(0, flags, bytes(mutated))], exclude_vars={137})
    if idx is not None:
        print("  FAIL exclusion did not take effect"); ok = False
    else:
        print("  ok  excluding var 137 hides that same difference (exclusion has a cost)")

    # 7. a malformed line is refused rather than partially parsed
    for bad in ("cycle 0 flags 00 vars 00",
                "cycle 0 flags %s" % flags.hex(),
                "nonsense"):
        try:
            parse_line(bad)
            print("  FAIL malformed line accepted: %r" % bad); ok = False
        except ValueError:
            pass
    else:
        print("  ok  malformed lines refused, not partially parsed")

    buf.unlink()
    print()
    print("SELF-TEST %s" % ("PASSED" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("oracle", nargs="?")
    ap.add_argument("ours", nargs="?")
    ap.add_argument("--exclude-vars", default="",
                    help="comma-separated var numbers to ignore. ★ Every entry NARROWS the "
                         "gate; name why in the report or do not add it.")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.oracle or not args.ours:
        ap.error("need <oracle> and <ours>, or --self-test")

    ex = [int(x) for x in args.exclude_vars.split(",") if x.strip()]
    if ex:
        print("★ EXCLUDED VARS: %s -- the gate does not cover these" % ex)

    a, b = load(args.oracle), load(args.ours)
    print("oracle: %d cycles   ours: %d cycles" % (len(a), len(b)))
    idx, detail = compare(a, b, ex)
    print()
    if idx is None:
        print("NO DIVERGENCE. %s" % detail[0])
        return 0
    print("FIRST DIVERGENCE AT CYCLE %d (line %d)" % (a[idx][0], idx + 1))
    for d in detail[:20]:
        print("   %s" % d)
    if len(detail) > 20:
        print("   ... and %d more differences at this cycle" % (len(detail) - 20))
    return 1


if __name__ == "__main__":
    sys.exit(main())
