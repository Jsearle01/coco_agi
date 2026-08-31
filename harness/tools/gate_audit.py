#!/usr/bin/env python3
"""harness/tools/gate_audit.py -- does every gate runner BUILD what it tests, or CONSUME it?

★★★★★ WHY THIS IS A TOOL AND NOT A READING. `res_run.ps1` pointed RES_PROG at a prebuilt binary
and never invoked the assembler, so the 1,264-resource gate reported "all clean" for two tasks
from a binary assembled before the code it gated existed [L-70]. **The staleness was noticed once,
in passing, in a report about something else, and not followed up** -- so a second eyeball pass is
exactly the instrument that already failed.

★★★ THE CONDITION IS MECHANICAL. For each runner: does it invoke lwasm, or does it name a `.bin`
it did not build? A runner that names an artifact it does not assemble is SUSPECT, and the
evidence is the artifact's mtime against its source's.

★★ WHAT COUNTS AS A RUNNER. Anything under harness/tools/ that launches MAME or drives a gate:
the .ps1 and .sh scripts, plus the .lua drivers they autoboot -- because a .lua that reads
`os.getenv("X_PROG")` is consuming whatever its caller built, and the caller may be a human.
★ A .lua is classified by whether its CALLER builds; a .lua cannot assemble anything itself.

★ Reports; does not gate. Exit 1 when any consumer is stale, so a caller may choose.
"""
import argparse
import hashlib
import io
import pathlib
import re
import subprocess
import sys
import time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]

ASM = re.compile(r"lwasm", re.I)
# ★ A .bin the script names. Covers "build/x.bin", "build\x.bin" and $env:X_PROG = "...".
BIN = re.compile(r"[\"'`]?(build[\\/][A-Za-z0-9_.\-]+\.bin)", re.I)
# ★ Env vars that hand a program path IN from the caller -- the tell for a .lua consumer.
ENVPROG = re.compile(r'getenv\(\s*"([A-Z0-9_]*PROG)"', re.I)
# ★★★★ THE DEFAULT IS THE DANGEROUS HALF, AND THE FIRST VERSION OF THIS TOOL MISSED IT.
# `run_gates.sh` names no .bin at all, so it classified as "no artifact" -- but it autoboots
# pic_sweep.lua, whose line is `local PROG = os.getenv("PIC_PROG") or "build/pic_probe.bin"`.
# **A runner that supplies no program silently uses the driver's default**, which nothing builds.
# ★★ So the audit has to follow the default through the .lua, or it exonerates the renderer gate
# -- one of the five -- on the grounds that its runner mentions no artifact.
LUADEF = re.compile(r'getenv\(\s*"([A-Z0-9_]*PROG)"\s*\)\s*or\s*"([^"]+\.bin)"', re.I)
# ★★★ ANY .lua the runner MENTIONS, not just one literally after -autoboot_script. run_gates.sh
# passes the driver as a shell argument (`run <name> <script> <seconds>` … `-autoboot_script "$2"`),
# so an anchored pattern exonerated it -- and it drives the RENDERER gate, one of the five.
# ★★ Third correction to this tool in one sitting. The instrument built to find "what did we fail
# to look at" needed three passes to stop failing to look at things itself.
AUTOBOOT = re.compile(r"([A-Za-z0-9_]+\.lua)", re.I)


LWASM = "C:\\WIN_LWTools\\lwasm.exe"
MANIFEST = pathlib.Path(__file__).resolve().parent / "gates.manifest"


def manifest():
    """(name, src, artifact, [flags]) for each gate. ★ Single home for the build lines (2F)."""
    rows = []
    for line in MANIFEST.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        name, src, out = parts[0].strip(), parts[1].strip(), parts[2].strip()
        flags = parts[3].split() if len(parts) > 3 else []
        rows.append((name, src, out, flags))
    return rows


def src_for(binname):
    """Best-effort source for an artifact: build/foo.bin -> src/harness/foo.s.

    ★ Strips the variant suffixes this project uses (_pk, _nc, _fault, _present, .ref, .chk...)
    so build/pic_probe_pk.bin maps back to src/harness/pic_probe.s. A variant is still built
    from the same source, so staleness is the same question.
    """
    stem = pathlib.Path(binname).stem
    for suf in ("_pk", "_nc", "_fault", "_present", "_fwd", "_subsys", "_ref", "_chk",
                "_good", "_pre", "_prechange"):
        if stem.endswith(suf):
            stem = stem[: -len(suf)]
    stem = stem.split(".")[0]
    for cand in (ROOT / "src" / "harness" / f"{stem}.s", ROOT / "src" / "engine" / f"{stem}.s"):
        if cand.exists():
            return cand
    return None


