"""harness/tools/patch_regen.py -- regenerate an oracle patch from the live ScummVM tree.

★★★★★ THE PATCH FILES ARE A RECORD, AND A RECORD DRIFTS. The instrumentation lives as uncommitted
changes in C:\\Projects\\scummvm; oracle/patches/*.patch is the archived diff. Editing the source and
forgetting the archive leaves a patch that no longer reconstructs the oracle its results came from
-- which is the provenance defect §2Q exists to prevent, and it is invisible because both files
still look fine.

★★★★ IT PRESERVES THE HEADER AND REPLACES ONLY THE DIFF. Every patch here opens with a `#` comment
block carrying the reasoning, the §2P note and the cumulative-diff warning; those are authored and
must survive. Everything from the first `diff --git` is regenerated.

★★★ AND IT WRITES UTF-8 WITHOUT A BOM, DELIBERATELY. The previous 0010 had every `★` in its diff
body replaced by `?` -- an ASCII-strip somewhere in how it was produced -- so the archived copy was
lossy against a source that was fine. Regenerating through this fixes that as a side effect.

usage:  python harness/tools/patch_regen.py <patch-file> <file> [file ...]
        (files are paths inside the scummvm tree, e.g. engines/agi/agi.cpp)
"""
import io
import subprocess
import sys

SCUMMVM = r"C:\Projects\scummvm"
GIT = r"C:\Users\jayse\DEV\cmd\git.exe"


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    patch_path, files = argv[1], argv[2:]

    with io.open(patch_path, "r", encoding="utf-8", errors="replace") as f:
        old = f.read()
    cut = old.find("diff --git ")
    if cut < 0:
        print("★★★ no 'diff --git' in %s -- refusing to guess where the header ends" % patch_path)
        return 1
    header = old[:cut]

    out = subprocess.run([GIT, "diff", "--"] + files, cwd=SCUMMVM,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if out.returncode != 0:
        print("★★★ git diff failed: %s" % out.stderr.decode("utf-8", "replace"))
        return 1
    body = out.stdout.decode("utf-8", "replace").replace("\r\n", "\n")
    if not body.strip():
        print("★★★ git diff is EMPTY for %s -- the tree has no instrumentation to archive" % files)
        return 1

    with io.open(patch_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(header)
        f.write(body)

    print("  %s regenerated: %d header bytes + %d diff bytes over %d file(s)"
          % (patch_path, len(header.encode("utf-8")), len(body.encode("utf-8")), len(files)))
    stars_old = old.count("\u2605")
    stars_new = header.count("\u2605") + body.count("\u2605")
    print("  ★ count %d -> %d" % (stars_old, stars_new))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
