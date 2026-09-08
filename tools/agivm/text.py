"""text.py -- the TEXT reference: word wrap, message-box geometry, glyph emission.

Transcribed from the pinned oracle, ScummVM 9d9b9e93 (v2.9.1), engines/agi:
    text.cpp:1095-1201  TextMgr::stringWordWrap
    text.cpp:445-519    TextMgr::drawMessageBox
    text.cpp:307-342    TextMgr::displayCharacter
    text.cpp:549-564    TextMgr::closeWindow
    text.cpp:162-210    TextMgr::charAttrib_Set   (EGA branch)
    text.h:63-74        the constants

★★★★★ READ FROM THE ORACLE, NOT THE SPECS [L-25]. The AGI Specifications describe message display
but are not authoritative for wrapping, and this function has three edge cases the engine names by
game in its own comments (King's Quest 1's intro, whose scrolling text is padded with spaces so old
lines are erased; the Apple IIgs restart UI, which uses spaces to make the window larger; Gold Rush
room 60's "  Lake Michigan!" at max length 9, which must split into "  Lake" / "Michigan!").
**Those three exist because the obvious implementation gets them wrong**, and none of them is in
the Specs.

═══════════════════════════════════════════════════════════════════════════════════════════════
★★★★★ §2V — WHAT EACH STRUCTURE BECOMES ON THE 6809, NAMED AT THE DECISION

| here (Python)                  | on the 6809                          | cost                        |
|--------------------------------|--------------------------------------|-----------------------------|
| `text` as a `str`              | ★★★★ a POINTER into the LOGIC        | zero -- the message is      |
|                                | resource's message table, in the     | already resident in the     |
|                                | arena. Not copied.                   | arena window [res_core]     |
| `out` accumulating a wrapped   | ★★★★★ a FIXED 2,000-BYTE BUFFER.     | 2,000 B of MAP_RESERVED,    |
| `str`                          | The oracle's own is `static char     | and it is the single        |
|                                | resultWrappedBuffer[2000]` -- the    | largest allocation the      |
|                                | port inherits the same bound, not a  | text engine needs           |
|                                | growing list [§2V.2 unbounded        |                             |
|                                | containers: state the maximum]       |                             |
| `box_width` / `box_height`     | two bytes                            | 2 B                         |
| the `(row, col, fg, bg)` tuple | ★★★ NOT a tuple -- four bytes of     | 4 B, in the direct page if  |
| emitted per glyph              | zero-page state mutated in place.    | it can be had. NO per-glyph |
|                                | The emission IS the draw call.       | allocation exists.          |
| `events` list                  | ★★★★★ DOES NOT EXIST ON THE TARGET.  | zero on the target; this is |
|                                | It is the gate's artifact, not the   | reference-only scaffolding  |
|                                | renderer's. The 6809 draws straight  | and is marked as such       |
|                                | into the display buffer.             | so the port does not copy it|
| `checksum`                     | ★★★★ likewise gate-only. The port    | zero                        |
|                                | has no reason to compute it.         |                             |
| ── `stringPrintf`, added P6.18 ─────────────────────────────────────────────────────────────|
| `out` accumulating the         | ★★★★★ A SECOND FIXED 2,000-BYTE      | 2,000 B more of             |
| substituted `str`              | BUFFER, DISTINCT FROM THE WRAP'S.    | MAP_RESERVED -- 4,000 B for |
|                                | The oracle has both:                 | the text engine's two       |
|                                | `resultPrintfBuffer[2000]` at        | stages, and they cannot     |
|                                | text.cpp:1218 and                    | share one buffer because    |
|                                | `resultWrappedBuffer[2000]` at 1096, | the wrap READS the printf   |
|                                | and the wrap READS the printf's      | output while WRITING its    |
|                                | output (text.cpp:463 then 468)       | own [text.cpp:463,468]      |
| `string_printf` RECURSING for  | ★★★★★ THE HAZARD ROW. The oracle     | ★★★ a per-call accumulator  |
| `%s` and `%m`                  | recurses into THE SAME static        | the 6809 does not get for   |
|                                | buffer and gets away with it ONLY    | free. Either a second       |
|                                | because it accumulates into a        | staging buffer, or an       |
|                                | SEPARATE `Common::String` and copies | append-in-place rewrite     |
|                                | to the static last [1288, 1294].     | that never returns a        |
|                                | ★★★★ A 6809 port that recurses       | pointer to shared storage.  |
|                                | straight into one shared output      | ★★ Depth is 1 in the        |
|                                | buffer CLOBBERS THE CALLER.          | sweep and unbounded in      |
|                                |                                      | principle -- state a cap.   |
| `z`, the `"%015i"` scratch     | ★★ 16 bytes, and the 6809 has no     | 16 B + a byte-to-decimal    |
|                                | `sprintf`: a divide-by-10 loop       | routine (~40 B of code)     |
|                                | emitting 15 digits into a fixed      |                             |
|                                | buffer, then an index into it.       |                             |
| `PrintfState`'s six callbacks  | ★★★ NOT closures -- five are direct  | zero; they are already      |
|                                | reads of resident state (vars, the   | where the port needs them   |
|                                | OBJECT file, logic 0's message       |                             |
|                                | table, the parsed-word slots, the    |                             |
|                                | string table) and the sixth is       |                             |
|                                | `curLogicNr`, one byte.              |                             |

★★★★ THE ROW THAT WILL PROBABLY BE WRONG, said in advance because parser.py's §3.E predicted four
forms and the fourth was incomplete: **"the message is not copied" is the claim most likely to
conceal a copy.** `stringWordWrap` reads the message and writes a DIFFERENT buffer, so the source
is not copied -- but if the 6809's arena window is remapped between reading a message and drawing
it, the message would have to be staged somewhere first, and that staging is a copy this table does
not have a row for. **It is unknown until the port measures it** [the §3.E precedent: three held,
the fourth was the one asserted without measurement].
═══════════════════════════════════════════════════════════════════════════════════════════════
"""

