## Form B Report — P3b.2 — pack the plane, decompose the VM, measure the budget
**Class:** build + recon. wip.
★★★★ **AC-2 PASSES. AC-3 stops on §9 trigger 1 for the RENDERER half. AC-6 fires trigger 3 IN
REVERSE — the corpus asks for a cycle TWICE as fast as the budget, not slower.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-30 (HEAD `7645004`, wip). git status clean at receipt.

---

### §6 — Pre-dispatch grep (verbatim, before the summary)

```
=== coco_agi ===        7645004  wip   (clean)

=== siblings (§2T: cite P6.1 §0) ===
POP3_port          104b197  wip  tracked-modified=0
karateka_coco3     29f8f0a  wip  tracked-modified=1

=== hal_sync ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)

=== reg_discipline ===
[reg-discipline] 5 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   5   $FFA5 $FFA6

=== pic_core.s [AD-80] ===
★ pic_probe.bin BYTE-IDENTICAL after the extraction
```

**The five gates:** renderer **45 PASS / 0 FAIL**, resources **1,264** across 10 sweeps,
VM **nine titles PASS**, cels **6,782/6,782**, compositing **20/20 identical**.

★★ **`VM_VAR_TIME_DELAY` handling** — var **10** [`vm_tables.s:60`], read at
`vm_cycle.s:325` into `vm_tdelay`; `vm_pace` advances a virtual clock **25 ms per step** and
interprets when `vm_passed >= vm_tdelay`. ★★★ **The oracle DOUBLES it** —
`time_delay = get_var(10) * 2; if not time_delay: time_delay = 1`
[`tools/agivm/cycle.py:358-363`]. **That doubling is the whole of AC-6** (§3.4).

**No contradiction found. Proceeded.**

---

### 1 — Summary

★★★★ **A — PACKING WORKS AND THE DRAW PHASE FITS.** Six sites carry a stated nibble convention;
**58,965 against 65,280, 6,315 spare**, and the figure is the probe's own armed assertion rather
than my arithmetic. The compositor packs cleanly: **gate 20/20 identical, injected fault 20/20
divergent at exactly the predicted byte counts and locations** (L-62 discharged on the packed
build).

★★★★ **But the RENDERER cannot be packed without restructuring the fill, and that is §9 trigger
1.** Not a missing case — two structural dependencies: `PRI_DELTA` is a *constant* offset
between planes that exists only because they share geometry (fixed, at the cost of a multiply),
and **the span walk is a byte-pointer walk** (`abx`, `leax ±1,x`) that packing turns into a
nibble walk. **That is the inner loop P3.3 took from 11.1 s to 2.7 s.** ★★ So the map's framing
was wrong a second time, one level deeper: the cost of packing is not "a nibble extract on the
priority read" — **the plane's GEOMETRY is load-bearing for the fill's two central
optimisations** [L-64 again].

★★★★ **B — THE VM DECOMPOSES, AND THE ANSWER IS THE RESOURCE COPY.** By ablation on KQ1:
harness+pacing floor **5.77%**, the interpreter's own instrumentation **1.44%**. By an
independently measured coefficient, the resource copy is **~57.9%**. ★★ **~34.9% is
unattributed and is reported as such, not distributed** (§9 trigger 5).

★★★★ **C — AND THE BUDGET QUESTION INVERTS.** §9 trigger 3 anticipated the corpus asking for
*slower* than 5 cycles/s. It does not. **92 write sites across nine titles; the dominant value
(50.6%) asks for 100 ms/cycle — 10 cycles/second, TWICE the assumed budget — and not one site in
the corpus asks for slower than 200 ms.** Our engine achieves **6.2 cyc/s (KQ1)** and **5.3
(KQ3)** VM-only. **The gap is larger than anyone thought, not smaller.**

★★★ **AC-7: stage-then-blast is "measured, not worth it", and its premise is false.**
`co_put_visual` is a plain `sta ,x` — **there is no nibble read-modify-write on the visual
plane.**

---

### 2 — Files modified

