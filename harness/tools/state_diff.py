"""state_diff.py -- diff a sampled VM state block against the reference's, BY NAME. [T-P0-096]

★★★★★ SEVEN ARMS ASKED WHICH BUILD DIFFERENCE CORRELATES WITH A DIVERGENCE. This asks the other
question: **what did the interpreted logic actually read.** The reference and the port run the same
logic on the same inputs and decide differently, so something they read differs -- and the 288-byte
state block is where a variable or a flag would show it.

★★★★ THE SAME FORMAT vm_diff.py COMPARES: 32 packed flag bytes (LSB-first) then 256 variables
[vm_sweep.lua:714-716]. p3b_run.lua's P3B_STATEDUMP writes one such record per sampled cycle, read
from the port's own VM_FLAGS/VM_VARS -- no change to the port.

★★★★★ ALIGNMENT IS THE WHOLE DIFFICULTY AND IT IS NOT AN INDEX [T-P0-096 §1.2]. The reference jumps
at cycle 8 and the port at cycle 9 -- two hosts' arming seams, one park apart. **A diff that is one
cycle out shows every timer and counter as differing and buries the one byte that matters.** So
--offset is explicit, and --scan reports the difference count at several offsets so the right one is
CHOSEN ON EVIDENCE rather than assumed.

★ §2P: prints cycle numbers, variable numbers, flag numbers and byte values. No game data.

usage:
    python harness/tools/state_diff.py --oracle build/vm_stage/X/oracle.bin \\
        --port "build/p3b_headless/state_*.bin" --scan
    python harness/tools/state_diff.py --oracle ... --port ... --offset -1
"""
import argparse
import glob
import pathlib
import re
import sys

ROW = 288
NFLAG = 32


def oracle_records(path):
    b = pathlib.Path(path).read_bytes()
    if len(b) % ROW:
        print("★★★ %s is %d bytes, not a multiple of %d" % (path, len(b), ROW))
        sys.exit(2)
    return [b[i:i + ROW] for i in range(0, len(b), ROW)]


def port_samples(where):
    """-> {cycle: bytes}, keyed by the number in the filename.

    ★★★ A DIRECTORY, NOT A GLOB, AND THAT IS FORCED BY THE PLATFORM. This build of Python on
    Windows expands wildcards in argv itself, so `--port 'dir/state_*.bin'` arrives as eleven
    separate arguments and argparse rejects the last ten. Quoting does not help and neither does
    PowerShell's stop-parsing token, because the expansion is happening inside the interpreter.
    ★★ So the caller names the directory and the pattern lives here, where nothing can reinterpret
    it [the same reason p3b_run.lua's run list is built from the map rather than from a shell].
    """
    out = {}
    pattern = str(pathlib.Path(where) / "state_*.bin")
    for p in sorted(glob.glob(pattern)):
        m = re.search(r"(\d+)\.bin$", p)
        if not m:
            continue
        d = pathlib.Path(p).read_bytes()
        if len(d) != ROW:
            print("★★★ %s is %d bytes, expected %d" % (p, len(d), ROW))
            sys.exit(2)
        out[int(m.group(1))] = d
    return out


def differences(a, b):
    """-> ([(flag, av, bv)], [(var, av, bv)])"""
    flags, vars_ = [], []
    for k in range(NFLAG):
        if a[k] != b[k]:
            for bit in range(8):
                av, bv = (a[k] >> bit) & 1, (b[k] >> bit) & 1
                if av != bv:
                    flags.append((k * 8 + bit, av, bv))
    for k in range(NFLAG, ROW):
        if a[k] != b[k]:
            vars_.append((k - NFLAG, a[k], b[k]))
    return flags, vars_


def main():
    a_ = argparse.ArgumentParser()
    a_.add_argument("--oracle", required=True)
    a_.add_argument("--port", required=True,
                    help="DIRECTORY holding state_NNN.bin (not a glob -- see port_samples)")
    a_.add_argument("--offset", type=int, default=0,
                    help="oracle cycle = port cycle + offset")
    a_.add_argument("--scan", action="store_true",
                    help="report the difference count at offsets -3..+3 and stop")
    a = a_.parse_args()

    orc = oracle_records(a.oracle)
    prt = port_samples(a.port)
    if not prt:
        print("★★★ no port samples matched %s" % a.port)
        sys.exit(2)
    print("oracle   : %d cycles" % len(orc))
    print("port     : %d sample(s) at cycles %s" % (len(prt), sorted(prt)))

    # ★★★★★ THE ALIGNMENT IS CHOSEN ON EVIDENCE. The offset with the fewest differing bytes is the
    # one where the two sides are describing the same moment; a wrong offset lights up every timer.
    if a.scan:
        print("\noffset   total differing bytes over the sampled cycles   (lower = better aligned)")
        best, bestn = None, None
        for off in range(-3, 4):
            tot, used = 0, 0
            for c, rec in sorted(prt.items()):
                j = c + off
                if 0 <= j < len(orc):
                    tot += sum(1 for k in range(ROW) if rec[k] != orc[j][k])
                    used += 1
            if used:
                print("  %+d      %6d   (%d cycle(s) compared)" % (off, tot, used))
                if bestn is None or tot < bestn:
                    best, bestn = off, tot
        print("\n★ best alignment: offset %+d with %d differing byte(s)" % (best, bestn))
        return

    print("\nalignment: oracle cycle = port cycle %+d" % a.offset)
    anydiff = False
    for c, rec in sorted(prt.items()):
        j = c + a.offset
        if not (0 <= j < len(orc)):
            print("port c%-4d -> oracle c%-4d  OUT OF RANGE" % (c, j))
            continue
        flags, vars_ = differences(orc[j], rec)
        if not flags and not vars_:
            print("port c%-4d vs oracle c%-4d : ★ identical, all 288 bytes" % (c, j))
            continue
        anydiff = True
        print("port c%-4d vs oracle c%-4d : ★★★ %d flag(s), %d var(s)"
              % (c, j, len(flags), len(vars_)))
        for f, ov, pv in flags:
            print("      flag %-3d  oracle=%d  port=%d" % (f, ov, pv))
        for v, ov, pv in vars_:
            print("      var  %-3d  oracle=%-3d port=%-3d" % (v, ov, pv))
    if not anydiff:
        print("\n★★★★ NOTHING IN THE STATE BLOCK DIFFERS over the sampled cycles. The divergence is "
              "OUTSIDE these 288 bytes -- the object table, the resource state or the logic's own "
              "bytes.")


if __name__ == "__main__":
    main()
