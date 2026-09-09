## Form B Report — P6.27 (T-P0-083) — rollover, and the parse boundary
**Class:** build (measurement-first).  wip.

★★★★★ **Leading with the negative, as §8 asks.** The signature is **NOT produced**, and the hypothesis
that motivated the task is **disproven rather than merely unconfirmed**: at every arm, the buffer
`par_parse` reads is byte-identical to the buffer the host reads afterwards. **This is §7 trigger 3.**

★★★★ **Rollover is characterised and it is well-behaved**: it defers keystrokes, it does not lose or
reorder them. ★★★ **One new behavioural fact did come out of it** — a character key closed in the
*same frame* as ENTER is discarded — recorded in §3.4.

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-083 dispatch receipt (HEAD `e8a121b`, wip; descends from `25121b2` as the dispatch expected).
`git status` clean but for `coco_agi.code-workspace` (untracked editor file, deliberately unstaged).

---

### §3 — Pre-dispatch grep (C-13), verbatim, before the summary

```
=== coco_agi ===        e8a121b  wip   ?? coco_agi.code-workspace
=== POP3_port ===       104b197  wip   (no tracked modification)
=== karateka_coco3 ===  29f8f0a  wip    M harness/smoke/last-run.log
```

★★ **§2T citation, with P6.26 §3's caveat carried forward unchanged.** POP `104b197` and Karateka
`29f8f0a` are **the same refs P6.26 §3 recorded**, read the same way — at their **`wip` working
trees**, not at a public ref (§2S). Neither has a tracked source modification; Karateka's single
tracked change is `harness/smoke/last-run.log`, a run log, and both repos' untracked material is
`docs/ground-truth/` PDFs, gitignored under §2.2 and invisible in any clone.
★ **No sibling artifact is built or claimed here** — this task touches no HAL file and no
`src/engine/` file — so §2T's "the after-build is still required in full" does not engage.

```
=== hal_sync from coco_agi ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
=== from POP3_port ===
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, ...)
=== from karateka_coco3 ===
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, ...)

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s     8    $FFA5 $FFA6
```

**Flag set, enumerated not confirmed [L-77]:**
`lwasm --6809 -f raw -DHAL_KEYBOARD=1 -o build/input_probe.bin --map=build/input_probe.map -I. src/harness/input_probe.s`
→ **3,734 B at grep time**, matching the dispatch's expectation. ★ It is **3,750 B** for the rest of
this report: the 16 bytes are `IP_SNAP` and its copy loop, added by this task (§3.2).

**Staged vocabulary [L-111]:** `build\vm_stage\Kingquest1\words.tok`, **3,144 bytes**, printed by the
runner *and* by the Lua on every run. ★ Not `oracle_words.bin`.

**P6.26's negative still holds:**

```
1 plain  (first line)  keys=13 curpos=12 entered=1  egon=2  words=2,37
2 backsp (reopened)    keys=15 curpos=12 entered=1  egon=2  words=2,37
3 plain  (reopened)    keys=13 curpos=12 entered=1  egon=2  words=2,37
4 backsp (reopened)    keys=15 curpos=12 entered=1  egon=2  words=2,37
5 FAULT  (rockk, none)  keys=14 curpos=13 entered=1  egon=2  words=2,0
  fault arm 5 vs arm 1 : DIFFER -- the instrument can go red
  ★★★ NO DIVERGENCE REPRODUCED -- all four arms parse alike [trigger 1: stop]
```

★ **No contradiction found. Proceeding.**

---

### 1 — Summary

`IP_SNAP` was added to the probe: **the guest's own copy of `IP_INBUF`, taken immediately before
`jsr par_parse`.** Every buffer reading on record until now was taken by the host, frames later,
**on the far side of the thing in doubt**. Comparing the two answers P6.26 §8's open question
directly.

