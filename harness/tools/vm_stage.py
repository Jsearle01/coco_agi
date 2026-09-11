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
from volread import words as words_mod  # noqa: E402

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
    # ★★ The jump must be declared to the STAGER, not only to the runner -- see below.
    ap.add_argument("--room", type=int, default=0, help="stage for a run that jumps to this room")
    ap.add_argument("--room-at", type=int, default=8, help="cycle the jump happens at")
    # ★★★★ T-P0-060: THE SCRIPTED INPUT. Off by default, so every existing gate invocation stages
    # exactly what it staged before and the nine-title result is unmoved [L-79: an arm that is
    # supposed to change nothing must be shown to change nothing].
    ap.add_argument("--input", default="",
                    help="a vm_input_script.py file: '<cycle> <text>' per line. "
                         "Both legs read THIS file; the guest gets it via vm_sweep.lua.")
    a = ap.parse_args()

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    game = resource.load_from_files(a.game_dir)

    # ── the reference run: the trace, and which resources it touched ────────────────────
    rec = Recorder()
    vm = cycle_mod.Vm(game, 0x2917, trace=rec)

    # ═══════════════════════════════════════════════════════════════════════════════════
    # ★★★★★ THE PARSER, ON THE REFERENCE SIDE. Loaded BEFORE start() so the vocabulary exists
    # for the first feed; the 6809 leg stages words.tok at the same point, before its first
    # cycle. ★★★ With no --input the vocabulary is still not loaded at all -- feed_input() is
    # never called, ENTERED_CLI is never set, and test_said() returns False on its guard, which
    # is exactly what the stub did [cycle.py:83]. Staging a vocabulary and feeding nothing would
    # ALSO be inert, but not loading it keeps the two arms textually identical to the old ones.
    input_script = {}
    if a.input:
        for raw in pathlib.Path(a.input).read_text(encoding="latin-1").splitlines():
            raw = raw.rstrip("\n")
            if not raw or raw.startswith("#"):
                continue
            cyc, _sep, text = raw.partition(" ")
            input_script[int(cyc)] = text
        wt = pathlib.Path(a.game_dir) / "WORDS.TOK"
        wt_bytes = wt.read_bytes()
        vm.load_vocabulary(words_mod.parse(wt_bytes).words)
        vm.input_script = input_script
        # ★ The guest reads the SAME bytes. §2P: staged into build/ (untracked), never tracked,
        # and the size and hash are all that is printed.
        (out / "words.tok").write_bytes(wt_bytes)
        (out / "input.txt").write_bytes(pathlib.Path(a.input).read_bytes())
        print("vocabulary   : %d bytes  sha256 %s -> %s"
              % (len(wt_bytes), hashlib.sha256(wt_bytes).hexdigest()[:16], out / "words.tok"))
        print("input script : %d line(s) at cycles %s"
              % (len(input_script), sorted(input_script)))

    vm.start()
    # ★★★ vm.run(), NOT a bare loop over interpret_cycle(). The loop that was here called
    # interpret_cycle directly and so skipped everything run() does AROUND a cycle: the 25 ms
    # virtual clock, the VM_VAR_TIME_DELAY pacing gate, timer_update(), and the four post-cycle
    # resets. **virtual_ms therefore never advanced and vars 11-14 never ticked**, so the oracle
    # held VAR_SECONDS at 0 for ever while the 6809 -- which paces correctly in vm_pace -- put it
    # at 1 from cycle 11. The diff reported the GUEST as divergent on the one variable where the
    # guest was right and the baseline was wrong.
    # ★★ §2O.1's rule generalised: the baseline has to be the reference RUNNING, not a
    # convenience harness wrapped around its interior. A loop that calls one method of the
    # reference is not the reference; it is a third implementation with no tests.
    # ★ Confirmed against the reference itself: run(max_cycles=20) on KQ1 ends at virtual_ms
    # 1925 with TIME_DELAY=2 and SECONDS=1 -- i.e. the second boundary really is crossed inside
    # the sampled window, and the guest's cycle 11 is where it belongs.
    # ═══════════════════════════════════════════════════════════════════════════════════════
    # ★★★★★ THE SAME ROOM JUMP THE RUN WILL MAKE, OR THE STAGING IS FOR A DIFFERENT RUN
    # [T-P0-086 §4B]. `touched` is the set of volumes THIS reference run loaded, and the staging is
    # built from it. A run that jumps to a room reaches resources this one never does -- so staging
    # without the jump stages the wrong volumes, and the guest reports a resource error for a room
    # it was deliberately sent to.
    # ★★★★ MEASURED, NOT PREDICTED: PoliceQuest1 staged volumes [0,1] from a no-jump run, and the
    # jump to room 97 then gave `err 1` and no print on the 6809 side while the offline reference
    # printed 112 times. **Both legs must be fed identically** -- §2O.1's rule, applied to staging
    # rather than to input.
    # ★★★ Same two writes as p3b_run.lua and p3b_room.lua: var 0 and flag 5, the game's own dispatch.
    if a.room:
        vm.run(max_cycles=min(a.room_at, a.cycles))
        vm.set_var(0, a.room)                     # VAR_CURRENT_ROOM
        vm.state.set_flag(5, True)                # FLAG_NEW_ROOM_EXEC
        print("room jump    : var0 <- %d, flag 5 set, at cycle %d" % (a.room, a.room_at))
    vm.run(max_cycles=a.cycles)
    if a.room:
        print("room jump    : landed %s, dispatched %s, final room %d"
              % (vm.get_var(0) == a.room, not vm.state.get_flag(5), vm.get_var(0)))

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
    # ★★★★ THE WIRING'S COVERAGE, ON THE REFERENCE SIDE. A clean state diff is what the STUB
    # produced, so it is evidence about said() only if said() was reached AND returned true at
    # least once. The 6809 leg publishes vm_saidn / vm_saidm / vm_fedn and vm_sweep.lua prints
    # them beside these, so the two can be compared directly rather than assumed equal.
    print("said()       : evaluated %d, matched %d;  inputs fed %d"
          % (vm.said_seen, vm.said_matched, vm.input_fed))
    # ★★★★★ AND SAY WHY THE RUN ENDED, because with input fed it stops ending for the reason it
    # used to. Kingquest1 runs 600 cycles with no input and **140 with the script**: a fed line
    # matched a said() whose branch quits the game. ★★★★ That is the wiring working -- said()
    # returning true and the game acting on it -- and it must not be read as staging falling
    # short. ★★★ The 6809 leg reaches vm_quit at the same cycle or the state diff fails, so the
    # early stop is itself part of what is being compared, not a shortened window.
    print("run ended    : %d of %d cycles, should_quit=%s should_restart=%s"
          % (len(rec.rows), a.cycles, vm.should_quit, vm.should_restart))
    if a.input and (vm.should_quit or vm.should_restart):
        print("★ the run QUIT before --cycles. With a script fed this is a said() branch firing,")
        print("  and the guest must quit at the same cycle for the diff to pass.")
    if a.input and vm.said_matched == 0:
        print("★★★ said() never MATCHED on this title -- the script exercises the guard and not")
        print("    the matcher. Report it; do not read the state diff as covering said().")

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
