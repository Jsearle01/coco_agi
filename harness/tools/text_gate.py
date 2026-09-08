"""harness/tools/text_gate.py -- the TEXT gate: our text reference against patch 0010's log.

★★★★★ THE FIRST GATE FOR A SUBSYSTEM WHOSE ORACLE THIS PROJECT HAD TO BUILD FIRST. Every text
opcode is a declared no-op on both legs and oracle/dumps/ held nothing for text until P6.15, so a
text renderer could not have been gated against anything.

★★★★★ RECTANGLES AND GLYPHS ARE REPORTED SEPARATELY -- BUT THE DISPATCH'S SPLIT NEEDED CORRECTING.
The framing was "rectangles match + checksum diverges = wrapping; rectangles diverge = geometry."
**The rectangle is DERIVED from the wrap**: backgroundSize_Width is textSize_Width * 4 + 10, and
textSize_Width is stringWordWrap's output. So a rectangle can diverge for a wrapping reason, and
this gate says which by looking at WHICH FIELD moved:

    w or x differ, y and h agree   ->  WRAPPING (a different box WIDTH came out of the wrap)
    y or h differ                  ->  wrapping changed the LINE COUNT, or geometry
    rectangles identical, sum moves ->  wrapping put different characters in the same places

★★★★ THE SWEEP REGION IS BOUNDED BY EVIDENCE, NOT ASSUMPTION. The capture holds the oracle's text
sweep AND the game's own credits drawing afterwards. They separate cleanly: every sweep glyph is
drawn (15, 8) because drawMessageBox sets charAttrib(0, 15), and the first (15, 0) glyph sits at
index 32570 -- exactly one past the last restore at 32569. The gate reads up to and including the
last R and REPORTS how many events it dropped, so the boundary is visible rather than silent.

★★★ §2P: this tool never prints message text. It reads the game's messages to feed the reference
and reports positions, colours, counts and checksums -- patch 0010's discipline.

usage:  python harness/tools/text_gate.py <game-dir> <oracle-log> [--fault-wrap]
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from agivm import text as textref                      # noqa: E402
from volread import logic as logic_mod                 # noqa: E402
from volread import resource                           # noqa: E402

MSGS_PER_LOGIC = 8      # ★ agi.cpp's sweep bound: `t < _game.logics[nr].numTexts && t < 8`


def read_oracle(path):
    """Parse the log and cut it at the last restore -- the end of the sweep."""
    lines = pathlib.Path(path).read_text(encoding="ascii", errors="replace").splitlines()
    last_r = max(i for i, l in enumerate(lines) if l.startswith("R "))
    kept, dropped = lines[:last_r + 1], lines[last_r + 1:]
    events = []
    for line in kept:
        p = line.split()
        if p[0] == "G":
            events.append(("G", int(p[1]), int(p[2]), int(p[3]), int(p[4]), int(p[5])))
        elif p[0] == "R":
            events.append(("R", int(p[1]), int(p[2]), int(p[3]), int(p[4])))
        # ★ "S" is P6.15's probe line, which proved the writer works; not a decision.
    return events, len(dropped)


def oracle_slice_without_format(theirs, fmt_indices):
    """Drop the oracle events belonging to messages the reference cannot yet reproduce.

    ★★★★★ WHY THIS EXISTS, AND WHY IT IS NOT MOVING THE GOALPOSTS. drawMessageBox runs
    stringPrintf(textPtr) BEFORE stringWordWrap (text.cpp:463) -- it expands AGI's %v / %m / %o /
    %s / %w / %g codes against LIVE VM STATE. The reference implements the wrap and not yet the
    substitution, so for a message containing a format code it is wrapping DIFFERENT TEXT than the
    oracle did, and comparing them measures the missing substitution, not the wrap.
    ★★★★ 11 of 596 messages carry a '%'. Excluding exactly those isolates the wrap and makes the
    claim precise: **this run gates stringWordWrap on 585 messages and gates nothing about
    stringPrintf.** The excluded count is printed so the scope is part of the result [L-85].
    ★★★ The slice is by MESSAGE, using the restore events as delimiters -- each message is the run
    of glyphs since the previous R, then its own R.
    """
    out, msg_i, pending = [], 0, []
    for e in theirs:
        pending.append(e)
        if e[0] == "R":
            if msg_i not in fmt_indices:
                out.extend(pending)
            pending = []
            msg_i += 1
    return out


def _unsafe_for_oracle(msg):
    """agi.cpp's sweep guard, byte for byte: a `%m` whose index does not begin 1..9.

    ★★★ The oracle's own guard at text.cpp:1272 is `numTexts > i` -- high end only -- so an index
    of 0 reads texts[-1]. `%m` with no digits gives strtoul 0, and so does an explicit `%m0`.
    """
    for k in range(len(msg) - 1):
        if msg[k:k + 1] == b"%" and msg[k + 1:k + 2] == b"m":
            nxt = msg[k + 2:k + 3]
            if not (b"1" <= nxt <= b"9"):
                return True
    return False


def reference_events(game_dir, fault_wrap=False, skip_format=False, fault_printf=False):
    """Run the reference over the same messages, in the same order, as agi.cpp's sweep."""
    # ★★★ Faults are set on the REFERENCE MODULE, not applied by this gate. A gate that could
    # manufacture its own failure would prove nothing when it failed [§2W].
    # ★★★★ The two faults reach DIFFERENT STAGES, which is the point of having both: --fault-wrap
    # diverges rectangle 0 (every message wraps), --fault-printf diverges rectangle 555 (only the
    # format-bearing ones), so each says which stage the gate is actually watching.
    textref.FAULT_WRAP = bool(fault_wrap)
    textref.FAULT_PRINTF = bool(fault_printf)

    game = resource.load_from_files(game_dir)

    # ★★★ logic 0's messages, which %g reads directly and %m reads via curLogicNr (see below).
    logic0_texts = []
    try:
        raw0 = game.load("LOGIC", 0)
        if raw0:
            logic0_texts = [m.decode("latin-1") for m in logic_mod.split(raw0, 0).messages]
    except Exception:                                  # noqa: BLE001
        pass

    # ★★★★ The sweep runs at INIT: no input parsed, no strings set, variables at their initial
    # values. So ego words and strings are empty and getVar returns 0 -- the PrintfState defaults.
    # Those are ASSUMPTIONS ABOUT THE SWEEP, not guarantees from the state diff (AC-5), and the
    # gate is what tests them.
    st = textref.PrintfState(logic0_texts=logic0_texts)
    r = textref.TextRenderer(printf_state=st)
    logics = 0
    msgs = 0
    skipped = 0
    fmt_indices = set()
    # ★★ agi.cpp's sweep walks dirLogic in index order and skips absent entries; this mirrors it.
    for nr in range(256):
        try:
            raw = game.load("LOGIC", nr)
        except Exception:                              # noqa: BLE001
            continue
        if not raw:
            continue
        lg = logic_mod.split(raw, nr)
        logics += 1
        # ★★★★★ %m READS LOGIC 0 IN THE SWEEP, AND THIS LINE CHANGED ONCE ALREADY. Its guard is
        # `if (logics[curLogicNr].numTexts > i)` (text.cpp:1272), and **the sweep never sets
        # curLogicNr, so curLogicNr is 0** -- %m reads logic 0's message table, exactly as %g does.
        #
        # ★★★★ P6.17/P6.18 measured EMPTY and were right at the time, for a reason that has since
        # been removed: the sweep called unloadResource on every logic INCLUDING logic 0, so
        # `logics[0].numTexts` was 0, the guard failed, and %m contributed nothing. Three candidates
        # were tried against the oracle's own rectangle for Kingquest1 message 555 (w=74, box width
        # 16): curLogicNr=0 gave 78, the swept logic gave 82, and EMPTY gave 74.
        #
        # ★★★★★ P6.18's crash fix HELD LOGIC 0 RESIDENT (agi.cpp -- %g88 was dereferencing it after
        # the free), and that silently moved %m from "appends nothing" to "substitutes". **The same
        # 596 Kingquest1 messages now emit 35,716 glyphs instead of 35,584 -- +132.** ★★★ A fix to
        # one substitution code moved a different one, which is §2H exactly: the first mechanism was
        # real and was not the whole mechanism. Had the reference not been changed with it, the gate
        # would have reported a wrapping divergence on 35 Kingquest1 messages and the cause would
        # have been three files away.
        #
        # ★★ Still a property of the SWEEP rather than of AGI: in real gameplay curLogicNr is the
        # RUNNING logic, not 0. A gate driven from gameplay needs it, and the 288-byte state diff
        # does not carry it (AC-5).
        r.printf_state.cur_logic_texts = logic0_texts
        for msg in lg.messages[:MSGS_PER_LOGIC]:
            if not msg:
                continue
            # ★★★★★ MIRRORS agi.cpp's SKIP, AND MIRRORING IS ALL IT DOES. The sweep refuses to draw
            # a message carrying a `%m` whose index does not begin 1..9, because stringPrintf reads
            # `texts[-1]` on it and the oracle segfaults -- SpaceQuest-2 message #355, which killed
            # the capture at 354 for two tasks. ★★★★ Without this line the reference draws 575 where
            # the oracle drew 574 and the gate reports a WRAPPING divergence at rectangle 354: a
            # real mismatch, pointing at the wrong subsystem entirely.
            # ★★★ IT IS DELIBERATELY THE NARROWEST FORM. A skip that dropped every %m-bearing
            # message would hide 1,044 of the corpus's 1,194 format-bearing messages and the gate
            # would still print PASS [§2W: an instrument that cannot be wrong does not measure].
            # ★★ One message in nine titles is skipped, and the gate prints the count.
            if _unsafe_for_oracle(msg):
                skipped += 1
                continue
            if b"%" in msg:
                fmt_indices.add(msgs)
                if skip_format:
                    msgs += 1
                    continue
            # ★★ messages are BYTES (volread/logic.py:52). latin-1 is the byte-preserving decode:
            # every byte maps to the code point of the same value, so ord(ch) in the reference's
            # checksum equals the byte the oracle hashed. A utf-8 decode would either raise or
            # silently combine bytes, and the checksum would then diverge for a reason that looks
            # exactly like a wrapping defect.
            r.draw_message_box(msg.decode("latin-1"))
            r.close_window()
            msgs += 1
    textref.FAULT_WRAP = False
    textref.FAULT_PRINTF = False
    return r.events, logics, msgs, fmt_indices, skipped


