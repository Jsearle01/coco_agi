#!/usr/bin/env python3
"""classify_corpus.py -- THREE-AXIS classification of every corpus row (AD-28).

★★★ WHY THREE AXES. "Is this game v2 or v3?" was answered from the DIRECTORY layout while the
VOLUMES said something else, and every classification before T-P0-005 -- ours and the
Orchestrator's -- reported one axis as the answer. AD-28:

    INTERPRETER VERSION, DIRECTORY FORMAT and VOLUME FORMAT are THREE INDEPENDENT AXES.
    A row that names one of them is not classified.

    dir_format      v2 = four separate LOGDIR/PICDIR/VIEWDIR/SNDDIR
                    v3 = one combined <prefix>DIR
    vol_format      V2 = 5-byte record header
                    V3 = 7-byte header with a compressed length, LZW
    interp_version  the AGI interpreter build, e.g. 0x2440, 0x3149

★★ EACH VALUE CARRIES HOW IT WAS DETERMINED, and a value that cannot be established is left
EMPTY AND FLAGGED, never guessed (L-26). A version established by md5 match against the oracle's
own table and one inferred from file shape are NOT the same claim and must not share a column
value -- so `interp_version` is populated ONLY from an oracle match, and `*_method` says so.

────────────────────────────────────────────────────────────────────────────────────────────
★★ THE DETECTION HASH SCHEME, READ FROM THE SOURCE (L-25) -- NOT ASSUMED
────────────────────────────────────────────────────────────────────────────────────────────
    file    v2 macros pass the literal "logdir"          detection_tables.h:122,127,137
            v3 macros pass an explicit combined-DIR name detection_tables.h:123
                                                          (dmdir, bcdir, grdir, kq4dir, ...)
    span    md5 of the FIRST 5000 BYTES                  advancedDetector.cpp:974 (_md5Bytes)
            AGI does not override it                     agi/detection.cpp:92-97
    size    AD_ENTRY1s(f, md5, size); AD_NO_SIZE = -1 means IGNORE, and a real size IS
            ENFORCED                                     advancedDetector.h:82,98,116
                                                          advancedDetector.cpp:818

★ The size check is why a match here is falsifiable in two dimensions rather than one (L-23):
GAME_PS entries carry a real size, so a file with a colliding digest but a different length
would still be rejected.

★ md5 is the key ScummVM itself indexes on, so this tool matches on md5 and then VERIFIES the
size where the entry gives one. That avoids modelling fourteen macro signatures -- which would
be a second implementation of the table's semantics, and therefore a thing that could be wrong
in its own way.

Read-only over game data (§2P). Emits a manifest; never content.
"""
import argparse
import hashlib
import pathlib
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

MD5_SPAN = 5000                  # advancedDetector.cpp:974
V2_DIR_NAMES = ("logdir", "picdir", "viewdir", "snddir")
SIGNATURE = 0x1234
V2_HEADER_LEN = 5
V3_HEADER_LEN = 7


# ─────────────────────────────────────────────────────────── the oracle's table

