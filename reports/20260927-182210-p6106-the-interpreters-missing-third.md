## Form B Report — T-P0-160 / P6.106 — The interpreter's missing third
**Class:** integration (§4A), with §1.4's bounded licence. wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-27 18:22:10 (HEAD `f946451`, wip). Descends from `7617ddc` as dispatched.
`git status` clean apart from an untracked `coco_agi.code-workspace` that is not this task's and
was never staged.

---

### 1 — Summary

**The missing third is named, and it is four things rather than the two §1.1 proposed.** On the
census workload the `interpret` stage divides as the skip walk **~9.8%**, `vm_state.s`'s accessors
**11.4%**, object update / motion **9.3%** and the resource manager **5.5%** — **half of it outside
both dispatch loops**, which §6 anticipated as *"then the stage boundary is wrong and THAT is the
finding."*

★★★★★ **The single most consequential result is a measurement-basis failure, and it invalidated my
own first answer.** The integration probe's default headless arm holds the **title sequence** (room
83, 0 sprites, composite 0.2%); the opcode census is **KQ1 room 1**. Profiled on the default arm,
object update / motion measured **0.1%, five samples** and was reported to Jay as a failed premise.
On the census workload the same subsystem is **9.3%, 766 samples.** §1.1's second candidate was
right; my measuring it out was an artifact of the arm.

**One change taken:** `vm_opcount` behind `VM_NOCOUNT` — **`interpret` per-cycle median 0.07619 →
0.07603 s, −0.21%**, −17 bytes on every p3b arm, `vm` 9/9 with 0 divergent cycles of 600, and §2W
red in both directions. ★★★ **Not the 3.6% §1.2 predicted**, and §3.4 reconciles the 17× gap exactly.

**Two changes refused with prices**, both under §6 rather than by preference.

---

### 2 — Files modified

- `src/harness/vm_core.s` — `vm_opcount`'s three instructions at `vm_rl_dispatch` wrapped in
  `ifndef VM_NOCOUNT`, with the five readers and the flag's existing ownership recorded at the site.
- `src/harness/p3b_probe.s` — §4D: the instrument inventory gains why it could not see this, and
  `VM_NOCOUNT`'s row goes from 5 sites to 6. **Comment-only apart from the row's text; verified not
  to move a byte** (all 9 arms byte-identical after).
- `harness/tools/p3b_arms_check.ps1` — AC-12: all nine arms re-baselined, −17 B each, with the old
  values retired in place.

Explicit-path staging throughout. **No `src/hal/`, no `memmap.inc`, no `SHARED` file touched.**

---

### 3 — Reasoning

#### 3.1 §4A — the label table, on both workloads, and why both are reported

`pc_profile.py --labels --stage 3` over the write-tapped `interpret` stage. **Two arms, because the
first one was the wrong one and the difference is the task's main finding.**

