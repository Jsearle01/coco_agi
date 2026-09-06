#!/usr/bin/env python3
"""harness/tools/words_census.py -- WORDS.TOK per title: size, synonym classes, ignorables.

★★★★ WHAT THIS IS FOR [T-P0-058 AC-2]. `said()` matches WORD NUMBERS, not text, and several
spellings share a number -- that sharing IS the synonym class and it is why AGI feels forgiving.
Before any matcher is written, the vocabulary it matches against has to be counted per title and
per class, or a matching failure and a vocabulary failure look identical.

★★★★★ ONE DIVERGENCE FROM THE ORACLE IS KNOWN, DOCUMENTED, AND MEASURED HERE RATHER THAN
ASSUMED AWAY. ScummVM's Words::loadDictionary SKIPS an entry whose first character does not equal
its bucket letter [words.cpp:109-117, the SQ0 fan-game workaround, bug #6415]; `words.py` RECORDS
it and counts it as `off_bucket`. ★★★ Per §2.1 that skip is a ScummVM NORMALISATION, not
something AGI did -- so the two vocabularies differ by exactly `off_bucket` entries, and a gate
that does not know the number cannot tell that difference from a parse defect.

★★ §2P: counts, class sizes, digests and word NUMBERS only. **No vocabulary text is printed.**
The digest is over (len, bytes, id) triples so it is sensitive to the words without exposing them.

usage: python harness/tools/words_census.py <dir-of-title-dirs> [--only Kingquest1,larry1]
"""
import argparse
import collections
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1].parent / "tools" / "volread"))
import words as words_mod  # noqa: E402


def census(path):
    d = words_mod.parse(pathlib.Path(path).read_bytes())
    by_id = collections.Counter(wid for _w, wid, _l in d.words)
    ignorable = by_id.get(0, 0)
    # ★ A "synonym class" is a word id shared by 2+ spellings. id 0 is the IGNORE class and is
    # counted separately -- it is not a synonym group, it is the words the tokeniser drops.
    classes = {i: c for i, c in by_id.items() if i != 0}
    multi = {i: c for i, c in classes.items() if c > 1}
    ok, ratio = words_mod.looks_like_words(d)
    return {
        "entries": len(d.words),
        "ids": len(classes),
        "ignorable": ignorable,
        "synonym_classes": len(multi),
        "largest_class": max(multi.values()) if multi else 0,
        "off_bucket": d.off_bucket,
        "bytes": d.raw_len,
        "ascii_ok": ok,
        "ascii_ratio": ratio,
        "digest": words_mod.digest(d)[:16],
    }


def oracle_entries(path):
    """Read oracle_words.bin: u8 bucket, u8 len, bytes, u16 id (LE), in BUCKET ORDER."""
    b = pathlib.Path(path).read_bytes()
    out, i = [], 0
    while i + 2 <= len(b):
        bucket = b[i]
        ln = b[i + 1]
        i += 2
        if i + ln + 2 > len(b):
            raise ValueError("oracle_words.bin truncated at %d" % i)
        w = bytes(b[i:i + ln])
        i += ln
        wid = b[i] | (b[i + 1] << 8)
        i += 2
        out.append((w, wid, bucket))
    return out


def verify_against_oracle(words_tok, dump):
    """★★★★ AC-2's actual comparison: OUR parse against what the ORACLE loaded, entry for entry.

    ★★★ Bucket order is compared, not just membership. findWordInDictionary() scans a bucket in
    order and keeps the LAST full match, so two dictionaries with the same entries in a different
    order are different matchers. A set comparison would pass on a dictionary that matches
    differently -- which is the whole thing this gate exists to catch.
    """
    ours = words_mod.parse(pathlib.Path(words_tok).read_bytes()).words
    theirs = oracle_entries(dump)
    # ★ Ours is in FILE order across all buckets; the oracle's dump is bucket-major. Group ours
    # the same way rather than sorting either -- sorting would destroy the very order under test.
    by_bucket = collections.defaultdict(list)
    for w, wid, letter in ours:
        by_bucket[letter].append((w, wid, letter))
    ours_bucket_major = [e for b in range(26) for e in by_bucket[b]]
    if len(ours_bucket_major) != len(theirs):
        return False, "count %d vs oracle %d" % (len(ours_bucket_major), len(theirs))
    for i, (a_, b_) in enumerate(zip(ours_bucket_major, theirs)):
        if a_[0] != b_[0] or a_[1] != b_[1] or a_[2] != b_[2]:
            return False, ("first difference at bucket-major index %d: "
                           "id %d vs %d, len %d vs %d, bucket %d vs %d"
                           % (i, a_[1], b_[1], len(a_[0]), len(b_[0]), a_[2], b_[2]))
    return True, "%d entries identical, in bucket order" % len(theirs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--only", default="")
    ap.add_argument("--oracle", default="",
                    help="dir of <Title>/oracle_words.bin to verify against")
    a = ap.parse_args()
    want = {x.strip() for x in a.only.split(",") if x.strip()}

    root = pathlib.Path(a.root)
    rows = []
    for d in sorted(root.iterdir()):
        if not d.is_dir():
            continue
        if want and d.name not in want:
            continue
        wt = None
        for cand in ("WORDS.TOK", "words.tok"):
            if (d / cand).exists():
                wt = d / cand
                break
        if wt is None:
            continue
        try:
            rows.append((d.name, census(wt)))
        except words_mod.WordsError as e:
            rows.append((d.name, {"error": str(e)}))

    print("%-22s %7s %7s %7s %8s %8s %7s  %-16s" %
          ("title", "bytes", "entries", "ids", "syn-cls", "ignore", "offbkt", "digest16"))
    print("-" * 96)
    for name, r in rows:
        if "error" in r:
            print("%-22s  ★★★ %s" % (name, r["error"]))
            continue
        print("%-22s %7d %7d %7d %8d %8d %7d  %s%s" %
              (name, r["bytes"], r["entries"], r["ids"], r["synonym_classes"],
               r["ignorable"], r["off_bucket"], r["digest"],
               "" if r["ascii_ok"] else "  ★★★ NOT ASCII (%.2f)" % r["ascii_ratio"]))
    print("-" * 96)
    if a.oracle:
        print()
        print("★★★ AC-2 -- OUR PARSE vs WHAT THE ORACLE LOADED, entry for entry, in bucket order")
        odir = pathlib.Path(a.oracle)
        checked = passed = 0
        for name, r in rows:
            if "error" in r:
                continue
            dump = odir / name / "oracle_words.bin"
            if not dump.exists():
                continue
            checked += 1
            wt = root / name / "WORDS.TOK"
            try:
                ok, msg = verify_against_oracle(wt, dump)
            except Exception as e:                                   # noqa: BLE001
                ok, msg = False, str(e)
            passed += 1 if ok else 0
            print("  %-22s %s  %s" % (name, "PASS" if ok else "★★★ FAIL", msg))
        print("  %d of %d titles verified against the oracle" % (passed, checked))

    ob = [n for n, r in rows if "error" not in r and r["off_bucket"]]
    if ob:
        print("★★★ off-bucket entries present in: %s" % ", ".join(ob))
        print("    ScummVM SKIPS these [words.cpp:109]; we record them. The vocabularies")
        print("    differ by exactly that count, and it is a normalisation, not a defect.")
    else:
        print("★ No off-bucket entries in any title: our vocabulary and the oracle's should")
        print("  agree entry for entry, and AC-2 can compare them directly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
