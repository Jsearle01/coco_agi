#!/usr/bin/env python3
"""harness/tools/said_gate.py -- the parser gate: our said() against the oracle's. [T-P0-058 AC-3]

★★★★★ WHAT IS COMPARED. For each case -- a real operand pattern from the shipped bytecode plus an
input line -- both sides run parseUsingDictionary() then testSaid() and report the ego word IDs
and the match result. The diff is per case, so the first divergent line names the pattern, the
input and which half disagreed [L-10: per-case verdicts, never a total alone].

★★★★ THE OPERAND PATTERNS ARE NOT INVENTED. said_census.py walks every LOGIC's bytecode and
extracts every real call site; this gates against those, in the game's own proportions. A matcher
tested on operand patterns nobody wrote would prove nothing about the game.

★★★ THE INPUTS ARE GENERATED FROM THE VOCABULARY, and four shapes per pattern, because the
semantics that are easy to get wrong are all about what happens at the ENDS:
    exact     one word per operand              -> should match
    wrong     one operand's word replaced       -> should not, unless that operand is 1 or 9999
    extra     a trailing word the pattern lacks -> should not, unless the pattern ends 9999
    empty     nothing typed                     -> should not (ENTERED_CLI is false)
★★ 9999 is "rest of line INCLUDING nothing" and 1 is "any single word", so those two shapes are
exactly where a plausible-looking matcher diverges.

★ §2P: generated input text is written to a local case file for the oracle to read and is never
printed. Word NUMBERS and counts only in the output.

usage:
  python harness/tools/said_gate.py <game-dir> <said.json> <workdir> --emit
  ... run the oracle in <workdir> ...
  python harness/tools/said_gate.py <game-dir> <said.json> <workdir> --check
"""
import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / "tools"))
sys.path.insert(0, str(ROOT.parent / "tools" / "volread"))

import words as words_mod                          # noqa: E402
from agivm import parser as ap                     # noqa: E402


def build(game_dir, said_json, limit):
    wt = pathlib.Path(game_dir) / "WORDS.TOK"
    d = words_mod.parse(wt.read_bytes())
    vocab = ap.Vocabulary(d.words)

    # id -> a representative spelling. First in bucket order, which is deterministic.
    rep = {}
    for w, wid, _l in d.words:
        if wid not in (0,) and wid not in rep:
            rep[wid] = w.decode("latin-1")
    # a filler for operand 1 ("any word") and for the "wrong"/"extra" shapes
    filler = rep[sorted(rep)[0]] if rep else "x"
    other = rep[sorted(rep)[1]] if len(rep) > 1 else filler

    sites = json.loads(pathlib.Path(said_json).read_text(encoding="utf-8"))
    seen, patterns = set(), []
    for s in sites:
        t = tuple(s["operands"])
        if t and t not in seen:
            seen.add(t)
            patterns.append(t)
    patterns = patterns[:limit]

    cases = []
    for pat in patterns:
        # words for the operands we can express; 9999 contributes nothing
        base = []
        expressible = True
        for o in pat:
            if o == 9999:
                continue
            if o == 1:
                base.append(filler)
            elif o in rep:
                base.append(rep[o])
            else:
                expressible = False
                break
        if not expressible:
            continue
        exact = " ".join(base)
        cases.append((pat, exact))
        if base:
            wrong = " ".join([other if i == 0 else w for i, w in enumerate(base)])
            cases.append((pat, wrong))
        cases.append((pat, (exact + " " + other).strip()))
        cases.append((pat, ""))
    return vocab, cases


