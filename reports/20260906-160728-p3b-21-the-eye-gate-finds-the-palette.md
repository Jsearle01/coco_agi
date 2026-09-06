## Form B Report — P3b.21 — The eye gate finds the palette; the composite gate cannot fail on priority

**Class:** build. wip. ★★★★★ **TWO TRIGGERS FIRED (1 and 4). This task STOPS.**

---

### §4 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi ===       wip  73f0068  (clean at start)
=== POP3_port ===      wip  104b197  unchanged from P3b.20 §4
=== karateka_coco3 === wip  29f8f0a  unchanged from P3b.20 §4

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s)

gate   artifact                  shipped    fresh  verdict
pic 2642 | pic_nc 2512 | pic_nc_pk 2971 | pic_win 2655 | res 2019
cel 1436 | comp 967 | vm 8712 | p3b 12962          ALL NINE IDENTICAL

clock MEASURED 1.789772 MHz (160009 cycles calibrated)      [L-78]
```

★★ **§2T:** siblings cited from P3b.20 §0, both HEADs unchanged.

★★★★★ **§4 REQUIRES A CONTRADICTION TO STOP THE TASK, AND ONE WAS FOUND IMMEDIATELY.**
`comp_render.py` printed **`★★★ DIFFER`** for all three eye-gate pairs while `plane_pair_diff.py`
reported **0.0%** for the same files. **The tool was wrong** (§3.A). Resolved before AC-1 was
handed over, because handing Jay an image captioned DIFFER would have pre-loaded his verdict.

★★ **§4's flag row [L-77]:** `flag_diff.py --manifest` again lists `PRI_WIN_WRITE` and
`PLANE_PRI_WIN` as ON for the four `pic` rows. **Still false, still open** — carried from P3b.20
AC-9.3 and unfixed here (§11 scope).

---

### 1 — Summary

★★★★★ **AC-1 found a defect no byte gate could reach, which is the third time in five tasks.**
Jay, live: ***"the fills look better… also, the palette looks wrong"***, then ***"in the first room
the trees look unfilled (white) but that could just be a palette issue; for the second the fill
looks good but palette is off as in the first room."***

**He is right, and the cause is a data table, not the renderer.** `gfx_pal16` is **not AGI's
palette**: it is a generic 16-colour ramp in a different order. **AGI index 2 is EGA green; the
table maps it to `$38` = R2 G2 B2 = light grey.** Green foliage rendering as pale grey is exactly
"trees look unfilled (white)". ★★★★ **The planes are byte-identical to the oracle — pictures 1, 22
and 3 are 0 differing bytes on BOTH planes — so the fills are complete and only the colour mapping
is wrong.** ★★ **Not fixed: trigger 1, and §2B independently requires Jay's ruling before
overwriting a palette table.**

★★★★ **AC-4 FAILED and that is trigger 4.** The composite gate **cannot be made to fail on the
priority plane.** `COMP_FAULT` moves the visual plane and **zero priority bytes**, in every
divergent frame of both corpora tested — and there is a structural reason (§3.D), so it is not a
corpus problem and no widening fixes it.

**B delivered anyway:** the composite corpus went from **24 frames, one room, one title** to
**180 frames from nine sources across six titles**, and the widening immediately showed that
**5 of 9 available corpora exercise zero priority rejections.**

---

### 2 — Files modified

- `harness/tools/comp_render.py` — the raw-byte verdict corrected (§3.A).
- `harness/tools/p3b_run.lua` — **`P3B_HOLD`**, so the operator can actually see the gate (§3.B).
- `docs/gates/p3b21_pic{001,003,022}.priority.png` — **ours, committed** (§2P).
- ★ **`src/hal/coco3-dsk/gfx.s` NOT modified** — the palette finding is reported, not fixed.

---

### 3 — Reasoning

#### 3.A ★★★★★ The instrument said DIFFER about planes that match [§4 contradiction]

`comp_render.py:110` compared **raw bytes**: `same = "IDENTICAL" if gv == ov`. The guest doubles
each pixel into both nibbles (`$AA` for colour 10); the oracle writes the bare value (`$0A`). A raw
compare therefore reports a difference on **every pixel of a perfect render**.

★★★★ **The same file already knew better** — `render()` forty lines above masks `& 0x0F` to get the
value, and **its images were correct the whole time.** ★★★ **Only the one-line verdict was wrong,
which is the dangerous shape: the picture looks right and the caption under it says DIFFER.**
Fixed to use the expression the renderer already trusted; all three now read `IDENTICAL`.

★★★ **Third instance of this class** (P3b.15's 97.6%, P3b.19's 99.2%, this) and **the first inside
a committed tool** rather than a scratch script.

#### 3.B ★★★★ An eye gate the operator cannot look at is not an eye gate

Jay: ***"i need a delay after each is displayed to really see for sure."*** `p3b_run.lua` called
`m:exit()` on the frame the cycle count completed, so the room he was being asked to judge was on
screen for a fraction of a second before the window closed. ★★★ **That gate had been run four times
across P3b.14–P3b.20 before anyone said so**, because every previous run was scored from the plane
dump rather than the screen.

`P3B_HOLD` (emulated seconds, default 20 in the launcher) holds the finished picture. ★★ The hold
is tested **before** the report block: placing it after re-ran the whole summary on every frame of
the hold — 900 copies of "final room 22" for a 15-second look.

#### 3.C ★★★★★ The palette [AD-124]

`gfx_pal16` [`gfx.s:800-816`] against AGI's EGA order:

| index | `gfx_pal16` | decodes to | AGI/EGA requires |
|---|---|---|---|
| 1 | `$07` dk grey | R1 G1 B1 | **blue** (0,0,AA) |
| **2** | **`$38` grey** | **R2 G2 B2 = (AA,AA,AA)** | **green (0,AA,0)** |
| 3 | `$3F` white | R3 G3 B3 | **cyan** (0,AA,AA) |
| 5 | `$26` orange | R3 G1 B0 | **magenta** (AA,0,AA) |
| 7 | `$12` green | R0 G3 B0 | **light grey** (AA,AA,AA) |
| 15 | `$33` lt green | R2 G3 B1 | **white** (FF,FF,FF) |

★★★ **Index 2 is the one Jay saw.** Green → light grey is "trees look unfilled (white)".

★★ **The GIME encoding is verified from the file's own `gfx_pal4`, not assumed:** `$26` is
commented *"R=3 G=1 B=0"* and `$19` *"R=0 G=2 B=3"*, which both satisfy
`value = R1<<5 | G1<<4 | B1<<3 | R0<<2 | G0<<1 | B0`. ★ **My derived correct table is arithmetic and
is labelled unverified per §8:** `$00 $08 $10 $18 $20 $28 $22 $38 $07 $0F $17 $1F $27 $2F $37 $3F`.

★★★★ **Why no byte gate could see this.** Every gate compares plane **values** against the oracle's
plane values. **The palette is the map from value to colour and is not in either buffer.** A
perfectly correct plane renders wrong and every gate stays green — which is §4A.1's pattern with a
new instance.

★★★ **Three constraints on the fix, which is why it is reported and not made:**
1. **Trigger 1** — the dispatch says report in full and stop.
2. **§2B** — the RGB palette table is authored content; Jay rules before it is overwritten.
3. ★★★★ **§2M — `gfx.s` is SHARED across three repos.** `gfx_pal16` sits in the shared palette
   block, so a change there is a change to POP and Karateka or it is drift. ★★ **§2M.4 says an
   AGI-only export belongs in `hal_globals.s` (PROJECT_LOCAL)**, and §2M.5 already established the
   shared-mechanism/project-local-data seam for the mode table. **The palette looks like the same
   seam, and that is a design call for the Orchestrator, not a patch.**

#### 3.D ★★★★★ AC-4: the composite gate cannot fail on the priority plane [trigger 4]

`COMP_FAULT` flips `bhi`→`bhs`, so pixels at **equal** priority stop being drawn. Measured on the
two corpora whose staged frames the fault reaches:

```
larry1   frames 163/164/165/170   visual 1642/1612/1606/1566 differ   PRIORITY 0 differ
KQ1ego1  frames 568/569           visual    5/6            differ     PRIORITY 0 differ
```

★★★★ **Zero, everywhere.** And it is **not** because the compositor leaves the plane alone — the
oracle's own dumps say it writes it: **576 of 576 KQ1ego1 frames** change `after.priority` against
`before.priority`, 159 of 319 in larry1, 386 of 398 in PoliceQuest1.

★★★★★ **The reason is structural, and it means no corpus can fix it.** The fault bites exactly at
**equal-priority** pixels. At an equal-priority pixel the priority value the sprite would write is
**the value already there**, so drawing and not-drawing leave the priority plane identical. **A
fault built on the equal-priority boundary can only ever move the visual plane.**

★★★ **Consequence, stated plainly: "BOTH PLANES IDENTICAL" in the composite gate is one claim and
one tautology.** The priority half has never been shown able to fail. ★★ **That is the same
condition that let the fill's priority write stay broken for eleven tasks** [AD-121], which is
exactly what trigger 4 exists to catch. **A different fault is needed — one that perturbs the
priority VALUE written rather than the decision to draw — and designing it is not this task's.**

#### 3.E ★★★ B: the widening, and what it exposed [AC-3, AC-6]

Nine frame sources staged at 20 frames each — **180 frames, six titles, nine rooms/sequences**,
against the previous **24 frames, one room, one title with the ego artificially placed**.

★★★★★ **The widening's real finding is not a defect but a blind spot in the corpora themselves:**

| corpus | candidates | rejected-by-priority | control-branch | fault caught |
|---|---|---|---|---|
| KQ1ego1 (**the old gate**) | 576 | 1,820 | 488 | **2 of 20** |
| KQ1room1 | 566 | **0** | 486 | — |
| KQ1room3 | 384 | 100 | 880 | — |
| KQ1room5 | 403 | **0** | 0 | — |
| Kingquest2 | 100 | **0** | 0 | — |
| Kingquest3 | 571 | **0** | 0 | — |
| larry1 | 319 | **0** | 0 | **20 of 20** |
| PoliceQuest1 | 398 | **15,525** | 0 | **0 of 20** |
| SpaceQuest-1 | 291 | 9,314 | 0 | **20 of 20** |

★★★★ **Five of nine exercise ZERO priority rejections** — `comp_stage.py` warns on each that the
gate *"would pass with the priority test inverted"* [L-38].

★★★★★ **And the two separators are INVERTED, which refutes the dispatch's §3 suggestion.** §3 asks
whether a `priSeed`-style separator is available. **It is — and rejected-by-priority is the wrong
one.** PoliceQuest1 has the most rejections in the set (15,525) and catches the fault **0 times**;
larry1 has **zero** rejections and catches it **20 times**. The separator that predicts fault
detection is **equal-priority pixels**, which `comp_fault_predict.py` already counts:

```
KQ1ego1       2 frame(s) must differ, 18 must not   ->  measured  2 divergent
larry1       20 must differ,  0 must not            ->  measured 20 divergent
SpaceQuest-1 20 must differ,  0 must not            ->  measured 20 divergent
PoliceQuest1  0 must differ, 20 must not            ->  measured  0 divergent
              ★★★ "THE FAULT CHANGES NOTHING ON THIS STAGED SET"
