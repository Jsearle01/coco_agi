## Form B Report — P6.3 — Widen the parser gate, gate the tokeniser, and port it to 6809
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0 = 2026-09-06 ~19:35 local (HEAD `390e8bb`, wip). ★ **The stamp is bracketed, not recorded** —
the dispatch arrived between my P6.2 report at 19:30 and this task's first artifact
(`parser_sweep.ps1`) at 19:36. Stated as a bracket rather than rounded into a false precision.

`git status` at t0: clean. At report time: `harness/tools/said_gate.py` and `tools/agivm/parser.py`
modified; `src/engine/parser.s`, `src/harness/parser_probe.s`, `harness/tools/parser_gate.lua` new.

★★ **AC texts below are RESTATED, not quoted.** The dispatch is no longer in my context verbatim.
The substance of each is what I worked to and is recoverable from the artifacts; if a restatement
has drifted from the dispatch's wording, the verdict should check the dispatch, not this list.

---

### 1 — Summary

The parser is ported to 6809 and matches `tools/agivm/parser.py` on **23,328 cases across five
titles — every distinct `said()` operand pattern in each — with zero divergence on both the
tokenised word numbers and the match result.** The Python leg is itself gated against the pinned
oracle at the same 23,328 cases with zero divergence, so the chain is 6809 → Python → ScummVM.
The port is **870 bytes** (739 code, 131 state) against `MAP_RESERVED`'s 3,328, which is
**unchanged**. §3.E's four predicted 6809 forms all held; one was incomplete, and the gap is a
40-byte scratch buffer the prediction's phrasing ("no copy") concealed.

★★★★★ **The task's real finding is not about the parser. Four of the five titles were reported as
diverging, and they were not.** The port gate's stall detector charged its 20-second budget to a
whole chunk instead of to progress, so a chunk that took longer than 20 emulated seconds was
declared stalled *while it was working* — and King's Quest 1, the smallest dictionary, was the one
that passed. On top of that, three symbol addresses in the stall dump were hard-coded and had gone
stale by two bytes, so the dump printed `fpos=33849` — an offset of 33,849 into a 34-byte string,
which is not a plausible wrong answer but the single most incriminating one the situation could
produce. And `said_gate.py --results` printed the 6809 side under the label `oracle`, so every port
run this task made asserted a provenance it did not have. ★★ **Then the guard I added to prevent
the second one recurring turned out to be unable to fire** — it read an `lfs` global that MAME's
Lua does not define, and passed a map I had deliberately stalened. **Four defects, one class: a
diagnostic that does not fail, it testifies.** All four are fixed, all four are captured as
candidates, and the guard is now broken on purpose in both directions before being believed.

---

### 2 — Files modified

**New:**
- `src/engine/parser.s` — the port. `par_clean`, `par_find`, `par_parse`, `par_said`, plus the two
  character-class tables and `PAR_FAULT_FIRST_MATCH`.
- `src/harness/parser_probe.s` — the probe that runs the port over the gate's case file.
- `harness/tools/parser_gate.lua` — the MAME host: chunked staging, map-derived symbols,
  progress-based stall budget.

