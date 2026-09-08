"""harness/tools/text_tail.py -- what does the RUNNING GAME draw, after the sweep ends? [P6.19]

★★★★★ THE SWEEP IS NOT THE ONLY THING IN THE LOG. patch 0010 logs every drawCharacter for the
whole session, and text_gate.py cuts the log at the LAST restore rectangle because everything after
it is the game playing rather than the sweep. Kingquest1 drops 3,611 events at that cut -- and
those 3,611 are the title screen and whatever follows it, drawn by the game's own logic.

★★★★ THAT MAKES THIS THE INSTRUMENT FOR JAY'S QUESTION: is the scroll panel on KQ1's title screen
empty because the words are text the engine has not drawn, or because something dropped picture
geometry? The tail says which, in positions.

★★★ §2P: rows, columns, colours and counts. patch 0010 never logged the character code, so this
cannot print game text even by accident.

usage:  python harness/tools/text_tail.py [title ...]
"""
import os
import sys

DUMPS = os.path.join(os.path.dirname(__file__), "..", "..", "oracle", "dumps")


def load(path):
    ev = []
    with open(path, "r") as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            if p[0] == "G" and len(p) >= 6:
                ev.append(("G", int(p[1]), int(p[2]), int(p[3]), int(p[4])))
            elif p[0] == "R":
                ev.append(("R",))
    return ev


def main(argv):
    titles = argv[1:] or ["Kingquest1"]
    for t in titles:
        p = os.path.join(DUMPS, "text-%s" % t, "text_events.txt")
        if not os.path.isfile(p):
            print("%-20s no dump at %s" % (t, p))
            continue
        ev = load(p)
        last_r = max((i for i, e in enumerate(ev) if e[0] == "R"), default=-1)
        tail = [e for e in ev[last_r + 1:] if e[0] == "G"]
        print("=== %s ===" % t)
        print("  %d events total, last restore at %d, %d glyphs AFTER it"
              % (len(ev), last_r, len(tail)))
        if not tail:
            print("  ★★★ the game drew NO text of its own -- the tail is empty")
            continue
        rows = {}
        for _, r, c, fg, bg in tail:
            rows.setdefault(r, []).append(c)
        print("  row  glyphs  columns        colours")
        cols_seen = {}
        for _, r, c, fg, bg in tail:
            cols_seen.setdefault(r, set()).add((fg, bg))
        for r in sorted(rows):
            cs = rows[r]
            print("  %3d  %6d  %2d..%-2d        %s"
                  % (r, len(cs), min(cs), max(cs),
                     ",".join("fg%d/bg%d" % k for k in sorted(cols_seen[r]))))
        print("  ★ rows %d..%d, %d distinct rows" % (min(rows), max(rows), len(rows)))


if __name__ == "__main__":
    main(sys.argv)
