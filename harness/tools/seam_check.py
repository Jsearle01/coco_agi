#!/usr/bin/env python3
"""seam_check.py -- THE §4.2a SEAM, ENFORCED (AC-8).

★★ THE RULE: **no module outside `tools/volread/resource.py` may branch on the AGI version.**
Finding a resource is separated from decoding it; version knowledge lives in exactly one place.
That is what keeps the v3 deferral [design §11.1, AD-25] reversible -- adding v3 becomes a new
decoder behind the seam instead of an edit to every call site.

★ THIS IS THE P1 ANALOGUE OF §2N's REGISTER DISCIPLINE, and it exists for the same reason: a
claim about a whole tree that nothing verifies decays silently. §2N's lesson applies twice over:

  1. **A literal grep is the discredited instrument.** §2N's four-part rule exists because
     grepping `$FF..` counted COMMENTS and MISSED ALIASES -- wrong in both directions at once.
     The same trap is here: this file is thick with the words "v2" and "v3" in prose, and a
     naive grep would flag every one. So a line counts only if it is CODE -- not a comment, not
     a docstring -- and only if the version token is used in a CONDITIONAL or comparison.
  2. **Zero is not the goal, ONE SANCTIONED OWNER is.** resource.py is *supposed* to branch on
     version. The finding is a branch anywhere else.

★ THE ALLOWLIST IS BY EXPLICIT FILENAME, never by pattern -- adding one must be a visible act,
exactly as §2N requires of harness probes.

Exit 1 on a violation, so this can gate a build later. Stdlib only, standalone.
"""
import argparse
import ast
import pathlib
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# ★ The one module allowed to know. By explicit filename.
SANCTIONED = ("tools/volread/resource.py",)

# Version tokens that would indicate a branch. Matched against string literals and attribute
# names appearing in a CONDITIONAL context only.
VERSION_TOKENS = ("v2", "v3", "V2", "V3", "agi_version", "version")

DEFAULT_ROOTS = ("tools/volread",)


class Finding:
    def __init__(self, path, lineno, kind, text):
        self.path, self.lineno, self.kind, self.text = path, lineno, kind, text


def _literals(node):
    """Every string literal anywhere inside an expression."""
    out = []
    for n in ast.walk(node):
        if isinstance(n, ast.Constant) and isinstance(n.value, str):
            out.append(n.value)
    return out


def _names(node):
    out = []
    for n in ast.walk(node):
        if isinstance(n, ast.Attribute):
            out.append(n.attr)
        elif isinstance(n, ast.Name):
            out.append(n.id)
    return out


def scan_file(path, rel):
    """Find version branches in CODE. Comments and docstrings are invisible to ast, which is
    exactly why ast is used here instead of a regex -- see the module docstring."""
    findings = []
    try:
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
    except SyntaxError as e:
        return [Finding(rel, e.lineno or 0, "SYNTAX", str(e))]

    for node in ast.walk(tree):
        # a conditional whose test mentions a version token
        tests = []
        if isinstance(node, (ast.If, ast.IfExp, ast.While)):
            tests = [node.test]
        elif isinstance(node, ast.Assert):
            tests = [node.test]
        elif isinstance(node, ast.Match):
            tests = [node.subject]
        if not tests:
            continue
        for t in tests:
            toks = set(_literals(t)) | set(_names(t))
            hit = sorted(tok for tok in toks
                         if any(v == tok or v in str(tok) for v in VERSION_TOKENS))
            if hit:
                findings.append(Finding(rel, getattr(node, "lineno", 0),
                                        "VERSION BRANCH", ", ".join(hit)))
    return findings


def main():
    ap = argparse.ArgumentParser(description="Enforce the §4.2a version seam (AC-8).")
    ap.add_argument("--roots", nargs="*", default=list(DEFAULT_ROOTS))
    ap.add_argument("--allow", nargs="*", default=[],
                    help="EXTRA sanctioned files, by explicit filename (never a pattern)")
    args = ap.parse_args()

    sanctioned = set(SANCTIONED) | {pathlib.Path(a).as_posix() for a in args.allow}

    files = []
    for root in args.roots:
        base = pathlib.Path(root)
        if not base.exists():
            continue
        files.extend(sorted(p for p in base.rglob("*.py")))

    if not files:
        print("[seam] no Python under %s -- nothing to check." % ", ".join(args.roots))
        return 0

    violations, sanctioned_hits = [], []
    for p in files:
        rel = p.as_posix()
        for f in scan_file(p, rel):
            (sanctioned_hits if rel in sanctioned else violations).append(f)

    print("[seam] scanned %d file(s) under %s" % (len(files), ", ".join(args.roots)))
    print("[seam] sanctioned owner(s): %s" % ", ".join(sorted(sanctioned)))
    print()
    print("  version branches INSIDE the seam (expected, and the point): %d"
          % len(sanctioned_hits))
    for f in sanctioned_hits:
        print("      %s:%d  %s" % (f.path, f.lineno, f.text))
    print()
    if violations:
        print("  ★ VERSION BRANCHES OUTSIDE THE SEAM: %d -- THIS IS A FAILURE" % len(violations))
        for f in violations:
            print("      %s:%d  %s  [%s]" % (f.path, f.lineno, f.text, f.kind))
        print()
        print("[seam] The v3 deferral is only reversible while version knowledge stays in one")
        print("[seam] place. Move the branch behind resource.py, or add the file to SANCTIONED")
        print("[seam] in THIS commit -- which is the approval, and is a visible act.")
        return 1

    print("  ★ version branches outside the seam: 0")
    print("[seam] OK -- the §4.2a seam holds.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