**The answer is no.** Across six arms — plain, character-one-frame-before-ENTER,
character-simultaneous-with-ENTER, character-held-across-ENTER, full-line rollover, and a
rollover-typed junk line — **the snapshot equals the after-read every time**, while the fault arm,
whose buffer the host deliberately altered, differs. `par_parse` sees exactly what the host later
shows.

**Rollover was characterised** (§3.3): resolution is by scan order, deterministic, order-independent,
and the losing key is **deferred, not dropped**. A rollover-typed `look at rock` yields
`LOOK AT ROCK` → `egon=2, words 2,37`, identical to the one-key-at-a-time control.

**The signature `egon=1, words=0` from a readback of `LOOK AT ROCK` was not produced by any arm.**

### 2 — Files modified

- `src/harness/input_probe.s` — `IP_SNAP` (`$4700`, 48 B) and a copy loop before `jsr par_parse`.
  3,734 → 3,750 B. ★ **Instrumentation only**: nothing reads `IP_SNAP` but the host, and the buffer,
  the parser and the boundary are all exactly where they were.
- `harness/tools/rollover_probe.lua` — **NEW.**
- `harness/tools/input_run.ps1` — a `-Rollover` arm; the output filter rewritten in ASCII (§3.5).

★★ **AC-8: no engine or HAL file was touched.** `git diff --stat HEAD -- src/engine/ src/hal/` is
**empty**; `git diff HEAD -- src/engine/getstring.s` is **0 lines**.

### 3 — Reasoning

**3.1 ★★★★ The hypothesis, and why it was worth a task.**

P6.26 §8 inferred — and labelled as inference — that `par_parse` may have seen a buffer the host's
read did not show, because `egon=1, words=0` means *one non-ignore group, unknown*, which
`LOOK AT ROCK` does not produce under any arm. ★★★ **That inference was correct in its reasoning and
its conclusion is now falsified by measurement**, which is exactly what a labelled inference is for.

**3.2 ★★★★★ `IP_SNAP`, and why the host could never have answered this.**

The host reads `IP_INBUF` when it sees `IP_DONE == 1` — after `gs_finish`, after `par_clean`, after
`par_parse`, and after the guest has gone back to scanning. ★★★ **A reading taken there cannot
distinguish "the parser saw this" from "the parser saw something else and the buffer was rewritten
before you looked".** The snapshot is taken by the guest, in the same instruction stream, immediately
before the call. **The comparison is only meaningful because the two readings straddle the doubt.**

**3.3 ★★★★★ AC-1: the resolution rule, MEASURED, not read from the source.**

| both keys down | winner | when the winner lifts |
|---|---|---|
| L(r1,c4) + K(r1,c3) | **K** | K (K held) |
| O(r1,c7) + N(r1,c6) | **N** | N |
| L(r1,c4) + D(r0,c4) | **D** | D |
| L(r1,c4) + R(r2,c2) | **R** | R |
| **R(r2,c2) + L(r1,c4)** — reverse assertion order | **R** | **L arrives** |
| L then K, 3-frame stagger | **K** | K |
| K(r1,c3) + CLEAR(r6,c1) | **CLEAR `$08`** | CLEAR |
| K(r1,c3) + ENTER(r6,c0) | **ENTER `$0D`** | ENTER |

★★★★ **The rule: the lower COLUMN index wins; a tie on column is broken by the lower ROW index.**
Every row above follows it — c3<c4, c6<c7, c2<c4, c1<c3, c0<c3, and D beats L on row 0 vs row 1 at the
same column 4. ★★★ **It is order-independent**: `R+L` and `L+R` both resolve R, so it is scan
priority and not "first pressed" or "last pressed". ★★ **Deterministic**: two full runs are
byte-identical [L-30].

★★★★★ **And the loser is DEFERRED, not discarded.** The `R+L` row is the direct evidence: zero new
events while both are down, then **L arrives the instant R lifts**. ★★★ **This is why rollover does
not corrupt a typed line.** The first key of any pair always registers on its own press — nothing
else is down at that moment — and the second registers either immediately (if it outranks the first)
or on the first's release. **Order is preserved in both cases, and nothing is duplicated**, because
once the winner is latched a scan resolving the same key is not a new event.

