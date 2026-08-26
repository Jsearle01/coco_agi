#!/usr/bin/env python3
"""AC-6/AC-7: diff the CoCo3's rendered planes against the PINNED ORACLE.

★★★ THE BASELINE IS THE ORACLE, NEVER tools/picrender/. Both are clients of the same reference
(design §8.2, CLAUDE.md §2O.1). Comparing the CoCo3 output to our offline renderer would let
both be wrong in the same way and report green for ever. tools/picrender/ is not imported here
and must never be.

★★ THE TRANSFORM, STATED AND INVERTED IN THE DIRECTION THAT CAN FAIL.

  VISUAL. The oracle's plane is 160x168, one byte per pixel, values 0-15. The CoCo3's is mode 2
  4bpp, two screen pixels per byte, and AGI's 160 columns are doubled to the CoCo3's 320 -- so
  one AGI pixel is exactly one CoCo3 byte with the colour in BOTH nibbles.

  We UNPACK the CoCo3 buffer back to 160x168 indices and compare THOSE, rather than packing the
  oracle's and comparing packed bytes. The direction matters: packing the oracle would apply
  OUR transform to BOTH sides, so a bug in the packing would cancel itself and a wrong render
  could still diff clean. Unpacking applies it to one side only.

  ★ And the unpack VERIFIES the two nibbles agree before trusting either. A byte whose halves
  differ is not a colour index -- it means the renderer wrote a half-pixel, which is a real
  defect the naive `byte & 0x0F` would silently absorb.

  PRIORITY. 160x168 one byte per pixel on BOTH sides (design §3.3 keeps priority 160 wide, the
  lookup being x>>1). No transform, so no place for a transform error to hide.

Usage:
    picdiff.py <run-dir> <oracle-dir> <picture-nr> [--expect-fail]
"""
import argparse
import hashlib
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

W, H = 160, 168
PLANE = W * H


def unpack_visual(packed):
    """CoCo3 4bpp -> 160x168 colour indices. Returns (indices, half_pixel_errors)."""
    out = bytearray(PLANE)
    bad = []
    for i, b in enumerate(packed):
        hi, lo = (b >> 4) & 0x0F, b & 0x0F
        if hi != lo:
            if len(bad) < 8:
                bad.append((i % W, i // W, hi, lo))
        out[i] = lo
    return out, bad


def compare(name, ours, theirs):
    if len(ours) != len(theirs):
        print("  %-9s LENGTH MISMATCH ours %d, oracle %d" % (name, len(ours), len(theirs)))
        return False, None
    ho = hashlib.sha256(ours).hexdigest()
    ht = hashlib.sha256(theirs).hexdigest()
    if ours == theirs:
        print("  %-9s ★ BYTE-IDENTICAL   %d bytes   sha256 %s" % (name, len(ours), ho[:32]))
        return True, None
    diffs = [i for i in range(len(ours)) if ours[i] != theirs[i]]
    first = diffs[0]
    print("  %-9s ★ DIFFERS          %d of %d bytes (%.3f%%)"
          % (name, len(diffs), len(ours), 100.0 * len(diffs) / len(ours)))
    print("      ours   sha256 %s" % ho)
    print("      oracle sha256 %s" % ht)
    print("      first differing pixel: offset %d = (x=%d, y=%d)  ours %d, oracle %d"
          % (first, first % W, first // W, ours[first], theirs[first]))
    return False, first


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("oracle_dir")
    ap.add_argument("picture", type=int)
    ap.add_argument("--expect-fail", action="store_true",
                    help="AC-8: invert the exit code, so an injected fault that IS caught "
                         "reports success and one that is NOT caught fails the run")
    args = ap.parse_args()

    run = pathlib.Path(args.run_dir)
    ora = pathlib.Path(args.oracle_dir)

    fb = (run / "fb.bin").read_bytes()
    pri = (run / "pri.bin").read_bytes()
    o_vis = (ora / ("pic%03d.visual.bin" % args.picture)).read_bytes()
    o_pri = (ora / ("pic%03d.priority.bin" % args.picture)).read_bytes()

    print("picture %d" % args.picture)
    print("  CoCo3 framebuffer window : %d bytes (packed 4bpp)" % len(fb))
    print("  oracle visual / priority : %d / %d bytes" % (len(o_vis), len(o_pri)))
    print()

    vis, half = unpack_visual(fb)
    if half:
        print("  ★ HALF-PIXEL BYTES: %d+ bytes have differing nibbles -- the renderer wrote a"
              % len(half))
        print("    single CoCo3 pixel where it should have written a doubled AGI pixel.")
        for x, y, hi, lo in half:
            print("      (x=%d, y=%d) hi=%d lo=%d" % (x, y, hi, lo))
        print()
    else:
        print("  unpack: every byte's nibbles agree -- the doubling is intact")

    ok_v, _ = compare("VISUAL", bytes(vis), o_vis)
    ok_p, _ = compare("PRIORITY", pri, o_pri)

    print()
    passed = ok_v and ok_p and not half
    print("AC-6/AC-7: %s" % ("PASS" if passed else "FAIL"))

    if args.expect_fail:
        print("★ --expect-fail: a FAIL here is the expected result (the gate caught the fault).")
        return 0 if not passed else 1
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
