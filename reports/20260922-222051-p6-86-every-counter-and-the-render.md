## Form B Report — P6.86 — Every counter, and the render decomposed
**Class:** measurement, §1.3's licence NOT exercised.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-22 (HEAD `9c561b3`, wip). `git status` clean apart from an untracked
`coco_agi.code-workspace` that predates this task.

### 1 — Summary
★★★★★ **§4A's answer is NO FOURTH INSTANCE, and that is the task's first deliverable.** The tree
has **three** conditional-instrument families — `PIC_NOCOUNT` (16 sites), `COMP_NOCOUNT` (6),
`VM_NOCOUNT` (5) — **all three already disabled in every shipped arm**, the last of them one task
ago. **No opt-in instrument is `equ`'d in any source file**, and no shipped arm's flag set names
one. ★★★ **So §1.1's "three for three is a class" is confirmed as a class and closed as an
inventory: there is nothing left switched on.**

★★★★★ **§4B: the render is structural and fill-dominated.** 4,881 samples over `P3_PHASE=17`
alone reconcile to **100.0% of 4.894 s**, against the marker's 4.8957 — **the fill subsystem is
63.6%**, and inside it the cost is spread across nine of its own routines with no single defect.
★★★★ **No candidate met §1.3's five criteria, so nothing was taken** — §6's third trigger, and
§4C says either outcome is a pass.

★★★★ **The comment that caused P6.85 is corrected and its shape is named.** `p3b_probe.s`'s *"the
renderer has no such switch"* was false since `pic_fill.s` was written; it is the **third** instance
of *a comment asserting an absence, with nothing able to make it fail*.