def newest_source(src):
    """The newest mtime among a source and everything it includes, transitively.

    ★★ A probe is stale if ANY file it pulls in is newer than the artifact -- res_probe.s itself
    never changed while res_core.s changed three times underneath it, which is exactly how the
    binary went stale without its own source being touched.
    """
    seen, stack, newest = set(), [src], 0.0
    while stack:
        f = stack.pop()
        if f in seen or not f.exists():
            continue
        seen.add(f)
        newest = max(newest, f.stat().st_mtime)
        for m in re.finditer(r'include\s+"([^"]+)"', f.read_text(errors="replace")):
            stack.append(ROOT / m.group(1))
    return newest, len(seen)




def collect(src, seen=None):
    """The transitive include set of a source."""
    seen = seen if seen is not None else set()
    stack = [src]
    while stack:
        f = stack.pop()
        if f in seen or not f.exists():
            continue
        seen.add(f)
        for m in re.finditer(r'include\s+"([^"]+)"', f.read_text(errors="replace")):
            stack.append(ROOT / m.group(1))
    return seen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--hash", metavar="SRC",
                    help="print a source-tree hash for SRC and exit (AC-3's build stamp)")
    ap.add_argument("--verify", action="store_true",
                    help="rebuild every manifest entry and BYTE-COMPARE against the shipped "
                         "artifact -- proves staleness where mtime only infers it")
    ap.add_argument("--check", metavar="BIN",
                    help="exit 1 if BIN is stale against its source's include tree; for a runner "
                         "that must not build (vm_load.ps1 -- concurrent instances)")
    args = ap.parse_args()

    if args.verify:
        # ★★★★★ THE INSTRUMENT THE MTIME PASS WAS A PROXY FOR. Rebuild every manifest entry to a
        # scratch path and COMPARE BYTES against the shipped artifact. ★★★ This exists because the
        # mtime pass OVER-REPORTS: build/pic_probe.bin was a full day stale against its include
        # tree and byte-identical to a fresh build, so the renderer gate's 45/45 was never in
        # doubt. An mtime says the source tree MOVED; only a rebuild says the artifact is WRONG.
        # ★★ It under-reports too, in principle -- a touched-but-unchanged file bumps an mtime,
        # and a rebuild with different FLAGS produces a different program at an unchanged mtime.
        # Bytes answer both. res_probe.bin in T-P0-037 was content-real (pre-cache vs post-cache)
        # and that is the case this would have caught on day one.
        rc = 0
        print(f"{'gate':<6} {'artifact':<24} {'shipped':>8} {'fresh':>8}  verdict")
        print("-" * 72)
        for name, src, out, flags in manifest():
            outp, srcp = ROOT / out, ROOT / src
            tmp = ROOT / "build" / f".verify_{name}.bin"
            cmd = [LWASM, "--raw", "-I.", *flags, "-o", str(tmp), str(srcp)]
            r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
            if r.returncode != 0:
                print(f"{name:<6} {out:<24} {'':>8} {'':>8}  ★★★ ASSEMBLE FAILED: "
                      f"{(r.stdout + r.stderr).strip().splitlines()[0][:60] if (r.stdout+r.stderr).strip() else '?'}")
                rc = 1
                continue
            fresh = tmp.read_bytes()
            if not outp.exists():
                print(f"{name:<6} {out:<24} {'ABSENT':>8} {len(fresh):>8}  ★★★ artifact missing")
                rc = 1
            elif outp.read_bytes() == fresh:
                print(f"{name:<6} {out:<24} {outp.stat().st_size:>8} {len(fresh):>8}  identical")
            else:
                print(f"{name:<6} {out:<24} {outp.stat().st_size:>8} {len(fresh):>8}  "
                      f"★★★ DIFFERS -- the gate is testing something else")
                rc = 1
            tmp.unlink(missing_ok=True)
        print()
        print("★ 'identical' means the shipped artifact IS what its source builds now. That is the"
              " claim an mtime cannot make.")
        return rc

    if args.check:
        # ★★★★ FOR A RUNNER THAT MUST NOT BUILD. vm_load.ps1 launches N concurrent MAME instances
        # and deliberately never writes build/ -- rebuilding would have N processes writing one
        # binary while others read it, which is the withdrawn-measurement shape from T-P0-024.
        # ★★★ So the answer for it is not "build" but "refuse a stale input". A harness that
        # cannot build what it tests can still decline to test the wrong thing.
        p = ROOT / args.check
        src = src_for(args.check)
        if not p.exists():
            print(f"★★★ {args.check} ABSENT")
            return 1
        if src is None:
            print(f"? {args.check}: no source found; cannot judge")
            return 0
        newest, n = newest_source(src)
        if newest > p.stat().st_mtime:
            print(f"★★★ {args.check} IS STALE against {src.name}'s include tree ({n} files) -- "
                  f"rebuild before trusting any result from it")
            return 1
        print(f"{args.check} current vs {src.name} ({n} files)")
        return 0

    if args.hash:
        src = ROOT / args.hash
        files = collect(src)
        h = hashlib.sha256()
        for f in sorted(files):
            h.update(f.name.encode())
            h.update(f.read_bytes())
        print(f"{h.hexdigest()[:12]} ({len(files)} files)")
        return 0

    tools = ROOT / "harness" / "tools"
    runners = sorted(list(tools.glob("*.ps1")) + list(tools.glob("*.sh")))
    luas = sorted(tools.glob("*.lua"))

    print(f"{'runner':<26} {'class':<20} {'artifact(s) it names'}")
    print("-" * 96)
    bad = 0
    consumers = []
    for r in runners:
        text = r.read_text(errors="replace")
        builds = bool(ASM.search(text))
        bins = sorted(set(m.group(1).replace("\\", "/") for m in BIN.finditer(text)))
        # ★★ Follow every .lua this runner autoboots and inherit its DEFAULT artifact, because a
        # runner that names nothing still runs whatever the driver falls back to.
        inherited = []
        for m in AUTOBOOT.finditer(text):
            lua = tools / m.group(1)
            if lua.exists():
                for d in LUADEF.finditer(lua.read_text(errors="replace")):
                    tag = f"{d.group(2)}  (default of ${d.group(1)} in {lua.name})"
                    if tag not in inherited: inherited.append(tag)
                    bins.append(d.group(2))
        bins = sorted(set(bins))
        if builds:
            cls = "BUILDS-FROM-SOURCE"
        elif bins:
            cls = "★ CONSUMES-ARTIFACT"
            consumers.append((r, bins))
        else:
            cls = "no artifact"
        print(f"{r.name:<26} {cls:<20} {' '.join(bins) if bins else '--'}")
        for i in inherited:
            print(f"{'':<26} {'':<20}   via autoboot: {i}")

    print()
    print(f"{'lua driver':<26} {'class':<20} {'takes its program from'}")
    print("-" * 96)
    for l in luas:
        text = l.read_text(errors="replace")
        envs = sorted(set(m.group(1) for m in ENVPROG.finditer(text)))
        if envs:
            print(f"{l.name:<26} {'★ CALLER-SUPPLIED':<20} {' '.join('$' + e for e in envs)}")
        elif "mame" in text.lower() or "add_machine_frame_notifier" in text:
            print(f"{l.name:<26} {'driver, no prog var':<20} --")

    # ── staleness evidence for every consumer ──
    print()
    print("★★ STALENESS EVIDENCE (artifact mtime vs newest mtime among its source's include tree)")
    print(f"{'artifact':<30} {'built':<20} {'newest source':<20} {'files':<6} verdict")
    print("-" * 96)
    shown = set()
    for r, bins in consumers:
        for b in bins:
            if b in shown: continue
            shown.add(b)
            p = ROOT / b
            src = src_for(b)
            if not p.exists():
                print(f"{b:<30} {'ABSENT':<20} {'--':<20} {'--':<6} ★ cannot run")
                bad += 1
                continue
            if src is None:
                print(f"{b:<30} {time.strftime('%Y-%m-%d %H:%M', time.localtime(p.stat().st_mtime)):<20}"
                      f" {'(no source found)':<20} {'--':<6} ?")
                continue
            newest, n = newest_source(src)
            bt = p.stat().st_mtime
            v = "★★★ STALE" if newest > bt else "current"
            if newest > bt:
                bad += 1
            print(f"{b:<30} {time.strftime('%Y-%m-%d %H:%M', time.localtime(bt)):<20}"
                  f" {time.strftime('%Y-%m-%d %H:%M', time.localtime(newest)):<20} {n:<6} {v}")

    print()
    print(f"★ {len(consumers)} runner(s) consume an artifact they do not build; {bad} stale or absent.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