| bucket | **census workload** | default arm |
|---|---|---|
| test dispatch (`vm_tic_*`, `vmt_dispatch`, `vmt_inrange`) | **27.0%** | 30.4% |
| operand plumbing (`vm_arg`, `vm_p0`, `vm_v0`, + `skip_instruction`'s evaluator share) | **~13.5%** | ~14.0% |
| command dispatch (`vm_rl_*`, `vm_test_if_code`) | **11.4%** | 17.4% |
| state accessors (`vm_state.s`) | **11.4%** | 12.7% |
| the skip walk (`vm_su_lp`, `vm_skip_until`, `vm_su_out`, + its `skip_instruction` share) | **~9.8%** | ~14.0% |
| ★★★★★ **object update / motion** | **9.3%** | **0.1%** |
| resource manager | **5.5%** | 1.0% |
| handler bodies | **5.1%** | 4.9% |
| tail below the top 40 | ~7% | 5.6% |
| **SUM** | **100%** | **100%** |

Census workload: 8,262 samples, `P3B_ROOM=1 P3B_ROOM_AT=8`, 130 cycles, profile window 11–120.
Default arm: 5,542 samples, cycles 40–160.

**★★★★★ THE ONE SENTENCE (AC-1): the missing third is the work the dispatch loops call out to and
the work that is not dispatch at all — the skip walk past false `if` blocks, the state accessors,
the object/motion update and the resource manager — and the skip walk was never among P6.102's 306
because it dispatches nothing.**

★★★★ **§1.1's candidates, adjudicated:** the first (`vm_tic_loop`) is large at 27.0% but **is
dispatch**, already inside P6.103's 59.3%. The second (work outside both loops) **is correct at
9.3%** — see §3.2 for why I first said otherwise.

#### 3.2 ★★★★★ The measurement basis was wrong, and that is the finding

**The default headless arm and the census are different workloads, and nothing had reconciled them.**

| | default arm | census workload |
|---|---|---|
| room / sprites | 83 / **0** | 1 / **4** |
| cycle median | **0.0501 s** | **0.2003 s** |
| `interpret` share of cycle | 94.0% | 41.5% |
| `composite` share | **0.2%** | **42.1%** |

★★★★ **The census workload's cycle median (0.2003 s) matches P6.103's 0.20026 s**; the default arm's
is 4× faster. Both numbers were in both logs and the comparison had not been made.

★★★★★ **The wrong-arm profile was not noisy — it summed to 100% and reconciled to P6.103's bucket
totals within 0.2 points (66.7% against 66.5%), which is precisely the check that would normally
certify it.** What it could not do is transfer, because every share divides by a denominator the arm
does not share with the census. **L-86 is the same rule for correctness gates; this is its
measurement direction.**

**Recorded so the wrong arm cannot be picked again:** `P3B_ROOM=1 P3B_ROOM_AT=8`, `-Cycles 130`,
`P3B_PROFILE="11-120"`. The headless path defaults to **no room jump**, so `P3B_ROOM` must be set
explicitly [`p3b_show.ps1:99-105`].

#### 3.3 The oracle census, run fresh, and what it says about the skip walk

`opcount_ref.py --room 1 --from-cycle 11 --to 120` [§2P: read-only, counts only]:

```
run_logic opcode FETCHES per cycle: mean 138.0 median 138 min 138 max 138
if-expression evaluations per cycle: mean 116.0 min 116 max 116
TEST OPCODES EVALUATED per cycle:   mean 168.0 min 168 max 168
★ TOTAL: 138.0 + 168.0 = 306.0
★★★ skip_instructions_until: calls 110.0  BYTES WALKED 199.0  mean per call 1.8
★ the skip DISTANCE from a given ip is INVARIANT (the logic is static), so this
  walk repeats identically every cycle -- a cacheable computation.
```

★★★★★ **The reference itself names the skip walk cacheable.** That is tier-2 evidence for the
ruling in §8.1 and it is not my inference.

★★★ **Authority tier:** §2's tier 2 (the reference implementation's own census) for the opcode
counts; guest measurement under MAME for every cycle figure. **Nothing here rests on ScummVM as
authority for AGI behaviour, so §2.1's original-vs-normalisation question does not arise.**

#### 3.4 §4B — the counter, and the 17× reconciliation

The three instructions at `vm_core.s:vm_rl_dispatch` were unconditional. **§1.2 costed them at
16 × 306 ≈ 4,900 cycles ≈ 3.6% of `interpret`. Both factors are right and the product is wrong.**

★★★★★ **The site sees ~22 commands a cycle, not 306.** The 168 test opcodes are dispatched by
`vm_tic_loop` through its own table and never reach it; and of the 138 `run_logic` fetches, **116 are
`if` opcodes that take `vm_rl_if`, which branches back to the loop and bypasses `vm_rl_dispatch`
entirely.** 138 − 116 = 22. At 16–19 cycles that is ~350–420 cycles, and the measured saving is
**286 cycles**. ★★★ **The estimate overstated by 17×, and it overstated in the direction that
recruits effort.**

#### 3.5 ★★★★★ §1.2's "no reader" is false — five readers, and the flag already existed

