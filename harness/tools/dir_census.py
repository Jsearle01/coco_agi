"""harness/tools/dir_census.py -- how many DIR slots does any title actually have? [P6.22 AC-3]

★★★★★ MAP_DIR_STRIDE RESERVES 1,024 BYTES PER TYPE AND THE COMMENT SAYS "341 slots vs 216 present
max". **216 is nine Sierra titles.** The fan corpus is 150, and a stride cut to fit the Sierra
maximum would be bounded by a number measured on 6% of the available data [L-85: the corpus is part
of the claim].

★★★★ WHAT MUST FIT IS THE DIR FILE'S SIZE IN BYTES, not a slot count -- §2F.3 says the resource map
IS the game's own DIR tables and design §4 loads them verbatim, so the stride has to hold the file.
Each v2 entry is 3 bytes, so bytes = 3 x slots and the two are interchangeable; this reports both
because the map is written in bytes and the comment is written in slots.

★★★ v3 TITLES ARE EXCLUDED, as fan_census.py excludes them [L-22]: v3 keeps a single combined
directory inside the volume rather than four DIR files, so it has no stride to overflow and
counting it would put an unrelated number in the maximum.

★★ §2P: the fan corpus is read from the pinned zips READ-ONLY -- `zipfile.ZipFile(z, "r")` -- and
nothing is extracted. Sizes and counts only; no resource data is emitted.

usage:  python harness/tools/dir_census.py [--fan-only | --sierra-only] [--top N]
"""
import argparse
import os
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

SIERRA = r"C:\Projects\agi-games\pc"
FAN = r"C:\Projects\agi-games\agile-gdx\html\webapp\games"

V2_DIRS = ("logdir", "picdir", "viewdir", "snddir")
ENTRY = 3                       # v2 DIR entry: 3 bytes


# ★★★★★ THE FILE'S SIZE IS NOT WHAT THE TABLE MUST HOLD, AND THE FIRST VERSION OF THIS TOOL
# MEASURED THE WRONG THING. Every v2 DIR is padded to 768 bytes -- 256 entries of 3, which is the
# format's own ceiling because a resource number is a byte -- so "max size" came back as 768 for
# 67 titles including PoliceQuest1 and said nothing at all about how many slots are USED.
# ★★★★ What bounds the stride is the HIGHEST INDEX WITH A PRESENT ENTRY: the table is indexed
# directly (entry N at offset 3N), so a title whose highest present resource is 216 needs 651
# bytes and the $FFFFFF padding above it is not data. **That is the number the map's own comment
# is quoting, and the two differ by 40%.**
# ★★★ An absent entry is $FF $FF $FF [design §4; the loader skips them]. Nothing else is treated
# as absent, because a zero offset is a legitimate resource at the start of volume 0.
EMPTY = b"\xff\xff\xff"


