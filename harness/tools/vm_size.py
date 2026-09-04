#!/usr/bin/env python3
"""harness/tools/vm_size.py -- the VM's bytes, per module and per symbol [AC-2].

★★★★ FINER THAN glue_delta.py, AND WITH A LIMIT WORTH STATING. glue_delta attributes every
listing line to the file that emitted it, which is exact. This goes one level down by SYMBOL
DELTA: each label's extent is the distance to the next label at a higher address.

★★★ THAT IS NOT EXACT AND THE DIFFERENCE MATTERS. Code between two labels is charged wholly to
the first, so an unlabelled block inflates whatever precedes it, and a `fcb`/`rmb` run with no
label of its own disappears into its predecessor. **Per-module totals from glue_delta are the
authority; these per-symbol figures are a lead, not a measurement** -- which is exactly the
distinction T-P0-042 got wrong twice before address deltas reconciled [L-41: a ratio is not a
cost].

★★ The reconciliation is printed: per-symbol totals must sum to the module's own span, and a
mismatch is this tool's error rather than a rounding note.

usage:  python harness/tools/vm_size.py --map build/p3b/p3b.map --modules vm_cmds,vm_run,...
"""
import argparse
import collections
import io
import pathlib
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]
SYM = re.compile(r"^Symbol: (\S+) \([^)]*\) = ([0-9A-Fa-f]+)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", required=True)
    ap.add_argument("--src-dir", default="src/harness")
    ap.add_argument("--modules", default="")
    ap.add_argument("--top", type=int, default=20)
    a = ap.parse_args()

    syms = []
    for ln in (ROOT / a.map).open(errors="replace"):
        m = SYM.match(ln)
        if m:
            try:
                syms.append((int(m.group(2), 16), m.group(1)))
            except ValueError:
                pass
    syms.sort()

    # ★ Which module defines each label -- the map does not say, so it is recovered from source.
    owner = {}
    mods = [m.strip() for m in a.modules.split(",") if m.strip()]
    for mod in mods:
        p = ROOT / a.src_dir / (mod + ".s")
        if not p.exists():
            continue
        # ★★★★★ LABELS ONLY -- NEVER `equ` CONSTANTS. The first version took every symbol the map
        # exported, so bitmasks entered the size table as addresses: fDontUpdate "2048 bytes" at
        # $1000 is the flag VALUE $1000 differenced against the next constant, and VM_FLAGS,
        # SCRIPT_HEIGHT and the whole fXxx family came with it. **The four largest entries were
        # all constants and none of them occupies a byte.**
        # ★★★ This is L-56 exactly, and the project has hit it before: addr_census.py counted
        # bitmasks as addresses and was corrected the same way. A symbol table does not
        # distinguish a location from a number; the SOURCE does, and an `equ` is the tell.
        txt = p.read_text(errors="replace")
        equs = set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s+equ\s", txt, re.M))
        for m in re.finditer(r"^([A-Za-z_][A-Za-z0-9_]*)[: ]", txt, re.M):
            if m.group(1) not in equs:
                owner.setdefault(m.group(1), mod)

    per_mod = collections.Counter()
    rows = []
    for i, (addr, name) in enumerate(syms):
        if name not in owner:
            continue
        nxt = syms[i + 1][0] if i + 1 < len(syms) else addr
        size = nxt - addr
        # ★ A negative or absurd delta means the next symbol is in a different region (data vs
        # code); charge nothing rather than a wild number.
        if 0 < size < 4096:
            rows.append((size, name, owner[name], addr))
            per_mod[owner[name]] += size

    rows.sort(reverse=True)
    print(f"{'symbol':<26} {'module':<14} {'addr':>6} {'bytes':>7}")
    print("-" * 58)
    for size, name, mod, addr in rows[:a.top]:
        print(f"{name:<26} {mod:<14} ${addr:04X} {size:>7}")
    print("-" * 58)
    tot = sum(r[0] for r in rows)
    print(f"{'TOTAL (symbol-attributed)':<41} {tot:>7}")
    print()
    print("per module, symbol-attributed:")
    for mod, n in per_mod.most_common():
        print(f"   {mod:<16} {n:>7}")
    print()
    print("★★ Per-symbol figures are symbol-DELTA and charge unlabelled code to the preceding")
    print("   label. glue_delta.py's per-module spans are the authority; compare before quoting.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