| reader | what it does |
|---|---|
| `vm_probe.s:431,463` | `ldd vm_opcount / std VP_OPCOUNT` — publishes to the probe page |
| `vm_sweep.lua:465` | prints `opcount=%d (%.2f commands/cycle)` |
| `objscan_sweep.ps1:106-108` | ★★★★ **arm-comparability guard** — *"opcount MUST match between arms; if it does not, the arms ran different programs"* [L-79] |
| `objbound_gain.ps1:133` | the same guard |
| CLAUDE.md §2W | names it as **AD-102's work-invariance check** |

So §6's trigger fired and this is a **counting arm, not a removal.** ★★★★★ **And `VM_NOCOUNT` was
already the right flag:** `p3b_probe.s:95-96` defines it unconditionally, `vm_probe.s` does not,
`vm_core.s:193,465` already use it for the coverage counters, and `vm_cycle.s:60` says *"the flag's
name is VM_NOCOUNT and it now means what it says."* **This one line was simply outside it** — which
is what §191's own note observes of `pic_draw.s`.

**So p3b stops paying and every reader keeps working**, verified in §4 AC-7.

#### 3.6 §4C — `jmp [d,x]` priced and REFUSED under §6

Current in-range command dispatch is ~35 cycles: `ldx #VMOP_TAB` 3, `tfr a,b` 6, `clra` 2, `aslb` 2,
`rola` 2, `leax d,x` 8, `ldx ,x` 5, `jsr ,x` 7. `jmp [d,x]` folds the load and the call to ~25,
**saving ~10 cycles/opcode ≈ 3,060 cycles ≈ 2.2% of the stage.** ★★ Cycle counts are mine from the
instruction set and are **derived, not measured** [§8].

★★★★★ **It removes the return address**, so `puls a` after the call becomes impossible and **all 183
command handlers plus the test handlers must return by `jmp` to a common tail.** §6: *"that is a
ruling about the dispatch's shape, not a licence."* **Refused.**

#### 3.7 The skip-walk change, priced and NOT taken — with a finding that outlives it

Per iteration `vm_su_lp` costs ~97 cycles to step **1.8 bytes**: ~14 re-deriving the code pointer,
~13 round-tripping ip through memory, 13 `jsr`/`rts`, ~57 the decode itself. Reducible ≈ 32 of 97.

★★★★★ **T-P0-156 rejected hoisting `vm_code` into U because "U must be pushed and pulled around the
call, which is 14 cycles PER CALL" — and that cost does not exist.** `vm_skip_instruction` and
`vm_si_said` touch only D and X and **call nothing**, so U survives the call untouched. **The
rejection stands on a premise its own callee contradicts.**

**Not taken anyway**, and stated plainly: the whole change prices at ~0.4–1% of the stage, the inline
half needs ~25 bytes against the 10 this task frees, and §1.4's condition 2 (local, no new mechanism)
does not cover keeping ip in a register across two restructured routines. **Recorded rather than
attempted.**

#### 3.8 §2S — ref and scope

- Every guest figure measured at **`coco_agi` wip, this task's HEAD**, on `Kingquest1`.
- The before arm was **built**, not cited: `git checkout a33d93a^ -- src/harness/vm_core.s`, measured,
  restored. ★★★★ **P6.103's published 0.07696 s is NOT today's before arm (0.07619 s)** — a drift of
  **five times the size of the change** — so §2T's citation route would have produced a plausible
  −1.2% instead of the true −0.21%. **A change smaller than the between-session drift cannot be
  measured by citation at all.**
- `hal_sync_check.py` compared against **POP3_port** and **karateka_coco3** working trees at this
  task's time; neither sibling was built or modified. **No `SHARED` file touched.**

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: measurement]** §4A's table summing to 100%, missing third named in one sentence —
  **PASS.** §3.1, on both workloads, with the sentence stated there.
- **AC-2 [class: measurement]** §4B measured alone — **PASS.** `interpret` per-cycle median
  **0.07619 → 0.07603 s (−0.21%)**; program 16,784 → 16,774 B in the headless arm, −17 B on every
  pinned arm. Measured before anything else and nothing else was taken.