### 2 — Files modified
- `src/harness/p3b_probe.s` — **comment only**: §1.2's false sentence corrected with what it cost,
  and the **instrument inventory table** placed in the tree (§9's second delta).
- `harness/tools/pc_profile.py` — `--stage N`, so a profile can be restricted to one `P3_PHASE`.
- `harness/tools/pic_census.py` — NEW: a picture's primitives, and where a picture sits in the
  corpus distribution.

★★★ **All nine arms and all five probes byte-identical** — the `src/` change moves no bytes.

### 3 — Reasoning

#### §3(2) — every conditional instrument, by symbol and by arm ★★★★★ (this is §4A)

**ON BY DEFAULT (`ifndef` — costs unless disabled):**

| flag | sites | counts | disabled in p3b by | live anywhere? |
|---|---|---|---|---|
| `PIC_NOCOUNT` | **16** | fill checks (`fc_count`), line/pixel paths | `p3b_probe.s`, **all arms** [T-P0-138] | no |
| `COMP_NOCOUNT` | 6 | composite pixels tested / written / rejected | `p3b_probe.s`, **COMBINED arm only** [T-P0-130] | ★★★★ **yes — the `p3b` cel arm** |
| `VM_NOCOUNT` | 5 | opcodes and tests seen | `p3b_probe.s`, all arms but `-DP3B_COVERAGE` [T-P0-102] | no |

★★★★★ **The one live counter is deliberate and must stay.** `COMP_NOCOUNT` is defined under
`ifdef P3B_COMBINED`, so the **cel arm `p3b` still counts** — and that file already says why:
*"The cel arm (`p3b`) keeps counting: it is not the shipped build, and gates.manifest's rows for it
quote `co_tested` and `co_rej_pri` as their evidence."* ★★★★ **§6's second trigger exactly — an
instrument a gate needs is not a candidate; the answer is a counting ARM, and one already exists.**
★★ Cost when on, measured: **11.9% of a castle cycle** [P6.76].

**OPT-IN (`ifdef` — free unless a flag is passed), checked rather than assumed:**
`RES_CHECKSUM`, `VM_TRACE`, `VM_IFDIAG`, `VM_SAIDDIAG`, `VM_VAR0DIAG`, `VM_OBJCENSUS`,
`TX_MSGDIAG`, `P3B_SPRSTATS`, `P3B_COVERAGE`, `P3B_CELTEST`, `P3B_VIEWHDR_TEST`, `P3B_PICSTEPS`,
`RES_TEST_TRIMALL`. ★★★ **None is `equ`'d in any source file** (grepped), and **no shipped arm's
flag set names one** — `$BASE`, `$TEXT` and the two combined rows in `p3b_arms_check.ps1` contain
configuration and fault flags only.

★★ **Everything else the `ifndef` census returned is configuration or a fault arm**, not an
instrument: `PLANE_WINDOWED`, `TEXT_MODELLED`, `PIC_WIRED`, `RF_NO_GETSTRING` (a fit-assertion
arm), the `*_FAULT_*` family, and so on. **58 distinct `ifndef` symbols; 3 are instruments.**

#### §3(3) — what each costs, and which have never been measured ★★★
| | measured | cost when on |
|---|---|---|
| `PIC_NOCOUNT` off | ★ yes, T-P0-138 | **29.4% of a room change** |
| `COMP_NOCOUNT` off | ★ yes, P6.76 | 11.9% of a castle cycle |
| `VM_NOCOUNT` off | ★ partly | P6.46: **corrupted game data**; the counters sat inside the arena window |
| every opt-in flag | ★★ **not measured, and does not need to be** | zero unless passed |

#### §3(4) — `pic_render_at`'s structure, and timing inside it ★★★★
A flat dispatch loop: `pic_get` → range-check → `pr_table[op]` → `jsr` → repeat, over eleven
opcodes (`F0`–`FA`, `FF` ends). ★★★★★ **No new markers were needed**: T-P0-138's `-DP3B_PICSTEPS`
already stamps `P3_PHASE=17` for the render's duration, and the profiler records `P3_PHASE` beside
every PC — so `pc_profile.py --stage 17` is the render and nothing else, **without one extra guest
instruction.**

★★★ **Cross-checked against the write-tapped markers, which are exact:**
| step | marker | profile |
|---|---|---|
| clear (15) | 0.2322 s | 0.232 s |
| **render (17)** | **4.8957 s** | **4.894 s** |
| shadow (19) | 0.1749 s | 0.176 s |
| present (21) | 0.1966 + 0.1967 s | 0.393 s (**two** presents in that guest cycle) |

#### §4B — the render decomposed ★★★★★
**Window: `P3_PHASE=17`, host cycle 9, KQ1 room 1, 4,881 samples at 997 Hz, span 4.894 s.**

| class | samples | share | seconds |
|---|---|---|---|
| **fill (`pic_fill.s`)** | **3,102** | **63.6%** | **3.11** |
| picture core (`put_pixel`, `op_*`, `pic_get`) | 692 | 14.2% | 0.70 |
| plane window access | 537 | 11.0% | 0.54 |
| lines (`pic_draw.s`) | 472 | 9.7% | 0.47 |
| MMU phase switches | 56 | 1.1% | 0.05 |
| key scan / IRQ | 22 | 0.4% | 0.02 |
| **SUM** | **4,881** | **100.0%** | **4.89** |

★★★★ **It reconciles: 4.894 s against the marker's 4.8957 — 0.03% apart**, and the classes sum to
100% by construction. **No gap to name.**

**Per routine, inside the render:** `flood_fill` 42.2% · `put_pixel` 10.8% · `draw_line` 9.7% ·
`ff_win_row` 6.2% · `plane_vis` 5.5% · `plane_pri` 4.2% · `ffsp_body` 3.3% · `ff_store` 3.2% ·
`ff_store_pri` 2.8% · `ffp_toggle` 2.1% · `fill_check` 1.7% · `op_rel_line` 1.5% · `ff_push` 1.2%.
★★★ **Top 18 cover 97.8%; 33 routines seen.** `PCs in remapped slots 3-6: 0 samples`.

#### §4B(3) — a denominator, and whether the castle is typical ★★★★
**KQ1 picture 1, 2,752 payload bytes:** 22 `fill` · 235 `rel_line` · 154 `dis_pri` · 63
`set_visual` · 47 `abs_line` · 30 `set_pri` · 19 `x_corner` · 7 `y_corner` · 5 `dis_visual` —
**86 fill SEEDS and 1,423 line POINTS.**

So: **3.11 s of fill over 86 seeds ≈ 36 ms per seed** (141 ms per `fill` opcode), and **0.47 s of
line over 1,423 points ≈ 0.33 ms per point.** ★★★ A fill seed costs about **110× a line point.**

★★★★★ **The castle is typical, slightly above median — NOT an outlier.** Across 287 pictures in
the three pinned titles: **median 16 fills / 60 seeds, max 39 fills / 273 seeds**; the castle is
**22 fills (74th percentile), 86 seeds (72nd)**. ★★★ **So the figure generalises, and the worst
case in the corpus is roughly 3× the fill work** — a room whose render would be ~9 s even after
T-P0-138.

#### §4C — §1.3's five criteria, per candidate ★★★★★

**Candidate 1 — anything from §4A.** ★★★★ **There is none.** The audit found no instrument
switched on that a shipped arm does not need. **Criteria not reached.**

**Candidate 2 — the fill, 63.6% of the render.**

| | criterion | verdict |
|---|---|---|
| 1 | **One cause** | ★★★★ **FAILS.** It is one subsystem but nine routines — `flood_fill` 42.2%, `ff_win_row` 6.2%, `ffsp_body` 3.3%, `ff_store` 3.2%, `ff_store_pri` 2.8%, `ffp_toggle` 2.1%, `fill_check` 1.7%, `ff_push` 1.2%, `ff_win_map` 0.9%. **That is an algorithm's shape, not a defect's.** |
| 2 | **Local, no new mechanism** | ★★★ **FAILS.** Changing it is an algorithm change [P3.3 already took it from 11.102 s to 2.746 s once]. |
| 3–5 | — | not reached |

**Candidate 3 — plane window access, 11.0%.** ★★ **FAILS (2)**: per-pixel address formation is a
mechanism change in an inner loop — **the same candidate P6.84 declined**, and declining it twice
for the same reason is recorded rather than re-argued.

★★★★★ **So nothing was taken. §6's third trigger — "the render's cost is spread with no dominant
class... then it is structural" — fires in its stronger form: there IS a dominant class, and
inside it the cost is still spread.** ★★★ **That is the finding, and §4C says it is a pass.**

#### §1.2's shape, named ★★★★
`p3b_probe.s`'s *"the renderer has no such switch"* is the third of a kind:
| | comment | what it cost |
|---|---|---|
| P6.79 | `res_core.s` *"this is the ONLY routine that writes it"* ($FFA6) | **two shipped defects** |
| P6.71 | `p3b_probe.s` *"no reader"* | a live counter |
| **P6.85** | *"the renderer has no such switch"* | **29.4% of a room change** |
★★★ **A negative claim in prose is the one kind of comment that cannot decay loudly**: the code
stays correct while the sentence stops being true, so nothing ever contradicts it. ★★ Searched for
more of the same shape; **these three are the ones found.**

#### §2S — sibling refs
POP3_port `104b197` (wip), karateka_coco3 `29f8f0a` (wip); both dirty with pre-existing work not
mine. **No `SHARED` file touched**; `hal_sync_check.py` OK. lwasm 4.24 unchanged.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement]** §3(2)'s three tables. ★★★★★ **Three instrument families, all three
  disabled in the shipped arms; one live in a gate arm, deliberately; no opt-in self-enabled.**