```

★★★ **Prediction matched measurement on all four corpora** [L-27]. ★★ **A corpus can be excellent
at one aspect of the priority test and blind to another**, and one number for "exercises priority"
hides that.

#### 3.F Authority tiers

AC-1's verdict is **Jay's, tier 1**, and the palette conclusion rests on **the source table read as
data** — not on interpreting his screen, and not on any pixel I looked at (§3). Oracle planes are
the reference per §2O.1. §2H: the **second mechanism** is §3.E's two separators; the **caller** is
named at each step; the **prior-report grep** is §4's `flag_diff` item carried from P3b.20.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: eye-gated] — ★★★★★ RUN BY JAY, AND IT FOUND A DEFECT. Trigger 1 fires.**
  Launch path **`poke`**, RGB, live. **Fills: PASS** — *"the fills look better"*, *"for the second
  the fill looks good"*. **Palette: FAIL** — *"the palette looks wrong"*, *"palette is off as in the
  first room"*, and room 1's *"trees look unfilled (white)"* is index 2 → light grey (§3.C).
  ★★★ **P3b's byte work is confirmed by eye; a new defect is opened.**
- **AC-2 [class: byte-comparable] — PASS.** `hal_sync_check` OK in all three; `reg_discipline`
  **8 / 1 file / 2 registers**, unchanged. **All nine gates identical** (§4). §2T: P3b.20 §0.
- **AC-3 [class: byte-comparable] — PASS.** **180 frames, 6 titles, 9 sources**, from 24/1/1.
  All nine corpora **20/20 identical, 0 divergent** on the shipped compositor. ★★ Bound: 20 per
  source is **my choice**, not a limit — candidates run 100–576 (§3.E).
- **AC-4 [class: byte-comparable] — ★★★★★ FAIL. TRIGGER 4.** The gate fails on the **visual** plane
  (40 of 40 frames across larry1 and SpaceQuest-1) and **cannot fail on the priority plane: 0 bytes,
  every divergent frame, both corpora.** Structural, not corpus-dependent (§3.D). **Stopped as
  instructed.**
- **AC-5 [class: state-comparable] — the nine corpora, with bound and its nature:**

  | gate | corpus | of | fraction | bound | constraint or choice? |
  |---|---|---|---|---|---|
  | pic | 45 pictures | 287 reachable | 16% | **1,263-byte poke window** | **constraint, liftable** |
  | pic_nc | same 45 | 287 | 16% | inherits pic | constraint |
  | pic_nc_pk | same 45 | 287 | 16% | inherits pic | constraint |
  | pic_win | same 45 | 287 | 16% | inherits pic; ★ **and does not window** | constraint + defect |
  | res | 10 volumes / 1,264 fetches | — | **not established** | unknown | ★ **still not established** |
  | cel | 6 titles / 9,193 cels | 150 titles | 4% | staging | **choice** |
  | comp | **180 frames / 6 titles** | 3,609 candidates | **5.0%** | 20 per source | **choice** |
  | vm | 9 titles | 150 (12 staged) | 6% | staging | **choice** |
  | p3b | **53 rendered** | 82 KQ1 | **65%** | **vol.0/vol.1 staged only** | **constraint, liftable** |

  ★★ **Six of nine are choices**; two are liftable constraints; **`res` is still not established**,
  carried unresolved from AD-119.
- **AC-6 [class: byte-comparable] — the widening caught NO renderer defect** (9 × 20/20 identical),
  **and that is reported as bounding the risk**, per the dispatch. ★★★ **What it caught instead is
  a defect in the CORPORA** (§3.E): five of nine cannot fail on an inverted priority test.
- **AC-7 [class: state-comparable] — P3b.20's AC-9 and AC-10 items.**
  **CLOSED:** AC-9.1 (all committed tools read both planes — re-confirmed, and `comp_render` was the
  exception found here); AC-10.1, .2, .4, .6 (all landed in P3b.20).
  **OPEN:** ★★★ **AC-9.3 `flag_diff --manifest` over-reports — reproduced again in §4**;
  AC-9.2 `picset.py` selects on one plane; AC-10.3 the 29 unrendered pictures (now AC-5's `p3b`
  row); AC-10.5 duplicates AC-9.3.
- **AC-8 [class: state-comparable] — five things the dispatch did not anticipate.**
  1. ★★★★★ **The palette** — AC-1 found a defect in a data table no gate reads (§3.C).
  2. ★★★★★ **The composite gate's priority half is a tautology** (§3.D), and no corpus fixes it.
  3. ★★★★ **The two priority separators are inverted** — the corpus with the most rejections
     catches the fault least (§3.E).
  4. ★★★★ **`comp_render.py` captioned three correct images DIFFER** (§3.A).
  5. ★★★ **The eye gate was unwatchable** and had been for four runs (§3.B).
- **AC-9 [class: suite]** — see §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — AC-3, the widened composite gate, shipped compositor:**

```
KQ1ego1  KQ1room1  KQ1room3  KQ1room5  Kingquest2  Kingquest3  larry1  PoliceQuest1  SpaceQuest-1
   all nine:  ★ 20 frames: 20 identical, 0 divergent      = 180 frames, 6 titles
