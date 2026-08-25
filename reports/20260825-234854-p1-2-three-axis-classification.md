## Form B Report — T-P0-007 — three-axis classification, and the KQ1 SOUND anomaly
**Class:** recon. wip.

---

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-08-25T23:48:54Z. HEAD at receipt `29f234d` (wip) → **at report `ddfbe20`**, pushed.
`git status --porcelain` at report → clean.

---

## ★ §2 PRE-DISPATCH GREP FINDINGS (C-13) — VERBATIM, BEFORE THE SUMMARY

```
coco_agi        branch wip   HEAD 29f234d8e92613ce6a47c8662f795747fa80bb9b  (at receipt)
POP3_port       branch wip   HEAD 282a65cf9c79739326e101b3d7cccffc8cff2daa
karateka_coco3  branch wip   HEAD 072ddcfc27ccb2c0a9b820913cd57b341a6e6fbc
oracle pin      9d9b9e93108a276c551aeffa390169ccc5148e15   (unchanged)
```

Sibling refs **unchanged since T-P0-001** (§2S.3).

**Manifests present, and which axes each already records:**

| file | rows | axes recorded |
|---|---|---|
| `agile-gdx-81c42ba.tsv` | 150 | `version` — **shape-derived guess only** |
| `coco3-images.tsv` | 80 | `version` — **shape-derived guess only** |
| `coco3-files.tsv` | 1,311 | none (per-file inventory) |
| `pc-agi.tsv` | 6 | `shape` — **one axis** |

★★ **Confirmed: no manifest separates the three axes.** Every one records a single
shape-derived value, which is exactly the hole AD-28 names.

### ★★ THE DETECTION HASH SCHEME, AS FOUND (not assumed — L-25)

| | value | file:line at `9d9b9e93` |
|---|---|---|
| **file** | literal `"logdir"` for v2 macros | `detection_tables.h:122` (`GAME`), `:127` (`GAME_P`), `:137` (`GAME_PS`) |
| | an explicit combined-DIR name for v3 | `:123` (`GAME3`) — `dmdir`, `bcdir`, `grdir`, `kq4dir`, `mhdir`, `mh2dir`, `dirs` |
| | `"logdir"` for **all** FANMADE variants | `:157` (`FANMADE_ILVFO`), `:159` (`FANMADE_ISVPO`) |
| **span** | **md5 of the FIRST 5000 BYTES** | `advancedDetector.cpp:974` — `_md5Bytes = 5000` |
| | AGI does **not** override it | `agi/detection.cpp:92-97` |
| **size** | `AD_ENTRY1s(f, md5, size)`; `AD_NO_SIZE = (uint32)-1` means **ignore** | `advancedDetector.h:116`, `:98`, `:82` |
| | a real size **IS enforced** | `advancedDetector.cpp:818` |

★ **The size check is what makes a match falsifiable in two dimensions rather than one** (L-23):
`GAME_PS` entries carry a real size, so a digest collision with a different length is still
rejected. **My P1.1 assumption of "first 5000 bytes of logdir" turns out to have been right —
but I had not verified the size half, and this task did.**

---

### 1 — Summary

★★ **All 194 corpus rows are now classified on three independent axes, each value carrying how
it was established, and 153 are matched against the oracle's own detection table.**

★★★ **AC-5 is resolved, and the answer is (a)/(b) with a twist: the oracle is WRONG about these
four entries and we are right.** `Kingquest1` SOUND 34–37 are **stale DIR entries** pointing past
the end of `VOL.2` — the only out-of-range entries in the entire game. The oracle appears to
"succeed" on them, emitting 206 zero bytes each. **206 is exactly the length of SOUND 21, the
last resource successfully loaded before them.** ScummVM's `volumeHeader[7]` is an
**uninitialised stack local**: the seek lands past EOF, the read returns nothing, the buffer
still holds SOUND 21's header, so the `0x1234` check passes against stale data. **Our refusal is
more correct than the oracle's output** (§3D).

★ **AC-6 confirms AD-28 from the new columns**, not by re-asserting it: CoCo3 is **1 V2**
(`KQ3/Original`) / **32 V3** / **5 not established**.

