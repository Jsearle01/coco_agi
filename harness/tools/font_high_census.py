#!/usr/bin/env python3
"""harness/tools/font_high_census.py -- how many titles use glyphs >= 128?

★★★★★ THE QUESTION THIS ANSWERS. The message box does not fit: the probe's map is 48 bytes short
and the cheapest way out is halving the font from 256 glyphs to 128, which costs 1,024 bytes and
breaks any text using the IBM CP437 upper half -- the box-drawing and accented characters.
**"Would that break anything?" is a corpus fact, not a judgement call**, so it is measured.

★★★★ WHAT IS SCANNED, AND WHY IT IS THE RIGHT SET. Every message of every LOGIC of every pinned
title. Messages are what `print`, `display` and `print.at` render, so they are where a high glyph
would actually reach the font. ★★★ Inventory names and the vocabulary are NOT scanned and are
named here as a gap rather than left implied -- they render through the same font, so a clean
result here is necessary and not sufficient.

★★★ res_decode has already run inside volread, so these bytes are plaintext and not the
"Avis Durgan" XOR. A census over ciphertext would find high bytes everywhere and mean nothing.

★★ §2P: counts, codepoint NUMBERS and message indices only. No message text is printed, ever.

usage:
  python harness/tools/font_high_census.py [--titles A,B] [--games-root DIR]
"""
import argparse
import collections
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# ★★★★ IMPORTED BEFORE stdout IS WRAPPED, AND THE ORDER IS LOAD-BEARING. opcode_census re-wraps
# sys.stdout at ITS import; doing that after we wrap drops the last reference to our wrapper,
# which finalises it and CLOSES the shared buffer -- every later print then dies with "I/O
# operation on closed file". ★★ Measured the hard way: the fan sweep printed its header and then
# threw on the first result row.
try:
    from opcode_census import blobs_from_zip                 # noqa: E402
except Exception:                                            # noqa: BLE001
    blobs_from_zip = None

# ★★★ reconfigure(), NOT a new TextIOWrapper. Two modules each replacing sys.stdout with a fresh
# wrapper over the same buffer is a use-after-close: whichever wrapper loses its last reference is
# finalised and closes the buffer out from under the other. reconfigure mutates in place and has
# no second object to orphan.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from volread import logic as logic_mod, resource   # noqa: E402

DEFAULT_TITLES = ("Kingquest1", "Kingquest2", "Kingquest3", "SpaceQuest-1", "SpaceQuest-2",
                  "PoliceQuest1", "larry1", "BlackCauldron", "MixedUpMotherGoose")


def scan(game):
    msgs = high_msgs = high_bytes = 0
    codepoints = collections.Counter()
    logics_hit = set()
    for nr in range(256):
        try:
            raw = game.load("LOGIC", nr)
        except Exception:                                   # noqa: BLE001
            continue
        if raw is None:
            continue
        try:
            lg = logic_mod.split(raw, index=nr)
        except Exception:                                   # noqa: BLE001
            continue
        for m in lg.messages:
            if isinstance(m, str):
                m = m.encode("latin-1", "replace")
            if not m:
                continue
            msgs += 1
            hits = [b for b in m if b >= 0x80]
            if hits:
                high_msgs += 1
                high_bytes += len(hits)
                logics_hit.add(nr)
                codepoints.update(hits)
    return msgs, high_msgs, high_bytes, codepoints, logics_hit