★★ **Untested limit, stated rather than implied: three or more keys down at once.** Every pairing
here is exactly two.

**3.4 ★★★★ A new behavioural fact, from the arm that had to be built twice.**

★★★ **B2 was mislabelled and B4 is the real test.** The step machine runs one step per frame, so
B2's two `press` steps are two *frames* apart: K was alone for one frame, registered as an ordinary
keystroke, and only then did ENTER arrive. **A sequential case wearing a simultaneous label** — its
buffer reads `LOOK AT ROCKK`. B4 closes both fields in a single frame.

★★★★ **B4's result: `LOOK AT ROCK` — the character is LOST, not deferred.** ENTER outranks K (c0<c3),
so K never becomes an event; the line submits; and when the line reopens both keys are still down, so
ENTER stays latched and K never gets its turn. ★★ **A character closed in the same frame as ENTER is
discarded.** Reported as a finding; **no fix is proposed and none is in scope.**

**3.5 ★★★★ AC-2's answer, and the fault arm that makes it worth believing.**

All six real arms: **snapshot == after-read**, byte for byte across 48 bytes. The fault arm — where
the host poked `$5A` into `IP_INBUF+2` after the guest had snapshotted — **differs**, and its verdict
is printed **first**, ahead of the six it validates [L-113, now standing practice per AC-4].

★★★ **Without the fault arm this run's most likely wrong answer was "they all match".** Six arms
compared only against themselves agree for many reasons unrelated to the question — a stale snapshot
address, a probe built before `IP_SNAP` existed, the same 48 bytes read twice. **The Lua refuses to
run at all if `IP_SNAP` is absent from the map**, which is the same guard in a second place.

**3.6 ★★★★★ Five defects in my own instrument, each of which produced a plausible port defect.**

★★★★ **Every one of them was caught by a contradiction in the output, not by review**, and each is
recorded because the readings they produced are exactly the shape this subsystem has been mistaken
about four times.

| # | the instrument did | it read as |
|---|---|---|
| 1 | held each key a fixed 4 frames | the opening `L` never registered → **`OOK AT ROCK`**, a port dropping a character |
| 2 | B3 released ENTER, then K two frames later | K alone became a new event in the **next** arm's line → **`KLOK AT ROCK`** |
| 3 | `set_value(1)` on an already-closed field | a doubled letter is a no-op → **`LOK`** for `look`, rollover "losing" input |
| 4 | sampled the `waitkey` baseline at the wait | **6 of 12 keystrokes reported "dropped"** while the line came out perfect — *it reported drops for the keys that worked fastest* |
| 5 | put a `★` in a PowerShell `-Pattern` | PS 5.1 reads a BOM-less UTF-8 `.ps1` as ANSI, so it matched nothing — **the driver's report and the final verdict were filtered out while every supporting table survived** |

★★★★★ **#5 is the one worth carrying.** The filter removed **only the conclusions** and kept all the
evidence, so the run looked complete and simply had no verdict. ★★★ **A filter that drops the
strongest claims and keeps the tables is worse than one that drops everything**, because nothing looks
wrong.

★★★ **#4 is the sharpest measurement error**: the baseline was read *after* the stimulus, so the
fastest responses — the keys that registered during the overlap — had already incremented the counter
and looked like timeouts. **The tell was the contradiction**: 6 dropped keystrokes and a correct line.

**3.7 ★★ §2H's three checks.**

1. **A second mechanism for another object class?** Yes, and this task adds the fourth view: delivery,
   decoding, host binding [AD-165], and now **arbitration** — what the decoder does when the matrix
   reports more than one key. ★ It is a property of `HAL_key_scan`'s loop order, not of any table.
