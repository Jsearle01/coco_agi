"""harness/tools/gs_gate.py -- emit get.string cases, and diff the 6809 against the reference.
[P6.23 AC-3]

★★★★★ THE CASES ARE DERIVED, NOT INVENTED, and that is what stops this being a gate about the
cases. Each is (a real lead-in message from the title, a row/column, a max length, a key list), and
the key lists are built from a fixed generator so the same title always produces the same cases --
reproducible, and covering the four branches stringKeyPress has:

    printable      the common path, and the one that fills the buffer
    backspace      which draws nothing at column 0 and a cell-clear otherwise
    over-length    max_len + 3 keys, so the strictly-greater test is exercised
    enter/escape   which end the loop with the buffer kept / cleared

★★★★ THE ORACLE LEG IS THE PYTHON, as it is for the text port gate, and the Python is gated against
ScummVM at 4,594 rectangles. **get.string itself is NOT oracle-gated** -- driving it there needs a
keystroke-fed sweep patch 0010 does not have -- so this compares 6809 against reference and says so
[P6.21 AC-7].

★★★ THE 'C' RECORDS ARE 6809-AGAINST-PYTHON ONLY. Backspace clears a cell through clearBlock,
which contains no drawCharacter, so patch 0010 is silent on it [P6.20 §5].

★★ §2P: cases carry game text into RAM; the emitted file lands in build/ (gitignored) and nothing
here prints a character.

usage:
  python harness/tools/gs_gate.py --emit  <game-dir> <cases-out> <table-out>
  python harness/tools/gs_gate.py --check <game-dir> <results-in> [--fault-maxlen]
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
sys.path.insert(0, os.path.dirname(__file__))
from volread import resource, logic as logic_mod                   # noqa: E402
from agivm import text as textref                                  # noqa: E402

GAMES = r"C:\Projects\agi-games\pc"
N_CASES = 48
ROWS = (22, 23, 24, 0, 5)
COLS = (0, 1, 5, 12)
MAXLENS = (6, 12, 20, 30, 40)

# ★★ A fixed, boring key alphabet: letters, digits, space and punctuation the parser will see.
ALPHA = [ord(c) for c in "abcdefghijklmnopqrstuvwxyz0123456789 .,'-"]


def keys_for(n, maxlen):
    """Deterministic per case index. Four shapes, chosen by n % 4."""
    shape = n % 4
    body = [ALPHA[(n * 7 + i * 13) % len(ALPHA)] for i in range(maxlen // 2 + 3)]
    if shape == 0:
        return body + [0x0D]                                    # type, enter
    if shape == 1:
        return body + [0x08, 0x08, 0x0D]                        # type, backspace twice, enter
    if shape == 2:
        # ★★★ OVER-LENGTH: max_len + 3 keys, so the `max_len > cursor_pos` test must discard the
        # tail SILENTLY. A `>=` there would let one extra character in, and nothing else in this
        # gate would notice.
        return [ALPHA[(n + i) % len(ALPHA)] for i in range(maxlen + 3)] + [0x0D]
    return body + [0x1B]                                        # type, escape


def logic0_texts(game):
    try:
        raw0 = game.load("LOGIC", 0)
        if raw0:
            return logic_mod.split(raw0, 0).messages
    except Exception:                                              # noqa: BLE001
        pass
    return []


def build_cases(game):
    l0 = logic0_texts(game)
    lead = [i for i, m in enumerate(l0) if m and len(m) < 120]
    out = []
    for n in range(N_CASES):
        # ★ every fourth case has NO lead-in, so the "textPtr is null" branch is covered
        li = -1 if (n % 4 == 3 or not lead) else lead[n % len(lead)]
        out.append({
            "lead": li,
            "row": ROWS[n % len(ROWS)],
            "col": COLS[n % len(COLS)],
            "maxlen": MAXLENS[n % len(MAXLENS)],
            "dest": n % 13,
            "cursor": 0 if (n % 3) else ord("_"),
            "keys": keys_for(n, MAXLENS[n % len(MAXLENS)]),
        })
    return out, l0


def do_emit(game_dir, cases_out, table_out):
    game = resource.load_from_files(game_dir)
    cases, l0 = build_cases(game)

    blob = bytearray()
    offs = []
    for m in l0:
        if not m:
            offs.append(0xFFFF)
            continue
        offs.append(len(blob))
        blob += m + b"\0"
    with open(table_out, "wb") as f:
        f.write(struct.pack(">H", len(offs)))
        for o in offs:
            f.write(struct.pack(">H", o))
        f.write(struct.pack(">H", len(blob)))
        f.write(bytes(blob))

    with open(cases_out, "wb") as f:
        for c in cases:
            lead_off = 0xFFFF if c["lead"] < 0 else offs[c["lead"]]
            f.write(struct.pack(">H", lead_off))
            f.write(bytes([c["row"], c["col"], c["maxlen"], c["dest"], c["cursor"],
                           len(c["keys"])]))
            f.write(bytes(c["keys"]))
    print("  emitted %d cases, logic0 %d entries / %d text bytes"
          % (len(cases), len(offs), len(blob)))


def reference(game_dir, fault_maxlen=False):
    game = resource.load_from_files(game_dir)
    cases, l0raw = build_cases(game)
    l0 = [m.decode("latin-1") for m in l0raw]
    st_printf = textref.PrintfState(logic0_texts=l0, cur_logic_texts=l0)
    r = textref.TextRenderer(printf_state=st_printf)
    r.checksum = 0
    strings = [""] * 13
    out = []
    for c in cases:
        ist = textref.InputState(cursor_char=c["cursor"])
        base = len(r.events)
        lead = l0[c["lead"]] if c["lead"] >= 0 else None
        ml = c["maxlen"] + 1 if fault_maxlen else c["maxlen"]
        textref.get_string(r, ist, strings, c["dest"], lead,
                           c["row"], c["col"], ml, c["keys"])
        out.append({"events": r.events[base:], "curpos": ist.cursor_pos,
                    "entered": 1 if ist.entered else 0})
    return out


def read_results(path):
    data = open(path, "rb").read()
    cases, pend = [], []
    i = 0
    while i < len(data):
        t = data[i:i + 1]
        if t == b"G":
            pend.append(("G", data[i + 1], data[i + 2], data[i + 3], data[i + 4],
                         struct.unpack(">H", data[i + 5:i + 7])[0]))
            i += 7
        elif t == b"C":
            pend.append(("C", data[i + 1], data[i + 2], data[i + 3]))
            i += 4
        elif t == b"E":
            curpos, entered = data[i + 1], data[i + 2]
            n = struct.unpack(">H", data[i + 3:i + 5])[0]
            cases.append({"events": pend[:n], "curpos": curpos, "entered": entered})
            pend = pend[n:]
            i += 5
        else:
            raise SystemExit("★★★ bad record tag %r at %d" % (t, i))
    return cases


def do_check(game_dir, results_in, fault_maxlen):
    title = os.path.basename(os.path.normpath(game_dir))
    print("=== get.string gate: %s ===" % title)
    ours = read_results(results_in)
    theirs = reference(game_dir, fault_maxlen)
    print("  cases  : 6809 %d   reference %d" % (len(ours), len(theirs)))
    og = sum(len(c["events"]) for c in ours)
    tg = sum(len(c["events"]) for c in theirs)
    print("  events : 6809 %d   reference %d" % (og, tg))

    ok = len(ours) == len(theirs)
    bad = 0
    for i in range(min(len(ours), len(theirs))):
        a, b = ours[i], theirs[i]
        if a["curpos"] != b["curpos"] or a["entered"] != b["entered"]:
            print("  *** CASE %d STATE: 6809 curpos=%d entered=%d   reference curpos=%d entered=%d"
                  % (i, a["curpos"], a["entered"], b["curpos"], b["entered"]))
            bad += 1
        elif a["events"] != b["events"]:
            for j in range(min(len(a["events"]), len(b["events"]))):
                if a["events"][j] != b["events"][j]:
                    print("  *** CASE %d EVENT %d: 6809 %s   reference %s"
                          % (i, j, a["events"][j], b["events"][j]))
                    break
            else:
                print("  *** CASE %d EVENT COUNT: 6809 %d   reference %d"
                      % (i, len(a["events"]), len(b["events"])))
            bad += 1
        if bad >= 3:
            break
    if bad:
        ok = False
    elif ok and og == tg:
        print("  OK %d cases identical: %d events, cursor positions and entered flags"
              % (len(ours), og))
    if og != tg:
        ok = False
    print("GET.STRING GATE %s" % ("PASS" if ok else "*** FAIL"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--emit", nargs=3, metavar=("GAMEDIR", "CASES", "TABLE"))
    ap.add_argument("--check", nargs=2, metavar=("GAMEDIR", "RESULTS"))
    ap.add_argument("--fault-maxlen", action="store_true",
                    help="give the REFERENCE one extra byte of buffer, so a correct port FAILS "
                         "-- the strictly-greater test in stringKeyPress")
    a = ap.parse_args()
    if a.emit:
        do_emit(*a.emit)
        return 0
    if a.check:
        return do_check(a.check[0], a.check[1], a.fault_maxlen)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
