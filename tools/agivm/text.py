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

    def __init__(self, window_row_min=2):
        # ★ _window_Row_Min is `gameRow` (text.cpp:93). For a normal v2 game with the status line
        # at row 0 the message box sits two rows down, which the capture confirms: the first
        # message's startingRow is 8 and its first glyph is logged at row 10.
        self.window_row_min = window_row_min
        self.events = []            # ★★ gate-only; see the §2V table
        self.checksum = 0
        self._msg = None

    # ── the checksum patch 0010 keeps, so neither side needs the characters (§2P) ──────────
    def _hash(self, ch):
        self.checksum = (self.checksum * 31 + ord(ch)) & 0xFFFFFFFF
        return self.checksum & 0xFFFF

    def draw_message_box(self, text, wanted_width=0, wanted_row=-1, wanted_column=-1):
        """text.cpp:445-519."""
        max_width = wanted_width
        if wanted_width == 0:
            max_width = 30                       # text.cpp:457-458

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
        """text.cpp:295-342 -- displayText's loop and displayCharacter."""
        reset_column = column
        for ch in text:
            if ch in ("\n", "\r"):
                if row < (FONT_ROW_CHARACTERS - 1):
                    row += 1
                column = reset_column
                continue
            self.events.append(("G", row, column, fg, bg, self._hash(ch)))
            column += 1
            if column > (FONT_COLUMN_CHARACTERS - 1):
                # ★ displayCharacter recurses with 0x0D rather than wrapping inline
                if row < (FONT_ROW_CHARACTERS - 1):
                    row += 1
                column = reset_column

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
