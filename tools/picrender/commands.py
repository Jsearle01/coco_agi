#!/usr/bin/env python3
"""commands.py -- the PICTURE opcode dispatch, and the byte-stream reader it needs.

★ From picture.cpp drawPicture() at 9d9b9e93. Read, not recalled -- L-25.

    0xF0  set visual colour, and _scrOn = TRUE     (the enable is implicit in the opcode)
    0xF1  _scrOn = FALSE
    0xF2  set priority colour, and _priOn = TRUE
    0xF3  _priOn = FALSE
    0xF4  yCorner
    0xF5  xCorner
    0xF6  line, absolute
    0xF7  line, short/relative
    0xF8  flood fill
    0xF9  _patCode = next byte
    0xFA  plot brush
    0xFF  end of data
    else  ★ the oracle emits `warning("Unknown picture opcode %02x")` and CONTINUES.

★★ AC-4 FORBIDS A SILENT NO-OP ON AN UNKNOWN OPCODE, and the oracle's own behaviour is a
warning-and-continue, which in a batch of 150 pictures is effectively silent. So this renderer
RECORDS every unknown opcode with the resource that used it, and the report lists them. A
silently skipped opcode produces a *plausible wrong picture* -- the failure the byte-comparison
exists to catch, and the one that would otherwise be blamed on the fill.

★ THE PARAMETER TERMINATOR IS THE OPCODE RANGE ITSELF (getNextParamByte, picture.cpp:104):
a value >= _minCommand (0xF0) is NOT a parameter; the reader rewinds one byte and the current
command ends. So commands are self-terminating and there is no length field anywhere. ★ That is
why an off-by-one in the reader desynchronises the whole rest of the picture rather than
corrupting one shape -- and why `_dataOffsetNibble` (v3's 4-bit parameters) must never be
enabled for v2 data.
"""
from . import draw as draw_mod
from .fill import FillStats, flood

MIN_COMMAND = 0xF0          # picture.cpp:64


class PictureData:
    """The byte-stream reader. Mirrors getNextByte / getNextParamByte exactly."""

    __slots__ = ("data", "offset", "nibble")

    def __init__(self, data, nibble_mode=False):
        self.data = data
        self.offset = 0
        # ★ v3-only 4-bit parameters. Kept for shape, never enabled for v2 (dispatch §12).
        self.nibble = nibble_mode

    def at_end(self):
        return self.offset >= len(self.data)

    def next_byte(self):
        if self.offset >= len(self.data):
            return 0xFF                     # treat exhaustion as end-of-data
        b = self.data[self.offset]
        self.offset += 1
        return b

    def next_param_byte(self):
        """-> (ok, value). ok is False when the next byte is an OPCODE, and the read rewinds."""
        if self.offset >= len(self.data):
            return False, 0
        value = self.data[self.offset]
        self.offset += 1
        if value >= MIN_COMMAND:
            self.offset -= 1                # ★ rewind, exactly as the oracle does
            return False, 0
        return True, value

    def next_coordinates(self):
        okx, x = self.next_param_byte()
        if not okx:
            return False, 0, 0
        oky, y = self.next_param_byte()
        if not oky:
            return False, 0, 0
        return True, x, y


class RenderResult:
    __slots__ = ("screens", "stats", "unknown_opcodes", "opcode_counts", "line_pixels")

    def __init__(self, screens, stats, unknown, counts, line_pixels):
        self.screens = screens
        self.stats = stats
        self.unknown_opcodes = unknown        # list[(opcode, offset)]
        self.opcode_counts = counts
        self.line_pixels = line_pixels


def run(screens, data, resource_label="?"):
    """Execute a PICTURE byte stream against `screens`. -> RenderResult."""
    pen = draw_mod.Pen(screens)
    st = PictureData(data)
    stats = FillStats()
    unknown = []
    counts = {}

    while not st.at_end():
        cur = st.next_byte()
        counts[cur] = counts.get(cur, 0) + 1

        if cur == 0xF0:
            pen.scr_color = st.next_byte()
            pen.scr_on = True
        elif cur == 0xF1:
            pen.scr_on = False
        elif cur == 0xF2:
            pen.pri_color = st.next_byte()
            pen.pri_on = True
        elif cur == 0xF3:
            pen.pri_on = False
        elif cur == 0xF4:
            _y_corner(pen, st)
        elif cur == 0xF5:
            _x_corner(pen, st)
        elif cur == 0xF6:
            _line_absolute(pen, st)
        elif cur == 0xF7:
            _line_short(pen, st)
        elif cur == 0xF8:
            _do_fill(pen, st, screens, stats)
        elif cur == 0xF9:
            pen.pat_code = st.next_byte()
        elif cur == 0xFA:
            _plot_brush(pen, st)
        elif cur == 0xFF:
            break
        else:
            # ★ AC-4: recorded, never silently skipped.
            unknown.append((cur, st.offset - 1))

    return RenderResult(screens, stats, unknown, counts, pen.pixels)


def _x_corner(pen, st):
    ok, x1, y1 = st.next_coordinates()
    if not ok:
        return
    pen.put_virt_pixel(x1, y1)
    while True:
        okx, x2 = st.next_param_byte()
        if not okx:
            break
        draw_mod.draw_line(pen, x1, y1, x2, y1)
        x1 = x2
        oky, y2 = st.next_param_byte()
        if not oky:
            break
        draw_mod.draw_line(pen, x1, y1, x1, y2)
        y1 = y2


def _y_corner(pen, st):
    ok, x1, y1 = st.next_coordinates()
    if not ok:
        return
    pen.put_virt_pixel(x1, y1)
    while True:
        oky, y2 = st.next_param_byte()
        if not oky:
            break
        draw_mod.draw_line(pen, x1, y1, x1, y2)
        y1 = y2
        okx, x2 = st.next_param_byte()
        if not okx:
            break
        draw_mod.draw_line(pen, x1, y1, x2, y1)
        x1 = x2


def _line_absolute(pen, st):
    ok, x1, y1 = st.next_coordinates()
    if not ok:
        return
    pen.put_virt_pixel(x1, y1)
    while True:
        ok2, x2, y2 = st.next_coordinates()
        if not ok2:
            break
        draw_mod.draw_line(pen, x1, y1, x2, y2)
        x1, y1 = x2, y2


def _line_short(pen, st):
    ok, x1, y1 = st.next_coordinates()
    if not ok:
        return
    pen.put_virt_pixel(x1, y1)
    while True:
        okd, disp = st.next_param_byte()
        if not okd:
            break
        dx = ((disp & 0xF0) >> 4) & 0x0F
        dy = disp & 0x0F
        if dx & 0x08:
            dx = -(dx & 0x07)
        if dy & 0x08:
            dy = -(dy & 0x07)
        draw_mod.draw_line(pen, x1, y1, x1 + dx, y1 + dy)
        x1 += dx
        y1 += dy


def _do_fill(pen, st, screens, stats):
    while True:
        ok, x, y = st.next_coordinates()
        if not ok:
            break
        flood(screens, x, y, pen.scr_on, pen.pri_on,
              pen.scr_color, pen.pri_color, stats)


def _plot_brush(pen, st):
    while True:
        if pen.pat_code & 0x20:
            okn, num = st.next_param_byte()
            if not okn:
                break
            pen.pat_num = num
        ok, x1, y1 = st.next_coordinates()
        if not ok:
            break
        draw_mod.plot_pattern(pen, x1, y1)
