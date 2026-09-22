#!/usr/bin/env python3
"""state_pair.py -- first VM-state divergence between p3b and the reference, UNDER INPUT [T-P0-131].

★★★★ The vm gate compares 288 bytes a cycle with NO input, so nothing that only happens once the ego
moves has ever been compared. This pairs p3b's P3B_STATEDUMP (state_NNN.bin, taken at the park AFTER
cycle N) with ego_ref.py --dump (ref_NNN.bin, taken at the START of cycle N's body), i.e. port N
against reference N+1, and names every variable and flag that differs.

★★ Layout (both sides): 32 bytes of flags, then 256 variables. ★★★ Flag n is byte n>>3, mask
1<<(n&7) -- LSB FIRST, read from vm_setflag/vm_getflag [vm_state.s:347-382]. The first version
ASSUMED MSB-first, labelled the assumption, and named flags 56 and 194; no logic in KQ1 touches
either, which is what exposed it. The byte and mask are still printed. §2P: numbers only.

usage: python harness/tools/state_pair.py <p3b dir> <ref dir> <from> <to> [--offset 1]
"""
import argparse
import pathlib


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("ref")
    ap.add_argument("lo", type=int)
    ap.add_argument("hi", type=int)
    ap.add_argument("--offset", type=int, default=1)
    a = ap.parse_args()
    for n in range(a.lo, a.hi + 1):
        pf = pathlib.Path(a.port) / ("state_%03d.bin" % n)
        rf = pathlib.Path(a.ref) / ("ref_%03d.bin" % (n + a.offset))
        if not pf.exists() or not rf.exists():
            print("cycle %d: missing %s" % (n, pf if not pf.exists() else rf))
            continue
        p, r = pf.read_bytes(), rf.read_bytes()
        diffs = []
        for i in range(32):
            x = p[i] ^ r[i]
            for bit in range(8):
                m = 1 << bit
                if x & m:
                    diffs.append("flag %d (byte %d mask $%02X) port=%d ref=%d"
                                 % (i * 8 + bit, i, m, bool(p[i] & m), bool(r[i] & m)))
        for v in range(256):
            if p[32 + v] != r[32 + v]:
                diffs.append("var %d port=%d ref=%d" % (v, p[32 + v], r[32 + v]))
        print("port %d vs ref %d: %s" % (n, n + a.offset,
                                        "identical" if not diffs else "; ".join(diffs)))


if __name__ == "__main__":
    main()
