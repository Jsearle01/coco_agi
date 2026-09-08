"""harness/tools/getstring_space.py -- AC-3: what get.string + an input line needs, and what is
left to put it in. [P6.20]

★★★★★ THE DISPATCH ASKS FOR THIS BEFORE THE CODE, AND THAT ORDER IS THE POINT. MAP_RESERVED is
3,328 B with 195 free after P6.19, M-48's 455 bytes are spent, and MAP_CODE has 5 -- so if the
answer is "it does not fit", the options are a map change or a design change and both are Jay's
(§8 trigger 1). Deciding that at the keyboard, by trimming something, is the failure this ordering
exists to prevent.

★★★★ EVERY DATA ROW IS MEASURED OR READ FROM THE PIN. Nothing here is a guess:
  - the string table's real size comes from harness/tools/string_census.py, which walks 889 logics
    at 100% coverage and finds the highest slot any title touches
  - _inputString[42] and TEXT_STRING_MAX_SIZE 40 are text.h at the pin
  - the occupancy figures are P6.19's measured artifact sizes

★★★ THE CODE ROWS ARE ESTIMATES AND ARE LABELLED AS SUCH, each anchored on a routine already
measured in src/engine/text.s rather than on a feeling. ★★ They are also, deliberately, not the
part that decides: **the DATA alone exceeds what is free**, so the verdict does not rest on them.

usage:  python harness/tools/getstring_space.py
"""
import sys

# ── the map, from src/engine/memmap.inc ──────────────────────────────────────────
MAP_RESERVED, MAP_RESERVED_END = 0x5300, 0x6000
MAP_RESERVED_MIN = 3072
PARSER = 954                    # memmap.inc: 870 code+state + two 42 B input buffers
TEXT_ENGINE = 1411              # P6.19, measured from build/text_probe.map
TEXT_PBUF = 768                 # src/engine/text.s TXT_PBUF_MAX

# ── free space elsewhere, computed from memmap.inc's own constants ───────────────
MAP_VM_OBJ, MAP_VM_OBJ_N, MAP_VM_OBJ_SZ = 0x0B20, 16, 42
MAP_DIRS = 0x1000

# ── the requirement ──────────────────────────────────────────────────────────────
SLOTS_MEASURED = 13             # string_census.py: highest slot touched is 12
SLOTS_ORACLE = 25               # agi.h MAX_STRINGS + 1
STRINGLEN = 40                  # agi.h MAX_STRINGLEN
INPUTSTRING = 42                # text.h _inputString[42]

EDIT_STATE = [
    ("_inputStringCursorPos", 1), ("_inputStringMaxLen", 1), ("_inputStringEntered", 1),
    ("_inputCursorChar", 1), ("_inputEditEnabled", 1), ("_inputStringRow", 1),
    ("_inputStringColumn", 1), ("saved charPos (push/pop)", 2), ("_promptRow", 1),
]

CODE = [
    ("get.string handler (operands, charPos push/set/pop, edit-state save/restore,"
     " lead-in via existing txt_printf/txt_wrap, stringSet, setString)", 130,
     "between txt_dec3 (46 B) and txt_blit (156 B); mostly sequencing"),
    ("stringKeyPress state machine (ctrl-c/x, backspace, enter, escape, printable"
     " with the 0x20..0x7f range test)", 150,
     "five branch groups; txt_dispch's whole dispatcher is 44 B for one"),
    ("displayCharacter's backspace arm + a one-cell clear", 90,
     "the cell clear is a reduced txt_blit, measured at 156 B"),
    ("key matrix -> ASCII for AD-134's scheme (table + scan + debounce)", 140,
     "~60 B of table + ~80 B of code"),
]


def main():
    free_reserved = (MAP_RESERVED_END - MAP_RESERVED) - PARSER - TEXT_ENGINE - TEXT_PBUF
    obj_end = MAP_VM_OBJ + MAP_VM_OBJ_N * MAP_VM_OBJ_SZ
    free_vmstate = MAP_DIRS - obj_end

    print("═══ what MAP_RESERVED has ═══")
    print("  region                    %5d B  ($%04X-$%04X, floor %d on the SIZE)"
          % (MAP_RESERVED_END - MAP_RESERVED, MAP_RESERVED, MAP_RESERVED_END, MAP_RESERVED_MIN))
    print("  parser                    %5d B" % PARSER)
    print("  text engine               %5d B   [P6.19, measured]" % TEXT_ENGINE)
    print("  text substitution buffer  %5d B" % TEXT_PBUF)
    print("  ------------------------------")
    print("  FREE                      %5d B   ★ and sound is unwritten" % free_reserved)
    print()
    print("═══ free elsewhere, from memmap.inc's own constants ═══")
    print("  MAP_VMSTATE tail          %5d B   ($%04X-$%04X, after 16 x %d B screen objects)"
          % (free_vmstate, obj_end, MAP_DIRS, MAP_VM_OBJ_SZ))
    print("  MAP_CODE spare            %5d B" % 5)
    print()

    print("═══ what get.string + an input line needs ═══")
    print("── DATA (measured or read at the pin) ──")
    tbl_m = SLOTS_MEASURED * STRINGLEN
    tbl_o = SLOTS_ORACLE * STRINGLEN
    print("  string table, %2d slots x %d   %5d B   [string_census.py, 889 logics, 100%% walked]"
          % (SLOTS_MEASURED, STRINGLEN, tbl_m))
    print("     (the oracle's own bound: %d x %d = %d B)" % (SLOTS_ORACLE, STRINGLEN, tbl_o))
    print("  _inputString[%d]             %5d B   [text.h at the pin]" % (INPUTSTRING, INPUTSTRING))
    est = sum(n for _, n in EDIT_STATE)
    print("  edit state, %d fields         %5d B   [enumerated below]" % (len(EDIT_STATE), est))
    data = tbl_m + INPUTSTRING + est
    print("  ------------------------------")
    print("  DATA SUBTOTAL             %5d B" % data)
    print()
    print("── CODE (ESTIMATED, each anchored on a measured routine) ──")
    code = 0
    for name, n, anchor in CODE:
        code += n
        print("  ~%4d B  %s" % (n, name.split("(")[0].strip()))
        print("           anchor: %s" % anchor)
    print("  ------------------------------")
    print("  CODE SUBTOTAL            ~%5d B   ★ ESTIMATE" % code)
    print()
    total = data + code
    print("  TOTAL                    ~%5d B  against %d free in MAP_RESERVED" %
          (total, free_reserved))
    print()

    print("═══ the verdict, and it does not rest on the estimate ═══")
    if data > free_reserved:
        print("  ★★★★★ THE DATA ALONE DOES NOT FIT: %d B of tables and buffers against %d free."
              % (data, free_reserved))
        print("        Even with ZERO bytes of code this is %.1fx over." % (data / free_reserved))
    print("  ★★★★ With the string table moved to the MAP_VMSTATE tail (%d B free, and the table"
          % free_vmstate)
    print("        is VM state rather than text-engine state), MAP_RESERVED would need")
    rest = INPUTSTRING + est + code
    print("        %d + %d + ~%d = ~%d B -- still %.1fx over %d."
          % (INPUTSTRING, est, code, rest, rest / free_reserved, free_reserved))
    print("  ★★★ So it does not fit under either placement. §8 trigger 1.")
    print()
    print("── edit state, enumerated ──")
    for n, b in EDIT_STATE:
        print("     %-28s %d B" % (n, b))
    return 0


if __name__ == "__main__":
    sys.exit(main())