# ── text.h:63-74 ───────────────────────────────────────────────────────────────────────────
FONT_VISUAL_WIDTH = 4
FONT_VISUAL_HEIGHT = 8
FONT_ROW_CHARACTERS = 25
FONT_COLUMN_CHARACTERS = 40
HEIGHT_MAX = 20

WRAP_BUFFER_MAX = 2000          # ★ text.cpp:1096 -- static char resultWrappedBuffer[2000]

# ★★★★★ AC-5's FAULT, and it lives HERE rather than in the gate because the gate must not be able
# to fake a failure. Setting it changes the wrap test from `>=` to `>` -- the single most plausible
# transcription slip in stringWordWrap, and the one the oracle's own source guards against by
# writing `>=`. ★★★★ A word that exactly fills the remaining width then fails to wrap, so
# characters land in different places while the box geometry mostly survives: **the checksum moves
# and the rectangles do not**, which is exactly the failure shape the gate separates. A fault that
# broke the geometry would prove nothing about wrapping, and wrapping is the path that had no gate.
FAULT_WRAP = False


def string_word_wrap(text, max_width):
    """text.cpp:1095-1201, statement for statement.

    Returns (wrapped_text, box_width, box_height).

    ★★★★ THE FOUR THINGS THAT ARE EASY TO GET WRONG, all load-bearing:
      1. `word_len` INCLUDES a leading space. `word_start` points at the space and `cur_read` has
         already moved past both space and word, so the span carries it. That is what makes Gold
         Rush's "  Lake" keep one of its two spaces.
      2. The wrap test is `word_len >= line_width_left`, NOT `>`. A word that exactly fills the
         remaining width still wraps.
      3. The leading space is dropped ONLY on the wrapping branch -- mid-line it is kept and
         counted, which is how KQ1's space-padded intro lines keep their width.
      4. `box_height >= HEIGHT_MAX` breaks out of the LOOP, so text past 20 lines is discarded
         rather than clipped at draw time.
    """
    out = []
    box_width = 0
    box_height = 0
    line_width = 0
    line_width_left = max_width

    word_start = 0
    cur_read = 0
    n = len(text)

    while cur_read < n and text[cur_read] != "\0":
        # If first character is a space, skip it, so that we process at least this space
        if text[cur_read] == " ":
            cur_read += 1

        while cur_read < n and text[cur_read] not in (" ", "\n"):
            cur_read += 1

        word_end_char = text[cur_read] if cur_read < n else "\0"
        word_len = cur_read - word_start

        wraps = (word_len > line_width_left) if FAULT_WRAP else (word_len >= line_width_left)
        if wraps:
            # ★ 3: the leading space is dropped only here
            if word_len and text[word_start] == " ":
                word_start += 1
                word_len -= 1

            if word_len > max_width:
                # Word way too long, split it in half
                cur_read = cur_read - (word_len - max_width)
                word_len = max_width

            out.append("\n")
            if line_width > box_width:
                box_width = line_width
            box_height += 1
            line_width = 0
            line_width_left = max_width

            if box_height >= HEIGHT_MAX:
                break

        out.append(text[word_start:word_start + word_len])
        line_width += word_len
        line_width_left -= word_len

        if word_end_char == "\n":
            cur_read += 1
            out.append("\n")
            if line_width > box_width:
                box_width = line_width
            box_height += 1
            line_width = 0
            line_width_left = max_width
            if box_height >= HEIGHT_MAX:
                break

        word_start = cur_read

    # ★★ THE TAIL IS GUARDED BY cur_read, NOT BY line_width. An all-empty message leaves
    # cur_read at 0 and produces a box of height 0 -- which is a real case the sweep hits.
    if cur_read > 0:
        if line_width > box_width:
            box_width = line_width
        box_height += 1

    return "".join(out), box_width, box_height