- **AC-2 [measurement]** ★★ **N/A — no fix was taken**, so there is nothing to measure separately.
- **AC-3 [measurement]** §4B's table, **reconciling to 100.0% / 4.894 s against a marker's
  4.8957.** No gap.
- **AC-4 [measurement]** §4B's per-routine list and §4B(3)'s per-primitive figures.
- **AC-5 [judgement]** §4C's three candidates, criteria answered. ★★★ **Nothing meets the bar.**
- **AC-6 [state-comparable]** ★★ **N/A — nothing taken**, and the arms prove it: **all nine
  byte-identical**, so no pixel can have moved.
- **AC-7 [byte-comparable · gate]** `src/` changed (comments), so all RUN: `pic` **45 PASS / 0
  FAIL (of 45)**, `cel` **9,193/9,193**, `comp` **124/124**, `res` **1,264/1,264**, `vm` **9/9 (0
  divergent of 600 each)**. ★★★ **All five probes byte-identical**, so these confirm rather than
  test.
- **AC-8 [state-comparable · fault injection]** ★★ **N/A — no fix taken.**
- **AC-9 [state-comparable]** ★★★ **Steady cycle untouched by construction**: the nine arms are
  byte-identical to T-P0-138's, whose steady figures are mean 0.2917 / median 0.2837.