2. **The calling routine.** The snapshot sits in `ip_entered`, the probe's own caller, between
   `gs_finish` and `par_parse` — **the caller owns the boundary**, so the measurement is at the seam
   rather than inside either routine.
3. **Grep the reports for the same subsystem.** P6.23 blamed delivery; P6.24 disproved it; P6.25
   blamed debounce and the cause was a UX change; P6.26 eliminated backspace and reopening. ★★★ **This
   is the fifth report and the first to close a hypothesis by disproof rather than by non-reproduction.**

**3.8 ★★ Authority tier.** No ScummVM or Specs claim is made. Everything is measured from the port
running under MAME, plus KQ1's own `WORDS.TOK`. ★ The one semantic used — unknown word → 0, ignore
words dropped — was **measured** in P6.26 arm 5 and is re-observed here in B2/B3 (`2,0`).

### 4 — Verification (AC-by-AC)

★ **Per L-112, each AC names what observed it; no PASS covers two classes.**

- **AC-1 [state-comparable · observed by: field assertion + guest readback]** **PASSED.** Resolution
  rule measured and stated (§3.3): lower column wins, ties by lower row; deterministic;
  order-independent; loser deferred not dropped. **Two runs byte-identical** [L-30].

- **AC-2 [byte-comparable · observed by: guest snapshot vs host memory read]** **PASSED.**
  `IP_SNAP` and `IP_INBUF` dumped 48 bytes for all seven arms. ★★★ **They never differ on a real arm**,
  and differ on the fault arm. **Trigger 1 does not fire.**

- **AC-3 [state-comparable · observed by: guest parse result + host readback]** ★★★★★ **NOT
  PRODUCED — and that is a result, not a failure.** No arm yields `egon=1, words=0` from a readback of
  `LOOK AT ROCK`. The full-rollover arm S1 yields `LOOK AT ROCK` → `egon=2, words 2,37`, identical to
  the control. ★★ The only `egon=1, words=0` in the run comes from the pair-test junk line
  `LKONLDLRRLLKK`, whose single unknown word makes it the expected result, not the signature.

- **AC-4 [state-comparable · observed by: fault injection]** **PASSED, adjudicated FIRST.** The host
  poked `$5A` into `IP_INBUF+2` post-parse; the comparison reported `DIFFER`. ★ It is this task's own
  comparison, not arm 5 recycled, and the Lua exits early if it comes back blind.

- **AC-5 [state-comparable · observed by: the arm table itself]** **PASSED.** Three variables named —
  V1 rollover, V2 timing offset, V3 ENTER boundary — and every arm prints which it moves and which it
  holds. B1 moves none; B2/B3/B4 move V3 at three offsets; S1 moves V1 with V3 fixed; the pair arms
  move V1/V2 with V3 fixed; the fault arm moves none of the three and perturbs the comparison instead.

- **AC-6 [byte-comparable · observed by: the runner's output]** **PASSED.** All runs via
  `input_run.ps1 -Rollover` / `-Repro`; no hand-typed MAME or `lwasm` line. Vocabulary path and size
  printed by runner and Lua.

- **AC-7 [suite · observed by: byte gates]** **PASSED.** `★ gates run: pic res cel comp p3b -- all
  green`; `hal_sync_check.py` OK ×3; `reg_discipline.py` 8 in `mmu_phase.s`, unchanged.

- **AC-8 [state-comparable · observed by: git]** **PASSED.**
  `git diff --stat HEAD -- src/engine/ src/hal/` **empty**; `git diff HEAD -- src/engine/getstring.s`
  **0 lines**. ★ AD-167 and AD-169 untouched; echo still uppercase in every dump.

- **AC-9 [suite]** Two candidates captured; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).** §3's grep is above. Two runs of the rollover arm are
line-for-line identical (`Compare-Object` → `RUN 1 AND RUN 2 IDENTICAL`, 77 lines each):

