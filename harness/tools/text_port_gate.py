"""harness/tools/text_port_gate.py -- emit the gate's cases, and diff the 6809 against the
reference. [T-P0-075 AC-3/AC-4]

★★★★★ THE PORT IS COMPARED TO THE PYTHON, AND THE PYTHON IS COMPARED TO THE ORACLE. The reference
leg is re-gated by harness/tools/text_run.sh on every run -- 4,594 rectangles and 293,648 glyphs
across nine titles -- so this leg cannot quietly rest on a stale reference. ★★★ Diffing the 6809
straight against the oracle would be the same comparison with a longer chain and one more thing to
get wrong; if this ever diverges, bisecting is one step [L-36].

★★★★ THE CASES ARE THE SWEEP'S, NOT A SELECTION. `--emit` walks agi.cpp's own rule -- every
loadable logic, its first eight non-empty texts, skipping the one message the pinned oracle cannot
survive -- which is byte for byte the list text_gate.py runs the reference over. **A gate whose
corpus is chosen for convenience is a claim about the convenience** [L-85].

★★★ §2P: the emitted case file carries game text, so it is written to build/ (gitignored) and
never committed, exactly as oracle_parser_cases.txt is. Everything this tool PRINTS is a count, a
position, a colour or a checksum.

usage:
  python harness/tools/text_port_gate.py --emit <game-dir> <cases-out> <table-out>
  python harness/tools/text_port_gate.py --check <game-dir> <results-in> [--fault-wrap]
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
sys.path.insert(0, os.path.dirname(__file__))
from volread import resource, logic as logic_mod                   # noqa: E402
from agivm import text as textref                                  # noqa: E402
from text_gate import _unsafe_for_oracle, MSGS_PER_LOGIC           # noqa: E402


def sweep_messages(game):
    """agi.cpp's sweep, and text_gate.py's reference walk, in one place."""
    for nr in range(256):
        try:
            raw = game.load("LOGIC", nr)
        except Exception:                                          # noqa: BLE001
            continue
        if not raw:
            continue
        lg = logic_mod.split(raw, nr)
        for msg in lg.messages[:MSGS_PER_LOGIC]:
            if not msg:
                continue
            if _unsafe_for_oracle(msg):
                continue
            yield nr, msg


def logic0_texts(game):
    try:
        raw0 = game.load("LOGIC", 0)
        if raw0:
            return logic_mod.split(raw0, 0).messages
    except Exception:                                              # noqa: BLE001
        pass
    return []


def do_emit(game_dir, cases_out, table_out):
    game = resource.load_from_files(game_dir)

    # ★★★ THE MESSAGE TABLE IS THE 6809's %g / %m SOURCE, and it is a pointer array into a text
    # block -- §2V's "a resource is in BANKED MEMORY, not a dict". The probe stages the block at a
    # known base and this writes the OFFSETS; the probe adds the base once.
    l0 = logic0_texts(game)
    blob = bytearray()
    offs = []
    for m in l0:
        if not m:
            offs.append(0xFFFF)          # ★ absent: the probe treats 0xFFFF as "no pointer"
            continue
        offs.append(len(blob))
        blob += m + b"\0"
    with open(table_out, "wb") as f:
        f.write(struct.pack(">H", len(offs)))
        for o in offs:
            f.write(struct.pack(">H", o))
        f.write(struct.pack(">H", len(blob)))
        f.write(bytes(blob))

    n = 0
    with open(cases_out, "wb") as f:
        for _nr, msg in sweep_messages(game):
            f.write(msg + b"\0")
            n += 1
    print("  emitted %d messages, logic0 table %d entries / %d text bytes"
          % (n, len(offs), len(blob)))
    return n


def reference_events(game_dir, fault_wrap=False, fault_printf=False):
    """The reference over the same list. Mirrors text_gate.py's own setup exactly."""
    textref.FAULT_WRAP = bool(fault_wrap)
    textref.FAULT_PRINTF = bool(fault_printf)
    game = resource.load_from_files(game_dir)
    l0 = [m.decode("latin-1") for m in logic0_texts(game)]
    st = textref.PrintfState(logic0_texts=l0, cur_logic_texts=l0)
    out = []
    for _nr, msg in sweep_messages(game):
        r = textref.TextRenderer(printf_state=st)
        r.checksum = reference_events.ck
        r.draw_message_box(msg.decode("latin-1"))
        m = r._msg
        glyphs = [e for e in r.events if e[0] == "G"]
        r.close_window()
        rect = r.events[-1]
        out.append({
            "boxw": m and 0 or 0,
            "rect": (rect[1], rect[2], rect[3], rect[4]),
            "glyphs": [(g[1], g[2], g[3], g[4], g[5]) for g in glyphs],
        })
        reference_events.ck = r.checksum
    textref.FAULT_WRAP = False
    textref.FAULT_PRINTF = False
    return out


