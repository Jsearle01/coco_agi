#!/usr/bin/env python3
"""harness/tools/vm_input_script.py -- derive a scripted input for the VM gate. [T-P0-060 AC-4]

★★★★★ THE PARSER WAS A FUNCTION WITH NO CALLER, AND A CALLER NEEDS SOMETHING TO SAY. This
builds that something, and it builds it from the GAME rather than from my imagination: it runs
the reference for the gated window with no input, records every said() the game actually
evaluates, and synthesises a line of text for each operand pattern that is made of real word
numbers.

★★★★ EVERY LINE IS VERIFIED BEFORE IT IS EMITTED. A synthesised line is only useful if it
tokenises back to the operands it was built from -- and it may not, because "the LAST full match
in bucket order wins" can pick a different entry for a spelling that is a prefix of another
[parser.s par_find]. So each candidate is run through parse_using_dictionary and kept ONLY if
the resulting word numbers equal the pattern. **A generator that assumes its own output is the
same class of instrument as a gate that has never failed** [§2W].

★★★ WHY NOT JUST TYPE "look" AND BE DONE. Because a said() that never matches exercises the
guard and nothing else, and the guard is the half that already worked (the stub satisfied it).
The value of this gate is said() returning TRUE and the game branching on it, and that only
happens for operands the game actually tests.

★★ §2P: game text is copyrighted. The generated script goes to build/ (untracked) and this
script prints COUNTS, CYCLE NUMBERS and WORD NUMBERS only -- never a spelling. --show-text is
deliberately not offered.

usage:
  python harness/tools/vm_input_script.py <game-dir> --out build/vm_stage/<title>/input.txt
        [--cycles 600] [--max-lines 12]
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import cycle as cycle_mod        # noqa: E402
from agivm import parser as ap              # noqa: E402
from volread import resource                # noqa: E402
from volread import words as words_mod      # noqa: E402


def spellings_by_id(game_dir):
    d = words_mod.parse((pathlib.Path(game_dir) / "WORDS.TOK").read_bytes())
    by_id = {}
    for w, wid, _letter in d.words:
        by_id.setdefault(wid, []).append(w.decode("latin-1"))
    # ★ Shortest spelling first: a shorter word is less likely to contain a separator or an
    # invalid character, and cleanUpInput's handling of those is the part with the most rules.
    for k in by_id:
        by_id[k].sort(key=len)
    return by_id, d.words


def main():
    ap_ = argparse.ArgumentParser()
    ap_.add_argument("game_dir")
    ap_.add_argument("--out", required=True)
    ap_.add_argument("--cycles", type=int, default=600)
    ap_.add_argument("--max-lines", type=int, default=12)
    # ★★★★★ --eye: KEEP ONLY LINES WHOSE said() BRANCH IS VISIBLE, for §4A's eye gate.
    # ★★★★ Kingquest1's first verified script quits the game at cycle 29 -- a said() matched and
    # its branch reached quit. **That is the wiring working and it is a terrible thing to show
    # Jay**: the screen stops. An eye gate has to produce something a person can SEE, and with
    # text rendering out of scope [T-P0-060 §13] the visible channel is the ROOM.
    # ★★★ So each candidate is run ON ITS OWN against the reference and kept only if it moves
    # VAR_CURRENT_ROOM and does not quit. That is a MEASUREMENT of each line's effect, not a
    # guess about it -- and it is the difference between an eye gate that demonstrates something
    # and one that demonstrates that something happened.
    ap_.add_argument("--eye", action="store_true",
                     help="keep only lines that change VAR_CURRENT_ROOM and do not quit")
    a = ap_.parse_args()

    game = resource.load_from_files(a.game_dir)
    by_id, entries = spellings_by_id(a.game_dir)
    vocab = ap.Vocabulary(entries)

    # ── 1. the census: what does this game actually ask said() about? ───────────────────
    # ★ No input fed here, so this run is the ordinary gate run and the census is a property of
    # the GAME, not of a script I have already chosen.
    vm = cycle_mod.Vm(game, 0x2917)
    vm.said_trace = []
    vm.start()
    vm.run(max_cycles=a.cycles)

    # said_trace rows: (cycle_nr, logic_nr, n, operands, ego, entered_cli, result)
    # ★★ cycle_nr is read AFTER interpret_cycle() incremented it, so the cycle whose BODY is
    # running is cycle_nr - 1. The script's cycle numbers must be body numbers, because that is
    # what both legs feed against.
    first_at = {}
    for row in vm.said_trace:
        pat = tuple(row[3])
        body_cycle = row[0] - 1
        if pat and pat not in first_at and body_cycle >= 1:
            first_at[pat] = body_cycle

    print("game        : %s" % a.game_dir)
    print("said() evaluated : %d times over %d cycles, %d distinct operand patterns"
          % (len(vm.said_trace), a.cycles, len(first_at)))

    # ── 2. keep only patterns we can build a verified line for ─────────────────────────
    # ★ 1 ("any single word") and 9999 ("rest of line") are said() wildcards, not word numbers,
    # and 0 is IGNORE. None of them has a spelling, so a pattern containing one cannot be
    # synthesised whole -- those are exercised by the 23,328-case parser gate, not here.
    # ★★★★★ THE WILDCARDS ARE NOT UNSYNTHESISABLE, AND REJECTING THEM THREW AWAY THE GAMEPLAY.
    # The first version dropped every pattern containing 1 or 9999 on the grounds that they have
    # no spelling. They do not need one:
    #     9999  "rest of line, INCLUDING nothing" [parser.s par_said] -- so it is satisfied by
    #           adding NOTHING, and a said(verb, 9999) is matched by typing just the verb.
    #     1     "any single word" -- satisfied by any real word at that position.
    # ★★★★ AND THOSE ARE EXACTLY THE PATTERNS THAT MATTER. A bare said(a,b) is how a game tests
    # a meta-command; `said(<verb>, 9999)` is how it tests a sentence. Kingquest1's four
    # rejected patterns were four of its fifteen, and every gameplay-shaped one was among them.
    # ★★★ THE VERIFICATION CHANGED WITH IT, and it was wrong before in a way that mattered.
    # "the line must tokenise back to exactly the operands" is the wrong question -- said() does
    # not require equality, it requires a MATCH. So the check is now test_said() itself, run
    # against this line's own tokenised words: **ask the function under test.**
    filler = None
    for wid in sorted(by_id):
        if wid not in (0, 1, 9999) and by_id[wid]:
            filler = by_id[wid][0]
            break

    def synthesise(pat):
        parts = []
        for w in pat:
            if w == 9999:
                break                        # "rest of line, including nothing"
            if w == 1:
                if filler is None:
                    return None
                parts.append(filler)         # "any single word"
            elif w == 0 or w not in by_id:
                return None
            else:
                parts.append(by_id[w][0])
        return " ".join(parts) if parts else None

    chosen, rejected_wild, rejected_verify, rejected_nospell = [], 0, 0, 0
    for pat, cyc in sorted(first_at.items(), key=lambda kv: kv[1]):
        text = synthesise(pat)
        if text is None:
            rejected_nospell += 1
            continue
        ego, _nf, cli = ap.parse_using_dictionary(text, vocab)
        # ★★★ said()'s own guard needs ENTERED_CLI, and a said() that has already accepted input
        # this cycle rejects everything -- so the probe is the first said() of a fresh line.
        matched, _acc = ap.test_said(list(pat), ego, False, cli)
        if not (cli and matched):
            rejected_verify += 1
            continue
        chosen.append((cyc, pat, text))

    print("patterns rejected: %d unsynthesisable, %d do not match their own line "
          "(%d wildcard patterns now KEPT rather than dropped)"
          % (rejected_nospell, rejected_verify, rejected_wild))

    # ══════════════════════════════════════════════════════════════════════════════════════
    # ★★★★★ CLASSIFY EVERY LINE BY WHAT IT DOES TO THE RUN, AND SCHEDULE THE TERMINAL ONES LAST.
    # ★★★★ Kingquest3's census puts said(13,237) first, and that line reaches restart.game. Fed
    # at cycle 1 the whole run ends at cycle 2 -- a two-cycle trace, which is correct and is not
    # a diff. Kingquest1's quit line does the same at cycle 140.
    # ★★★★★ THIS IS NOT FILTERING THE TEST TO MAKE IT PASS, and the distinction matters: a
    # terminal line is still fed, still gated, and the other leg must reproduce the stop at the
    # SAME cycle or vm_diff.py fails on the length [T-P0-060 AC-4 gates exactly that on KQ1].
    # **What changes is the ORDER**, so the window is covered before the run ends rather than
    # instead of it. Ordering a corpus is a corpus decision and it is stated here.
    # ★★★ A line that RAISES is excluded, because there is no reference behaviour to gate
    # against -- and which opcode it reached is printed, since that is the coverage fact.
    # ★★ One probe run per candidate. They are short and the alternative is a schedule whose
    # effect nobody measured, which is how the two-cycle trace happened.
    if not a.eye and chosen:
        base = cycle_mod.Vm(game, 0x2917)
        base.start()
        base.run(max_cycles=a.cycles)
        quiet, terminal, raised = [], [], []
        at = max(2, a.cycles // 4)
        for cyc, pat, text in chosen:
            probe = cycle_mod.Vm(game, 0x2917)
            probe.load_vocabulary(entries)
            probe.input_script = {at: text}
            probe.start()
            try:
                probe.run(max_cycles=a.cycles)
            except Exception as exc:                        # noqa: BLE001
                raised.append((pat, str(exc).split("(")[0].strip()))
                continue
            if probe.should_quit or probe.should_restart:
                terminal.append((cyc, pat, text))
            else:
                quiet.append((cyc, pat, text))
        # ★★★★★ "RAISE", NOT "REACH AN UNIMPLEMENTED OPCODE". The first version of this line said
        # the latter, and then the per-cycle watchdog started firing -- so two Kingquest3 lines
        # that hit a NON-TERMINATING logic were reported under a label that named a different
        # cause. ★★★ That is `said_gate.py --results` printing the 6809 side as `oracle` [P6.3
        # §3.F.3], one task later and by the same hand: **a label that names the usual cause
        # instead of the actual one.** The reason string is printed per line and is the fact; the
        # heading now says only that the line raised.
        print("lines classified : %d continue, %d end the run, %d raise (see each reason)"
              % (len(quiet), len(terminal), len(raised)))
        for pat, why in raised:
            print("   ★★★ said(%-12s %s" % (",".join(str(x) for x in pat) + ")", why))
        for _c, pat, _t in terminal:
            print("   ★ said(%-12s ends the run -- scheduled LAST"
                  % (",".join(str(x) for x in pat) + ")"))
        # ★ At most ONE terminal line, and it goes last: two would make the second unreachable
        # and a script whose file does not describe what runs is the defect this tool avoids.
        chosen = quiet + terminal[:1]

    # ── 2b. --eye: measure each candidate's effect, one line per run ────────────────────
    if a.eye:
        at = max(2, a.cycles // 4)          # ★ late enough that the room is drawn and settled
        base = cycle_mod.Vm(game, 0x2917)
        base.start()
        base.run(max_cycles=a.cycles)
        base_room, base_delay = base.get_var(0), base.get_var(10)
        visible, quiet, quits, unimpl = [], 0, 0, []
        for cyc, pat, text in chosen:
            probe = cycle_mod.Vm(game, 0x2917)
            probe.load_vocabulary(entries)
            probe.input_script = {at: text}
            probe.start()
            # ★★★★★ AN UNIMPLEMENTED OPCODE HERE IS A RESULT, NOT A CRASH -- and it is this
            # task's least expected finding. The nine-title VM gate has been byte-identical for
            # tasks, and it never executed restart.game or restore.game because **without input
            # an AGI game sits in attract mode and never takes those branches**. Feeding a line
            # opens them: Kingquest3 reaches restart.game and Kingquest1 reaches restore.game,
            # both of which dispatch.py raises on deliberately rather than no-opping.
            # ★★★★ So the parser is not only a subsystem, it is the DOOR to a part of the
            # command space the gate has never covered. Recording which opcode each line reaches
            # is worth more than the line itself.
            try:
                probe.run(max_cycles=a.cycles)
            except Exception as exc:                        # noqa: BLE001
                unimpl.append((pat, str(exc).split("(")[0].strip()))
                continue
            room, delay = probe.get_var(0), probe.get_var(10)
            if probe.should_quit:
                quits += 1
            elif room != base_room:
                visible.append((cyc, pat, text, "room %d -> %d" % (base_room, room), 0))
            elif delay != base_delay:
                # ★★★★★ THE SPEED WORDS ARE THE EYE GATE, AND THEY ARE THE GAME'S OWN ANSWER.
                # VAR_TIME_DELAY is the animation rate; P6.3 §3.G established that fast/normal/
                # slow are ORDINARY VOCABULARY with ordinary word numbers in every title
                # measured, so a said(fast) that moves var 10 is **the game's LOGIC responding
                # to a typed command**, not ScummVM's handleSpeedCommands interception, which is
                # a normalisation sitting above the parser and is out of scope (§2.1).
                # ★★★★ And it needs NO TEXT ON SCREEN, which is what makes it usable now: text
                # rendering is the next task, and a speed change is visible without it.
                # ★★★ Measured on Kingquest1: said(fast) drives var 10 from 2 to 0 and said(slow)
                # from 2 to 4 -- a doubling in each direction, over the same 120 cycles.
                visible.append((cyc, pat, text, "var10 %d -> %d" % (base_delay, delay),
                                delay - base_delay))
            else:
                quiet += 1
        print("--eye        : %d line(s) visibly change the game, %d quit, %d no visible change, "
              "%d reach an unimplemented opcode"
              % (len(visible), quits, quiet, len(unimpl)))
        # ★★★★ THE OPCODES ARE THE FINDING, NOT THE NOISE. The nine-title VM gate has never
        # executed these: without input an AGI game sits in attract mode and never takes the
        # branch. **The parser is the door to a part of the command space no gate has covered.**
        for pat, why in unimpl:
            print("   ★★★ said(%-12s %s" % (",".join(str(x) for x in pat) + ")", why))
        # ★★★ ORDER THEM SLOWEST-FIRST so an eye gate shows the change in BOTH directions: a
        # single "it got faster" is one observation and could be anything; slow then fast is the
        # same control moving twice, which is what makes it a demonstration [§2W.1's shape,
        # applied to a human's judgement rather than to a guard].
        visible.sort(key=lambda v: -v[4])
        for _c, pat, _t, what, _d in visible:
            print("   said(%-12s %s" % (",".join(str(x) for x in pat) + ")", what))
        if not visible:
            print("★★★ NO LINE PRODUCES A VISIBLE CHANGE on this title in %d cycles." % a.cycles)
            print("    That is a result: the eye gate needs a different title or more cycles.")
            return 1
        chosen = [(c, p, t) for c, p, t, _w, _d in visible]

    # ★★★★ SPREAD THEM, DO NOT DEDUPE THEM AWAY. The first version keyed one feed per cycle and
    # emitted ONE line for Kingquest1 -- because logic 0's input handler evaluates all fifteen
    # of its said() patterns in EVERY cycle, so "the cycle a pattern was first evaluated at" is
    # the same cycle for all of them. **A dedupe on that key throws away the whole census and
    # leaves a one-line script that looks deliberate.**
    # ★★★ So the census answers WHICH LINES ARE WORTH FEEDING and the stride answers WHEN. The
    # patterns are still the game's own; only the schedule is ours, and it is stated here rather
    # than being an accident of a dict key.
    # ★★ One feed per cycle is still enforced -- two lines on one cycle would silently drop one.
    # ★★★★ THE EYE GATE'S SCHEDULE IS DELIBERATE AND DIFFERENT. A byte gate wants the lines
    # spread across the window; a PERSON needs to see the BEFORE state first. So --eye starts a
    # quarter of the way in -- past the first room's ~7 s render -- and spaces the rest evenly,
    # giving Jay a baseline, then slow, then fast: the same control moving twice.
    if a.eye:
        first = max(2, a.cycles // 4)
        stride = max(1, (a.cycles - first) // (len(chosen) + 1))
    else:
        first, stride = 1, max(1, a.cycles // (a.max_lines + 1))
    seen_cycles, lines = set(), []
    for i, (cyc, pat, text) in enumerate(chosen[:a.max_lines]):
        at = (first + i * stride) if a.eye else (max(cyc, 1) + i * stride)
        if at >= a.cycles or at in seen_cycles:
            continue
        seen_cycles.add(at)
        lines.append((at, pat, text))
    lines.sort()

    out = pathlib.Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="latin-1", newline="\n") as f:
        f.write("# generated by harness/tools/vm_input_script.py -- <cycle> <text>\n")
        f.write("# feed before the body of that cycle; both legs read THIS file.\n")
        for cyc, _pat, text in lines:
            f.write("%d %s\n" % (cyc, text))

    print("lines written    : %d -> %s" % (len(lines), out))
    # ★ §2P: word NUMBERS and cycle numbers. No spellings.
    for cyc, pat, _text in lines:
        print("   cycle %-4d said(%s)" % (cyc, ",".join(str(x) for x in pat)))
    if not lines:
        print("★★★ NO VERIFIED LINES -- this title cannot exercise said() from a synthesised")
        print("    line in the gated window. That is a result, not a failure; report it.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
