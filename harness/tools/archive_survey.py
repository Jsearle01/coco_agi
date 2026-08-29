#!/usr/bin/env python3
"""harness/tools/archive_survey.py -- what is IN the archives, read from the container.

★★ L-53: the dispatch's §4 classification is the Orchestrator's and is to be CONFIRMED, not
trusted. This reads the zip directory without extracting anything, so the shape of each title is
established from the archive itself before a single byte lands on disk.

★★★ SHAPE IS DECIDED BY THE DIRECTORY FILES, NOT BY THE FOLDER NAME. A title is:
    AGI v2   -- four separate DIR files (logdir/picdir/viewdir/snddir), any case
    AGI v3   -- one combined <prefix>dir plus <prefix>vol.n
    SCI      -- RESOURCE.MAP / RESOURCE.nnn
    unknown  -- none of the above
★ Trigger 3 names Black Cauldron specifically: it has a v1 booter release in circulation, and a
v1 title has no DIR files at all. That is why "unknown" is a reported outcome and not an error.

★ §2P: prints names, sizes and counts. No content is read or extracted.
"""
import argparse
import collections
import io
import pathlib
import sys
import zipfile

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

V2_DIRS = {"logdir", "picdir", "viewdir", "snddir"}


def classify(names):
    """names = the file names directly inside one candidate game directory, lowercased."""
    have = V2_DIRS & names
    if len(have) == 4:
        return "AGI v2", ""
    sci = [n for n in names if n.startswith("resource.")]
    if sci:
        return "SCI", "%d resource files" % len(sci)
    # v3: <prefix>dir alongside <prefix>vol.n
    v3 = [n for n in names if n.endswith("dir") and n not in V2_DIRS]
    vols = [n for n in names if "vol." in n]
    if v3 and vols:
        return "AGI v3", "%s + %d vols" % (",".join(sorted(v3)), len(vols))
    if have:
        return "AGI v2?", "only %d of 4 DIR files: %s" % (len(have), ",".join(sorted(have)))
    return "unknown", "no DIR files, no RESOURCE.* (a v1 booter looks like this)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=r"C:\Projects\agi-games\pc")
    a = ap.parse_args()

    root = pathlib.Path(a.root)
    archives = sorted(root.glob("*.zip"))
    if not archives:
        print("no .zip archives under %s" % root)
        return 1

    print("archives under %s" % root)
    for z in archives:
        print("  %-24s %10d bytes" % (z.name, z.stat().st_size))
    print()

    for z in archives:
        print("═" * 78)
        print("%s" % z.name)
        with zipfile.ZipFile(z) as zf:
            infos = zf.infolist()
            # group by the directory that directly contains each file
            bydir = collections.defaultdict(list)
            for i in infos:
                if i.is_dir():
                    continue
                p = pathlib.PurePosixPath(i.filename)
                bydir[str(p.parent)].append((p.name, i.file_size))

            for d in sorted(bydir):
                names = {n.lower() for n, _ in bydir[d]}
                shape, note = classify(names)
                if shape == "unknown" and len(bydir[d]) < 3:
                    continue                     # not a game directory, just loose files
                total = sum(s for _, s in bydir[d])
                vols = sorted(n for n in names if "vol." in n)
                print("  %-46s %-8s %7d files %9d B" % (d, shape, len(bydir[d]), total))
                if vols:
                    print("      vols: %s" % " ".join(vols))
                if note:
                    print("      %s" % note)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