reference_events.ck = 0


def read_results(path):
    """The probe's records. Glyphs precede their message header -- see text_probe.s."""
    data = open(path, "rb").read()
    msgs = []
    pend = []
    i = 0
    while i < len(data):
        t = data[i:i + 1]
        if t == b"G":
            row, col, fg, bg = data[i + 1], data[i + 2], data[i + 3], data[i + 4]
            ck = struct.unpack(">H", data[i + 5:i + 7])[0]
            pend.append((row, col, fg, bg, ck))
            i += 7
        elif t == b"M":
            boxw, boxh, srow, trow, tcol = data[i + 1:i + 6]
            bgx, bgy, bgw, bgh, ng = struct.unpack(">hhHHH", data[i + 6:i + 16])
            msgs.append({"rect": (bgx, bgy, bgw, bgh), "glyphs": pend[:ng],
                         "boxw": boxw, "boxh": boxh, "srow": srow,
                         "trow": trow, "tcol": tcol})
            pend = pend[ng:]
            i += 16
        else:
            raise SystemExit("★★★ bad record tag %r at offset %d" % (t, i))
    return msgs


def classify_rect(a, b):
    """★★★ L-103: the rectangle is DERIVED from the wrap, so it cannot name the stage that made
    it -- but WHICH FIELD moved narrows it. Same shape as text_gate.py's own classifier."""
    if a == b:
        return None
    if a[2] != b[2] and a[3] == b[3]:
        return "box WIDTH differs (textSize_Width)"
    if a[3] != b[3] and a[2] == b[2]:
        return "box HEIGHT differs (a different number of LINES)"
    if a[2] != b[2] and a[3] != b[3]:
        return "box WIDTH and HEIGHT both differ"
    return "POSITION differs (same size, different placement)"


def do_check(game_dir, results_in, fault_wrap, fault_printf):
    title = os.path.basename(os.path.normpath(game_dir))
    print("=== port gate: %s ===" % title)
    reference_events.ck = 0
    ours = read_results(results_in)
    theirs = reference_events(game_dir, fault_wrap, fault_printf)
    print("  messages     : 6809 %d   reference %d" % (len(ours), len(theirs)))
    og = sum(len(m["glyphs"]) for m in ours)
    tg = sum(len(m["glyphs"]) for m in theirs)
    print("  glyphs       : 6809 %d   reference %d" % (og, tg))

    ok = True
    n = min(len(ours), len(theirs))
    for i in range(n):
        why = classify_rect(ours[i]["rect"], theirs[i]["rect"])
        if why:
            print("  *** RECTANGLE %d DIVERGES -- %s" % (i, why))
            print("      6809 %s   reference %s" % (ours[i]["rect"], theirs[i]["rect"]))
            ok = False
            break
    if ok:
        print("  OK rectangles identical (%d)" % n)

    bad = 0
    for i in range(n):
        a, b = ours[i]["glyphs"], theirs[i]["glyphs"]
        if a != b:
            for j in range(min(len(a), len(b))):
                if a[j] != b[j]:
                    print("  *** GLYPH message %d index %d: 6809 %s   reference %s"
                          % (i, j, a[j], b[j]))
                    break
            else:
                print("  *** GLYPH COUNT message %d: 6809 %d   reference %d"
                      % (i, len(a), len(b)))
            bad += 1
            if bad >= 3:
                break
    if bad:
        ok = False
    elif ok:
        print("  OK glyphs identical in position, colour and checksum (%d)" % og)

    if len(ours) != len(theirs) or og != tg:
        ok = False
    print("PORT GATE %s" % ("PASS" if ok else "*** FAIL"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--emit", nargs=3, metavar=("GAMEDIR", "CASES", "TABLE"))
    ap.add_argument("--check", nargs=2, metavar=("GAMEDIR", "RESULTS"))
    ap.add_argument("--fault-wrap", action="store_true",
                    help="run the REFERENCE with its wrap fault, so a correct port must FAIL")
    ap.add_argument("--fault-printf", action="store_true",
                    help="run the REFERENCE with its printf fault, so a correct port must FAIL")
    a = ap.parse_args()
    if a.emit:
        do_emit(*a.emit)
        return 0
    if a.check:
        return do_check(a.check[0], a.check[1], a.fault_wrap, a.fault_printf)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
