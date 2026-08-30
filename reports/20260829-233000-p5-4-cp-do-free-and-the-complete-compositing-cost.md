## Form B Report — P5.4 — `cp_do_free`, and the complete compositing cost
**Class:** build. wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-29 (HEAD `d115392`, wip). git status clean at receipt.

---

### 1 — Summary

**`cp_do_free`'s inflation is fixed, and the compositing cost is now measurable: 14.0% / 28.0% /
42.1% of a second at 2 / 4 / 6 sprites.** ★★★ **T-P0-028's 53% / 106% are WITHDRAWN.** They were
overstated by **3.78×**, and at four sprites the real figure is **28.0%, below the dispatch's ~30%
trigger** — so the §3.6 / §9 re-ranking that T-P0-028 said its number forced is **not forced by
this measurement.**

★★★ **The second finding is larger than the first, and it is bad news about a gate I reported as
good news last task.** T-P0-029 replaced the attract-mode corpus with 80 gameplay frames and
called it strictly better evidence. It is not: **the injected fault that makes the gate mean
anything is undetectable on those 80 frames.** The faulted binary passes them **40/40**. The
gameplay corpus gained the control branch and **silently lost the priority boundary**, and only
the gain was noticed.

★★ Third: `x_liveness.py` now models **three** registers and is clean on the tree — but getting
there produced **three false positives** from a mistake worth naming (§3.4).

---

### 2 — Files modified

- `src/harness/comp_probe.s` — `cp_do_free`: `jsr cp_setup` moved **above** `ldd CP_N`; the
  mechanism documented at the site.
- `harness/tools/x_liveness.py` — `scan_b` parameterised to `scan_reg(lines, regname, WRITE,
  READ, SAFE)`; **D pass added**; `pshs` ordering corrected; `bra`/`lbra` added as block
  terminators; `vm_v0`/`vm_v1`/`vm_v2` added to `B_SAFE`.
- `harness/tests/x_liveness_fixture.s` — the `cp_do_free` shape added as a regression case.
- `harness/tools/build_comp.sh` — **new.** The three `lwasm` variant lines.
- `harness/tools/run_comp_sweep.sh` — **new.** The MAME launch line.
- `harness/mame-cfg/coco3.cfg` — MAME-written, incidental.

★ No `src/engine/**`, no shared HAL file, no game data (§2P).

---

### 3 — Reasoning

#### 3.1 `cp_do_free` — the mechanism, and the diagnosis it replaces

The loop read `ldd CP_N` and **then** `jsr cp_setup`. `cp_setup` ends `lda CP_KEY / sta vc_key`,
so it returns with **A = the cel's clear key**, and D is A:B. The counter became
`(clearKey << 8) | lowByte(CP_N)`:

| clear key | D | repeats | measured |
|---|---|---|---|
| 8 | `$0801` | 2,049 | 696,660 tested for a 340 px cel |
| 3 | `$0301` | 769 | 295,296 for a 384 px cel |
| 0 | `$0001` | 1 | 192 for a 192 px cel — correct |

★★★ **T-P0-029 named the wrong cause.** It reported the defect as firing *"only on frames where
the control branch fires"*. That is a **correlation**: attract cels happen to carry key 0 **and**
happen never to reach a control line; gameplay cels carry keys 8 and 3 and do both. Two properties
moved together across the entire sample and I named the one that explains nothing numeric.

★★ **The falsifying evidence was printed in the report that made the claim.** 2,049 and 769 are
`$0801` and `$0301` — a byte in the *high half*. No story about a branch firing produces numbers of
that shape. A branch firing more often explains *"slower"*; it does not explain *"2,049"*.

★ **Authority tier:** ours — a defect in our harness, not a claim about AGI.

#### 3.2 The corpus finding — a gate that cannot fail

The compositing gate's credibility rests on the injected one-boundary fault (`bhs` for `bhi`, so
equal-priority pixels stop being drawn). Running `comp_fault_predict.py` across **all ten** staged
sets:

