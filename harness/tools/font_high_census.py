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
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default="C:/Projects/agi-games/pc")
    ap.add_argument("--titles", default=",".join(DEFAULT_TITLES))
    a = ap.parse_args()

    root = pathlib.Path(a.games_root)
    print("glyphs >= 128 in LOGIC messages, per title")
    print("%-22s %8s %8s %8s %7s  %s"
          % ("title", "msgs", "w/ high", "bytes", "logics", "distinct codepoints"))
    broken = 0
    all_cp = collections.Counter()
    for t in [s.strip() for s in a.titles.split(",") if s.strip()]:
        d = root / t
        if not d.is_dir():
            print("%-22s  no directory" % t)
            continue
        game = resource.load_from_files(str(d))
        msgs, hm, hb, cp, lh = scan(game)
        all_cp.update(cp)
        if hm:
            broken += 1
        shown = ", ".join("%d" % c for c, _n in sorted(cp.items())[:8])
        if len(cp) > 8:
            shown += ", ..."
        print("%-22s %8d %8d %8d %7d  %s" % (t, msgs, hm, hb, len(lh), shown or "-"))

    print("")
    print("★ %d of the titles scanned contain at least one message glyph >= 128" % broken)
    if all_cp:
        print("  distinct codepoints across the set: %d" % len(all_cp))
        print("  most frequent: %s"
              % ", ".join("%d x%d" % (c, n) for c, n in all_cp.most_common(10)))
    else:
        print("  NOTHING in the corpus uses the upper half of the font.")
        print("  ★★ That makes a 128-glyph font free FOR THIS CORPUS -- and it is a statement")
        print("     about these titles, not about AGI [L-86]. Inventory names and the")
        print("     vocabulary were not scanned; see this file's header.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