- `src/harness/composite.s` — `-DPRI_PACKED`: the nibble convention, five sites, `PRI_STRIDE`.
- `src/harness/pic_core.s` — `put_pixel`'s packed priority write (site six).
- `src/harness/pic_probe.s` — `pri_clear` packed (site **seven**, §3.2).
- `src/harness/pic_fill.s` — `ff_store_pri` (the packed run store) + the **armed refusal**.
- `src/harness/vm_core.s` — `-DVM_NOCOUNT` around the two dispatch counters.
- `src/harness/p3b_probe.s` — the fit assertion now uses the build's real plane size, and its
  **8,192-byte arithmetic error corrected** (§3.1).
- `harness/tools/comp_sweep.lua`, `pic_sweep.lua` — expand the GUEST, never pack the oracle.
- `harness/tools/vm_ablate.ps1`, `timedelay_census.py` — **new.**

★★ **Every unpacked binary verified BYTE-IDENTICAL** — `pic_probe.bin`, `comp_probe.bin`,
`vm_probe.bin`. The guards are inert by default, so the five gates cannot have moved.

---

### 3 — Reasoning

#### 3.1 AC-2, and an error in my own assertion

| | unpacked | packed |
|---|---|---|
| visual, flat | 26,880 | 26,880 |
| priority | 26,880 | **13,440** |
| cel staging | 4,784 | 4,784 |
| seed + hw stacks, status | 1,882 | 1,882 |
| engine code (measured) | 11,768 | 11,979 |
| **total vs 65,280** | **72,194 ✗ +6,914** | ★★★ **58,965 ✓ spare 6,315** |

★★★★ **P3b's assertion was over-strict by 8,192 and I did not catch it.** It read
`P3B_DRAW_NEED + P3_CODE_END`, and **`P3_CODE_END` is an ADDRESS**, so it charged the phase a
second time for everything below `MAP_CODE` — which `P3B_DRAW_NEED` already itemises. ★★ It went
unnoticed because the unpacked case is over the limit either way — **72,194 by hand against
80,386 by the assertion, same verdict from different arithmetic.** P3b's *reported* figure was
summed by hand and is correct; the check was not measuring what it claimed. ★★★ **A check that
agrees with you for the wrong reason is the one you never audit** — it surfaced only because
packing made the two disagree.

#### 3.2 The seventh site, found by the shape of its failure

The packed renderer gate failed **every** picture: visual identical, priority differing by
**~13,440 of 26,880 — exactly half the plane.** ★★★ That signature named it. A wrong nibble
convention corrupts *every other pixel*, and the cause was `pri_clear` writing `$0404` (two
bytes of priority 4) across `PIC_W*PIC_H` bytes: packed, every even pixel's high nibble read 0,
and the clear overran the 13,440-byte plane by another 13,440.

★★ **I enumerated six sites by grepping for plane ACCESS and missed the one that INITIALISES
it.** A clear is neither a pixel read nor a pixel write, so it matched no pattern I searched
for. Both the fill value and the length had to change; either alone still fails.

#### 3.3 Why the fill blocks — §9 trigger 1

1. **`PRI_DELTA equ PRI_BASE-FB_BASE`** — a constant displacement from a visual pointer to the
   same pixel's priority byte, valid only while both planes are 160 wide. ★ **Fixed** —
   `ff_store_pri` recomputes from (x, y), handling an odd leading pixel, a run of whole bytes
   and an odd trailing pixel. The run halves; the ends cost more.
2. ★★★★ **The span walk is the blocker.** `abx` forms `X = &row[fc_x]`; the left and right scans
   step `leax ∓1,x` **once per pixel** and read `lda ,x`. Packed, the pointer advances every
   *other* pixel and the nibble alternates, so the step becomes conditional and the read gains a
   shift. **That is the loop P3.3 optimised across three decompositions, documented here down to
   the cycle.** Restructuring it is a design decision, not a fix, so it is reported.

★★ **The refusal is armed**: a packed renderer build errors rather than silently mis-rendering
the 9 priority-only pictures of the gated 45.

