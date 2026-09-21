#!/usr/bin/env python3
"""view_straddle.py -- which VIEW header reads straddle an 8 KB block boundary? [T-P0-130 §4B.1]

★★★★ set.view / set.loop / set.cel read a VIEW's header IN PLACE through the volume window since
T-P0-130 [vm_run.s], instead of copying the whole VIEW into the arena. The window is one 8 KB
block, so a two-byte field whose bytes sit in different blocks is the case that finds a defect
in an in-place read. This lists every such field in the corpus, so the fault arm can be shown to
hit a real one rather than an invented one.

★★ What is read, per vm_run.s (offsets relative to the payload, i.e. after the 5-byte record
header):
    +2                     loop count                         1 byte
    +5 + 2n                loop n's offset, little-endian     2 bytes   <- can straddle
    L = that offset        cel count                          1 byte
    L + 1 + 2m             cel m's offset (rel. to L), LE     2 bytes   <- can straddle
    C = L + that offset    width, height                      2 bytes   <- can straddle
★ A block boundary is a VOLUME offset that is a multiple of 8,192: volumes are staged from a
block-aligned slice base [res_core.s:648], so the low 13 bits of the volume offset are the
in-block displacement whatever block the volume starts at.

§2P: game files are opened read-only; prints numbers only.

usage: python harness/tools/view_straddle.py [--games C:\\Projects\\agi-games\\pc] [title ...]
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from volread import resource  # noqa: E402

VM_GATE_TITLES = ["Kingquest1", "Kingquest2", "Kingquest3", "SpaceQuest-1", "SpaceQuest-2",
                  "PoliceQuest1", "larry1", "BlackCauldron", "MixedUpMotherGoose"]
BLOCK = 8192
HDR = 5


def le16(b, i):
    return b[i] | (b[i + 1] << 8)


def fields(v):
    """Yield (name, payload_offset, width) for every header field the VM can read."""
    nloops = v[2]
    yield ("loopcount", 2, 1)
    for n in range(nloops):
        lo = 5 + 2 * n
        yield ("loop%d.off" % n, lo, 2)
        L = le16(v, lo)
        if L >= len(v):
            continue
        yield ("loop%d.celcount" % n, L, 1)
        for m in range(v[L]):
            co = L + 1 + 2 * m
            if co + 1 >= len(v):
                continue
            yield ("loop%d.cel%d.off" % (n, m), co, 2)
            C = L + le16(v, co)
            if C + 1 < len(v):
                yield ("loop%d.cel%d.wh" % (n, m), C, 2)


def reach(game, cycles, version):
    """★★★ Which header fields does a real run READ? Runs the oracle-gated reference [tools/agivm]
    for `cycles` and records every (view, loop, cel) that set.view / set.loop / set.cel resolve,
    by wrapping objects.py's module functions -- so the interpreter that runs is the one under test
    [pic_order.py's rule]. Returns {view: set of field names read}.
    ★★ The field names match fields() above, so a straddling field can be checked for reach."""
    from agivm import objects
    from agivm.cycle import Vm
    read = {}
    orig = (objects.set_view, objects.set_loop, objects.set_cel)

    def note(v, name):
        read.setdefault(v, set()).add(name)

    def w_view(vm_, obj, view_nr):
        note(view_nr, "loopcount")
        return orig[0](vm_, obj, view_nr)

    def w_loop(vm_, obj, loop_nr):
        r = orig[1](vm_, obj, loop_nr)
        if obj.numLoops:
            note(obj.view, "loop%d.off" % obj.loop)
            note(obj.view, "loop%d.celcount" % obj.loop)
        return r

    def w_cel(vm_, obj, cel_nr):
        r = orig[2](vm_, obj, cel_nr)
        if obj.numLoops:
            note(obj.view, "loop%d.off" % obj.loop)
            note(obj.view, "loop%d.cel%d.off" % (obj.loop, obj.cel))
            note(obj.view, "loop%d.cel%d.wh" % (obj.loop, obj.cel))
        return r

    objects.set_view, objects.set_loop, objects.set_cel = w_view, w_loop, w_cel
    try:
        vm = Vm(game, version, seed=12345)
        vm.start()
        try:
            vm.run(max_cycles=cycles)
        except Exception as exc:                                    # noqa: BLE001
            print("    (reference stopped: %s)" % exc)
    finally:
        objects.set_view, objects.set_loop, objects.set_cel = orig
    return read


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--reach", type=int, default=0,
                    help="also run the reference N cycles and say whether each straddle is READ")
    ap.add_argument("--version", default="0x2917")
    ap.add_argument("--expect", default=None,
                    help="VIEW[,LOOP,CEL]: what set.view must produce there (AC-8's oracle)")
    ap.add_argument("--construct", default=None,
                    help="VOLS: list VIEWs in these volumes whose payload CROSSES a block boundary, "
                         "with the payload offset and the two bytes either side (AC-8)")
    ap.add_argument("titles", nargs="*")
    a = ap.parse_args()
    if a.construct is not None:
        # ★★★★ AC-8's constructed straddle. The corpus's three header straddles could not tell a
        # correct read from a faulted one, so the test reads a 16-bit value at an offset chosen to
        # straddle, through the same vm_le16 the headers use. The high byte is printed so a case
        # whose high byte equals what the fault would read instead can be avoided.
        vols = {int(s) for s in a.construct.split(",")}
        for t in (a.titles or ["Kingquest1"]):
            g = resource.load_from_files(pathlib.Path(a.games) / t)
            for e in g.iter_present(resource.VIEW):
                if e.volume not in vols:
                    continue
                v = g.load(resource.VIEW, e.index)
                p0 = e.offset + HDR
                nxt = (p0 // BLOCK + 1) * BLOCK           # first boundary after the payload start
                k = nxt - 1 - p0                          # payload offset whose NEXT byte is over it
                if k + 1 < len(v):
                    print("%s view %3d vol %d: payload +%d straddles (volume offset %d|%d), "
                          "bytes lo=$%02X hi=$%02X -> LE16 %d"
                          % (t, e.index, e.volume, k, nxt - 1, nxt, v[k], v[k + 1],
                             v[k] | (v[k + 1] << 8)))
        return
    if a.expect is not None:
        # ★★★ AC-8's expected values, read straight from the VIEW's bytes by the same offsets
        # vm_run.s walks. -DP3B_VIEWHDR_TEST prints the guest's; the two lines must match.
        parts = [int(x) for x in a.expect.split(",")] + [0, 0]
        vn, ln, cn = parts[0], parts[1], parts[2]
        for t in (a.titles or ["Kingquest2"]):
            g = resource.load_from_files(pathlib.Path(a.games) / t)
            v = g.load(resource.VIEW, vn)
            ln = ln if ln < v[2] else 0                   # set_view: out-of-range loop -> 0
            L = le16(v, 5 + 2 * ln)
            cn = cn if cn < v[L] else 0                   # set_loop: out-of-range cel -> 0
            C = L + le16(v, L + 1 + 2 * cn)
            print("%s view %d expect: numloops=%d numcels=%d loop=%d cel=%d xsize=%d ysize=%d"
                  % (t, vn, v[2], v[L], ln, cn, v[C], v[C + 1]))
        return
    total_fields = total_straddle = total_reached = 0
    for t in (a.titles or VM_GATE_TITLES):
        g = resource.load_from_files(pathlib.Path(a.games) / t)
        nv = ns = 0
        rows = []
        for e in g.iter_present(resource.VIEW):
            v = g.load(resource.VIEW, e.index)
            base = e.offset + HDR                 # volume offset of payload byte 0
            for name, off, w in fields(v):
                nv += 1
                if w == 2 and (base + off) % BLOCK == BLOCK - 1:
                    ns += 1
                    rows.append((e.index, e.volume, name, off, base + off))
        total_fields += nv
        total_straddle += ns
        print("%-20s %6d header fields read-able, %d straddle a block boundary" % (t, nv, ns))
        got = reach(g, a.reach, int(a.version, 0)) if (a.reach and rows) else None
        if got is not None:
            # ★★ §2W: a "not read" verdict is only worth something if this instrument can say
            # READ. The count of views it saw set is that evidence, printed beside every verdict.
            print("    reference set %d distinct views, %d distinct fields, in %d cycles"
                  % (len(got), sum(len(s) for s in got.values()), a.reach))
        for vi, vol, name, off, abs_ in rows:
            verdict = ""
            if got is not None:
                hit = name in got.get(vi, ())
                total_reached += hit
                verdict = ("  ★ READ within %d cycles" % a.reach if hit
                           else "  -- not read in %d cycles (view %s)"
                           % (a.reach, "loaded" if vi in got else "never set"))
            print("    view %3d  vol %d  %-18s at payload +%d (volume offset %d)%s"
                  % (vi, vol, name, off, abs_, verdict))
    print("TOTAL %d fields, %d straddling%s" % (
        total_fields, total_straddle,
        (", %d of them READ by the reference in %d cycles" % (total_reached, a.reach))
        if a.reach else ""))


if __name__ == "__main__":
    main()
