#!/usr/bin/env python3
"""harness/tools/vm_stage.py -- stage a title's volumes for vm_sweep.lua, and emit the oracle trace.

★★ WHAT THE HOST SUPPLIES AND WHAT THE GUEST DOES. The host writes RAW volume bytes into
physical blocks and RAW DIR bytes into RAM, and nothing else. Every parse AC-2 is about -- the
DIR entry decode, the 20-bit offset, the record header, the LOGIC bytecode/message split, the
VIEW header walk -- happens on the 6809. §2O.1: if this script fed the guest parsed offsets, a
shared misreading would agree with itself forever.

★★★ WHICH VOLUMES TO STAGE IS A CAPACITY QUESTION, NOT A PARSING ONE. 56 free blocks on a
512 KB machine is 458,752 bytes; KQ3's four volumes total 651,490 and do not fit. So the script
asks the REFERENCE which resources the gated window actually loads, takes the set of volumes
those live in, and stages exactly those. ★ That is metadata about the workload, not a parse
result handed to the guest -- and if a volume is missed the guest reads unstaged RAM, fails the
signature check and HALTS, which is a loud failure rather than a wrong answer.

★ The oracle trace (flags+vars per cycle) is written here too, so the diff has both sides from
one invocation and they cannot be generated from different runs by accident.

★ §2P: reads game data; writes slices and a trace to build/, which is not tracked.
"""
import argparse
import hashlib
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import cycle as cycle_mod  # noqa: E402
from volread import resource  # noqa: E402

TYPES = ["LOGIC", "PICTURE", "VIEW", "SOUND"]
DIRFILES = ["logdir", "picdir", "viewdir", "snddir"]
BLOCK = 0x2000


class Recorder:
    """The oracle side of AC-2: 32 flag bytes + 256 var bytes per cycle, at cycle entry."""

    def __init__(self):
        self.rows = []

    def emit(self, cycle_nr, flags, vars_):
        self.rows.append(bytes(flags) + bytes(vars_))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("--out", required=True)
    ap.add_argument("--cycles", type=int, default=600)
    ap.add_argument("--volbase", type=int, default=8)
    ap.add_argument("--blocks", type=int, default=56, help="free physical blocks (L-44: stated)")
    a = ap.parse_args()

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    game = resource.load_from_files(a.game_dir)

    # ── the reference run: the trace, and which resources it touched ────────────────────
    rec = Recorder()
    vm = cycle_mod.Vm(game, 0x2917, trace=rec)
    vm.start()
    for _ in range(a.cycles):
        if vm.should_quit:
            break
        vm.interpret_cycle()

    touched = set()
    for nr in vm._logic_cache:
        touched.add(game.entry("LOGIC", nr).volume)
    for nr in vm._view_cache:
        touched.add(game.entry("VIEW", nr).volume)

    (out / "oracle.bin").write_bytes(b"".join(rec.rows))
    print("oracle trace : %d cycles x 288 bytes -> %s"
          % (len(rec.rows), out / "oracle.bin"))
    print("               sha256 %s"
          % hashlib.sha256(b"".join(rec.rows)).hexdigest()[:16])

    # ── the raw DIR tables, rebuilt byte for byte ───────────────────────────────────────
    for rt, name in zip(TYPES, DIRFILES):
        buf = bytearray()
        for e in game.dirs[rt]:
            if not e.present:
                buf += b"\xFF\xFF\xFF"
            else:
                v = (e.volume & 0x0F) << 4 | ((e.offset >> 16) & 0x0F)
                buf += bytes([v, (e.offset >> 8) & 0xFF, e.offset & 0xFF])
        (out / (name + ".bin")).write_bytes(bytes(buf))

    # ── stage the touched volumes, block-aligned, in order ──────────────────────────────
    base = a.volbase
    budget = a.blocks
    volmap = {}
    staged, skipped = [], []
    for v in sorted(touched):
        data = game.volumes.get(v).data
        nblk = (len(data) + BLOCK - 1) // BLOCK
        if nblk > budget:
            skipped.append((v, len(data), nblk))
            continue
        (out / ("vol%d.bin" % v)).write_bytes(data)
        volmap[v] = base
        staged.append((v, len(data), nblk, base))
        base += nblk
        budget -= nblk

    with (out / "manifest.txt").open("w", encoding="ascii", newline="\n") as f:
        f.write("cycles %d\n" % len(rec.rows))
        for v, n, nblk, b in staged:
            f.write("vol %d %d %d\n" % (v, b, n))
    print("volumes      : touched %s" % sorted(touched))
    for v, n, nblk, b in staged:
        print("  vol.%d %7d bytes -> %2d blocks at block %2d" % (v, n, nblk, b))
    for v, n, nblk in skipped:
        print("  ★★★ vol.%d %7d bytes (%d blocks) NOT STAGED -- out of budget" % (v, n, nblk))
    print("blocks used  : %d of %d" % (a.blocks - budget, a.blocks))
    if skipped:
        print("★★ A fetch into an unstaged volume will fail the signature check and HALT the")
        print("   guest -- loud, not a wrong answer. But the gate cannot pass with one skipped.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
