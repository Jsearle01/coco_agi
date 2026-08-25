#!/usr/bin/env python3
"""dirfile.py -- AGI DIR parsing: (type, index) -> (volume, offset).

★★ THIS MODULE FINDS RESOURCES. IT DOES NOT DECODE THEM (design §4.2a).
It yields (volume, offset) and stops. Turning those bytes into a LOGIC or a PICTURE is
resource.py's job, and keeping the two apart is what makes the v3 deferral reversible: a v3
loader is a new decoder behind the same seam, not a rewrite of everything that calls it.

★ THE FORMAT IS TAKEN FROM THE ORACLE, NOT FROM THE SPECS.
CLAUDE.md §2 ranks ScummVM (tier 3) above the AGI Specifications (tier 4, "known incomplete in
places"). Read at the pin, ScummVM 9d9b9e93, engines/agi/loader_v2.cpp:31-68:

    agid[i/3].volume = *(mem + i) >> 4;
    agid[i/3].offset = READ_BE_UINT24(mem + i) & _EMPTY;      // _EMPTY = 0xfffff, agi.h:88

So each entry is THREE bytes:
    volume = byte0 >> 4                       (top nibble)
    offset = big-endian 24-bit & 0x0FFFFF     (low 20 bits)
An unused entry is FF FF FF, which yields offset == 0xFFFFF == _EMPTY. ★ Note the volume
nibble of an empty entry reads as 15 and is meaningless; test the OFFSET, never the volume.

★ A DIR file's length is not required to be a multiple of 3. ScummVM's loop condition is
`i + 2 < flen`, so a trailing 1- or 2-byte remainder is IGNORED rather than treated as an
error. Reproduced here exactly -- this is the kind of edge the Specs do not mention.
"""
import pathlib

ENTRY_SIZE = 3
EMPTY = 0xFFFFF

# The four v2 directory files, in ScummVM's own load order (loader_v2.cpp:116-122).
# ★ Case varies BY CORPUS: the fan set uses lower case, the CoCo3 OS-9 media uses `logDir`.
# Callers pass the actual name; this module never guesses one.
DIR_TYPES = ("LOGIC", "PICTURE", "VIEW", "SOUND")


class DirEntry:
    __slots__ = ("restype", "index", "volume", "offset")

    def __init__(self, restype, index, volume, offset):
        self.restype = restype
        self.index = index
        self.volume = volume
        self.offset = offset

    @property
    def present(self):
        return self.offset != EMPTY

    def __repr__(self):
        if not self.present:
            return "<%s %d: empty>" % (self.restype, self.index)
        return "<%s %d: vol %d @ 0x%05X>" % (self.restype, self.index, self.volume, self.offset)


def parse_dir_bytes(data, restype):
    """Parse a DIR file's bytes -> list[DirEntry], including empty slots.

    Empty slots are RETAINED and returned with present == False, because the INDEX is the
    resource's identity: LOGIC 7 is the eighth 3-byte slot whether or not slots 0-6 are used.
    Dropping empties would renumber every resource after the first gap.
    """
    out = []
    n = len(data) // ENTRY_SIZE
    for i in range(n):
        o = i * ENTRY_SIZE
        b0, b1, b2 = data[o], data[o + 1], data[o + 2]
        volume = b0 >> 4
        offset = (((b0 << 16) | (b1 << 8) | b2)) & EMPTY
        out.append(DirEntry(restype, i, volume, offset))
    return out


def parse_dir_file(path, restype):
    return parse_dir_bytes(pathlib.Path(path).read_bytes(), restype)   # 'rb' -- read only (§2P)


def slot_count(data):
    """Number of 3-byte SLOTS, matching P0.3's manifest column of the same name.

    ★ Slots are an UPPER BOUND on live resources -- an unused slot is FF FF FF and still
    occupies its three bytes. AC-3 cross-checks this against the manifest, and the two are
    expected to agree exactly because both are len/3; the interesting number is how many slots
    are PRESENT, which only this parser can say.
    """
    return len(data) // ENTRY_SIZE