- **AC-10 [suite]** `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green (`all green`);
  ★★ **`-IfRec` still assembles (19,986 B)**; mojibake clean on every touched file.
- **AC-11 [eye gate]** ★★★★ **NOT OFFERED, per the AC's own instruction** — nothing was taken, so
  there is nothing for Jay to look at, and asking would spend his attention on an unchanged
  program.
- **AC-12 [manifest]** ★★ **Not re-baselined: nothing moved.** All nine byte-identical to
  T-P0-138's figures.
- **AC-13** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
=== AC-2 SUMMARY === all nine titles PASS (vm, 600 cycles each, 0 divergent)

★ all 9 arms byte-identical to the recorded baseline (SHA256)
★ every non-p3b probe byte-identical
-IfRec assembles: 19986 B
[reg-discipline] 6 register access(es) in 1 file(s) over 4 register(s).
  src/engine/mmu_phase.s   6  $FFA3 $FFA4 $FFA5 $FFA6
[hal-sync] OK      CHECK OK: vm_tables.s matches optable.py.

§4A  ifndef census: 58 distinct symbols; 3 are instruments.
     PIC_NOCOUNT 16 sites | COMP_NOCOUNT 6 | VM_NOCOUNT 5
     opt-in instruments equ'd in source: NONE

§4B  # window cycles 9-10  hz 997  samples 6139  [--stage 17: only samples with P3_PHASE=17]
     between stages (P3_PHASE=17)  4881  100.0%
     flood_fill 42.2% | put_pixel 10.8% | draw_line 9.7% | ff_win_row 6.2%
     plane_vis 5.5% | plane_pri 4.2% | ffsp_body 3.3% | ff_store 3.2% | ff_store_pri 2.8%
     BY SUBSYSTEM: pic_fill.s 63.6% | picture render 14.2% | plane window 11.0%
                   pic_draw.s 9.7% | MMU phase 1.1% | key scan 0.3% | IRQ 0.1%  SUM 100.0%
     top 18 cover 97.8%; 33 routines seen;  PCs in remapped slots 3-6: 0 samples

     marker cross-check: clear 0.2322 vs 0.232 | render 4.8957 vs 4.894
                         shadow 0.1749 vs 0.176 | present 0.3933 vs 0.393 (two presents)

§4B(3) Kingquest1 picture 1: 2752 bytes, 22 fill, 235 rel_line, 47 abs_line, 154 dis_pri
       ★ fill SEEDS 86   line POINTS 1423
       corpus: 287 pictures  median fills 16  median seeds 60  max fills 39  max seeds 273
       ★★ the castle: 22 fills (74th pct), 86 seeds (72nd pct)
```

**25.2 bundled-artifact grep:** N/A — nine arms and five probes pinned by hash, all unmoved.

**25.3 operator-runtime-smoke:** ★★ **NOT RUN, and deliberately.** No shipped byte changed; AC-11
instructs that the eye gate is offered only if something was taken. **The last observed gate
remains T-P0-138's** (Jay: *"seems shorter" / "yes" / "no"*), and the arms are byte-identical to
the ones he watched.

