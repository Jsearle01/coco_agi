#!/usr/bin/env python3
"""ego_ref.py -- what does the ORACLE-GATED REFERENCE do with one arrow press? [T-P0-131]

★★★★ T-P0-131's cycle-timed traces show the ego walking three steps and stopping with no key
involved (x 110 -> 113 right, 110 -> 107 left, KQ1 room 1). Before that is called a port defect it
is run here: the reference [tools/agivm], jumped to the same room at the same cycle, is given the
press the way handleController delivers it -- VAR_EGO_DIRECTION set, the ego's motion type normal
when player control is on [keyboard.cpp:600-611] -- before cycle AT+1, which is when the port's
dispatcher delivers a key pressed during cycle AT. Then one cycle at a time, the ego's x and
direction.

★ §2P: numbers only. usage:
    python harness/tools/ego_ref.py --dir 3 --at 15 --to 30
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm.cycle import Vm                    # noqa: E402
from agivm.optable import VM_VAR_EGO_DIRECTION  # noqa: E402
from volread import resource                   # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=r"C:\Projects\agi-games\pc\Kingquest1")
    ap.add_argument("--room", type=int, default=1)
    ap.add_argument("--room-at", type=int, default=8)
    ap.add_argument("--dir", type=int, default=3)
    ap.add_argument("--at", type=int, default=15, help="the press lands before cycle AT+1")
    ap.add_argument("--to", type=int, default=30)
    a = ap.parse_args()

    vm = Vm(resource.load_from_files(a.game), 0x2917, seed=12345)
    vm.start()
    vm.run(max_cycles=a.room_at)
    vm.set_var(0, a.room)
    vm.state.set_flag(5, True)
    vm.run(max_cycles=a.at)
    ego = vm.state.screen_objs[0]
    # handleController: same direction again -> 0, else the new one; motion normal under control.
    new = 0 if ego.direction == a.dir else a.dir
    vm.set_var(VM_VAR_EGO_DIRECTION, new)
    if getattr(vm.state, "player_control", True):
        ego.motionType = 0
    print("press: VAR %d <- %d before cycle %d (ego x=%d y=%d dir=%d)"
          % (VM_VAR_EGO_DIRECTION, new, a.at + 1, ego.x, ego.y, ego.direction))
    row = []
    for c in range(a.at + 1, a.to + 1):
        vm.run(max_cycles=c)
        row.append("%d:%d/%d" % (c, ego.x, ego.direction))
    print("reference ego (cycle:x/dir): " + " ".join(row))


if __name__ == "__main__":
    main()
