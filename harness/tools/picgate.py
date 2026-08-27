#!/usr/bin/env python3
"""T-P0-012 AC-3: diff EVERY picture in the gated set against the pinned oracle.

★★★ PER-PICTURE PASS/FAIL, NEVER A TOTAL (L-10). "44 of 45 planes matched" is a number that
hides which one did not and how badly; a total can also be dominated by easy pictures. Every
row is printed with its own verdict, and the exit code is non-zero if ANY row fails.

★★ THE BASELINE IS THE ORACLE (§2O.1). tools/picrender/ is not imported here and must never
be -- both it and the CoCo3 renderer are clients of the same reference, so comparing them to
each other would let both be wrong the same way and report green forever.

★ The transform and its direction are unchanged from T-P0-011: the CoCo3's 4bpp buffer is
UNPACKED to indices and those are compared, rather than packing the oracle's, so a packing bug
cannot cancel a rendering bug. Nibble agreement is verified before either half is trusted.

★ AC-8: --expect-fail inverts the exit code, so an injected fault that IS caught reports
success. It also names WHICH picture diverged, because "the set failed" is not evidence that
the fault was caught at the expected place.
"""
import argparse
import collections
import hashlib
import io
import json
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

W, H = 160, 168
PLANE = W * H


def unpack_visual(packed):
    out = bytearray(PLANE)
    bad = []
    for i, b in enumerate(packed):
        hi, lo = (b >> 4) & 0x0F, b & 0x0F
        if hi != lo and len(bad) < 8:
            bad.append((i % W, i // W, hi, lo))
        out[i] = lo
    return bytes(out), bad


def first_diff(a, b):
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            return i
    return -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sweep_dir")
    ap.add_argument("picset_json")
    ap.add_argument("--expect-fail", action="store_true")
    args = ap.parse_args()

    sweep = pathlib.Path(args.sweep_dir)
    manifest = json.loads(pathlib.Path(args.picset_json).read_text(encoding="utf-8"))

    print("%-18s %5s %6s  %-38s %-38s %s"
          % ("picture", "fills", "bytes", "visual", "priority", "verdict"))
    print("-" * 128)

    npass = nfail = nmiss = 0
    failures = []
    for m in manifest:
        name = m["name"]
        fb = sweep / (name + ".fb.bin")
        pri = sweep / (name + ".pri.bin")
        ov = pathlib.Path(m["oracle"]) / ("pic%03d.visual.bin" % m["nr"])
        op = pathlib.Path(m["oracle"]) / ("pic%03d.priority.bin" % m["nr"])

        if not fb.exists() or not pri.exists():
            print("%-18s %5d %6d  %-38s %-38s ★ NO OUTPUT (probe halted or timed out)"
                  % (name, m["fills"], m["bytes"], "-", "-"))
            nmiss += 1
            failures.append((name, "no output"))
            continue

        vis, half = unpack_visual(fb.read_bytes())
        prib = pri.read_bytes()
        o_vis, o_pri = ov.read_bytes(), op.read_bytes()

        vok = vis == o_vis
        pok = prib == o_pri
        ok = vok and pok and not half

        def cell(mine, theirs, good):
            if good:
                return "identical %s" % hashlib.sha256(mine).hexdigest()[:16]
            d = sum(1 for x, y in zip(mine, theirs) if x != y)
            f = first_diff(mine, theirs)
            return "DIFFERS %d px, first (%d,%d)" % (d, f % W, f // W)

        verdict = "PASS" if ok else "★ FAIL"
        if half:
            verdict += " [half-pixel at (%d,%d)]" % (half[0][0], half[0][1])
        print("%-18s %5d %6d  %-38s %-38s %s"
              % (name, m["fills"], m["bytes"],
                 cell(vis, o_vis, vok), cell(prib, o_pri, pok), verdict))
        if ok:
            npass += 1
        else:
            nfail += 1
            failures.append((name, "visual" if not vok else "", "priority" if not pok else ""))

    print("-" * 128)
    print("per-picture: %d PASS, %d FAIL, %d with no output   (of %d)"
          % (npass, nfail, nmiss, len(manifest)))
    bygame = collections.Counter(m["name"].rsplit("-", 1)[0] for m in manifest)
    print("games covered: %d  (%s)" % (len(bygame),
          ", ".join("%s=%d" % kv for kv in sorted(bygame.items()))))
    if failures:
        print("★ FAILING PICTURES (named, not counted):")
        for f in failures:
            print("    %s" % (" ".join(x for x in f if x)))

    passed = (nfail == 0 and nmiss == 0)
    if args.expect_fail:
        print("★ --expect-fail: a FAIL here is the expected result.")
        return 0 if not passed else 1
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