★★ **Three defects in my own parser were found and fixed, each of which had already produced
wrong output** (§3E). One of them — a `GAME*`-only pattern that missed 208 `FANMADE` entries —
made me briefly report *"fan matched 10 of 150"*, which was **a fact about my regex, not about
the corpus.** It is 134 of 150.

★ **And I conflated two commits and said so** (§6.4).

**All seven AC pass.**

---

### 2 — Files modified

Explicit-path staging (§2E). Three commits.

**`db7fda8`** — ★ **this commit's message is wrong and `ddfbe20` corrects it** (§6.4)
- `docs/project/agi-coco3-design-v0.6.md` — **+109 lines, 0 deletions.** Orchestrator-authored
  sound sections §5.1–5.3, which appeared in the tree *after* `8028bb8` committed v0.6 as given.
  **Not authored by me** (§2D).
- `harness/tools/classify_corpus.py` — **new**, the classifier. *(undescribed in that commit)*
- `games/manifests/corpus-classification.tsv` — **new**, 194 rows. *(undescribed)*

**`ddfbe20`** — an empty commit correcting `db7fda8`'s message.

★ **No game data committed** (§2P): the classification is digests, sizes and identifiers only.

---

### 3 — Reasoning

#### 3A — The three axes, and how each value is established

| axis | how | when it is left EMPTY |
|---|---|---|
| `dir_format` | four separate DIR files → v2; one combined `*dir` → v3 | no DIR files, or ambiguous |
| `vol_format` | ★ **the oracle's own `detectV3VolumeFormat`** — ten consecutive 7-byte records must each land where the previous `clen` says | LOGIC 0 is an empty slot; volume absent; combined-DIR (v3 layout not walked — out of scope) |
| `interp_version` | ★★ **ONLY from an oracle md5+size match** | **any row that did not match** |

★★ **`interp_version` is never inferred from shape, and that is L-26 made structural.** A version
from the oracle's table and one guessed from file layout are different claims; giving them the
same column value would destroy the distinction. **41 rows have it empty**, and each carries a
`*_method` saying why.

★ **The volume test is the oracle's algorithm, not a heuristic of mine.** My first attempt at
P1.1 asked *"does a plausible `clen` sit at +5?"*, which classified **every** CoCo3 title as V3
including ones where `len == clen` — **it could not fail** (L-23). The oracle's ten-record walk
desynchronises within a record or two on a wrong assumption, so it can.

#### 3B — AC-4: what the PC drop actually runs on

The direct answer the Orchestrator could not get from T-P0-005:

| row | dir_format | vol_format | interp_version | ScummVM entry |
|---|---|---|---|---|
| `Kingquest1` | v2 | V2 | **0x2917** | `kq1` "2.0F 1987-05-05 5.25″" DOS |
| `Kingquest2` | v2 | V2 | **0x2917** | `kq2` "2.2 1987-05-07 5.25″" DOS |
| `Kingquest3` | v2 | V2 | **0x2440** | `kq3` "2.00 1987-05-25 5.25″" DOS |

★★ **KQ1 and KQ2 are 0x2917; KQ3 is 0x2440 — different interpreter builds in the same drop.**
That is precisely the distinction a one-axis classification erases, and it is why AD-28 exists.

#### 3C — AC-6: AD-28 confirmed from the columns, not from memory

```
CoCo3 vol_format:   V2 = 1     V3 = 32     (empty) = 5
```

The single V2 row is **`King's Quest III/Original`**, matching ScummVM's entry
*"King's Quest 3 (CoCo3 158k/360k) 1.0C 6/27/88 [AGI 2.023] | **Official port by Sierra**"*,
interp **0x2440**. **AD-28 stands**, and §6.2's trigger did not fire.

★ The five empty rows are the `Savegames` variants — **no LOGIC dir**, so the axis is genuinely
not established. **They are flagged, not defaulted**, which is the whole point of the method
columns.

★ **One discrepancy worth recording:** that entry's human comment says *"[AGI 2.023]"* while its
machine `ver` field is **0x2440**. The comment describes the original release; `ver` is what
ScummVM emulates. **They are not the same fact**, and the manifest carries the machine field.

#### 3D — ★★★ AC-5: the KQ1 SOUND anomaly, and why the oracle is the one that is wrong

