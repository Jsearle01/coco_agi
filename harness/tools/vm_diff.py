#!/usr/bin/env python3
"""harness/tools/vm_diff.py -- AC-2: the per-cycle state diff, 6809 against tools/agivm.

★★★ 288 BYTES PER CYCLE: 32 packed flag bytes then 256 variables, in that order on both sides.
The exclusion set is EMPTY -- P4.1 removed the nondeterminism at source and that has to survive
the port, so nothing here is allowed to skip a byte.

★★ THE FIRST DIVERGENT CYCLE IS THE WHOLE VALUE OF THIS TOOL. A count of differing cycles says
how bad; the first cycle and the exact variable say WHERE, and that is what makes a divergence
bisectable against the reference instead of a mystery [L-36]. So the report leads with cycle,
then variable/flag number, then both values.

★ §2P: prints cycle numbers, variable numbers, flag numbers and byte values. No game data, no
text, no resource bytes.
"""
import argparse
import hashlib
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ROW = 288
NFLAGBYTES = 32


def rows(path):
    data = pathlib.Path(path).read_bytes()
    return [data[i:i + ROW] for i in range(0, len(data) - ROW + 1, ROW)], data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--oracle", required=True)
    ap.add_argument("--guest", required=True)
    ap.add_argument("--title", default="")
    ap.add_argument("--max-report", type=int, default=12)
    a = ap.parse_args()

    orc, orc_raw = rows(a.oracle)
    gst, gst_raw = rows(a.guest)
    n = min(len(orc), len(gst))

    print("title        : %s" % (a.title or "-"))
    print("oracle       : %d cycles  sha256 %s"
          % (len(orc), hashlib.sha256(orc_raw).hexdigest()[:16]))
    print("guest        : %d cycles  sha256 %s"
          % (len(gst), hashlib.sha256(gst_raw).hexdigest()[:16]))
    print("compared     : %d cycles x %d bytes, exclusion set EMPTY" % (n, ROW))

    first = None
    ndiff = 0
    varset, flagset = set(), set()
    reported = 0
    for c in range(n):
        o, g = orc[c], gst[c]
        if o == g:
            continue
        ndiff += 1
        if first is None:
            first = c
        details = []
        for k in range(NFLAGBYTES):
            if o[k] != g[k]:
                for b in range(8):
                    if (o[k] ^ g[k]) & (1 << b):
                        fl = k * 8 + b
                        flagset.add(fl)
                        details.append("flag %d oracle=%d guest=%d"
                                       % (fl, (o[k] >> b) & 1, (g[k] >> b) & 1))
        for k in range(NFLAGBYTES, ROW):
            if o[k] != g[k]:
                v = k - NFLAGBYTES
                varset.add(v)
                details.append("var %d oracle=%d guest=%d" % (v, o[k], g[k]))
        if reported < a.max_report:
            reported += 1
            print("  cycle %-4d %d difference(s): %s"
                  % (c, len(details), "; ".join(details[:6])
                     + (" ..." if len(details) > 6 else "")))

    print()
    print("divergent cycles : %d of %d" % (ndiff, n))
    if first is not None:
        print("first divergence : cycle %d" % first)
        print("vars involved    : %s" % sorted(varset))
        print("flags involved   : %s" % sorted(flagset))
    # ═══════════════════════════════════════════════════════════════════════════════════════
    # ★★★★★ A CYCLE-COUNT MISMATCH IS A DIVERGENCE IN EITHER DIRECTION [T-P0-061 AC-9].
    # The rule was `len(guest) >= len(oracle)`, so a guest that ran PAST the reference passed.
    # ★★★★ MEASURED: Kingquest3's parser arm gave oracle 508, guest 509 -- the probe's post-cycle
    # check tested vm_quit but not vm_restart, so it sampled one extra row -- and this printed
    # "AC-2 PASS -- byte-identical on every compared cycle". **The gate passed on an asymmetry
    # because of its own length rule**, while `min()` quietly hid the extra row from comparison.
    # ★★★ THE ASYMMETRIC RULE HAD A REASON AND IT WAS THE WRONG ONE: it was written so a guest
    # that halted EARLY would fail loudly, and "longer" was left permissive as the harmless
    # direction. It is not harmless -- it means the two legs disagree about when the run ends,
    # which is a state difference that happens to fall outside the compared window.
    # ★★ Both directions now fail, and each is named, because "the guest stopped early" and "the
    # guest kept going" have opposite causes and a single message would send the reading wrong.
    same_len = (len(orc) == len(gst))
    if not same_len:
        if len(gst) < len(orc):
            print("★★★ THE GUEST STOPPED EARLY: %d cycles against the oracle's %d -- it has"
                  % (len(gst), len(orc)))
            print("    halted; see cycles.txt for the opcode and the logic.")
        else:
            print("★★★ THE GUEST RAN PAST THE ORACLE: %d cycles against %d -- the reference"
                  % (len(gst), len(orc)))
            print("    ended the run and the guest did not. The extra cycle(s) are OUTSIDE the")
            print("    compared window, so byte-identity below says nothing about them.")
    print()
    print("AC-2 %s" % ("PASS -- byte-identical on every compared cycle" if (ndiff == 0 and same_len)
                       else "★★★ FAIL"))
    return 0 if (ndiff == 0 and same_len) else 1


if __name__ == "__main__":
    sys.exit(main())