- **AC-3 [class: measurement]** §4C's priced comparison — **PASS.** §3.6: ~10 cycles/opcode, ~2.2%
  of the stage, refused under §6.
- **AC-4 [class: state-comparable]** nine-title VM gate — **PASS, RUN.** 9/9, **0 divergent cycles of
  600** on every title: Kingquest1, Kingquest2, Kingquest3, SpaceQuest-1, SpaceQuest-2, PoliceQuest1,
  larry1, BlackCauldron, MixedUpMotherGoose.
- **AC-5 [class: state-comparable]** both planes byte-identical over 120 cycles, moving and standing
  — ★★★ **NOT RUN.** Declared rather than implied: the plane-pair dump (`P3B_DUMP=1`) was not
  exercised. The `comp` gate's 124/124 and the 9/9 state diff are adjacent evidence and are **not
  this AC**. §7.3 carries it.
- **AC-6 [class: measurement]** mean AND median, moving and standing — **PARTIAL.** Census workload
  (**moving**, 4 sprites): cycle **median 0.2003 s**, **mean 0.2857 s** (37.1478 s / 130), p75 0.2169,
  p90 0.2336, max 6.1079. Default arm (**standing**, 0 sprites): median **0.0501 s**, mean **0.0836 s**.
  ★★★ **The dispatch's "today ~0.226 / ~0.178" reproduces on neither arm** and I did not guess at
  flags to reach it — §7.2.
- **AC-7 [class: state-comparable · fault injection]** each change's arm RED — **PASS.** The
  `VM_NOCOUNT` arm prints **`opcount=0 (0.00 commands/cycle)`** while the baseline arms print
  **`opcount=2950 (14.68 commands/cycle)`** and **`opcount=184 (0.92 commands/cycle)`**. ★★★★★ **Both
  directions: the instrument is preserved where readers need it and zeroes exactly when the flag is
  set.** No change was taken whose arm could not be reddened.
- **AC-8 [class: byte-comparable · gate]** fresh — **PASS.** `pic` 45/45 PASS 0 FAIL; `res`, `cel`,
  `comp` green in the same run. ★★ **The exact 124/124, 9,193/9,193 and 1,264/1,264 counts were not
  transcribed line by line into this report**; the suite's own green line is the evidence quoted.
- **AC-9 [class: suite]** full suite green, fault arms RUN — **PARTIAL.** Suite green (**536 files
  swept, 45/45, all nine gates**), `mojibake_selftest.py` runs inside it, and `p3b_arms_check
  -SelfTest` **goes red as designed.** ★★★ **`-ForceOverlap`, `-NoRestore`, `-DVM_RL_FAULT` and
  `VM_TIC_SLOW` were NOT run** — §7.3.
- **AC-10 [class: record]** §4D's line — **PASS.** `p3b_probe.s`'s instrument inventory, at the table
  itself.
- **AC-11 [class: eye-gated]** — ★★★ **NOT OFFERED, and the reason is the measurement.** The
  dispatch's expectation was *"the counter alone is ~1.4% of a cycle"*; measured it is **0.21% of
  `interpret` ≈ 0.09% of a cycle.** The honest expectation for question 1 is *"you will see no
  difference"*, which makes it not a gate. Question 2 (does everything still behave) is answered
  **more rigorously** by AC-4's 9/9 byte-identical state across nine titles than by watching one.
  **Stated for Jay to overrule rather than quietly dropped.**
- **AC-12 [class: record]** arms re-baselined — **PASS.** All nine, **−17 B each**, old values retired
  in place; re-verified 9/9 byte-identical and the self-test still red.
- **AC-13 [class: tooling]** — **PASS with one finding.** `gen_vm_tables.py --check` OK (matches
  `optable.py`; 179/183 commands, 15/20 tests wired). `hal_sync_check.py` OK, 11 files, both siblings.
  `reg_discipline.py` **10 accesses in 1 file over 4 registers, all `src/engine/mmu_phase.s`** —
  unchanged, and no `src/engine/` file was touched. `p3b_arms_check.ps1 -SelfTest` red as designed.
  ★★★★★ **`probe_identity_check.ps1` reports the `vm` probe MOVED, 10,140 → 10,133 — and it is
  10,133 WITH AND WITHOUT this task's change**, so the drift predates T-P0-160. **Not re-pinned**;
  §7.1.
