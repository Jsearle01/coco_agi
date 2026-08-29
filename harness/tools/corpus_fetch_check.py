#!/usr/bin/env python3
"""harness/tools/corpus_fetch_check.py -- AC-8: the new titles fetch correctly.

★★★ THE SECOND PARSE IS INDEPENDENT, OR THE CHECK IS WORTHLESS. This does NOT call
volread.load() twice. It reads the DIR entry and the volume record BY HAND from the raw bytes --
volume nibble, 20-bit big-endian offset, 0x1234 big-endian signature, little-endian length at
+3 -- and compares that slice against what volread returns. §2O.1: comparing a reader to itself
reports green forever.

★★ The hand parse is written from the FORMAT, not from volread's code, for the same reason. If
both were derived from the same source a shared misreading would agree.

★ v3 titles are NOT fetched: their records are LZW-compressed and §11.1 is re-closed. They are
listed as skipped rather than silently omitted [L-22].

★ §2P: reads game data; prints counts, offsets and lengths. No resource bytes.
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
DIRFILES = {"LOGIC": "logdir", "PICTURE": "picdir", "VIEW": "viewdir", "SOUND": "snddir"}


def find_ci(d, name):
    for p in d.iterdir():
        if p.is_file() and p.name.lower() == name:
            return p
    return None


def hand_parse(game_dir, rt, index):
    """Read one resource straight out of the bytes, without volread."""
    d = pathlib.Path(game_dir)
    dirf = find_ci(d, DIRFILES[rt])
    if dirf is None:
        raise FileNotFoundError(DIRFILES[rt])
    raw = dirf.read_bytes()
    off = index * 3
    if off + 3 > len(raw):
        raise IndexError("slot %d past the DIR" % index)
    b0, b1, b2 = raw[off], raw[off + 1], raw[off + 2]
    vol = b0 >> 4
    offset = ((b0 & 0x0F) << 16) | (b1 << 8) | b2      # BIG-endian 20 bits
    if offset == 0xFFFFF:
        return None
    volf = find_ci(d, "vol.%d" % vol)
    if volf is None:
        raise FileNotFoundError("vol.%d" % vol)
    v = volf.read_bytes()
    if v[offset] != 0x12 or v[offset + 1] != 0x34:     # signature, BIG-endian
        raise ValueError("bad signature at 0x%05X in vol.%d" % (offset, vol))
    length = v[offset + 3] | (v[offset + 4] << 8)      # LITTLE-endian
    return v[offset + 5:offset + 5 + length]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--per-type", type=int, default=8, help="resources sampled per type")
    a = ap.parse_args()

    root = pathlib.Path(a.root)
    total_ok = total_bad = 0
    rows = []
    defects = []
    skipped = []
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        names = {f.name.lower() for f in d.iterdir() if f.is_file()}
        if not {"logdir", "picdir", "viewdir", "snddir"} <= names:
            if any(x.endswith("dir") for x in names) and any("vol." in x for x in names):
                skipped.append((d.name, "AGI v3 -- LZW, not fetched (§11.1)"))
            else:
                skipped.append((d.name, "not an AGI v2 directory"))
            continue
        game = resource.load_from_files(str(d))
        # ★★ A PRESENT DIR ENTRY IS NOT NECESSARILY A FETCHABLE ONE, and the two malformations
        # are different. P1.3 found four KQ1 SOUND entries pointing PAST THE END of a volume
        # that exists; SpaceQuest-1 SOUND 0 names volume 15, which does not exist at all. Its
        # bytes are FF 23 C1 -- not the FF FF FF empty marker, so `present` is True.
        # ★ Both are properties of the pinned corpus, not of the reader. They are excluded from
        # the fetch sample and REPORTED, because "the fetch failed" and "the entry was never
        # loadable" are different findings and only the first is about volread.
        volsizes = {}
        for f in d.iterdir():
            if f.is_file() and f.name.lower().startswith("vol."):
                try:
                    volsizes[int(f.name.split(".")[-1])] = f.stat().st_size
                except ValueError:
                    pass
        for rt in TYPES:
            for e in game.dirs[rt]:
                if not e.present:
                    continue
                if e.volume not in volsizes:
                    defects.append((d.name, rt, e.index, e.volume, e.offset, "volume absent"))
                elif e.offset + 5 > volsizes[e.volume]:
                    defects.append((d.name, rt, e.index, e.volume, e.offset,
                                    "offset past end of vol.%d (%d B)"
                                    % (e.volume, volsizes[e.volume])))
        badset = {(t, i) for (nm, t, i, _v, _o, _w) in defects if nm == d.name}

        ok = bad = 0
        detail = []
        for rt in TYPES:
            n = 0
            for e in game.dirs[rt]:
                if not e.present or n >= a.per_type or (rt, e.index) in badset:
                    continue
                n += 1
                try:
                    mine = hand_parse(d, rt, e.index)
                    theirs = game.load(rt, e.index)
                except Exception as exc:                       # noqa: BLE001
                    bad += 1
                    detail.append("%s %d: %s" % (rt, e.index, type(exc).__name__))
                    continue
                if mine == theirs:
                    ok += 1
                else:
                    bad += 1
                    detail.append("%s %d: %d vs %d bytes"
                                  % (rt, e.index, len(mine or b""), len(theirs)))
        total_ok += ok
        total_bad += bad
        rows.append((d.name, ok, bad, detail))

    print("AC-8 -- volread against an INDEPENDENT hand parse of the raw bytes\n")
    print("%-24s %6s %6s" % ("title", "ok", "bad"))
    for name, ok, bad, detail in rows:
        print("%-24s %6d %6d%s" % (name, ok, bad, "" if not bad else "   ★★★"))
        for x in detail[:4]:
            print("      %s" % x)
    print()
    print("sampled %d resources across %d v2 titles: %d byte-identical, %d differing"
          % (total_ok + total_bad, len(rows), total_ok, total_bad))
    print()
    print("corpus defects -- present DIR entries that are not loadable (excluded above):")
    if defects:
        print("  %-22s %-8s %5s %4s %9s  %s" % ("title","type","index","vol","offset","why"))
        for nm, t, i, v, o, why in defects:
            print("  %-22s %-8s %5d %4d %9d  %s" % (nm, t, i, v, o, why))
    else:
        print("  none")
    print()
    print("not fetched (stated, not omitted) [L-22]:")
    for name, why in skipped:
        print("  %-24s %s" % (name, why))
    print()
    print("AC-8 %s" % ("PASS" if total_bad == 0 else "★★★ FAIL"))
    return 0 if total_bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
