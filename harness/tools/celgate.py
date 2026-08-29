#!/usr/bin/env python3
"""harness/tools/celgate.py -- AC-2: the 6809's decoded cels against the pinned oracle's.

★★ THE BASELINE IS THE ORACLE (CLAUDE.md §2O.1). oracle/dumps/cels-<title>/ is what the
instrumented ScummVM's own decodeView() produced; build/cel_sweep/<title>/ is what the 6809
produced from the same VIEW resources. tools/agivm/view.py is NOT consulted here even though it
agrees with both -- it and the 6809 are clients of the same reference, and comparing them to
each other would let both be wrong the same way.

★ PER-TITLE, NEVER A TOTAL (L-10). "6,700 of 6,782 matched" hides which title failed and how.

★★ AND PER-CEL LOCALISATION (§5, L-59): a whole-corpus verdict DETECTS. For every mismatch this
reports the first differing byte, its row and column within the cel, and whether the cel is
mirrored -- because "byte 1,204 differs" and "column 0 of every row differs" are different
defects, and the second names the mirrored walk directly.

★ §2P: cel pixels are copyrighted game content. Counts, offsets and hashes only.
"""
import argparse
import collections
import hashlib
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def load_manifest(p):
    rows = []
    for line in pathlib.Path(p).read_text(errors="replace").splitlines():
        f = line.split()
        if len(f) >= 8 and f[3] != "ERR":
            rows.append(dict(view=int(f[0]), loop=int(f[1]), cel=int(f[2]),
                             w=int(f[3]), h=int(f[4]), key=int(f[5]),
                             mir=int(f[6]), off=int(f[7])))
        elif len(f) == 5 and f[3] == "ERR":
            rows.append(dict(view=int(f[0]), loop=int(f[1]), cel=int(f[2]),
                             err=int(f[4])))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("titles", nargs="+")
    ap.add_argument("--oracle", default="oracle/dumps")
    ap.add_argument("--sweep", default="build/cel_sweep")
    a = ap.parse_args()

    grand = collections.Counter()
    status = 0
    print("%-14s %7s %7s %7s %7s %8s %8s" %
          ("title", "queued", "decoded", "match", "mism", "errors", "mirrored"))
    print("-" * 70)

    for t in a.titles:
        odir = pathlib.Path(a.oracle) / ("cels-" + t)
        sdir = pathlib.Path(a.sweep) / t
        if not (odir / "cels.txt").exists() or not (sdir / "cels.txt").exists():
            print("%-14s  MISSING dump or sweep -- skipped" % t)
            status = 1
            continue

        orows = load_manifest(odir / "cels.txt")
        srows = load_manifest(sdir / "cels.txt")
        oblob = (odir / "cels.bin").read_bytes()
        sblob = (sdir / "cels.bin").read_bytes()

        okey = {(r["view"], r["loop"], r["cel"]): r for r in orows if "off" in r}
        c = collections.Counter()
        failures = []
        for r in srows:
            k = (r["view"], r["loop"], r["cel"])
            c["queued"] += 1
            if "err" in r:
                c["errors"] += 1
                c["err_%d" % r["err"]] += 1
                continue
            c["decoded"] += 1
            o = okey.get(k)
            if o is None:
                c["no_oracle_row"] += 1
                continue
            if (o["w"], o["h"], o["key"], o["mir"]) != (r["w"], r["h"], r["key"], r["mir"]):
                c["meta"] += 1
                if len(failures) < 8:
                    failures.append("view %d loop %d cel %d: META ours %dx%d key=%d mir=%d "
                                    "oracle %dx%d key=%d mir=%d"
                                    % (k[0], k[1], k[2], r["w"], r["h"], r["key"], r["mir"],
                                       o["w"], o["h"], o["key"], o["mir"]))
                continue
            n = r["w"] * r["h"]
            want = oblob[o["off"]:o["off"] + n]
            got = sblob[r["off"]:r["off"] + n]
            if want == got:
                c["match"] += 1
                if r["mir"]:
                    c["mirrored"] += 1
            else:
                c["mism"] += 1
                if len(failures) < 8:
                    d = next(i for i in range(n) if want[i] != got[i])
                    # ★ row and column, not just a flat offset: a column-0 failure is the
                    # mirrored walk and a row-N failure is the row advance, and the flat
                    # number distinguishes neither.
                    failures.append(
                        "view %d loop %d cel %d (%dx%d mir=%d): first diff at byte %d "
                        "= row %d col %d (ours %d, oracle %d)"
                        % (k[0], k[1], k[2], r["w"], r["h"], r["mir"], d,
                           d // r["w"], d % r["w"], got[d], want[d]))

        print("%-14s %7d %7d %7d %7d %8d %8d"
              % (t, c["queued"], c["decoded"], c["match"], c["mism"],
                 c["errors"], c["mirrored"]))
        for f in failures:
            print("      %s" % f)
        errs = sorted(k for k in c if k.startswith("err_"))
        if errs:
            print("      error codes: %s"
                  % ", ".join("%s x%d" % (k.replace("err_", "code "), c[k]) for k in errs))
        if c["mism"] or c["errors"] or c["meta"]:
            status = 1
        grand.update(c)

    print("-" * 70)
    print("%-14s %7d %7d %7d %7d %8d %8d"
          % ("TOTAL", grand["queued"], grand["decoded"], grand["match"],
             grand["mism"], grand["errors"], grand["mirrored"]))
    if grand["decoded"]:
        print("\ncels byte-identical to the oracle: %d / %d queued (%.2f%%)"
              % (grand["match"], grand["queued"],
                 100.0 * grand["match"] / max(1, grand["queued"])))
    return status


if __name__ == "__main__":
    sys.exit(main())
