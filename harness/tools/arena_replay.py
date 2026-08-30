#!/usr/bin/env python3
"""harness/tools/arena_replay.py -- M-34: the residency arena's eviction curve.

★★★ WHAT THIS ANSWERS AND WHY IT IS NOT A GUESS. Two probes chose arena sizes -- res_probe.s
12 KB at $3000, vm_probe.s 21 KB at $6B00 -- and NEITHER figure came from a workload. They
disagree by 9 KB and by base. This replays a real playthrough against a simulated arena and
counts what a given size actually costs, so AC-2 can choose a point on a measured curve instead
of inheriting a probe's convenience.

★★ THE MODEL. AGI's own semantics discard every loaded resource on a room change
(cycle.py:267-270 clears loaded_logics/views/pics/sounds). Our arena sits BENEATH that: the
bytes stay cached even after AGI forgets them, so returning to a room is free rather than a
refetch. **The eviction curve is exactly the value of that cache**, and at arena size 0 it
degenerates to "every touch is a disk fetch", which is the no-cache baseline.

★ TWO COUNTERS, DELIBERATELY DISTINCT:
    evictions -- times a resident resource was thrown out to make room
    refetches -- times a resource was re-read from disk having been resident earlier
  They are not the same number: a resource evicted and never wanted again costs an eviction and
  no refetch, and that difference is the whole question of whether the arena is big enough.

★★★ ROOMS ARE REACHED BY THE HOST-SIDE ROOM JUMP, not by playing through -- var 0 is
VAR_CURRENT_ROOM and flag 5 is FLAG_NEW_ROOM_EXEC, which logic.0 tests every cycle [P5.3 AC-4].
Two writes and no target code. **Stated here because AC-1 requires the workload to be stated:
this is a room SWEEP, not a walkthrough, and it exercises resource loading rather than plot.**

★ SIZES ARE THE REAL ON-DISK RECORD LENGTHS from game.load(), never estimates. The game
directory is opened READ-ONLY (CLAUDE.md §2P).
"""
import argparse
import collections
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from agivm.cycle import Vm                      # noqa: E402
from volread import resource                    # noqa: E402


def collect_touches(game_dir, version, rooms, cycles_per_room, seed, platform):
    """Run the VM across a room sweep and record every resource touch, in order.

    ★★ HOOKS load_logic/load_view RATHER THAN game.load, because the VM memoises in
    _logic_cache/_view_cache and game.load therefore fires ONCE per resource for the whole run.
    A curve built from first-fetches only would show zero evictions at every size -- the
    instrument would have measured the VM's Python dict instead of our arena [L-56].
    """
    game = resource.load_from_files(game_dir)
    vm = Vm(game, version, platform=platform, seed=seed)

    touches = []          # (type, index, size)
    sizes = {}

    real_logic, real_view = vm.load_logic, vm.load_view

    def size_of(kind, nr):
        key = (kind, nr)
        if key not in sizes:
            try:
                sizes[key] = len(game.load(kind, nr))
            except Exception:                                # noqa: BLE001
                sizes[key] = 0
        return sizes[key]

    def hooked_logic(nr):
        r = real_logic(nr)
        touches.append(("LOGIC", nr, size_of("LOGIC", nr)))
        return r

    def hooked_view(nr):
        r = real_view(nr)
        touches.append(("VIEW", nr, size_of("VIEW", nr)))
        return r

    vm.load_logic, vm.load_view = hooked_logic, hooked_view

    vm.start()
    reached, failed = [], []
    for room in rooms:
        try:
            # ★ the two-write room jump; see the module header
            vm.state.vars[0] = room & 0xFF
            vm.state.flags[5] = True
            vm.run(max_cycles=cycles_per_room)
            reached.append(room)
        except Exception:                                    # noqa: BLE001
            failed.append(room)
    return touches, reached, failed, sizes


def simulate(touches, capacity):
    """LRU arena of `capacity` bytes over the touch stream.

    ★ A resource larger than the whole arena is counted as an UNCACHEABLE fetch rather than
    looping forever trying to evict enough for it -- and it is reported separately, because a
    single oversized resource silently defeating the cache is precisely the kind of thing an
    aggregate eviction count hides.
    """
    resident = collections.OrderedDict()      # key -> size, MRU last
    used = 0
    evictions = refetches = fetches = oversized = 0
    seen_before = set()

    for kind, nr, size in touches:
        key = (kind, nr)
        if key in resident:
            resident.move_to_end(key)
            continue
        fetches += 1
        if key in seen_before:
            refetches += 1
        seen_before.add(key)
        if size > capacity:
            oversized += 1
            continue
        while used + size > capacity and resident:
            _, ev = resident.popitem(last=False)
            used -= ev
            evictions += 1
        resident[key] = size
        used += size
    return {"evictions": evictions, "refetches": refetches, "fetches": fetches,
            "oversized": oversized, "peak_used": used}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("--version", default="0x2917")
    ap.add_argument("--rooms", default="1-40")
    ap.add_argument("--cycles-per-room", type=int, default=40)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--platform", default="dos")
    ap.add_argument("--label", default="")
    ap.add_argument("--sizes", default="0,2,4,6,8,12,16,21,24,32,40,48,64",
                    help="arena sizes in KB")
    args = ap.parse_args()

    lo, _, hi = args.rooms.partition("-")
    rooms = list(range(int(lo), int(hi) + 1)) if hi else [int(lo)]

    touches, reached, failed, sizes = collect_touches(
        args.game_dir, int(args.version, 0), rooms,
        args.cycles_per_room, args.seed, args.platform)

    label = args.label or pathlib.Path(args.game_dir).name
    distinct = {(k, n) for k, n, _ in touches}
    working_set = sum(sizes[k] for k in distinct if k in sizes)

    print(f"=== {label}")
    print(f"workload      : room sweep {args.rooms}, {args.cycles_per_room} cycles/room, "
          f"seed {args.seed}  (host-side room jump, not a walkthrough)")
    print(f"rooms reached : {len(reached)} of {len(rooms)}"
          + (f"   failed: {len(failed)}" if failed else ""))
    print(f"touches       : {len(touches)}  over {len(distinct)} distinct resource(s)")
    print(f"working set   : {working_set:,} B if everything touched were resident at once")
    print()
    print(f"  {'arena':>9}  {'evictions':>10}  {'refetches':>10}  {'fetches':>8}  {'oversized':>9}")
    print("  " + "-" * 54)
    curve = []
    for kb in [int(s) for s in args.sizes.split(",")]:
        cap = kb * 1024
        r = simulate(touches, cap)
        curve.append((kb, r))
        print(f"  {kb:>6} KB  {r['evictions']:>10}  {r['refetches']:>10}  "
              f"{r['fetches']:>8}  {r['oversized']:>9}")

    # ★★ THE KNEE IS THE DELIVERABLE, not the table. Report the smallest size at which
    # refetches stop falling -- past that point more arena buys nothing on this workload.
    best = min(r["refetches"] for _, r in curve)
    knee = next((kb for kb, r in curve if r["refetches"] == best), None)
    print()
    print(f"  ★ refetches bottom out at {best} and first reach it at {knee} KB")
    zero_ev = next((kb for kb, r in curve if r["evictions"] == 0 and kb > 0), None)
    print(f"  ★ first size with ZERO evictions: {zero_ev} KB"
          if zero_ev else "  ★ no tested size eliminates eviction")
    return 0


if __name__ == "__main__":
    sys.exit(main())