PRINTF_BUFFER_MAX = 2000        # ★ text.cpp:1218 -- static char resultPrintfBuffer[2000]


class PrintfState:
    """The game state stringPrintf substitutes FROM.

    ★★★★★ AC-5: THIS IS THE ANSWER, AND IT IS NOT ALL COVERED BY THE STATE DIFF. The nine-title
    diff is 288 bytes -- 32 packed flag bytes then 256 variables [vm_diff.py:4] -- and
    stringPrintf reads FOUR things beyond that:

        %v  getVar(i)                      -> variables      ★ COVERED by the diff
        %0  objectName(i)                  -> the OBJECT file  ✗ NOT covered
        %g  logics[0].texts[i]             -> logic 0's messages (static game data)
        %w  getEgoWord(i)                  -> the last PARSED INPUT words   ✗ NOT covered
        %s  getString(i)                   -> VM strings      ✗ NOT covered
        %m  logics[curLogicNr].texts[i]    -> and curLogicNr  ✗ NOT covered

    ★★★★ SO A GREEN NINE-TITLE DIFF DOES NOT GUARANTEE THE SUBSTITUTION'S INPUTS. Three of the six
    codes read state the diff never compares, and a fourth depends on curLogicNr, which the diff
    also does not carry. **For the oracle's SWEEP this happens not to bite** -- it runs at init,
    before any input is parsed, so ego words and strings are empty and the variables are at their
    initial values -- but that is a property of the sweep, not a guarantee from the gate.
    ★★★ Stated as a limit rather than worked around: a text gate driven from real gameplay would
    need those four covered, and the diff would have to widen to do it.

    ★★★★★ AC-7 MEASURED THIS AND HALF OF IT WAS WRONG. The sentence here used to say `objectName`
    and `getString` "are unused ... and will be exercised the first time a title uses them -- which
    AC-7's wider corpus is what would find." **The corpus found one of the two.**
    `harness/tools/text_census.py` over all nine v2 gate titles, 14,944 messages:

        %v 436   %0 0   %g 4   %w 121   %s 189   %m 1,044        (1,194 format-bearing messages)

    ★★★★ **`%s` IS USED, by six of the nine titles** -- PoliceQuest1 94, SpaceQuest-1 40,
    SpaceQuest-2 32, larry1 16, MixedUpMotherGoose 6, Kingquest2 1 -- and `%s` is the RECURSING
    code, so the hazard row in the §2V table above is on a live path rather than a hypothetical one.
    ★★★ It still models as empty and still agrees with the oracle, because the sweep runs at init
    and the oracle's string table is empty there too: **both sides read the same empty state, which
    is agreement about the harness and not evidence about substitution.** That is a limit on what
    596-times-nine has tested, and it is the limit AC-9's `get.string` work has to lift.

    ★★ **`%0` is used by NO staged title** -- zero occurrences in 14,944 messages -- so the object
    path is untested and the corpus cannot contradict the empty model. ★ Kingquest1's own 44
    format-bearing messages are %v x28, %m x35, %w x13, which is why one title could not have found
    either of these.

    ★ Also measured, and it retires divergence C below as a live concern: **no message in any of the
    nine ends in a backslash** (65 contain one, 63 of them PoliceQuest1's).
    """

    def __init__(self, get_var=None, object_name=None, logic0_texts=None,
                 ego_word=None, get_string=None, cur_logic_nr=0, cur_logic_texts=None):
        # ★ Defaults are the SWEEP's state: fresh init, nothing parsed, no strings set.
        self.get_var = get_var or (lambda i: 0)
        self.object_name = object_name or (lambda i: "")
        self.logic0_texts = logic0_texts or []
        self.ego_word = ego_word or (lambda i: "")
        self.get_string = get_string or (lambda i: "")
        self.cur_logic_nr = cur_logic_nr
        self.cur_logic_texts = cur_logic_texts or []


