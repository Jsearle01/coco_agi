"""VIEW resource decoding: loops, cels, RLE, mirroring.

Transcribed from the pinned oracle's view.cpp decodeView() (113-296) and unpackViewCelData()
(302-390). ★ CLAUDE.md §2 ranks ScummVM above the AGI Specifications, and the Specs are tier 4
and known incomplete; where the two differ this file follows the oracle, and the difference is
recorded below as a finding rather than silently resolved.

★★ WHAT THE SPECS DO NOT TELL YOU, found by reading the oracle:

1. MIRRORING IS NOT "FLIP THE CEL". The cel header's mirror byte carries BOTH a mirror bit
   (0x80) AND the loop number the cel originally belongs to (bits 4-6). A cel is mirrored only
   when that recorded loop is NOT the loop currently being walked -- so the SAME cel bytes
   decode un-mirrored in their home loop and mirrored in the borrowing loop. Reading bit 7
   alone mirrors the original too, and the sprite faces the wrong way in half its loops.

2. MIRRORING HAPPENS DURING DECODE, NOT AFTER. The oracle walks the destination buffer
   BACKWARDS while unpacking (view.cpp:311-315, 348-358), rather than decoding forwards and
   reversing rows afterwards. Reproduced here as index arithmetic. The two are equivalent for
   well-formed data and NOT equivalent for a row whose chunks overrun its width, which the
   oracle treats as an error.

3. ★ VERSION 0x2230 PUTS THE MIRROR DATA IN THE LOOP HEADER (L-24 -- name the variant). There
   the cel-count byte's low nibble is the count and bits 4-5 are the mirror loop -- TWO bits,
   not the three used in the cel header. Only early xmascard is affected. Implemented and
   flagged; no pinned corpus title uses it.

4. A ROW ENDS ON A ZERO BYTE and any remaining pixels are the clear key. The row is NOT
   implicitly terminated by filling `width` pixels -- except on Apple II, which has no
   terminators at all. Apple II is out of scope here but the asymmetry is why the loop reads
   the way it does.

★ NOT REPRODUCED: the CGA dithering pass at view.cpp:373-388, which rewrites every pixel
through getCGAMixtureColor. It runs only for _renderMode == kRenderCGA; the oracle runs EGA
(see agivm/cycle.py start()), so it is dead for every comparison this project makes. Called out
because a CGA-rendered oracle would produce different cel bytes and the diff would look broken.
"""

from .optable import kAgiComputerPC  # noqa: F401  (keeps the generated module a hard dependency)


class ViewError(Exception):
    pass


class Cel:
    __slots__ = ("width", "height", "clear_key", "mirrored", "pixels")

    def __init__(self, width, height, clear_key, mirrored, pixels):
        self.width = width
        self.height = height
        self.clear_key = clear_key
        self.mirrored = mirrored
        self.pixels = pixels          # bytearray, width*height, one byte per pixel

    def __repr__(self):
        return "<Cel %dx%d key=%d%s>" % (self.width, self.height, self.clear_key,
                                         " mirrored" if self.mirrored else "")


class Loop:
    __slots__ = ("cels",)

    def __init__(self, cels):
        self.cels = cels

    def __len__(self):
        return len(self.cels)


class View:
    __slots__ = ("loops", "description", "header_step_size", "header_cycle_time")

    def __init__(self, loops, description, step_size=0, cycle_time=0):
        self.loops = loops
        self.description = description
        self.header_step_size = step_size
        self.header_cycle_time = cycle_time

    @property
    def loop_count(self):
        return len(self.loops)


def _le16(b, o):
    return b[o] | (b[o + 1] << 8)


