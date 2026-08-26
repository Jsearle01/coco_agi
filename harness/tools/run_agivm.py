#!/usr/bin/env python3
"""Run tools/agivm over a game directory and emit a per-cycle state trace.

★ THE GAME DIRECTORY IS OPENED READ-ONLY, ALWAYS (CLAUDE.md §2P). The trace is written
somewhere else entirely. A tool that opens a game file for writing is a bug.

Usage:
    python harness/tools/run_agivm.py <game-dir> <out-vmstate.txt>
        [--version 0x2917] [--cycles 800] [--seed 12345] [--platform dos]
"""
import argparse
import io
import pathlib
import sys
import traceback

# ★ The Windows console defaults to cp1252 and cannot encode the ★ this project's reports use.
# Without this the runner dies AFTER doing all its work, losing the output it just computed.
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from agivm.cycle import Vm                      # noqa: E402
from agivm.dispatch import OpcodeError, IMPLEMENTED, MODELLED, UNIMPLEMENTED  # noqa: E402
from agivm.trace import Trace                   # noqa: E402
from volread import resource                    # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("out")
    ap.add_argument("--version", default="0x2917")
    ap.add_argument("--cycles", type=int, default=800)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--platform", default="dos")
    ap.add_argument("--game-id", default="")
    args = ap.parse_args()

    version = int(args.version, 0)
    game = resource.load_from_files(args.game_dir)
    print("game    : %s" % args.game_dir)
    print("version : 0x%04X   platform: %s" % (version, args.platform))

    vm = Vm(game, version, platform=args.platform, game_id=args.game_id, seed=args.seed)

    cov = vm.table.coverage()
    print("opcodes : commands %d implemented / %d modelled / %d unimplemented"
          % (cov["commands"][IMPLEMENTED], cov["commands"][MODELLED],
             cov["commands"][UNIMPLEMENTED]))
    print("          tests    %d implemented / %d modelled / %d unimplemented"
          % (cov["tests"][IMPLEMENTED], cov["tests"][MODELLED],
             cov["tests"][UNIMPLEMENTED]))

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    status = 0
    with Trace(str(out)) as tr:
        vm.trace = tr
        vm.start()
        try:
            vm.run(max_cycles=args.cycles)
        except OpcodeError as exc:
            print()
            print("HALTED: %s" % exc)
            status = 2
        except Exception as exc:                            # noqa: BLE001
            print()
            print("HALTED (%s): %s" % (type(exc).__name__, exc))
            traceback.print_exc(limit=6)
            status = 3
        print()
        print("cycles emitted : %d" % tr.count)

    # ── AC-5: motion mode coverage. Modes REACHED and modes NOT reached, both named.
    MODE_NAMES = {0: "normal", 1: "wander", 2: "follow.ego", 3: "move.obj", 4: "ego(mouse)"}
    print()
    print("motion modes reached (checkMotion calls):")
    if vm.motion_modes_seen:
        for m in sorted(vm.motion_modes_seen):
            print("   %-12s (%d) : %d" % (MODE_NAMES.get(m, "UNKNOWN"), m,
                                          vm.motion_modes_seen[m]))
    else:
        print("   none")
    missing = [MODE_NAMES[m] for m in sorted(MODE_NAMES) if m not in vm.motion_modes_seen]
    print("   NOT reached this run: %s" % (", ".join(missing) if missing else "none"))
    print("   ★ every mode above is implemented; an unhandled mode raises rather than")
    print("     silently no-opping (motion.py check_motion).")

    # ── AC-6: compositing cost
    print()
    print("compositing cost (blit.py -- cost model, not pixels):")
    print(vm.blit_cost.report())

    if vm.modelled_calls:
        top = sorted(vm.modelled_calls.items(), key=lambda kv: -kv[1])[:10]
        print("modelled opcodes actually reached: %s"
              % ", ".join("%s x%d" % (k, v) for k, v in top))
    print("wrote %s" % out)
    return status


if __name__ == "__main__":
    sys.exit(main())