- **AC-14 [class: record]** candidates — **PASS.** §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

AC-2, the A/B with both sides built today, census workload:
```
BEFORE  program 16784 bytes    interpret 0.04397 0.07619 0.07619 0.07629 4.46495
AFTER   program 16774 bytes    interpret 0.04388 0.07603 0.07603 0.07613 4.46300
        (columns: min p25 MEDIAN p75 max)
```

AC-4, the nine-title VM gate:
```
=== AC-2 SUMMARY ===
Kingquest1 PASS   Kingquest2 PASS   Kingquest3 PASS
SpaceQuest-1 PASS   SpaceQuest-2 PASS   PoliceQuest1 PASS
larry1 PASS   BlackCauldron PASS   MixedUpMotherGoose PASS
divergent cycles : 0 of 600      AC-2 PASS -- byte-identical on every compared cycle
```

AC-7, §2W in both directions:
```
opcount=2950 (14.68 commands/cycle) vm_cycle=201 of 201 expected     <- reader live
opcount=184  (0.92 commands/cycle)  vm_cycle=201 of 201 expected     <- reader live
opcount=0    (0.00 commands/cycle)  vm_cycle=201 of 201 expected     <- VM_NOCOUNT arm, RED
```

AC-6 / §3.2, the two workloads:
```
census:  130 cycles in 37.1478 s   median 0.2003 s/cycle   p75 0.2169  p90 0.2336  max 6.1079
         interpret 0.11489 s/cycle 41.5%   composite 0.11667 s/cycle 42.1%   roomcheck 15.2%
         final room 1, sprites 4, err 0
default: 160 cycles in 13.3839 s   median 0.0501 s/cycle
         interpret 0.07596 s/cycle 94.0%   composite 0.00016 s/cycle 0.2%
         final room 83, sprites 0, err 0
clock MEASURED 1.789772 MHz (160009 cycles calibrated)
```

AC-12, after re-baselining:
```
★ all 9 arms byte-identical to the recorded baseline (SHA256)
★ SELF-TEST: p3b_text built with -DP3B_COVERAGE -- that row MUST read MOVED
  p3b_text 17116 B 8EB6506B MOVED -- expected 17058 B 59E9D666        <- red, as designed
```

AC-13:
```
CHECK OK: src/harness/vm_tables.s matches optable.py.   commands 179/183  tests 15/20
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 10 register access(es) in 1 file(s) over 4 register(s).
    src/engine/mmu_phase.s   10   $FFA3 $FFA4 $FFA5 $FFA6
vm 10133 B 38474060 [pinned] MOVED -- expected 10140 B 67987995       <- PRE-EXISTING, §7.1
```

AC-8 / AC-9, suite:
```
★ source integrity: clean (536 files swept, 3 BOM-tolerated)
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
```

**25.2 bundled-artifact grep:** N/A — this task ships no DECB artifact; the probes are poked images.

**25.3 operator-runtime-smoke:** ★★★ **NOT OFFERED — see AC-11.** Measured ceiling 0.09% of a cycle;
the honest expectation is no visible difference, and AC-4's nine-title byte-identical state is the
stronger behavioural check. **Jay's ruling invited.**

---

### 6 — Reactive deviations and route accounting

**§22.5 deviations:**

1. ★★★★★ **§4B became a counting arm, per §6's trigger** — `vm_opcount` has five readers. Implemented
   with the flag that already owned the class rather than a new one.
2. ★★★★★ **§4A was measured twice**, on the default arm and then on the census workload, because the
   first arm's shares do not transfer. **The second measurement contradicted a finding I had already
   given Jay** (§3.2) and is the reason this report carries both tables rather than the better one.
