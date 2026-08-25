#!/usr/bin/env python3
"""screens.py -- the visual and priority buffers a PICTURE renders into.

★ EVERY CONSTANT HERE WAS READ AT THE PIN, NOT INFERRED (L-25 -- my own RESOURCETYPE_* lesson,
where an enum that "obviously" started at 0 started at 1 and mislabelled 299 comparisons):

    _DEFAULT_WIDTH   160        picture.h:27
    _DEFAULT_HEIGHT  168        picture.h:28
    initial fill     visual 15 (white), priority 4      picture.cpp:387-388,
                                                        picture.h:56 getInitialPriorityColor()
    clear on decode  _gfx->clear(15, getInitialPriorityColor())   picture.cpp:771

★★ TWO BUFFERS, ONE BYTE PER PIXEL, NOT PACKED. ScummVM's `_gameScreen` and `_priorityScreen`
are each `calloc(SCRIPT_WIDTH * SCRIPT_HEIGHT)` -- 26,880 bytes apiece, flat row-major, one byte
per pixel even though only 4 bits carry data (graphics.cpp:200-202, confirmed at P0.2). We match
that layout exactly because AC-3 diffs against those buffers byte for byte. ★ The CoCo3's packed
4bpp framebuffer is a P3 concern and deliberately absent here -- packing now would put a
transformation between us and the baseline, which is what §2O.1 forbids.
"""

WIDTH = 160
HEIGHT = 168
PIXELS = WIDTH * HEIGHT

VISUAL_WHITE = 15          # the colour a visual fill floods INTO
PRIORITY_RED = 4           # the value a priority fill floods INTO

# draw-mask bits, mirroring GFX_SCREEN_MASK_* (graphics.h)
MASK_VISUAL = 0x01
MASK_PRIORITY = 0x02


class Screens:
    """The pair of 160x168 byte planes a picture is drawn into."""

    __slots__ = ("visual", "priority", "width", "height")

    def __init__(self, width=WIDTH, height=HEIGHT):
        self.width = width
        self.height = height
        self.visual = bytearray(width * height)
        self.priority = bytearray(width * height)

    def clear(self, visual_color=VISUAL_WHITE, priority_color=PRIORITY_RED):
        """★ decodePicture() clears to white/4 BEFORE drawing (picture.cpp:771). A picture that
        draws nothing is therefore a white screen at priority 4, not a black one -- and P0.3
        measured exactly that: 156 of 193 priority dumps were uniform 4."""
        n = self.width * self.height
        self.visual = bytearray([visual_color]) * n
        self.priority = bytearray([priority_color]) * n

    def in_bounds(self, x, y):
        """picture.cpp getGraphicsCoordinates(): 0 <= x < _width && 0 <= y < _height."""
        return 0 <= x < self.width and 0 <= y < self.height

    def put_pixel(self, x, y, draw_mask, color, priority):
        """GfxMgr::putPixel (graphics.cpp:412-421) -- writes each plane only if its mask bit
        is set. ★ Note it does NOT bounds-check; PictureMgr::putVirtPixel does that first."""
        off = y * self.width + x
        if draw_mask & MASK_VISUAL:
            self.visual[off] = color
        if draw_mask & MASK_PRIORITY:
            self.priority[off] = priority

    def get_color(self, x, y):
        return self.visual[y * self.width + x]

    def get_priority(self, x, y):
        return self.priority[y * self.width + x]

    def digests(self):
        import hashlib
        return (hashlib.sha256(self.visual).hexdigest(),
                hashlib.sha256(self.priority).hexdigest())