def decode_view(data, version=0x2917, view_nr=-1):
    """Decode a VIEW resource. Returns a View.

    Mirrors decodeView(). Apple II and AGI256 variants are refused rather than mis-decoded:
    both change the header size or the clear-key width, and guessing would produce a plausible
    wrong cel instead of an error.
    """
    if len(data) < 5:
        raise ViewError("view %d: unexpected end of view data (%d bytes)" % (view_nr, len(data)))

    if version < 0x2000:
        step_size, cycle_time = data[0], data[1]
    else:
        step_size, cycle_time = 0, 0

    header_loop_count_offset = 2
    view_header_size = 5

    loop_count = data[header_loop_count_offset]
    description_offset = _le16(data, header_loop_count_offset + 1)

    description = None
    if description_offset:
        end = description_offset
        while end < len(data) and data[end] != 0:
            end += 1
        description = bytes(data[description_offset:end])

    if not loop_count:
        return View([], description, step_size, cycle_time)

    if len(data) < view_header_size + loop_count * 2:
        raise ViewError("view %d: unexpected end of view data (loop offsets)" % view_nr)

    mirror_in_loop_header = (version == 0x2230)

    loops = []
    for loop_nr in range(loop_count):
        loop_offset = _le16(data, view_header_size + loop_nr * 2)
        if len(data) < loop_offset + 1:
            raise ViewError("view %d: unexpected end of view data (loop header)" % view_nr)

        loop_header_byte = data[loop_offset]
        if mirror_in_loop_header:
            cel_count = loop_header_byte & 0x0F
        else:
            cel_count = loop_header_byte

        if len(data) < loop_offset + 1 + cel_count * 2:
            raise ViewError("view %d: unexpected end of view data (cel offsets)" % view_nr)

        cels = []
        for cel_nr in range(cel_count):
            cel_offset = _le16(data, loop_offset + 1 + cel_nr * 2) + loop_offset
            if len(data) < cel_offset + 3:
                raise ViewError("view %d: unexpected end of view data (cel header)" % view_nr)

            width = data[cel_offset + 0]
            height = data[cel_offset + 1]
            tm = data[cel_offset + 2]

            clear_key = tm & 0x0F
            mirrored = False
            if mirror_in_loop_header:
                if loop_header_byte & 0x80:
                    mirror_loop = (loop_header_byte >> 4) & 0x03
                    if mirror_loop != loop_nr:
                        mirrored = True
            else:
                if tm & 0x80:
                    mirror_loop = (tm >> 4) & 0x07
                    if mirror_loop != loop_nr:
                        mirrored = True

            if width == 0 and height == 0:
                raise ViewError("view %d: cel is 0x0" % view_nr)

            comp = data[cel_offset + 3:]
            if len(comp) == 0:
                raise ViewError("view %d: compressed cel size is 0 bytes" % view_nr)

            pixels = _unpack_cel(comp, width, height, clear_key, mirrored, view_nr)
            cels.append(Cel(width, height, clear_key, mirrored, pixels))

        loops.append(Loop(cels))

    return View(loops, description, step_size, cycle_time)


def _unpack_cel(comp, width, height, clear_key, mirrored, view_nr):
    """unpackViewCelData(). Index arithmetic mirrors the oracle's pointer arithmetic exactly."""
    raw = bytearray(width * height)

    remaining_height = height
    remaining_width = width
    adjust_pre = 0
    adjust_after = 1
    p = 0

    if mirrored:
        adjust_pre = -1
        adjust_after = 0
        p += width

    pos = 0
    n = len(comp)

    while remaining_height:
        if pos >= n:
            raise ViewError("view %d: unexpected end of data while unpacking" % view_nr)
        cur = comp[pos]
        pos += 1

        if cur == 0:
            color = clear_key
            chunk_len = remaining_width
        else:
            color = cur >> 4
            chunk_len = cur & 0x0F
            if chunk_len > remaining_width:
                raise ViewError("view %d: invalid chunk (len %d > remaining %d)"
                                % (view_nr, chunk_len, remaining_width))

        if chunk_len == 0:
            pass
        elif chunk_len == 1:
            p += adjust_pre
            raw[p] = color
            p += adjust_after
        else:
            if mirrored:
                p -= chunk_len
            raw[p:p + chunk_len] = bytes([color]) * chunk_len
            if not mirrored:
                p += chunk_len

        remaining_width -= chunk_len

        if cur == 0:
            remaining_width = width
            remaining_height -= 1
            if mirrored:
                p += width * 2

    return raw