def classify_rect(a, b):
    """Which field moved, and therefore what kind of divergence this is."""
    _, ax, ay, aw, ah = a
    _, bx, by, bw, bh = b
    if (ay, ah) == (by, bh) and (aw != bw or ax != bx):
        return ("WRAPPING (box WIDTH differs: textSize_Width came out different)",
                f"ours w={aw} x={ax}  oracle w={bw} x={bx}")
    if ah != bh:
        return ("WRAPPING (box HEIGHT differs: a different number of LINES came out)",
                f"ours h={ah} y={ay}  oracle h={bh} y={by}")
    return ("GEOMETRY (position moved with size intact)", f"ours {a}  oracle {b}")


def compare(ours, theirs):
    our_r = [e for e in ours if e[0] == "R"]
    their_r = [e for e in theirs if e[0] == "R"]
    our_g = [e for e in ours if e[0] == "G"]
    their_g = [e for e in theirs if e[0] == "G"]

    res = {"our_rects": len(our_r), "their_rects": len(their_r),
           "our_glyphs": len(our_g), "their_glyphs": len(their_g),
           "rect_matched": 0, "rect_first_diff": None,
           "pos_first_diff": None, "sum_first_diff": None}

    for i, (a, b) in enumerate(zip(our_r, their_r)):
        if a != b:
            res["rect_first_diff"] = (i, a, b)
            break
        res["rect_matched"] = i + 1

    for i, (a, b) in enumerate(zip(our_g, their_g)):
        if a[1:5] != b[1:5] and res["pos_first_diff"] is None:
            res["pos_first_diff"] = (i, a[1:5], b[1:5])
        if a[5] != b[5] and res["sum_first_diff"] is None:
            res["sum_first_diff"] = (i, a[5], b[5])
        if res["pos_first_diff"] and res["sum_first_diff"]:
            break
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("oracle_log")
    ap.add_argument("--skip-format", action="store_true",
                    help="exclude messages carrying a %% code: gates the WRAP alone, "
                         "and gates nothing about stringPrintf")
    ap.add_argument("--fault-wrap", action="store_true",
                    help="P6.17 AC-5: change the wrap test from >= to >; EXPECTED to fail")
    ap.add_argument("--fault-printf", action="store_true",
                    help="P6.18 AC-4: drop %%v's leading-zero strip; EXPECTED to fail at the "
                         "first format-bearing message, with the wrap intact")
    a = ap.parse_args()

    theirs, dropped = read_oracle(a.oracle_log)
    ours, logics, msgs, fmt_indices, skipped = reference_events(
        a.game_dir, a.fault_wrap, a.skip_format, a.fault_printf)
    if a.skip_format:
        theirs = oracle_slice_without_format(theirs, fmt_indices)

    title = pathlib.Path(a.game_dir).name
    print(f"=== text gate: {title} ===")
    print(f"  sweep region : {len(theirs)} events kept, {dropped} dropped after the last restore")
    print(f"  reference    : {msgs} messages across {logics} logics"
          + (f"   ({skipped} skipped: the oracle reads texts[-1] on them)" if skipped else ""))
    if a.fault_wrap:
        print("  *** FAULT INJECTED (--fault-wrap): wrap test >= became > -- EXPECTED TO FAIL")
    if a.fault_printf:
        print("  *** FAULT INJECTED (--fault-printf): %v leading-zero strip dropped -- EXPECTED TO FAIL")

    c = compare(ours, theirs)
    print(f"  rectangles   : ours {c['our_rects']}   oracle {c['their_rects']}"
          f"   -- {c['rect_matched']} identical before any divergence")
    print(f"  glyphs       : ours {c['our_glyphs']}   oracle {c['their_glyphs']}")

    ok = True
    if c["rect_first_diff"] is not None or c["our_rects"] != c["their_rects"]:
        ok = False
        i, av, bv = c["rect_first_diff"]
        kind, detail = classify_rect(av, bv)
        print(f"  *** RECTANGLE {i} DIVERGES -- {kind}")
        print(f"      {detail}")
    else:
        print(f"  OK rectangles identical ({c['their_rects']})")

    if c["our_glyphs"] != c["their_glyphs"]:
        ok = False
        print(f"  *** GLYPH COUNT DIVERGES: {c['our_glyphs']} vs {c['their_glyphs']}"
              f"  (delta {c['our_glyphs'] - c['their_glyphs']})")
    elif c["pos_first_diff"] is not None:
        ok = False
        print(f"  *** GLYPH POSITION DIVERGES at draw {c['pos_first_diff'][0]}: "
              f"ours {c['pos_first_diff'][1]} vs oracle {c['pos_first_diff'][2]}")
    elif c["sum_first_diff"] is not None:
        ok = False
        n = c["sum_first_diff"][0]
        print(f"  *** CHECKSUM DIVERGES at draw {n}: "
              f"{c['sum_first_diff'][1]} vs {c['sum_first_diff'][2]}")
        print(f"      -> {n} draws matched in position, colour AND checksum before this point")
        # ★★★★★ THE CHECKSUM IS CUMULATIVE, SO --skip-format BREAKS ITS CHAIN AND THAT IS NOT A
        # DEFECT. patch 0010 hashes every character the ORACLE drew, including the messages this
        # mode excludes; from the first excluded message onward the two running values cannot
        # agree however correct the wrap is. **Verified, not assumed**: with --skip-format the
        # first divergence lands inside kept-message 555 and the first format-bearing message IS
        # 555. ★★★ So the number above is the checksum's verified PREFIX, and the divergence at
        # its end is this mode's own boundary rather than a finding.
        if a.skip_format:
            print("      NOTE: --skip-format breaks the cumulative checksum chain at the first "
                  "excluded message; the prefix above is what is actually verified")
    else:
        print(f"  OK glyphs identical in position, colour and checksum ({c['their_glyphs']})")

    print("TEXT GATE " + ("PASS" if ok else "*** FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
