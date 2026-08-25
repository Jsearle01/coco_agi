#!/usr/bin/env python3
"""draw.py -- lines, corners and the pen/brush, all transcribed from the oracle.

★ Read at 9d9b9e93: picture.cpp draw_Line / xCorner / yCorner / draw_LineShort /
draw_LineAbsolute / plotPattern.

★★ THE LINE ROUTINE IS NOT BRESENHAM AND MUST NOT BE "CORRECTED" TO IT. ScummVM's draw_Line
carries its own error-accumulation loop that steps BOTH axes each iteration, each gated on its
own error term. A standard Bresenham differs from it on some diagonals by a pixel, and a
one-pixel difference is a failed byte-comparison -- while looking perfectly reasonable on
screen. This is the same trap as the LOGIC `+1` message offset from P1.1: plausible output,
wrong bytes.

★ Endpoints are CLIPPED, not rejected (`CLIP<int16>(x, 0, _width - 1)`), so an off-screen
coordinate draws a line to the edge rather than nothing.

★ plotPattern's circle tables are copied verbatim. They are data, not an algorithm, and
regenerating them from a circle equation would be exactly the self-derived baseline §2O.1
forbids -- the shapes are whatever Sierra shipped, not whatever a circle ought to be.
"""
from .screens import MASK_PRIORITY, MASK_VISUAL

# plotPattern's tables, verbatim from picture.cpp
BINARY_LIST = (0x8000, 0x4000, 0x2000, 0x1000, 0x800, 0x400, 0x200, 0x100,
               0x80, 0x40, 0x20, 0x10, 0x8, 0x4, 0x2, 0x1)

CIRCLE_LIST = (0, 1, 4, 9, 16, 25, 37, 50)

CIRCLE_DATA = (
    0x8000,
    0x0000, 0xE000, 0x0000,
    0x7000, 0xF800, 0xF800, 0xF800, 0x7000,
    0x3800, 0x7C00, 0xFE00, 0xFE00, 0xFE00, 0x7C00, 0x3800,
    0x1C00, 0x7F00, 0xFF80, 0xFF80, 0xFF80, 0xFF80, 0xFF80, 0x7F00, 0x1C00,
    0x0E00, 0x3F80, 0x7FC0, 0x7FC0, 0xFFE0, 0xFFE0, 0xFFE0, 0x7FC0, 0x7FC0, 0x3F80, 0x1F00,
    0x0E00,
    0x0F80, 0x3FE0, 0x7FF0, 0x7FF0, 0xFFF8, 0xFFF8, 0xFFF8, 0xFFF8, 0xFFF8, 0x7FF0, 0x7FF0,
    0x3FE0, 0x0F80,
    0x07C0, 0x1FF0, 0x3FF8, 0x7FFC, 0x7FFC, 0xFFFE, 0xFFFE, 0xFFFE, 0xFFFE, 0xFFFE, 0x7FFC,
    0x7FFC, 0x3FF8, 0x1FF0, 0x07C0,
)


def _clip(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


class Pen:
    """Holds the draw state the primitives share, so nothing needs a global."""

    __slots__ = ("screens", "scr_on", "pri_on", "scr_color", "pri_color",
                 "pat_code", "pat_num", "pixels")

    def __init__(self, screens):
        self.screens = screens
        # picture.cpp drawPicture() initial state, lines 384-388
        self.scr_on = False
        self.pri_on = False
        self.scr_color = 15
        self.pri_color = 4
        self.pat_code = 0
        self.pat_num = 0
        self.pixels = 0

    @property
    def draw_mask(self):
        return ((MASK_VISUAL if self.scr_on else 0) |
                (MASK_PRIORITY if self.pri_on else 0))

    def put_virt_pixel(self, x, y):
        """PictureMgr::putVirtPixel -- bounds-check, then write the enabled planes."""
        if not self.screens.in_bounds(x, y):
            return
        mask = self.draw_mask
        if not mask:
            return
        self.screens.put_pixel(x, y, mask, self.scr_color, self.pri_color)
        self.pixels += 1


def draw_line(pen, x1, y1, x2, y2):
    """picture.cpp draw_Line -- transcribed, NOT replaced with Bresenham (see module doc)."""
    w, h = pen.screens.width, pen.screens.height
    x1 = _clip(x1, 0, w - 1)
    x2 = _clip(x2, 0, w - 1)
    y1 = _clip(y1, 0, h - 1)
    y2 = _clip(y2, 0, h - 1)

    if x1 == x2:                                  # vertical
        if y1 > y2:
            y1, y2 = y2, y1
        while y1 <= y2:
            pen.put_virt_pixel(x1, y1)
            y1 += 1
        return

    if y1 == y2:                                  # horizontal
        if x1 > x2:
            x1, x2 = x2, x1
        while x1 <= x2:
            pen.put_virt_pixel(x1, y1)
            x1 += 1
        return

    step_x, delta_x = 1, x2 - x1
    if delta_x < 0:
        step_x, delta_x = -1, -delta_x
    step_y, delta_y = 1, y2 - y1
    if delta_y < 0:
        step_y, delta_y = -1, -delta_y

    if delta_y > delta_x:
        i = detdelta = delta_y
        error_x, error_y = delta_y // 2, 0
    else:
        i = detdelta = delta_x
        error_x, error_y = 0, delta_x // 2

    x, y = x1, y1
    pen.put_virt_pixel(x, y)

    while True:
        error_y += delta_y
        if error_y >= detdelta:
            error_y -= detdelta
            y += step_y
        error_x += delta_x
        if error_x >= detdelta:
            error_x -= detdelta
            x += step_x
        pen.put_virt_pixel(x, y)
        i -= 1
        if i <= 0:
            break


def plot_pattern(pen, x, y):
    """picture.cpp plotPattern -- the pen/brush shape, transcribed including its oddities."""
    pen_x = x
    pen_y = y
    pen_size = pen.pat_code & 0x07
    ptr = CIRCLE_LIST[pen_size]

    pen_x = (pen_x * 2) - pen_size
    if pen_x < 0:
        pen_x = 0
    temp16 = (pen.screens.width * 2) - (2 * pen_size)
    if pen_x >= temp16:
        pen_x = temp16
    pen_x //= 2
    pen_final_x = pen_x

    pen_y = pen_y - pen_size
    if pen_y < 0:
        pen_y = 0
    temp16 = 167 - (2 * pen_size)      # ★ literal 167 in the oracle, not height-1
    if pen_y >= temp16:
        pen_y = temp16
    pen_final_y = pen_y

    t = pen.pat_num | 0x01
    temp16 = (pen_size << 1) + 1
    pen_final_y += temp16
    pen_width = temp16 << 1

    circle_cond = (pen.pat_code & 0x10) != 0
    counter_step = 4
    dither_cond = 0x02

    while pen_y < pen_final_y:
        circle_word = CIRCLE_DATA[ptr]
        ptr += 1
        counter = 0
        while counter <= pen_width:
            if circle_cond or (BINARY_LIST[counter >> 1] & circle_word) != 0:
                if (pen.pat_code & 0x20) != 0:
                    temp8 = t % 2
                    t >>= 1
                    if temp8 != 0:
                        t ^= 0xB8
                if (pen.pat_code & 0x20) == 0 or (t & 0x03) == dither_cond:
                    pen.put_virt_pixel(pen_x, pen_y)
            pen_x += 1
            counter += counter_step
        pen_x = pen_final_x
        pen_y += 1
