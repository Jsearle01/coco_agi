"""harness/tools/text_oob.py -- which swept message drives the ORACLE out of bounds. [P6.18]

★★★★★ THE ORACLE SEGFAULTS ON TWO OF THE NINE GATE TITLES under the text sweep -- PoliceQuest1
(exit 139 after 10 messages) and SpaceQuest-2 (exit 139 after 354). ★★★★ A crashed oracle is not a
failed gate and it is not a passed one either: it means the corpus AC-7 can gate today is SEVEN
titles, and saying "nine" would be the L-72 defect (a partial run asserting more than it tested).

★★★★★ THIS TOOL IS OFFLINE AND READS ONLY GAME DATA. It does not run ScummVM, so it cannot be
stopped by the crash it is diagnosing. It walks exactly the messages the sweep walks -- the first
eight non-empty texts of every loadable logic, agi.cpp's `t < _game.logics[nr].numTexts && t < 8`
-- and evaluates each format code against THE ORACLE'S OWN BOUNDS, which are in three cases absent:

    %s  text.cpp:1267  i = strtoul(...)      -- NO -1, NO bound test, indexes strings[25][40]
    %g  text.cpp:1259  logics[0].texts[i-1]  -- NO bound test at all
    %0  text.cpp:1255  objectName(i-1)       -- bound is objectName's, not stringPrintf's
    %m  text.cpp:1272  guarded HIGH only (numTexts > i); i == -1 passes
    %w  text.cpp:1263  getEgoWord(i-1)
    %v  text.cpp:1231  getVar(i) -- vars are 256 and i is a byte, so this one cannot escape

★★★ §2P: COUNTS AND INDICES ONLY. No message is printed, no substring, no hash that could be
matched back to text. A logic number and a message ORDINAL are structure, not content.

★★★★★ IT PREDICTED SPACEQUEST-2 TO THE MESSAGE. The tool says sweep message #355 is the only
out-of-bounds one in the title; the capture drew 354 restores and died. **That is the §2W
demonstration this instrument needed** -- it was not shown able to fail, it was shown able to
name the failure point of a crash that had already happened, which is stronger.

★★★★ AND IT DOES NOT EXPLAIN POLICEQUEST1, which is clean here and died after 10. §2H: the first
mechanism found is real and is not the whole mechanism. `--describe` is what separates them --
it reports the STRUCTURE of one swept message (length, codes, control bytes) without printing it.

usage:  python harness/tools/text_oob.py [title ...]
        python harness/tools/text_oob.py --describe <title> <first-ordinal> [count]
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
from volread import resource, logic as L                          # noqa: E402

GAMES = r"C:\Projects\agi-games\pc"
V2_TITLES = ["Kingquest1", "Kingquest2", "Kingquest3", "SpaceQuest-1", "SpaceQuest-2",
             "PoliceQuest1", "larry1", "BlackCauldron", "MixedUpMotherGoose"]

MAX_STRINGS = 24            # agi.h -- strings[MAX_STRINGS + 1][MAX_STRINGLEN], so valid is 0..24
SWEEP_TEXTS = 8             # agi.cpp -- the sweep's own `t < 8`

FMT = re.compile(rb"%([a-zA-Z0])([0-9]*)")


def swept_messages(g):
    """The sweep's own walk: every loadable logic, its first 8 texts, non-empty ones only."""
    for nr in range(256):
        try:
            raw = g.load("LOGIC", nr)
        except Exception:
            continue
        if raw is None:
            continue
        try:
            lg = L.split(raw, nr)
        except Exception:
            continue
        shown = 0
        for t, m in enumerate(lg.messages):
            if t >= SWEEP_TEXTS:
                break
            if not m:
                continue
            shown += 1
            yield nr, t, m, lg


def describe(title, first, count):
    """★★★ STRUCTURE, NOT CONTENT [§2P]. Length, format codes, control bytes -- never the text."""
    p = title if os.path.isdir(title) else os.path.join(GAMES, title)
    g = resource.load_from_files(p)
    print("%-20s  describing sweep messages #%d..#%d" % (title, first, first + count - 1))
    print("  %6s %6s %5s %7s  %-24s %s" %
          ("ord", "logic", "text", "len", "codes", "control bytes"))
    seen = 0
    for nr, t, m, lg in swept_messages(g):
        seen += 1
        if seen < first:
            continue
        if seen >= first + count:
            break
        codes = ["%" + mo.group(1).decode("latin-1") + mo.group(2).decode("latin-1")
                 for mo in FMT.finditer(m)]
        ctrl = sorted(set(b for b in bytearray(m) if b < 0x20 or b >= 0x7F))
        print("  %6d %6d %5d %7d  %-24s %s" %
              (seen, nr, t, len(m), ",".join(codes) or "-",
               " ".join("%02X" % b for b in ctrl) or "-"))


def main(argv):
    if len(argv) > 1 and argv[1] == "--describe":
        describe(argv[2], int(argv[3]), int(argv[4]) if len(argv) > 4 else 4)
        return
    titles = argv[1:] or V2_TITLES
    for title in titles:
        p = title if os.path.isdir(title) else os.path.join(GAMES, title)
        if not os.path.isdir(p):
            print("%-20s -- no such game dir" % title)
            continue
        g = resource.load_from_files(p)
        try:
            n0 = len(L.split(g.load("LOGIC", 0), 0).messages)
        except Exception:
            n0 = 0

        hits = []
        seen = 0
        for nr, t, m, lg in swept_messages(g):
            seen += 1
            for mo in FMT.finditer(m):
                code = mo.group(1).decode("latin-1")
                num = int(mo.group(2)) if mo.group(2) else 0
                why = None
                if code == "s" and num > MAX_STRINGS:
                    why = "%%s%d indexes strings[%d] -- max is %d" % (num, num, MAX_STRINGS)
                elif code == "g" and not (1 <= num <= n0):
                    why = "%%g%d -> logic0.texts[%d] of %d" % (num, num - 1, n0)
                elif code == "m" and num == 0:
                    why = "%m0 -> texts[-1] (the oracle guards only the high end)"
                elif code == "m" and num > len(lg.messages):
                    why = "%%m%d -> texts[%d] of %d" % (num, num - 1, len(lg.messages))
                if why:
                    hits.append((nr, t, seen, why))

        status = "★★★★ %d OUT-OF-BOUNDS" % len(hits) if hits else "clean"
        print("%-20s  %5d messages swept   %s" % (title, seen, status))
        for nr, t, ordinal, why in hits[:12]:
            print("        logic %-3d text %d   (sweep message #%d)   %s" % (nr, t, ordinal, why))
        if len(hits) > 12:
            print("        ... and %d more" % (len(hits) - 12))


if __name__ == "__main__":
    main(sys.argv)
