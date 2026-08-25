#!/usr/bin/env python3
"""volume.py -- VOL record headers and raw resource extraction by (volume, offset).

★★ THIS MODULE KNOWS NOTHING ABOUT AGI VERSIONS (design §4.2a, AC-8).
The header length is a PARAMETER, not a branch. v2 records have a 5-byte header and v3 records
7; that choice belongs to resource.py, which is the one place allowed to know which version it
is looking at. Passing it in is what keeps the seam real rather than decorative -- a version
`if` here would put version knowledge in the retrieval layer and the v3 deferral would stop
being reversible.

★ THE FORMAT IS THE ORACLE'S, read at the pin (ScummVM 9d9b9e93,
engines/agi/loader_v2.cpp:134-176):

    fp.read(&volumeHeader, _hasV3VolumeFormat ? 7 : 5);
    signature = READ_BE_UINT16(volumeHeader);        // must be 0x1234
    agid->len = READ_LE_UINT16(volumeHeader + 3);

So a v2 record header is:
    [0..1]  0x12 0x34   signature, BIG-endian
    [2]     volume number  (bit 7 is a v3 "compressed picture" flag; meaningless in v2)
    [3..4]  length, LITTLE-endian
followed by `length` bytes of resource data.

★ MIXED ENDIANNESS IN A FIVE-BYTE HEADER is exactly the sort of detail worth taking from the
implementation rather than from prose: the signature is big-endian and the length beside it is
little-endian. Getting that backwards yields a plausible-looking length and silent corruption.
"""

SIGNATURE = 0x1234
V2_HEADER_LEN = 5
V3_HEADER_LEN = 7


class VolumeError(Exception):
    pass


class Volume:
    """One VOL file, held in memory, read-only (§2P)."""

    def __init__(self, name, data):
        self.name = name
        self.data = data

    @classmethod
    def from_path(cls, path):
        import pathlib
        p = pathlib.Path(path)
        return cls(p.name, p.read_bytes())                 # 'rb' -- read only, always

    @classmethod
    def from_bytes(cls, name, data):
        """For OS-9 images, where the VOL never exists as a host file (AC-9)."""
        return cls(name, data)

    def __len__(self):
        return len(self.data)

    def read_record(self, offset, header_len=V2_HEADER_LEN):
        """-> (payload_bytes, declared_len, header_volume_byte)

        ★ EVERY FAILURE MODE HERE IS RAISED, NOT PAPERED OVER. A record that overruns the file
        is AC-4's explicit check ("no resource may overrun its volume"), and returning a short
        buffer instead of raising would turn a parser bug into a quiet truncation that only
        surfaces as a wrong picture ten steps downstream.
        """
        if offset < 0 or offset + header_len > len(self.data):
            raise VolumeError("%s: header at 0x%05X runs past end (%d bytes)"
                              % (self.name, offset, len(self.data)))

        hdr = self.data[offset:offset + header_len]
        sig = (hdr[0] << 8) | hdr[1]                       # BIG-endian
        if sig != SIGNATURE:
            raise VolumeError("%s: bad signature 0x%04X at 0x%05X (expected 0x1234)"
                              % (self.name, sig, offset))

        vol_byte = hdr[2]
        length = hdr[3] | (hdr[4] << 8)                    # LITTLE-endian

        start = offset + header_len
        end = start + length
        if end > len(self.data):
            raise VolumeError("%s: record at 0x%05X declares %d bytes, only %d available"
                              % (self.name, offset, length, len(self.data) - start))

        return self.data[start:end], length, vol_byte


class VolumeSet:
    """The vol.N files of one game, however they are sourced.

    ★ Sourcing is deliberately abstract: the fan corpus has `vol.0` on disk, the CoCo3 corpus
    has it inside an OS-9 image, and AC-9 requires both to work. A dict of name -> bytes is the
    whole interface, so neither medium leaks into the parser.
    """

    def __init__(self):
        self._vols = {}

    def add(self, number, volume):
        self._vols[int(number)] = volume

    def add_bytes(self, number, name, data):
        self.add(number, Volume.from_bytes(name, data))

    def get(self, number):
        v = self._vols.get(int(number))
        if v is None:
            raise VolumeError("volume %s not present (have %s)"
                              % (number, sorted(self._vols)))
        return v

    def numbers(self):
        return sorted(self._vols)

    def total_bytes(self):
        return sum(len(v) for v in self._vols.values())

    def read(self, number, offset, header_len=V2_HEADER_LEN):
        return self.get(number).read_record(offset, header_len)
