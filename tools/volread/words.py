#!/usr/bin/env python3
"""words.py -- WORDS.TOK: the parser vocabulary.

★ FROM THE ORACLE (ScummVM 9d9b9e93, engines/agi/words.cpp loadDictionary):

    u16[26]  offsets, BIG-endian, one per initial letter a..z; 0 means "no words"
    then, at each offset, a run of entries:
        u8       prefix length shared with the PREVIOUS word
        u8[]     remaining characters, each stored as (c ^ 0x7F) & 0x7F,
                 the LAST of which has bit 7 set in its stored form
        u16      word id, BIG-endian
    a prefix length of 0 ends the letter's run

★★ TWO DETAILS THAT ARE EASY TO GET WRONG AND SILENT WHEN WRONG:
  1. **The offsets are BIG-endian** while almost everything else in AGI is little-endian. A
     little-endian read yields a large offset that usually lands outside the file, so this one
     at least fails loudly -- unlike (2).
  2. **The prefix compression is incremental against the previous word**, so a single mis-read
     length silently corrupts every subsequent word in that letter's run rather than just one.
     There is no checksum and no terminator to resynchronise on.

★ The character transform `(c ^ 0x7F) & 0x7F` is its own obfuscation, unrelated to the
`Avis Durgan` XOR used for LOGIC messages and OBJECT. Two different schemes in one game's data,
which is the sort of thing worth stating plainly so nobody "unifies" them.

★ ScummVM carries a WORKAROUND here for the fan game SQ0, whose words beginning with digits are
filed under 'a' (bug #6415). It skips entries whose first character does not match the letter
bucket. **We RECORD such entries rather than skipping them** -- our job is to report what the
data contains, not to make a game playable -- and the count is surfaced so the divergence from
the oracle is visible rather than buried. §2.1: that skip is a ScummVM normalisation, not
something AGI did.
"""

NUM_LETTERS = 26


class WordsError(Exception):
    pass


class Dictionary:
    __slots__ = ("words", "off_bucket", "raw_len")

    def __init__(self, words, off_bucket, raw_len):
        self.words = words              # list[(word_bytes, word_id, letter_index)]
        self.off_bucket = off_bucket    # entries whose first char != its bucket letter
        self.raw_len = raw_len

    def __len__(self):
        return len(self.words)

    def ids(self):
        return {w[1] for w in self.words}


def parse(data):
    n = len(data)
    if n < NUM_LETTERS * 2:
        raise WordsError("WORDS.TOK: %d bytes, too short for the 26 offsets" % n)

    words = []
    off_bucket = 0

    for letter in range(NUM_LETTERS):
        off = (data[letter * 2] << 8) | data[letter * 2 + 1]     # ★ BIG-endian
        if off == 0:
            continue
        if off >= n:
            raise WordsError("WORDS.TOK: letter %d offset %d past end (%d)" % (letter, off, n))

        pos = off
        prev = b""
        while pos < n:
            prefix = data[pos]
            pos += 1
            if prefix == 0 and words and prev and prev[0:1] and prev[0] >= (ord('a') + letter):
                # run for this letter has ended (oracle: k == 0 && str[0] >= 'a' + i)
                break
            if prefix > len(prev):
                # incremental prefix longer than the previous word: unrecoverable desync
                raise WordsError("WORDS.TOK: letter %d prefix %d exceeds previous word (%d)"
                                 % (letter, prefix, len(prev)))
            chars = bytearray(prev[:prefix])
            while pos < n:
                c = data[pos]
                pos += 1
                chars.append((c ^ 0x7F) & 0x7F)
                if c & 0x80:
                    break
            if pos + 1 >= n:
                break
            word_id = (data[pos] << 8) | data[pos + 1]           # ★ BIG-endian
            pos += 2
            w = bytes(chars)
            if not w:
                break
            if w[0] != (ord('a') + letter):
                off_bucket += 1
            words.append((w, word_id, letter))
            prev = w
            if pos >= n:
                break

    return Dictionary(words, off_bucket, n)


def digest(d):
    """Stable digest -- counts evidenced without printing vocabulary (§2P)."""
    import hashlib
    h = hashlib.sha256()
    for w, wid, _ in d.words:
        h.update(len(w).to_bytes(2, "little"))
        h.update(w)
        h.update(wid.to_bytes(2, "little"))
    return h.hexdigest()


def looks_like_words(d, min_ratio=0.95):
    """Are the recovered words lower-case ASCII? ★ Can fail: skip the ^0x7F transform and this
    collapses, so a pass is evidence the transform ran, not merely that bytes appeared."""
    total = ok = 0
    for w, _, _ in d.words:
        for b in w:
            total += 1
            if 97 <= b <= 122 or 48 <= b <= 57 or b in (32, 39, 45):
                ok += 1
    if total == 0:
        return True, 1.0
    r = ok / total
    return r >= min_ratio, r