def build_tokenise(game_dir, limit):
    """AC-4: gate the TOKENISER on its own, independent of said().

    ★★★★★ WHY SEPARATELY. P6.2 §7.3 flagged it: the tokeniser was gated only THROUGH said()'s
    results, and **a tokenise defect that produces the same IDs by a different route would pass**.
    That is L-38's shape -- two things matching for different reasons. Here the comparison is the
    ego word ID LIST itself, with said() reduced to a constant: every case uses the operand
    pattern (1,), so the match result carries no information and cannot mask a tokenise defect.

    ★★★★ THE INPUTS TARGET cleanUpInput() AND findWordInDictionary(), not said():
      * separators   ,.?!();:[]{}  -> become spaces        [words.cpp:184]
      * invalid      ' ` - \\ "     -> DELETED, not separated [words.cpp:205]
      * "a" / "i" alone             -> IGNORE, occupy no slot [words.cpp:264]
      * an unknown word             -> recorded, then parsing STOPS [words.cpp:374]
      * multi-word dictionary entries and prefix collisions -> the LAST full match in bucket
        order wins, which is the rule a "longest match" rewrite would get wrong
      * case, leading/trailing/multiple spaces, empty input
    ★★ The vocabulary supplies the words, so the cases are the title's own, not invented text.
    """
    wt = pathlib.Path(game_dir) / "WORDS.TOK"
    d = words_mod.parse(wt.read_bytes())
    vocab = ap.Vocabulary(d.words)

    # words grouped so the generated inputs are real vocabulary, never invented text
    plain, multi, ignorable = [], [], []
    for w, wid, _l in d.words:
        s = w.decode("latin-1")
        if wid == 0:
            ignorable.append(s)
        elif " " in s:
            multi.append(s)
        else:
            plain.append(s)

    inputs = []
    inputs.append("")                                    # empty -> no words, ENTERED_CLI false
    inputs.append("   ")                                 # spaces only
    for s in plain[:limit]:
        inputs.append(s)                                 # one word
        inputs.append(s.upper())                         # case folding
        inputs.append("  " + s + "  ")                   # leading/trailing space
        inputs.append(s + ",")                           # trailing separator
        inputs.append(s + "'s")                          # apostrophe is DELETED, not a break
        inputs.append("a " + s)                          # "a" ignored
        inputs.append("i " + s)                          # "i" ignored
        inputs.append("zzqq " + s)                       # unknown FIRST -> parsing stops
        inputs.append(s + " zzqq")                       # unknown SECOND -> recorded, stops
    for s in plain[:limit]:
        for t in plain[:6]:
            inputs.append(s + " " + t)                   # pairs, incl. prefix collisions
    for s in multi[:limit]:
        inputs.append(s)                                 # a multi-word dictionary entry
        inputs.append(s + " " + (plain[0] if plain else "x"))
    for s in ignorable[:40]:
        inputs.append(s)                                 # id 0 -> occupies no slot at all
        inputs.append(s + " " + (plain[0] if plain else "x"))
    # ★★★★★ CAPPED AT 19 WORDS, AND THE CAP IS A MEASUREMENT. The first version generated
    # 25-word inputs to probe past MAX_WORDS (20). **The oracle SEGFAULTS** -- exit 139, twice,
    # reproducibly. words.cpp:367 writes `_egoWords[wordCount].id` with no bound check and
    # agi.h:81 sizes that array at 20, so a 21st word writes off the end.
    # ★★★★ P6.2 §7.4 recorded this as "the oracle's behaviour there is undefined; ours stops".
    # It is stronger than that: **there is no reference behaviour because the reference dies.**
    # T-P0-059 §1 declined gating it on the grounds that there is nothing to gate against --
    # correct, and now evidenced rather than inferred.
    # ★★ So the gate stays inside the array. Our implementation stopping at 20 is the safer
    # divergence and is recorded, not gated.
    for s in plain[:20]:
        inputs.append((s + " ") * 19)                    # 19 words: inside MAX_WORDS = 20

    # ★ said() is held constant at (1,) so this gate reports the TOKENISER and nothing else.
    seen, cases = set(), []
    for text in inputs:
        if text in seen:
            continue
        seen.add(text)
        cases.append(((1,), text))
    return vocab, cases


def build_synonyms(game_dir):
    """AC-8: one synonym class, EVERY spelling, end to end.

    ★★★★ THE CLASS IS THE POINT OF THE VOCABULARY. `get`, `take` and `grab` share a word number,
    and that sharing is why AGI feels forgiving. A class mapped wrongly makes one phrasing work
    and another fail -- which is invisible to a matcher test that only ever types one spelling.
    ★★ So: take the LARGEST class, type each of its spellings on its own, and require that every
    one tokenises to the same word number and matches said(<that number>).
    """
    wt = pathlib.Path(game_dir) / "WORDS.TOK"
    d = words_mod.parse(wt.read_bytes())
    vocab = ap.Vocabulary(d.words)
    by_id = {}
    for w, wid, _l in d.words:
        if wid != 0:
            by_id.setdefault(wid, []).append(w.decode("latin-1"))
    wid, spellings = max(by_id.items(), key=lambda kv: len(kv[1]))
    cases = [((wid,), s) for s in spellings]
    return vocab, cases, wid, len(spellings)