def _scan(blob):
    """-> (highest present index + 1, present count). 0 means the type is entirely absent."""
    hi = 0
    n = 0
    for i in range(len(blob) // ENTRY):
        e = blob[i * ENTRY:(i + 1) * ENTRY]
        if e != EMPTY:
            hi = i + 1
            n += 1
    return hi, n


def dirs_from_folder(path):
    """-> {name: (used_slots, present, filesize)} or None if this is not a v2 title."""
    out = {}
    try:
        names = {n.lower(): n for n in os.listdir(path)}
    except OSError:
        return None
    for d in V2_DIRS:
        if d not in names:
            return None
        fp = os.path.join(path, names[d])
        with open(fp, "rb") as f:
            blob = f.read()
        hi, n = _scan(blob)
        out[d] = (hi, n, len(blob))
    return out


def dirs_from_zip(path):
    """★★ READ-ONLY -- `ZipFile(path, "r")`, and nothing is extracted to disk (§2P)."""
    try:
        with zipfile.ZipFile(path, "r") as zf:
            want = {}
            for i in zf.infolist():
                if i.is_dir():
                    continue
                base = i.filename.rsplit("/", 1)[-1].lower()
                if base in V2_DIRS:
                    want[base] = i.filename
            if len(want) < len(V2_DIRS):
                return None
            out = {}
            for d in V2_DIRS:
                blob = zf.read(want[d])
                hi, n = _scan(blob)
                out[d] = (hi, n, len(blob))
            return out
    except (zipfile.BadZipFile, OSError, KeyError):
        return None


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--sierra", default=SIERRA)
    ap.add_argument("--fan", default=FAN)
    ap.add_argument("--sierra-only", action="store_true")
    ap.add_argument("--fan-only", action="store_true")
    ap.add_argument("--top", type=int, default=8)
    ap.add_argument("--stride", type=int, default=704,
                    help="the proposed stride in bytes; reported against every title")
    a = ap.parse_args(argv)

    rows = []          # (source, title, {name: size})
    skipped_v3 = 0

    if not a.fan_only:
        for name in sorted(os.listdir(a.sierra)):
            p = os.path.join(a.sierra, name)
            if not os.path.isdir(p):
                continue
            d = dirs_from_folder(p)
            if d is None:
                skipped_v3 += 1
                continue
            rows.append(("sierra", name, d))

    if not a.sierra_only:
        for name in sorted(os.listdir(a.fan)):
            if not name.lower().endswith(".zip"):
                continue
            d = dirs_from_zip(os.path.join(a.fan, name))
            if d is None:
                skipped_v3 += 1
                continue
            rows.append(("fan", name[:-4], d))

    if not rows:
        print("★★★★★ NO TITLE YIELDED FOUR v2 DIR FILES -- this measured nothing and prints no")
        print("      maximum. Check the corpus paths before believing any number here.")
        return 1

    def need(d):
        """The bytes this title's largest type actually needs: 3 x (highest present index + 1)."""
        return max(hi for hi, _n, _sz in d.values()) * ENTRY

    worst = {}
    for src, title, d in rows:
        for k, (hi, n, sz) in d.items():
            if hi > worst.get(k, (0, "", "", 0))[0]:
                worst[k] = (hi, title, src, n)

    print("%-10s %8s %8s   %-28s %s" % ("type", "slots", "present", "title", "source"))
    print("-" * 72)
    for k in V2_DIRS:
        hi, title, src, n = worst.get(k, (0, "-", "-", 0))
        print("%-10s %8d %8d   %-28s %s" % (k, hi, n, title, src))
    print("-" * 72)
    gmax = max(need(d) for _, _, d in rows)
    gslots = gmax // ENTRY
    gtitle = [t for _, t, d in rows if need(d) == gmax][0]
    print("HIGHEST PRESENT SLOT ANYWHERE: %d slots = %d bytes   (%s)"
          % (gslots, gmax, gtitle))
    print("  ★ every DIR file on disk is padded to 768 B = 256 slots, the format's own ceiling;")
    print("    what the stride must hold is the USED prefix, not the padding.")

    n_s = sum(1 for r in rows if r[0] == "sierra")
    n_f = sum(1 for r in rows if r[0] == "fan")
    print("coverage: %d Sierra + %d fan = %d v2 titles; %d skipped as not-v2"
          % (n_s, n_f, len(rows), skipped_v3))

    for src in ("sierra", "fan"):
        sub = [r for r in rows if r[0] == src]
        if not sub:
            continue
        m = max(need(d) for _, _, d in sub)
        who = [t for _, t, d in sub if need(d) == m][0]
        print("  %-7s max %3d slots = %4d B  (%s)" % (src, m // ENTRY, m, who))

    print()
    over = [(t, need(d), src) for src, t, d in rows if need(d) > a.stride]
    print("PROPOSED STRIDE %d B = %d slots" % (a.stride, a.stride // ENTRY))
    if over:
        print("★★★★★ %d TITLE(S) EXCEED IT:" % len(over))
        for t, sz, src in sorted(over, key=lambda r: -r[1])[:a.top]:
            print("     %-28s %3d slots = %4d B  (%s)" % (t, sz // ENTRY, sz, src))
        print("★★★★ This is the dispatch's trigger 1: the cut is bounded by real data.")
        return 2
    print("★ no title exceeds it; margin over the largest is %d B = %d slots"
          % (a.stride - gmax, a.stride // ENTRY - gslots))

    print()
    print("highest-present-slot distribution (16-slot buckets):")
    hist = {}
    for _, _, d in rows:
        b = ((need(d) // ENTRY) // 16) * 16
        hist[b] = hist.get(b, 0) + 1
    for b in sorted(hist):
        print("  %3d-%3d : %3d" % (b, b + 15, hist[b]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