```
=== §2W: can the snapshot-vs-after comparison say DIFFER? [adjudicated first] ===
  FAULT arm -- host poked $5A into IP_INBUF+2 after the parse: DIFFER -- the comparison can go red
★ driver: every scripted keystroke became a counted event (none dropped)

=== AC-1: two fields asserted at once -- what HAL_key_scan resolved ===
  window                          events  codes resolved
  same row  L+K (both down)         1    $4B'K'
  same row  L+K (A released)        0    $4B'K'
  same row  O+N (both down)         1    $4E'N'
  same row  O+N (A released)        0    $4E'N'
  same col  L+D (both down)         1    $44'D'
  same col  L+D (A released)        0    $44'D'
  diff both L+R (both down)         1    $52'R'
  diff both L+R (A released)        0    $52'R'
  diff both R+L (both down)         0    $52'R'
  diff both R+L (A released)        1    $4C'L'
  stagger   L>K (both down)         1    $4B'K'
  stagger   L>K (A released)        0    $4B'K'
  with CLEAR K+C (both down)        1    $08
  with CLEAR K+C (A released)       0    $08
  with ENTER K+E (both down)        1    $0D
  with ENTER K+E (A released)       0    $0D

=== AC-2: IP_SNAP (guest, at `jsr par_parse`) vs IP_INBUF (host, after) ===
F  FAULT  host pokes buffer post-parse   [nothing -- it perturbs the COMPARISON, not the guest]
   snap  |LOOK AT ROCK.???????????????????????????????????|
         4C 4F 4F 4B 20 41 54 20 52 4F 43 4B 00 FF FF FF ...
   after |LOZK AT ROCK.???????????????????????????????????|
         4C 4F 5A 4B 20 41 54 20 52 4F 43 4B 00 FF FF FF ...
   ★★★ SNAPSHOT DIFFERS FROM AFTER-READ
B1 ENTER alone (control)            ★ snapshot == after-read
B2 K one frame before ENTER         ★ snapshot == after-read
B4 K and ENTER closed in ONE frame  ★ snapshot == after-read
B3 K held right across ENTER        ★ snapshot == after-read
S1 rollover across the whole line   ★ snapshot == after-read
P  with ENTER K+E                   ★ snapshot == after-read

=== AC-3: the signature -- egon=1, words=0 from a readback of LOOK AT ROCK ===
  F  FAULT  host pokes buffer post-parse   keys=13 readback=[LOZK AT ROCK] egon=2 words=2,37
  B1 ENTER alone (control)                 keys=13 readback=[LOOK AT ROCK] egon=2 words=2,37
  B2 K one frame before ENTER              keys=14 readback=[LOOK AT ROCKK] egon=2 words=2,0
  B4 K and ENTER closed in ONE frame       keys=13 readback=[LOOK AT ROCK] egon=2 words=2,37
  B3 K held right across ENTER             keys=14 readback=[LOOK AT ROCKK] egon=2 words=2,0
  S1 rollover across the whole line        keys=13 readback=[LOOK AT ROCK] egon=2 words=2,37
  P  with ENTER K+E                        keys=16 readback=[LKONLDLRRLLKK] egon=1 words=0

  ★ signature NOT produced and every snapshot matches its after-read
    -- a clean negative, not a failure [trigger 3]
```

★ The `B1/B2/B3/B4/S1/P` rows above are abbreviated to their verdict lines; the full 48-byte snap and
after dumps for each are in `build/p6_27_w1.log` and are byte-identical within each arm.

Suite:

