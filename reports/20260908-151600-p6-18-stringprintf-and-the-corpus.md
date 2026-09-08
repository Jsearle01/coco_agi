## Form B Report — T-P0-074 (P6.18) — `stringPrintf`, the stage before the wrap; and the corpus widened to nine
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-08T15:16:05-04:00 (HEAD 2ccf68a, wip). Working tree dirty with this task's changes only
(listed in §2). `coco_agi.code-workspace` is untracked editor state and is NOT staged.

### 1 — Summary
`stringPrintf` is implemented in the text reference and gated, and the gate's corpus went from one
title to nine. Widening it found that **the oracle's own text sweep segfaulted on two of the nine**
— and that the two crashes have different owners: PoliceQuest1's was a defect in our sweep, which
unloaded logic 0 while `%g` was still reading it; SpaceQuest-2's is the pinned engine reading
`texts[-1]` on a bare `%m`, on unmodified shipped game data. An offline instrument written to
diagnose them predicted both to the exact message, nine titles for nine. Fixing the first moved a
second thing — holding logic 0 resident switched `%m` from "appends nothing" to "substitutes" — and
the reference was changed to match, with the oracle picking the answer both times. The text gate now
passes **9/9 titles, 4,594 rectangles and 293,648 glyphs**, and both fault arms were re-shown to
fail on the new build and the new corpus.

