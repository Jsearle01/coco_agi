#!/usr/bin/env python3
"""tools/agivm/parser.py -- AGI's parser: tokenise input, match said(). [T-P0-058]

★★★★★ FROM THE ORACLE, NOT THE SPECS [L-25]. Every rule below is transcribed from the pin
(ScummVM 9d9b9e93) with the file:line beside it, because the Specs and the oracle differ here and
§2 ranks the oracle above them:

    words.cpp:218  cleanUpInput()          separators, invalid chars, the trailing space
    words.cpp:250  findWordInDictionary()  bucket scan, LAST full match wins, a/i ignore
    words.cpp:326  parseUsingDictionary()  the loop, unknown-word stop, the two flags
    op_test.cpp:318 testSaid()             the guards, 9999, 1, and the two tail conditions
    op_test.cpp:469 skipInstruction()      said's operand count comes FROM THE STREAM

═══════════════════════════════════════════════════════════════════════════════════════════════
★★★★★ THE SHAPES THIS COMMITS TO, AND WHAT EACH BECOMES ON THE 6809 [Jay, T-P0-058 note].
Python can express what AGI DOES and not what the CoCo3 COSTS, and three of this project's
lessons came from exactly that gap [L-66, L-67, AD-88]. So each structure is named here with its
target form, and none of them is a Python convenience:

  THE VOCABULARY -- a list of (bytes, id) per letter bucket, IN FILE ORDER.
      6809: **the resource itself, in place, under one window.** No copy and no index is built,
      because WORDS.TOK already IS an index: 26 big-endian head offsets, then alphabetically
      sorted prefix-compressed runs. ★★★★ A Python dict {word: id} would be the obvious choice
      and is doubly wrong -- it is unportable AND it loses "last full match in bucket order
      wins", which is the oracle's actual rule.
      ★★★ RESIDENCY, MEASURED NOT ASSUMED [the note's question]: the largest WORDS.TOK in the
      corpus is SpaceQuest-2 at 6,828 bytes; KQ1 3,144, KQ3 5,657, larry1 6,597, PQ1 6,737.
      **All twelve are under 8,192**, so unlike AD-78's arena -- where the largest LOGIC exceeded
      a window and forced a two-slot design -- the vocabulary needs ONE slot. Stated as a
      measurement so the port does not re-derive it.

  THE TOKENISED RESULT -- a fixed-length list of word NUMBERS, bounded at MAX_WORDS = 20
      [agi.h:81], with a separate count. **No strings are retained.**
      6809: a 40-byte array (20 x u16) plus a count byte, in the status block. said() only ever
      compares numbers, so the text has no consumer on the target.
      ★★ The oracle also keeps each word's TEXT for VM_VAR_WORD_NOT_FOUND display; that is a
      text-rendering concern and is out of scope here (§12), so this keeps the count only.

  THE said() OPERANDS -- read from the instruction stream, N then N x u16.
      6809: read in place from the LOGIC in its window. Already bounded by N, no allocation.

  THE MATCH ITSELF -- integer comparisons in a loop over at most min(N, 20) entries.
      6809: the same loop. This is the one piece with no Python-vs-target gap at all.
═══════════════════════════════════════════════════════════════════════════════════════════════

★ §2P: this module handles vocabulary bytes because matching requires them. It prints nothing.
"""

MAX_WORDS = 20                      # agi.h:81
DICT_UNKNOWN = -1                   # words.h:27
DICT_IGNORE = 0                     # words.h:28

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ AC-4's INJECTED FAULT. A gate that has only ever reported PASS has not been shown to be a
# gate [L-62], and a fault proven elsewhere does not transfer -- it has to fail on THIS corpus.
#
# ★★★★ FAULT_ANY_WORD drops the `z == 1` case, so operand 1 stops meaning "any single word" and is
# compared as a literal word number instead. **That is a defect a careful reader would plausibly
# write**: 1 looks like a word id, there is nothing in the operand stream that marks it as
# special, and every pattern without a 1 in it still behaves perfectly. KQ1 has 103 such sites,
# larry1 132, PoliceQuest1 187 -- a minority, which is exactly why a gate could miss it.
# ★★ Off by default and set only by harness/tools/said_gate.py --fault.
FAULT_ANY_WORD = False

# words.cpp:184 isCharSeparator
SEPARATORS = set(" ,.?!();:[]{}")
# words.cpp:205 isCharInvalid
INVALID = set("'`-\\\"")


def clean_up_input(raw):
    """words.cpp:218. Drop invalid chars, collapse separators to single spaces, no trailing one.

    ★★ Transcribed rather than reimplemented: the loop's shape decides what "a  b" and "a-b"
    become, and a tidier rewrite gets those wrong in ways no small test would show.
    """
    out = []
    i, n = 0, len(raw)
    while i < n:
        c = raw[i]
        if c in SEPARATORS or c in INVALID:
            i += 1
            continue
        while i < n:
            c = raw[i]
            if c not in INVALID:
                out.append(c)
            i += 1
            if i < n and raw[i] in SEPARATORS:
                out.append(" ")
                break
            if i >= n:
                break
    s = "".join(out)
    if s.endswith(" "):
        s = s[:-1]
    return s


