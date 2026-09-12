"""room_trace.py -- the ROOM's trajectory across a run, from a per-cycle state dump. [T-P0-094]

★★★★★ THIS EXISTS BECAUSE THE CLUSTER HAD TWO ENDPOINTS AND NO TRAJECTORY. Six tasks recorded
"final room 83" or "final room 1" and nothing in between, so "the game restarted" was an inference
from where a run stopped rather than an observation of what it did. **A room number per cycle turns
that into a sequence.**

★★★★ IT READS THE GATE's OWN DUMP FORMAT, not a new one: 288 bytes per cycle, 32 packed flag bytes
then 256 variables, exactly as vm_diff.py documents and reads. Var 0 is VAR_CURRENT_ROOM, so it is
byte 32 of each record. **One producer, two consumers** -- the same file the diff compares is the
file this summarises, so the two cannot disagree about what the run did [§2O.1].

★ §2P: prints cycle numbers, room numbers and flag numbers. No game data.

usage:
    python harness/tools/room_trace.py <dump.bin> [--flag N] [--label NAME]
    python harness/tools/room_trace.py a.bin --vs b.bin --label-a oracle --label-b guest
"""
import argparse
import pathlib
import sys

ROW = 288
NFLAGBYTES = 32
VAR0 = NFLAGBYTES          # VAR_CURRENT_ROOM


def records(path):
    b = pathlib.Path(path).read_bytes()
    if len(b) % ROW:
        print("★★★ %s is %d bytes, not a multiple of %d -- wrong dump format?"
              % (path, len(b), ROW))
        sys.exit(2)
    return [b[i:i + ROW] for i in range(0, len(b), ROW)]


def flag(rec, n):
    return (rec[n >> 3] >> (n & 7)) & 1


def transitions(recs):
    """-> [(cycle, room)] at every change, including cycle 0."""
    out, prev = [], None
    for i, r in enumerate(recs):
        room = r[VAR0]
        if room != prev:
            out.append((i, room))
            prev = room
    return out


def main():
    a_ = argparse.ArgumentParser()
    a_.add_argument("dump")
    a_.add_argument("--vs", help="a second dump to compare room-for-room")
    a_.add_argument("--label", default="run")
    a_.add_argument("--label-a", default="A")
    a_.add_argument("--label-b", default="B")
    a_.add_argument("--flag", type=int, action="append", default=[],
                    help="also report this flag's transitions (5 = NEW_ROOM_EXEC)")
    a = a_.parse_args()

    ra = records(a.dump)
    ta = transitions(ra)
    print("%-8s : %d cycles, %d room transition(s)" % (a.label, len(ra), len(ta)))
    print("%-8s : %s" % ("rooms", "  ".join("c%d->%d" % (c, r) for c, r in ta)))
    for f in a.flag:
        prev, ch = None, []
        for i, r in enumerate(ra):
            v = flag(r, f)
            if v != prev:
                ch.append((i, v))
                prev = v
        print("flag %-3d : %s" % (f, "  ".join("c%d=%d" % (c, v) for c, v in ch)))

    if a.vs:
        rb = records(a.vs)
        tb = transitions(rb)
        print("%-8s : %d cycles, %d room transition(s)" % (a.label_b, len(rb), len(tb)))
        print("%-8s : %s" % ("rooms", "  ".join("c%d->%d" % (c, r) for c, r in tb)))
        # ★★★ THE ROOM-ONLY DIFF, WHICH IS NOT THE BYTE DIFF. vm_diff.py answers "do all 288 bytes
        # agree"; this answers "do they agree about the ROOM", which is the question the restart
        # cluster is actually asking and which a 288-byte verdict buries.
        n = min(len(ra), len(rb))
        first = next((i for i in range(n) if ra[i][VAR0] != rb[i][VAR0]), None)
        if first is None:
            print("verdict  : ★ the two runs agree about the room on every one of %d cycles" % n)
        else:
            print("verdict  : ★★★ first ROOM disagreement at cycle %d -- %s=%d %s=%d"
                  % (first, a.label_a, ra[first][VAR0], a.label_b, rb[first][VAR0]))


if __name__ == "__main__":
    main()