### 6 — Reactive deviations and route accounting

1. ★★★ **`pc_profile.py --stage N` was added and the dispatch did not ask for it.** §4B wants
   shares that sum to the render (4.89 s) and not to the cycle (6.16 s); the profiler already
   recorded `P3_PHASE` per sample and T-P0-138's markers already stamped it, so a filter was the
   whole cost — **no guest change, no second run.**
2. ★★ **`pic_census.py` is new** — §4B(3)'s denominator and the typicality question had no
   producer. `picset.py` censuses opcodes but requires an oracle tree and writes resource files.

★★★★ **No §2J.5 violation.** Every edit used `Edit`/`Write`; `fix_mojibake --check` clean.

**ROUTE ACCOUNTING.** ★★★★★ **The dispatch offered a licence and it was not exercised, which is
the outcome §4C names as a pass.** **NOT taken, each with the criterion it fails:** the fill
(criteria 1 and 2); per-pixel plane addressing (criterion 2 — **declined for the second time, same
reason**); `COMP_NOCOUNT` in the cel arm (**§6's second trigger — a gate needs it**).

### 7 — Uncertainty flags

1. ★★★★★ **The render is structural and the next step is not a fix.** 63.6% of it is the fill,
   and inside the fill the cost is spread across nine routines. **Any real gain is an algorithm
   change and wants a ruling**, not a licence.
2. ★★★★ **A fill seed costs ~36 ms — about 110× a line point.** That ratio, not the total, is what
   a fill task should start from, and it is measured on ONE picture.
3. ★★★ **The corpus maximum is 273 seeds against the castle's 86.** A worst-case room would render
   in roughly **9 s even after T-P0-138** — so the doorway pause is not uniformly 6.2 s.
4. ★★★ **`COMP_NOCOUNT` remains off in the `p3b` cel arm.** Correct today, because that gate's rows
   read the counters. ★★ **But it means one arm's timings are not comparable to the combined
   arm's**, and nothing in the tree says so at the point a reader would compare them.
5. ★★ **The audit is of the SOURCE TREE, not of the build system.** A flag passed only from a shell
   would not appear in it; `p3b_arms_check.ps1` and `p3b_show.ps1` were read, and `run_gates.sh`
   was not exhaustively audited for instrument flags.
6. ★★ **`VM_NOCOUNT`'s cost when on has never been isolated** — P6.46 recorded the corruption, not
   a percentage. It is disabled everywhere that matters, so the number is of historical interest.

### 8 — Follow-up candidates

1. ★★★★★ **The fill, as an algorithm task with a ruling** — 63.6% of the render, 3.11 s, ~36 ms a
   seed. ★★★ **P3.3 already took the fill from 11.102 s to 2.746 s once**, so the precedent for a
   structural change exists and so does its shape.
2. ★★★★ **The steady cycle's drawing path** — the other speed task, now genuinely next: compositor
   24.3% + cel decode 17.8% + plane access 11.7% of a 0.29 s cycle [P6.84].
3. ★★★ **Say, in the tree, that the `p3b` cel arm counts and the combined arm does not** [§7(4)] —
   one line beside the inventory table, so a future comparison is not made across two cost models.
4. ★★★ **Audit the remaining performance figures against the probe and flags they were measured
   on** [P6.85's follow-up, still open]. ★★★ **Design spec §7.1's `0.039 s/cycle` is `comp_probe`'s
   and is nine tasks flagged.**
5. ★★ **The map ruling** (region A); **the VIEW checksum gap**; **real-time pacing**; **typing
   cadence**; **the title page** items; **`checkPriority`/`checkCollision`**; **`MAP_PRI_BANDS`**
   at `memmap.inc:310` — **the thirty-second task.**

### 9 — User interaction during task
None. ★★ No eye gate was offered, per AC-11: nothing was taken and the shipped bytes are
unchanged.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-22-a-comment-asserting-an-absence.md`

### 11 — Commit
`<hash>`  (pushed to origin/wip before this report)
