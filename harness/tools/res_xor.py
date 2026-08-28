#!/usr/bin/env python3
"""harness/tools/res_xor.py -- AC-9: the `Avis Durgan` decode, done on the 6809.

★★★ WHAT IS UNDER TEST AND WHAT IS NOT. The 6809 fetches a LOGIC, finds its message section,
and XORs the strings region in place; the host reads the arena back. Both sides are then split
by tools/volread/ -- the ORACLE does the splitting on both, so a difference can only come from
the decode. ★ If this script split the guest's buffer with its own parser, a matching bug in
both parsers would agree and report a pass.

★★ 2P AND AC-9's OWN RULE: game text is copyrighted. This prints message COUNTS, LENGTHS and
SHA-256 DIGESTS. It never prints, writes or logs a message. The digests are what make the
comparison checkable without the text.

★ The guest's own message count is compared too: it is an independent parse of the same
structure, and a disagreement localises a decode failure to the split rather than to the XOR.
"""
import argparse
import hashlib
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from volread import logic, resource  # noqa: E402

TYPES = ["LOGIC", "PICTURE", "VIEW", "SOUND"]


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

    if a.mode == "emit":
        n = 0
        with (stage / "ops.txt").open("w", encoding="ascii", newline="\n") as f:
            for e in game.dirs["LOGIC"]:
                if e.present and e.volume == a.volume:
                    f.write("5 0 %d\n" % e.index)      # mode 5 = open + decode
                    f.write("3 0 0\n")                 # close, so every one starts at depth 0
                    n += 1
        print("AC-9 scenario: %d LOGIC resources in vol.%d" % (n, a.volume))
        return 0

    rows = []
    with (pathlib.Path(a.sweep) / "fetched.idx").open() as f:
        next(f)
        for line in f:
            rows.append(tuple(int(x) for x in line.strip().split(",")))
    blob = (pathlib.Path(a.sweep) / "fetched.bin").read_bytes()

    pos = 0
    ok = bad = empty = 0
    msgs_total = 0
    mismatches = []
    for op, t, i, st, ln, base, _depth, msgs in rows:
        if op != 5:
            continue
        if st != 0:
            mismatches.append((i, "guest status %d" % st))
            continue
        guest = blob[pos:pos + ln]
        pos += ln

        want = logic.split(game.load("LOGIC", i), index=i, decrypt_strings=True)
        # ★ The guest already applied the XOR, so the oracle must not apply it again here --
        # it only splits. That asymmetry is the whole experiment.
        got = logic.split(guest, index=i, decrypt_strings=False)

        if not want.messages:
            empty += 1
        if got.message_count != want.message_count:
            mismatches.append((i, "messages %d, oracle %d" % (got.message_count,
                                                              want.message_count)))
        elif msgs != want.message_count:
            mismatches.append((i, "guest reported %d messages, parsed %d" % (msgs,
                                                                             want.message_count)))
        elif got.messages != want.messages:
            d = next(k for k in range(len(got.messages)) if got.messages[k] != want.messages[k])
            mismatches.append((i, "message %d differs (%d vs %d bytes)"
                               % (d, len(got.messages[d]), len(want.messages[d]))))
        elif got.bytecode != want.bytecode:
            mismatches.append((i, "★★★ BYTECODE differs -- the XOR ran past the strings region"))
        else:
            ok += 1
            msgs_total += want.message_count

    def digest(pairs):
        h = hashlib.sha256()
        for idx, ms in pairs:
            h.update(b"%d:" % idx)
            for m in ms:
                h.update(b"%d," % len(m))
                h.update(m)
        return h.hexdigest()

    guest_pairs, oracle_pairs = [], []
    pos = 0
    for op, t, i, st, ln, base, _depth, msgs in rows:
        if op != 5 or st != 0:
            continue
        g = blob[pos:pos + ln]
        pos += ln
        guest_pairs.append((i, logic.split(g, index=i, decrypt_strings=False).messages))
        oracle_pairs.append((i, logic.split(game.load("LOGIC", i), index=i).messages))

    gd, od = digest(guest_pairs), digest(oracle_pairs)
    print("game            : %s  vol.%d" % (a.game_dir, a.volume))
    print("LOGIC decoded on the 6809 : %d   (of which %d carry no messages)" % (ok, empty))
    print("messages recovered        : %d" % msgs_total)
    print("bytecode section intact   : %s"
          % ("yes -- no XOR leaked outside the strings region"
             if not any("BYTECODE" in m[1] for m in mismatches) else "★★★ NO"))
    print("sha256 guest-decoded messages : %s" % gd)
    print("sha256 oracle-decoded messages: %s" % od)
    print("digests %s" % ("MATCH" if gd == od else "★★★ DIFFER"))
    print("disagreements   : %d" % len(mismatches))
    for i, why in mismatches[:20]:
        print("  ! LOGIC %3d  %s" % (i, why))
    return 0 if (not mismatches and gd == od) else 1


if __name__ == "__main__":
    sys.exit(main())
