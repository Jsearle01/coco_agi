#!/usr/bin/env python3
"""harness/tools/res_gate.py -- AC-2: diff what the 6809 fetched against tools/volread/.

★★ THE COMPARISON IS BYTE-FOR-BYTE, RESOURCE BY RESOURCE. fetched.idx carries (type, index,
status, len, remaps) per handshake and fetched.bin carries the concatenated payloads; the
expected side is regenerated here from volread for exactly the requested list, in the requested
order. A total-length match is not the gate -- two resources can swap and still total the same.

★★★ §2O.1: THE BASELINE IS THE ORACLE-VERIFIED READER, NOT OUR OWN GUEST. res_stage.py hands the
guest RAW DIR BYTES and a RAW VOLUME SLICE; every parse the gate is about happens on the 6809.
If this script fed the guest parsed offsets, a shared misreading would pass forever.

★ §2P: reads game data, writes only counts and offsets. No resource bytes are printed or stored.
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from volread import resource  # noqa: E402

TYPES = ["LOGIC", "PICTURE", "VIEW", "SOUND"]
ERRS = {0: "ok", 1: "empty-slot", 2: "bad-signature", 3: "out-of-range", 4: "too-big"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("--sweep", default=str(ROOT / "build" / "res_sweep"))
    ap.add_argument("--expect-fail", default="",
                    help="AC-3: 'TYPE:INDEX' that MUST have failed; anything else passing is ok")
    a = ap.parse_args()

    sweep = pathlib.Path(a.sweep)
    game = resource.load_from_files(a.game_dir)
    blob = (sweep / "fetched.bin").read_bytes()

    rows = []
    with (sweep / "fetched.idx").open() as f:
        next(f)
        for line in f:
            f5 = [int(x) for x in line.strip().split(",")]
            rows.append(tuple(f5[:5]) + (f5[5] if len(f5) > 5 else 0,))

    pos = 0
    ok = bad = failed = 0
    per_type = {t: 0 for t in TYPES}
    mismatches = []
    remaps_total = 0
    cyc = []
    for t, i, st, ln, rm, cy in rows:
        rt = TYPES[t]
        if st != 0:
            failed += 1
            mismatches.append((rt, i, "status=%d (%s)" % (st, ERRS.get(st, "?"))))
            continue
        got = blob[pos:pos + ln]
        pos += ln
        want = game.load(rt, i)
        remaps_total += rm
        if cy:
            cyc.append((ln, rm, cy))
        if len(got) != len(want):
            bad += 1
            mismatches.append((rt, i, "length %d, oracle %d" % (len(got), len(want))))
        elif got != want:
            bad += 1
            d = next(k for k in range(len(got)) if got[k] != want[k])
            mismatches.append((rt, i, "%d bytes, first difference at +%d" % (len(got), d)))
        else:
            ok += 1
            per_type[rt] += 1

    print("sweep       : %s" % sweep)
    print("game        : %s" % a.game_dir)
    print("requests    : %d   fetched-bytes %d   consumed %d" % (len(rows), len(blob), pos))
    print("byte-identical vs tools/volread/ : %d" % ok)
    print("  per type  : %s" % per_type)
    print("mismatched  : %d      guest-reported failures: %d" % (bad, failed))
    print("MMU remaps  : %d over %d successful fetches (%.2f per fetch)"
          % (remaps_total, ok, remaps_total / ok if ok else 0))
    if cyc:
        # ★★ AC-7 IS TWO NUMBERS, NOT ONE: a fixed cost per fetch and a marginal cost per byte.
        # A single mean over a 24-to-10,428-byte spread would describe neither. The fit is over
        # the ZERO-REMAP fetches so the remap cost cannot leak into the slope; the remap cost is
        # then the residual on the fetches that did remap. [L-30: run counts stated]
        z = [(n, c) for n, r, c in cyc if r == 0]
        if len(z) > 1:
            mx = sum(n for n, _ in z) / len(z)
            my = sum(c for _, c in z) / len(z)
            sxx = sum((n - mx) ** 2 for n, _ in z)
            sxy = sum((n - mx) * (c - my) for n, c in z)
            slope = sxy / sxx if sxx else 0.0
            base = my - slope * mx
            print("AC-7 fetch cost (n=%d zero-remap fetches): %.1f cycles fixed + "
                  "%.3f cycles/byte" % (len(z), base, slope))
            for k in (1, 2, 3):
                g = [(n, c) for n, r, c in cyc if r == k]
                if g:
                    resid = sum(c - (base + slope * n) for n, c in g) / len(g)
                    print("     %d remap(s): n=%-4d mean excess over the zero-remap fit "
                          "%+.1f cycles (%.1f per remap)" % (k, len(g), resid, resid / k))
        allc = [c for _, _, c in cyc]
        allc.sort()
        print("     cycles per fetch: min %d, median %d, max %d over %d fetches"
              % (allc[0], allc[len(allc) // 2], allc[-1], len(allc)))

    if pos != len(blob):
        print("★★★ %d trailing bytes unaccounted for -- the index and the blob disagree"
              % (len(blob) - pos))
    for rt, i, why in mismatches[:20]:
        print("  ! %-7s %3d  %s" % (rt, i, why))
    if len(mismatches) > 20:
        print("  ... %d more" % (len(mismatches) - 20))

    if a.expect_fail:
        tname, idx = a.expect_fail.split(":")
        idx = int(idx)
        hit = [m for m in mismatches if m[0] == tname and m[1] == idx]
        others = [m for m in mismatches if not (m[0] == tname and m[1] == idx)]
        print("AC-3 : injected fault at %s %d -> %s" % (tname, idx, hit[0][2] if hit else "NOT DETECTED"))
        print("AC-3 : collateral failures elsewhere: %d" % len(others))
        return 0 if (hit and not others) else 1

    return 0 if (bad == 0 and failed == 0 and pos == len(blob)) else 1


if __name__ == "__main__":
    sys.exit(main())