```

**25.1 — AC-4, the fault, per plane:**

```
build/comp_fault.bin  967 bytes  (-DCOMP_FAULT; shipped comp_probe.bin untouched)
larry1        20 frames: 0 identical, 20 divergent
SpaceQuest-1  20 frames: 0 identical, 20 divergent
KQ1ego1       20 frames: 18 identical, 2 divergent
PoliceQuest1  20 frames: 20 identical, 0 divergent   ★ the fault is invisible here

frame 163  visual 1642 differ   PRIORITY 0 differ
frame 164  visual 1612 differ   PRIORITY 0 differ
frame 568  visual    5 differ   PRIORITY 0 differ
frame 569  visual    6 differ   PRIORITY 0 differ
★★★ the priority plane never moves -- AC-4 FAILS, trigger 4
```

**25.1 — the oracle DOES write the priority plane (so §3.D is not "nothing writes it"):**

```
frames-KQ1ego1     : 0 frames where after.priority == before.priority, 576 changed
frames-PoliceQuest1: 12 same, 386 changed        frames-larry1: 160 same, 159 changed
```

**25.1 — AC-1's palette, from the source table:**

```
gfx_pal16[2] = $38 = R2 G2 B2 = (AA,AA,AA) light grey     AGI index 2 = EGA GREEN (00,AA,00)
gfx_pal16[15]= $33 = R2 G3 B1                             AGI index 15 = WHITE
encoding verified against gfx_pal4's own comments ($26 "R=3 G=1 B=0", $19 "R=0 G=2 B=3")
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; the nine gate binaries are byte-identical
to their sources (§4).