def os9_titles(root):
    """Yield (label, blobs) for every CoCo3 OS-9 release under `root`.

    ★★★★★ THESE ARE THE MOST RELEVANT TITLES THERE ARE and they are not in the pinned set:
    Sierra's OWN CoCo3 AGI releases, the actual target platform. If any game were going to use
    the upper half of a CoCo3 font it would be one of these.
    ★★★ Reuses classify_corpus._blobs_from_os9 rather than opening the images here [§2F]. os9fs
    is read-only by construction -- "a tool that opens a game image for writing is a bug" -- and
    §2P makes that non-negotiable.
    ★★ One variant per title: the images are the same game packaged for different media, so
    scanning all five would report each title five times and inflate a count nobody could read.
    """
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import classify_corpus                                  # noqa: E402
    for game_dir in sorted(p for p in pathlib.Path(root).iterdir() if p.is_dir()):
        if game_dir.name.startswith("_"):
            continue
        variants = sorted(p for p in game_dir.iterdir() if p.is_dir())
        pick = next((v for v in variants if "floppy" in v.name.lower()), None) or \
               (variants[0] if variants else None)
        if pick is None:
            continue
        try:
            blobs = classify_corpus._blobs_from_os9(pick)
        except Exception as exc:                            # noqa: BLE001
            yield game_dir.name, None, str(exc).strip()
            continue
        yield game_dir.name, blobs, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default="C:/Projects/agi-games/pc")
    ap.add_argument("--titles", default=",".join(DEFAULT_TITLES))
    ap.add_argument("--os9-root", default="",
                    help="census Sierra's CoCo3 OS-9 releases instead of a PC directory")
    # ★★★★ 150 FAN GAMES, which is the largest non-pinned population available and the one most
    # likely to contain a CP437 box-drawing character: fan authors were not constrained by
    # Sierra's own house style. **This is the set that can actually falsify "the upper half is
    # unused"**, where the pinned nine can only fail to.
    ap.add_argument("--fan-root", default="",
                    help="census the fan-game zips (150 titles)")
    ap.add_argument("--quiet", action="store_true", help="only print titles that HAVE high glyphs")
    a = ap.parse_args()

    root = pathlib.Path(a.games_root)
    print("glyphs >= 128 in LOGIC messages, per title")
    print("%-22s %8s %8s %8s %7s  %s"
          % ("title", "msgs", "w/ high", "bytes", "logics", "distinct codepoints"))
    broken = 0
    scanned = 0
    unscannable = []
    all_cp = collections.Counter()
    if a.fan_root:
        sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
        from opcode_census import blobs_from_zip           # noqa: E402
        zips = sorted(pathlib.Path(a.fan_root).glob("*.zip"))
        for z in zips:
            try:
                game = resource.load_from_blobs(blobs_from_zip(z), z.stem)
                msgs, hm, hb, cp, lh = scan(game)
            except Exception as exc:                        # noqa: BLE001
                unscannable.append("%s (%s)" % (z.stem, str(exc).strip()[:60]))
                continue
            scanned += 1
            all_cp.update(cp)
            if hm:
                broken += 1
            if hm or not a.quiet:
                print("%-22s %8d %8d %8d %7d  %s"
                      % (z.stem[:22], msgs, hm, hb, len(lh),
                         ", ".join("%d" % c for c, _n in sorted(cp.items())[:8]) or "-"))
        print("")
        print("★ %d zips found; %d scanned; %d NOT scannable" % (len(zips), scanned,
                                                                 len(unscannable)))
        print("★ %d of the %d scanned use a glyph >= 128" % (broken, scanned))
        if all_cp:
            print("  most frequent codepoints: %s"
                  % ", ".join("%d x%d" % (c, n) for c, n in all_cp.most_common(12)))
        elif scanned == 0:
            print("  ★★★ NO TITLE WAS SCANNED -- this establishes nothing.")
        return 0

    if a.os9_root:
        for label, blobs, err in os9_titles(a.os9_root):
            short = label[:22]
            if blobs is None:
                print("%-22s %8s  NOT SCANNED -- %s" % (short, "-", err))
                unscannable.append(label)
                continue
            try:
                game = resource.load_from_blobs(blobs, label)
            except Exception as exc:                        # noqa: BLE001
                print("%-22s %8s  NOT SCANNED -- %s"
                      % (short, "-", str(exc).strip()))
                unscannable.append(label)
                continue
            msgs, hm, hb, cp, lh = scan(game)
            scanned += 1
            all_cp.update(cp)
            if hm:
                broken += 1
            shown = ", ".join("%d" % c for c, _n in sorted(cp.items())[:8])
            print("%-22s %8d %8d %8d %7d  %s" % (short, msgs, hm, hb, len(lh), shown or "-"))
        print("")
        if unscannable:
            print("★★★ %d NOT SCANNED and therefore UNKNOWN, not clean: %s"
                  % (len(unscannable), ", ".join(unscannable)))
        print("★ %d of %d scanned use a glyph >= 128" % (broken, scanned))
        if all_cp:
            print("  most frequent: %s"
                  % ", ".join("%d x%d" % (c, n) for c, n in all_cp.most_common(10)))
        elif scanned == 0:
            print("  ★★★ NO TITLE WAS SCANNED -- this establishes nothing.")
        else:
            print("  Nothing in the %d title(s) scanned uses the upper half." % scanned)
        return 0

    for t in [s.strip() for s in a.titles.split(",") if s.strip()]:
        d = root / t
        if not d.is_dir():
            print("%-22s  no directory" % t)
            continue
        # ★★★★ A TITLE THAT CANNOT BE LOADED IS REPORTED, NOT FATAL, AND NOT COUNTED AS CLEAN.
        # volread is v2-only this phase [design §11.1], so a v3 title raises here. The first
        # version let that exception kill the whole sweep, which would have been read as "the
        # census found nothing" -- **an unscannable title is an UNKNOWN, and the difference
        # between unknown and clean is the whole point of running this** [§2W].
        try:
            game = resource.load_from_files(str(d))
        except Exception as exc:                            # noqa: BLE001
            reason = str(exc).strip()
            print("%-22s %8s  NOT SCANNED -- %s" % (t, "-", reason))
            unscannable.append(t)
            continue
        msgs, hm, hb, cp, lh = scan(game)
        scanned += 1
        all_cp.update(cp)
        if hm:
            broken += 1
        shown = ", ".join("%d" % c for c, _n in sorted(cp.items())[:8])
        if len(cp) > 8:
            shown += ", ..."
        print("%-22s %8d %8d %8d %7d  %s" % (t, msgs, hm, hb, len(lh), shown or "-"))

    print("")
    if unscannable:
        print("★★★ %d title(s) NOT SCANNED and therefore UNKNOWN, not clean: %s"
              % (len(unscannable), ", ".join(unscannable)))
    print("★ %d of the titles scanned contain at least one message glyph >= 128" % broken)
    if all_cp:
        print("  distinct codepoints across the set: %d" % len(all_cp))
        print("  most frequent: %s"
              % ", ".join("%d x%d" % (c, n) for c, n in all_cp.most_common(10)))
    elif scanned == 0:
        # ★★★★★ ZERO SCANNED IS NOT ZERO FOUND, AND THE FIRST VERSION SAID IT WAS. Run over six
        # titles that volread cannot open, it printed "NOTHING in the corpus uses the upper half
        # of the font" -- a clean bill of health for a sweep that read no bytes at all.
        # **A summary that cannot distinguish "looked and found none" from "could not look" is
        # the same defect as a filter that accepts every row** [§2W].
        print("  ★★★ NO TITLE WAS SCANNED. This run establishes NOTHING about the font --")
        print("      it is not evidence of absence, it is absence of evidence.")
    else:
        print("  NOTHING in the %d title(s) scanned uses the upper half of the font." % scanned)
        print("  ★★ That makes a 128-glyph font free FOR THOSE TITLES -- and it is a statement")
        print("     about them, not about AGI [L-86]. Inventory names and the")
        print("     vocabulary were not scanned; see this file's header.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
