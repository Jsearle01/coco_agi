#!/usr/bin/env python3
"""logic.py -- LOGIC resource: bytecode/message split and the Avis Durgan decode.

★★ THIS DOES NOT DISASSEMBLE THE BYTECODE. It splits the resource and recovers the message
strings. Opcode decoding is the VM's problem [design §11.1 defers it]; §12 keeps it out of this
task, and the split is what the storage layer actually needs.

★ LAYOUT, FROM THE ORACLE (ScummVM 9d9b9e93, engines/agi/logic.cpp decodeLogic), whose own
comment states it more precisely than the Specs do:

    bytecode section:
        u16      bytecode size            (LITTLE-endian)
        u8[]     bytecode
    message section:
        u8       message count
        u16      messages size            (2 + offsets + strings)
        u16[]    string offsets           ★ RELATIVE TO message_section_pos + 1
        string[] strings, NUL-terminated, possibly encrypted

★★ THE "+1" IN THE OFFSET BASE IS THE DETAIL TO GET RIGHT. Offsets are relative to
`messageSectionPos + 1`, not to the section start and not to the resource start. Off by one and
every message reads one byte late -- which yields *plausible text*, shifted, and would sail past
any eyeball check. Taken from the implementation, not inferred.

★ THE XOR KEY AND ITS SCOPE: `Avis Durgan`, 11 bytes, applied as `mem[i] ^= key[i % 11]` over
the STRINGS REGION ONLY (global.cpp:311-316, CRYPT_KEY_SIERRA at agi.h:92). Not the offsets,
not the header, not the bytecode. And ScummVM skips it entirely when the resource was
LZW-compressed -- irrelevant here because v3 is out of scope, but the reason is recorded so a
later v3 decoder does not have to rediscover it.
"""

CRYPT_KEY_SIERRA = b"Avis Durgan"
CRYPT_KEY_AGDS = b"Alex Simkin"


def decrypt(data, key=CRYPT_KEY_SIERRA):
    """XOR-decrypt in the oracle's exact form: mem[i] ^= key[i % len(key)]."""
    k = len(key)
    return bytes(b ^ key[i % k] for i, b in enumerate(data))


class LogicError(Exception):
    pass


class Logic:
    __slots__ = ("index", "bytecode", "messages", "raw_len", "message_count")

    def __init__(self, index, bytecode, messages, raw_len):
        self.index = index
        self.bytecode = bytecode
        self.messages = messages          # list[bytes]; ★ bytes, not str -- see decode_messages
        self.raw_len = raw_len
        self.message_count = len(messages)


def split(data, index=-1, key=CRYPT_KEY_SIERRA, decrypt_strings=True):
    """Split a raw LOGIC resource into bytecode and messages.

    ★ Every bound is checked and violations RAISE. A LOGIC whose declared bytecode size runs
    past the resource is a parser or extraction error, and silently clamping it would convert
    that into a subtly wrong disassembly later -- the failure mode §2O.1's oracle diff exists
    to catch, arriving one layer too late to be cheap.
    """
    n = len(data)
    if n < 2:
        raise LogicError("LOGIC %d: %d bytes, too short for a size field" % (index, n))

    bytecode_size = data[0] | (data[1] << 8)
    msg_pos = 2 + bytecode_size
    if msg_pos > n:
        raise LogicError("LOGIC %d: bytecode size %d runs past resource (%d bytes)"
                         % (index, bytecode_size, n))
    bytecode = data[2:msg_pos]

    # ★ A LOGIC may legitimately end exactly at the message section with no message data.
    if msg_pos == n:
        return Logic(index, bytecode, [], n)

    if msg_pos + 3 > n:
        raise LogicError("LOGIC %d: message header truncated at %d (%d bytes)"
                         % (index, msg_pos, n))

    count = data[msg_pos]
    messages_size = data[msg_pos + 1] | (data[msg_pos + 2] << 8)
    offsets_pos = msg_pos + 3
    strings_pos = offsets_pos + 2 * count
    strings_size = messages_size - 2 - 2 * count

    if count == 0:
        return Logic(index, bytecode, [], n)
    if strings_pos > n:
        raise LogicError("LOGIC %d: %d message offsets run past resource"
                         % (index, count))
    if strings_size < 0:
        raise LogicError("LOGIC %d: messages_size %d too small for %d offsets"
                         % (index, messages_size, count))

    end = min(strings_pos + strings_size, n)
    body = bytearray(data)
    if decrypt_strings:
        body[strings_pos:end] = decrypt(bytes(body[strings_pos:end]), key)

    messages = []
    for i in range(count):
        o = offsets_pos + i * 2
        rel = body[o] | (body[o + 1] << 8)
        if rel == 0:
            messages.append(b"")          # ScummVM maps a zero offset to the empty string
            continue
        start = msg_pos + 1 + rel         # ★ the +1, see the module docstring
        if start >= n:
            messages.append(b"")
            continue
        stop = body.find(0, start)
        if stop == -1:
            stop = n
        messages.append(bytes(body[start:stop]))

    return Logic(index, bytecode, messages, n)


def message_digest(messages):
    """A stable digest of a LOGIC's messages, for reporting WITHOUT printing game text.

    ★★ AC-6 requires message recovery to be evidenced without quoting any of it: the text is
    Sierra's, and §2P's reasoning about game data covers what the data SAYS as much as the bytes
    themselves. A digest proves the decode ran and is reproducible; it reveals nothing.
    """
    import hashlib
    h = hashlib.sha256()
    for m in messages:
        h.update(len(m).to_bytes(4, "little"))
        h.update(m)
    return h.hexdigest()


def looks_like_text(messages, min_ratio=0.80):
    """Heuristic sanity check: are the decoded bytes mostly printable ASCII?

    ★ L-23 -- this check CAN fail, and that is the point. Run it on a LOGIC decoded WITHOUT the
    XOR and it drops far below the threshold, because XORing English text with "Avis Durgan"
    yields bytes that are mostly non-printable. So a passing score is evidence the key was
    applied and applied correctly, not merely that some bytes were produced. The report states
    the failing case alongside the passing one for exactly that reason.
    """
    total = printable = 0
    for m in messages:
        for b in m:
            total += 1
            if 32 <= b < 127 or b in (9, 10, 13):
                printable += 1
    if total == 0:
        return True, 1.0
    ratio = printable / total
    return ratio >= min_ratio, ratio
