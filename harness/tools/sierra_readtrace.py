#!/usr/bin/env python3
"""harness/tools/sierra_readtrace.py -- T-P0-019 / AC-3..AC-6: read the gated fill trace.

Consumes MAME's live disassembly (`trace file,0,noloop`) captured by sierra_trace.lua while
Sierra's renderer was drawing a room, and reports:
  * the PC histogram, so the hot loop is found rather than guessed
  * the loop bodies, reconstructed as contiguous instruction ranges
  * ★★★ AC-6's cross-check: the store instructions in the trace must account for the
    ~26,000 on-screen writes and the 160-byte runs already measured. A traced routine that
    does not write cannot be the fill -- that is exactly how P3.9's reading was wrong.

★★ WHY THIS TRACE CAN BE TRUSTED WHERE P3.9's DUMP COULD NOT. MAME disassembles at execution
time through the live memory map, so there is no "which block was mapped" question. The
capture's own metadata records MMU 00 3E 3E 09 01 02 03 3F and screen start $76000 -- the
in-game map -- against P3.9's dumps which were a different session entirely.

★ §2P: the trace is read from the scratchpad and NEVER copied into the repo. This tool prints
aggregate structure -- addresses, opcode mnemonics, counts -- not Sierra's code.
"""
import argparse
import collections
import os
import re
import sys

LINE = re.compile(r"^([0-9A-Fa-f]{4}):\s+(\S+)\s*(.*)$")

# 6809 store mnemonics -- the instructions that can write memory
STORES = {"STA", "STB", "STD", "STX", "STY", "STU", "STS",
          "CLR", "INC", "DEC", "COM", "NEG", "ASL", "LSL", "ASR", "LSR", "ROL", "ROR",
          "PSHS", "PSHU", "TST"}
# ★ TST/PSH are included in the scan but flagged separately: TST reads, PSH writes the stack.
REAL_STORES = {"STA", "STB", "STD", "STX", "STY", "STU", "STS",
               "CLR", "INC", "DEC", "COM", "NEG", "ASL", "LSL", "ASR", "LSR", "ROL", "ROR"}


def load(path):
    out = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for ln in f:
            m = LINE.match(ln.rstrip("\n"))
            if m:
                out.append((int(m.group(1), 16), m.group(2).upper(), m.group(3).strip()))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tracefile")
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--window", type=int, default=40,
                    help="instructions of context to print around the hot PC")
    a = ap.parse_args()

    ins = load(a.tracefile)
    print(f"{a.tracefile}: {len(ins)} instructions traced")
    meta = os.path.join(os.path.dirname(a.tracefile), "fill.meta")
    if os.path.exists(meta):
        print("--- capture metadata ---")
        for ln in open(meta, encoding="utf-8"):
            print("   " + ln.rstrip())

    pcs = collections.Counter(i[0] for i in ins)
    print(f"\ndistinct PCs: {len(pcs)}")
    print(f"\n★ HOTTEST ADDRESSES\n{'PC':>8} {'count':>8} {'share':>7}  mnemonic")
    first = {}
    for pc, _, _ in ins:
        pass
    seen = {}
    for pc, mn, op in ins:
        seen.setdefault(pc, (mn, op))
    for pc, n in pcs.most_common(a.top):
        mn, op = seen[pc]
        print(f"  ${pc:04X} {n:>8} {100*n/len(ins):>6.1f}%  {mn} {op}")

    # ── AC-6: do the stores account for the measured writes? ────────────────────────────
    st = [i for i in ins if i[1] in REAL_STORES]
    print(f"\n★★★ AC-6 CROSS-CHECK -- stores in the trace")
    print(f"   store instructions executed : {len(st)}  ({100*len(st)/max(len(ins),1):.1f}% of the stream)")
    bym = collections.Counter(i[1] for i in st)
    for mn, n in bym.most_common(12):
        print(f"      {mn:<5} {n:>7}")
    bypc = collections.Counter(i[0] for i in st)
    print("   hottest STORE sites:")
    for pc, n in bypc.most_common(8):
        mn, op = seen[pc]
        print(f"      ${pc:04X} {n:>7}   {mn} {op}")

    # ── contiguous hot regions: where does the time actually go? ────────────────────────
    print("\n★ HOT REGIONS (contiguous PC ranges holding the bulk of the stream)")
    hot = sorted(pc for pc, n in pcs.items() if n >= max(2, len(ins) // 2000))
    regions, cur = [], None
    for pc in hot:
        if cur and pc - cur[1] <= 8:
            cur[1] = pc
        else:
            if cur:
                regions.append(cur)
            cur = [pc, pc]
    if cur:
        regions.append(cur)
    regions.sort(key=lambda r: -sum(pcs[p] for p in range(r[0], r[1] + 1)))
    for lo, hi in regions[:8]:
        n = sum(pcs[p] for p in range(lo, hi + 1))
        nst = sum(bypc[p] for p in range(lo, hi + 1))
        print(f"   ${lo:04X}-${hi:04X}  {hi-lo+1:>4} B  {n:>7} instr  {100*n/len(ins):>5.1f}%"
              f"   stores {nst}")

    # ── the hot loop body, in execution order, deduplicated ─────────────────────────────
    top_pc = pcs.most_common(1)[0][0]
    print(f"\n★★ LOOP BODY around the hottest PC ${top_pc:04X}")
    idx = next(i for i, v in enumerate(ins) if v[0] == top_pc)
    lo = max(0, idx - a.window // 2)
    body = []
    for pc, mn, op in ins[lo:lo + a.window]:
        body.append((pc, mn, op))
    for pc, mn, op in body:
        print(f"   ${pc:04X}  {mn:<6} {op:<18}  x{pcs[pc]}")


if __name__ == "__main__":
    main()
