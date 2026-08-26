#!/usr/bin/env python3
"""AC-2: compare tools/agivm/view.py's decoded cels against the PINNED ORACLE's.

★★ THE BASELINE IS THE ORACLE (CLAUDE.md §2O.1). The oracle dumps its OWN rawBitmap buffers
(patch 0006); this tool decodes the same VIEW resources independently and compares. There is no
golden file, and none may ever be introduced: a stored copy of our own output would let both
sides be wrong the same way and report green for ever.

★ §2P: a decoded cel is copyrighted game content. This prints COUNTS and HASHES. It never
writes cel bytes anywhere, and nothing it produces is committed.

Per-game counts, not just a total (L-10): a decoder that fails on one game and passes four
others is a different fact from a uniform pass, and a total hides it.

Usage:
    python harness/tools/celcheck.py <dump-dir> [<dump-dir> ...] --games-root DIR
"""
import argparse
import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from agivm import view as view_mod      # noqa: E402
from volread import resource            # noqa: E402


def load_manifest(path):
    rows = []
    for line in path.read_text(encoding="ascii").splitlines():
        if not line.strip():
            continue
        f = line.split()
        if len(f) != 8:
            raise SystemExit("bad manifest line: %r" % line)
        rows.append({
            "view": int(f[0]), "loop": int(f[1]), "cel": int(f[2]),
            "w": int(f[3]), "h": int(f[4]), "key": int(f[5]),
            "mirrored": bool(int(f[6])), "offset": int(f[7]),
        })
    return rows


def check_game(dump_dir, game_dir, version):
    manifest = load_manifest(dump_dir / "cels.txt")
    blob = (dump_dir / "cels.bin").read_bytes()
    game = resource.load_from_files(str(game_dir))

    stats = {"cels": 0, "match": 0, "mismatch": 0, "mirrored": 0, "mirrored_match": 0,
             "views": set(), "missing_view": 0, "decode_error": 0, "meta_mismatch": 0}
    failures = []

    # decode each view ONCE, then walk its cels in manifest order
    decoded = {}
    for row in manifest:
        vn = row["view"]
        if vn not in decoded:
            try:
                raw = game.load("VIEW", vn)
                decoded[vn] = view_mod.decode_view(raw, version=version, view_nr=vn)
            except Exception as exc:                       # noqa: BLE001
                decoded[vn] = exc
        v = decoded[vn]
        stats["views"].add(vn)
        stats["cels"] += 1
        if row["mirrored"]:
            stats["mirrored"] += 1

        if isinstance(v, Exception):
            stats["decode_error"] += 1
            if len(failures) < 6:
                failures.append("view %d: decode failed: %s" % (vn, v))
            continue

        if row["loop"] >= len(v.loops) or row["cel"] >= len(v.loops[row["loop"]].cels):
            stats["missing_view"] += 1
            if len(failures) < 6:
                failures.append("view %d loop %d cel %d: not produced by our decoder"
                                % (vn, row["loop"], row["cel"]))
            continue

        cel = v.loops[row["loop"]].cels[row["cel"]]
        size = row["w"] * row["h"]
        want = blob[row["offset"]:row["offset"] + size]

        # metadata first -- a width/height/mirror disagreement explains a byte mismatch and
        # is a different defect from a wrong RLE expansion
        if (cel.width, cel.height, cel.clear_key, cel.mirrored) != \
           (row["w"], row["h"], row["key"], row["mirrored"]):
            stats["meta_mismatch"] += 1
            if len(failures) < 6:
                failures.append(
                    "view %d loop %d cel %d: meta ours=(%d,%d,key=%d,mir=%s) "
                    "oracle=(%d,%d,key=%d,mir=%s)"
                    % (vn, row["loop"], row["cel"], cel.width, cel.height, cel.clear_key,
                       cel.mirrored, row["w"], row["h"], row["key"], row["mirrored"]))
            continue

        if bytes(cel.pixels) == want:
            stats["match"] += 1
            if row["mirrored"]:
                stats["mirrored_match"] += 1
        else:
            stats["mismatch"] += 1
            if len(failures) < 6:
                diff_at = next((i for i in range(size)
                                if cel.pixels[i] != want[i]), -1)
                failures.append(
                    "view %d loop %d cel %d (%dx%d mir=%s): first byte differs at %d "
                    "(ours %d, oracle %d)"
                    % (vn, row["loop"], row["cel"], row["w"], row["h"], row["mirrored"],
                       diff_at, cel.pixels[diff_at], want[diff_at]))

    return stats, failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dumps", nargs="+")
    ap.add_argument("--version", default="0x2917")
    args = ap.parse_args()

    total = {"cels": 0, "match": 0, "mismatch": 0, "mirrored": 0, "mirrored_match": 0,
             "views": 0, "missing_view": 0, "decode_error": 0, "meta_mismatch": 0}
    rows = []
    status = 0

    for d in args.dumps:
        dump_dir = pathlib.Path(d)
        name = dump_dir.name.replace("cels-", "")
        game_dir = dump_dir.parent / "__missing__"
        for cand in (pathlib.Path(r"C:\Projects\agi-games\pc") / name,
                     pathlib.Path(r"C:\Projects\agi-games\_scratch\p5cels") / name):
            if cand.is_dir():
                game_dir = cand
                break
        if not game_dir.is_dir():
            print("  %-12s NO GAME DIR -- skipped" % name)
            status = 1
            continue
        if not (dump_dir / "cels.txt").exists():
            # ★ Skip loudly, never silently: a dump directory with no manifest means the run
            # produced nothing, and treating that as "nothing to check" would shrink the
            # sample without saying so (L-22).
            print("  %-12s NO cels.txt in %s -- skipped" % (name, dump_dir))
            status = 1
            continue

        # version per game, from the P1.2 classification where it matters
        ver = 0x2440 if name == "Kingquest3" else int(args.version, 0)
        st, failures = check_game(dump_dir, game_dir, ver)
        rows.append((name, ver, st, failures))
        for k in total:
            if k == "views":
                total[k] += len(st["views"])
            else:
                total[k] += st[k]
        if st["mismatch"] or st["decode_error"] or st["missing_view"] or st["meta_mismatch"]:
            status = 1

    print("%-12s %-7s %6s %6s %8s %8s %9s %8s %8s"
          % ("game", "ver", "views", "cels", "match", "mismatch", "mirrored", "mir-ok", "errors"))
    print("-" * 82)
    for name, ver, st, _ in rows:
        print("%-12s 0x%04X %6d %6d %8d %8d %9d %8d %8d"
              % (name, ver, len(st["views"]), st["cels"], st["match"], st["mismatch"],
                 st["mirrored"], st["mirrored_match"],
                 st["decode_error"] + st["missing_view"] + st["meta_mismatch"]))
    print("-" * 82)
    print("%-12s %-6s %6d %6d %8d %8d %9d %8d %8d"
          % ("TOTAL", "", total["views"], total["cels"], total["match"], total["mismatch"],
             total["mirrored"], total["mirrored_match"],
             total["decode_error"] + total["missing_view"] + total["meta_mismatch"]))

    for name, _, st, failures in rows:
        if failures:
            print()
            print("  %s -- first failures:" % name)
            for f in failures:
                print("    %s" % f)

    print()
    if total["cels"]:
        print("cel bytes agreeing with the oracle: %d / %d (%.2f%%)"
              % (total["match"], total["cels"], 100.0 * total["match"] / total["cels"]))
    return status


if __name__ == "__main__":
    sys.exit(main())
