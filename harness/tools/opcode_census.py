#!/usr/bin/env python3
"""harness/tools/opcode_census.py -- AC-7: which opcodes the CORPUS contains, statically.

★★★ THIS IS THE COMPLEMENT TO vm_opcov.py, NOT A REPLACEMENT. vm_opcov.py counts opcodes
EXECUTED by three King's Quest titles over 600 cycles each -- their opening scenes. This counts
opcodes PRESENT in every LOGIC of every title. "Which opcodes can the gate check" and "which
opcodes does the corpus contain" are different questions and only the first had ever been asked
[X-53]. Both numbers are wanted and they mean different things.

★★★ IT WALKS THE INSTRUCTION STREAM. IT DOES NOT HISTOGRAM BYTES. A byte histogram counts
operands as opcodes -- `assignn(v25, 0x16)` would register a `call`, and the total would be
inflated by exactly the opcodes that look like common constants. The walk is the same one the
interpreter does:
    0xFF  a condition expression; its own stream, with `said` variable-length
    0xFE  goto, two operand bytes
    0x00  return
    else  a command, with VMOP_ARGS[op] operand bytes
★★ Operand counts come from optable.py -- generated from the pinned oracle -- never typed here
(L-29, and P4.4 is the cautionary tale: two hand-typed constants cost a gate).

★★ v3 TITLES ARE EXCLUDED AND THE EXCLUSION IS EXPLICIT [L-22]. Their LOGIC is LZW-compressed
and this project has no decompressor (§11.1 re-closed). They are named in the output as
excluded, with the reason, rather than silently absent.

★ §2P: reads game data; emits opcode numbers, names and counts. No game text, no resource bytes.
"""
import argparse
import collections
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import optable  # noqa: E402
from volread import logic as logic_mod, resource  # noqa: E402

SAID = 0x0E
CMD_ARGS = {i: len(p) for i, (n, p, h) in enumerate(optable.V2_COMMANDS)}
CMD_NAME = {i: n for i, (n, p, h) in enumerate(optable.V2_COMMANDS)}
TEST_ARGS = {i: len(p) for i, (n, p, h) in enumerate(optable.V2_TESTS)}
TEST_NAME = {i: n for i, (n, p, h) in enumerate(optable.V2_TESTS)}


class WalkError(Exception):
    pass


def walk(code, cmds, tests):
    """Walk one LOGIC's bytecode, recording opcodes reached. Raises on a malformed stream."""
    ip = 0
    n = len(code)
    while ip < n:
        op = code[ip]
        ip += 1
        if op == 0xFF:
            ip = walk_expr(code, ip, tests)
            ip += 2                       # the branch word
            continue
        if op == 0xFE:
            ip += 2
            continue
        if op == 0x00:
            continue                      # `return` -- keep scanning; a LOGIC has many
        if op not in CMD_ARGS:
            raise WalkError("command opcode %02X at %d is not in the v2 table" % (op, ip - 1))
        cmds[op] += 1
        ip += CMD_ARGS[op]
    return ip


def walk_expr(code, ip, tests):
    """The 0xFF condition expression: 0xFC or / 0xFD not / 0xFF or 0x00 end / else a test."""
    n = len(code)
    while ip < n:
        op = code[ip]
        ip += 1
        if op in (0xFC, 0xFD):
            continue
        if op in (0x00, 0xFF):
            return ip
        if op not in TEST_ARGS:
            raise WalkError("test opcode %02X at %d is not in the v2 table" % (op, ip - 1))
        tests[op] += 1
        if op == SAID:
            # ★ variable length: a count byte, then that many 16-bit words
            ip += code[ip] * 2 + 1
        else:
            ip += TEST_ARGS[op]
    return ip


