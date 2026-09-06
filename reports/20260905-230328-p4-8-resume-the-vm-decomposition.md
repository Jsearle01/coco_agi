## Form B Report — P4.8 — resume the VM decomposition, with a working instrument

**Class:** recon. wip. Calibration-light — receipt stamp only.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-05 (dispatch carried no explicit receipt timestamp; report written 2026-09-05T23:03:28-04:00).

---

## §4 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `wip` @ **`d3037bd52c4a272f6dca480c52c7a08734e5ff19`**, `origin/wip` identical |
| `git status` | **clean** — see the correction below |
| POP + Karateka | §2T cite INFRA.1 §0; register figures drifted [AD-104], recorded not chased (§11) |
| `hal_sync_check.py` | **OK in all three repos** |
| the five gates, fresh builds | §2T cite INFRA.1 §4 + byte-identity, see AC-1 |
| **flag sets — enumerated and diffed** | **8/8 artifacts identical** to what their sources build now |
| **the clock — measured** | **1.789417 MHz (640,000 cycles calibrated, this session)** |
| **`opcount` on the pace-only arm** | **`opcount=0`**, `vm_cycle=0 of 201` — confirmed before any other arm was trusted |

### ★★ CORRECTION to §4's premise, reported before the summary

> §4 states: *"INFRA.1 found `vm_probe.s` modified relative to HEAD; that is live work and it is what
> the gate builds."*

**`vm_probe.s` is now clean against HEAD, and nothing about the code changed.** The modification
existed because this machine's clone predated the old laptop's push of `ec86b83`. P4.7 fetched it and
reset the branch onto it; the working-tree bytes were **byte-identical to `ec86b83`** and remain so.
★ **Same bytes, different git status.** The gate still builds exactly what §4 intends it to build —
`build/vm_probe.bin`, 8,822 B, `identical` under `gate_audit.py --verify`.

---

### 1 — Summary

The VM's cycle is now decomposed, on two titles, by an instrument that reports where the cycles
actually go rather than what an arm removes. **The interpreter's inner loop is the single largest
term and it is title-independent: 64,902 cy/VM cycle on Kingquest1 and 65,888 on Kingquest3, a 1.5%
spread.** Everything that separates the two titles is elsewhere — **63.6% of KQ3's extra cost is the
resource copy still running with the cache live.** Two structural findings came out of it, both of
trigger 1's class and neither anticipated: **the VM performs a 32-iteration software long division
per 25 ms timer tick**, worth 11.2% of KQ1's cycle, to detect a boundary a counter would give free;
and **`VM_PACEONLY` cannot measure the harness floor at all**, because the arm silently changes how
much pacing happens. Nothing was changed.

---

### 2 — Files modified

**No VM, engine, HAL or gate source was touched. This task changed no code that any gate builds** —
`gate_audit.py --verify` reports 8/8 artifacts identical, before and after.

Two new measurement tools, untracked until this report's commit:

- `harness/tools/vm_profile.lua` — PC sampler. **Installs a notifier and then `dofile`s
  `vm_sweep.lua` unmodified**, so the run being profiled is the run the ablation harness performs;
  a second copy of that staging would measure a different program [L-56].
- `harness/tools/vm_profile.py` — attributes sampled PCs to symbol and module, in **`vm_size.py`'s
  buckets** so AC-5's comparison is possible at all.

---

### 3 — Reasoning

#### A. Why sampling, and what it costs

