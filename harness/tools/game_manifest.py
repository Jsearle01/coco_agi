#!/usr/bin/env python3
"""game_manifest.py -- identify and measure the pinned AGI corpus (CLAUDE.md §2Q, M-01).

★★ GAME DATA IS THE USER'S AND IS READ-ONLY, ABSOLUTELY (§2P). This tool opens every archive
in 'r' mode and NEVER extracts, never writes into the corpus, and never copies game bytes into
the repository. What it emits is a MANIFEST -- names, checksums, sizes, version identification.
That is what games/manifests/ is for and it is all it may ever hold.

★★ SIZES COME FROM THE ARCHIVE'S OWN CENTRAL DIRECTORY, NOT FROM A PARSER WE WROTE.
§12 forbids writing a VOL/DIR parser this phase, and §2O.1 explains why it would matter later:
anything we author that participates in producing a measurement can be wrong in the same
direction as the thing it is measuring. zipfile reports the UNCOMPRESSED size each archive
records for each member; that is the archive's claim, not our decode.

WHAT IS MEASURED, AND WHAT IS MERELY DERIVED
--------------------------------------------
  MEASURED  (archive metadata, trustworthy)
      sha256 of the zip, member names, per-member uncompressed size, totals.
  DERIVED   (arithmetic on a size, labelled as such -- CLAUDE.md §8: label your own arithmetic)
      resource SLOT counts, from DIR file length / 3. AGI's DIR record is 3 bytes
      [AGI Specs §4], so length/3 is the number of SLOTS. It is an UPPER BOUND on live
      resources: an unused slot is 0xFFFFFF and still occupies its three bytes. Reported as
      'slots', never as 'resources', because they are not the same number.

VERSION IDENTIFICATION -- by archive SHAPE, which is evidence and not proof
--------------------------------------------------------------------------
  v2  separate logdir + picdir + viewdir + snddir, and vol.n
  v3  one combined <prefix>dir, and <prefix>vol.n

★ Shape is a strong signal and it is not a decode. Whether a v3-shaped title actually carries
LZW-compressed resources is settled by running it through the pinned ScummVM, not by this
tool -- see the report's AC-8. A title is reported here as 'v3-shaped'.
"""
import argparse
import hashlib
import pathlib
import sys
import zipfile

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# AD-04: one CoCo3 floppy, 34 usable tracks x 18 sectors x 256 bytes.
ONE_FLOPPY = 156672
# AD-06: the RAM-disk ceiling, ~376 KB.
RAMDISK_CEILING = 376 * 1024

V2_DIRS = ("logdir", "picdir", "viewdir", "snddir")

# ★★ NOT GAME DATA -- EXCLUDED FROM EVERY "DOES IT FIT" FIGURE.
#
# AGIDATA.OVL is Sierra's DOS INTERPRETER OVERLAY, shipped beside the game, not resource data.
# Our CoCo3 interpreter replaces it outright, so counting it against a floppy or a RAM-disk
# budget charges the port for code it will never carry -- 6,656 to 8,192 bytes, in 88 of the
# 150 archives.
#
# Two independent confirmations, because "it looks like interpreter code" is not evidence:
#   1. 62 of the 150 games DO NOT SHIP IT AT ALL and are complete, playable titles. A file
#      absent from 41% of the corpus cannot be required resource data.
#   2. The pinned ScummVM NEVER OPENS IT. Its only mention in engines/agi is a comment in
#      detection_tables.h:238 using the version string inside it to identify an interpreter
#      build. Nothing reads it as a resource.
#
# The full member vocabulary of the corpus is: vol.N, words.tok, object, logdir, picdir,
# viewdir, snddir, agidata.ovl, pal.N, dmvol.N, dmdir, vvol.N, vdir. Everything on that list
# except agidata.ovl is game data.
NOT_GAME_DATA = ("agidata.ovl",)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:                     # 'rb' -- read only, always
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def classify(names):
    """-> ('v2'|'v3-shaped'|'unknown', dir_members, vol_members)"""
    lower = {n.lower(): n for n in names}
    vols = sorted(n for n in lower if ".vol." in n or lower[n].lower().count("vol.") == 1
                  and lower[n].lower().split("vol.")[-1].isdigit())
    # simpler and more robust: any member whose name contains 'vol.' followed by digits
    vols = sorted(n for n in lower if "vol." in n and n.split("vol.")[-1].isdigit())

    if all(d in lower for d in V2_DIRS):
        return "v2", [lower[d] for d in V2_DIRS], [lower[v] for v in vols]

    # v3: exactly one member ending in 'dir', paired with <prefix>vol.n
    dirs = sorted(n for n in lower if n.endswith("dir"))
    if len(dirs) == 1 and vols:
        prefix = dirs[0][:-3]
        if any(v.startswith(prefix) for v in vols):
            return "v3-shaped", [lower[dirs[0]]], [lower[v] for v in vols]

    return "unknown", [lower[d] for d in dirs], [lower[v] for v in vols]


