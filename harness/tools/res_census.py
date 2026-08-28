#!/usr/bin/env python3
"""harness/tools/res_census.py -- AC-4: check the 6809's DIR parse slot by slot.

★★ THIS IS A DIFFERENT CLAIM FROM AC-2's. The byte gate proves the entries it happened to load
were parsed correctly; it says nothing about the slots it skipped -- empty ones, and ones living
in a volume that was not staged. ★★★ The empty-slot rule is exactly the one that hides there:
"test the offset, never the volume", because FF FF FF reads as volume 15. A census over EVERY
slot is what puts that rule under test.

Two modes:
  emit   -- write a requests.txt naming every slot of every type (for RES_MODE=census)
  check  -- diff the guest's parsed (present, volume, offset) against tools/volread/

★ 2P: reads game data, prints counts and offsets only.
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
RES_E_EMPTY = 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["emit", "check"])
    ap.add_argument("game_dir")
    ap.add_argument("--stage", required=True)
    ap.add_argument("--sweep", default="")
    a = ap.parse_args()

    game = resource.load_from_files(a.game_dir)

    if a.mode == "emit":
        out = pathlib.Path(a.stage) / "requests.txt"
        n = 0
        with out.open("w", encoding="ascii", newline="\n") as f:
            for ti, rt in enumerate(TYPES):
                for e in game.dirs[rt]:
                    f.write(f"{ti} {e.index}\n")
                    n += 1
        print("census request list: %d slots -> %s" % (n, out))
        print("  slots per type: %s" % {t: len(game.dirs[t]) for t in TYPES})
        return 0

    rows = []
    with (pathlib.Path(a.sweep) / "fetched.idx").open() as f:
        next(f)
        for line in f:
            rows.append(tuple(int(x) for x in line.strip().split(",")))

    ok = 0
    present_ok = empty_ok = 0
    bad = []
    counts = {t: [0, 0] for t in TYPES}          # [present-per-guest, slots-per-guest]
    for t, i, st, vol, off in rows:
        rt = TYPES[t]
        e = game.dirs[rt][i]
        counts[rt][1] += 1
        guest_present = (st != RES_E_EMPTY)
        if guest_present:
            counts[rt][0] += 1
        if guest_present != e.present:
            bad.append((rt, i, "guest present=%s, oracle present=%s" % (guest_present, e.present)))
        elif not e.present:
            empty_ok += 1
            ok += 1
        elif (vol, off) != (e.volume, e.offset):
            bad.append((rt, i, "guest vol %d off 0x%05X, oracle vol %d off 0x%05X"
                        % (vol, off, e.volume, e.offset)))
        else:
            present_ok += 1
            ok += 1

    oracle_counts = game.counts()
    print("game        : %s" % a.game_dir)
    print("slots parsed on the 6809 : %d" % len(rows))
    print("  agreeing with tools/volread/ : %d   (present %d, empty %d)"
          % (ok, present_ok, empty_ok))
    print("  disagreeing                  : %d" % len(bad))
    print("present/slots per type -- guest vs oracle:")
    for t in TYPES:
        g = tuple(counts[t])
        o = oracle_counts[t]
        flag = "" if g == o else "   ★★★ MISMATCH"
        print("  %-8s guest %3d/%3d   oracle %3d/%3d%s" % (t, g[0], g[1], o[0], o[1], flag))
    for rt, i, why in bad[:20]:
        print("  ! %-7s %3d  %s" % (rt, i, why))

    agree = all(tuple(counts[t]) == oracle_counts[t] for t in TYPES)
    return 0 if (not bad and agree) else 1


if __name__ == "__main__":
    sys.exit(main())