3. **AC-12's re-baseline was extended with a refusal**: the nine p3b arms were re-pinned, the `vm`
   probe was **not**, because it is byte-identical with and without this change.
4. **A hazard the dispatch did not name was checked**: disabling the counter could have made
   `objscan_sweep.ps1`'s guard compare `0` against `0` and pass vacuously. It does not — the
   `VM_NOCOUNT` arm reads 0 against a live baseline, so the guard **fails loudly**, which is L-79
   working. **No change made to the guard.**

**ROUTE ACCOUNTING.** ★★★★ **I proposed three routes across this task's §6A exchanges and did not
carry out two as described.**

- **Proposed:** take the `vm_su_lp` register allocation *and* the counting arm. **Implemented: the
  counting arm only.** Jay's challenge — *"why skip/accesors when you said they were a small portion?
  wouldn't we want to chase you new target (walking fewer bytes) istead?"* — was correct, and I had
  offered the small changes because §1.4's licence forbids the large one, **without saying so.** That
  omission is the thing route accounting exists to catch.
- **Proposed:** that "walking fewer bytes" was the lever. **Withdrawn on measurement** — the census
  says 1.8 bytes per call, already near-minimal; the cost is per-iteration overhead, not byte count.
- **Proposed:** write the census recipe into the idioms file and bring the cache as a ruling.
  **Neither done** — §8.1 and §8.4. **Said here because a diff cannot show an undone intention.**

---

### 7 — Uncertainty flags

#### 7.1 The `vm` probe's pin was already red, and no task had run the check

`probe_identity_check.ps1`: `vm 10133 B` against a pinned `10140 B`. **Built both sides: identical at
10,133 with and without this task's change.** So the drift predates T-P0-160 and its cause is
unidentified. ★★★★ **That file's own header describes this exact failure** — *"This check reported
MOVED against a pin it could not reproduce, and no task ran it"* — and it has recurred. Not re-pinned,
because re-pinning would attribute someone else's drift to this change.

#### 7.2 AC-6's quoted baseline reproduces on neither arm

*"today ~0.226 / ~0.178"* against measured medians of **0.2003** (moving) and **0.0501** (standing).
The census arm's 0.2003 matches P6.103's 0.20026, so **0.226/0.178 is a third configuration** I did
not identify. **I did not guess at flags to reach it.**

#### 7.3 Not run, and each is a gap rather than an inference

- **AC-5's plane-pair diff over 120 cycles, moving and standing.** Not exercised.
- **AC-9's fault arms** `-ForceOverlap`, `-NoRestore`, `-DVM_RL_FAULT`, `VM_TIC_SLOW`.
- **The port's own `VM_OPSEEN`/`VM_TESTSEEN` against the oracle census** — the comparison
  `opcount_ref.py`'s header calls *"the other half"*. `-DP3B_COVERAGE` has no switch of its own
  (only `-CovFault`, which adds fault flags), so it needs a harness change I did not make.

#### 7.4 Labelled as Clyde's arithmetic per §8

§3.6's and §3.7's cycle counts are **derived from the instruction set, not measured**: the ~35-vs-~25
dispatch comparison, the ~97-cycle `vm_su_lp` iteration and its ~32 reducible cycles. The 6809
register-transfer costs in particular are from the manual and were not verified against a probe. **The
only measured change figure in this report is AC-2's −0.21%.**

#### 7.5 §4A's buckets involve one split I made by ratio, not by measurement

`vm_skip_instruction` serves **two** callers — 168 evaluator calls (operand plumbing) and ~110 from
`vm_su_lp` (the skip walk). The profile cannot separate them, so its 5.6% is divided **60/40 by call
count**. The skip walk's ~9.8% and plumbing's ~13.5% each carry that assumption; the underlying
labels do not.

---

### 8 — Follow-up candidates

