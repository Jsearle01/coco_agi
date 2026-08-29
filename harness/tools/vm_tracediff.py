#!/usr/bin/env python3
"""harness/tools/vm_tracediff.py -- find the FIRST instruction where the 6809 and the reference part.

★★ PARSED, NOT TEXTUAL. The two traces are produced by different toolchains (Lua's string.format
and Python's %), so a `diff` compares padding as well as content and reports every line as
changed. Parsing both to (ip, opcode, kind) tuples compares what the traces MEAN.

★★★ THE FIRST DIVERGENT STEP IS THE WHOLE OUTPUT. A state difference observed at cycle 1 can
originate hundreds of instructions earlier; the first differing instruction is where the defect
actually is [L-36].

★ Context either side is printed, because an instruction is only interpretable next to the ones
that set up its operands.
"""
import argparse
import io
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KIND = {0: "loop", 1: "eval", 2: "expr-end"}


def load(p):
    out = []
    for line in pathlib.Path(p).read_text(errors="replace").splitlines():
        f = line.split()
        if len(f) == 3:
            out.append((int(f[0]), int(f[1], 16), int(f[2])))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("reference")
    ap.add_argument("guest")
    ap.add_argument("--context", type=int, default=6)
    # ★★ THE GUEST TRACE IS A WINDOW, NOT A PREFIX. Only 384 entries fit in host-readable RAM
    # and logic 0 is 719 steps per cycle, so the guest records steps [from, from+384) and the
    # reference has to be sliced to match. Comparing an unsliced reference against a windowed
    # guest reports a divergence at step 0 every time, which is a property of the alignment and
    # not of the VM.
    ap.add_argument("--skip", type=int, default=0,
                    help="drop this many reference steps -- must equal VM_TRACEFROM")
    a = ap.parse_args()

    r, g = load(a.reference)[a.skip:], load(a.guest)
    print("reference: %d steps (after --skip %d)    guest: %d steps"
          % (len(r), a.skip, len(g)))

    n = min(len(r), len(g))
    first = None
    for i in range(n):
        if r[i] != g[i]:
            first = i
            break
    if first is None:
        if len(r) == len(g):
            print("\n★ IDENTICAL -- every step matches, same length")
            return 0
        first = n
        print("\n★★ Common prefix of %d steps is identical; the traces differ only in LENGTH." % n)

    print("\nfirst divergence at step %d\n" % first)
    lo = max(0, first - a.context)
    hi = min(max(len(r), len(g)), first + a.context + 1)
    print("  %-6s | %-22s | %-22s" % ("step", "reference", "guest (6809)"))
    print("  %s" % ("-" * 56))
    for i in range(lo, hi):
        rs = ("ip=%-5d op=%02X %-8s" % (r[i][0], r[i][1], KIND.get(r[i][2], "?"))
              if i < len(r) else "-")
        gs = ("ip=%-5d op=%02X %-8s" % (g[i][0], g[i][1], KIND.get(g[i][2], "?"))
              if i < len(g) else "-")
        mark = "  <<<" if i == first else ""
        print("  %-6d | %-22s | %-22s%s" % (i + a.skip, rs, gs, mark))
    return 1


if __name__ == "__main__":
    sys.exit(main())