**The DIR bytes first.** The four entries are **not** the `FF FF FF` empty marker:

```
slot 34   22 0E 2F   -> volume 2, offset 0x20E2F   (VOL.2 is 90,891 bytes)
slot 35   22 0E 8F   -> volume 2, offset 0x20E8F
slot 36   22 0E ED   -> volume 2, offset 0x20EED
slot 37   22 12 6B   -> volume 2, offset 0x2126B
slots 28-33 and 38-47:  FF FF FF  -- genuinely empty
```

★ **They are the ONLY out-of-range entries in the entire game**: LOGDIR 90 present / 0 bad,
PICDIR 82 / 0, VIEWDIR 118 / 0, SNDDIR 26 / **4**.

**Now the discriminator the dispatch names — what does the oracle do?**

```
sound 30-33 : (no dump -- correctly nothing; they are empty slots)
sound 34    : 206 bytes  ALL ZERO
sound 35    : 206 bytes  ALL ZERO
sound 36    : 206 bytes  ALL ZERO
sound 37    : 206 bytes  ALL ZERO
scummvm.log lines mentioning "signature" : 0   -- it did not even warn
```

★★★ **206 is exactly the length of SOUND 21 — the last resource successfully loaded before
them.** No other KQ1 sound is 206 bytes.

**The mechanism follows from that.** `loadVolumeResource` declares `uint8 volumeHeader[7]` as a
**stack local**. The seek lands past EOF; `fp.read(&volumeHeader, 5)` returns zero bytes and
**leaves the buffer untouched**, still holding SOUND 21's header from the previous call. So
`READ_BE_UINT16` sees a valid `0x1234`, the signature check passes, `len` is taken as **206**,
`calloc` zeroes a 206-byte buffer, the payload read returns nothing, and the function returns a
non-null pointer to 206 zeros.

**Verdict against the dispatch's three candidates:**

- **(c) our offset arithmetic is wrong — EXCLUDED.** The decode is confirmed byte-by-byte from
  the raw DIR (`0x22 >> 4 = 2`; `0x220E2F & 0xFFFFF = 0x20E2F`), is the same arithmetic the
  oracle uses, and was validated at 2,410/2,410. **§6.3's stop does not fire.**
- **(a)/(b) — the entries are DEAD DATA IN THE RELEASE.** Not empty markers, so not "unused
  slots" in the formal sense; not corruption of a working resource either. They are **stale
  references into a volume region that does not exist in this release** — most plausibly
  left over from a build where `VOL.2` was larger. The game is complete, playable, and carries a
  ScummVM detection entry.

★★ **And the finding that matters more than the classification: our refusal is MORE CORRECT than
the oracle's output.** ScummVM does not read those resources — it reads *uninitialised stack* and
reports success. **Per §2.1 the 206 zero bytes are a fact about ScummVM, not about AGI**, and
anyone diffing against them would be diffing against a bug. **This is a genuine defect in the
baseline**, benign here only because nothing plays sounds 34–37.

#### 3E — ★★ Three defects in my own parser, each of which produced wrong output

**All three were caught by cross-checking a figure against something independent, not by
reading the code.**

1. **The size heuristic picked a YEAR.** `GAME("kq3", "2.00 1987-05-25", ...)` — my "first bare
   integer" search ran over the raw argument list and found **1987**, then reported
   **"MD5 MATCH BUT SIZE MISMATCH (1987 vs 390)"** for KQ3. ★ A negative lookbehind on `"` does
   not save you: **the character before the year is a space, inside the string.** Fixed by
   stripping quoted strings first.
2. **Duplicate md5s were overwritten.** `by_md5[md5] = …` silently discarded every entry sharing
   a digest with a later one. Fixed to keep all candidates, with `lookup` choosing on size.
3. ★★★ **A `GAME*`-only pattern missed 208 `FANMADE` entries.** The table went from **155 keys**
   to **363**, and fan-corpus matches from **10 of 150** to **134 of 150**. ★ **I had already
   said "10 of 150" out loud. It was a fact about my regex, not about the corpus** — L-22
   exactly: *the retrieved set is not the whole set*, and here the retrieval was mine.