The project's preferred exact mechanism is a write-tap on a guest-published phase byte, stamped with
`total_cycles` (pic_probe's since T-P0-012, and what `p3b_run.lua` uses). **`vm_probe.s` publishes no
such byte, and adding one would change the binary the VM gate builds** — which §2 and AC-1 forbid. So
attribution here is by **sampled PC**, one sample per emulated frame, which costs the guest nothing.

★★ **The sampler was shown not to perturb the run.** The profiled baseline reproduced the ablation
baseline exactly: **201 cycles, 14.238755 emulated s, 126,762 cy/VM cycle, opcount 2,950** — the same
digits as the un-profiled run in P4.7's §5.

★ **Resolution is stated, not implied.** 926 samples (KQ1) and 1,365 (KQ3). That supports module-level
shares; per-symbol rows are printed as leads and labelled as such [L-41].

#### B. ★★★★ The instrument was wrong first, and the tell was a data symbol

The first attribution charged **24.6% of KQ3's cycles to `vm_icguard`** — which is `fcb 0` at
`vm_cycle.s:455`, **a data byte at $224C**. Data does not execute.

The cause: attribution charges a PC to the greatest *owned* symbol at or below it, and my module list
held only `src/harness/vm_*.s`. **`res_core.s` and five HAL modules are also linked in**
(`vm_probe.s`'s own `include` list), so ~500 bytes of unowned resource-layer code were charged
*backwards* onto the last owned label. ★★ **An unowned module does not vanish from a profile; it
hides inside whatever precedes it.** Fixed by taking the module list from the probe's includes; the
tool now names any listed module it cannot find, so the hole cannot silently reopen.

★★★ **This is the same shape `vm_size.py` records for `equ` constants entering a size table, and
`addr_census.py` hit first.** It cost no MAME time — the samples were re-attributed from disk.

#### C. ★★★★★ STRUCTURAL FINDING 1 — a 32-iteration long division per timer tick [trigger 1]

`vm_pace` loops until a cycle is due, calling `vm_step_clock` once per 25 ms tick. Each tick calls
`vm_timer_update`, which calls **`vm_div32` — a restoring long division, 32 iterations, of the 32-bit
millisecond counter by 1000** [`vm_cycle.s:352-361`, `vm_cycle.s:416-451`].

★★★ **Its only purpose is to detect whether the second changed.** The quotient is compared against
`vm_lastsec` and discarded if equal [`vm_cycle.s:363-368`]. **The boundary is reachable without a
division:** `vm_vms` only ever grows by 25, so a second falls every 40th tick — and the file already
knows this, because the comment two lines above says the reference's *"general delta arithmetic
collapses to an increment here"* and the increment is implemented. **The increment was reproduced;
the search for the boundary was not.**

**Measured, on Kingquest1:** the timer path is **11.2% of the VM's cycle — 14,197 of 126,762
cy/VM cycle**, of which `vm_dv32_lp` alone is 9.3%.

★★ **It is title-dependent, which is why one number would have hidden it:** 11.2% on KQ1 and **4.1%**
on KQ3, because the divide runs once per tick and the tick count per cycle is `TIME_DELAY × 2`, which
each game sets for itself.

★★★★ **This is L-66's shape** — *a port paying per call what its reference pays once*. ScummVM's
`inGameTimerUpdate` computes this on a host with native 32-bit division; the 6809 pays ~640 cycles of
shift-and-subtract for it, tens of times per VM cycle. **Reported and stopped, per trigger 1. Nothing
was changed.**

#### D. ★★★★★ STRUCTURAL FINDING 2 — `VM_PACEONLY` cannot measure the floor [L-73, AC-4]

The profiler's own falsification check fired: the sampler put the pacing path at **11.2%** of KQ1
where `VM_PACEONLY` measures **2.7%** — 8.5 pp apart.

**The sampler is right and the arm is wrong**, and the mechanism is visible in the source.
`vm_step_clock` reads `VAR_TIME_DELAY` and derives `vm_tdelay = time_delay × 2`, clamping to **1** when
it is zero [`vm_cycle.s:330-346`]. **In the pace-only arm no logic runs, so no game ever sets
`TIME_DELAY`, so `tdelay` stays 1 and the pacing loop runs one tick per cycle instead of many.**

**Measured both ways, and they agree with the mechanism:**

| arm | `vm_div32` share | cy/VM cycle | **absolute cost of the divide** |
|---|---|---|---|
| baseline (KQ1) | 10.3% | 126,762 | **≈13,000 cy** |
| `VM_PACEONLY` | 23.7% | 3,443 | **≈815 cy** |

**16× less pacing work in the arm that exists to measure pacing.**

★★★★ **So `VM_PACEONLY` moves two variables — interpretation, and the depth of the pacing loop — which
is L-73 exactly.** AD-83's floor of 13.7% was wrong by 5×; **P4.7 corrected the number to 2.7% and the
number is still not the floor**, because no single figure is: the pacing cost is a property of the
title, not of the harness. ★★ **This report does not replace it with another constant.** It reports
11.2% for KQ1 and 4.1% for KQ3, measured.

★ **KQ3 is why this needed two titles.** On KQ3 the sampler says 4.1% against the arm's 2.7% and the
check prints `AGREES`. **A single-title run on KQ3 would have confirmed a broken arm.**

#### E. Two constants the profiler was not designed to produce

Converting shares to absolute cycles gives two figures that nothing in the method forced:

- **`vm_core` (the interpreter's dispatch and inner loops): 64,902 cy/VM cycle on KQ1, 65,888 on KQ3
  — a 1.5% spread across titles whose totals differ by 51%.**
- **`vm_probe` (the harness itself): 8,240 and 8,427 — a 2.3% spread.**

★★★ **Both are what they must be if the profile is sound**: interpreter dispatch per cycle is
title-independent, and a harness that varied with the game would not be a harness. ★★ Taken with
`vm_tables` — **10.4% of the VM's bytes and 0.0% of its samples, because it is data** — these are
three independent ways the sampler could have been caught reporting on something other than the run,
and was not.

#### F. Authority tiers

Every figure is **fresh tool output on this machine** (25.1) — MAME runs, hashes, `git` plumbing.
Claims about ScummVM's behaviour are confined to §3.C's citation of `inGameTimerUpdate`, which
`vm_cycle.s:349` names as the reference for that routine; per §2.1 that is **a fact about ScummVM**,
and no claim is made here about what Sierra's interpreter did. §2H's three checks: the second
mechanism was looked for and found (the divide is one of two things `vm_step_clock` does; the other,
the `TIME_DELAY` read, is what §3.D turns on); the calling routine is named in every case
(`vm_pace` → `vm_step_clock` → `vm_timer_update` → `vm_div32`); and the prior-report grep is §3.D's
reconciliation of AD-83 and P4.7 against each other.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] — PASS.** `hal_sync_check.py` **OK in all three repos**;
  `reg_discipline.py` **8 accesses, 1 file, 2 registers** (`src/engine/mmu_phase.s`, `$FFA5 $FFA6`) —
  unchanged, and still not the recorded 5 [AD-104, recorded not chased per §11]. **Gates unchanged:**
  `gate_audit.py --verify` **8/8 identical**, run before and after this task's measurements.
  **§2T citation:** the five gate results are cited from **INFRA.1 §4 AC-3** — renderer 45/45 · cels
  9,193/9,193 · compositing 20/20 · VM 9/9 exclusion-set-empty · resources 1,264/1,264 — run fresh on
  this machine, with byte-identity of all eight gate artifacts standing as the evidence that their
  inputs are unchanged. ★ This task changed no tracked source, so the citation is §2T's case exactly.
- **AC-2 [class: state-comparable] — THE DECOMPOSITION.** Per module, sampled PC, two titles:

  | module | KQ1 share | KQ1 cy/cycle | KQ3 share | KQ3 cy/cycle |
  |---|---|---|---|---|
  | `vm_core` — interpreter dispatch + inner loops | **51.2%** | **64,902** | **34.4%** | **65,888** |
  | `res_core` — resource copy (`rfe_word`) | 4.2% | 5,324 | **24.3%** | **46,543** |
  | timer/pacing path (`vm_div32`) | **11.2%** | **14,197** | 4.1% | 7,853 |
  | `vm_objects` | 6.6% | 8,366 | 9.5% | 18,196 |
  | `vm_probe` — the harness | 6.5% | 8,240 | 4.4% | 8,427 |
  | `vm_state` | 7.5% | 9,507 | 5.8% | 11,109 |
  | `vm_run` | 4.8% | 6,085 | 8.6% | 16,472 |
  | `vm_cmds` | 4.8% | 6,085 | 5.8% | 11,109 |
  | `vm_tests` | 1.8% | 2,282 | 2.1% | 4,022 |
  | `gfx` (HAL) | 0.4% | — | 0.3% | — |
  | **total** | **100%** | **126,762** | **100%** | **191,534** |

  ★★ **Unattributed: 0 samples below the VM's first label, on both titles** — every sample landed in
  owned code. **What is NOT claimed:** that 0% unattributed means 0% uncertainty. This is a *sampled*
  profile; the uncertainty is in each share, not in a residual, and at 926/1,365 samples a share of
  ~5% carries a margin of roughly ±1.5 pp. **Stated, not distributed.**
- **AC-3 [class: byte-comparable] — every arm's `opcount`, and one arm rejected.**

  | arm | `opcount` | predicted | verdict |
  |---|---|---|---|
  | baseline KQ1 | **2,950** | scales with work | moves 193 → 420 → 2,950 at TIMED 1/20/200 |
  | baseline KQ3 | **5,439** | higher (27.06 vs 14.68 cmd/cycle) | as predicted |
  | `VM_PACEONLY` | **0** | zero — no interpretation | **as predicted** |
  | `VM_NOCOUNT` | 2,950 | unchanged — counters only | as predicted |
  | `ABL_NOCACHE` | 2,950 | unchanged — equal work | as predicted |
  | `ABL_NOCOPY` | **184** | unchanged (2,950) | ★★★ **DOES NOT MOVE AS PREDICTED — not evidence** |
  | `ABL_NOFETCH` | **184** | unchanged (2,950) | ★★★ **DOES NOT MOVE AS PREDICTED — not evidence** |

  ★★ The last two are P4.7's finding, re-confirmed and **not used** in AC-2. Trigger 2's condition is
  met by arms already known bad; it is reported, and no figure in this report rests on them.
- **AC-4 [class: state-comparable] — how much is instrument.** **The harness itself is 6.5% (KQ1) /
  4.4% (KQ3) — 8,240 and 8,427 cy/VM cycle, constant in absolute terms** (§3.E). Instrumentation
  counters add **3.3%**, measured independently by `VM_NOCOUNT` (126,762 → 122,550). ★★★★ **AD-83's
  13.7% floor and P4.7's corrected 2.7% are both withdrawn as a concept, not just as numbers**
  (§3.D): the pacing cost is title-dependent and `VM_PACEONLY` cannot measure it. Measured, not
  inherited.
- **AC-5 [class: state-comparable] — the two decompositions DISAGREE, systematically and
  informatively.** Same buckets, both axes:

  | module | bytes | byte share | KQ1 cycle share | reading |
  |---|---|---|---|---|
  | `vm_core` | 566 | 7.1% | **51.2%** | ★★★★ **7× over** — small, hot: the dispatch loop |
  | `vm_cmds` | 1,787 | **22.5%** | 4.8% | ★★★ **5× under** — large, cold |
  | `vm_run` | 1,676 | **21.1%** | 4.8% | ★★★ **4× under** — motion routines, rarely reached |
  | `res_core` | 1,097 | 13.8% | 4.2% / **24.3%** (KQ3) | title-dependent |
  | `vm_tables` | 828 | 10.4% | **0.0%** | ★★ it is DATA — and the sampler never lands in it |
  | `vm_cycle` | 633 | 8.0% | 12.3% | over, via `vm_div32` |
  | `vm_state` | 190 | 2.4% | 7.5% | ★ 3× over — small and hot |
  | total | 7,956 | | | |

  ★★★★ **AC-5's named case is present: `vm_cmds` and `vm_run` are 43.6% of the VM's bytes and 9.6% of
  its cycles.** That is not a defect — an interpreter's opcode implementations are mostly cold — but
  it is the finding the AC asks for, and it says where size may be spent to buy speed and where it
  may not. ★ Trigger 3 does not fire: the two are not measuring the same quantity and are not
  expected to agree; they disagree in the direction an interpreter predicts.
- **AC-6 [class: state-comparable] — ranked BY MEASURED SHARE, and not acted on** (§2):

  1. **The interpreter's inner loop, `vm_core`** — 51.2% / 34.4%; **64,902 and 65,888 cy/VM cycle,
     title-independent.** The largest single term and the most stable. `vm_tic_loop`, `vm_rl_loop`,
     `vm_su_lp`, `vm_skip_instruction` are its four hottest labels.
  2. **The resource copy, `rfe_word`** — 4.2% / **24.3%**; and **63.6% of KQ3's excess over KQ1**.
     Already known avoidable [AD-87]; the cache removes 56.2% of the uncached cost and **what remains
     is still the second-largest term.**
  3. **The timer divide, `vm_div32`** — **11.2%** / 4.1% (§3.C). Structural, and the cheapest of the
     three to reason about.
  4. **`vm_objects`** — 6.6% / 9.5%; 8,366 → 18,196 cy, scaling with object count.
  5. **The harness, `vm_probe`** — 6.5% / 4.4%, constant; **not VM cost at all** (AC-4).
- **AC-7 [class: state-comparable] — KQ3's shortfall is reachable in principle; the 4-sprite margin
  is NOT answerable from this data.** KQ3 costs **191,534 cy/VM cycle against KQ1's 126,762 — a
  64,772 gap — and the profile attributes 95% of it**: `res_core` +41,219 (63.6%), `vm_run` +10,387,
  `vm_objects` +9,830, against `vm_core` +986 and `vm_probe` +187. ★★★ **So KQ3 is not slower because
  the interpreter is slower; it is slower because it copies more.** ★ **On the 4-sprite margin:
  "cannot tell from this data"** — that is M-49's compositing-live measurement and no arm here
  exercises the sprite path (`gfx` draws 0.4%).
- **AC-8 [class: state-comparable] — one found, and it was mine.** The profiler's first module list
  was incomplete and charged the resource layer onto a data byte (§3.B) — **found by the top row of a
  cycle profile being an `fcb 0`.** ★★ Beyond that: `ABL_NOCOPY`/`ABL_NOFETCH` remain rejected (AC-3);
  `ABL_TITLE` was inert [AD-94]; `opcount` was blind [AD-102]; `pic_probe.s` aliases three counters
  onto `PAL_READBACK` [P4.7 AC-10]. ★★★ **Still never shown able to fail: the `res`, `cel` and `comp`
  probes' counters.** Named as unexamined, not asserted sound. **Trigger 5 — a fourth blind
  instrument — is not claimed**: mine was caught before it published a figure, and what it would have
  invalidated is listed in §3.B.
- **AC-9 [class: state-comparable] — three things this dispatch did not anticipate.** (1) **The timer
  divide** (§3.C) — the dispatch's candidate list named "per-cycle work that scales with something
  other than opcodes"; this scales with `TIME_DELAY`, which is neither opcodes nor resource size.
  (2) **`VM_PACEONLY` cannot measure the floor** (§3.D) — AC-4 asked for the floor to be measured
  rather than inherited, on the assumption a floor exists to measure. (3) **`vm_core`'s absolute cost
  is title-independent** (§3.E), which no AC asked for and which is what makes the KQ1/KQ3 comparison
  interpretable at all. ★ "Nothing" was not the answer.
- **AC-10 [class: suite]** — see §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

*§4 — git, hal-sync, flag diff:*
```
branch: wip
HEAD:       d3037bd52c4a272f6dca480c52c7a08734e5ff19
origin/wip: d3037bd52c4a272f6dca480c52c7a08734e5ff19
git status: clean

coco_agi       : [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port      : [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3 : [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)

gate   artifact                  shipped    fresh  verdict
pic    build/pic_probe.bin          2642     2642  identical
pic_nc build/pic_nc_unpacked.bin     2512     2512  identical
pic_nc_pk build/pic_nc_packed.bin      2971     2971  identical
pic_win build/pic_v_windowed_nocount.bin     2655     2655  identical
res    build/res_probe.bin          2019     2019  identical
cel    build/cel_probe.bin          1436     1436  identical
comp   build/comp_probe.bin          967      967  identical
vm     build/vm_probe.bin           8822     8822  identical
```

*§4 — the pace-only gate, before anything else was trusted:*
```
=== VM_PACEONLY  (8810 bytes) ===
clock MEASURED 1.789417 MHz (640000 cycles calibrated, this session)
AC-7 free-run: 201 cycles in 0.386770 emulated s
opcount=0  (0.00 commands/cycle)   vm_cycle=0 of 201 expected  ★★★ MISMATCH
```

*The sampler does not perturb the run — profiled baseline vs P4.7's un-profiled baseline:*
```
vm_profile: sampling PC -> build/vm_prof/Kingquest1.txt
AC-7 free-run: 201 cycles in 14.238755 emulated s
    70.840 ms/cycle   126762 CPU cycles/VM cycle   14.1 VM cycles/s
    opcount=2950  (14.68 commands/cycle)   vm_cycle=201 of 201 expected
```

*AC-2 — Kingquest1, 926 samples:*
```
samples: 926 total, 926 attributed to a VM symbol, 0 below the VM's first label (100.0% attributed)

module            samples     share
vm_core               474     51.2%
vm_cycle              114     12.3%
vm_state               69      7.5%
vm_objects             61      6.6%
vm_probe               60      6.5%
vm_run                 44      4.8%
vm_cmds                44      4.8%
res_core               39      4.2%
vm_tests               17      1.8%
gfx                     4      0.4%
TOTAL                 926    100.0%

symbol                       module        samples     share
vm_tic_loop                  vm_core           113     12.2%
vm_dv32_lp                   vm_cycle           86      9.3%
vm_rl_loop                   vm_core            82      8.9%
vm_su_lp                     vm_core            63      6.8%
vm_skip_instruction          vm_core            52      5.6%
vm_tic_end                   vm_core            51      5.5%
vm_uo_lp                     vm_objects         35      3.8%
vm_arg                       vm_cmds            32      3.5%
```

*AC-2 — Kingquest3, 1,365 samples:*
```
samples: 1365 total, 1365 attributed to a VM symbol, 0 below the VM's first label (100.0% attributed)

module            samples     share
vm_core               469     34.4%
res_core              332     24.3%
vm_objects            130      9.5%
vm_run                117      8.6%
vm_state               79      5.8%
vm_cmds                79      5.8%
vm_cycle               66      4.8%
vm_probe               60      4.4%
vm_tests               29      2.1%
gfx                     4      0.3%
TOTAL                1365    100.0%

symbol                       module        samples     share
rfe_word                     res_core          277     20.3%
vm_tic_loop                  vm_core           116      8.5%
vm_rl_loop                   vm_core            95      7.0%
vm_tic_end                   vm_core            55      4.0%
vm_skip_instruction          vm_core            50      3.7%
vm_arg                       vm_cmds            49      3.6%
vm_dv32_lp                   vm_cycle           48      3.5%
```

*§3.D — the check firing, and then agreeing on the other title:*
```
Kingquest1  CHECK -- pacing path, sampler vs ablation
  sampler          : 11.2%  (104 samples)
  VM_PACEONLY      : 2.7%
  difference       : 8.5 pp -- ★★★ DISAGREES -- do not quote this profile

Kingquest3  CHECK -- pacing path, sampler vs ablation
  sampler          : 4.1%  (56 samples)
  VM_PACEONLY      : 2.7%
  difference       : 1.4 pp -- AGREES
```

*§3.D — the pace-only arm profiled, showing how little pacing it does:*
```
=== VM_PACEONLY, Kingquest1, 93 samples ===
module            samples     share
vm_probe               61     65.6%
vm_cycle               28     30.1%
gfx                     4      4.3%

symbol                       module        samples     share
vp_calloop                   vm_probe           21     22.6%
vp_at_rd                     vm_probe           19     20.4%
vm_dv32_lp                   vm_cycle           19     20.4%
```

*AC-3 — `opcount` movement, baseline Kingquest1:*
```
ABL_TIMED=1   :   2 cycles   opcount=193
ABL_TIMED=20  :  21 cycles   opcount=420
ABL_TIMED=200 : 201 cycles   opcount=2950
ABL_NOCOPY, TIMED 20 / 200 / 400 : opcount=184 / 184 / 184   ★ rejected, not used
```

*AC-5 — the size axis, same buckets:*
```
per module, symbol-attributed (TOTAL 7956):
   vm_cmds             1787      vm_cycle             633
   vm_run              1676      vm_core              566
   res_core            1097      vm_tests             266
   vm_tables            828      vm_probe             217
   vm_objects           696      vm_state             190
```

*AC-7 — where KQ3's extra 64,772 cy/VM cycle goes:*
```
module           KQ1 cy     KQ3 cy      delta
vm_core           64902      65888        986
res_core           5324      46543      41219
timer path        14197       7853      -6344
vm_objects         8366      18196       9830
vm_probe           8240       8427        187
vm_run             6085      16472      10387
vm_cmds            6085      11109       5024
vm_state           9507      11109       1602
vm_tests           2282       4022       1740
total delta KQ3-KQ1: 64772
```

*AC-1 — `reg_discipline.py`:*
```
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s      8   $FFA5 $FFA6
```

**25.2 bundled-artifact grep:** N/A — this task imported no sibling artifact and committed no bundled
asset. The sibling and gate claims are §2T citations to INFRA.1, whose evidence was a rebuild-and-hash
on this machine.

**25.3 operator-runtime-smoke:** `N/A — no visual surface this task.`

---

### 6 — Reactive deviations and route accounting

1. **Attribution is by sampled PC, not by the project's preferred exact phase-tap** (§3.A). The exact
   mechanism needs a guest-published byte, and publishing one would change the binary the VM gate
   builds. Sampling was chosen as the only method that leaves the measured program untouched, and its
   resolution is stated everywhere it is quoted.
2. **Two new harness tools were added.** They measure; they change nothing any gate builds, and
   `gate_audit.py --verify` is 8/8 identical after them. If the Orchestrator reads "no code changed"
   as excluding new measurement tools, these should be reverted and this report's figures stand
   unreproducible — flagged rather than assumed.
3. **Two titles, not nine.** KQ1 and KQ3 were profiled; the remaining seven were not. §3.D is why two
   was the minimum — one title would have confirmed a broken arm — but nine would be better and this
   is not a nine-title result.
4. **`ABL_NOCOPY`/`ABL_NOFETCH` were run but excluded** from every figure (AC-3).
5. **Nothing was optimised, and the two structural findings were reported rather than acted on**
   (trigger 1, §2).

**ROUTE ACCOUNTING.** No route was proposed in advance for this task. What this report contains is the
AC list as written, plus §4's premise correction and the three unanticipated findings in AC-9. I did
**not** resume the decomposition into a change, spend M-48's 455 bytes, touch the cycle-rate decision,
run M-49's compositing-live, chase AD-104's register drift or the stale `scummvm.pin`.

---

### 7 — Uncertainty flags

- ★★★ **These are sampled shares, not counted cycles.** 926 and 1,365 samples. A 5% share carries
  roughly ±1.5 pp; the headline terms (51.2%, 24.3%, 11.2%) are well clear of that, the small ones
  are not. **`gfx` at 0.4% is four samples and should not be quoted at all.**
- ★★★ **Per-symbol rows charge unlabelled code to the preceding label** — `vm_size.py`'s
  approximation, inherited deliberately so both axes share it. `rfe_word` at 20.3% is the copy loop
  plus whatever follows it before the next label; **the module figure is the claim.**
- ★★ **The timer divide's cost was measured on two titles and it differs by 2.7× between them.**
  Neither is "the" figure. Seven titles are unmeasured, and `TIME_DELAY` is the variable to expect it
  to track.
- ★★ **§3.D explains `VM_PACEONLY`'s failure by a mechanism read from source, and confirms it by a
  16× ratio — but `vm_tdelay`'s actual value in each arm was not read out.** The probe does not
  publish it. That is the one link in §3.D's chain that is inference rather than measurement, and a
  future task can close it by publishing `vm_tdelay` at the park.
- ★ **`reg_discipline.py` still reads 8 against a recorded 5** [AD-104]; the `scummvm.pin` patch list
  still records five patches against eight applied. Both carried forward, untouched (§11).
- ★ **The `res`, `cel` and `comp` counters have still never been shown able to fail** (AC-8).

**Triggers:** **1 FIRES TWICE** (§3.C the timer divide; and §3.D, which is structural about the
harness rather than the VM) — **both reported, nothing changed.** 2's condition is met only by
`ABL_NOCOPY`/`ABL_NOFETCH`, already known and excluded. 3 does not fire (§4 of AC-5). 4 does not fire
— the profile attributes every sample. 5 is not claimed (AC-8).

---

### 8 — Follow-up candidates

1. ★★★★ **Replace the per-tick `vm_div32` with a second-boundary counter** — `vm_vms` grows by 25, so
   a second is every 40th tick. Worth 11.2% of KQ1's cycle on this measurement. **Trigger 1: Jay's
   and the Orchestrator's call, not this task's.**
2. ★★★★ **The residual resource copy is the second-largest term and the largest on KQ3** — 24.3%, and
   63.6% of KQ3's excess. AD-87's cache took 56.2%; this is what it left.
3. ★★★ **Retire or repair `VM_PACEONLY`, `ABL_NOCOPY` and `ABL_NOFETCH`** — three of six arms in
   `vm_ablate.ps1`'s default set are now known not to measure what they name.
4. ★★★ **Publish `vm_tdelay` at the park** so §3.D's last inferential link becomes a measurement.
5. ★★ **Profile the remaining seven titles**, and correlate the timer share against each game's
   `TIME_DELAY`.
6. ★★ **Apply AC-3's zero-on-an-empty-arm test to the `res`, `cel` and `comp` counters** (carried from
   P4.7).
7. ★ **`vm_core`'s title-independent 65,000 cy/VM cycle is the floor any parser budget must clear** —
   it is the number §8's cycle-rate decision turns on.

---

### 9 — User interaction during task

`None.`

### 10 — Candidate(s) captured this task

Pushed to `methodology-candidate-pool` **`main`**, `seeds/AGI/live/`:

- `2026-09-05-an-ablation-arm-can-silently-change-how-much-work-the-harness-itself-does.md` — §3.D:
  `VM_PACEONLY` removes interpretation *and*, through a variable the game sets, most of the pacing it
  exists to measure.
- `2026-09-05-a-data-symbol-at-the-top-of-a-cycle-profile-means-the-attribution-is-wrong.md` — §3.B:
  an unowned module hides inside whatever label precedes it, and `fcb 0` at the top of a profile is
  the tell.

★ **INFRA.1's two owed rows are still owed** — they are that task's, not this one's, and are recorded
in its §10.

### 11 — Commit

To be committed on `wip` and pushed to `origin/wip` before this report is read, staged by explicit
path per §2E: `harness/tools/vm_profile.lua`, `harness/tools/vm_profile.py`, and this report.
**No file any gate builds is in that list**, and `gate_audit.py --verify` is 8/8 identical after them.