def measure(path):
    with zipfile.ZipFile(path, "r") as zf:          # 'r' -- read only, always
        infos = zf.infolist()
        sizes = {i.filename: i.file_size for i in infos}

    version, dir_members, vol_members = classify(sizes.keys())
    total = sum(sizes.values())
    overlay_bytes = sum(v for k, v in sizes.items() if k.lower() in NOT_GAME_DATA)
    game_bytes = total - overlay_bytes           # ★ the figure the thresholds use
    vol_bytes = sum(sizes[m] for m in vol_members)
    dir_bytes = sum(sizes[m] for m in dir_members)

    slots = {}
    if version == "v2":
        for d in dir_members:
            slots[d.lower()] = sizes[d] // 3        # DERIVED -- see the header

    return {
        "name": path.stem,
        "sha256": sha256_of(path),
        "zip_bytes": path.stat().st_size,
        "version": version,
        "total_uncompressed": total,
        "overlay_bytes": overlay_bytes,
        "game_bytes": game_bytes,
        "vol_bytes": vol_bytes,
        "dir_bytes": dir_bytes,
        "vol_count": len(vol_members),
        "member_count": len(sizes),
        "slots": slots,
    }


def main():
    ap = argparse.ArgumentParser(description="Measure the pinned AGI corpus, read-only.")
    ap.add_argument("corpus", help="directory of game .zip archives")
    ap.add_argument("--out", help="write the TSV index here")
    ap.add_argument("--summary-only", action="store_true")
    args = ap.parse_args()

    root = pathlib.Path(args.corpus)
    zips = sorted(root.glob("*.zip"))
    if not zips:
        print("[manifest] no .zip archives under %s" % root)
        return 1

    rows = [measure(z) for z in zips]
    rows.sort(key=lambda r: r["name"])

    if args.out:
        out = pathlib.Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            "# AGI CORPUS MANIFEST -- generated by harness/tools/game_manifest.py",
            "# ★ MANIFEST ONLY. No game data is in this repository and none ever may be (§2P).",
            "# Sizes are the ARCHIVE's own uncompressed figures, not our decode (§2O.1, §12).",
            "# 'version' is by archive SHAPE; v3-shaped is a signal, not a decode.",
            "# log/pic/view/snd slots are DERIVED as dirlen/3 and are an UPPER BOUND (unused",
            "# slots are 0xFFFFFF and still occupy 3 bytes). Slots are not live resources.",
            "#",
            "\t".join(["name", "sha256", "version", "zip_bytes", "total_uncompressed",
                       "game_bytes", "overlay_bytes", "vol_bytes", "dir_bytes", "vols", "members",
                       "log_slots", "pic_slots", "view_slots", "snd_slots"]),
        ]
        for r in rows:
            s = r["slots"]
            lines.append("\t".join([
                r["name"], r["sha256"], r["version"], str(r["zip_bytes"]),
                str(r["total_uncompressed"]), str(r["game_bytes"]), str(r["overlay_bytes"]),
                str(r["vol_bytes"]), str(r["dir_bytes"]),
                str(r["vol_count"]), str(r["member_count"]),
                str(s.get("logdir", "")), str(s.get("picdir", "")),
                str(s.get("viewdir", "")), str(s.get("snddir", "")),
            ]))
        out.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("[manifest] wrote %s (%d games)" % (out, len(rows)))

    # ---- summary: this is M-01 ----
    totals = sorted(r["game_bytes"] for r in rows)
    n = len(totals)
    median = totals[n // 2] if n % 2 else (totals[n // 2 - 1] + totals[n // 2]) // 2
    by_ver = {}
    for r in rows:
        by_ver[r["version"]] = by_ver.get(r["version"], 0) + 1

    print()
    print("[manifest] %d game(s)" % n)
    print("[manifest] by shape: %s" % ", ".join("%s=%d" % kv for kv in sorted(by_ver.items())))
    print()
    print("  GAME bytes per game (uncompressed, agidata.ovl excluded -- see header)")
    print("    min    %10d  (%s)" % (totals[0], min(rows, key=lambda r: r["game_bytes"])["name"]))
    print("    median %10d" % median)
    print("    max    %10d  (%s)" % (totals[-1], max(rows, key=lambda r: r["game_bytes"])["name"]))
    print("    sum    %10d" % sum(totals))
    print()
    over_floppy = [r for r in rows if r["game_bytes"] > ONE_FLOPPY]
    over_ram = [r for r in rows if r["game_bytes"] > RAMDISK_CEILING]
    print("  exceeding ONE FLOPPY   (%d B, AD-04): %d of %d  (%.0f%%)"
          % (ONE_FLOPPY, len(over_floppy), n, 100.0 * len(over_floppy) / n))
    print("  exceeding RAM-DISK     (%d B, AD-06): %d of %d  (%.0f%%)"
          % (RAMDISK_CEILING, len(over_ram), n, 100.0 * len(over_ram) / n))
    if over_ram:
        print("    over the RAM-disk ceiling:")
        for r in sorted(over_ram, key=lambda r: -r["game_bytes"]):
            print("      %-10s %10d  %s" % (r["name"], r["game_bytes"], r["version"]))

    if not args.summary_only:
        print()
        print("  v3-shaped titles (the LZW / combined-DIR path):")
        for r in rows:
            if r["version"] != "v2":
                print("      %-10s %-12s total=%-9d vols=%d  sha256=%s"
                      % (r["name"], r["version"], r["game_bytes"], r["vol_count"],
                         r["sha256"][:16]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
