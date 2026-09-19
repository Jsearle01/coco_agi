#!/usr/bin/env python3
"""Diff a resource the guest dumped on a checksum mismatch against the game's own bytes.

★★★★★ WHY THIS EXISTS AND WHY IT IS SEPARATE FROM THE CHECKSUM. res_check.s answers "did these
bytes change", which is the question a gate can ask cheaply on every bind. It cannot answer "what
changed them" -- for that you need the bytes on both sides, and the guest has only one of them.

★★★★ P6.46's ANSWER CAME FROM THE OFFSETS, NOT THE MISMATCH. Eight offsets whose values advanced
by whole numbers per cycle is what turned "logic 102 is damaged" into "VM_OPSEEN is at $6400 and
those offsets are opcodes". **A single-offset report would have named a symptom.** So this prints
every differing offset, the delta, and the gaps between them -- the three things that made the
pattern visible -- and it does it from a file rather than from a person reading two hex dumps.

★★★ It is logic_copy_diff.py generalised: that one parses a 256-byte snapshot out of a run log for
a LOGIC, this one takes a full dump of any resource type the checksum watches.

Usage:
    python harness/tools/res_copy_diff.py <dump.bin> <game-dir> <type> <index>
        type: 0=LOGIC 1=PICTURE 2=VIEW 3=SOUND  (res_core.s's RES_* order)
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from volread import logic as logic_mod, resource    # noqa: E402

# ★★ res_core.s's RES_* numbering, which is also the DIR order. Named here rather than assumed:
#    a type number read as the wrong kind would diff against a different resource entirely and
#    report every byte as differing, which reads like catastrophic corruption.
TYPES = {0: "LOGIC", 1: "PICTURE", 2: "VIEW", 3: "SOUND"}


def reference_bytes(game_dir, rtype, index):
    """The reference bytes, and how much of them can honestly be compared.

    Returns (bytes, comparable_length).

    ★★★★★ FOR A LOGIC ONLY THE BYTECODE IS COMPARED, AND THE REASON IS §2H's. The guest holds the
    resource AFTER res_decode, which XORs the message strings in place; the file holds them
    encrypted. The first version compared the raw bytes and reported 1,399 extra differing
    offsets -- the whole message section, every one real and none a corruption -- which very
    nearly buried the eight that mattered. The second XORed from `stringsPos` with the key
    restarting at zero and still reported 1,502, because **the message section has its own header
    and offset table and only the strings are encrypted.**
    ★★★★ SO THE SPAN IS NARROWED RATHER THAN GUESSED. `u16 bytecode length` + the bytecode is
    exact, needs no model of the message layout, and **is the region the instrument exists to
    protect**: executable bytes. Getting the string seam right is a second question and it is not
    this tool's [logic.cpp decodeLogic, at the pin].
    ★★★ The narrowing is PRINTED, not silent -- a comparison scoped by accident is L-88 and a
    comparison scoped on purpose has to say so.
    """
    game = resource.load_from_files(game_dir)
    raw = game.load(TYPES[rtype], index)
    if rtype != 0:
        return raw, len(raw)
    return raw, int.from_bytes(raw[0:2], "little") + 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("game_dir")
    ap.add_argument("type", type=int)
    ap.add_argument("index", type=int)
    ap.add_argument("--max", type=int, default=64, help="offsets to print")
    args = ap.parse_args()

    if args.type not in TYPES:
        print("unknown resource type", args.type)
        return 2

    got = pathlib.Path(args.dump).read_bytes()
    want, comparable = reference_bytes(args.game_dir, args.type, args.index)

    print("%s %d: dump %d bytes, reference %d bytes"
          % (TYPES[args.type], args.index, len(got), len(want)))
    if len(got) != len(want):
        print("  ★★★ LENGTHS DIFFER -- compare the shorter span only")
    n = min(len(got), len(want), comparable)
    if comparable < min(len(got), len(want)):
        print("  ★ comparing the first %d bytes only: u16 length + bytecode. The message section "
              "is XORed in the guest and not in the file, and only the STRINGS are encrypted -- "
              "see reference_bytes()." % comparable)
    diffs = [(o, want[o], got[o]) for o in range(n) if want[o] != got[o]]
    print("differing offsets: %d of %d compared" % (len(diffs), n))
    if not diffs:
        print("  ★ identical over the compared span")
        return 0
    print()
    print("  offset  want  got   delta(got-want)")
    for off, wv, gv in diffs[:args.max]:
        print("  $%04X    %02X    %02X    %+d" % (off, wv, gv, (gv - wv + 256) % 256))
    if len(diffs) > args.max:
        print("  ... %d more" % (len(diffs) - args.max))
    print()
    # ★★★ THE GAPS ARE THE PATTERN. In P6.46 they were 1,1,9,9,1,16,31 -- irregular, which is what
    # says "these are not a contiguous overwrite" and points at an index rather than a memcpy.
    gaps = [b[0] - a[0] for a, b in zip(diffs, diffs[1:])]
    print("  gaps between differing offsets:", gaps[:args.max])
    print("  span: $%04X..$%04X" % (diffs[0][0], diffs[-1][0]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