**25.3 operator-runtime-smoke: ★★★★★ RUN BY JAY, live, `poke`, RGB.** Fills PASS, palette FAIL.
Verdict quoted verbatim in AC-1.

---

### 6 — Reactive deviations and route accounting

- ★★★★★ **TRIGGER 1 FIRED** (AC-1 found what the byte gates did not) — reported in full, **palette
  not touched.**
- ★★★★★ **TRIGGER 4 FIRED** (AC-4 cannot fail on the priority plane) — **stopped.**
- **Trigger 3** partially: `res`'s corpus bound is still not established (AC-5) — reported.
- **ROUTE ACCOUNTING.** I proposed no route. Two changes were made that the dispatch did not ask
  for and both are **instrument, not subject**: `comp_render.py`'s verdict (a §4 contradiction that
  would have prejudiced Jay's verdict) and `P3B_HOLD` (without which AC-1 could not be performed).
  **Neither touches anything under test.** ★ **What I did NOT do:** fix the palette, design a
  priority-capable composite fault, fix `flag_diff`, or widen `res`.

---

### 7 — Uncertainty flags

1. ★★★★ **My corrected palette table is arithmetic and unverified** (§3.C, §8). It should be checked
   against `docs/ground-truth/` before anyone builds it — CLAUDE.md §8 already flags the design
   spec's palette table as Orchestrator arithmetic pending exactly that check.
