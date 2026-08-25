#!/usr/bin/env python3
"""inventory.py -- the OBJECT table: item names and their starting rooms.

★ FROM THE ORACLE (ScummVM 9d9b9e93, engines/agi/objects.cpp decodeObjects):

    u16      total size of the name-offset table   (LITTLE-endian)
    u8       number of animated objects            ★ ScummVM reads and IGNORES this
    entries[]  3 bytes each:  u16 name offset (LE), u8 starting room
    strings[]  NUL-terminated names

    numObjects = LE16(mem) / 3
    spos       = 3 for v2/v3 (version >= 0x2000), 0 for v1
    entry i is at spos + i*3;  name lives at LE16(entry) + spos

★★ THE ENCRYPTION TEST IS A HEURISTIC, AND IT IS THE ORACLE'S OWN:

    if (READ_LE_UINT16(mem) > flen)  decrypt(mem, flen);

i.e. *if the first field is an implausible size, the file must be encrypted.* There is no flag
and no magic number. Reproduced exactly rather than improved on -- guessing differently from
the oracle here would silently produce garbage names on some games and correct ones on others,
which is the worst possible split.

★ L-23 applied to that heuristic: it CAN fail, in a way worth naming. A *plaintext* OBJECT file
whose table size genuinely exceeds its own length would be misread as encrypted, and an
*encrypted* file whose first two bytes happen to decode below the length would be left
encrypted. Neither was observed in either corpus, and the check that would catch it is
`looks_like_names()` below -- which is why that exists rather than being assumed unnecessary.
"""
from .logic import decrypt, CRYPT_KEY_SIERRA

PAD_SIZE = 3          # 4 on Amiga (objects.cpp:31); no Amiga media in either corpus


class ObjectError(Exception):
    pass


class ObjectTable:
    __slots__ = ("names", "rooms", "num_animated", "was_encrypted", "raw_len")

    def __init__(self, names, rooms, num_animated, was_encrypted, raw_len):
        self.names = names                  # list[bytes] -- bytes, not str (game text, §2P)
        self.rooms = rooms                  # list[int]
        self.num_animated = num_animated
        self.was_encrypted = was_encrypted
        self.raw_len = raw_len

    def __len__(self):
        return len(self.names)


def parse(data, spos=PAD_SIZE, key=CRYPT_KEY_SIERRA):
    """Parse an OBJECT table.

    ★ `spos` is the offset of the first entry, and it is a PARAMETER rather than something
    derived from a version here. ScummVM computes it as `getVersion() >= 0x2000 ? padsize : 0`
    (objects.cpp:57) -- that is a VERSION BRANCH, and §4.2a puts version knowledge in
    resource.py alone. An earlier draft of this function took `version` and branched on it;
    harness/tools/seam_check.py flagged it at inventory.py:72 the first time it ran, which is
    the check earning its keep on the very code that introduced it.
    """
    n = len(data)
    if n < 3:
        raise ObjectError("OBJECT: %d bytes, too short" % n)

    table_size = data[0] | (data[1] << 8)
    was_encrypted = table_size > n
    if was_encrypted:
        data = decrypt(data, key)
        table_size = data[0] | (data[1] << 8)

    num_objects = table_size // PAD_SIZE
    if num_objects > 256:
        # ★ ScummVM returns OK here rather than dying, for AGDS games (objects.cpp:46-49).
        # Matching that is deliberate: refusing a file the oracle accepts would make our
        # corpus coverage differ from the baseline we are validated against.
        raise ObjectError("OBJECT: %d objects declared, over the 256 the oracle tolerates"
                          % num_objects)

    num_animated = data[2] if n > 2 else 0

    names, rooms = [], []
    for i in range(num_objects):
        so = spos + i * PAD_SIZE
        if so + 2 >= n:
            raise ObjectError("OBJECT: entry %d at %d runs past file (%d)" % (i, so, n))
        rooms.append(data[so + 2])
        off = (data[so] | (data[so + 1] << 8)) + spos
        if off >= n:
            names.append(b"")               # oracle warns and clears; same outcome
            continue
        stop = data.find(0, off)
        names.append(bytes(data[off:stop if stop != -1 else n]))

    return ObjectTable(names, rooms, num_animated, was_encrypted, n)


def looks_like_names(table, min_ratio=0.80):
    """Are the recovered names mostly printable? ★ The check that can catch a wrong
    encryption verdict (see the module docstring). Returns (ok, ratio)."""
    total = printable = 0
    for nm in table.names:
        for b in nm:
            total += 1
            if 32 <= b < 127:
                printable += 1
    if total == 0:
        return True, 1.0
    r = printable / total
    return r >= min_ratio, r


def digest(table):
    """Stable digest, so counts can be evidenced without printing game text (§2P)."""
    import hashlib
    h = hashlib.sha256()
    for nm, rm in zip(table.names, table.rooms):
        h.update(len(nm).to_bytes(2, "little"))
        h.update(nm)
        h.update(bytes([rm]))
    return h.hexdigest()
