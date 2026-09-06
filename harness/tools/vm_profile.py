#!/usr/bin/env python3
"""harness/tools/vm_profile.py -- attribute sampled PCs to SYMBOL and MODULE [T-P0-047 AC-2].

★★★★ THE BUCKETS ARE vm_size.py's, DELIBERATELY. AC-5 asks whether the cycle decomposition
agrees with T-P0-044's SIZE decomposition, and that question is only answerable if both are
counted into the same bins. Ownership is recovered from source exactly as vm_size.py does it --
labels only, never `equ` constants, because a map cannot tell a location from a number and the
source can (vm_size.py's own note; addr_census.py made the mistake first).

★★★ ATTRIBUTION IS BY GREATEST SYMBOL <= PC, which charges unlabelled code to the preceding
label. That is the same approximation vm_size.py carries, and pairing it with the same
approximation on the other axis is what makes the two comparable. Per-MODULE figures are the
claim; per-symbol rows are a lead.

★★★★★ THE PROFILE IS NOT TRUSTED UNTIL IT REPRODUCES SOMETHING MEASURED WITHOUT IT.
--check-floor takes the pacing and instrumentation shares that ABLATION measured independently
(VM_PACEONLY, VM_NOCOUNT) and prints the sampler's own figure beside them. A sampler that cannot
reproduce a known share is reporting on something other than the run [L-81: a check that has
never rejected anything is indistinguishable from one that cannot].

usage:
  python harness/tools/vm_profile.py --samples build/vm_prof/kq1.txt \\
      --map build/vm_abl_baseline.map [--top 24] [--floor-pct 2.7] [--instr-pct 3.3]
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

# ★★★★★ EVERY MODULE THE PROBE LINKS, TAKEN FROM ITS OWN include LIST -- not the vm_*.s ones
# alone. The first version of this file listed only src/harness/vm_*.s, and the omission was not
# silent-but-harmless: attribution charges a PC to the greatest OWNED symbol at or below it, so
# ~500 bytes of unowned resource-layer code were charged BACKWARDS onto `vm_icguard` -- an
# `fcb 0` at $224C, a DATA byte, which duly appeared as 24.6% of Kingquest3's cycles.
# ★★★ The tell was that the top row was a data symbol, the same tell vm_size.py records for
# `equ` constants entering a size table. An unowned module does not vanish from a profile; it
# hides inside whatever label precedes it [L-56 -- the first measurement measures the
# scaffolding].
MODULES = [
    "src/harness/vm_probe.s", "src/harness/vm_tables.s", "src/harness/vm_state.s",
    "src/harness/vm_core.s", "src/harness/vm_cmds.s", "src/harness/vm_tests.s",
    "src/harness/vm_run.s", "src/harness/vm_objects.s", "src/harness/vm_cycle.s",
    "src/harness/res_core.s",
    "src/hal/coco3-dsk/hal_globals.s", "src/hal/coco3-dsk/sys.s",
    "src/hal/coco3-dsk/time.s", "src/hal/coco3-dsk/irq_vbl.s",
    "src/hal/coco3-dsk/gfx.s",
]


def load_owner(_src_dir, modules):
    """label -> module, from SOURCE. `equ` constants are excluded (vm_size.py's rule)."""
    owner = {}
    missing = []
    for rel in modules:
        p = ROOT / rel
        mod = pathlib.Path(rel).stem
        if not p.exists():
            missing.append(rel)
            continue
        txt = p.read_text(errors="replace")
        equs = set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s+equ\s", txt, re.M))
        for m in re.finditer(r"^([A-Za-z_][A-Za-z0-9_]*)[: ]", txt, re.M):
            if m.group(1) not in equs:
                owner.setdefault(m.group(1), mod)
    # ★ A module named here and absent from disk would silently reopen the same hole.
    for rel in missing:
        print("★★★ vm_profile: module not found, its code will mis-attribute: %s" % rel)
    return owner


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", required=True, help="file of 4-hex-digit PCs, one per line")
    ap.add_argument("--map", required=True)
    ap.add_argument("--src-dir", default="src/harness")
    ap.add_argument("--top", type=int, default=24)
    ap.add_argument("--floor-pct", type=float, default=None,
                    help="pacing share measured by VM_PACEONLY, for the sampler's own check")
    ap.add_argument("--instr-pct", type=float, default=None,
                    help="instrumentation share measured by VM_NOCOUNT, likewise")
    ap.add_argument("--pace-syms", default="vm_pace,vm_step_clock",
                    help="symbols making up the pacing path, for --floor-pct")
    a = ap.parse_args()

    owner = load_owner(a.src_dir, MODULES)

    syms = []
    for ln in (ROOT / a.map).open(errors="replace"):
        m = SYM.match(ln)
        if m:
            try:
                syms.append((int(m.group(2), 16), m.group(1)))
            except ValueError:
                pass
    # ★ Only labels the source owns are placement candidates; an `equ` at $1000 is a bitmask and
    # would otherwise swallow every PC above it.
    syms = sorted((addr, name) for addr, name in syms if name in owner)
    addrs = [s[0] for s in syms]

    import bisect
    per_sym = collections.Counter()
    per_mod = collections.Counter()
    total = below = 0
    for ln in (ROOT / a.samples).open(errors="replace"):
        ln = ln.strip()
        if not ln:
            continue
        try:
            pc = int(ln, 16)
        except ValueError:
            continue
        total += 1
        i = bisect.bisect_right(addrs, pc) - 1
        if i < 0:
            # ★ Below every VM label -- DECB, the ROM, or the probe's pre-entry. Counted, never
            # silently dropped: a large share here would mean the sampler is not watching the VM.
            below += 1
            continue
        name = syms[i][1]
        per_sym[name] += 1
        per_mod[owner[name]] += 1

    attributed = total - below
    if not total:
        print("★★★ no samples -- the run produced nothing to attribute")
        return 1

    print("samples: %d total, %d attributed to a VM symbol, %d below the VM's first label"
          % (total, attributed, below))
    print("         (%.1f%% attributed)" % (100.0 * attributed / total))
    print()
    print("PER MODULE -- this is the claim")
    print("%-16s %8s %9s" % ("module", "samples", "share"))
    print("-" * 36)
    for mod, n in per_mod.most_common():
        print("%-16s %8d %8.1f%%" % (mod, n, 100.0 * n / attributed))
    print("-" * 36)
    print("%-16s %8d %8.1f%%" % ("TOTAL", attributed, 100.0))
    print()
    print("PER SYMBOL -- a lead, not a measurement (symbol-delta attribution)")
    print("%-28s %-12s %8s %9s" % ("symbol", "module", "samples", "share"))
    print("-" * 60)
    for name, n in per_sym.most_common(a.top):
        print("%-28s %-12s %8d %8.1f%%" % (name, owner[name], n, 100.0 * n / attributed))

    # ─────────────────────────────────────────────────────────────────────────────
    # ★★★★★ THE SAMPLER'S OWN FALSIFICATION TEST.
    # ─────────────────────────────────────────────────────────────────────────────
    if a.floor_pct is not None:
        pace = [s.strip() for s in a.pace_syms.split(",") if s.strip()]
        got = sum(per_sym[s] for s in pace)
        got_pct = 100.0 * got / attributed
        print()
        print("CHECK -- pacing path, sampler vs ablation")
        print("  symbols          : %s" % ", ".join(pace))
        print("  sampler          : %.1f%%  (%d samples)" % (got_pct, got))
        print("  VM_PACEONLY      : %.1f%%" % a.floor_pct)
        d = abs(got_pct - a.floor_pct)
        print("  difference       : %.1f pp -- %s" % (
            d, "AGREES" if d <= 1.5 else "★★★ DISAGREES -- do not quote this profile"))
    if a.instr_pct is not None:
        print()
        print("CHECK -- instrumentation, ablation figure for reference: %.1f%% (VM_NOCOUNT)"
              % a.instr_pct)
        print("  ★ counters are inline throughout the interpreter, not a symbol of their own,")
        print("    so the sampler cannot bucket them; this is stated, not estimated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
