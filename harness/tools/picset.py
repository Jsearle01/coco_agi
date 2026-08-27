#!/usr/bin/env python3
"""T-P0-012 AC-3/AC-4: choose the gated PICTURE set, extract the resources, census the opcodes.

★★ SELECTION IS BIASED TOWARD FILLS ON PURPOSE (L-38). Two buffers can match for different
reasons: in T-P0-011 row 0 agreed with the oracle throughout while the canvas clear colour was
wrong, because with a black canvas no fill could succeed and row 0 was genuinely black on both
sides. A set of simple line-only pictures could pass with the fill subsystem broken. So the set
is weighted by fill count, and the question "what would this comparison look like if fills were
absent?" is answered by AC-3 covering pictures where the answer is 'completely different'.

★ It also includes KQ1 #80 unconditionally, so T-P0-011's result is REPRODUCED rather than
assumed, and it spreads across three games so a per-game quirk cannot hide.

★★ GAME DATA IS READ-ONLY (§2P). This opens the volumes for reading and writes ONLY to the
build tree. No resource bytes are committed.
"""
import argparse
import collections
import io
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from volread import resource  # noqa: E402

OPNAMES = {
    0xF0: "set_visual", 0xF1: "disable_visual", 0xF2: "set_priority",
    0xF3: "disable_priority", 0xF4: "y_corner", 0xF5: "x_corner",
    0xF6: "abs_line", 0xF7: "rel_line", 0xF8: "fill", 0xF9: "set_pattern",
    0xFA: "pattern_brush", 0xFF: "end",
}

# The opcodes the 6809 renderer implements. Anything else must HALT LOUDLY (AC-4).
IMPLEMENTED = {0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xFF}


def census(data):
    """Opcode counts, walking the resource the way the renderer does."""
    ops = collections.Counter()
    i, n = 0, len(data)
    while i < n:
        b = data[i]
        if b < 0xF0:
            i += 1
            continue
        ops[b] += 1
        i += 1
        if b == 0xFF:
            break
        while i < n and data[i] < 0xF0:
            i += 1
    return ops


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--oracle-root", required=True,
                    help="directory holding base-<Game>/picNNN.visual.bin")
    ap.add_argument("--out", required=True, help="build dir for the .res files")
    ap.add_argument("--count", type=int, default=45)
    ap.add_argument("--max-bytes", type=int, default=0x4EF,
                    help="probe's PIC_DATA window: $1200..$16EF")
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    oracle = pathlib.Path(args.oracle_root)

    games = ["Kingquest1", "Kingquest2", "Kingquest3"]
    rows = []
    unimplemented = collections.Counter()

    for g in games:
        game = resource.load_from_files(str(pathlib.Path(args.games_root) / g))
        odir = oracle / ("base-%s" % g)
        for e in game.iter_present("PICTURE"):
            nr = e.index
            if not (odir / ("pic%03d.visual.bin" % nr)).exists():
                continue
            try:
                data = game.load("PICTURE", nr)
            except Exception:
                continue
            ops = census(data)
            bad = [o for o in ops if o not in IMPLEMENTED]
            if bad:
                for o in bad:
                    unimplemented[o] += 1
                continue                      # cannot gate what the renderer halts on
            if len(data) > args.max_bytes:
                continue                      # would overrun the probe's window
            rows.append({
                "game": g, "nr": nr, "bytes": len(data),
                "fills": ops.get(0xF8, 0),
                "lines": ops.get(0xF7, 0) + ops.get(0xF6, 0),
                "corners": ops.get(0xF4, 0) + ops.get(0xF5, 0),
                "ops": {OPNAMES.get(o, hex(o)): c for o, c in sorted(ops.items())},
            })

    print("candidates with oracle dumps, implemented opcodes, and a resource that fits: %d"
          % len(rows))
    if unimplemented:
        print("★ EXCLUDED for unimplemented opcodes (AC-4 lists these):")
        for o, c in unimplemented.most_common():
            print("    %-14s ($%02X)  in %d picture(s)" % (OPNAMES.get(o, "?"), o, c))
    else:
        print("★ no picture used an unimplemented opcode")

    # --- selection: fill-heavy first, spread across games, KQ1 #80 forced in -------------
    per_game = collections.defaultdict(list)
    for r in rows:
        per_game[r["game"]].append(r)
    for g in per_game:
        per_game[g].sort(key=lambda r: (-r["fills"], -r["lines"]))

    chosen, seen = [], set()
    forced = next((r for r in rows if r["game"] == "Kingquest1" and r["nr"] == 80), None)
    if forced:
        chosen.append(forced)
        seen.add((forced["game"], forced["nr"]))
        print("★ KQ1 #80 forced in (reproduces T-P0-011)")

    idx = 0
    while len(chosen) < args.count:
        added = False
        for g in games:
            lst = per_game[g]
            if idx < len(lst):
                r = lst[idx]
                if (r["game"], r["nr"]) not in seen:
                    chosen.append(r)
                    seen.add((r["game"], r["nr"]))
                    added = True
                if len(chosen) >= args.count:
                    break
        if not added and idx > max(len(v) for v in per_game.values()):
            break
        idx += 1

    # --- extract -------------------------------------------------------------------------
    manifest = []
    for r in chosen:
        game = resource.load_from_files(str(pathlib.Path(args.games_root) / r["game"]))
        data = game.load("PICTURE", r["nr"])
        name = "%s-%03d" % (r["game"], r["nr"])
        (out / (name + ".res")).write_bytes(data)
        r["name"] = name
        r["oracle"] = str(oracle / ("base-%s" % r["game"]))
        manifest.append(r)

    (out / "picset.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")

    print()
    print("SELECTED %d pictures across %d games" % (len(manifest),
                                                    len({m["game"] for m in manifest})))
    bygame = collections.Counter(m["game"] for m in manifest)
    for g, c in sorted(bygame.items()):
        f = [m["fills"] for m in manifest if m["game"] == g]
        print("  %-12s %2d pictures   fills min %d / median %d / max %d"
              % (g, c, min(f), sorted(f)[len(f) // 2], max(f)))
    allf = sorted(m["fills"] for m in manifest)
    print("  ★ fill counts across the set: min %d, median %d, max %d, total %d"
          % (allf[0], allf[len(allf) // 2], allf[-1], sum(allf)))
    print("  ★ %d of %d pictures have >= 10 fills -- a fill-light set could pass with the "
          "fill broken (L-38)" % (sum(1 for f in allf if f >= 10), len(allf)))

    used = collections.Counter()
    for m in manifest:
        for k, c in m["ops"].items():
            used[k] += c
    print("  opcodes exercised: %s" % " ".join("%s=%d" % kv for kv in sorted(used.items())))
    never = [OPNAMES[o] for o in IMPLEMENTED if OPNAMES[o] not in used]
    print("  ★ implemented but NOT reached by this set (AC-4): %s" % (", ".join(never) or "none"))
    print("  resources -> %s" % out)


if __name__ == "__main__":
    main()