def emit(cases, workdir, limit=None):
    out = []
    for pat, text in cases:
        out.append("%s\t%s" % (",".join(str(x) for x in pat), text))
    p = pathlib.Path(workdir) / "oracle_parser_cases.txt"
    p.write_text("\n".join(out) + "\n", encoding="ascii")
    # ═══════════════════════════════════════════════════════════════════════════════════════
    # ★★★★★ RECORD THE LIMIT, BECAUSE IT DEFINES THE CORPUS AND LIVED ONLY ON A COMMAND LINE.
    # --check REGENERATES the cases rather than reading the file the oracle consumed, so its
    # --limit must match the --emit run's or it compares a different corpus. T-P0-059's widened
    # tokeniser run used --limit 1000; T-P0-060 came to check it and the default 400 produced
    # 6,210 cases against the oracle's 12,435 on Kingquest3.
    # ★★★★ THE COUNT CHECK CAUGHT IT AND SAID SO -- "case count 6210 vs oracle 12435" -- which
    # is the instrument behaving correctly: it refused rather than diffing the wrong corpus.
    # **The defect is not that it failed, it is that the number needed to make it pass existed
    # nowhere on disk** and had to be recovered by bisection. Same class as the VM gate's nine
    # titles living in an environment variable: the SCOPE of a gate is part of its definition.
    # ★★ Written beside the cases, so the corpus and the parameter that produced it travel
    # together and a workdir is self-describing.
    if limit is not None:
        (pathlib.Path(workdir) / "cases.limit").write_text("%d\n" % limit, encoding="ascii")
    return p, len(cases)


def emitted_limit(workdir, fallback):
    """The --limit that produced this workdir's cases, if it was recorded."""
    p = pathlib.Path(workdir) / "cases.limit"
    if p.exists():
        try:
            return int(p.read_text(encoding="ascii").strip())
        except ValueError:
            pass
    return fallback


def ours(vocab, cases):
    res = []
    for pat, text in cases:
        ego, _nf, cli = ap.parse_using_dictionary(text, vocab)
        # ★ Each case starts from a fresh keystroke: parse_using_dictionary clears the
        # accepted-input flag, so said()'s match-consumes-input side effect cannot leak.
        ok, _acc = ap.test_said(list(pat), ego, False, cli)
        res.append((ego, ok))
    return res


def read_oracle(workdir, path=""):
    """★★ Same record format either side, deliberately: "<n> ego=a,b,c -> r".

    The 6809 probe writes it too [parser_gate.lua], so AC-7's port diff reuses this reader and
    the same ours() -- **one comparison, two references**. A second reader would be a second
    thing to get right, and the two sides could then differ in the reader rather than the parser.
    """
    p = pathlib.Path(path) if path else pathlib.Path(workdir) / "oracle_parser_results.txt"
    out = []
    for line in p.read_text(encoding="ascii", errors="replace").splitlines():
        if not line.strip():
            continue
        # "<n> ego=a,b,c -> r"
        _n, rest = line.split(" ", 1)
        egopart, rpart = rest.split(" -> ")
        ids = egopart[4:]
        ego = [int(x) for x in ids.split(",")] if ids else []
        out.append((ego, rpart.strip() == "1"))
    return out