# ★★★★★ AC-4's FAULT. It lives in the reference, not the gate, so the gate cannot manufacture its
# own failure [§2W]. It drops the leading-zero strip from %v, which is the single most plausible
# slip in this function: getVar returns a byte, "%015i" pads it to fifteen digits, and forgetting
# to strip turns "3" into "000000000000003". ★★★★ It moves the CHECKSUM and the WRAP (a 15-digit
# number wraps differently), leaving everything the wrap does correct -- so it exercises the
# substitution stage specifically, which is what AC-4 asks for and what the wrap fault could not
# reach.
FAULT_PRINTF = False


def string_printf(text, st):
    """text.cpp:1217-1296, statement for statement.

    ★★★★ THE FIVE THINGS THAT ARE EASY TO GET WRONG:
      1. **The object code is '0', not 'o'** (text.cpp:1254). Reading the Specs would give %o.
      2. `%v` formats through "%015i" and then strips leading zeros with `i < 14`, so an all-zero
         value keeps ONE digit rather than vanishing -- the engine's comment says "don't remove
         the 3rd zero if 000".
      3. `%v<n>|<w>` sets a field WIDTH: i = 15 - w, taking the last w digits.
      4. `%s` and `%m` RECURSE through stringPrintf, so a substituted string is substituted again.
         ★★ `%s` does NOT subtract 1 from its index; `%0`, `%g`, `%w` and `%m` all do.
      5. `\\` escapes the next character and falls through to the literal branch.

    ★★★★★ THREE PLACES THIS REFERENCE IS DELIBERATELY NOT THE ORACLE, recorded rather than quietly
    "fixed" [§2.1: say which you are reproducing; §8: a divergence is stated, not assumed benign].
    **All three are out-of-range paths that the oracle does not guard and this does.** None is
    reachable from well-formed game data, and none is exercised by the 596-message sweep -- so they
    are stated as limits on what the gate has tested, not as claims about which behaviour is right:

      A. **`%g` is unchecked in the oracle** [text.cpp:1260]: `logics[0].texts[i]` with no bound
         test at all. A `%g` past logic 0's message count reads out of bounds there and emits
         nothing here.
      B. **`%m`'s guard is one-sided** [text.cpp:1272]: `numTexts > i` catches the high end and not
         `i == -1`, which `%m0` produces. This checks `0 <= idx`.
      C. ★★★ **A TRAILING `\\` WALKS PAST THE TERMINATOR in the oracle** [text.cpp:1283-1288]: the
         escape branch increments, then FALLS THROUGH to `resultString += *originalText++`, which
         appends the NUL and leaves the pointer one byte beyond it -- so the `while (*originalText)`
         at 1224 resumes on whatever follows the message. This stops at the end of the string.

    ★★★★ WHY THIS MATTERS TO THE PORT AND NOT ONLY TO THE REFERENCE: C is the one to carry forward.
    On the 6809 the messages are contiguous in the LOGIC resource's text table, so "reads past the
    terminator" means "reads the NEXT MESSAGE", and the naive port reproduces the oracle's walk
    exactly and for free. **If a title ever ends a message with a backslash, matching the oracle
    here requires deliberately NOT bounds-checking** -- which is a decision, and it belongs on the
    §2V table above rather than in whatever the port happens to do.
    """
    out = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "%":
            i += 1
            if i >= n:
                break
            code = text[i]
            i += 1
            digits = ""
            while i < n and text[i].isdigit():
                digits += text[i]
                i += 1
            num = int(digits) if digits else 0

            if code == "v":
                z = "%015i" % st.get_var(num)
                width = 99
                if i < n and text[i] == "|":
                    i += 1
                    wd = ""
                    while i < n and text[i].isdigit():
                        wd += text[i]
                        i += 1
                    width = int(wd) if wd else 0
                if width == 99:
                    if FAULT_PRINTF:
                        k = 0                     # ★ AC-4's fault: no leading-zero strip
                    else:
                        k = 0
                        while k < 14 and z[k] == "0":
                            k += 1
                else:
                    k = 15 - width
                out.append(z[k:])
            elif code == "0":
                out.append(st.object_name(num - 1))
            elif code == "g":
                idx = num - 1
                if 0 <= idx < len(st.logic0_texts):
                    out.append(st.logic0_texts[idx])
            elif code == "w":
                out.append(st.ego_word(num - 1))
            elif code == "s":
                out.append(string_printf(st.get_string(num), st))
            elif code == "m":
                idx = num - 1
                if 0 <= idx < len(st.cur_logic_texts):
                    out.append(string_printf(st.cur_logic_texts[idx], st))
            # ★ default: the code is consumed and nothing is emitted
            while i < n and text[i].isdigit():
                i += 1
        elif ch == "\\":
            i += 1
            if i < n:
                out.append(text[i])
                i += 1
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def char_attrib_ega(foreground, background):
    """text.cpp:198-206, the EGA branch of charAttrib_Set.

    ★★ Returns the COMBINED pair, which is what drawCharacter receives and what the oracle log
    records -- not the requested pair. drawMessageBox asks for (0, 15) and every glyph in a box is
    therefore drawn (15, 8); background 8 is the engine's invert flag, not a colour.
    """
    if background:
        return 15, 8
    return foreground, 0


