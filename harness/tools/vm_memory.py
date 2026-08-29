#!/usr/bin/env python3
"""harness/tools/vm_memory.py -- AC-9: what the VM costs in RAM, per module and per region.

★★ TWO DIFFERENT FOOTPRINTS, AND CONFLATING THEM WOULD OVERSTATE THE COST BY 25%. The probe
binary contains the HAL, the resource layer and the harness itself as well as the VM; only some
of that ships. The per-module table below is taken from lwasm's LISTING, which records the
address each included file starts at, so the split is measured rather than apportioned.

★ Regions come from the equates, not from a comment: a map that drifts from the source is worse
than no map, and this task already spent a session on a table that had grown into the code.

★ CLAUDE.md 2K: the verification target is 512 KB. These figures are what the VM occupies in the
first 64 KB of it; the design spec's block budget is a different question and is not answered
here.
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# ★ lwasm's listing puts the address in column 1 and the SOURCE FILE in parentheses, truncated
# from the left to a fixed width -- "(arness/vm_probe.s):00049". The truncation is why the key
# below is the parenthesised text as printed rather than a path: reconstructing the full name
# would be guessing, and the tail is unique across this build's includes.
INCLUDE = re.compile(r"^([0-9A-Fa-f]{4})\s+\S*\s*\(\s*([^)]+?)\s*\):(\d+)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listing", default="build/vm_probe.lst")
    ap.add_argument("--binary", default="build/vm_probe.bin")
    ap.add_argument("--load", type=lambda s: int(s, 16), default=0x0700)
    a = ap.parse_args()

    size = pathlib.Path(a.binary).stat().st_size
    print("image: %d bytes at $%04X, ends $%04X" % (size, a.load, a.load + size))
    print()

    # ── per-module, from the listing's include markers ──────────────────────────────────
    first, last = {}, {}
    order = []
    for line in pathlib.Path(a.listing).read_text(errors="replace").splitlines():
        m = INCLUDE.match(line)
        if not m:
            continue
        addr, path = int(m.group(1), 16), m.group(2)
        if path not in first:
            first[path] = addr
            order.append(path)
        last[path] = max(last.get(path, 0), addr)

    print("%-40s %6s %6s %8s" % ("module", "start", "end", "bytes"))
    print("-" * 64)
    total = 0
    for p in order:
        n = last[p] - first[p]
        total += n
        print("%-40s  $%04X  $%04X %8d" % (p, first[p], last[p], n))
    print("-" * 64)
    print("%-40s %20d  (sum of spans; interleaving makes this approximate)"
          % ("", total))
    print()

    # ── regions, read from the source equates ───────────────────────────────────────────
    src = {}
    for f in ("src/harness/vm_state.s", "src/harness/vm_probe.s", "src/harness/vm_core.s"):
        for line in (ROOT / f).read_text(errors="replace").splitlines():
            m = re.match(r"^(\w+)\s+equ\s+\$([0-9A-Fa-f]{4})\s*(?:;|$)", line)
            if m:
                src.setdefault(m.group(1), int(m.group(2), 16))

    def span(name, lo, hi, note=""):
        print("%-16s $%04X-$%04X %7d  %s" % (name, lo, hi, hi - lo, note))

    print("%-16s %-11s %7s  %s" % ("region", "range", "bytes", "note"))
    print("-" * 64)
    span("code", a.load, a.load + size, "VM + HAL + resource layer + harness")
    if "RES_DIRS" in src:
        span("RES_DIRS", src["RES_DIRS"], src["RES_DIRS"] + 0x1000, "four DIR tables")
    if "VM_VARS" in src and "VM_OBJ" in src:
        span("VM state", src["VM_VARS"], src["VM_OBJ"], "vars, flags, controllers, obj->room")
        span("VM_OBJ", src["VM_OBJ"], src["VM_OBJ"] + 255 * 32, "255 screen objects x 32")
    if "VM_TESTSEEN" in src:
        span("coverage", src["VM_TESTSEEN"], src["VM_TESTSEEN"] + 512,
             "★ HARNESS ONLY -- AC-5 counters, not shipped")
    if "vmtr_buf" in src:
        span("trace", src["vmtr_buf"], src["vmtr_buf"] + 384 * 4,
             "★ HARNESS ONLY, and only under -DVM_TRACE")
    if "RES_ARENA" in src and "RES_ARENA_END" in src:
        span("RES_ARENA", src["RES_ARENA"], src["RES_ARENA_END"],
             "residency arena; measured peak 12,816 B")
    print()
    if "RES_ARENA" in src:
        head = src["RES_ARENA_END"] - src["RES_ARENA"] - 12816
        print("arena headroom over the measured peak: %d bytes (%.1f%%)"
              % (head, 100.0 * head / 12816))
    return 0


if __name__ == "__main__":
    sys.exit(main())
