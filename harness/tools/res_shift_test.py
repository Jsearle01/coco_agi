#!/usr/bin/env python3
"""harness/tools/res_shift_test.py -- test ONE hypothesis about the cache's wrong bytes.

★★★★ THE HYPOTHESIS. res_cache_stash relocates a LOGIC's bytes from the scratch (src = res_top)
DOWN-arena to the cache (dest = res_ccur - len), and dest > src, so the two regions OVERLAP: the
cache destination sits on top of the scratch's upper part. If a consumer reads the resource from
the SCRATCH address instead of the post-stash res_base, it sees

    bytes [0, D)        untouched scratch          -> CORRECT
    bytes [D, len)      the copy's own output      -> the logic's bytes 0.. shifted by D

where D = dest - src. ★★★ The prediction is exact and falsifiable: **guest[D+k] == oracle[k]**,
and the first difference lands at exactly D. The measured first differences already equal D for
every LOGIC 0 (3289, 3350, 1860 against arenas of 8999, 8938, 10428 in a 12,288-byte arena based
at $3000 with the cache growing down from $6000).

★★ This distinguishes the hypothesis from "the backward copy is wrong". The copy loop reads
`lda ,-u` / `sta ,-y` and is correct for dest > src; a broken copy would not reproduce the source
bytes verbatim at a constant shift.

usage:  python harness/tools/res_shift_test.py --sweep build/res_sweep_evict --volume Kingquest1-v0
"""
import argparse
import io
import pathlib
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

ARENA_END = 0x6000
ARENA = 0x3000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sweep", required=True)
    ap.add_argument("--volume", required=True)
    ap.add_argument("--games", default="C:/Projects/agi-games/pc")
    a = ap.parse_args()

    from volread import resource  # noqa: E402

    game = re.sub(r"-v\d+$", "", a.volume)
    sweep = ROOT / a.sweep / a.volume
    blob = (sweep / "fetched.bin").read_bytes()
    g = resource.load_from_files(f"{a.games}/{game}")

    print(f"{'type':<8} {'idx':>5} {'len':>7} {'firstdiff':>10} {'D=dest-src':>11} "
          f"{'match?':>7}  shift-test")
    print("-" * 88)
    TYPES = resource.TYPES if hasattr(resource, "TYPES") else \
        ["LOGIC", "PICTURE", "VIEW", "SOUND"]
    off = 0
    checked = tested = confirmed = 0
    with (sweep / "fetched.idx").open() as f:
        next(f)                      # ★ header row: type,index,status,len,remaps,cycles
        rows = [[int(x) for x in ln.strip().split(",")] for ln in f if ln.strip()]
    for r in rows:
        t, idx, status, ln = r[0], r[1], r[2], r[3]
        rtype = TYPES[t]
        if status != 0:
            continue
        ours = blob[off:off + ln]
        off += ln
        want = g.load(rtype, idx)     # ★ same call res_gate.py makes -- one home for the oracle
        if ours == want:
            continue
        checked += 1
        fd = next((i for i in range(min(len(ours), len(want))) if ours[i] != want[i]), None)
        if fd is None:
            continue
        # ★ D as the model predicts it for a FIRST cached logic in an empty cache.
        D = (ARENA_END - ln) - ARENA
        # ★★ The real test does not assume D: recover the shift from the data, then check it
        # explains the WHOLE corrupted tail. A shift that only matches at one point is a
        # coincidence; one that matches thousands of bytes is the mechanism.
        shift = fd
        tail_ok = (shift > 0 and
                   ours[shift:ln] == want[0:ln - shift])
        tested += 1
        if tail_ok:
            confirmed += 1
        print(f"{rtype:<8} {idx:>5} {ln:>7} {fd:>10} {D:>11} {'yes' if fd == D else 'no':>7}  "
              f"{'★ tail==oracle[0:len-D] CONFIRMED' if tail_ok else 'tail does NOT match shift'}")

    print()
    print(f"mismatched: {checked}   shift-tested: {tested}   confirmed: {confirmed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