2. ★★★ **Whether the AGI palette belongs in `gfx.s` or `hal_globals.s` is a design call** (§3.C).
3. ★★★ **AC-4's structural argument is a derivation** — supported by 0 priority bytes across every
   divergent frame in two corpora, but I have not proven no fault could move that plane, only that
   an equal-priority-boundary fault cannot.
4. ★★ **20 frames per source is my choice**, and the per-source candidate pools are 100–576.
5. ★ **`res`'s corpus remains unestablished** across two audits now.

---

### 8 — Follow-up candidates

1. ★★★★★ **The palette** — Jay's ruling, then the table, then where it lives (§3.C).
2. ★★★★★ **A composite fault that perturbs the priority VALUE**, so the plane can fail (§3.D).
3. ★★★★ **Re-stage the composite gate on equal-priority score**, not rejection count (§3.E).
4. ★★★ **Stage the remaining KQ1 volumes** — turns `p3b`'s 53 into 79.
5. ★★★ **Fix `flag_diff --manifest`** — open across two tasks now.
6. ★★ **Establish `res`'s corpus bound.**

---

### 9 — User interaction during task

★★★★ **Jay ran AC-1 and returned three messages**, all quoted verbatim in AC-1 and §3.B/§3.C: a
request for a display delay (acted on, §3.B), *"the palette looks wrong"*, and the per-room detail
distinguishing fills from palette. ★★ **He also asked which items specifically to look at**, and was
given two live commands and one image pair rather than the nine files.

---

### 10 — Candidate(s) captured this task

`seeds/AGI/live/2026-09-06-a-fault-can-be-structurally-unable-to-reach-the-plane-it-gates.md`

---

### 11 — Commit

`b52ba07` (pushed to origin/wip before this report; this §11 hash lands in the follow-up commit).
Pool candidate `fd27cd9` on `methodology-candidate-pool@main`.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
