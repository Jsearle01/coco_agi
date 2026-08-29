#!/usr/bin/env python3
"""harness/tools/ignore_probe.py -- AC-1: prove .gitignore covers what is about to arrive.

★★★ THE ORDERING IS THE SAFETY PROPERTY, NOT THE PATTERN LIST. Game data pushed to a public
repository CANNOT be deleted -- a later `rm` takes it out of the tree and leaves it in history,
and the only real remedy is a history rewrite across three synchronised sibling repos plus a
force-push. So this runs, and its result is committed and pushed, BEFORE any archive is dropped.

★★ IT ASKS GIT, NOT THE PATTERN FILE. `git check-ignore -v` reports the rule that matched, by
file and line, so a name that is covered "obviously" but actually is not shows up here rather
than in `git status` after the fact. ★ L-28: the matcher is not the grammar -- reading the
patterns and believing they cover a case is exactly the error this avoids.

★ Paths are HYPOTHETICAL. Nothing is created; check-ignore works on names.
"""
import argparse
import io
import subprocess
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# What a DOS AGI release actually ships, plus the archive wrappers it may arrive in.
# ★ Both cases everywhere: the CoCo3 corpus taught us the filesystem's case-insensitivity is a
# property of THIS host and not of the rule (see .gitignore's logDir note).
CASES = [
    ("archive wrappers", [
        "SpaceQuest-1.zip", "SPACEQUEST1.ZIP", "sq2.7z", "bc.rar", "pq1.tar.gz",
        "larry1.arc", "mother.lzh", "goldrush.cab", "mhny.iso",
    ]),
    ("AGI resource files", [
        "SpaceQuest-1/logdir", "SpaceQuest-1/LOGDIR", "SpaceQuest-1/picdir",
        "SpaceQuest-1/PICDIR", "SpaceQuest-1/viewdir", "SpaceQuest-1/VIEWDIR",
        "SpaceQuest-1/snddir", "SpaceQuest-1/SNDDIR",
        "SpaceQuest-1/vol.0", "SpaceQuest-1/VOL.0", "SpaceQuest-1/vol.3",
        "SpaceQuest-1/words.tok", "SpaceQuest-1/WORDS.TOK",
        "SpaceQuest-1/object", "SpaceQuest-1/OBJECT",
    ]),
    ("v3 combined directories", [
        "GOLDRUSH/GOLDRUSH/grdir", "GOLDRUSH/GOLDRUSH/GRDIR",
        "ManhunterNewyork/mhny/mhdir", "ManHunterSanFrancisco/mhsf/mh2dir",
        "GOLDRUSH/GOLDRUSH/grvol.0", "ManhunterNewyork/mhny/mhvol.1",
    ]),
    ("DOS interpreter and drivers", [
        "SpaceQuest-1/SIERRA.EXE", "SpaceQuest-1/sierra.exe",
        "SpaceQuest-1/AGI.OVL", "SpaceQuest-1/agi.ovl",
        "SpaceQuest-1/SIERRA.COM", "SpaceQuest-1/CGA.DRV", "SpaceQuest-1/IBM.SYS",
    ]),
    ("DOS text, art and help", [
        "SpaceQuest-1/SQ1.QA", "SpaceQuest-1/HELP.MSG", "SpaceQuest-1/TITLE.SCR",
        "SpaceQuest-1/READ.HLP", "SpaceQuest-1/BOX.GIF",
    ]),
    ("batch files", [
        "SpaceQuest-1/SIERRA.BAT", "SpaceQuest-1/install.bat", "SQ1.BAT",
    ]),
    ("SCI game data (out of scope, still never committed)", [
        "Kingquest4/RESOURCE.MAP", "Kingquest4/RESOURCE.001", "larry2/resource.map",
    ]),
    ("★ MUST NOT be ignored -- the build contract and manifests", [
        "build.bat", "games/manifests/pc-agi.tsv", "games/manifests/notes.md",
        "content/font8x8.bin",
    ]),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--expect-unignored", action="store_true",
                    help="also fail if a MUST-NOT row is ignored")
    a = ap.parse_args()

    bad = []
    for title, paths in CASES:
        must_not = title.startswith("★")
        print("\n%s" % title)
        for p in paths:
            r = subprocess.run(["git", "check-ignore", "-v", p],
                               capture_output=True, text=True)
            rule = r.stdout.strip()
            # ★★ EXIT 0 DOES NOT MEAN "IGNORED". check-ignore returns 0 whenever a rule MATCHED,
            # including a NEGATION -- and then reports the `!` rule that un-ignores the path. The
            # first version read the exit code alone and declared games/manifests/notes.md and
            # content/font8x8.bin ignored when their `!` rules are precisely what keeps them
            # addable. ★ L-28 on my own matcher: the exit status is not the grammar.
            pattern = ""
            if rule and "\t" in rule:
                head = rule.split("\t")[0]
                parts = head.split(":")
                pattern = parts[-1] if parts else ""
            ignored = r.returncode == 0 and not pattern.startswith("!")
            if must_not:
                ok = not ignored
                mark = "" if ok else "   ★★★ IGNORED, MUST NOT BE"
            else:
                ok = ignored
                mark = "" if ok else "   ★★★ NOT IGNORED"
            if not ok:
                bad.append((p, must_not))
            if ignored:
                # rule looks like ".gitignore:123:pattern\tpath"
                where = rule.split("\t")[0] if "\t" in rule else rule
                print("  %-42s ignored by %s%s" % (p, where, mark))
            else:
                print("  %-42s NOT ignored%s" % (p, mark))

    print()
    print("failures: %d" % len(bad))
    for p, mn in bad:
        print("  %-42s %s" % (p, "must NOT be ignored" if mn else "must be ignored"))
    print()
    print("AC-1 %s" % ("PASS -- every arriving form is covered, and nothing that must stay "
                       "addable is caught" if not bad else "★★★ FAIL"))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
