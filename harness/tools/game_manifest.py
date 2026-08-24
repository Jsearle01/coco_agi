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


# ═══════════════════════════════════════════════════════════════════════════════════════════
# OS-9 / CoCo3 MODE (P0.4)
# ═══════════════════════════════════════════════════════════════════════════════════════════
#
# ★ ONE ROW PER IMAGE, NOT PER TITLE (dispatch §4.3). The media variants of a title are
# different builds -- measured, see the report's AC-5 -- so a per-title row would average over
# artifacts that genuinely differ and hide the thing worth knowing.
#
# ★★ This mode reads a FILESYSTEM, not AGI resources (§12). It reports which files exist and
# how large they are; it never decodes a LOGIC, PICTURE, VIEW or SOUND.

AGI_DIR_NAMES = ("logdir", "picdir", "viewdir", "snddir")
AGI_OTHER = ("words.tok", "object")

# ★ Sierra's CoCo3 interpreter and the OS-9 host, by name. These are CODE, not game resources,
# and must not be counted as AGI bytes -- our interpreter replaces every one of them. Same
# reasoning that excluded AGIDATA.OVL from the P0.3 figures.
INTERPRETER_NAMES = ("cmds/sierra", "cmds/mnln", "cmds/scrn", "cmds/shdw", "cmds/tocgen")
HOST_PREFIXES = ("cmds/", "modules/")
HOST_NAMES = ("os9boot", "startup", "toc", "toc.txt")


def classify_os9_file(path):
    """-> 'agi' | 'interpreter' | 'host' | 'other'   (path is the in-image path, any case)"""
    low = path.lower()
    base = low.rsplit("/", 1)[-1]
    if base in AGI_DIR_NAMES or base in AGI_OTHER:
        return "agi"
    if base.startswith("vol.") and base[4:].isdigit():
        return "agi"
    if low in INTERPRETER_NAMES:
        return "interpreter"
    if low.startswith(HOST_PREFIXES) or low in HOST_NAMES:
        return "host"
    if base.endswith("dir") and base not in AGI_DIR_NAMES:
        return "agi"                      # v3 combined-DIR shape
    return "other"


def measure_os9(path, os9fs):
    img = os9fs.try_open(path)
    if img is None:
        return None
    files = []
    for name, size, lsn, trunc in img.walk():
        data, short = img.read_file(lsn)
        files.append({
            "name": name,
            "size": size,
            "actual": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "kind": classify_os9_file(name),
            "short": short or len(data) < size,
        })
    files.sort(key=lambda f: f["name"].lower())

    agi = [f for f in files if f["kind"] == "agi"]
    vols = [f for f in agi if f["name"].lower().rsplit("/", 1)[-1].startswith("vol.")]
    dirs = {f["name"].lower().rsplit("/", 1)[-1] for f in agi}
    version = "v2" if all(d in dirs for d in AGI_DIR_NAMES) else (
        "v3-shaped" if any(d.endswith("dir") for d in dirs) else "none")

    return {
        "path": path,
        "sha256": img.sha256(),
        "image_bytes": len(img.data),
        "stride": img.stride,
        "sectors": img.sectors,
        "volume": img.volume,
        "dd_fmt": img.dd_fmt,
        "files": files,
        "file_count": len(files),
        "agi_bytes": sum(f["actual"] for f in agi),
        "agi_files": len(agi),
        "vol_count": len(vols),
        "interp_bytes": sum(f["actual"] for f in files if f["kind"] == "interpreter"),
        "host_bytes": sum(f["actual"] for f in files if f["kind"] == "host"),
        "version": version,
    }


def run_os9(root, out_images, out_files):
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    import os9fs

    root = pathlib.Path(root)
    imgs = sorted(p for p in root.rglob("*")
                  if p.is_file() and p.suffix.lower() in (".dsk", ".par"))
    rows = []
    for p in imgs:
        r = measure_os9(p, os9fs)
        if r is None:
            print("[manifest] NOT OS-9: %s" % p)
            continue
        rows.append(r)

    def rel(p):
        return p.relative_to(root).as_posix()

    if out_images:
        o = pathlib.Path(out_images)
        o.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            "# CoCo3 OS-9 AGI IMAGE MANIFEST -- harness/tools/game_manifest.py --os9",
            "# ★ MANIFEST ONLY. No game data is in this repository and none ever may be (§2P).",
            "# ONE ROW PER IMAGE, not per title: the media variants are different builds.",
            "# agi_bytes counts AGI resources ONLY -- Sierra's interpreter (CMDS/Sierra, MnLn,",
            "# Scrn, Shdw, TOCGen) and the OS-9 host (OS9Boot, MODULES/, shell utilities) are",
            "# CODE our port replaces, and are reported separately.",
            "# stride 512 = DrivePak container (one 256-byte OS-9 sector per 512-byte block).",
            "#",
            "\t".join(["image", "sha256", "image_bytes", "stride", "sectors", "volume",
                       "dd_fmt", "version", "files", "agi_files", "agi_bytes", "vols",
                       "interp_bytes", "host_bytes"]),
        ]
        for r in rows:
            lines.append("\t".join([
                rel(r["path"]), r["sha256"], str(r["image_bytes"]), str(r["stride"]),
                str(r["sectors"]), r["volume"], "0x%02X" % r["dd_fmt"], r["version"],
                str(r["file_count"]), str(r["agi_files"]), str(r["agi_bytes"]),
                str(r["vol_count"]), str(r["interp_bytes"]), str(r["host_bytes"]),
            ]))
        o.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("[manifest] wrote %s (%d images)" % (o, len(rows)))

    if out_files:
        o = pathlib.Path(out_files)
        o.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            "# CoCo3 OS-9 PER-FILE INVENTORY -- harness/tools/game_manifest.py --os9",
            "# ★ sha256 is of the FILE CONTENT read out of the image. Content only: no AGI",
            "# resource is decoded, and no game byte is stored here -- only its digest.",
            "#",
            "\t".join(["image", "file", "kind", "size", "actual", "sha256", "short"]),
        ]
        for r in rows:
            for f in r["files"]:
                lines.append("\t".join([
                    rel(r["path"]), f["name"], f["kind"], str(f["size"]),
                    str(f["actual"]), f["sha256"], "1" if f["short"] else "0",
                ]))
        o.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("[manifest] wrote %s (%d file rows)" % (o, sum(r["file_count"] for r in rows)))

    print()
    print("[manifest] %d image(s), %d file(s)" % (len(rows), sum(r["file_count"] for r in rows)))
    by_stride = {}
    for r in rows:
        by_stride[r["stride"]] = by_stride.get(r["stride"], 0) + 1
    print("[manifest] stride: %s" % ", ".join("%d-byte=%d" % kv for kv in sorted(by_stride.items())))
    empty = [r for r in rows if r["file_count"] == 0]
    print("[manifest] images with zero files: %d" % len(empty))
    return rows


def main():
    ap = argparse.ArgumentParser(description="Measure an AGI corpus, read-only.")
    ap.add_argument("corpus", help="directory of game .zip archives, or of OS-9 images with --os9")
    ap.add_argument("--out", help="write the TSV index here")
    ap.add_argument("--summary-only", action="store_true")
    ap.add_argument("--os9", action="store_true",
                    help="read CoCo3 OS-9 disk images (.dsk/.par) instead of ZIP archives")
    ap.add_argument("--out-files", help="--os9: write the per-file inventory TSV here")
    args = ap.parse_args()

    if args.os9:
        run_os9(args.corpus, args.out, args.out_files)
        return 0

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