def main():
    a_ = argparse.ArgumentParser()
    a_.add_argument("game_dir")
    a_.add_argument("said_json")
    a_.add_argument("workdir")
    a_.add_argument("--emit", action="store_true")
    a_.add_argument("--check", action="store_true")
    a_.add_argument("--limit", type=int, default=400)
    a_.add_argument("--results", default="",
                    help="AC-7: diff against this results file instead of the oracle's")
    a_.add_argument("--tokenise", action="store_true",
                    help="AC-4: gate the tokeniser alone, said() held constant")
    a_.add_argument("--fault-tokenise", action="store_true",
                    help="AC-5: inject the tokeniser fault")
    a_.add_argument("--synonyms", action="store_true",
                    help="AC-8: gate the largest synonym class, every spelling")
    a_.add_argument("--fault", action="store_true",
                    help="AC-4: inject the any-word fault and show the gate catches it")
    a = a_.parse_args()

    if a.fault:
        ap.FAULT_ANY_WORD = True
        print("★★★ FAULT INJECTED: operand 1 no longer means 'any word'")
    if a.fault_tokenise:
        ap.FAULT_LONGEST_MATCH = True
        print("★★★ FAULT INJECTED: findWordInDictionary keeps the FIRST match, not the last")

    if a.tokenise:
        # ★★★ ON --check, THE LIMIT COMES FROM THE WORKDIR IF IT WAS RECORDED. The corpus is
        # defined by the emit run, not by whatever the checker was invoked with; an explicit
        # --limit on the command line still wins, so a deliberate re-scope is still possible.
        lim = a.limit if a.emit or a.limit != 400 else emitted_limit(a.workdir, a.limit)
        if lim != a.limit:
            print("limit             : %d, from %s/cases.limit (the emit run's)" % (lim, a.workdir))
        vocab, cases = build_tokenise(a.game_dir, lim)
        if a.emit:
            p, n = emit(cases, a.workdir, lim)
            print("wrote %s  (AC-4: %d tokeniser cases, limit %d)" % (p, n, lim))
            return 0
        mine = ours(vocab, cases)
        theirs = read_oracle(a.workdir, a.results)
        if len(mine) != len(theirs):
            print("★★★ case count %d vs oracle %d" % (len(mine), len(theirs)))
            return 1
        bad = [i for i, ((e1, _r1), (e2, _r2)) in enumerate(zip(mine, theirs)) if e1 != e2]
        nonempty = sum(1 for e, _r in theirs if e)
        print("tokeniser cases   : %d" % len(mine))
        print("  produced words  : %d cases tokenised to at least one word" % nonempty)
        print("  ego-list differs: %d" % len(bad))
        if bad:
            i = bad[0]
            print("★★★ first divergence at case %d: ours=%s oracle=%s"
                  % (i, mine[i][0], theirs[i][0]))
            return 1
        print("★ %d of %d identical on the tokenised word list" % (len(mine), len(mine)))
        return 0

    if a.synonyms:
        vocab, cases, wid, nsp = build_synonyms(a.game_dir)
        if a.emit:
            p, n = emit(cases, a.workdir)
            print("wrote %s  (AC-8: word id %d, %d spellings)" % (p, wid, nsp))
            return 0
        mine = ours(vocab, cases)
        theirs = read_oracle(a.workdir, a.results)
        if len(mine) != len(theirs):
            print("★★★ case count %d vs oracle %d" % (len(mine), len(theirs)))
            return 1
        bad = [i for i, (m, t) in enumerate(zip(mine, theirs)) if m != t]
        same_id = all(e == [wid] for e, _r in theirs)
        allmatch = all(r for _e, r in theirs)
        print("AC-8 synonym class: word id %d, %d spellings" % (wid, nsp))
        print("  every spelling tokenises to that one number : %s" % ("YES" if same_id else "NO"))
        print("  every spelling matches said(%d)              : %s"
              % (wid, "YES" if allmatch else "NO"))
        print("  ours vs oracle differences                  : %d" % len(bad))
        return 0 if (not bad and same_id and allmatch) else 1

    vocab, cases = build(a.game_dir, a.said_json, a.limit)
    if a.emit:
        p, n = emit(cases, a.workdir)
        print("wrote %s  (%d cases from %d distinct patterns)"
              % (p, n, len({c[0] for c in cases})))
        return 0

    mine = ours(vocab, cases)
    theirs = read_oracle(a.workdir, a.results)
    # ★★★★ NAME THE SIDE THAT IS ACTUALLY LOADED. --results swaps the right-hand reference from
    # ScummVM's dump to the 6809 probe's, and the output went on printing "oracle" either way --
    # so AC-7's runs read as a comparison against ScummVM that they were not. **A label is a
    # claim about provenance**, and this one was wrong on every port run this task made.
    other = "6809" if a.results else "oracle"
    if len(mine) != len(theirs):
        print("★★★ case count %d vs %s %d -- the %s did not run every case"
              % (len(mine), other, len(theirs), other))
        return 1

    bad_ego = bad_res = 0
    first = None
    for i, ((e1, r1), (e2, r2)) in enumerate(zip(mine, theirs)):
        if e1 != e2:
            bad_ego += 1
            if first is None:
                first = (i, "tokenise", cases[i][0], e1, e2, r1, r2)
        elif r1 != r2:
            bad_res += 1
            if first is None:
                first = (i, "match", cases[i][0], e1, e2, r1, r2)

    total = len(mine)
    matched = sum(1 for _e, r in theirs if r)
    print("cases            : %d   (%d distinct operand patterns)"
          % (total, len({c[0] for c in cases})))
    print("%-6s matched   : %d of %d" % (other, matched, total))
    print("tokenise differs : %d" % bad_ego)
    print("match differs    : %d" % bad_res)
    if first:
        i, kind, pat, e1, e2, r1, r2 = first
        print("★★★ first divergence at case %d (%s): operands=%s python ego=%s->%s "
              "%s ego=%s->%s" % (i, kind, list(pat), e1, r1, other, e2, r2))
        return 1
    print("★ %d of %d identical on BOTH the tokenised words and the match result" % (total, total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