class DetectionTable:
    """ScummVM's AGI detection entries, indexed by md5 -- the key it indexes on itself."""

    # ★ FANMADE* MUST BE HERE, AND LEAVING IT OUT WAS A REAL GAP (L-22). A GAME*-only pattern
    # covers 159 entries and misses 208 FANMADE ones -- which is most of what the 150-game fan
    # corpus would ever match. The first run reported "10 of 150 matched" and that figure was
    # an artifact of the parser, not a fact about the corpus.
    ENTRY = re.compile(r'^\s*((?:GAME|FANMADE)[A-Z0-9_]*)\((.*)\)\s*,?\s*$')

    # ★ FANMADE entries carry NO version on the line: it is baked into the macro chain
    # (detection_tables.h:164-177  FANMADE -> FANMADE_F -> FANMADE_LF -> FANMADE_LVFO, ver
    # 0x2917). Variants that take an explicit ver (FANMADE_V, FANMADE_LVFO, FANMADE_SVP) put a
    # 0xNNNN on the line and are picked up by the normal search. So: use the line's version if
    # one is present, else this default -- and record which, because they are different claims.
    FANMADE_DEFAULT_VER = "0x2917"

    def __init__(self, path):
        self.by_md5 = {}
        lines = pathlib.Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
        for i, line in enumerate(lines):
            m = self.ENTRY.match(line)
            if not m:
                continue
            macro, args = m.group(1), m.group(2)
            md5s = re.findall(r'"([0-9a-f]{32})"', args)
            if not md5s:
                continue
            ver = re.search(r'0x([0-9A-Fa-f]{4})\b', args)
            strs = re.findall(r'"([^"]*)"', args)
            # ★ THE FILE SIZE IS A BARE INTEGER ARGUMENT -- AND QUOTED STRINGS MUST BE REMOVED
            # FIRST. An earlier version searched the raw argument list and picked up the YEAR
            # out of an extra like "2.00 1987-05-25", then reported KQ3 as a size mismatch
            # (1987 vs 390) that does not exist. A negative lookbehind on '"' does not save it:
            # the character before the year is a SPACE, inside the string.
            bare = re.sub(r'"[^"]*"', '""', args)
            size = None
            for tok in re.findall(r'(?<![\w.])(\d{2,7})(?![\w.])', bare):
                if not tok.startswith("0"):
                    size = int(tok)
                    break
            if macro.startswith("FANMADE") and not macro.startswith("FANMADE_I"):
                # FANMADE(name, md5): arg 0 is the TITLE and the id is fixed by the macro.
                gid, extra = "agi-fanmade", (strs[0] if strs else "")
            else:
                gid = strs[0] if strs else "?"
                extra = strs[1] if len(strs) > 1 else ""
            # comment lines immediately above carry the human description
            ctx = []
            for back in (2, 1):
                j = i - back
                if j >= 0 and lines[j].strip().startswith("//"):
                    ctx.append(lines[j].strip().lstrip("/ ").strip())
            plat = re.search(r'kPlatform(\w+)', args)
            for md5 in md5s:
                # ★ DUPLICATE md5s EXIST -- the same DIR shipped on several platforms, or the
                # same release listed at two sizes. An earlier version ASSIGNED rather than
                # appended and silently lost every duplicate, shrinking the table without
                # saying so. Keep them all; `lookup` decides between them on size.
                if ver:
                    version, ver_src = "0x" + ver.group(1), "on the entry line"
                elif macro.startswith("FANMADE"):
                    version, ver_src = self.FANMADE_DEFAULT_VER, "FANMADE macro default"
                else:
                    version, ver_src = "", "not on the line"
                self.by_md5.setdefault(md5, []).append({
                    "macro": macro, "gid": gid, "extra": extra,
                    "version": version, "version_source": ver_src,
                    "size": size,
                    "platform": plat.group(1) if plat else "DOS",
                    "comment": " | ".join(ctx),
                })

    def lookup(self, md5, actual_size):
        """-> (entry, note). ★ The size is VERIFIED, not merely reported (advancedDetector.cpp:818).

        ★ Where several entries share an md5, the SIZE is what separates them: candidates are
        tried and the one whose size agrees wins. Only if none agrees is a mismatch reported,
        and then all candidate sizes are named so the disagreement is inspectable.
        """
        cands = self.by_md5.get(md5)
        if not cands:
            return None, "no md5 match"
        for e in cands:
            if e["size"] is None or e["size"] == actual_size:
                return e, "ok"
        return cands[0], "MD5 MATCH BUT SIZE MISMATCH (%s vs %s)" % (
            "/".join(str(c["size"]) for c in cands), actual_size)


# ─────────────────────────────────────────────────────────── the three axes

def classify_dir_format(names_lower):
    """-> ('v2'|'v3'|'none', detection_filename, method)"""
    if all(n in names_lower for n in V2_DIR_NAMES):
        return "v2", names_lower["logdir"], "four separate DIR files present"
    combined = [n for n in names_lower if n.endswith("dir")]
    if len(combined) == 1:
        return "v3", names_lower[combined[0]], "single combined '%s'" % combined[0]
    if combined:
        return "none", None, "ambiguous: %d files end in 'dir'" % len(combined)
    return "none", None, "no DIR files"