### 2 — Files modified
- `tools/agivm/text.py` — M. `string_printf` + `PrintfState` (P6.18's substitution stage); five §2V
  rows for the printf structures, including the recursion hazard; three named divergences from the
  oracle's unguarded paths; AC-9's `get.string` requirements block.
- `harness/tools/text_gate.py` — M. `%m` now reads logic 0 (measured); `_unsafe_for_oracle` mirrors
  the sweep's skip; skip count reported.
- `oracle/patches/0010-oracle-text-decision-log.patch` — M. Regenerated from the live tree: the
  sweep holds logic 0 and skips the out-of-bounds message; 112 `★` restored (see §3.D).
- `harness/tools/text_capture.sh` — NEW. Per-title capture, one out-dir each.
- `harness/tools/text_census.py` — NEW. What the corpus contains, per title. Counts only (§2P).
- `harness/tools/text_oob.py` — NEW. Which swept message drives the oracle out of bounds, offline.
- `harness/tools/text_run.sh` — NEW. The gate over its declared nine-title corpus.
- `harness/tools/patch_regen.py` — NEW. Regenerates an oracle patch from the live ScummVM tree.
- `C:\Projects\scummvm/engines/agi/agi.cpp` — the oracle's own tree (archived by patch 0010).

### 3 — Reasoning

**A. The corpus was the finding, not the checkbox.** [authority: measurement]
`text_census.py` over the nine v2 gate titles: **14,944 messages, 1,194 format-bearing.** P6.17's
"596" was 4% of that. The format-code histogram is what made the widening actionable rather than
decorative:

| | %v | %0 | %g | %w | %s | %m |
|---|---|---|---|---|---|---|
| all nine titles | 436 | **0** | 4 | 121 | **189** | 1,044 |

★★★ **`PrintfState`'s note that `%0` and `%s` "are unused … and will be exercised the first time a
title uses them" was half wrong, and the corpus is what found it.** `%s` is used by **six of the
nine** — PoliceQuest1 94, SpaceQuest-1 40, SpaceQuest-2 32, larry1 16, MixedUpMotherGoose 6,
Kingquest2 1 — and `%s` is the *recursing* code, so the §2V hazard row sits on a live path. It still
models as empty and still agrees, because the sweep runs at init and the oracle's string table is
empty there too: **both sides read the same empty state, which is agreement about the harness and
not evidence about substitution.** `%0` is used by no staged title at all, so that model is
untestable from this corpus. Kingquest1's own codes are %v×28, %m×35, %w×13 — **one title could not
have found either.**

**B. Two segfaults, two different owners.** [authority: the oracle running; §2H's three checks]
Both SpaceQuest-2 and PoliceQuest1 exited 139 under `TEXT_DUMP=1`. `text_oob.py` diagnoses this
*offline*, from game data alone, so it cannot be stopped by the crash it is diagnosing:

- **SpaceQuest-2** — sweep message **#355** carries a bare `%m`. `strtoul` gives 0; text.cpp:1272's
  guard is `numTexts > i`, the **high end only**; `texts[-1]` is read. The capture had drawn **354**.
- **PoliceQuest1** — sweep message **#11** is the 4-byte message `%g88`. `%g` reads
  `logics[0].texts[i]` (text.cpp:1259) — and **our sweep called `unloadResource` on every logic it
  visited, logic 0 included.** By logic 2, logic 0's texts were freed. The capture had drawn **10**.

★★★★ **Nine for nine: every title the tool calls hazardous stopped exactly one message before the
message it names, and every title it calls clean swept to completion.** That is why §3 states a
cause rather than a hypothesis.

**The owners differ and that governs the fix.** PoliceQuest1's is ours — in a real game logic 0 is
the always-resident logic and this cannot happen, so **the sweep manufactured the crash**; logic 0
is now held for the sweep's duration. SpaceQuest-2's is **the engine, on unmodified shipped data**,
and the oracle is pinned (§2Q) — changing its semantics would make it a different oracle. That one
message is **skipped and counted**, so the corpus reads "574, one named" rather than a number that
quietly means something else [L-72]. The guard is deliberately the narrowest form that covers the
observed crash: a skip that dropped every `%m`-bearing message would hide 1,044 of the 1,194
format-bearing messages and the gate would still print PASS.

**C. §2H: fixing the first mechanism moved a second one.** [authority: the oracle running]
`%m` reads `logics[curLogicNr]`, and **the sweep never sets curLogicNr, so curLogicNr is 0** — `%m`
reads logic 0 exactly as `%g` does. P6.17/P6.18 measured `cur_logic_texts = []` and were right *at
the time*, for a reason that the crash fix removed: logic 0 was being unloaded, `numTexts` was 0, the
guard failed, and `%m` contributed nothing. **Holding logic 0 resident silently switched `%m` to
substituting: the same 596 Kingquest1 messages now emit 35,716 glyphs instead of 35,584, +132.**
★★★ Had the reference not been changed with it, the gate would have reported a *wrapping* divergence
on 35 Kingquest1 messages and the cause would have been three files away. The reference now uses
`logic0_texts`, and **the oracle picked that answer too** — 32,105/32,105 on the first run.

**D. The archived patch was lossy against a source that was fine.** [authority: measurement]
Patch 0010's diff body contained **zero `★` and a scattering of `?`** where the ScummVM source has
proper stars — an ASCII-strip in whatever produced it (the failure mode recorded as unrecoverable in
this session's standing notes). `patch_regen.py` preserves the authored `#` header, replaces
everything from the first `diff --git`, and writes UTF-8 without a BOM: **112 stars restored, 0 → 112.**
The patch files are a *record*, and a record that no longer reconstructs the oracle its results came
from is the provenance defect §2Q exists to prevent — invisible, because both files still look fine.

**E. Three places the reference is deliberately not the oracle.** [authority: ScummVM at the pin;
§2.1 — these are facts about ScummVM, and all three are *engine* behaviour rather than normalisation]
Recorded in `string_printf`'s docstring rather than quietly "fixed": `%g` is bounds-tested nowhere
(text.cpp:1260); `%m`'s guard is one-sided (1272); and **a trailing `\` walks past the terminator**
— the escape branch increments then falls through to `resultString += *originalText++`, appending
the NUL and leaving the pointer one byte past it, so the loop resumes on whatever follows. ★★★ The
third is the one that carries to the port: on the 6809 the messages are contiguous in the LOGIC
text table, so "past the terminator" means "the next message", and the naive port reproduces it for
free. **Measured: no message in any of the nine ends in a backslash** (65 contain one, 63 of them
PoliceQuest1's), so it is unreachable from this corpus — a decision to make, not a bug to chase.

**F. §2H's third check.** Grepping the reports for this subsystem: P6.15 established the text oracle
had no gate at all, P6.16 settled the parser gate's oracle leg, P6.17 transcribed `stringWordWrap`
and believed it was the whole path. **This report contradicts P6.17's `cur_logic_texts = []` finding
and says so at the line itself** rather than leaving the later value to win by recency.

### 4 — Verification (AC-by-AC)

- **AC-1** [class: suite] Every gate run, including both parser arms — `run_gates.sh all`: pic 45/45,
  res 1,264/1,264, cel 9,193/9,193, comp 124/124, p3b green. VM gate no-input arm **9/9 PASS**,
  parser arm **9/9 PASS with input fed to 6 of 9**. Verbatim in §5.
- **AC-2** [class: byte-comparable] `stringPrintf` implemented, statement for statement from
  text.cpp:1217-1296 — `tools/agivm/text.py`, with the five easy-to-get-wrong details named
  (the object code is `'0'` not `'o'`; `%v` strips leading zeros with `i < 14`; `%v<n>|<w>` sets
  `i = 15 - w`; `%s`/`%m` recurse; `%s` alone does not subtract 1).
- **AC-3** [class: byte-comparable] The full message set gated — **9/9 titles, 4,594 rectangles and
  293,648 glyphs identical in position, colour and checksum.** Not 596: 596 was one title.
- **AC-4** [class: byte-comparable] `--fault-printf` (drop `%v`'s leading-zero strip) fires on **all
  nine**, at rectangles 555 / 371 / 530 / 223 / 22 / 431 / 36 / 351 / 1 — i.e. **at each title's
  first format-bearing message, with everything before it intact.** `--fault-wrap` fires at 0 / 3 /
  11 / 7 / 9 / 16 / 18 / 4 / 79. ★ The two arms diverge at different points on every title, which is
  the stage separation this AC asks for; note MixedUpMotherGoose inverts the usual order (its first
  message is format-bearing), so "printf fires later" is a tendency and not a rule.
- **AC-5** [class: state-comparable] What `stringPrintf` reads beyond the 288-byte diff — documented
  in `PrintfState`. Three of six codes (`%0`, `%w`, `%s`) read state the diff never compares, and
  `%m` depends on `curLogicNr`, which it also does not carry. **A green nine-title diff does not
  guarantee the substitution's inputs.**
- **AC-6** [class: byte-comparable] The checksum boundary — **resolved, and it was an artifact.**
  P6.17's boundary was a property of `--skip-format`, which excludes format-bearing messages; with
  `stringPrintf` present the full set passes with no boundary at all.
- **AC-7** [class: suite] Corpus widened — nine titles, per title, not a total:

  | title | logics | messages | with `%` | swept | glyphs gated |
  |---|---|---|---|---|---|
  | Kingquest1 | 90 | 1,441 | 44 | 596 | 32,105 |
  | Kingquest2 | 133 | 1,321 | 58 | 536 | 35,988 |
  | Kingquest3 | 125 | 2,072 | 219 | 743 | 56,290 |
  | SpaceQuest-1 | 101 | 1,772 | 117 | 515 | 32,825 |
  | SpaceQuest-2 | 118 | 1,828 | 237 | 574 *(1 skipped)* | 43,376 |
  | PoliceQuest1 | 118 | 3,416 | 343 | 660 | 40,379 |
  | larry1 | 46 | 1,850 | 119 | 316 | 20,560 |
  | BlackCauldron | 85 | 968 | 49 | 427 | 27,933 |
  | MixedUpMotherGoose | 73 | 276 | 8 | 227 | 4,192 |
  | **TOTAL** | | **14,944** | **1,194** | **4,594** | **293,648** |

  ★ "messages" is every message in every logic; "swept" is the sweep's first-8-per-logic rule.
- **AC-8** [class: byte-comparable] The §2V table extended in the source at the decision — five rows
  for `stringPrintf`: the second 2,000-byte buffer (the wrap reads the printf's output, so they
  cannot share one), the **recursion hazard** (the oracle recurses into one static buffer and gets
  away with it only because it accumulates into a separate `Common::String`; **a 6809 port that
  recurses straight into one shared output buffer clobbers the caller**), the 16-byte `"%015i"`
  scratch plus a divide-by-10 routine, and the six callbacks that are direct reads rather than
  closures.
- **AC-9** [class: state-comparable] `get.string`'s requirements — read at the pin (`cmdGetString`)
  and recorded at the foot of `text.py`. **Its lead-in text path is already built**: `stringPrintf`
  → `stringWordWrap(…, 40)` → `displayText`. The remaining work is input and cursor state, not
  rendering: a one-deep saved cursor, edit-state restored to *previous* rather than off, the
  1,000-byte string table `%s` reads — and `cycleInnerLoopActive(CYCLE_INNERLOOP_GETSTRING)`, which
  is a **VM** question: the port's main loop has no nested-cycle re-entry today, the same shape as
  `have.key`.
- **AC-10** [class: suite] Gates run and green — see AC-1 and §5.

★ **No eye gate (§4A).** This task changed no 6809 source: the deliverables are the offline Python
reference, host-side harness tools, and the oracle's own instrumentation. §4A's ordering binds
INTEGRATION tasks, which assemble two or more independently-gated subsystems on the target; nothing
here reaches the target. The p3b integration probe ran in the suite regardless and is green.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
★ gates run: pic res cel comp p3b  -- all green
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
```

```
=== AC-2 SUMMARY ===   (VM gate, no-input arm)
Kingquest1 PASS   Kingquest2 PASS   Kingquest3 PASS   SpaceQuest-1 PASS   SpaceQuest-2 PASS
PoliceQuest1 PASS   larry1 PASS   BlackCauldron PASS   MixedUpMotherGoose PASS

=== AC-2 SUMMARY ===   (VM gate, parser arm)
Kingquest1 PASS input fed        Kingquest2 PASS input fed      Kingquest3 PASS input fed
SpaceQuest-1 PASS input fed      SpaceQuest-2 PASS (no input)   PoliceQuest1 PASS input fed
larry1 PASS input fed            BlackCauldron PASS (no input)  MixedUpMotherGoose PASS (no input)
★ parser arm covered 6 of 9 titles with input; 3 ran without and are the plain gate.
```

```
=== text gate: SpaceQuest-2 ===
  reference    : 574 messages across 118 logics   (1 skipped: the oracle reads texts[-1] on them)
  rectangles   : ours 574   oracle 574   -- 574 identical before any divergence
  glyphs       : ours 43376   oracle 43376
  OK rectangles identical (574)
  OK glyphs identical in position, colour and checksum (43376)
TEXT GATE PASS
═══════════════════════════════════════════════════════════════════════
★ TEXT GATE PASS over all 9 titles
```

**§2W — every instrument shown able to fail, on THIS build and THIS corpus [L-62]:**

- `--fault-wrap`: FAIL on 9/9, first divergence at rectangle 0/3/11/7/9/16/18/4/79.
- `--fault-printf`: FAIL on 9/9, first divergence at rectangle 555/371/530/223/22/431/36/351/1.
- `text_run.sh` with one dump removed: `★★★ larry1 : NO ORACLE DUMP … ★★★ TEXT GATE FAILED:
  larry1(nodump)   (8 of 9 titles gated)`, exit 1 — **the count is honest about how many ran.**
  Dump restored; verified present afterwards.
- `text_oob.py` — not merely exercised but **shown predictive**: it names the first hazardous
  message per title, and nine of nine titles' observed behaviour matched (two stopped exactly one
  message before the named one; seven called clean swept to the end).

**HAL / register discipline:** `hal_sync_check.py` and `reg_discipline.py` are **N/A** — no file
under `src/hal/`, `src/hal.inc` or `src/engine/` was touched (see §2).

**25.2 bundled-artifact grep:** N/A — no target artifact produced or changed this task.

**25.3 operator-runtime-smoke:** N/A — no 6809 source changed, nothing new reaches a screen. The
p3b integration probe ran headless in the suite and is green.

### 6 — Reactive deviations and route accounting
**Deviations (§22.5):** two, both forced by evidence found mid-task and neither in the dispatch.
1. **The ScummVM sweep was modified and the oracle rebuilt.** Not asked for; AC-7 was
   uncompletable without it, because two of the nine titles' captures were segfaults. The change is
   in the *sweep*, our instrumentation — no engine semantics were altered, and the one engine
   out-of-bounds found is skipped rather than patched, precisely to keep the pin intact (§2Q).
2. **The reference's `%m` handling was changed**, reversing a P6.17/P6.18 finding. Forced by (1);
   documented at the line with both measurements.

**Route accounting:** I proposed no route this task beyond the dispatch's AC list. Everything in §2
is either an AC's deliverable or one of the two deviations above; nothing described was left
unimplemented.

### 7 — Uncertainty flags
- ★★ **`%0` is untested and untestable from this corpus** — zero occurrences in 14,944 messages.
  `objectName` is modelled as empty and nothing can currently contradict it.
- ★★ **`%s` is exercised 189 times and proves less than it looks.** Both sides read an empty string
  table because the sweep runs at init. The recursion path in `stringPrintf` therefore has **no
  positive evidence** — the gate has never seen `%s` substitute anything. AC-9's work is what lifts
  this.
- ★ **The skipped SpaceQuest-2 message is not gated at all.** One message in 4,595.
- ★ Patch 0010 remains a **cumulative** diff over its four files (unchanged from P6.15; the header
  says so). Splitting the series into true increments still needs the patches committed rather than
  stacked in a dirty tree.

### 8 — Follow-up candidates
- **`get.string`** — the AC-9 list is concrete; the blocking item is the VM's missing nested-cycle
  re-entry, shared with `have.key`.
- **The eight/nine text opcodes still `vm_op_modelled`** — now that both text stages exist and are
  gated, these are implementable.
- **p3b's missing `PIC_NOCOUNT`** — carried for ten tasks now.
- **`-DVM_VBLCLOCK` runaway into `$0400-$05FF`** — still unexplained.
- **Two orphan oracle artifacts remain**, `oracle_said.txt` and `row24.txt` (was three;
  `text_events.txt` now has consumers).
- ★ **Consider `text_run.sh` joining `run_gates.sh`** — it is a byte gate outside the suite, which
  is the exact argument that brought `comp` in [T-P0-061 AC-4]. Its cost is the ScummVM capture, not
  the gate itself; the gate over nine titles is seconds.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-08-a-harness-shortcut-manufactures-defects-in-what-it-measures.md`
- `seeds/AGI/live/2026-09-08-the-archived-copy-of-an-instrument-drifts-from-the-instrument.md`

### 11 — Commit
`b51e988` — pushed to origin/wip, and it carries every file in §2 including this report. ★ This line
is corrected by one follow-up commit, since a report cannot name the hash of the commit that
contains it.
