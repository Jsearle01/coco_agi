#!/usr/bin/env python3
"""harness/tools/res_stack.py -- AC-5: drive the residency stack past the point where it fits.

★★★ AC-5 IS NOT "MORE BYTES THAN THE WINDOW" -- AC-2 ALREADY DID THAT. Every one of the 1,264
gated fetches pulled a resource through an 8 KB window out of a volume up to 247,952 bytes long,
and 10,428-byte resources straddled three blocks. That demonstrates the WINDOW. ★★ This
demonstrates the ARENA: resources held resident SIMULTANEOUSLY, past the 12 KB the arena has.

The scenario, in three parts, and each part is a distinct claim:

  A. NEST     -- open several resources without closing, and check every one of them is still
                 byte-correct AT THE ADDRESS THE GUEST REPORTED. ★ A stack that returned the
                 right length at the wrong base would pass a length check and fail this.
  B. EXHAUST  -- keep opening until it refuses. ★★★ The refusal is the deliverable: status
                 RES_E_FULL, zero bytes, and depth UNCHANGED. Silent wrong bytes is the failure
                 being designed against, so "it failed" is not enough -- it must not have pushed.
  C. REUSE    -- close back down and open something else. ★ The arena must hand the space back;
                 if close were a no-op the next open would refuse and the bug would look like
                 an undersized arena rather than a broken pop.

★ 2P: reads game data; emits opcodes, lengths, addresses and counts. No resource bytes printed.
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
OPEN, CLOSE = 2, 3
ARENA, ARENA_END = 0x3000, 0x6000
ERRS = {0: "ok", 1: "empty-slot", 2: "bad-signature", 3: "out-of-range",
        4: "too-big-for-arena", 5: "arena-full", 6: "max-depth"}


def pick(game, volume, limit, want, min_size=1):
    """Resources present in the staged volume, largest first."""
    out = []
    for ti, rt in enumerate(TYPES):
        for e in game.dirs[rt]:
            if e.present and e.volume == volume and e.offset < limit:
                n = len(game.load(rt, e.index))
                if n >= min_size:
                    out.append((ti, e.index, n))
    out.sort(key=lambda c: -c[2])
    return out[:want]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["emit", "check"])
    ap.add_argument("game_dir")
    ap.add_argument("--stage", required=True)
    ap.add_argument("--sweep", default="")
    ap.add_argument("--volume", type=int, default=0)
    a = ap.parse_args()

    game = resource.load_from_files(a.game_dir)
    stage = pathlib.Path(a.stage)
    limit = len((game.volumes.get(a.volume)).data)

    if a.mode == "emit":
        big = pick(game, a.volume, limit, 12, min_size=1500)
        ops, plan = [], []
        # A. NEST -- open until the next one would not fit, without closing any
        held = 0
        for ti, idx, n in big:
            if held + n > ARENA_END - ARENA:
                break
            ops.append((OPEN, ti, idx)); plan.append(("nest", ti, idx, n))
            held += n
        # B. EXHAUST -- the next open must be refused, and must not push
        for ti, idx, n in big:
            if held + n > ARENA_END - ARENA:
                ops.append((OPEN, ti, idx)); plan.append(("exhaust", ti, idx, n))
                break
        # C. REUSE -- unwind completely, then open the largest again at depth 0
        for _ in range(len(ops) - 1):
            ops.append((CLOSE, 0, 0)); plan.append(("close", 0, 0, 0))
        ti, idx, n = big[0]
        ops.append((OPEN, ti, idx)); plan.append(("reuse", ti, idx, n))
        ops.append((CLOSE, 0, 0)); plan.append(("close", 0, 0, 0))

        with (stage / "ops.txt").open("w", encoding="ascii", newline="\n") as f:
            for o, ti, idx in ops:
                f.write(f"{o} {ti} {idx}\n")
        with (stage / "plan.txt").open("w", encoding="ascii", newline="\n") as f:
            for phase, ti, idx, n in plan:
                f.write(f"{phase} {ti} {idx} {n}\n")
        print("AC-5 scenario: %d ops -- nest %d, exhaust %d, close %d, reuse %d"
              % (len(ops), sum(1 for p in plan if p[0] == "nest"),
                 sum(1 for p in plan if p[0] == "exhaust"),
                 sum(1 for p in plan if p[0] == "close"),
                 sum(1 for p in plan if p[0] == "reuse")))
        print("arena %d bytes; nested bytes held at peak: %d"
              % (ARENA_END - ARENA, sum(p[3] for p in plan if p[0] == "nest")))
        return 0

    plan = [(p.split()[0], int(p.split()[1]), int(p.split()[2]), int(p.split()[3]))
            for p in (stage / "plan.txt").read_text().splitlines()]
    blob = (pathlib.Path(a.sweep) / "fetched.bin").read_bytes()
    rows = []
    with (pathlib.Path(a.sweep) / "fetched.idx").open() as f:
        next(f)
        for line in f:
            # ★ first 7 only: stack mode gained an 8th column (message count) for AC-9
            rows.append(tuple(int(x) for x in line.strip().split(","))[:7])

    pos, bad, ok = 0, [], 0
    prev_depth = 0
    peak = 0
    for (phase, pti, pidx, pn), (op, t, i, st, ln, base, depth) in zip(plan, rows):
        rt = TYPES[t]
        if phase in ("nest", "reuse"):
            want = game.load(rt, i)
            got = blob[pos:pos + ln]
            pos += ln
            if st != 0:
                bad.append((phase, rt, i, "refused: %s" % ERRS.get(st, st)))
            elif got != want:
                bad.append((phase, rt, i, "%d bytes at $%04X, differs from oracle" % (ln, base)))
            elif base < ARENA or base + ln > ARENA_END:
                bad.append((phase, rt, i, "base $%04X + %d escapes the arena" % (base, ln)))
            elif depth != prev_depth + 1:
                bad.append((phase, rt, i, "depth %d, expected %d" % (depth, prev_depth + 1)))
            else:
                ok += 1
                print("  %-7s %-7s %3d  %5d B at $%04X  depth %d" % (phase, rt, i, ln, base, depth))
            prev_depth = depth
            peak = max(peak, base + ln - ARENA)
        elif phase == "exhaust":
            note = "status=%d (%s), len=%d, depth %d" % (st, ERRS.get(st, st), ln, depth)
            if st == 0:
                bad.append((phase, rt, i, "★★★ ACCEPTED a %d B open that cannot fit" % pn))
            elif depth != prev_depth:
                bad.append((phase, rt, i, "★★★ refused but PUSHED: depth %d -> %d"
                            % (prev_depth, depth)))
            else:
                ok += 1
                print("  exhaust %-7s %3d  %d B request refused -- %s" % (rt, i, pn, note))
        else:
            if depth != max(0, prev_depth - 1):
                bad.append(("close", "-", 0, "depth %d, expected %d" % (depth, prev_depth - 1)))
            else:
                ok += 1
            prev_depth = depth

    print("arena         : $%04X-$%04X (%d bytes); peak held %d bytes"
          % (ARENA, ARENA_END, ARENA_END - ARENA, peak))
    print("operations    : %d   agreeing: %d   failing: %d" % (len(rows), ok, len(bad)))
    for phase, rt, i, why in bad:
        print("  ! %-8s %-7s %3s  %s" % (phase, rt, i, why))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