def classify_vol_format(vol_bytes, logic0_volume):
    """ScummVM's detectV3VolumeFormat, loader_v2.cpp:72-115 -- ten consecutive records must hold.

    ★ NOT a heuristic of mine. My first attempt asked "does a plausible clen sit at +5?", which
    classified every CoCo3 title as V3 including ones where len == clen, and could not fail
    (L-23). The oracle instead walks ten records and requires each to land where the previous
    one's clen says it will -- a wrong assumption desynchronises within a record or two.
    """
    data = vol_bytes.get(logic0_volume)
    if data is None:
        return "", "logic0 volume %s absent" % logic0_volume
    pos = 0
    for _ in range(10):
        if pos + V3_HEADER_LEN > len(data):
            return "V2", "V3 walk ran past end at record boundary"
        if ((data[pos] << 8) | data[pos + 1]) != SIGNATURE:
            return "V2", "V3 walk hit a bad signature"
        if (data[pos + 2] & 0x7F) != logic0_volume:
            return "V2", "V3 walk hit a wrong volume byte"
        clen = data[pos + 5] | (data[pos + 6] << 8)
        pos += V3_HEADER_LEN + clen
        if pos > len(data):
            return "V2", "V3 walk overran the volume"
        if pos == len(data):
            break
    return "V3", "ten consecutive 7-byte records held (oracle algorithm)"


def md5_first(data, span=MD5_SPAN):
    return hashlib.md5(data[:span]).hexdigest()



# ─────────────────────────────────────────────────────────── corpus walkers

def _blobs_from_dir(d):
    return {q.name: q.read_bytes() for q in pathlib.Path(d).iterdir() if q.is_file()}


def _blobs_from_os9(variant_dir):
    """★ A CoCo3 title spans several images; first occurrence wins, deterministically.
    P2.1 measured 24 duplicate filenames across KQ3/Original's ten sides with ZERO content
    differences, so the rule is safe on this corpus -- and it is stated rather than assumed."""
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    import os9fs
    blobs = {}
    for img_path in sorted(pathlib.Path(variant_dir).iterdir()):
        if img_path.suffix.lower() not in (".dsk", ".par"):
            continue
        img = os9fs.try_open(img_path)
        if img is None:
            continue
        for name, size, lsn, trunc in img.walk():
            base = name.rsplit("/", 1)[-1]
            if base in blobs:
                continue
            data, short = img.read_file(lsn)
            blobs[base] = data
    return blobs


def _blobs_from_zip(z):
    import zipfile
    with zipfile.ZipFile(z, "r") as zf:          # 'r' -- read only, always
        return {i.filename.rsplit("/", 1)[-1]: zf.read(i)
                for i in zf.infolist() if not i.is_dir()}


def classify_row(label, population, blobs, table):
    lower = {n.lower(): n for n in blobs}
    dir_fmt, det_name, dir_method = classify_dir_format(lower)

    vols = {}
    for n in blobs:
        b = n.lower()
        if "vol." in b and b.rsplit("vol.", 1)[-1].isdigit():
            vols[int(b.rsplit("vol.", 1)[-1])] = blobs[n]

    vol_fmt, vol_method = "", "no LOGIC dir"
    if dir_fmt == "v2" and "logdir" in lower and len(blobs[lower["logdir"]]) >= 3:
        ld = blobs[lower["logdir"]]
        logic0_vol = ld[0] >> 4
        off = ((ld[0] << 16) | (ld[1] << 8) | ld[2]) & 0xFFFFF
        if off == 0xFFFFF:
            vol_method = "LOGIC 0 is an empty slot"
        else:
            vol_fmt, vol_method = classify_vol_format(vols, logic0_vol)
    elif dir_fmt == "v3":
        # ★ NOT established: a combined-DIR title's volume layout is not walked this task
        # (v3 support is out of scope, dispatch §10). Left EMPTY and flagged, never guessed.
        vol_method = "combined DIR; v3 volume layout not walked (out of scope)"

    det_md5, det_size, entry, note = "", "", None, "no detection file"
    if det_name:
        d = blobs[det_name]
        det_md5, det_size = md5_first(d), len(d)
        entry, note = table.lookup(det_md5, det_size)

    if entry and note == "ok":
        interp = entry["version"]
        interp_method = "oracle md5+size match; version %s" % entry.get("version_source", "?")
    elif entry:
        interp, interp_method = "", "md5 matched but " + note
    else:
        interp, interp_method = "", "UNMATCHED -- not established"

    return {
        "population": population, "row": label,
        "dir_format": dir_fmt, "dir_method": dir_method,
        "vol_format": vol_fmt, "vol_method": vol_method,
        "interp_version": interp, "interp_method": interp_method,
        "detect_file": det_name or "", "detect_md5": det_md5,
        "detect_bytes": det_size,
        "scummvm_id": entry["gid"] if entry else "",
        "scummvm_extra": entry["extra"] if entry else "",
        "scummvm_platform": entry["platform"] if entry else "",
        "scummvm_comment": entry["comment"] if entry else "",
        "match_note": note,
    }