★ FANMADE entries also carry **no version on the line** — it is `0x2917`, baked into the macro
chain (`detection_tables.h:164-177`). The classifier records `version_source` so a version taken
from a macro default is distinguishable from one written on the entry (L-26).

#### 3F — §2H's three checks

1. **A SECOND mechanism for a different object class?** ★★ **Yes, and it is §3E.3.** The
   detection table has **two families** of entry — `GAME*` for catalogued commercial releases and
   `FANMADE*` for fan titles — and they differ in more than name: FANMADE hashes the same file
   but carries its version in the macro rather than the line. **A parser that handled only the
   first covered 43% of the table and reported the shortfall as a corpus property.**
2. **Name the routine that CALLS it.** Decisive for the hash scheme. `_md5Bytes` is not set by
   AGI at all — it comes from `AdvancedMetaEngineDetectionBase`'s constructor
   (`advancedDetector.cpp:974`). ★ **Reading only `engines/agi` would have left the span
   unknown**, and guessing it is the L-25 failure this dispatch names in its own §5.
3. **Grep prior reports.** P1.1 §3E hashed `logdir` on the assumption of a 5000-byte span and
   got matches; **this task confirms that assumption and adds the size check it lacked.** No
   contradiction — the earlier figures stand, now on firmer ground. P2.1 §3E's finding that
   `KQ3/Original` is the sole V2-volume CoCo3 build is re-derived here independently.

#### 3G — Refs and scopes (§2S.3, L-24)

Oracle citations at **`9d9b9e93`**. Corpora: `agile-gdx@81c42ba`, the CoCo3 drop, the PC drop.
Siblings at **POP `wip` `282a65c`** / **Karateka `wip` `072ddcf`**. ★ **Every classification row
names an image or a variant, never a bare title.**

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable]** — `coco_agi` **0**, POP **59** at `282a65c`, Karateka **8** at
  `072ddcf`; fixture demo rc=0; `seam_check.py` 0 violations. ✅ **PASS.**
- **AC-2 [state-comparable]** — `games/manifests/corpus-classification.tsv`, **194 rows**, with
  `dir_format` / `vol_format` / `interp_version` and a `*_method` for each. **41 rows carry an
  empty `interp_version`, every one flagged.** ✅ **PASS.**
- **AC-3 [state-comparable]** — the oracle's own scheme applied per §2 (md5 of the first 5,000
  bytes of the detection file, size enforced). **153 of 194 matched**, each reporting game id,
  extra/variant and version; **41 NO MATCH, reported as a finding.** ✅ **PASS.**
- **AC-4 [state-comparable]** — the three PC titles on all three axes with their entries named
  (§3B). ★ **KQ1/KQ2 = 0x2917, KQ3 = 0x2440.** ✅ **PASS.**
- **AC-5 [byte-comparable]** — resolved as **(a)/(b): stale DIR entries**, with (c) excluded
  (§3D). ★ **Plus a defect in the oracle**: its apparent success is an uninitialised-stack read.
  ✅ **PASS.**
- **AC-6 [suite]** — **1 V2 / 32 V3 / 5 not-established**, derived from the new columns.
  **AD-28 confirmed**; §6.2's trigger did not fire. ✅ **PASS.**
- **AC-7 [suite]** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1a — `reg_discipline.py` ×3 (AC-1):**

```
coco_agi  src/engine/**                    [reg-discipline] OK -- measured 0   rc=0
POP       src/ less src/hal,src/harness    [reg-discipline] OK -- measured 59  rc=0
Karateka  src/ less src/hal                [reg-discipline] OK -- measured 8   rc=0
run_rule_demo.sh  rc=0        seam_check.py  0 violations outside the seam
```

**25.1b — the classification summary:**

```
[classify] detection table: 363 md5 keys, 369 entries
[classify] wrote games/manifests/corpus-classification.tsv (194 rows)
[classify] rows=194   oracle-matched=153   unmatched=41

  pop       rows  matched   volV2   volV3    vol??
  PC/DOS       6        3       3       0        3
  CoCo3       38       16       1      32        5
  fan        150      134     147       0        3

  dir_format:  v2=183, v3=3, none=8

unmatched breakdown:
  17  CoCo3   no md5 match      (repacks ScummVM does not catalogue)
  16  fan     no md5 match
   5  CoCo3   no detection file (Savegames variants)
   3  PC/DOS  no detection file (the SCI directories)
```

