#!/usr/bin/env python3
"""render.py -- resource bytes -> (visual, priority). The top-level entry point.

★★ NO GOLDEN FILES, EVER (AC-9). Nothing in tools/picrender/ reads a stored expected buffer,
and nothing here generates one. The only thing this output is ever compared against is the
pinned oracle's own rendered buffers (§2O.1, L-06). A golden file we produced would be a
comparison of our renderer against our renderer -- which is Karateka's rule-derived validation
that passed 109/109 while the rule was wrong [Cluster A].

★ Priority banding is NOT applied here. `initPriorityTable`/`setPriorityTable`
(graphics.cpp:1289-1315) build a Y->priority lookup used when SPRITES are drawn; a PICTURE's
priority screen is written only by the picture's own commands. Conflating the two would put
banding into a buffer the oracle leaves alone -- see AC-7, which verifies the table separately.
"""
from . import commands
from .screens import Screens


def render(data, width=None, height=None, label="?"):
    """Render one PICTURE resource. -> RenderResult (screens + stats + unknown opcodes).

    ★ The clear-to-white/4 happens HERE because decodePicture() does it before drawing
    (picture.cpp:770-772). A caller that reuses a Screens without clearing would be rendering
    an overlay, which is a different operation (`draw.pic` vs `overlay.pic`) and not what AC-3
    compares.
    """
    kw = {}
    if width is not None:
        kw["width"] = width
    if height is not None:
        kw["height"] = height
    screens = Screens(**kw)
    screens.clear()
    return commands.run(screens, data, label)


def priority_table_default(height=168):
    """graphics.cpp:1295-1303 createDefaultPriorityTable -- 14 bands of 12 rows, <4 clamped to 4.

    ★ AC-7. 14 x 12 = 168 = SCRIPT_HEIGHT exactly, which is why design §3.5 can call it a
    168-byte lookup rather than a computation.
    """
    table = []
    priority = 1
    while priority < 15:
        for _ in range(12):
            table.append(4 if priority < 4 else priority)
        priority += 1
    return table[:height]


def priority_table_override(priority_base, height=168):
    """graphics.cpp:1305-1315 setPriorityTable -- the game-supplied override.

        x = (SCRIPT_HEIGHT - priorityBase) * SCRIPT_HEIGHT / 10
        priority = (y - base) < 0 ? 4 : (y - base) * SCRIPT_HEIGHT / x + 5, capped at 15

    ★ Integer division throughout, and `x` can be zero when priorityBase == SCRIPT_HEIGHT --
    the oracle would divide by zero there. Reproduced with a guard rather than a silent clamp,
    so the boundary stays visible.
    """
    table = []
    x = (height - priority_base) * height // 10
    for y in range(height):
        if (y - priority_base) < 0:
            table.append(4)
        elif x == 0:
            table.append(15)          # ★ oracle divides by zero here; see docstring
        else:
            p = (y - priority_base) * height // x + 5
            table.append(15 if p > 15 else p)
    return table
