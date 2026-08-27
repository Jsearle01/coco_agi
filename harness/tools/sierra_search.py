#!/usr/bin/env python3
"""harness/tools/sierra_search.py -- T-P0-017 / AC-2: is there a SHADOW BUFFER?

Searches the 64 KB CPU-space dumps sierra_shadow.lua takes around each room change for a
pre-rendered, picture-shaped region outside the displayed framebuffer.

★★ THE SIGNATURES LOOKED FOR, all three stated so the negative is reviewable (AC-3):
  1. A region that CHANGES WHOLESALE between "disk ends" and "screen settled" -- the blit's
     DESTINATION.
  2. A region ~26,880 bytes that is ALREADY PRESENT at "disk ends" and is UNCHANGED at
     "settled" -- the blit's SOURCE, which a copy does not modify.
  3. Picture-shaped content: on this machine one AGI pixel is one byte whose two nibbles are
     EQUAL (160 logical pixels doubled to 320 screen pixels at 2 px/byte), so a rendered room
     is dominated by bytes of the form $00,$11,$22..$FF. ★★ That is a strong, cheap signature
     and it does not depend on knowing where anything lives.

★ Sizes are not guessed: VRES=$1E measured in T-P0-016 decodes to HRES=111 -> 160 bytes/row,
CRES=10 -> 16 colours at 2 px/byte, LPF=00 -> 192 lines [ref: GIME-RM §6 VRES]. So the screen
is 160x192 = 30,720 B and a rendered AGI room (160x168) is 26,880 B.

★★★ WHAT THIS CANNOT SEE, stated because a negative is only as good as its coverage:
the dump is the CPU's 64 KB view at the instant of the notifier, and OS-9 task-switches, so the
window may belong to a system task rather than the interpreter. Physical RAM outside the window
is unreachable from Lua on this driver (no :ram share/region; the GIME publishes no space).
"""
import argparse
import collections
import os
import re
import sys

BLOCK = 8192            # MMU slot granularity
PIC_BYTES = 26880       # 160 x 168, one byte per AGI pixel
SCREEN_BYTES = 30720    # 160 x 192


def load(path):
    with open(path, "rb") as f:
        return f.read()


def nibble_doubled_share(buf, lo, hi):
    """Fraction of bytes in [lo,hi) whose nibbles are equal -- the picture signature."""
    n = same = 0
    for b in buf[lo:hi]:
        n += 1
        if (b >> 4) == (b & 0xF):
            same += 1
    return same / max(n, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dumpdir")
    ap.add_argument("--granule", type=int, default=1024,
                    help="comparison granularity in bytes (default 1024)")
    ap.add_argument("--pic-threshold", type=float, default=0.60,
                    help="nibble-doubled share that counts as picture-shaped (default 0.60)")
    ap.add_argument("--sweep", action="store_true")
    a = ap.parse_args()

    files = sorted(os.listdir(a.dumpdir))
    rec = []
    for fn in files:
        m = re.match(r"(\d+)_(\w+)_f(\d+)\.bin$", fn)
        if m:
            rec.append((int(m.group(1)), m.group(2), int(m.group(3)),
                        os.path.join(a.dumpdir, fn)))
    rec.sort()
    kinds = collections.Counter(r[1] for r in rec)
    print(f"{a.dumpdir}: {len(rec)} dumps  {dict(kinds)}")
    print(f"granule {a.granule} B   picture threshold {a.pic_threshold:.0%} nibble-doubled")
    print(f"a rendered AGI room = {PIC_BYTES} B; the screen = {SCREEN_BYTES} B\n")

    # pair each 'post' with the 'diskend' immediately preceding it -- the blit would happen
    # between those two instants
    posts = [r for r in rec if r[1] == "post"]
    print(f"{'transition':>10} {'diskend f':>10} {'post f':>8} {'granules':>9} "
          f"{'CHANGED':>8} {'bytes':>9}")
    changed_map = collections.Counter()
    pairs = []
    for p in posts:
        prior = [r for r in rec if r[1] == "diskend" and r[0] < p[0]]
        if not prior:
            continue
        d = prior[-1]
        A, B = load(d[3]), load(p[3])
        n = min(len(A), len(B))
        ch = []
        for off in range(0, n, a.granule):
            if A[off:off + a.granule] != B[off:off + a.granule]:
                ch.append(off)
                changed_map[off] += 1
        pairs.append((d, p, A, B, ch))
        print(f"{p[2]:>10} {d[2]:>10} {p[2]:>8} {n // a.granule:>9} "
              f"{len(ch):>8} {len(ch) * a.granule:>9}")

    if not pairs:
        print("no diskend/post pairs found")
        return

    print("\n★★ WHICH ADDRESSES CHANGE between 'disk ends' and 'screen settled'?")
    print("   (a blit's DESTINATION would be a contiguous ~26,880 B region changing every time)")
    for off, cnt in sorted(changed_map.items()):
        if cnt >= max(1, len(pairs) // 2):
            print(f"   ${off:04X}-${off + a.granule - 1:04X}  changed in {cnt}/{len(pairs)}")
    tot = sum(1 for off, c in changed_map.items() if c >= max(1, len(pairs) // 2))
    print(f"   -> {tot} granules ({tot * a.granule} B) change in at least half the transitions")

    print("\n★★★ SIGNATURE 3 -- picture-shaped (nibble-doubled) regions, per dump:")
    print(f"{'dump':>26} {'region':>14} {'share':>7}")
    found_any = False
    for d, p, A, B, ch in pairs[:3]:
        for label, buf in (("diskend", A), ("post", B)):
            best = []
            for off in range(0, len(buf) - a.granule, a.granule):
                s = nibble_doubled_share(buf, off, off + a.granule)
                if s >= a.pic_threshold:
                    best.append((off, s))
            # collapse to contiguous spans
            spans = []
            for off, s in best:
                if spans and off == spans[-1][1]:
                    spans[-1][1] = off + a.granule
                    spans[-1][2].append(s)
                else:
                    spans.append([off, off + a.granule, [s]])
            for lo, hi, ss in spans:
                if hi - lo >= 4096:
                    found_any = True
                    print(f"{label + ' f' + str(d[2] if label == 'diskend' else p[2]):>26} "
                          f"${lo:04X}-${hi - 1:04X} {sum(ss) / len(ss):>6.0%}"
                          f"   {hi - lo} B")
    if not found_any:
        print("   (no contiguous region >= 4096 B reaches the threshold in any dump)")

    if a.sweep:
        print("\n★ L-46 -- sweep the picture threshold; does any region qualify at any cutoff?")
        d, p, A, B, ch = pairs[0]
        print(f"{'thr':>6} {'largest contiguous qualifying region (post dump)':>50}")
        for thr in (0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90):
            best = 0
            cur = 0
            for off in range(0, len(B) - a.granule, a.granule):
                if nibble_doubled_share(B, off, off + a.granule) >= thr:
                    cur += a.granule
                    best = max(best, cur)
                else:
                    cur = 0
            print(f"{thr:>6.0%} {best:>50}")
        print(f"  ★ a shadow buffer would show ~{PIC_BYTES} B here at a plausible threshold.")


if __name__ == "__main__":
    main()