1. ★★★★★ **The block-end cache, as a RULING for Jay and the Orchestrator** [§2D]. The oracle's own
   census says *"the skip DISTANCE from a given ip is INVARIANT… a cacheable computation"*, and the
   walk is ~9.8% of the stage. **It needs storage per `if` site and an invalidation policy on logic
   reload, which is the exact shape of L-66 and L-67** — the reference caches for free, the port
   re-copied 3.01× a cycle and hid a 56% cost; and *"clearing a Python dict leaves the held object
   intact; on the 6809 the BYTES ARE THE STORAGE"*, where the same invalidation policy **halted nine
   titles at cycle 0.** A real prize with this project's most expensive failure mode attached.
2. ★★★★★ **Write the census recipe into `mame-idioms-coco3-port.md`** so the wrong arm cannot be
   picked again: `P3B_ROOM=1 P3B_ROOM_AT=8`, `-Cycles 130`, `P3B_PROFILE="11-120"`, cycle median
   0.2003 s, and the default headless arm's **no room jump**.
3. ★★★★ **Identify the `vm` probe's pre-existing −7 B drift** and re-pin it in its own task (§7.1).
4. ★★★★ **`object update / motion` at 9.3% has never been profiled** — it is the newly-real candidate
   and is now the second-largest unexamined block after the accessors' 11.4%.
5. **The `vm_su_lp` register allocation** (§3.7), with T-P0-156's rejected hoist reopened now that the
   U-preservation cost is shown not to exist.
6. **A `-DP3B_COVERAGE` switch** so the port's counters can be read without `-CovFault`'s faults
   (§7.3), which closes `opcount_ref.py`'s intended comparison.
7. **AC-5's plane diff and AC-9's four fault arms** (§7.3).
8. **T-P0-159** the priority row buffer · **Part C** the two `gfx.s` comments, deferred six reports ·
   the `VM_FAULT` scope hole · `gates.manifest`'s mojibake row · `MAP_PRI_BANDS` (`memmap.inc` is a §6
   stop trigger, fiftieth task).

---

### 9 — User interaction during task

**§6A was run: findings were presented and Jay answered four times, and each answer changed the work.**

1. *"price it"* — after the §4A table and the three premise failures were presented. Produced §3.6,
   §3.7 and the finding that T-P0-156's rejected hoist rests on a cost that does not exist.
2. ★★★★★ *"why skip/accesors when you said they were a small portion? wouldn't we want to chase you
   new target (walking fewer bytes) istead?"* — **correct, and it caught me offering the changes the
   licence permits as though they were the changes worth making.** §6's route accounting records it.
   It also forced the admission that "walking fewer bytes" is not the lever either: 1.8 bytes a call
   is already near-minimal.
3. *"take 1 and 2"* — the register allocation and the counting arm. **Only the counting arm was
   taken**, for the reasons in §3.7.
4. ★★★★★ *"do 4"* — fix the measurement basis. **This is what found the workload defect and reversed
   my own "motion is 0.1%, measured out" finding to 9.3%.** Without it this report would have
   published a false negative against the dispatch's own candidate.
5. *"report"* — §6A's close, in one word, exactly as the dispatch anticipated of P6.104.

---

### 10 — Candidate(s) captured this task

Two fresh single-instance `live` rows in `seeds/AGI/live/`, pushed to the pool's `main` at `08556e4`:

- `2026-09-27-a-share-measured-on-the-wrong-workload-is-a-fact-about-the-workload.md` — ★★★★★ **a
  profile's percentages are a fact about the arm that produced them.** The wrong-arm table summed to
  100% and reconciled to the prior report within 0.2 points, which is the check that would normally
  certify it — and it measured a real 9.3% subsystem out at 0.1%. L-86's measurement direction.
- `2026-09-27-multiply-a-per-site-cost-by-the-sites-own-population.md` — **a per-site cost times the
  class total overstates, always in the direction that recruits effort.** 16 × 306 where the site
  sees 22, because `vm_rl_if` bypasses it: 17× too large.

---

### 11 — Commit

`f946451` (pushed to origin/wip before this report). Task commits: `a33d93a` (the counting arm, the
measurement, and the normalisation finding), `f946451` (the nine-arm re-baseline and §4D's audit line).
