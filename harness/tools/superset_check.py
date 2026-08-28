#!/usr/bin/env python3
"""harness/tools/superset_check.py -- §2D's hard gate before overwriting an authored doc.

★★★ THE RULE: every substantive line of the IN-REPO copy must be present in the PROVIDED file,
verbatim or explicitly superseded. If the in-repo copy has content the provided file lost, STOP
and surface the delta -- do not overwrite.

★★ WHY A SCRIPT AND NOT A DIFF. A diff shows both directions and is dominated by the additions,
which are expected and uninteresting. The gate is one-directional: what did the provided file
DROP? That is a set-difference question, and reading it out of a two-column diff is exactly the
kind of manual step that passes when someone is tired.

★ "Substantive" = non-blank after stripping trailing whitespace. Blank-line and pure-EOL churn is
normalised away; everything else counts. Ordering is NOT required -- §2D says present, not
in-place -- so this compares as a multiset and reports lines whose count DROPPED.
"""
import argparse
import collections
import hashlib
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")


def lines(p):
    raw = pathlib.Path(p).read_bytes()
    text = raw.decode("utf-8", errors="replace")
    return [ln.rstrip() for ln in text.replace("\r\n", "\n").split("\n") if ln.strip()], raw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("in_repo")
    ap.add_argument("provided")
    a = ap.parse_args()

    old, old_raw = lines(a.in_repo)
    new, new_raw = lines(a.provided)

    co, cn = collections.Counter(old), collections.Counter(new)
    dropped = []
    for ln, k in co.items():
        if cn[ln] < k:
            dropped.append((k - cn[ln], ln))

    print("in-repo  : %s" % a.in_repo)
    print("           %d bytes, sha256 %s" % (len(old_raw), hashlib.sha256(old_raw).hexdigest()[:16]))
    print("           %d substantive lines" % len(old))
    print("provided : %s" % a.provided)
    print("           %d bytes, sha256 %s" % (len(new_raw), hashlib.sha256(new_raw).hexdigest()[:16]))
    print("           %d substantive lines" % len(new))
    print("added    : %d substantive lines not in the in-repo copy"
          % sum(max(0, cn[l] - co[l]) for l in cn))
    print("DROPPED  : %d substantive lines present in-repo and absent (or fewer) in the provided file"
          % sum(n for n, _ in dropped))
    for n, ln in dropped[:60]:
        print("  -%d  %s" % (n, ln[:110]))
    if len(dropped) > 60:
        print("  ... %d more distinct lines" % (len(dropped) - 60))
    print()
    print("SUPERSET CHECK: %s" % ("PASS -- the provided file contains every substantive in-repo line"
                                  if not dropped else
                                  "★★★ FAIL -- STOP AND SURFACE THE DELTA (§2D)"))
    return 0 if not dropped else 1


if __name__ == "__main__":
    sys.exit(main())