def census_title(path):
    game = resource.load_from_files(str(path))
    cmds, tests = collections.Counter(), collections.Counter()
    nlogic, failed = 0, []
    for e in game.dirs["LOGIC"]:
        if not e.present:
            continue
        try:
            lg = logic_mod.split(game.load("LOGIC", e.index), index=e.index)
        except Exception as exc:                              # noqa: BLE001
            failed.append((e.index, "split: %s" % type(exc).__name__))
            continue
        try:
            walk(lg.bytecode, cmds, tests)
            nlogic += 1
        except Exception as exc:                              # noqa: BLE001
            failed.append((e.index, str(exc)[:60]))
    return cmds, tests, nlogic, failed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--out", default=str(ROOT / "docs" / "project" / "opcode-census.md"))
    ap.add_argument("--gate-count", type=int, default=61,
                    help="opcodes the gate exercises, from vm_opcov.py")
    a = ap.parse_args()

    root = pathlib.Path(a.root)
    V2, V3, SKIP = [], [], []
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        names = {f.name.lower() for f in d.iterdir() if f.is_file()}
        if {"logdir", "picdir", "viewdir", "snddir"} <= names:
            V2.append(d)
        elif any(x.endswith("dir") for x in names) and any("vol." in x for x in names):
            V3.append(d)
        else:
            SKIP.append(d)

    per = {}
    for d in V2:
        try:
            per[d.name] = census_title(d)
        except Exception as exc:                              # noqa: BLE001
            SKIP.append(d)
            print("  ★ %s: %s" % (d.name, exc), file=sys.stderr)

    titles = sorted(per)
    cmd_sets = {t: set(per[t][0]) for t in titles}
    test_sets = {t: set(per[t][1]) for t in titles}
    common_cmd = set.intersection(*cmd_sets.values()) if cmd_sets else set()
    common_test = set.intersection(*test_sets.values()) if test_sets else set()
    all_cmd = set().union(*cmd_sets.values()) if cmd_sets else set()
    all_test = set().union(*test_sets.values()) if test_sets else set()

    out = []
    w = out.append
    w("# Opcode census — what the CORPUS contains\n")
    w("★★★ **Generated by `harness/tools/opcode_census.py`. Do not hand-edit.**\n")
    w("★★ **This is a STATIC census: opcodes PRESENT in every LOGIC of every v2 title.** It is the")
    w("complement to `vm_opcov.py`, which counts opcodes EXECUTED by three King's Quest titles over")
    w("600 cycles each. *Which opcodes can the gate check* and *which opcodes does the corpus")
    w("contain* are different questions [X-53]; both numbers are below and they mean different")
    w("things.\n")
    w("★★ **The stream is WALKED, not histogrammed.** A byte histogram counts operands as opcodes")
    w("— `assignn(v25, 0x16)` would register a `call`. Operand lengths come from `optable.py`,")
    w("generated from the pinned oracle (L-29).\n")

    w("## Totals\n")
    w("| | commands | tests | total |")
    w("|---|---|---|---|")
    w("| **present in the corpus** | **%d** | **%d** | **%d** |"
      % (len(all_cmd), len(all_test), len(all_cmd) + len(all_test)))
    w("| present in ALL %d titles | %d | %d | %d |"
      % (len(titles), len(common_cmd), len(common_test), len(common_cmd) + len(common_test)))
    w("| exercised by the gate (`vm_opcov.py`, 3 titles × 600 cycles) | — | — | **%d** |"
      % a.gate_count)
    w("")
    w("★★★ **%d distinct opcodes appear in the corpus against the %d the gate exercises — a"
      % (len(all_cmd) + len(all_test), a.gate_count))
    w("factor of %.1f.** That gap is the size of the remaining VM work.\n"
      % ((len(all_cmd) + len(all_test)) / a.gate_count))

    w("## Titles censused (%d, all AGI v2)\n" % len(titles))
    w("| title | LOGICs | commands | tests |")
    w("|---|---|---|---|")
    for t in titles:
        cmds, tests, nlogic, failed = per[t]
        w("| %s | %d | %d | %d |" % (t, nlogic, len(cmds), len(tests)))
    w("")

    if V3 or SKIP:
        w("## Excluded, explicitly [L-22]\n")
        for d in V3:
            w("- **%s** — AGI v3. ★★ Its LOGIC is **LZW-compressed** and this project has no"
              % d.name)
            w("  decompressor (§11.1 re-closed, manifest only). **Not censused**, and its opcode")
            w("  set is therefore unknown rather than empty.")
        for d in SKIP:
            w("- **%s** — not an AGI v2 directory (SCI, or a non-AGI Sierra format)." % d.name)
        w("")

    def table(nameof, ids, counts_by_title):
        rows = []
        for op in sorted(ids):
            rows.append("`0x%02X` %s" % (op, nameof.get(op, "?")))
        return rows

    w("## Common set — present in ALL %d titles\n" % len(titles))
    w("**Commands (%d):**\n" % len(common_cmd))
    w(", ".join(table(CMD_NAME, common_cmd, None)) or "_none_")
    w("")
    w("**Tests (%d):**\n" % len(common_test))
    w(", ".join(table(TEST_NAME, common_test, None)) or "_none_")
    w("")

    w("## Per title — opcodes NOT in the common set\n")
    for t in titles:
        extra_c = sorted(cmd_sets[t] - common_cmd)
        extra_t = sorted(test_sets[t] - common_test)
        if not extra_c and not extra_t:
            w("**%s** adds: _nothing beyond the common set_\n" % t)
            continue
        w("**%s** adds:\n" % t)
        if extra_c:
            w("- commands: %s" % ", ".join(table(CMD_NAME, extra_c, None)))
        if extra_t:
            w("- tests: %s" % ", ".join(table(TEST_NAME, extra_t, None)))
        w("")

    w("## Never present in any title\n")
    never_c = sorted(set(CMD_ARGS) - all_cmd)
    never_t = sorted(set(TEST_ARGS) - all_test - {0})
    w("**Commands (%d of %d):**\n" % (len(never_c), len(CMD_ARGS)))
    w(", ".join(table(CMD_NAME, never_c, None)) or "_none_")
    w("")
    w("**Tests (%d of %d):**\n" % (len(never_t), len(TEST_ARGS) - 1))
    w(", ".join(table(TEST_NAME, never_t, None)) or "_none_")
    w("")

    # ── which titles are UNIQUE carriers of an opcode -- the ones that matter for scope ──
    w("## Opcodes carried by only ONE title\n")
    w("★ These are the rows a corpus of three King's Quest titles could never have found.\n")
    solo = []
    for op in sorted(all_cmd):
        who = [t for t in titles if op in cmd_sets[t]]
        if len(who) == 1:
            solo.append(("cmd", op, CMD_NAME.get(op, "?"), who[0]))
    for op in sorted(all_test):
        who = [t for t in titles if op in test_sets[t]]
        if len(who) == 1:
            solo.append(("test", op, TEST_NAME.get(op, "?"), who[0]))
    if solo:
        w("| kind | opcode | name | only in |")
        w("|---|---|---|---|")
        for k, op, nm, t in solo:
            w("| %s | `0x%02X` | %s | %s |" % (k, op, nm, t))
    else:
        w("_none — every opcode present appears in at least two titles._")
    w("")

    failures = [(t, f) for t in titles for f in per[t][3]]
    w("## Walk failures\n")
    if failures:
        w("★★ A LOGIC whose stream could not be walked is reported, not skipped silently.\n")
        w("| title | LOGIC | reason |")
        w("|---|---|---|")
        for t, (idx, why) in failures[:40]:
            w("| %s | %d | %s |" % (t, idx, why))
        if len(failures) > 40:
            w("")
            w("… %d more" % (len(failures) - 40))
    else:
        w("_none — every LOGIC in every censused title walked cleanly to its end._")
    w("")

    text = "\n".join(out) + "\n"
    p = pathlib.Path(a.out)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="\n")

    print("titles censused : %d" % len(titles))
    print("v3 excluded     : %s" % ", ".join(d.name for d in V3) or "-")
    print("other excluded  : %s" % ", ".join(d.name for d in SKIP) or "-")
    print("distinct opcodes: %d commands + %d tests = %d"
          % (len(all_cmd), len(all_test), len(all_cmd) + len(all_test)))
    print("common to all   : %d" % (len(common_cmd) + len(common_test)))
    print("gate exercises  : %d" % a.gate_count)
    print("walk failures   : %d" % len(failures))
    print("wrote %s" % p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
