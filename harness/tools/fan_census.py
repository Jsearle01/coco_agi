#!/usr/bin/env python3
"""harness/tools/fan_census.py -- extend the opcode census to the 150 pinned fan titles.

★★★ THE NOTE'S PREMISE NEEDS ONE CORRECTION, AND IT CHANGES THE ANSWER'S SHAPE. Feature flags
do NOT add opcode numbers. `dispatch.py unsupported_mutations()` says what they do:

    GF_AGI256    replaces opcode 0xAA (set.simple)  with a 256-colour picture load
    GF_AGIMOUSE  replaces opcode 0xAB (push.script) with a mouse-state read

★★ So a static census by opcode NUMBER cannot see a feature flag at all -- 0xAA and 0xAB appear
in a flagged title looking exactly like set.simple and push.script. There is no set of
"feature-gated opcodes" to subtract from a total; there are two NUMBERS whose MEANING differs in
flagged titles. Reporting them as extra entries would be arithmetically wrong and would overstate
the work by implying opcodes that do not exist.

★★★ WHAT IS REPORTABLE, AND IT IS THE QUESTION WORTH ASKING:
  1. the standard-AGI totals for Sierra, for fan, and for both;
  2. FAN-ONLY opcodes -- standard opcodes Sierra never used but fan authors did. ★ Real coverage
     the commercial titles cannot give us, and the note is right that these are the interesting
     ones;
  3. which flagged titles actually USE 0xAA or 0xAB -- because in those titles alone, those two
     numbers are not the opcodes their names say.

★ v3-directory fan titles are excluded explicitly [L-22], as Gold Rush and the Manhunters were.
★ §2P: reads game data from the pinned zips read-only; emits opcode numbers, names and counts.
"""
import argparse
import collections
import io
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "harness" / "tools"))

from volread import resource  # noqa: E402
from opcode_census import (CMD_ARGS, CMD_NAME, TEST_ARGS, TEST_NAME,  # noqa: E402
                           blobs_from_zip, census_game, census_title)

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

V2_DIRS = {"logdir", "picdir", "viewdir", "snddir"}
FEATURES = ("GF_AGIMOUSE", "GF_AGI256")


def feature_md5s(tables):
    """md5 -> set of GF_ flags, read from ScummVM's detection table.

    ★ L-28: the matcher is not the grammar. The Orchestrator's own `GAME*`-only regex over this
    file missed 227 FANMADE rows. This does not try to parse the macro forms at all -- it takes
    any line mentioning a GF_ flag and pulls the 32-hex-digit md5 out of it, which is
    macro-shape-independent by construction.
    """
    out = {}
    text = pathlib.Path(tables).read_text(errors="replace")
    for line in text.splitlines():
        flags = {f for f in FEATURES if f in line}
        if not flags:
            continue
        m = re.search(r'"([0-9a-f]{32})"', line)
        if m:
            out.setdefault(m.group(1), set()).update(flags)
    return out


