#!/usr/bin/env python3
"""harness/tools/flag_diff.py -- what a build COULD define, against what it DOES [L-77].

★★★★★ WHY NAMING THE FLAGS WAS NOT ENOUGH, AND THIS EXISTS BECAUSE OF THAT.
T-P0-043's pre-dispatch grep asked for the flag set. I produced it, confirmed PLANE_WIN_MMU was
present, and reported it as checked. **-DHAL_SYS_FAST_CLOCK was ABSENT**, so the VM ran at
0.894 MHz, every derived figure was wrong by exactly 2.003x, and the task nearly reported a 33%
shortfall against the corpus's 10 that was really a missing -D.

★★★★ **A checklist that asks whether X is PRESENT cannot ask what is ABSENT.** Confirming the
named flags is a test the wrong way round: it enumerates from the answer. So this enumerates from
the SOURCE -- every `ifdef`/`ifndef` guard reachable in an artifact's include tree -- and diffs
the actual command line against it. The output is the guards the build does NOT define, which is
the list nobody was looking at.

★★★ It cannot know which absences MATTER; that is a reading, not a computation. What it can do is
make the absence visible at all, and put the load-bearing ones where a reader must pass them. Two
are marked EXPECTED-ON because their absence is silent and costly:
  HAL_SYS_FAST_CLOCK -- the machine runs at half speed and no error is raised [AD-100]
  PIC_NOCOUNT        -- counters cost 2.16x and a timing figure taken with them is not comparable

★ Guards that only select an ABLATION (ABL_*, *_FAULT) are expected OFF and are listed separately
so they do not drown the signal.

usage:  python harness/tools/flag_diff.py --src src/harness/p3b_probe.s --flags "-DA -DB"
        python harness/tools/flag_diff.py --manifest      (every gates.manifest row)
"""
import argparse
import io
import pathlib
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]

GUARD = re.compile(r"^\s*if(n?)def\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
INCL = re.compile(r'include\s+"([^"]+)"')

# ★★ Absence of these is silent and changes every derived number.
EXPECTED_ON = {
    "HAL_SYS_FAST_CLOCK": "machine runs at 0.894 MHz instead of 1.789 -- no error raised [AD-100]",
    "PIC_NOCOUNT": "counters cost 2.16x; a timing figure taken with them is not comparable",
}
ABLATION = re.compile(r"^(ABL_|.*_FAULT$|.*_STOP\d*$|FC_STOP|VM_PACEONLY|VM_NOCOUNT|"
                      r"PIC_STRADDLE|PIC_PALSWATCH|PIC_PRESENT|PIC_SNAP|ABL_NOEVICT)")


def tree(src, seen=None):
    seen = seen if seen is not None else set()
    p = ROOT / src if not pathlib.Path(src).is_absolute() else pathlib.Path(src)
    if p in seen or not p.exists():
        return seen
    seen.add(p)
    txt = p.read_text(errors="replace")
    for m in INCL.finditer(txt):
        tree(m.group(1), seen)
    return seen


def guards_of(src):
    g = set()
    for f in tree(src):
        for m in GUARD.finditer(f.read_text(errors="replace")):
            g.add(m.group(2))
    return g


def report(name, src, flags):
    defined = set(re.findall(r"-D([A-Za-z_][A-Za-z0-9_]*)", flags))
    # ★ Guards a source sets itself with `equ` are defined too -- p3b sets PLANE_WIN_MMU that way,
    # and treating it as absent would be exactly the false alarm this tool must not raise.
    for f in tree(src):
        for m in re.finditer(r"^([A-Za-z_][A-Za-z0-9_]*)\s+equ\s", f.read_text(errors="replace"), re.M):
            defined.add(m.group(1))
    g = guards_of(src)
    off = sorted(x for x in g - defined if not ABLATION.match(x))
    off_abl = sorted(x for x in g - defined if ABLATION.match(x))
    on = sorted(g & defined)

    print(f"── {name}  ({src}) ──")
    print(f"   ON  ({len(on)}): {' '.join(on) if on else '-'}")
    print(f"   OFF ({len(off)}): {' '.join(off) if off else '-'}")
    # ★★★★ THE FAST CLOCK CAN ALSO BE REACHED WITHOUT THE FLAG, AND THE FIRST VERSION OF THIS
    # TOOL DID NOT KNOW THAT. HAL_gfx_set_mode writes $FFD9 as part of selecting a graphics mode,
    # so a probe that calls it reaches 1.789 MHz whether or not HAL_SYS_FAST_CLOCK is defined --
    # which is why pic_probe's own calibration reads 1.7898 with the flag absent.
    # ★★★ Flagging those was a FALSE ALARM, and a checklist that cries wolf on six of eight rows
    # trains its reader to skip it. The ones that matter are the probes that time something and
    # never select a mode: res_probe and comp_probe.
    # ★★ A CALL, not the definition. Matching the bare name across the include tree finds
    # gfx.s's `HAL_gfx_set_mode:` label and reports every probe as calling it -- which flipped
    # res and comp from correctly-flagged to silently-excused on this tool's second revision.
    # The probe's OWN file, and a `jsr`, is the question.
    calls_set_mode = bool(re.search(r"jsr\s+HAL_gfx_set_mode",
                                    (ROOT / src).read_text(errors="replace")))
    bad = []
    for k, why in EXPECTED_ON.items():
        if k not in g or k in defined:
            continue
        if k == "HAL_SYS_FAST_CLOCK" and calls_set_mode:
            print(f"   ~ {k} absent, but HAL_gfx_set_mode is called -- fast mode reached that way")
            continue
        bad.append(k)
        print(f"   ★★★ EXPECTED-ON BUT ABSENT: {k}")
        print(f"       {why}")
    if off_abl:
        print(f"   (ablations, expected off: {' '.join(off_abl)})")
    print()
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src")
    ap.add_argument("--flags", default="")
    ap.add_argument("--name", default="build")
    ap.add_argument("--manifest", action="store_true")
    a = ap.parse_args()

    bad = []
    if a.manifest:
        mf = ROOT / "harness" / "tools" / "gates.manifest"
        for line in mf.read_text(errors="replace").splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            p = line.split("\t")
            if len(p) < 3:
                continue
            bad += report(p[0].strip(), p[1].strip(), p[3] if len(p) > 3 else "")
    else:
        bad = report(a.name, a.src, a.flags)

    if bad:
        print(f"★★★ {len(bad)} expected-on guard(s) absent. Every timing figure from such a build "
              f"is suspect.")
        return 1
    print("★ no expected-on guard is absent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