class Vocabulary:
    """The dictionary, bucketed by first letter, IN FILE ORDER (see the header)."""

    __slots__ = ("buckets",)

    def __init__(self, entries):
        # entries: list[(word_bytes, word_id, letter_index)] straight from volread/words.py
        self.buckets = [[] for _ in range(26)]
        for w, wid, letter in entries:
            self.buckets[letter].append((w.decode("latin-1"), wid))

    def find(self, lower, pos):
        """words.cpp:250 findWordInDictionary. Returns (word_id, found_len).

        ★★★★ THE RULE IS "LAST FULL MATCH IN BUCKET ORDER", not "longest". It scans the whole
        bucket and overwrites the candidate on every full match, breaking early ONLY on a perfect
        match (the dictionary word consumes all remaining input). Because WORDS.TOK is
        alphabetically sorted, later usually means longer -- but "usually" is not the rule, and a
        max()-by-length rewrite would differ wherever it is not.
        """
        n = len(lower)
        left = n - pos
        start = pos
        word_id = DICT_UNKNOWN
        found_len = 0
        first = lower[pos] if pos < n else ""

        if "a" <= first <= "z":
            # words.cpp:262 -- a single-char "a" or "i" followed by a space is IGNORED
            if pos + 1 < n and lower[pos + 1] == " " and first in ("a", "i"):
                word_id = DICT_IGNORE

            for word, wid in self.buckets[ord(first) - 97]:
                wlen = len(word)
                if wlen > left:
                    continue
                if lower[start:start + wlen] != word:
                    continue
                end = start + wlen
                if end >= n or lower[end] == " ":
                    word_id = wid
                    found_len = wlen
                    if left == found_len:
                        break

        if found_len == 0:
            # no dictionary hit: skip to the next space
            p = start
            while p < n and lower[p] != " ":
                p += 1
            found_len = p - start
        return word_id, found_len


def parse_using_dictionary(raw, vocab):
    """words.cpp:326. Returns (ego_word_ids, word_not_found_index, entered_cli).

    ★★★ THREE BEHAVIOURS THAT ARE EASY TO MISS AND ARE ALL LOAD-BEARING:
      1. An IGNORE result (id 0) is not recorded at all -- it does not occupy a word slot.
      2. An UNKNOWN word IS recorded (with id 0), sets VM_VAR_WORD_NOT_FOUND to its 1-based
         index, and **STOPS parsing** -- the rest of the line is never looked at.
      3. ENTERED_CLI is set from the word COUNT, and SAID_ACCEPTED_INPUT is always cleared here.
         Those two flags are testSaid()'s entire guard, so they belong to this function.
    """
    clean = clean_up_input(raw)
    lower = clean.lower()

    ego = []
    word_not_found = 0
    pos, n = 0, len(clean)
    while pos < n:
        if clean[pos] == " ":
            pos += 1
        wid, wlen = vocab.find(lower, pos)
        if wid != DICT_IGNORE:
            ego.append(0 if wid == DICT_UNKNOWN else wid)
            if len(ego) >= MAX_WORDS:
                # ★ agi.h:81 bounds the array; the oracle writes _egoWords[wordCount] without a
                # bound check, so exceeding it is undefined there. We stop, and say so.
                break
            if wid == DICT_UNKNOWN:
                word_not_found = len(ego)
                break
        pos += wlen
    return ego, word_not_found, len(ego) > 0


def test_said(operands, ego, accepted_input, entered_cli):
    """op_test.cpp:318 testSaid. Returns (result, new_accepted_input).

    ★★★★★ said() HAS A SIDE EFFECT AND IT IS THE MATCH-PRECEDENCE RULE. On success it sets
    VM_FLAG_SAID_ACCEPTED_INPUT, and the guard rejects every later call while that flag is set --
    so **the FIRST said() to match consumes the input** and no other said() in the same cycle can
    fire. Getting this wrong gives a game that responds to the wrong sentence, which passes every
    byte gate and shows up as a puzzle that will not solve.

    ★★★ 9999 is "rest of line": it matches everything remaining, INCLUDING nothing.
    ★★ 1 is "any single word".
    """
    if accepted_input or not entered_cli:
        return False, accepted_input

    nwords = len(operands)
    n = len(ego)
    z = 0
    c = 0
    idx = 0
    while nwords and n:
        z = operands[idx]
        idx += 1
        if z == 9999:
            nwords = 1              # then decremented below -> loop ends
        elif z == 1 and not FAULT_ANY_WORD:
            pass
        else:
            if ego[c] != z:
                return False, accepted_input
        c += 1
        nwords -= 1
        n -= 1

    # op_test.cpp:363 -- the input should be entirely consumed, or the last operand was 9999
    if n and z != 9999:
        return False, accepted_input
    # op_test.cpp:368 -- operands left over are only allowed if the next one is 9999
    if nwords != 0 and (idx >= len(operands) or operands[idx] != 9999):
        return False, accepted_input

    return True, True


def said_operand_count(code, ip):
    """op_test.cpp:469 skipInstruction. said (test 0x0E, v>=0x2000): ip += code[ip]*2 + 1.

    ★★★★ THE TRAP optable.py:19 RECORDS. `said`'s parameter string is EMPTY and the instruction
    is NOT zero-length: N comes from the stream. A table-driven skip that trusts the empty string
    desynchronises everything after it, and the damage presents as a VM defect rather than a
    parser one [L-28].
    """
    n = code[ip]
    return n, 1 + n * 2
