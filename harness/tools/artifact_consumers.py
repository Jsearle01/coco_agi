"""harness/tools/artifact_consumers.py -- which produced artifacts does nothing read? [P6.16 AC-8]

★★★★★ L-101: AN ARTIFACT THAT IS WRITTEN IS NOT AN ARTIFACT THAT IS READ. oracle_said.txt has been
produced by patch 0009 since it was written and consumed by nothing -- 1.4 MB per title, sitting as
a .tmp under a name no tool looks for. The producer looked correct because it wrote; nobody checked
that the other end existed.

★★★★ THE CHECK IS MECHANICAL, WHICH IS THE POINT. Every name a patch opens for writing is matched
against every name the harness opens for reading. A name with producers and no consumers is either
a diagnostic nobody needs or a gate leg that is not connected -- and the two are indistinguishable
from the producer's side, which is exactly how the first one survived.

★★★ IT REPORTS RATHER THAN FAILS. Some artifacts are legitimately human-read diagnostics; the list
is for a person to disposition, not a build to reject. A tool that failed here would be turned off
the first time somebody added a debug dump.

usage:  python harness/tools/artifact_consumers.py
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]

# ★ Names written by the oracle instrumentation. Two shapes: literal open("x.txt") and
# String::format("...%d...") whose literal prefix is what lands on disk.
# ★★★★ WRITES ONLY. The first version matched every open() and so listed oracle_said_script.txt as
# an unconsumed artifact -- but that name is opened by `Common::File f` and is an INPUT the oracle
# READS. ScummVM's two classes make the direction unambiguous: DumpFile writes, File reads. So the
# writer is identified by the DECLARED VARIABLE, and a bare open() is only counted when the same
# line or a nearby one declares a DumpFile.
# ★★ Consequence worth keeping: a name that only ever appears with Common::File is an input, and
# an input that nothing in the harness PRODUCES is a dormant feature -- a different finding from an
# unread output, and one this tool would otherwise hide inside the same list.
WRITE = re.compile(r'(?:DumpFile\s+(\w+).*?|(\w+)\.)open\s*\(\s*(?:Common::Path\(\s*)?"([A-Za-z0-9_.%]+)"')
FORMAT = re.compile(r'String::format\(\s*"([A-Za-z0-9_.%]+\.(?:bin|txt))"')


def produced():
    """Names the patches OPEN FOR WRITING, plus every %-formatted name they build."""
    names = set()
    for p in sorted((ROOT / "oracle" / "patches").glob("*.patch")):
        text = p.read_text(encoding="utf-8", errors="replace")
        added = [l for l in text.splitlines() if l.startswith("+")]
        # ★ Variables declared as DumpFile in this patch -- the writers.
        writers = set(re.findall(r'DumpFile\s+(\w+)', "\n".join(added)))
        for line in added:      # ★ ADDED lines only -- context lines are the pinned source
            for m in WRITE.finditer(line):
                var, var2, name = m.group(1), m.group(2), m.group(3)
                if var or (var2 and var2 in writers):
                    names.add(name)
            for m in FORMAT.finditer(line):
                names.add(m.group(1))
    return names


# ★★★★★ FILES THAT MENTION A NAME WITHOUT CONSUMING IT. This tool's first run reported
# oracle_said.txt as "read by: artifact_consumers.py, oracle_dump.sh" -- its own docstring, and a
# rename loop that moves the file without opening it. **Mentioning a name is not reading it**,
# which is L-101's own error committed by the tool written to detect L-101.
NOT_A_CONSUMER = {
    "harness/tools/artifact_consumers.py",   # this file names them all, by construction
    "harness/tools/oracle_dump.sh",          # renames *.tmp and lists the directory; opens nothing
}


def consumers(name):
    """Files in harness/ or tools/ that MENTION this name, minus the known non-consumers.

    ★★★ "Mentions" is still the test and it OVER-reports: a name in a comment counts. That is the
    safe direction for this question -- a false consumer hides an orphan, so the tool is written to
    make orphans hard to miss and the survivors are hand-dispositioned. The list is evidence for a
    person, not a verdict.
    """
    # ★★ A %-formatted family is matched by the literal prefix that actually lands on disk:
    # pic%03d.%s.bin -> "pic". Short stems are kept rather than discarded -- the first version
    # required 4 characters and so matched pic%03d.%s.bin literally, found nothing, and reported
    # the renderer's 164 dumps as unconsumed.
    stem = name.split("%")[0].rstrip("_.")
    hits = []
    for d in ("harness", "tools"):
        for p in (ROOT / d).rglob("*"):
            if p.suffix not in (".py", ".sh", ".lua", ".ps1") or not p.is_file():
                continue
            rel = p.relative_to(ROOT).as_posix()
            if rel in NOT_A_CONSUMER:
                continue
            try:
                if stem and stem in p.read_text(encoding="utf-8", errors="replace"):
                    hits.append(rel)
            except OSError:
                pass
    return hits


def main():
    names = produced()
    print("artifacts produced by oracle/patches/, and what reads them")
    print("=" * 78)
    orphans = []
    for n in sorted(names):
        c = consumers(n)
        if c:
            print(f"  {n:<28} read by: {', '.join(c[:3])}{' ...' if len(c) > 3 else ''}")
        else:
            print(f"  {n:<28} ★★★ NO CONSUMER")
            orphans.append(n)
    print("=" * 78)
    print(f"{len(names)} produced, {len(orphans)} with no consumer")
    for n in orphans:
        print(f"  orphan: {n}")


if __name__ == "__main__":
    main()