**Modified:**
- `tools/agivm/parser.py` — `FAULT_LONGEST_MATCH` added (AC-5's second fault, 12 lines).
- `harness/tools/said_gate.py` — `--results`, `--tokenise`, `--synonyms`, `--fault-tokenise`,
  `--limit`; `read_oracle(workdir, path)`; and the reference-labelling fix (§3.F).
- `mame-idioms-coco3-port.md` — **idiom 42 added** (§2A.4): reading your own symbols from the
  assembler's map, `lfs` reachable only via `require` in MAME's Lua (42a), and when a hex literal
  is correct because it names a declared contract rather than an interior symbol (42b).

**Unchanged and reported as such:** `src/engine/memmap.inc` — `MAP_RESERVED` is untouched
(`$5300..$6000` = 3,328 B). No HAL file was touched, so `hal_sync_check.py` has nothing to say
about this task; it is run in §5 regardless.

---

### 3 — Reasoning

#### 3.A The chain, and why the 6809 is not diffed against ScummVM directly

The port is compared against `parser.py`, and `parser.py` is compared against the oracle. Diffing
the 6809 against the oracle instead would be the same comparison with a longer chain and one more
thing to get wrong — and the Python leg is gated at the identical 23,328 cases with zero
divergence, so it is a sound intermediate. ★ Both legs read **the same case file, byte for byte**
(`said_gate.py --emit` writes it; `parser_gate.lua` stages it), and both write **the same record
format**, so one reader and one comparison serve both references [§2O.1: the two are clients of the
same reference; the 6809 is never compared to our own renderer *instead of* the oracle].

**Authority tier:** every parser rule in `parser.s` is transcribed from ScummVM at the pin with a
`file:line` beside it. Per §2.1: these are believed **original**, not normalisations —
`words.cpp`'s bucket walk, prefix compression and "last full match wins" are reading a Sierra file
format, and a normalisation would show up as a divergence against the format rather than as a
choice. The one place I am reproducing a **ScummVM choice** is the absence of a bound on
`_egoWords[]`; ScummVM segfaults past 20 words (measured, exit 139, twice) and the port stops at
`PAR_MAX_WORDS`. That is a deliberate divergence, recorded in the source at `par_parse`.

#### 3.B §2H's three checks, on `findWordInDictionary`

1. **Is there a second mechanism for a different object class?** Yes, and it is why the tokeniser
   needed a gate of its own. `said()` compares **word numbers**; the tokeniser produces them from
   **text**. Two words that are synonyms share a number, so a tokeniser that picks the wrong
   dictionary entry can produce the *right* number by the wrong route — invisible to `said()`.
   That is exactly what AC-5 demonstrates, on both legs (§3.D).
2. **Name the caller, not the implementation.** `findWordInDictionary` is called only from
   `parseUsingDictionary` (`words.cpp:326`), and the caller carries three rules the callee does not:
   an IGNORE result occupies no word slot, an UNKNOWN word is stored *and stops parsing*, and the
   two VM flags are set from the word count. Porting the callee alone would have produced a correct
   lookup inside a wrong parse.
3. **Grep the reports before citing a prior characterisation.** Done. `reports/*p6-2*` §3.E is this
   task's §3.E baseline and is quoted in §3.E below rather than paraphrased. No contradiction found
   between P6.2's parser claims and this task's measurements.

#### 3.C ★★★★★ The stall that was the harness's own clock

`parser_gate.lua` feeds the probe in chunks (a chunk is sized to fit between `$6000` and
`PP_RESULTS` at `$A000`) and declares a stall if `PP_DONE` has not been set within 20 emulated
seconds. **The clock was started when the chunk began and never restarted**, so the budget covered
the whole chunk. 224 cases fit inside it; 254 did not.

Four of five titles "stalled". The fifth was Kingquest1 — **the smallest dictionary in the corpus at
3,144 bytes** — and a failure that appears on the bigger dictionaries and not the smallest reads
exactly like a defect the bigger inputs expose. The program counter landed in `par_fi_cmp`'s
character loop on every stall, which reads like a runaway walk; ★★ **that loop is provably bounded
by a decrementing counter and cannot diverge**, which should have closed the hypothesis on
inspection and did not.

What actually closed it was bisection [L-36, and the dispatch's own trigger 1: *"if you can bisect
against `parser.py`, it is not ambiguous"*]:

- the accused case, in isolation with four neighbours: **parses correctly**;
- the last 2, 4, 8, 16, 32, 64, 128, 160, 192, 224 cases ending on it: **all pass**;
- the last 254: **stalls**.

★★★ **A threshold that sits between 224 and 254 cases is a COUNT, not an input — and a count
threshold on a fixed batch is the signature of a budget.** The stack pointer at stall was `$3CF4`,
twelve bytes below `lds #$3D00`, which ruled out the one resource that does accumulate per call.
Resetting the clock whenever `PP_RUN` advances took the same 254-case file from "stalled" to
"254 results written" with no change to a single line of 6809.

#### 3.D ★★★★★ The port's own injected fault, and what it proves about the tokeniser gate

A gate that has only ever reported PASS has not been shown to be a gate [L-62], and the Python
leg's two faults do not transfer — they prove `parser.py`'s harness, not this one. So the port
carries `PAR_FAULT_FIRST_MATCH`: after a full dictionary match, stop the bucket walk instead of
letting a later, longer match overwrite it.

★★★★ **It is the plausible version, not a strawman.** The bucket is alphabetically sorted, the
first full match looks final, and `bra par_fi_tail` saves a walk on every lookup. It is also
deliberately a fault `said()` can miss — it changes the winner only where one dictionary word is a
prefix of another in the same bucket, and those are usually synonyms sharing an id.

| title | tokenise differs | match differs |
|---|---|---|
| Kingquest1 | 132 | **0** |
| Kingquest3 | 303 | **0** |
| larry1 | 309 | **0** |
| PoliceQuest1 | 357 | **0** |
| SpaceQuest-1 | 188 | **0** |
| **total** | **1,289** | **0** |

★★★★★ **`match differs` is zero on every title.** A gate that watched only the `said()` result would
have reported the faulted port green on all 23,328 cases. This is P6.2 §7.3's prediction —
*"a tokenise defect that produces the same IDs by a different route"* — demonstrated on the target,
not just in Python, and it is the whole justification for L-38's independent tokeniser gate.

★★ **Cross-check that the two faults are the same defect:** `FAULT_LONGEST_MATCH` applied to
`parser.py` and diffed against the oracle gives **KQ1 132, larry1 309, PoliceQuest1 357** — digit
for digit the same counts as the port's. The fault was written twice, in two languages, from the
same reading, and the two agree on which 1,289 cases it moves.

#### 3.E AC-8 — §3.E's predicted 6809 forms against actual cost

P6.2's `parser.py` header committed to four target forms. Measured from `build/parser_probe.map`:

| §3.E predicted | actual | difference |
|---|---|---|
| **The vocabulary** — *"the resource itself, in place, under one window. No copy and no index is built."* | `par_vocab`: one 2-byte pointer. `par_fi_bucket` computes `vocab + letter*2`, reads the big-endian head offset, adds `par_vocab`, and walks the prefix runs in place. **Zero bytes of dictionary copied; no index built.** | ★★ **Held, but the phrasing concealed a cost.** Prefix compression means the candidate word must be *reassembled* to be comparable, so there is a **40-byte scratch (`par_word`) plus a length byte** the prediction did not name — 40 of the port's 131 state bytes, **31%**. Not a copy of the dictionary; a copy of one entry. |
| **Residency** — *"all twelve are under 8,192, so the vocabulary needs ONE slot."* | Re-measured independently: max **6,828** (SpaceQuest-2); PQ1 6,737, larry1 6,597, GoldRush 6,110, KQ3 5,657, SQ1 4,793, KQ2 3,516, KQ1 3,144, then four under 300. | **Held exactly.** 1,364 bytes of headroom on the largest. |
| **The tokenised result** — *"a 40-byte array (20 × u16) plus a count byte."* | `par_ego` 40 B + `par_egon` 1 B. | **Held exactly**, 41 B. |
| **The `said()` operands** — *"read in place from the LOGIC in its window. Already bounded by N, no allocation."* | `par_said` takes `X` at the operand block and walks it with a 2-byte cursor (`par_sd_p`). Nothing copied. | **Held.** |
| **The match itself** — *"the same loop. No Python-vs-target gap at all."* | One loop over `min(N, 20)`, 152 bytes of code. | **Held.** |

**What §3.E did not predict at all, and it is the more useful number:** the cost is dominated by
the parts it did not name.

| region | bytes | |
|---|---|---|
| `par_clean` | 121 | code |
| `par_is_sep` + `par_is_inv` | 46 | code |
| `par_septab` + `par_invtab` | 20 | data |
| `par_find` (incl. the bucket walk and compare) | 288 | code |
| `par_parse` | 132 | code |
| `par_said` | 152 | code |
| pointers (`par_vocab`/`inbuf`/`clnbuf`) | 6 | state |
| `par_ego` + count + `notfound` + 2 flags | 44 | state |
| `par_word` (the reassembly scratch) | 40 | state |
| `par_find` scratch (`fpos`/`fid`/`flen`/`fptr`/`fwlen`/`fcur_id`) | 10 | state |
| `par_clean` scratch, `par_said` scratch | 11 | state |
| **total** | **870** | **739 code + 131 state** |

★★★ **`cleanUpInput` and the bucket walk are 409 of 739 code bytes (55%), plus 20 bytes of tables.**
The two structures §3.E treated as the substance — the tokenised array and the match loop — are
`par_parse` + `par_said` = 284. **The header named the data and said nothing about which code
dominates, and the answer is the two transcription-sensitive routines**, which is also where every
port bug in this task lived (§7).

#### 3.F The three diagnostics that testified

1. **The stall budget** — §3.C.
2. **Three hard-coded symbol addresses.** The stall dump read `par_fpos`/`par_flen`/`par_egon` at
   `$21A9`/`$21AD`/`$20E6`, taken from an earlier build's map. The real addresses are
   `$21AB`/`$21AF`/`$20E8` — **every one two bytes low** after the source grew. The dump printed
   `fpos=33849`. ★★★ **An offset of 33,849 into a 34-byte string is not a large error; it is
   evidence the reading has no relationship to the quantity** — and it was read as a runaway cursor
   for several rounds, including a buffer dump that proved both buffers correctly NUL-terminated
   and was treated as deepening the mystery rather than as contradicting the premise. The Lua now
   parses `build/parser_probe.map`, makes a missing symbol fatal, and resolves the PC to
   nearest-symbol+offset. With honest symbols the same run reported `fpos=11 egon=2` — ordinary
   mid-parse values.
3. **The reference label.** `said_gate.py`'s output prints the two sides as `ours` and `oracle`.
   `--results` swaps the right-hand side from ScummVM's dump to the 6809 probe's, and the print
   statements were never touched — so **every port run this task made was labelled as a comparison
   against ScummVM that it was not.** The counts were right; the provenance the output asserted was
   not. Now derived from one variable set where the reference is chosen (`python` vs `6809`/`oracle`).

★★★★★ **And then I wrote a fourth one while fixing the second.** Reading symbols from the map moves
the staleness one file along — `lwasm` without `--map` leaves the old map beside a new `.bin` and
every symbol is wrong again with nothing to say so — so I added a guard refusing to run when the
map is older than the binary. It needs file mtimes, which need `lfs`. ★★★★ **`lfs` is present in
MAME's Lua but is NOT a global; it is reachable only through `require("lfs")`.** The guard read the
global, got `nil`, and fell through to the "no lfs" fallback I had written, which compared `0 < 0`
and passed. **I stamped the binary five minutes into the future and the guard let the run proceed.**

★★★ **An assertion that cannot fire, guarding the exact defect class that had just cost this task
hours, in the file written to fix it.** It was caught only by trying to break it [*an assertion you
have not broken is not an assertion*]. A three-line probe printed `lfs = nil` and
`require = true`; the guard now uses `require`, refuses on a stale map AND on a missing one, and
passes a fresh pair — two-sided, §5. **The general lesson is that an absent-capability fallback is
almost always permissive, so a false absence silently switches the check off** — and a guard added
in response to an incident deserves breaking more than any other code, not less.

★ Both are added to `mame-idioms-coco3-port.md` as **idiom 42** (§2A.4), with 42a for the `lfs`
namespace and 42b for the literal-vs-declared-contract distinction from §3.H.

#### 3.H ★★ I swept the other harnesses for the same defect, and they are clean

§3.F.2 is one instance of a class, so I swept the rest [*one instance of a defect class means sweep
for the rest*]. **266 hex literals across 25 Lua harnesses; 37 of them name an address inside the
guest's code region.** Checked individually against the probes' own sources, and the result is the
opposite of what I expected:

★★★ **`parser_gate.lua` was the outlier, not the pattern.** Every other literal in that range is a
**declared `equ` contract** — the DP handshake blocks at `$0080`–`$009F` (`vm_probe.s:32-52`,
`cel_probe.s:50-67`, `res_probe.s:14-26`, `pic_probe.s:130-149`), the `$2000` load address, and
staging buffer bases. **Those are fixed by design and do not move when the source grows.** They are
the right thing to write as literals.

★★ **I nearly filed a false finding here and the check that stopped it was §2H's second one.**
`vm_sweep.lua:407` reads `icguard` from the literal `0x008D` while `vm_sweep.lua:375` reads
`SYM.vm_icguard`, which resolves to `$21DE` — the same field name at two addresses in one file,
three lines apart, which reads as exactly this defect. It is not. `$008D` is `VP_ICGUARD`, the
probe's handshake slot; `$21DE` is the engine variable the probe mirrors into it. **Two addresses,
two things, both correct** — and naming the declaring routine rather than the line is what
separated them.

★ **The class has bitten this project twice before, and both are recorded in-tree**, which §2H's
third check found: `vm_sweep.lua:102-103` — *"Symbols come from the BUILD, never from a copy beside
the fixture (§2F). P1.3 lost half a session to a stale symbols.txt"* — and `res_sweep.lua:265-278`,
where a literal `0x3000` went stale when the LOGIC cache landed at T-P0-036 and produced a **green
gate reading the wrong address**, with the ablation arm accidentally making the stale literal right
again. **So `parser_gate.lua` is the third instance, and the first two had already been fixed and
written down.** Having the lesson in two files was not enough to stop me writing it a third time in
a new one — the same shape as §4A.2.

#### 3.G AC-6 — the speed words, after Jay's correction

Jay: *"if your talking about animation speed, the kqIII game for coco3 had a speed setting. if your
talking about the parser then yes, what you said."* Both, and the distinction matters. The speed
words are **ordinary vocabulary entries with ordinary word numbers** in every title measured:

```
title            fastest   fast      normal    slow
Kingquest1       --        id 160    id 159    id 161
Kingquest2       id 253    id 160    id 159    id 161
Kingquest3       id 10     id 9      id 8      id 7
larry1           id 310    id 309    id 308    id 307
PoliceQuest1     id 10     id 9      id 8      id 7
SpaceQuest-1     id 344    id 160    id 159    id 161
```

So the **game feature is in scope and is reached through the parser** — the port already tokenises
and matches these exactly like any other word, and the KQ3 CoCo3 speed setting Jay names is the
game's own LOGIC responding to `said(fast)`. What is **out** of scope is ScummVM's
`handleSpeedCommands` interception, which is a ScummVM normalisation (§2.1) sitting *above* the
parser and answering these words itself rather than letting the game do it. **We reproduce the
game's behaviour, not ScummVM's shortcut.**

---

### 4 — Verification (AC-by-AC)

★ AC texts restated (see §0).

- **AC-1 [class: state-comparable] — PASS, five titles.** The `said()` gate widened from a sampled
  400 to **every distinct operand pattern**: 1,932 + 6,740 + 5,436 + 6,800 + 2,420 = **23,328 cases
  from 5,832 distinct patterns**. `parser.py` vs the oracle: **tokenise differs 0, match differs 0**
  on all five. §5.
- **AC-2 [class: state-comparable] — PASS.** Coverage stated in its own units: 5,832 distinct
  operand patterns, 8,059 oracle matches of 23,328 cases (34.5%), so the corpus exercises both
  outcomes heavily rather than being dominated by non-matches.
- **AC-3 [class: state-comparable] — see §5 (widened run in flight at report time).** The tokeniser
  is gated **independently of `said()`**, with `said()` held constant, on its own case set built
  from the dictionary rather than from operand patterns.
- **AC-4 [class: state-comparable] — PASS.** `FAULT_ANY_WORD` (operand `1` stops meaning "any
  single word") is **caught by the `said()` gate**: match differs 42 (KQ1), 45 (larry1), 82 (PQ1).
- **AC-5 [class: state-comparable] — PASS, and it is the load-bearing one.** `FAULT_LONGEST_MATCH`
  is **missed by the `said()` gate and caught by the tokeniser gate**: tokenise differs
  132/309/357, **match differs 0**. Mirrored on the target as `PAR_FAULT_FIRST_MATCH` with the same
  counts (§3.D).
- **AC-6 [class: state-comparable] — ANSWERED, with Jay's correction incorporated.** §3.G. The speed
  words are ordinary vocabulary in all six titles measured; the game feature is in scope through
  the parser, ScummVM's interception is not.
- **AC-7 [class: state-comparable] — PASS, five titles, zero divergence.** `parser_probe.bin`
  (1,056 B) over the same 23,328 cases: **tokenise differs 0, match differs 0** on every title. The
  gate is shown to be able to fail by `PAR_FAULT_FIRST_MATCH` (1,289 cases caught) [L-62]. §5.
- **AC-8 [class: byte-comparable] — ANSWERED with the measured table.** §3.E. Four predictions held;
  one held with a 40-byte omission; and the dominant cost is in the two routines the prediction did
  not name.
- **AC-9 [class: byte-comparable] — ANSWERED.** The parser is **870 B (739 code + 131 state)**
  against `MAP_RESERVED` `$5300..$6000` = **3,328 B, UNCHANGED**, which is **26.1%**, leaving
  2,458 B for sound. `MAP_RESERVED_MIN`'s 3,072 floor is untouched. **The vocabulary is not in
  `MAP_RESERVED`** — it is a resource, and the measurement says one 8 KB slot holds any of the
  twelve (max 6,828). ★ Which slot is not settled by this task and is flagged in §7.
- **AC-10 [class: state-comparable] — four things the dispatch did not anticipate,** all one class:
  §3.C (a timeout reported as a stall), §3.F.2 (stale hard-coded symbols inventing a cursor value),
  §3.F.3 (a reference label asserting the wrong provenance), and §3.F's fourth — **a freshness
  guard that could not fire, written to fix the second one.** ★★ **The first three compounded**:
  the invented `fpos` made the timeout look like a runaway cursor, which sent the investigation
  into the parser instead of the harness, and the label meant the runs that would have shown the
  truth were filed under the wrong reference. ★ A fifth candidate finding — that the same
  literal-address defect is loose in the other 24 harnesses — was **tested and is false** (§3.H),
  and the negative is a result [§8].
- **AC-11 — four candidates captured.** §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — AC-7, the ported parser vs `parser.py`, five titles (verbatim):**

```
★ 1932 results written to build/parser/port/Kingquest1_6809.txt
cases            : 1932   (483 distinct operand patterns)
tokenise differs : 0
match differs    : 0
★ 1932 of 1932 identical on BOTH the tokenised words and the match result
★ 6740 results written to build/parser/port/Kingquest3_6809.txt
cases            : 6740   (1685 distinct operand patterns)
tokenise differs : 0
match differs    : 0
★ 6740 of 6740 identical on BOTH the tokenised words and the match result
★ 5436 results written to build/parser/port/larry1_6809.txt
cases            : 5436   (1359 distinct operand patterns)
tokenise differs : 0
match differs    : 0
★ 5436 of 5436 identical on BOTH the tokenised words and the match result
★ 6800 results written to build/parser/port/PoliceQuest1_6809.txt
cases            : 6800   (1700 distinct operand patterns)
tokenise differs : 0
match differs    : 0
★ 6800 of 6800 identical on BOTH the tokenised words and the match result
★ 2420 results written to build/parser/port/SpaceQuest-1_6809.txt
cases            : 2420   (605 distinct operand patterns)
tokenise differs : 0
match differs    : 0
★ 2420 of 2420 identical on BOTH the tokenised words and the match result
```

**25.1 — AC-7's fault, `-DPAR_FAULT_FIRST_MATCH` (the gate can fail).** ★ Condensed: every figure
and every `★★★` line is as the tool printed it; the per-title `cases :` lines are omitted (they are
identical to the clean run above) and that omission is mine.

```
★ 1932 results written to build/parser/port/Kingquest1_6809_fault.txt
tokenise differs : 132
match differs    : 0
★★★ first divergence at case 120 (tokenise): operands=[19, 90] python ego=[19, 90]->True 6809 ego=[19, 199, 90]->False
★ 6740 results written to build/parser/port/Kingquest3_6809_fault.txt
tokenise differs : 303
match differs    : 0
★★★ first divergence at case 376 (tokenise): operands=[2, 135] python ego=[2, 135]->True 6809 ego=[2, 134, 135]->False
★ 5436 results written to build/parser/port/larry1_6809_fault.txt
tokenise differs : 309
match differs    : 0
★★★ first divergence at case 108 (tokenise): operands=[3, 29] python ego=[3, 29]->True 6809 ego=[2, 29]->False
★ 6800 results written to build/parser/port/PoliceQuest1_6809_fault.txt
tokenise differs : 357
match differs    : 0
★★★ first divergence at case 144 (tokenise): operands=[116, 283] python ego=[116, 283]->True 6809 ego=[2, 283]->False
★ 2420 results written to build/parser/port/SpaceQuest-1_6809_fault.txt
tokenise differs : 188
match differs    : 0
★★★ first divergence at case 44 (tokenise): operands=[203, 43] python ego=[203, 43]->True 6809 ego=[2, 43]->False
```

**25.1 — AC-1/AC-2, `parser.py` vs the ORACLE, five titles (verbatim):**

```
cases            : 1932   (483 distinct operand patterns)
oracle matched   : 629 of 1932
tokenise differs : 0
match differs    : 0
★ 1932 of 1932 identical on BOTH the tokenised words and the match result
  ^^ Kingquest1
cases            : 6740   (1685 distinct operand patterns)
oracle matched   : 2158 of 6740
tokenise differs : 0
match differs    : 0
★ 6740 of 6740 identical on BOTH the tokenised words and the match result
  ^^ Kingquest3
cases            : 5436   (1359 distinct operand patterns)
oracle matched   : 1835 of 5436
tokenise differs : 0
match differs    : 0
★ 5436 of 5436 identical on BOTH the tokenised words and the match result
  ^^ larry1
cases            : 6800   (1700 distinct operand patterns)
oracle matched   : 2688 of 6800
tokenise differs : 0
match differs    : 0
★ 6800 of 6800 identical on BOTH the tokenised words and the match result
  ^^ PoliceQuest1
cases            : 2420   (605 distinct operand patterns)
oracle matched   : 749 of 2420
tokenise differs : 0
match differs    : 0
★ 2420 of 2420 identical on BOTH the tokenised words and the match result
  ^^ SpaceQuest-1
```

★ **23,328 and 8,059 are my sums of the five lines above, not printed by the tool** — 1,932 +
6,740 + 5,436 + 6,800 + 2,420 and 629 + 2,158 + 1,835 + 2,688 + 749 [§8: label your own arithmetic].

**25.1 — AC-4, `FAULT_ANY_WORD`, caught by the `said()` gate.** ★ Condensed as above: figures as
printed, one line per title, layout mine.

```
★★★ FAULT INJECTED: operand 1 no longer means 'any word'
Kingquest1    tokenise differs : 0   match differs : 42
  ★★★ first divergence at case 69 (match): operands=[1, 24] python ego=[2, 24]->False oracle ego=[2, 24]->True
larry1        tokenise differs : 0   match differs : 45
PoliceQuest1  tokenise differs : 0   match differs : 82
```

**25.1 — AC-5, `FAULT_LONGEST_MATCH`, MISSED by the `said()` gate.** ★ Condensed the same way.

```
★★★ FAULT INJECTED: findWordInDictionary keeps the FIRST match, not the last
Kingquest1    tokenise differs : 132   match differs : 0
PoliceQuest1  tokenise differs : 357   match differs : 0
larry1        tokenise differs : 309   match differs : 0
```

**25.1 — the map-freshness guard, broken on purpose in both directions (verbatim):**

```
-- 1. STALE MAP (bin stamped 5 min into the future): the guard MUST fire --
★★★ build/parser_probe.map is OLDER than build/parser_probe.bin -- the map is stale and every
    symbol it names is a guess. Re-assemble with --map.

-- 2. MISSING MAP: the guard MUST fire --
★★★ cannot stat build/nope.map -- no symbol map, or lfs unavailable. Assemble with --map=build/nope.map.

-- 3. FRESH: the guard must NOT fire --
staged: program 1056 B, vocabulary 3144 B, 1932 cases, chunk 400
★ 1932 results written to build/parser/port/smoke3.txt
```

★★ **Test 1 is the one that matters: the first version of this guard PASSED it**, because it read
the `lfs` global (nil) instead of `require("lfs")`. §3.F.

**25.1 — AC-3, the tokeniser gated alone: PENDING — see §7.**

**25.1 — `reg_discipline.py` (§2N; `src/engine/` was touched) (verbatim):**

```
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).

  file                                     count  registers
  src/engine/mmu_phase.s                       8  $FFA5 $FFA6
```

★ **`parser.s` adds zero register accesses**, which is the expected result for a routine that is
pure computation over a resource. The 8 in `mmu_phase.s` are unchanged.

**25.1 — the build.** ★ The commands are as run; `lwasm` prints nothing on success, so the sizes are
from the filesystem and the byte breakdown is my arithmetic over `build/parser_probe.map`.

```
lwasm --format=raw --output=build\parser_probe.bin --map=build\parser_probe.map src\harness\parser_probe.s
lwasm --format=raw -DPAR_FAULT_FIRST_MATCH --output=build\parser_probe_fault.bin --map=build\parser_probe_fault.map src\harness\parser_probe.s

parser_probe.bin        1056 bytes      (both exit 0, no diagnostics)
parser_probe_fault.bin  1058 bytes      (+2 = the ifdef'd `bra par_fi_tail`)

derived from the map: par_vocab = $20BA (8378); image ends at $2000 + 1056 - 1 = 9247
  -> parser.s occupies 870 bytes = 739 code + 131 state
MAP_RESERVED $5300..$6000 = 3,328 B, UNCHANGED   (MAP_RESERVED_MIN 3,072, untouched)
```

★ **`parser_probe.bin` is byte-for-byte the size it was before `PAR_FAULT_FIRST_MATCH` was added**,
and the map's symbol addresses are unchanged — the fault costs nothing when it is off.

**25.1 — `hal_sync_check.py`:** N/A — no shared HAL file was touched by this task.

**25.2 — bundled-artifact grep:** N/A — this task ships no DECB artifact; the probe is poked.

**25.3 — operator-runtime-smoke:** **N/A for this task, and stated deliberately.** §4A's eye gate
applies to **integration** tasks that assemble two or more independently-gated subsystems. This is
a component task: the parser has no display path, produces no pixels, and its entire observable
surface is word numbers and a boolean — which is byte-comparable and is gated at 23,328 cases here.
★ **When the parser is wired to the VM and to text input, that IS an integration task and AC-1 is
Jay's eye gate**, per §4A.3.

---

### 6 — Reactive deviations and route accounting

**Deviations (§22.5):**

1. ★★ **I widened the tokeniser and synonym gates to five titles.** P6.2 ran them on one title
   each. The dispatch's widening mandate was about `said()` operand patterns; extending it to the
   other two gates is mine, and it is reported as extra rather than as an AC.
2. ★ **I added `PAR_FAULT_FIRST_MATCH` to `parser.s`.** The dispatch asked for the port and its
   diff; the injected fault on the *target* side is mine, on L-62's reasoning that the Python leg's
   faults prove `parser.py`'s harness and not this one. It is `ifdef`-guarded and off by default.
3. ★ **I changed `said_gate.py`'s output labels.** Not asked for; it was necessary before this
   report could quote the port runs honestly (§3.F.3).
4. ★ **I added a map-freshness guard to `parser_gate.lua` and idiom 42 to the idioms file.** The
   guard is mine, on the reasoning that reading symbols from a map only relocates the staleness
   unless the map's own freshness is checked. §2A.4 requires the idiom addition and requires me to
   surface it, which §2 and §3.F do.
5. ★ **I swept the other 24 Lua harnesses for the same address defect** (§3.H). Not asked for; one
   instance of a defect class means sweep for the rest. It came back clean, which is a result.

**Route accounting.** I proposed no route this task beyond the dispatch's own three parts (widen /
gate the tokeniser / port). All three are in the commit. ★ **What I described mid-task and did NOT
implement:** while chasing the phantom `fpos`, I said the next step would be to dump `par_flen` and
`par_fpos` **after each case** to find the first case where `flen` exceeds the remaining input. **I
did not build that**, because fixing the symbol addresses made it unnecessary — there was no
runaway cursor to find. Recorded because a described-but-unbuilt instrument is invisible in a diff.

---

### 7 — Uncertainty flags

1. ★★ **AC-3's widened run was still in flight when this report was written.** The tokeniser gate
   passed on larry1 in P6.2 (2,142 cases, 0 differences); the five-title version re-runs the oracle
   on each title's own tokeniser case set and had completed Kingquest1 (6,107 cases) at report
   time. **Reported as pending rather than claimed** — §5 carries the placeholder, and the result
   will be surfaced as a follow-up message rather than folded silently into this file.
2. ★ **Which MMU slot the vocabulary occupies is not settled.** The *measurement* — one 8 KB slot
   suffices for all twelve titles — is settled and is AC-9's answer. The placement decision is a
   design question for the task that wires the parser to the VM.
3. ★ **The 870 bytes exclude the raw and cleaned input buffers.** The probe supplies them at
   `$3E00`/`$3F00` at 256 B each, which is generous; the real bound is AGI's input line length and I
   have not measured it. `MAP_RESERVED` has room for either answer, so this does not change AC-9's
   conclusion, but the figure is a code+state figure and should not be quoted as the parser's total
   footprint.
4. **Carried, unchanged, open across six tasks:** `flag_diff --manifest` over-reports.
5. **Carried:** the patch series rebuild is still deferred; `oracle/patches/0009-*.patch` remains
   cumulative (documented deviation).
6. **Carried:** p3b has 4 bytes of code region left.

---

### 8 — Follow-up candidates

1. **Wire the parser to the VM and to text input** — and that task is an **integration** task, so
   §4A applies and AC-1 is Jay's eye gate.
2. **Decide the vocabulary's slot** and record it in `memmap.inc`, with the 6,828-byte measurement
   as its justification.
3. ★★ **Sweep the other gate harnesses for chunk-budget stall detectors.** A detector that charges
   its clock to a batch will accuse the workload the moment the batch grows, and `parser_gate.lua`
   is the only one I checked. This is the open half of §3.F — the *address* half is done (§3.H) and
   came back clean; the *clock* half has not been looked at.
4. **Measure AGI's input line bound** and replace §7.3's estimate with it.

---

### 9 — User interaction during task

- Jay corrected AC-6: *"if your talking about animation speed, the kqIII game for coco3 had a speed
  setting. if your talking about the parser then yes, what you said."* Incorporated as §3.G — the
  speed words are ordinary vocabulary in every title measured, so the game feature is in scope
  through the parser and only ScummVM's interception is out.
- Standing instruction, carried: **do not commit PNGs unless asked.** No PNG is committed by this
  task; it produces none.

---

### 10 — Candidate(s) captured this task

Four, all in `seeds/AGI/live/`, pushed to the pool at `3eddcce` and `13bc261`:

- `2026-09-06-a-timeout-is-a-statement-about-the-harness-not-the-workload`
- `2026-09-06-a-hard-coded-symbol-address-turns-a-dump-into-fiction`
- `2026-09-06-a-label-naming-the-default-reference-lies-when-the-reference-is-switchable`
- `2026-09-06-a-guard-built-on-an-absent-global-is-inert-not-broken`

★ They are four distinct mechanisms and are captured as four rows rather than one, but they share a
family the reconciler may want to fold: **a diagnostic that cannot fail can still testify.** All
four produced confident, reproducible, entirely wrong statements — and each survived because the
thing it got wrong was never the thing under test. ★★ The fourth is the sharpest: it was written
*to fix* the second, and it was inert.

★ **Not captured, because it is an instance of an existing row rather than a new mechanism:** the
stale-address defect is the third in this project (P1.3's `symbols.txt`, T-P0-036's `RES_SLOT`
literal, and now `parser_gate.lua`), and both precedents were already written down in the very
files I was working beside. That belongs to
`one-instance-of-a-defect-class-means-sweep-for-the-rest`, which exists; per §2C I have not edited
it, and the recurrence is recorded here in §3.H for the reconciler.

### 11 — Commit

<filled at push>