```
★ gates run: pic res cel comp p3b  -- all green
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s     8    $FFA5 $FFA6
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact. `input_probe.bin` is a harness binary
(3,750 B).

**25.3 operator-runtime-smoke:** **N/A.** Headless throughout: `-video none -sound none -nothrottle`.
Nothing reached a screen and no eye gate is claimed.

### 6 — Reactive deviations and route accounting

**Deviation 1 — `IP_SNAP` added to `src/harness/input_probe.s`.** Scope §4B asks for a dump "at the
parse boundary", which no host-side read can take. ★★ Instrumentation in a harness probe, not a
behaviour change; nothing reads it but the host.

**Deviation 2 — arm B4 added.** B2 was specified and built as "ENTER + K same frame" and **was not
that** (§3.4). Rather than relabel it and leave the edge untested, B4 tests the genuine case and B2
was renamed to what it actually does. ★★ It produced the one new behavioural fact in this report.

**Deviation 3 — the runner's output filter rewritten.** Not scope; it silently removed the verdict
lines (§3.6 #5) and a task whose deliverable is a verdict cannot ship a filter that deletes it.

**ROUTE ACCOUNTING.** ★★★★ **P6.26 §8 proposed testing rollover and named it the one remaining
difference. This task contains that test in full, and it comes back negative.** ★★★ What this report
does **not** contain, and did not attempt: any fix, any explanation of the original observation, and
any further variant hunting after the negative. ★★ **The B4 arm is the only work done after the first
clean negative, and it validates the boundary claim rather than trying to overturn it.**

★★★ **The dispatch's standing intent (§7 trigger 3) is engaged, and I concur on the evidence**: §7.1
is unreproducible under every controlled variable this project can now drive — backspace, reopening,
rollover, and the ENTER boundary — and the buffer the parser reads has been shown to be the buffer the
host reports. **The recommendation is to close it; the ruling is Jay's.**

### 7 — Uncertainty flags

1. ★★★ **Three or more keys down at once is untested.** Every pairing is exactly two. A rollover
   typist can hold three; the resolution rule measured here predicts the lowest-column key wins, but
   **that is extrapolation, not measurement**.
2. ★★★ **The original line is still unexplained and no longer exists.** This report disproves a
   mechanism; it does not explain the observation. ★★ **`egon=1, words=0` remains what a one-word
   unknown buffer produces**, and no controlled input has yet produced that buffer from `look at rock`.
3. ★★ **A character closed in the same frame as ENTER is lost** (§3.4). Measured, unfixed, and no
   judgement offered on whether it should be.
4. ★★ **The driver's timing is frame-quantised.** One step per frame means the finest overlap this
   instrument can express is one frame (~16.7 ms emulated). **A human's rollover overlap can be
   shorter than the guest's scan interval**, which this cannot reproduce.
5. ★ **Single title, KQ1**, as scoped.

### 8 — Follow-up candidates

- ★★★ **Close §7.1** per trigger 3, at Jay's ruling.
- ★★ **AD-169's ruling** (wipe vs terminate) — this task adds evidence: the residue appears in S1's
  snapshot as the second `00` and is inert, because `par_clean` stops at the first terminator on both
  sides of the boundary. **Evidence for the ruling, not the ruling.**
- ★★ **Decide whether a character lost at the ENTER boundary matters** (§3.4). It is one frame wide
  and needs a real decision rather than a reflex fix.
- ★ **Three-key rollover**, if §7.1 is ever reopened.

### 9 — User interaction during task

**None.** ★ Headless start to finish; no eye gate and no operator input.

### 10 — Candidate(s) captured this task

Two, to `seeds/AGI/live/`:

- `2026-09-09-a-filter-that-drops-only-the-conclusions-is-worse-than-one-that-drops-everything`
  — *initiator: executor*. §3.6 #5: a non-ASCII literal in a PowerShell `-Pattern` matched nothing, so
  the run printed every supporting table and no verdict, and looked complete.
- `2026-09-09-take-the-baseline-before-the-stimulus-or-the-fastest-cases-look-like-timeouts`
  — *initiator: executor*. §3.6 #4: the progress check sampled its counter after the keypress, so keys
  that registered fastest had already incremented it and were reported as drops.

★ **No candidate for defects #1–#3** — they are ordinary driver bugs caught by their own output, not
principles this project lacks.

### 11 — Commit

`645ffef` — pushed to origin/wip before this report.
