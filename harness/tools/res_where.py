#!/usr/bin/env python3
"""harness/tools/res_where.py -- which VOLUME does a resource live in? [T-P0-127]

★★★★★ THIS EXISTS BECAUSE A SILENT DROP NEEDED A REASON. p3_composite_all skips a sprite whose
res_open fails and records NOTHING -- no counter, no error byte [p3b_probe.s:2539, pca_skip] -- so
"2 of 4 staged sprites composited" was as far as the guest could say. **The next question is
whether the resource it wanted is reachable at all**, and that is answerable entirely host-side
from the game's own DIR tables.

★★★ §2P: the game directory is opened READ-ONLY and nothing is written. Emits resource numbers,
volume numbers, offsets and lengths -- no resource bytes, no message text.

usage:
    python harness/tools/res_where.py --type view --num 107
    python harness/tools/res_where.py --type view --num 107 --staged 0,1
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from volread import resource  # noqa: E402

KINDS = ("logic", "picture", "view", "sound")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=r"C:\Projects\agi-games\pc\Kingquest1")
    ap.add_argument("--type", default="view", choices=KINDS)
    ap.add_argument("--num", type=int, required=True)
    ap.add_argument("--staged", default="",
                    help="comma-separated volume numbers the harness staged, for a verdict")
    a = ap.parse_args()

    game = resource.load_from_files(a.game)
    # ★★ The Game object keys its DIRs by resource-type NAME [resource.py:54, `self.dirs`], and
    # `entry()` raises rather than returning a partial -- so an out-of-range number is a refusal
    # here too rather than a silent None.
    try:
        # ★★ The DIR keys are the UPPERCASE names [resource.py:25], not the CLI's lowercase ones.
        e = game.entry(a.type.upper(), a.num)
    except Exception as exc:                                    # noqa: BLE001
        print("★★★ %s %d: %s" % (a.type, a.num, exc))
        return 2
    if not e.present:
        print("★★★ %s %d has an EMPTY DIR slot (FF FF FF) -- the game does not define it"
              % (a.type, a.num))
        return 1

    print("%s %d -> volume %d, offset %d" % (a.type, a.num, e.volume, e.offset))

    if a.staged:
        staged = {int(s) for s in a.staged.split(",") if s.strip() != ""}
        # ★★★★ THE VERDICT IS THE POINT. A resource in an unstaged volume cannot be fetched no
        # matter how correct the engine is, and the guest's only symptom is a sprite that never
        # draws [§2W.3: name the cause, do not leave a count to be interpreted].
        if e.volume in staged:
            print("   ★ volume %d IS staged (%s) -- reachable" %
                  (e.volume, ",".join(str(v) for v in sorted(staged))))
        else:
            print("   ★★★ volume %d is NOT staged (staged: %s) -- res_open CANNOT fetch it"
                  % (e.volume, ",".join(str(v) for v in sorted(staged))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