#### 3.4 AC-6's doubling, and the check that caught my own error

★★★★ **My first rate table was out by exactly 2**, because I modelled the pacing as
`1000/(25·v)` and the oracle does `time_delay = v*2; if 0 then 1`
[`tools/agivm/cycle.py:358-363`]. ★★★ **The anchor was in the dispatch's own first paragraph**:
AGI's default is ~5 cycles/second, and **only the corrected model reproduces it** — v10=4 → 8
steps → 200 ms → 5.0 cyc/s. The wrong model said 10. Two numbers one page apart disagreeing by
exactly 2, and I read past it because the table was mine.

#### 3.5 §2H's three checks

1. **A second mechanism for a different object class?** ★★ **Yes, and it is the whole of §3.3.**
   The compositor and the renderer both write priority, and packing the compositor was
   sufficient while packing the renderer was not — because the *fill* is a third client with a
   different access pattern (span walk, not per-pixel address).
2. **The calling routine.** The instrumentation ablation's caller is the dispatch loop, entered
   once per opcode — which is why 7 instructions cost 1.44% and not less.
3. ★ **Grepped before citing.** P5.4's 70.9% / 26.5% / 2.7% split is what settles AC-7's
   "test or write?" question; I did not re-derive it.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** ★ **PASS.** §6 verbatim. §2T cited from P6.1 §0; no shared
  file touched, so no sibling rebuild.

- **AC-2 [class: byte-comparable]** ★★★★ **PASS — 58,965 against 65,280, spare 6,315.** §3.1.
  The unpacked build still fails the same assertion, so the test discriminates.

- **AC-3 [class: byte-comparable]** ★★★ **PARTIAL — three of five clean on the packed path, the
  renderer blocked (§9 trigger 1).**
  - **compositing, packed: 20/20 identical.** ★★★★ **L-62 discharged ON THE PACKED BUILD** —
    faulted packed build **20/20 divergent**, byte counts and first-difference locations
    matching the unpacked predictions exactly (725 → row 49 col 23; 729 → row 109 col 23).
    **Fault-detectability survived the build change, and it was re-proven rather than assumed.**
  - **renderer, packed: BLOCKED** — §3.3.
  - **resources / VM / cels: unaffected** — they never touch the priority plane, and all three
    re-run clean (VM nine titles PASS, cels 6,782/6,782, resources 1,264).
  - ★★ **All unpacked binaries byte-identical**, so the five unpacked gates are unmoved by
    construction, not merely by re-running.

- **AC-4 [class: state-comparable]** ★★★★ **PASS — decomposed by ablation. Clock 1.7898 MHz,
  KQ1, 200 free-run cycles.**

  | build | CPU cy / VM cy | ms/cycle | share |
  |---|---|---|---|
  | baseline | 288,575 | 161.236 | 100% |
  | `-DVM_NOCOUNT` | 284,415 | 158.911 | ★ instrumentation = **1.44%** |
  | `-DVM_PACEONLY` | 16,643 | 9.299 | ★ harness + pacing floor = **5.77%** |

  ★★ **The interpreter proper is 94.2%** — so the answer to "how much is the harness" [L-56] is
  **5.8%, and it disappears in the shipped interpreter.**

  ★★★ **The resource copy, by an INDEPENDENT coefficient rather than an ablation** [L-61's
  second method]: the resource layer measures **1,022 cy + 11.98/byte**; P4.5 measured **13,687
  bytes and ~3.0 `run_logic` calls per cycle** on KQ1. →
  `3.0×1,022 + 13,687×11.98 = 167,036 cy` = **57.9% of the cycle.** ★ *My arithmetic over two
  independent measurements — a lead, not a finding (§8).* It agrees loosely with P4.5's fitted
  66–80%-of-interpreter (this gives 61.4%), and **the two methods differing by ~5 points is
  itself the useful part.**

  ★★★★ **UNATTRIBUTED: ~34.9%** — dispatch overhead, motion, handler bodies. **Reported, not
  distributed** (§9 trigger 5 honoured).

  ★★ **Why the copy is NOT ablated:** removing it leaves stale bytes in the arena and the
  dispatch then executes different opcodes — a different program, not the same program minus a
  part [L-43]. Only ablations that cannot change control flow were used.