class TextRenderer:
    """The message-box half of TextMgr, emitting the same decisions patch 0010 logs.

    ★★★ It models POSITIONS, not pixels. The oracle's log is a call log for the reason patch 0001
    gives about the display path, so a pixel buffer here would be modelling something the gate
    cannot see and the port would inherit the wrong emphasis [§2O.1].
    """

    def __init__(self, window_row_min=2, printf_state=None):
        # ★ _window_Row_Min is `gameRow` (text.cpp:93). For a normal v2 game with the status line
        # at row 0 the message box sits two rows down, which the capture confirms: the first
        # message's startingRow is 8 and its first glyph is logged at row 10.
        self.window_row_min = window_row_min
        self.printf_state = printf_state or PrintfState()
        self.events = []            # ★★ gate-only; see the §2V table
        self.checksum = 0
        self._msg = None
        # ★★★ ONE CURSOR, shared by the message path and the echo path, because the engine has
        # exactly one (_textPos) and displayCharacter moves it for both. The first draft kept the
        # cursor as locals inside _display_text, which works while messages are the only writer
        # and breaks the moment get.string echoes a keystroke between two of them.
        self.crow = 0
        self.ccol = 0
        self.reset_col = 0
        self.fg = 0
        self.bg = 0

    # ── the checksum patch 0010 keeps, so neither side needs the characters (§2P) ──────────
    def _hash(self, ch):
        self.checksum = (self.checksum * 31 + ord(ch)) & 0xFFFFFFFF
        return self.checksum & 0xFFFF

    def draw_message_box(self, text, wanted_width=0, wanted_row=-1, wanted_column=-1):
        """text.cpp:445-519."""
        max_width = wanted_width
        if wanted_width == 0:
            max_width = 30                       # text.cpp:457-458

        # ★★★★★ THE SUBSTITUTION RUNS FIRST -- text.cpp:463, and missing it is what made 11 of
        # Kingquest1's 596 messages diverge from index 555 [P6.17]. The wrap sees stringPrintf's
        # OUTPUT, never the raw message, so every downstream number -- box width, rectangle,
        # checksum -- is computed from the substituted string.
        text = string_printf(text, self.printf_state)

        wrapped, calc_w, calc_h = string_word_wrap(text, max_width)
        text_w, text_h = calc_w, calc_h

        if wanted_row == -1:
            starting_row = ((HEIGHT_MAX - text_h - 1) // 2) + 1
        else:
            starting_row = wanted_row
        text_row = starting_row + self.window_row_min

        if wanted_column == -1:
            text_col = (FONT_COLUMN_CHARACTERS - text_w) // 2
        else:
            text_col = wanted_column

        # ★ The rectangle, text.cpp:500-503. Verified by hand against the capture's first
        # restore (R 19 59 118 50) before this file was written.
        self._msg = {
            "bg_w": text_w * FONT_VISUAL_WIDTH + 10,
            "bg_h": text_h * FONT_VISUAL_HEIGHT + 10,
            "bg_x": text_col * FONT_VISUAL_WIDTH - 5,
            "bg_y": starting_row * FONT_VISUAL_HEIGHT - 5,
        }

        fg, bg = char_attrib_ega(0, 15)          # drawMessageBox's charAttrib_Set(0, 15)
        self._display_text(wrapped, text_row, text_col, fg, bg)

    def _display_text(self, text, row, column, fg, bg):
        """text.cpp:295-342 -- displayText's loop, over the shared cursor."""
        self.crow, self.ccol, self.reset_col = row, column, column
        self.fg, self.bg = fg, bg
        for ch in text:
            self.display_character(ch)

    # ══════════════════════════════════════════════════════════════════════════════════════
    # ★★★★ display_character <- text.cpp:307. THREE ARMS, AND ONLY ONE OF THEM DRAWS.
    # _display_text above handles CR/LF inline because a wrapped message never contains a
    # backspace; the ECHO does, so get.string needs the real thing.
    # ★★★★★ THE BACKSPACE ARM EMITS A 'C' EVENT AND patch 0010 DOES NOT LOG IT. text.cpp:320
    # calls `clearBlock(...)`, a graphics call with no drawCharacter in it, so the oracle's log is
    # SILENT on backspace [P6.20 §5]. The event is emitted here anyway -- the port must be
    # comparable against something -- and the gate filters it out with the reason named, rather
    # than the reference quietly not modelling it.
    def display_character(self, ch):
        code = ord(ch) if isinstance(ch, str) else ch
        if code == 0x08:
            # text.cpp:313-322 -- move back a cell, clear it, and DO NOT redraw anything
            if self.ccol:
                self.ccol -= 1
            elif self.crow > 21:
                self.ccol = FONT_COLUMN_CHARACTERS - 1
                self.crow -= 1
            self.events.append(("C", self.crow, self.ccol, self.bg))
            return
        if code in (0x0D, 0x0A):
            if self.crow < (FONT_ROW_CHARACTERS - 1):
                self.crow += 1
            self.ccol = self.reset_col
            return
        self.events.append(("G", self.crow, self.ccol, self.fg, self.bg,
                            self._hash(chr(code))))
        self.ccol += 1
        if self.ccol > (FONT_COLUMN_CHARACTERS - 1):
            self.display_character(chr(0x0D))       # ★ the engine recurses; so does this

    def close_window(self):
        """text.cpp:549-564.

        ★★★★ The y is CLAMPED to >= 0 before render_Block, and the log records the clamped value.
        A reference using backgroundPos_y raw diverges on exactly the case the engine comments on:
        print.at with y=0 puts the border over the menu bar and the background y goes negative
        (bugs #13820, #15241, MixedUpMotherGoose's nursery rhymes).
        """
        if self._msg is None:
            return
        m = self._msg
        self.events.append(("R", m["bg_x"], max(0, m["bg_y"]), m["bg_w"], m["bg_h"]))
        self._msg = None


TEXT_STRING_MAX_SIZE = 40       # text.h at the pin
MAX_STRINGS = 24                # agi.h -- slots 0..24; the port carries 13, measured
INPUT_STRING_MAX = 42           # text.h _inputString[42]

AGI_KEY_BACKSPACE = 0x08
AGI_KEY_ENTER = 0x0D
AGI_KEY_ESCAPE = 0x1B


class InputState:
    """TextMgr's input-edit state, the ten bytes MAP_INPUTSTATE holds on the target.

    ★★★ `cursor_char` is the one that changes the event stream most and is easiest to overlook:
    when it is non-zero, EVERY inputEditOn emits a backspace and EVERY inputEditOff re-emits the
    cursor glyph, so a single keystroke produces three events rather than one. Sierra's own default
    is 0 for get.string and non-zero for the command-line prompt [inputSetCursorChar callers].
    """

    def __init__(self, cursor_char=0):
        self.input_string = ""
        self.cursor_pos = 0
        self.max_len = 0
        self.entered = False
        self.cursor_char = cursor_char
        self.edit_enabled = False


def _edit_on(r, st):
    """text.cpp:670."""
    if not st.edit_enabled:
        st.edit_enabled = True
        if st.cursor_char:
            r.display_character(chr(AGI_KEY_BACKSPACE))


def _edit_off(r, st):
    """text.cpp:679."""
    if st.edit_enabled:
        st.edit_enabled = False
        if st.cursor_char:
            r.display_character(chr(st.cursor_char))


def string_key_press(r, st, key):
    """text.cpp:987-1085. Returns False when the edit loop should end.

    ★★★★ THE FOUR THINGS THAT ARE EASY TO GET WRONG:
      1. **inputEditOn brackets the WHOLE function and inputEditOff closes it**, so with a cursor
         character every branch -- including the ones that emit nothing of their own -- produces a
         backspace/cursor pair around it.
      2. Backspace decrements FIRST and only then draws (text.cpp:1003-1006), so a backspace at
         column 0 of an empty string draws nothing at all.
      3. The printable test is `_inputStringMaxLen > _inputStringCursorPos` -- strictly greater --
         so the buffer fills to max_len and the max_len-th keystroke is DISCARDED SILENTLY.
      4. The acceptable range is 0x20..0x7f for the default language, NOT 0x20..0xff.
    """
    _edit_on(r, st)
    cont = True
    if key in (0x03, 0x18):                      # ctrl-c / ctrl-x: clear the line
        while st.cursor_pos:
            st.cursor_pos -= 1
            st.input_string = st.input_string[:st.cursor_pos]
            r.display_character(chr(AGI_KEY_BACKSPACE))
    elif key == AGI_KEY_BACKSPACE:
        if st.cursor_pos:
            st.cursor_pos -= 1
            st.input_string = st.input_string[:st.cursor_pos]
            r.display_character(chr(AGI_KEY_BACKSPACE))
    elif key == AGI_KEY_ENTER:
        st.entered = True
        cont = False
    elif key == AGI_KEY_ESCAPE:
        st.input_string = ""
        st.cursor_pos = 0
        st.entered = False
        cont = False
    else:
        if st.max_len > st.cursor_pos and 0x20 <= key <= 0x7F:
            st.input_string += chr(key)
            st.cursor_pos += 1
            r.display_character(chr(key))
    _edit_off(r, st)
    return cont


def string_edit(r, st, max_len):
    """text.cpp:936-985, the non-RTL branch: echo any pre-set string, then hand over to the loop."""
    st.cursor_pos = 0
    for ch in st.input_string:
        r.display_character(ch)
        st.cursor_pos += 1
    st.max_len = max_len
    st.entered = False
    _edit_off(r, st)


def get_string(r, st, strings, dest_nr, lead_in, row, column, max_len, keys):
    """op_cmd.cpp cmdGetString, with the inner loop driven by an explicit key list.

    ★★★★★ THE INNER LOOP IS THE PART THAT DOES NOT TRANSFER, AND IT IS A VM QUESTION, NOT A TEXT
    ONE. The engine calls cycleInnerLoopActive(CYCLE_INNERLOOP_GETSTRING) and then spins on
    processAGIEvents until a key ends it -- **re-entering the event pump without advancing the
    interpreter cycle.** Modelling that here would model ScummVM's event loop, not AGI, so the
    keys arrive as a list and the loop is a `for`. The port faces the real question (§2V).
    """
    if max_len > TEXT_STRING_MAX_SIZE:
        max_len = TEXT_STRING_MAX_SIZE
    prev_edit = st.edit_enabled
    saved = (r.crow, r.ccol, r.reset_col)        # charPos_Push
    _edit_on(r, st)
    if row < FONT_ROW_CHARACTERS:                # text.cpp: `if (stringRow < 25)`
        r.crow, r.ccol = row, column

    if lead_in is not None:
        processed = string_printf(lead_in, r.printf_state)
        # ★★ 40, not 30. The message box's default max width is 30 (text.cpp:458); get.string
        # wraps at 40 and the engine's own comment there says "?? not absolutely sure".
        wrapped, _, _ = string_word_wrap(processed, 40)
        r._display_text(wrapped, r.crow, r.ccol, r.fg, r.bg)

    st.input_string = ""                          # stringSet("")
    string_edit(r, st, max_len)
    for k in keys:
        if not string_key_press(r, st, k):
            break

    if 0 <= dest_nr < len(strings):
        strings[dest_nr] = st.input_string
    r.crow, r.ccol, r.reset_col = saved            # charPos_Pop
    if not prev_edit:
        _edit_off(r, st)
    return st.input_string


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# ★★★★ AC-9 -- WHAT `get.string` STILL NEEDS, NOW THAT THE DISPLAY SIDE EXISTS
#
# ★★★ Read at the pin, `cmdGetString` (op_cmd.cpp), so this is a list of named callees rather than
# a guess at a design. Its lead-in text path is ALREADY BUILT by this module:
#
#       stringPrintf(leadInTextPtr)          <- string_printf above
#       stringWordWrap(processed, 40)        <- string_word_wrap above, max_width 40 not 30
#       displayText(...)                     <- the _display_text path in TextRenderer
#
# ★★★★ SO THE REMAINING WORK IS NOT RENDERING, IT IS INPUT AND CURSOR STATE -- five things, none
# of which this reference models today:
#
#   1. `charPos_Push` / `charPos_Set(row, col)` / `charPos_Pop`. ★★ A SAVED CURSOR, and the push and
#      pop bracket the whole opcode, so it is a one-deep stack of two bytes. On the 6809 that is two
#      direct-page bytes, not a structure.
#   2. `inputEditOn` / `inputEditOff`, restored to the PREVIOUS state rather than to off
#      (`previousEditState`) -- ★★ an opcode that runs inside an existing edit must not end it.
#   3. `cycleInnerLoopActive(CYCLE_INNERLOOP_GETSTRING)`. ★★★★ THE HARD PART, AND IT IS A VM
#      QUESTION RATHER THAN A TEXT ONE: the interpreter re-enters a nested cycle loop that keeps
#      drawing and polling until the edit ends. **The port's main loop has no such re-entry today**
#      -- vm_cycle.s runs one pass and returns -- and it is the same shape as `have.key`.
#   4. `stringSet("")` then `stringEdit(maxLen)`, with `maxLen` clamped to TEXT_STRING_MAX_SIZE.
#      ★★ A FIXED 40-byte edit buffer (MAX_STRINGLEN), which the 6809 already wants.
#   5. `setString(destNr, _inputString)` into `strings[MAX_STRINGS + 1][MAX_STRINGLEN]`
#      -- ★★★ 25 x 40 = 1,000 BYTES of string table, and this is the storage `%s` reads. It is
#      currently modelled as empty here, and AC-7 measured that six of the nine titles use `%s`
#      (189 occurrences), so the empty model is a limit the gate cannot see past until this exists.
#
# ★★★ ONE MORE ORACLE GUARD THAT IS ONE-SIDED, in the same family as the three named in
# string_printf's docstring: `state->_curLogic->numTexts >= leadInTextNr` admits
# `leadInTextNr == numTexts`, one past the end, because leadInTextNr is already `parameter[1] - 1`.
# ★★ Not observed to fire; recorded so the port's choice there is made rather than inherited.
# ═══════════════════════════════════════════════════════════════════════════════════════════════