COLUMNS = ["population", "row", "dir_format", "dir_method", "vol_format", "vol_method",
           "interp_version", "interp_method", "detect_file", "detect_md5", "detect_bytes",
           "scummvm_id", "scummvm_extra", "scummvm_platform", "match_note", "scummvm_comment"]

HEADER_NOTES = [
    "# THREE-AXIS CORPUS CLASSIFICATION (AD-28) -- harness/tools/classify_corpus.py",
    "# * MANIFEST ONLY. No game data here and none ever (§2P).",
    "# dir_format / vol_format / interp_version are INDEPENDENT AXES. Each has a *_method",
    "# saying HOW it was established. An EMPTY value was NOT ESTABLISHED -- never guessed.",
    "# interp_version is populated ONLY from an oracle md5+size match (L-26): a version from",
    "# the oracle's table and one inferred from file shape are different claims.",
    "# Detection hash = md5 of the FIRST 5000 BYTES of the detection file, size enforced where",
    "# the table gives one (advancedDetector.cpp:974 and :818, read not assumed -- L-25).",
    "#",
]


def main():
    ap = argparse.ArgumentParser(description="Three-axis corpus classification (AD-28).")
    ap.add_argument("--tables", default=r"C:\Projects\scummvm\engines\agi\detection_tables.h")
    ap.add_argument("--pc", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--coco3", default=r"C:\Projects\agi-games\coco3")
    ap.add_argument("--fan", default=r"C:\Projects\agi-games\agile-gdx\html\webapp\games")
    ap.add_argument("--out")
    args = ap.parse_args()

    table = DetectionTable(args.tables)
    print("[classify] detection table: %d md5 keys, %d entries"
          % (len(table.by_md5), sum(len(v) for v in table.by_md5.values())))

    rows = []

    pc = pathlib.Path(args.pc)
    if pc.exists():
        for d in sorted(pc.iterdir()):
            if d.is_dir():
                rows.append(classify_row(d.name, "PC/DOS", _blobs_from_dir(d), table))

    co = pathlib.Path(args.coco3)
    if co.exists():
        for title in sorted(co.iterdir()):
            if not title.is_dir() or title.name.startswith("_"):
                continue
            for variant in sorted(title.iterdir()):
                if variant.is_dir():
                    lbl = "%s/%s" % (title.name.split(" (")[0], variant.name)
                    rows.append(classify_row(lbl, "CoCo3", _blobs_from_os9(variant), table))

    fan = pathlib.Path(args.fan)
    if fan.exists():
        for z in sorted(fan.glob("*.zip")):
            rows.append(classify_row(z.stem, "fan", _blobs_from_zip(z), table))

    if args.out:
        out = pathlib.Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        lines = list(HEADER_NOTES)
        lines.append("\t".join(COLUMNS))
        for r in rows:
            lines.append("\t".join(str(r[c]).replace("\t", " ") for c in COLUMNS))
        out.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("[classify] wrote %s (%d rows)" % (out, len(rows)))

    matched = [r for r in rows if r["interp_version"]]
    print()
    print("[classify] rows=%d   oracle-matched=%d   unmatched=%d"
          % (len(rows), len(matched), len(rows) - len(matched)))
    print()
    print("  %-8s %5s %8s %7s %7s %8s" % ("pop", "rows", "matched", "volV2", "volV3", "vol??"))
    for pop in ("PC/DOS", "CoCo3", "fan"):
        sub = [r for r in rows if r["population"] == pop]
        if not sub:
            continue
        print("  %-8s %5d %8d %7d %7d %8d"
              % (pop, len(sub), sum(1 for r in sub if r["interp_version"]),
                 sum(1 for r in sub if r["vol_format"] == "V2"),
                 sum(1 for r in sub if r["vol_format"] == "V3"),
                 sum(1 for r in sub if not r["vol_format"])))

    print()
    print("  dir_format:  " + ", ".join(
        "%s=%d" % (k, sum(1 for r in rows if r["dir_format"] == k))
        for k in ("v2", "v3", "none")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