★ Before fixing my parser this read **155 keys / 29 matched / fan 10 of 150** (§3E).

**25.1c — AC-4, the match table:**

```
Kingquest1  dir=v2 vol=V2 interp=0x2917  kq1 "2.0F 1987-05-05 5.25\"" [DOS]  ok
Kingquest2  dir=v2 vol=V2 interp=0x2917  kq2 "2.2 1987-05-07 5.25\""  [DOS]  ok
Kingquest3  dir=v2 vol=V2 interp=0x2440  kq3 "2.00 1987-05-25 5.25\"" [DOS]  ok
```

**25.1d — AC-6, from the columns:**

```
CoCo3 vol_format:   V2=1   V3=32   (empty)=5
  the V2 row:  King's Quest III/Original   interp=0x2440
               scummvm: kq3 [CoCo3]  "King's Quest 3 (CoCo3 158k/360k) 1.0C 6/27/88
                                      [AGI 2.023] | Official port by Sierra"
  the empty rows: 5 x Savegames variants -- "no LOGIC dir"
```

**25.1e — ★★ AC-5, the anomaly:**

```
slot 34  22 0E 2F  -> vol 2 @ 0x20E2F   VOL.2 is 90,891 bytes   PAST END
slot 35  22 0E 8F  -> vol 2 @ 0x20E8F                            PAST END
slot 36  22 0E ED  -> vol 2 @ 0x20EED                            PAST END
slot 37  22 12 6B  -> vol 2 @ 0x2126B                            PAST END
slots 28-33, 38-47:  FF FF FF (genuinely empty)

out-of-range entries elsewhere in KQ1:  LOGDIR 0 · PICDIR 0 · VIEWDIR 0 · SNDDIR 4

the oracle's output for those four:  206 bytes, ALL ZERO, and NO warning
KQ1 SOUND lengths:  ... 20:81  21:206  <- the last load before 34, and the only 206
```

**25.2 — bundled-artifact grep:** **N/A.** No build artifact; the deliverables are one Python
tool and one TSV.

**25.3 — operator-runtime-smoke:** **N/A — no CoCo3 visual surface.**

---

### 6 — Reactive deviations and route accounting

1. **The classifier is a committed tool**, not a scratch script — §7 calls the table a reference
   artifact, so it must be regenerable.
2. **`FANMADE*` coverage was added mid-task** after the figures disagreed with expectation
   (§3E.3). **The dispatch did not ask for it; reporting 10-of-150 would have been wrong.**
3. **Design v0.6 gained 109 Orchestrator-authored lines during the task** and I committed them
   (§2D: Orchestrator owns content, Clyde owns commit). **109 insertions, 0 deletions**, so the
   superset property holds by construction.
4. ★★ **I CONFLATED TWO COMMITS AND THE MESSAGE IS FALSE.** `db7fda8`'s message says
   *"Committed separately from my own work so the provenance stays legible"* — and then
   `classify_corpus.py` and the TSV, still staged, went in with it. **`ddfbe20` is an empty
   commit correcting the record.** ★ **History was NOT rewritten**: `wip` is pushed and the
   Orchestrator reads the tree, so a force-push to tidy my own error costs more than the error.
   **A commit message that describes less than its commit contains is exactly what route
   accounting exists to catch, and it caught me.**

**ROUTE ACCOUNTING.** No route was proposed to Jay or the Orchestrator. What this change contains
is §2's file list plus the four items above. **What it does NOT contain:** no renderer, no VM, no
6809 code, **no v3/LZW support** — classifying a row as V3-volume is not implementing V3 — no v1
or PC Booter work, no game data. **Explicitly not done per §10:** no `src/hal/`, no
`hal_sync_check.py`, no `build.bat`, no re-running of T-P0-006's picture work.

---

### 7 — Uncertainty flags

1. **★ `vol_format` is EMPTY for all three v3-directory rows and the five Savegames variants.**
   The v3 volume layout is not walked this task (out of scope), so those rows carry a dir_format
   and no volume verdict. **Not a defect; an honest gap**, and the method column says so.
