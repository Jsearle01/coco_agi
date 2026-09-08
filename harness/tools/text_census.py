"""harness/tools/text_census.py -- what the text corpus actually CONTAINS, per title. [P6.18 AC-7]

★★★★★ "596 MESSAGES" IS A CLAIM ABOUT ONE TITLE, and L-85 is the standing lesson that a fixed
sample which always passes is evidence about the sample first. This counts the whole staged set so
the gate's coverage can be stated as a corpus rather than as a number.

★★★★ IT COUNTS, IT DOES NOT PRINT. §2P: the game text is the user's and is copyrighted. Every
output here is a COUNT or a FORMAT CODE -- never a message, never a substring of one, never a hash
of one that could be matched back. ★★★ Patch 0010 omits the character code for exactly this reason
and this tool omits the same thing; a substituted string is still game text [§2P].

★★★ The format-code histogram is what makes the census actionable rather than decorative: it says
which of stringPrintf's six codes the gate has never executed. `%0` and `%s` are modelled as empty
in PrintfState because Kingquest1 uses neither, and this is the instrument that finds out whether
any title does.

usage:  python harness/tools/text_census.py [game-dir ...]
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
from volread import resource, logic as L                          # noqa: E402

GAMES = r"C:\Projects\agi-games\pc"

# ★★ The nine v2 gate titles -- the same set vm_run.ps1 declares as $VM_GATE_TITLES, so the text
# corpus and the VM corpus are the same corpus and a title cannot be in one and not the other.
V2_TITLES = ["Kingquest1", "Kingquest2", "Kingquest3", "SpaceQuest-1", "SpaceQuest-2",
             "PoliceQuest1", "larry1", "BlackCauldron", "MixedUpMotherGoose"]

CODES = ["v", "0", "g", "w", "s", "m"]
CODE_RE = re.compile(rb"%(.)")


def census(path):
    g = resource.load_from_files(path)
    n_logics = n_msgs = n_fmt = n_esc = n_trailing_esc = 0
    longest = 0
    hist = dict((c, 0) for c in CODES)
    unknown = {}

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
        n_logics += 1
        for m in lg.messages:
            if not m:
                continue
            n_msgs += 1
            longest = max(longest, len(m))
            if b"\\" in m:
                n_esc += 1
                # ★★★ divergence C in text.py: a message ENDING in a backslash makes the oracle
                # walk past its own terminator. This is the count that says whether that path is
                # reachable from real game data at all.
                if m.endswith(b"\\"):
                    n_trailing_esc += 1
            if b"%" not in m:
                continue
            n_fmt += 1
            for mo in CODE_RE.finditer(m):
                c = mo.group(1).decode("latin-1")
                if c in hist:
                    hist[c] += 1
                else:
                    unknown[c] = unknown.get(c, 0) + 1
    return dict(logics=n_logics, msgs=n_msgs, fmt=n_fmt, esc=n_esc,
                trailing=n_trailing_esc, longest=longest, hist=hist, unknown=unknown)


def main(argv):
    titles = argv[1:] or V2_TITLES
    hdr = "%-20s %7s %7s %7s %8s" % ("title", "logics", "msgs", "w/ %", "longest")
    hdr += "".join("%6s" % ("%" + c) for c in CODES) + "%7s%7s" % ("esc", "trail\\")
    print(hdr)
    print("-" * len(hdr))

    tot = dict((c, 0) for c in CODES)
    t_msgs = t_fmt = t_esc = t_trail = 0
    covered = 0
    for t in titles:
        p = t if os.path.isdir(t) else os.path.join(GAMES, t)
        if not os.path.isdir(p):
            print("%-20s  -- no such game dir, skipped" % t)
            continue
        r = census(p)
        covered += 1
        row = "%-20s %7d %7d %7d %8d" % (t, r["logics"], r["msgs"], r["fmt"], r["longest"])
        row += "".join("%6d" % r["hist"][c] for c in CODES)
        row += "%7d%7d" % (r["esc"], r["trailing"])
        print(row)
        for c in CODES:
            tot[c] += r["hist"][c]
        t_msgs += r["msgs"]
        t_fmt += r["fmt"]
        t_esc += r["esc"]
        t_trail += r["trailing"]
        if r["unknown"]:
            # ★★ An unrecognised code is NOT an error -- stringPrintf's default branch consumes it
            # and emits nothing (text.cpp:1275). It is reported because a code appearing in real
            # data that the reference silently drops is worth knowing about.
            print("%-20s   unrecognised codes (consumed, nothing emitted): %s" %
                  ("", ", ".join("%%%s x%d" % (k, v) for k, v in sorted(unknown_items(r)))))

    print("-" * len(hdr))
    row = "%-20s %7s %7d %7d %8s" % ("TOTAL (%d titles)" % covered, "", t_msgs, t_fmt, "")
    row += "".join("%6d" % tot[c] for c in CODES)
    row += "%7d%7d" % (t_esc, t_trail)
    print(row)

    print()
    never = [c for c in CODES if tot[c] == 0]
    if never:
        print("★★★ NEVER EXERCISED by any staged title: %s" %
              ", ".join("%" + c for c in never))
        print("    -> PrintfState models these as empty and the corpus cannot contradict it.")
    else:
        print("★ every stringPrintf code appears in the corpus.")
    if t_trail == 0:
        print("★★ no message ends in a backslash -> text.py divergence C is UNREACHABLE from this")
        print("   corpus, and the port may bounds-check freely.")
    else:
        print("★★★★ %d messages end in a backslash -> divergence C IS reachable; the port's choice"
              % t_trail)
        print("   there is load-bearing and must be decided, not defaulted.")


def unknown_items(r):
    return r["unknown"].items()


if __name__ == "__main__":
    main(sys.argv)