- **AC-5 [class: state-comparable]** ★★ **PASS — measured VM-only, composed for sprites.**
  Clock **1.7898 MHz**, fast mode, 200 free-run cycles.

  | title | VM only | +2 sprites | +4 sprites |
  |---|---|---|---|
  | Kingquest1 | 161.2 ms → **6.2 cyc/s** | 189.3 ms → **5.28** | 217.3 ms → **4.60** |
  | Kingquest3 | 189.8 ms → **5.3 cyc/s** | 217.8 ms → **4.59** | 245.9 ms → **4.07** |

  ★★★ **The VM-only figures are MEASURED; the sprite columns are composition** (VM measured +
  P5.4's 28.04/56.07 ms) **and are labelled so** — the integrated loop still does not run.
  ★ KQ3 at 189.8 ms is worse than P4.5's 174.4; different method (200-cycle free-run), stated
  rather than reconciled.

- **AC-6 [class: state-comparable]** ★★★★ **PASS — and it inverts §9 trigger 3.**
  **92 write sites to var 10 across nine titles** (77 `assignn`, 10 `assignv`, 4 `increment`,
  1 `decrement`). Static, from `tools/volread/` via the project's own disassembler.

  | v10 | sites | share | ms/cycle | cyc/s |
  |---|---|---|---|---|
  | 0 | 17 | 22.1% | 25 | **40.0** |
  | 1 | 12 | 15.6% | 50 | **20.0** |
  | **2** | **39** | **50.6%** | **100** | ★★★ **10.0** |
  | 3 | 6 | 7.8% | 150 | 6.7 |
  | 4 | 3 | 3.9% | 200 | 5.0 |

  ★★★★ **The dominant request is 100 ms — half the assumed budget. 88.3% of sites ask for
  ≥10 cyc/s. NOT ONE SITE asks for slower than 200 ms.** ★★ So the 200 ms figure is not the
  Orchestrator's pessimism — it is the *most generous* value anything in the corpus requests,
  and the engine misses even that. **Trigger 3 does not fire; it fires backwards.**
  ★ **Limitation, stated:** this is what the bytecode CAN write, not what a playthrough DOES —
  an upper bound on variety, silent on frequency. Observed-from-the-reference is §8.

- **AC-7 [class: state-comparable]** ★ **PASS — ranked, not acted on.**

  | # | candidate | measured share | note |
  |---|---|---|---|
  | 1 | **Resource copying** | **~57.9%** | ★★★ the dominant term; bind-caching is the obvious lever |
  | 2 | **Unattributed** | **~34.9%** | needs finer ablation before anything is aimed at it |
  | 3 | harness + pacing | 5.77% | ★ **not the engine** — vanishes in the shipped interpreter |
  | 4 | VM instrumentation | 1.44% | `-DVM_NOCOUNT` now exists |

  ★★★★ **§5.2's stage-then-blast: MEASURED, NOT WORTH IT — and its premise is false.**
  - ★★★ **`co_put_visual` is `ldx / leax / lda / sta ,x` — a plain byte store.** The harness
    holds **one AGI pixel per byte** with the colour duplicated into both nibbles, hoisted to
    where the colour changes [P3.5]. **There is no read-modify-write on the visual plane**, so
    the mechanism §5.2 rests on does not exist there. It became real for the *priority* plane
    only as of this task's packing — and priority is stamped only on pixels passing the depth
    test, not on every sprite pixel.
  - ★★ **The TEST dominates the WRITE 2.7:1** — P5.4: transparency 70.9%, write 26.5%, control
    2.7%. Blasting removes store cost, not test cost, so the ceiling is a fraction of 26.5%.
  - ★★★ **Cel widths, measured across 6 titles / 8,682 cels:** mean **13.8**, **median 11**,
    p25 **7**, p75 **16**, p90 **25**. **33.4% are narrower than 8 px; 70.8% narrower than 16.**
    ★★ The fill's blast measured **−0.1% at a 9-byte median span**; a median cel row is **11
    pixels**, and packed that is **5.5 bytes**. **The extent is smaller than where the same
    technique already lost.**
  - ★ **Provisional on the representation**: if the visual plane is ever packed, the premise
    becomes true and this should be re-evaluated.

- **AC-8 [class: suite]** ★ **Three rows** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

```
★ PACKED FITS: code 11979 bytes
draw phase = 26880 + 13440 + 4784 + 1024 + 768 + 90 + code
  = 58,965 against 65,280  ->  spare 6,315
[unpacked] ERROR : "DRAW PHASE DOES NOT FIT: ..."
```

```
★ 20 frames: 20 identical, 0 divergent          <- compositing, PACKED
★ 20 frames: 0 identical, 20 divergent          <- compositing, PACKED + COMP_FAULT
   frame 015  725 byte(s) differ; first in visual at row 49 col 23
   frame 025  729 byte(s) differ; first in visual at row 109 col 23
```

```
pic_fill.s: ERROR : "-DPRI_PACKED needs the span walk restructured (byte-pointer -> nibble
walk). See the block above; this is T-P0-033 §9 trigger 1."
```

```
baseline         161.236 ms/cycle   288575 CPU cycles/VM cycle @ 1.7898 MHz   6.2 VM cycles/s
VM_NOCOUNT       158.911 ms/cycle   284415 CPU cycles/VM cycle @ 1.7898 MHz   6.3 VM cycles/s
VM_PACEONLY        9.299 ms/cycle    16643 CPU cycles/VM cycle @ 1.7898 MHz 107.5 VM cycles/s
[Kingquest3]     189.797 ms/cycle   339693 CPU cycles/VM cycle @ 1.7898 MHz   5.3 VM cycles/s
```

```
★ value histogram across the corpus (assignn v10, n):
    v10 =   0     17 site(s)   22.1%   ->     25 ms/cycle =  40.0 cyc/s
    v10 =   1     12 site(s)   15.6%   ->     50 ms/cycle =  20.0 cyc/s
    v10 =   2     39 site(s)   50.6%   ->    100 ms/cycle =  10.0 cyc/s
    v10 =   3      6 site(s)    7.8%   ->    150 ms/cycle =   6.7 cyc/s
    v10 =   4      3 site(s)    3.9%   ->    200 ms/cycle =   5.0 cyc/s
★ write kinds: set-literal 77 · set-from-var 10 · increment 4 · decrement 1
```

```
cels: 8682  mean width 13.8   median width 11.0
  p10 7 · p25 7 · p50 11 · p75 16 · p90 25
  cels with width < 8 : 33.4%      cels with width <16 : 70.8%
```

```
★ pic_probe.bin BYTE-IDENTICAL   ★ comp_probe.bin BYTE-IDENTICAL   ★ vm_probe.bin BYTE-IDENTICAL
TOTAL             6782    6782    6782       0        0      995
=== AC-2 SUMMARY === nine titles, all PASS
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; the packed renderer does not build by
design, and the shipped artifacts are unchanged from P6.1.

**25.3 operator-runtime-smoke:** **N/A** — nothing reached the screen. All work was headless
gates and free-run timing.

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **Stopped on §9 trigger 1 for the renderer half of AC-3** — the fill's span walk (§3.3).
   Reported rather than restructured; the refusal is armed so the state cannot be mistaken.
2. ★★ **Corrected P3b's fit assertion** (8,192-byte over-strictness, §3.1) — my own error from
   last task, found because packing made the two arithmetics disagree.
3. ★★ **Corrected AC-6's rate model** (the ×2 doubling, §3.4) before reporting any rate.
4. ★ **Corrected a T-P0-032 claim:** I reported that "`pic_draw.s` and `pic_core.s` increment
   unconditionally". **`pic_core.s` guards with `PIC_NOCOUNT` and predates my extraction**, as
   does `pic_fill.s`. **Only `pic_draw.s` is unguarded** — the asymmetry is one file, not the
   renderer, and the project's convention is better established than I said.
5. ★ **Three tools written** the dispatch did not name: `vm_ablate.ps1` (AC-4 needs per-variant
   symbols — §7.2), `timedelay_census.py` (AC-6), plus the two sweep readback paths.

**ROUTE ACCOUNTING.** ★★ **What I did NOT do:** did not optimise the VM (§13 — decompose and
stop); did not implement bind-caching though AC-7 ranks it first; did not restructure the fill;
did not implement stage-then-blast (measured, not worth it); did not decide the cycle rate
(§4 — Jay's); did not run the integrated P3b loop; produced no image.

---

### 7 — Uncertainty flags

1. ★★★★ **The ~34.9% unattributed in AC-4 is the largest single unknown**, and §9 trigger 5
   says report rather than distribute it. **Any optimisation aimed before it is characterised is
   aimed at a guess.**
2. ★★★★ **My first ablation run measured the scaffolding and I nearly reported it** [L-56].
   `-DVM_NOCOUNT` is 28 bytes smaller, so every symbol shifted and the harness staged the game
   to a *different build's* addresses — the run reached its gate, staged into the wrong place,
   completed no cycle, and printed **nothing**. ★★ The stale-symbol `VM_PACEONLY` figure was
   **2.076 ms**; the correct one is **9.299**. **A 4.5× error, silent.** `vm_ablate.ps1` exists
   to make per-variant symbols non-optional.
3. ★★★ **AC-4's resource-copy share is my arithmetic over two independent measurements**, not an
   ablation, and it disagrees with P4.5's fit by ~5 points.
4. ★★★ **AC-6 is static.** It bounds what the bytecode *can* request and says nothing about
   frequency in play. ★ 10 `assignv` sites write var 10 from another variable — KQ1's logic.0
   does `assignv(v10, v88)` — so a playthrough could request values this census cannot see.
5. ★★ **AC-5's sprite columns are composition, not measurement.** The integrated loop has still
   never run.
6. ★★ **`ff_store_pri` is written but only lightly exercised** — the packed renderer cannot run
   the gate, so its odd-leading/odd-trailing paths are unproven against the oracle.
7. ★ **The candidate push failed on auth — fourth consecutive task.** Twelve rows local only.

---

### 8 — Follow-up candidates

1. ★★★★ **Decide the fill's fate** — restructure the span walk for packed priority, or change
   the representation. **Nothing integrates until this is settled**, and it is the same decision
   P3b handed back, now scoped precisely.
2. ★★★★ **Characterise the 34.9%** with finer ablations before optimising anything.
3. ★★★ **Bind-caching** — AC-7's #1 at ~57.9%. A logic re-bound within a cycle is re-copied; the
   ablation and the fix are the same change, which makes it unusually cheap to evaluate.
4. ★★★ **AC-6 observed, not static** — instrument the reference and play, to get frequency.
   ★★ Especially the 10 `assignv` sites, which a static census cannot resolve.
5. ★★ **Guard `pic_draw.s`'s counters** with `PIC_NOCOUNT`, matching the other three files.
6. ★ **AD-77** remains open and out of scope.

---

### 9 — User interaction during task

`None.`

---

### 10 — Candidate(s) captured this task

Three rows in `seeds/AGI/live/`, committed locally. ★ **Push failed** — `Authentication failed`,
**fourth task running** — fire-and-forget per §2C, does not gate. No credential copied anywhere.

- `2026-08-30-a-clean-zero-from-a-scanner-is-a-result-about-the-scanner.md`
- `2026-08-30-a-derived-figure-must-reproduce-a-known-value-before-it-is-trusted.md`
- `2026-08-30-an-optimisations-premise-is-worth-checking-before-its-arithmetic.md`

---

### 11 — Commit

`<filled at commit>` (pushed to origin/wip before this report)