2. **★★ 41 rows are unmatched, and NO MATCH is weaker evidence than it looks.** It means *this
   digest is not in ScummVM's table* — **not** that the row is unknown to the world, and **not**
   that it is unusual. Most are CoCo3 repacks and fan titles the table never covered. ★ **Their
   `interp_version` is empty, so no downstream task should read a version for them.**
3. **★ My table parse still may not cover every entry shape.** `A2_*` (14) and `BOOTER_*` (6)
   macros are excluded — deliberately, since v1/Apple II/PC-Booter are declined (D-18) — but
   **that is 20 entries a future v1 question would need.** Multi-line entries, if any exist,
   are also missed; I did not audit for them.
4. **AC-5's conclusion that the entries are "stale from a larger VOL.2" is INFERENCE.** What is
   *measured* is that they point past the end, that they are the only such entries, and that the
   oracle's success is an uninitialised read. ★ **Why they exist is not established** and I have
   not opened a second KQ1 release to compare.
5. **★ The oracle defect (§3D) is reported, not filed.** I have not checked whether current
   ScummVM master still has it, nor whether it affects anything we depend on beyond these four
   entries. **It is benign here only because nothing plays those sounds.**
6. **`interp_version` is the version ScummVM EMULATES for a matched release**, which §3C shows
   can differ from the AGI version named in the entry's own comment. **Downstream readers should
   treat the column as "what the oracle runs it as", not "what Sierra shipped".**

---

### 8 — Follow-up candidates

1. ★★ **Report the ScummVM uninitialised-`volumeHeader` defect upstream** (§3D). It is a real
   bug in the pinned baseline, cheap to fix (`memset` or check the read's return), and **anyone
   byte-diffing against those dumps would be diffing against stack garbage.**
2. ★ **Fold the three axes back into the older manifests**, or mark their `version` columns as
   superseded — `agile-gdx-81c42ba.tsv` and `coco3-images.tsv` still carry a shape-derived guess
   under a column named `version`, and **that is the exact naming AD-28 was written against.**
3. **Decide §11.1** — 32 CoCo3 rows are V3-volume and unreachable until it is settled.
4. **Extend the parser to `A2_*`/`BOOTER_*`** if v1 ever reopens (§7.3, D-18).
5. **Investigate why KQ1's SNDDIR has four stale entries** (§7.4) — a second KQ1 release would
   settle whether it is release-specific.

---

### 9 — User interaction during task

**None.**

★ **No consultation trigger fired, and two were close.** §6.1 did not — the hash scheme took
about a dozen lines of reading across three files, well inside its threshold. **§6.2 did not:
AC-6 CONFIRMS AD-28** rather than contradicting it. **§6.3 did not: AC-5 landed on (a)/(b), not
(c)** — our arithmetic is sound, and had it been (c) I would have stopped. §6.4 did not: the
three axes **are** independent, demonstrably so — `KQ3/Original` is v2-dir **and** V2-volume
while its repacks are v2-dir **and** V3-volume, so volume format is not derivable from directory
format.

---

### 10 — Candidate(s) captured this task

**None.**

★ Stated rather than manufactured, and for the third task running the reasoning is the same: the
candidate this task would produce — *a figure you derived can be a fact about your instrument
rather than about the world* (§3E.3, "fan matched 10 of 150") — is **the same principle already
in the pool** as `a-matching-total-is-not-a-matching-measurement` and the P0.4 instrument-defect
rows. **§2C says capture at the FIRST instance.** Opening a fourth row for a fourth instance
would inflate the very count a reconciler uses to weigh the principle (`SCHEMA.md` §4: *never
fabricate history elements to inflate the count*). **Adding an instance to the existing row is a
read-time reconciler act, not mine.**

---

### 11 — Commit

`ddfbe20` — three commits this task:

```
8028bb8  P2.1a design v0.6 committed as given (§2D)          [prior task]
db7fda8  P1.2a design v0.6: Orchestrator sound sections      ★ message is wrong, see ddfbe20
ddfbe20  P1.2  CORRECTION to db7fda8's message
```

★ **`db7fda8` also contains `classify_corpus.py` and the classification TSV**, which its message
does not mention (§6.4). Pushed to `origin/wip` before this report.