| staged set | frames the fault must change |
|---|---|
| **SpaceQuest-1** (attract) | **20 of 20**, 13,466 bytes |
| Kingquest3 | 2 of 20, 42 bytes |
| **Kingquest2** / **-r2** / **-r4**, **PoliceQuest1**, **PQ1gate**, **PQ1gate2** | ★★★ **ZERO — "the gate cannot detect it here"** |

★★★ **Confirmed on the machine, not only in the predictor: the faulted build passes the gameplay
sets 40/40.** The 80/80 pass in T-P0-029 §AC-6 is **real** — the composite *is* byte-identical
there — but for this fault those frames are inert. The r2/r4 frames carry **one sprite**, and a
sprite in open ground never meets scenery at its own depth, exactly as `composite.s:159` predicts.

★★ **The error was a sentence nobody wrote down: *"the gameplay gate supersedes the attract
gate."*** Superseding is a claim about the **old** corpus — that it tests nothing the new one does
not — and I inferred it from a property of the **new** one. Coverage is not ordered by realism.
**The two corpora are complementary and neither should have replaced the other.**

★ **Trigger fired and honoured:** the dispatch's §6 says *"a harness built FOR a measurement is not
exempt from being the defect."* This is the fifth instance [L-13, L-23, L-56, L-61] — and this time
the defect is in the *corpus*, not the code.

#### 3.3 §2H's three checks, applied to the cost model

1. **A second mechanism for a different object class?** ★ Yes, and it is **not** in the fit.
   Save-under restore is a block copy of `xSize * ySize * 2` (sprite.cpp:131), paid **per sprite
   per cycle**, and this probe has **no mode for it** — modes are 2/3/4/5 only. §3.5 below.
2. **The calling routine.** The fit measures `co_composite` only. Its caller in the shipped
   interpreter is the sprite-draw phase, which per design §3.4 declares its MMU pair **once per
   phase, not per sprite** — so remaps are not a per-sprite cost and are correctly outside the fit.
3. ★ **Grepped the reports for the same subsystem before citing.** T-P0-028 §AC-6 and T-P0-029
   §AC-7 disagree about whether 53%/106% stand; **this report settles it against T-P0-028** (§3.6).

#### 3.4 The checker's own defect — kill sets and accusation sets go opposite ways

Extending `x_liveness.py` to D, I wrote WRITE and READ as one matched pair, both narrowed to
16-bit forms. Narrowing READ was right — it suppresses the codebase's ordinary
`jsr vm_getvar / tfr a,b` return idiom. **Narrowing WRITE in the same spirit was wrong** and
produced three false positives, clearest being `vm_passed`:

```
jsr vm_timer_update / lda / jsr vm_getvar / tfr a,b / clra / cmpd #0
```

— code that **fully rebuilds D** before using it. A WRITE set that cannot see `tfr a,b` or `clra`
still believes the pre-call value is live and accuses the `cmpd`.

> ★★★ **They are not two halves of one decision.** WRITE only ever **retires** suspicion, so broad
> is free. READ only ever **raises** it, so narrow is safe. **The safe directions are opposite,**
> and editing them together moves the tool along a diagonal where one side is always wrong.

