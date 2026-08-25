#!/usr/bin/env python3
"""fill.py -- the flood fill. ★★★ THIS IS THE TASK; everything else is bookkeeping around it.

Design §6.2 and §9 rank this first, and §11.2's M-02 is open: *what room-change delay is
acceptable, and does scanline fill meet it?* So this module does two jobs -- render correctly,
and REPORT WHAT IT COST, because a correct fill with no cost data leaves M-02 where it was.

────────────────────────────────────────────────────────────────────────────────────────────
THE ALGORITHM IS THE ORACLE'S (picture.cpp draw_Fill, read at 9d9b9e93)
────────────────────────────────────────────────────────────────────────────────────────────
It is a SCANLINE fill with a stack of SEED POINTS -- not a per-pixel queue, and not a stack of
spans. Per popped seed: scan left to the border, then walk right plotting, and while walking,
push ONE seed for each contiguous fillable run found on the row above and the row below.

★ `newspanUp` / `newspanDown` are what keep it a scanline fill rather than a pixel flood: a
seed is pushed only at the START of a run, so a 100-pixel-wide opening above costs one push,
not a hundred. Getting that wrong still renders correctly and explodes the stack -- which is
precisely the number AC-5 exists to measure, so a wrong-but-correct fill would corrupt the
answer to M-02 while looking fine.

────────────────────────────────────────────────────────────────────────────────────────────
★★ THE BOUNDARY TEST, WHICH IS THE SUBTLE PART (draw_FillCheck, picture.cpp)
────────────────────────────────────────────────────────────────────────────────────────────
    if (!_priOn && _scrOn && _scrColor != 15)  return screenColor == 15;
    if (_priOn && !_scrOn && _priColor != 4)   return screenPriority == 4;
    return (_scrOn && screenColor == 15 && _scrColor != 15);

Three cases, and the third is the one §5 of the dispatch flags:

  1. VISUAL ONLY      -> flood into white (15), bounded by non-white.
  2. PRIORITY ONLY    -> flood into red (4), bounded by non-red.
  3. ★★ BOTH ON       -> the test is `screenColor == 15`, THE VISUAL SCREEN ALONE.
     So with both enabled the priority fill is bounded by boundaries that exist only on the
     visual screen. Confirmed at the pin, not taken from the Specs -- AC-6.

★ TWO GUARDS THAT LOOK LIKE NOISE AND ARE NOT: `_scrColor != 15` and `_priColor != 4`. Filling
white into white, or 4 into 4, would never terminate; the oracle makes those a no-op by letting
the test return false immediately. A renderer that "helpfully" allowed them would hang.

★ `horizontalCheck` IS ACCEPTED AND NEVER READ in ScummVM's implementation. The AGI Specs
describe a horizontal-only variant of the check; the oracle ignores the distinction. §2.1: that
is a fact about ScummVM. It is reproduced here -- with the parameter kept and unused, so the
divergence stays visible instead of being tidied away.
"""
from .screens import MASK_PRIORITY, MASK_VISUAL


class FillStats:
    """★ AC-5. The stack depth is the number design §6.2 needs -- it bounds what the 6809 must
    hold, and it is the input to M-02 and thence to M-13."""

    __slots__ = ("invocations", "pixels", "pushes", "max_depth", "skipped")

    def __init__(self):
        self.invocations = 0     # draw_Fill(x, y) calls that actually ran
        self.pixels = 0          # pixels plotted by fills
        self.pushes = 0          # seeds pushed
        self.max_depth = 0       # ★ peak seed-stack depth, over the whole picture
        self.skipped = 0         # fills that returned immediately (both screens off)

    def merge(self, other):
        self.invocations += other.invocations
        self.pixels += other.pixels
        self.pushes += other.pushes
        self.max_depth = max(self.max_depth, other.max_depth)
        self.skipped += other.skipped

    def as_dict(self):
        return {"fills": self.invocations, "pixels": self.pixels, "pushes": self.pushes,
                "max_depth": self.max_depth, "skipped": self.skipped}


def fill_check(screens, x, y, scr_on, pri_on, scr_color, pri_color, horizontal_check=False):
    """draw_FillCheck. ★ `horizontal_check` is accepted and unused -- see the module docstring."""
    if not screens.in_bounds(x, y):
        return False

    screen_color = screens.get_color(x, y)
    screen_priority = screens.get_priority(x, y)

    if not pri_on and scr_on and scr_color != 15:
        return screen_color == 15
    if pri_on and not scr_on and pri_color != 4:
        return screen_priority == 4
    return scr_on and screen_color == 15 and scr_color != 15


def flood(screens, x, y, scr_on, pri_on, scr_color, pri_color, stats=None):
    """One draw_Fill(x, y). Returns the FillStats for this invocation."""
    st = stats if stats is not None else FillStats()

    # picture.cpp: if (!_scrOn && !_priOn) return;
    if not scr_on and not pri_on:
        st.skipped += 1
        return st

    st.invocations += 1

    draw_mask = (MASK_VISUAL if scr_on else 0) | (MASK_PRIORITY if pri_on else 0)

    def check(cx, cy, horiz):
        return fill_check(screens, cx, cy, scr_on, pri_on, scr_color, pri_color, horiz)

    stack = [(x, y)]
    st.pushes += 1
    st.max_depth = max(st.max_depth, len(stack))

    while stack:
        px, py = stack.pop()

        if not check(px, py, False):
            continue

        # scan left for the border
        c = px - 1
        while check(c, py, True):
            c -= 1

        newspan_up = True
        newspan_down = True
        c += 1
        while check(c, py, True):
            screens.put_pixel(c, py, draw_mask, scr_color, pri_color)
            st.pixels += 1

            if check(c, py - 1, False):
                if newspan_up:
                    stack.append((c, py - 1))
                    st.pushes += 1
                    if len(stack) > st.max_depth:
                        st.max_depth = len(stack)
                    newspan_up = False
            else:
                newspan_up = True

            if check(c, py + 1, False):
                if newspan_down:
                    stack.append((c, py + 1))
                    st.pushes += 1
                    if len(stack) > st.max_depth:
                        st.max_depth = len(stack)
                    newspan_down = False
            else:
                newspan_down = True

            c += 1

    return st
