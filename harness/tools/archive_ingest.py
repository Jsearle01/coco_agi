#!/usr/bin/env python3
"""harness/tools/archive_ingest.py -- extract the drop, place the titles, delete the archives.

★★★ NOTHING IS EXTRACTED INTO THE REPOSITORY. Everything lands under the corpus root, which is
outside the repo entirely (§2P: the game data is the user's and never enters the tree). The
archives arrived in the corpus root rather than the repo root, so they were never at risk -- but
they are still deleted at the end, because a .zip beside the corpus is a .zip that can be
copied into the wrong place later.

★★ EXTRACTION GOES TO A STAGING DIRECTORY FIRST, and titles already held are COMPARED rather
than overwritten. Kingquest1/2/3 are already in the corpus and are already pinned in
games/manifests/pc-agi.tsv; silently replacing them would discard a matched provenance row in
favour of an Internet Archive upload of unknown origin. ★ §2B's instinct, applied to data rather
than to an authored asset: do not overwrite something established without checking first.

★ Shapes are decided by archive_survey.py's rule (four DIR files = v2, <prefix>dir + vols = v3,
RESOURCE.* = SCI, otherwise unknown). SCI and unknown directories are NOT placed.
"""
import argparse
import hashlib
import io
import pathlib
import shutil
import sys
import zipfile

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

V2_DIRS = {"logdir", "picdir", "viewdir", "snddir"}

# ★ The archives nest the real game directory under a display name and then use a cryptic inner
# name (BlackCauldron/blackcauld, ManhunterNewyork/mhny). The corpus is flat -- Kingquest1 sits
# at the top -- so the inner name is what gets placed, and these give the cryptic ones a name a
# reader can identify without opening them. ★ Not a classification decision: the shape is still
# read from the DIR files, and nothing here changes a byte.
RENAME = {
    "blackcauld": "BlackCauldron",
    "MOTHER":     "MixedUpMotherGoose",
    "mhny":       "ManhunterNewYork",
    "mhsf":       "ManhunterSanFrancisco",
    "GOLDRUSH":   "GoldRush",
}


def shape_of(names):
    have = V2_DIRS & names
    if len(have) == 4:
        return "v2"
    if any(n.startswith("resource.") for n in names):
        return "SCI"
    v3 = [n for n in names if n.endswith("dir") and n not in V2_DIRS]
    if v3 and any("vol." in n for n in names):
        return "v3"
    return "unknown"


def dirhash(p):
    """A stable digest of a game directory: sorted (name, size, sha256-of-file)."""
    h = hashlib.sha256()
    for f in sorted(p.rglob("*")):
        if f.is_file():
            h.update(f.relative_to(p).as_posix().lower().encode())
            h.update(b"%d" % f.stat().st_size)
            h.update(hashlib.sha256(f.read_bytes()).digest())
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--apply", action="store_true", help="actually place and delete")
    a = ap.parse_args()

    root = pathlib.Path(a.root)
    staging = root / "_incoming"
    archives = sorted(root.glob("*.zip"))
    if not archives:
        print("no archives under %s -- nothing to do" % root)
        return 0

    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    print("extracting %d archives to %s" % (len(archives), staging))
    for z in archives:
        with zipfile.ZipFile(z) as zf:
            zf.extractall(staging)
        print("  %-24s ok" % z.name)

    # ── find every game directory in the staging tree ───────────────────────────────────
    found = []
    for d in sorted(p for p in staging.rglob("*") if p.is_dir()):
        names = {f.name.lower() for f in d.iterdir() if f.is_file()}
        if not names:
            continue
        s = shape_of(names)
        if s in ("v2", "v3"):
            found.append((d, s))

    print()
    print("%-42s %-4s %10s  %s" % ("directory", "type", "bytes", "disposition"))
    place, skip = [], []
    for d, s in found:
        total = sum(f.stat().st_size for f in d.rglob("*") if f.is_file())
        dest = root / RENAME.get(d.name, d.name)
        if dest.exists():
            same = dirhash(dest) == dirhash(d)
            note = ("ALREADY HELD, identical" if same
                    else "★★★ ALREADY HELD, DIFFERENT -- not replaced")
            skip.append((d.name, s, same))
        else:
            note = "place as %s" % dest.name
            place.append((d, dest, s))
        print("%-42s %-4s %10d  %s" % (str(d.relative_to(staging)), s, total, note))

    print()
    if not a.apply:
        print("★ dry run. Re-run with --apply to place %d and delete %d archives."
              % (len(place), len(archives)))
        return 0

    for d, dest, s in place:
        shutil.move(str(d), str(dest))
        print("placed  %-30s (%s)" % (dest.name, s))

    shutil.rmtree(staging, ignore_errors=True)
    for z in archives:
        z.unlink()
        print("deleted %s" % z.name)

    print()
    print("placed %d, already held %d, archives deleted %d"
          % (len(place), len(skip), len(archives)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