Two further corrections: **`bra`/`lbra` are block terminators** (a `bra` before a label means
control cannot fall through — this was `pic_draw.s`'s false positive), and **`vm_v0/v1/v2` are
B-safe**, verified by reading (`jsr vm_pN / jmp vm_getvar`, and `vm_getvar` brackets
`pshs b … puls b,pc` at `vm_state.s:182-189`) rather than inferred from the name.

★★ **`pshs` ordering was the miss that mattered.** `pshs d` was matched as a *save* before it could
be seen as a *use*, and the matching `puls d` then cleared the suspicion — so the checker reported
**nothing** on `cp_do_free` itself. A save protects a value across a *following* call; it cannot
un-corrupt one a *preceding* call already destroyed.

#### 3.5 What the cost figure does NOT include — named, not folded in

The dispatch's AC-6 asks for MMU remaps and save-under restore. **Both are outside this number and
I am naming them rather than estimating them into it:**

- **MMU remaps** — correctly outside. Per-phase, not per-sprite (§3.3 check 2).
- **Save-under restore** — ★★ **outside, and it is a real omission, not a negligible one.** It is
  `2 × cel area` bytes saved and restored per sprite per cycle. ★ *My own arithmetic, unverified
  (§8):* at the median 192-pixel cel that is 768 byte-moves; a `ldd ,u++ / std ,y++` loop is ~8
  cycles/byte, so **≈6,100 cycles ≈ 3.4 ms — roughly a quarter again on top of the 14.0 ms
  median.** ★★★ **This is a lead, not a finding.** The probe has no mode for it; measuring it is a
  follow-up (§8), and until measured **14.0/28.0/42.1 are a FLOOR.**

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** ★ **PASS — siblings rebuilt, byte-identical.** §2T.1 trigger 2
  fired (karateka's tree had a modified `harness/smoke/last-run.log`), so I **rebuilt rather than
  cited**. HEADs unchanged from T-P0-029: POP `104b197`, karateka `29f8f0a`; lwasm 4.24 unchanged.
  All five artifacts recorded in T-P0-029 §119-123 match:

  | artifact | T-P0-029 | now | |
  |---|---|---|---|
  | POP `loader.bin` | `56bf6740440c4e0a` | `56bf6740440c4e0a` | ✓ |
  | POP `probe.dmk` | `ec6daccb0b78a9d5` | `ec6daccb0b78a9d5` | ✓ |
  | `karateka.bin` | `9cd20dc537415e80` | `9cd20dc537415e80` | ✓ |
  | `gfxmode3.bin` | `d447c768bd5e6b80` | `d447c768bd5e6b80` | ✓ |
  | `sprite_engine_sandbox.bin` | `543ad8f014bd84d6` | `543ad8f014bd84d6` | ✓ |

- **AC-2 [class: state-comparable]** ★★★ **PASS — 14.0% / 28.0% / 42.1%** of a second at 2/4/6
  sprites. 45 samples, **residuals min +0.0% / max +0.0% / mean 0.0%** — an exact linear fit.
  Per-pixel: **97.18 cycles tested, 79.79 written, 42.19 per control-scan step.**
  ★ Seconds from the **no-count** build, counts from the counted build; the instrument costs
  **1.75×**, which is why they are separated.

- **AC-3 [class: state-comparable]** ★ **PASS.** Clock measured by slope at **1.7894 MHz** against
  the hardware constant 1.7898.

- **AC-4 [class: state-comparable]** ★★ **PASS — two paths agree exactly.** MODE 2 gives
  **916 = 340 + 384 + 192**, the three cels' areas; the fixed MODE 3 now agrees. **37 control hits,
  206 scan steps.**

- **AC-5 [class: state-comparable]** ★ **PASS.** Of the composite's cost: **transparency test
  70.9%**, **write 26.5%**, **control branch 2.7%**. ★★ The control branch is the *cheapest* of the
  three despite being the one that made the corpus swap seem necessary.

- **AC-6 [class: state-comparable]** ★★ **NAMED AS OUTSIDE, NOT FOLDED IN** — §3.5. MMU remaps are
  per-phase and correctly excluded; **save-under restore is a genuine omission** and the figures
  are a **floor** until it is measured.

- **AC-7 [class: byte-comparable]** ★ **PASS — gate unmoved at 80/80** on the gameplay sets,
  **20/20** on SpaceQuest-1. ★★★ **But see AC-8: 80/80 is a weaker statement than it looks.**

- **AC-8 [class: byte-comparable]** ★★★ **PASS on SpaceQuest-1, to the byte — and the finding is
  the corpus, not the fault.** Faulted build: **20 of 20 divergent**, every frame's byte count and
  first-difference location matching the predictor exactly (564 → visual row 138 col 23; 642 → row
  128; 659 → row 115; 664 → row 25; …). Correct build, same set: **20/20 identical.**
  ★★★ **On the gameplay sets the faulted build passes 40/40 — the gate cannot fail there** (§3.2).

- **AC-9 [class: state-comparable]** ★★★ **T-P0-028's 53% / 106% WITHDRAWN.** Replaced by
  **14.0% / 28.0%** at 2/4 sprites — a **3.78× overstatement**, consistent across both points, as a
  constant timing inflation predicts. ★★ **T-P0-029's defence of them does not survive §3.1**: it
  rested on *"zero control hits, so that path was behaving"*, and the control branch is not the
  predictor. **28.0% at four sprites is below the ~30% trigger; trigger 2 does not fire.**

- **AC-10 [class: suite]** ★ **Four rows captured** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, EOL/guard/export-placement normalised)
```

```
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
```

```
src/harness/vm_tables.s          0
src/harness/vm_tests.s           0

0 site(s) hold a register across a clobbering call
```

```
least-squares fit, cycles =
    per source pixel TESTED                       97.18
    per pixel WRITTEN                             79.79
    per control-scan STEP                         42.19
    per composite CALL (harness + prologue)        0.01

residuals: min +0.0%  max +0.0%  mean |0.0|%

AC-6 -- the standing tax, against the ~5 cycles/second AGI runs at:
    sprites          cycles     ms/frame % of a second
    2                 50168        28.04         14.0%
    4                100335        56.07         28.0%
    6                150503        84.11         42.1%
```

```
frames: 20 from build/comp_stage/SpaceQuest-1
  frame 029   2 sprites  ★★★ 564 byte(s) differ; first in visual at row 138 col 23
  frame 045   2 sprites  ★★★ 564 byte(s) differ; first in visual at row 138 col 23
  frame 028   2 sprites  ★★★ 642 byte(s) differ; first in visual at row 128 col 23
  [...]
★ 20 frames: 0 identical, 20 divergent          <- FAULTED build
★ 20 frames: 20 identical, 0 divergent          <- correct build, same set
```

```
=== Kingquest2-r2 (FAULTED build)
★ 20 frames: 20 identical, 0 divergent
=== Kingquest2-r4 (FAULTED build)
★ 20 frames: 20 identical, 0 divergent
```

POP: `=== BUILD COMPLETE ===`, six DECB files `ok`, `VERDICT: PASS`, `[reg-owner] OK — 25 owner
row(s) over 14 register(s)`, `[map_check] 6 map(s) clean`. Karateka: `=== BUILD COMPLETE ===`.

**25.2 bundled-artifact grep:** N/A — no bundled artifact produced this task; changes are to
`src/harness/` and `harness/tools/` only.

**25.3 operator-runtime-smoke:** **pending Jay** — **no image produced this task.** All gates ran
headless via `comp_sweep.lua`; launch path would be `poke`, which does not gate delivery (§4).

---

### 6 — Reactive deviations and route accounting

**Deviations from the dispatch spec:**

1. ★★ **AC-8 was expanded beyond re-running the fault.** The dispatch asks only that the injected
   fault still fail at the expected frame/pixel. It does, on SpaceQuest-1. **I additionally ran the
   predictor across all ten staged sets and the faulted binary against the gameplay sets**, which
   is what exposed §3.2. This is scope I added; the dispatch did not ask for it.
2. ★ **Two wrapper scripts written** (`build_comp.sh`, `run_comp_sweep.sh`) that the dispatch did
   not request. Reason in §10's third row: the invocations existed nowhere on disk and had to be
   reconstructed to run AC-8 at all.
3. ★ **`x_liveness.py`'s D pass** was begun before this report and completed here. It is the
   dispatch's §6 point ("a harness built FOR a measurement is not exempt"), not new scope.

**ROUTE ACCOUNTING.** I proposed no route this task beyond the dispatch's own AC list. ★★ **What I
did NOT do:** I did not measure save-under restore (AC-6 — named as outside, §3.5), did not
optimise the composite (explicitly out of scope), did not touch `src/engine/**`, and **did not make
the §3.6/§9 design call** — the dispatch says *"this task produces the number; the call is Jay's"*,
and the number is 14.0/28.0/42.1 as a floor.

---

### 7 — Uncertainty flags

1. ★★★ **The 14.0/28.0/42.1 figures are a FLOOR, not a total** — save-under restore is unmeasured
   (§3.5). My ≈3.4 ms/sprite estimate is **my own arithmetic and unverified** (§8).
2. ★★★ **The compositing gate's fault coverage is corpus-dependent and now known to be uneven.**
   Until a gameplay corpus with equal-priority pixels exists, **priority-boundary correctness is
   gated only by the attract-mode set.**
3. ★★ **T-P0-029's §AC-7 diagnosis is superseded by §3.1** and its defence of 53%/106% by §AC-9.
   Per §2H check 3, flagging this explicitly so the contradiction is not resolved later by recency.
4. ★ **Sprite COUNT in gameplay is still not established** — carried unchanged from T-P0-028. The
   2/4/6 columns are a scale, not a prediction of what a room actually draws.
5. ★ **The candidate push failed on auth** (§10); rows are committed locally only.

---

### 8 — Follow-up candidates

1. ★★★ **Measure save-under restore on the target** — a MODE 6 in `comp_probe.s`. It is the last
   unmeasured per-sprite cost and it moves the floor.
2. ★★★ **Build a gameplay corpus containing equal-priority pixels** so the fault gate is live on
   gameplay too. The oracle console's `position(0, x, y)` (T-P0-028 §454) can place the ego onto an
   occluding spot deterministically — that was already proposed for AC-9's image and now has a
   second, stronger reason.
3. ★★ **Run `comp_fault_predict.py` as a standing pre-check on every corpus change**, printing
   which sets can and cannot detect each injected fault. One loop; it caught §3.2.
4. ★ **Extend `x_liveness.py` to U and Y** — three lines each now that `scan_reg` is parameterised.
5. ★ **Resolve `Kingquest2-r3`/`KQ2-r1` frames-dir mismatch** — the predictor produced no summary
   for either (`frame100.before.visual.bin` missing from `frames-Kingquest2`), so two staged sets
   are currently unassessed for fault coverage.

---

### 9 — User interaction during task

Jay sent **"continue"** once, mid-task, with no change of scope. ★ No other interaction; §25.3 was
not exercised and no PNG was produced (§3).

---

### 10 — Candidate(s) captured this task

Four rows in `seeds/AGI/live/`, committed locally. ★ **Push failed** — `remote: Invalid username or
token` — fire-and-forget per §2C, does not gate. No credential copied anywhere (§2C).

- `2026-08-29-a-better-corpus-can-silently-remove-the-coverage-that-made-the-gate-evidence.md`
- `2026-08-29-a-correlation-across-a-uniform-sample-names-the-wrong-cause-with-full-confidence.md`
- `2026-08-29-a-liveness-checkers-kill-set-and-accusation-set-must-be-widened-in-opposite-directions.md`
- `2026-08-29-the-unsaved-script-rule-applies-to-the-command-that-launches-the-gate.md`

★ The register-liveness recurrence (third instance, in D) is a recurrence of the existing row
`an-instrument-that-models-one-register-cannot-see-the-same-defect-in-another`; per §2C I did not
edit it — folding is the reconciler's read-time job.

---

### 11 — Commit

`<filled at commit>` (pushed to origin/wip before this report)