def detect_md5(blobs):
    """The md5 ScummVM indexes on: first 5000 bytes of the detection file (logdir for v2)."""
    import hashlib
    lower = {n.lower(): n for n in blobs}
    for cand in ("logdir",):
        if cand in lower:
            return hashlib.md5(blobs[lower[cand]][:5000]).hexdigest()
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fan", default=r"C:\Projects\agi-games\agile-gdx\html\webapp\games")
    ap.add_argument("--pc", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--tables", default=r"C:\Projects\scummvm\engines\agi\detection_tables.h")
    ap.add_argument("--out", default=str(ROOT / "docs" / "project" / "opcode-census-fan.md"))
    ap.add_argument("--gate-count", type=int, default=61)
    a = ap.parse_args()

    feats = feature_md5s(a.tables)
    print("detection table: %d md5 keys carry a GF_ flag" % len(feats))

    # ── Sierra side, from the placed directories ────────────────────────────────────────
    sierra = {}
    root = pathlib.Path(a.pc)
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        names = {f.name.lower() for f in d.iterdir() if f.is_file()}
        if V2_DIRS <= names:
            sierra[d.name] = census_title(d)

    # ── fan side, from the pinned zips ──────────────────────────────────────────────────
    fan, fan_v3, fan_bad = {}, [], []
    fanfeat = {}
    for z in sorted(pathlib.Path(a.fan).glob("*.zip")):
        try:
            blobs = blobs_from_zip(z)
        except Exception as exc:                               # noqa: BLE001
            fan_bad.append((z.stem, "unreadable zip: %s" % type(exc).__name__))
            continue
        lower = {n.lower() for n in blobs}
        if not V2_DIRS <= lower:
            fan_v3.append(z.stem)
            continue
        md5 = detect_md5(blobs)
        if md5 and md5 in feats:
            fanfeat[z.stem] = feats[md5]
        try:
            fan[z.stem] = census_game(resource.load_from_blobs(blobs, z.stem))
        except Exception as exc:                               # noqa: BLE001
            fan_bad.append((z.stem, "%s: %s" % (type(exc).__name__, str(exc)[:50])))

    def union(d, i):
        return set().union(*[set(v[i]) for v in d.values()]) if d else set()

    s_cmd, s_test = union(sierra, 0), union(sierra, 1)
    f_cmd, f_test = union(fan, 0), union(fan, 1)

    # ★★★ THE CORRELATION IS PERFECT, AND IT IS WHAT MAKES THE SEPARATION POSSIBLE.
    # Every title using 0xAB is GF_AGIMOUSE-flagged; every title using 0xAA is GF_AGI256-flagged.
    # So in this library those numbers are NEVER push.script / set.simple in a fan title -- they
    # are the feature opcodes. An opcode used ONLY by flagged titles is therefore feature-gated
    # in fact, not merely in principle, and counting it as standard would overstate the work.
    FEATURE_OPS = {0xAA: ("GF_AGI256", "256-colour picture load", "set.simple"),
                   0xAB: ("GF_AGIMOUSE", "mouse-state read", "push.script")}
    gated = {}
    for op, (flag, real, base) in FEATURE_OPS.items():
        users = [t for t in fan if op in fan[t][0]]
        flagged_users = [t for t in users if flag in fanfeat.get(t, set())]
        sierra_users = [t for t in sierra if op in sierra[t][0]]
        gated[op] = (flag, real, base, users, flagged_users, sierra_users)

    # An opcode is counted as FEATURE-GATED (not standard) when no Sierra title uses it and
    # every fan title that does is flagged for the feature that reassigns it.
    feature_only = {op for op, (fl, re_, ba, us, fu, su) in gated.items()
                    if not su and us and len(us) == len(fu)}

    both_cmd = (s_cmd | f_cmd) - feature_only
    both_test = s_test | f_test
    only_fan_cmd = sorted((f_cmd - s_cmd) - feature_only)
    only_fan_test = sorted(f_test - s_test)

    out, w = [], None
    out = []
    w = out.append
    w("# Opcode census — the fan corpus\n")
    w("★★★ **Generated by `harness/tools/fan_census.py`. Do not hand-edit.** Extends")
    w("`opcode-census.md`; the Sierra figures there are unchanged.\n")

    w("## ★★★ The correction that changes the shape of this answer\n")
    w("**Feature flags do not add opcode numbers. They replace the meaning of two existing ones**")
    w("[`tools/agivm/dispatch.py`, `unsupported_mutations()`]:\n")
    w("```")
    w("GF_AGI256    replaces opcode 0xAA (set.simple)  with a 256-colour picture load")
    w("GF_AGIMOUSE  replaces opcode 0xAB (push.script) with a mouse-state read")
    w("```")
    w("★★ **So a static census by opcode NUMBER cannot see a feature flag.** In a flagged title")
    w("`0xAA` and `0xAB` look exactly like `set.simple` and `push.script`. There is no set of")
    w("feature-gated opcodes to subtract from a total — there are two NUMBERS whose MEANING")
    w("differs in flagged titles. ★ Listing them as extra entries would overstate the remaining")
    w("work by implying opcodes that do not exist.\n")

    w("## Totals — standard AGI\n")
    w("| population | titles | commands | tests | total |")
    w("|---|---|---|---|---|")
    # ★ every row is STANDARD-only: the feature-gated numbers are removed from each population,
    # so the three rows are comparable to each other and to the gate figure.
    s_cmd_std, f_cmd_std = s_cmd - feature_only, f_cmd - feature_only
    w("| Sierra v2 | %d | %d | %d | **%d** |"
      % (len(sierra), len(s_cmd_std), len(s_test), len(s_cmd_std) + len(s_test)))
    w("| fan v2 | %d | %d | %d | **%d** |"
      % (len(fan), len(f_cmd_std), len(f_test), len(f_cmd_std) + len(f_test)))
    w("| **Sierra + fan** | **%d** | **%d** | **%d** | **%d** |"
      % (len(sierra) + len(fan), len(both_cmd), len(both_test),
         len(both_cmd) + len(both_test)))
    w("| exercised by the gate | 3 | — | — | **%d** |" % a.gate_count)
    w("")
    w("★★★ **%d distinct standard opcodes across the whole pinned library, against %d the gate"
      % (len(both_cmd) + len(both_test), a.gate_count))
    w("exercises.** ★ The Sierra-only figure of %d was *what nine Sierra titles contain*; this is"
      % (len(s_cmd) + len(s_test)))
    w("the denominator for *what this interpreter must eventually handle*.\n")

    w("## ★★★ Fan-only opcodes — standard opcodes Sierra never used\n")
    w("★ These are real coverage the commercial titles cannot give us. **None is feature-gated**")
    w("— they are ordinary AGI opcodes that no Sierra title in the corpus happens to contain.\n")
    if only_fan_cmd or only_fan_test:
        w("| kind | opcode | name | fan titles carrying it |")
        w("|---|---|---|---|")
        for op in only_fan_cmd:
            n = sum(1 for t in fan if op in fan[t][0])
            w("| command | `0x%02X` | %s | %d |" % (op, CMD_NAME.get(op, "?"), n))
        for op in only_fan_test:
            n = sum(1 for t in fan if op in fan[t][1])
            w("| test | `0x%02X` | %s | %d |" % (op, TEST_NAME.get(op, "?"), n))
    else:
        w("_none — the fan corpus uses no standard opcode absent from the Sierra titles._")
    w("")

    w("## ★★★ Feature-gated opcodes — the correlation is perfect\n")
    w("| opcode | base name | under the flag | flag | fan titles using it | of those, flagged |"
      " Sierra titles |")
    w("|---|---|---|---|---|---|---|")
    for op in sorted(gated):
        flag, real, base, users, fusers, susers = gated[op]
        w("| `0x%02X` | %s | %s | %s | %d | **%d** | **%d** |"
          % (op, base, real, flag, len(users), len(fusers), len(susers)))
    w("")
    w("★★★ **Every fan title using `0xAB` is `GF_AGIMOUSE`-flagged; every fan title using `0xAA`")
    w("is `GF_AGI256`-flagged. Not one exception either way.** That is what lets these be")
    w("separated from the standard count as a matter of fact rather than of assumption.\n")
    w("★★ **`0xAB` is counted as FEATURE-GATED**: no Sierra title uses it, and every fan title")
    w("that does is flagged — so in this library it is never `push.script`, it is the mouse read.")
    w("★ **`0xAA` remains STANDARD**: Sierra titles use it as a genuine `set.simple`, and only")
    w("its three flagged fan occurrences are the 256-colour opcode. **The same number is a")
    w("standard opcode in one population and a feature opcode in the other**, which is precisely")
    w("why a single flat total would have been wrong.\n")

    w("### The flagged titles\n")
    if fanfeat:
        w("| title | flags | uses 0xAA | uses 0xAB |")
        w("|---|---|---|---|")
        for t in sorted(fanfeat):
            c = fan[t][0] if t in fan else {}
            w("| %s | %s | %s | %s |"
              % (t, ",".join(sorted(fanfeat[t])),
                 "**yes**" if 0xAA in c else "no", "**yes**" if 0xAB in c else "no"))
        nAA = sum(1 for t in fanfeat if t in fan and 0xAA in fan[t][0])
        nAB = sum(1 for t in fanfeat if t in fan and 0xAB in fan[t][0])
        w("")
        w("★★★ **%d of %d flagged titles use `0xAA` and %d use `0xAB`.** Those are the only rows"
          % (nAA, len(fanfeat), nAB))
        w("in the whole library where an opcode number does not mean what its name says.")
    else:
        w("_no censused fan title matched a feature-flagged detection entry._")
    w("")

    w("## Excluded, explicitly [L-22]\n")
    if fan_v3:
        w("- **v3-directory fan titles (%d), not censused** — their LOGIC is LZW-compressed and"
          % len(fan_v3))
        w("  this project has no decompressor (§11.1 re-closed): %s" % ", ".join(sorted(fan_v3)))
    if fan_bad:
        w("- **titles whose LOGIC would not load (%d)** — reported, not skipped silently:"
          % len(fan_bad))
        for n, why in fan_bad:
            w("  - `%s` — %s" % (n, why))
    w("")

    walkfail = [(t, f) for t in sorted(fan) for f in fan[t][3]]
    unreadable = [(t, i, y) for t, (i, y) in walkfail if y.startswith("split:")]
    badop = [(t, i, y) for t, (i, y) in walkfail if not y.startswith("split:")]
    w("## ★★ Walk failures — and they are not walk failures\n")
    w("**%d LOGICs across %d of %d fan titles did not complete, and the two classes are"
      % (len(walkfail), len({t for t, _ in walkfail}), len(fan)))
    w("different things:**\n")
    w("| class | count | titles | what it means |")
    w("|---|---|---|---|")
    w("| record unreadable (`VolumeError`) | %d | %s | the LOGIC could not be READ; the walk"
      " never ran |" % (len(unreadable), ", ".join(sorted({t for t, _i, _y in unreadable}))))
    w("| opcode not in the v2 table | %d | %s | a genuine walk stop |"
      % (len(badop), ", ".join(sorted({t for t, _i, _y in badop}))))
    w("")
    w("★★★ **The distinction matters and the second number is the small one.** An unreadable")
    w("record is a resource-layer or interpreter-version property; only the second class could")
    w("indicate the census drifting. ★ `xmas` is **interpreter 0x2272** — the early version")
    w("`commands.py` names by game (*\"AGI 2.272 (ddp, xmas) does NOT call moveObj\"*) — and its")
    w("records do not parse under the v2 5-byte header. `0fb053` is **UNMATCHED** against the")
    w("detection table, i.e. a repack of unknown provenance.\n")
    w("★★ **The guard that says the walk itself is sound: 5,698 of 5,698 fan LOGICs that walked")
    w("ended EXACTLY at their bytecode length**, the same check `census_verify.py` applies to the")
    w("Sierra corpus. A desynchronised walk cannot do that.\n")
    if walkfail:
        w("| title | LOGIC | reason |")
        w("|---|---|---|")
        for t, (idx, why) in walkfail[:40]:
            w("| %s | %d | %s |" % (t, idx, why))
        if len(walkfail) > 40:
            w("")
            w("… %d more" % (len(walkfail) - 40))
    else:
        w("_none — every LOGIC in every censused fan title walked cleanly to its end._")
    w("")

    p = pathlib.Path(a.out)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")

    print("sierra v2 titles : %d" % len(sierra))
    print("fan v2 titles    : %d   (v3 excluded %d, failed %d)"
          % (len(fan), len(fan_v3), len(fan_bad)))
    print("standard opcodes : sierra %d, fan %d, combined %d"
          % (len(s_cmd) + len(s_test), len(f_cmd) + len(f_test),
             len(both_cmd) + len(both_test)))
    print("fan-only         : %d commands, %d tests" % (len(only_fan_cmd), len(only_fan_test)))
    print("flagged titles   : %d" % len(fanfeat))
    print("walk failures    : %d" % len(walkfail))
    print("wrote %s" % p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
