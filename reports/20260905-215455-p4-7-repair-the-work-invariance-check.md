## Form B Report — P4.7 — the work-invariance check proved, and what it caught

**Class:** build. wip. Calibration-light — receipt stamp only.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-05 (dispatch carried no explicit receipt timestamp; report written 2026-09-05T21:54:55-04:00).

---

## §4 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `wip` @ **`ecf7d5c9726c140afc5fd338358a2c8e821c921a`** ("P4.6: record the five candidate rows in section 10") |
| POP + Karateka | §2T cite below; **trees clean of tracked modifications** (POP 0 modified; Karateka 1, a log) |
| `hal_sync_check.py` | **OK in all three repos** |
| the gates, fresh builds | renderer 45/45 · cels 9,193 · compositing 20/20 · VM **9/9 re-run this task** · resources 1,264 — §2T cite + byte-identity, see AC-1 |
| **the flag set — enumerated and diffed** | **8/8 artifacts identical** to what their sources build now |
| **the clock — measured** | **1.789417 MHz (640,000 cycles calibrated, this session)** |
| every ablation-derived figure | **enumerated — and the list was incomplete, see AC-4** |

### ★★★★★ CONTRADICTION — reported, then RETRACTED. The retraction is the finding.

> ★★★★★ **THIS SECTION'S ORIGINAL CLAIM WAS WRONG, AND THE WAY IT WAS WRONG IS THE LESSON.**
> It is kept in full rather than deleted, because a report that quietly replaces a false claim with a
> true one teaches nothing [L-53].

**What this section originally said, verbatim:**

> **Commit `ec86b83` does not exist in this repository.**
> - `git cat-file -t ec86b83` → `fatal: Not a valid object name`
> - Not on any branch (`wip`, `remotes/origin/wip` only), **not in the reflog** (12 entries back to
>   P3b.11d), **not among dangling commits** (`fsck --lost-found`).
> - **`origin/wip` is also `ecf7d5c9`** — so it was never pushed either.

**What is actually true.** `ec86b83` **exists, and it is `origin/wip`**:
`ec86b8331087777997c6dbe9ddf5b6e261db98a8`, authored `Sat Sep 5 19:17:29 2026 -0400`,
*"P4.7: the free-run counters were blind, and the clock was a literal"* — 4 files, 254 insertions,
16 deletions.

★★★★★ **THE DEFECT IN MY CHECK: `git rev-parse origin/wip` DOES NOT ASK THE REMOTE.** It reads a
**remote-tracking ref** — a local cache of what the remote said *at the last fetch*. This clone had
never been fetched on this machine, so that ref still held the value the old laptop last recorded.
**I read a stale local cache and reported it as a fact about GitHub.** Every one of the four checks
above is *individually correct and collectively worthless*, because all four interrogate local
object storage and the commit was never local. `cat-file`, `reflog` and `fsck` cannot see a commit
that was never fetched; that they agreed with each other read as corroboration and was really four
views of the same gap.

★★★★ **It was caught by a push being REJECTED** — `! [rejected] wip -> wip (fetch first)`, i.e. by an
operation that actually contacts the remote. **The only check in this class that means anything is one
that crosses the network.**

★★★ **This is L-78's shape** — *a printed clock that could not disagree with reality* — applied to git:
a cached ref cannot disagree with the remote, because it is not reading it. And it is X-32's shape
again, the fourth instance across two tasks: **a negative about the environment, asserted from the one
place that could not falsify it.**

### ★★ What the retraction does NOT change: every measurement in this report

★★★★★ **The repair this report measured is BYTE-IDENTICAL to `ec86b83`.** After fetching, the local
branch was reset onto `origin/wip` and `git diff origin/wip -- src/harness/vm_probe.s
harness/tools/vm_sweep.lua harness/tools/vm_ablate.ps1 harness/tools/slot_audit.py` is **empty**; the
working tree went clean against `ec86b83` with only this report and INFRA.1's left untracked.

★★★ **So AC-2 through AC-8 were measured against exactly the commit the dispatch named**, and stand
without amendment. The working tree's 133 tracked insertions plus untracked `slot_audit.py`'s 121
lines are `ec86b83`'s 254 exactly. **The dispatch's premise was right and my check was wrong**; what
actually happened is that this laptop's copy was taken *before* the 19:17 push, so the committed work
arrived as uncommitted changes.

**The WORK the dispatch attributes to `ec86b83` is present, and is uncommitted.** `git diff --stat HEAD`:

```
 harness/tools/vm_ablate.ps1 |   3 +-
 harness/tools/vm_sweep.lua  | 100 ++++++++++++++++++++++++++++++++++++++------
 src/harness/vm_probe.s      |  46 +++++++++++++++++++-
 3 files changed, 133 insertions(+), 16 deletions(-)
?? harness/tools/slot_audit.py
```

All five named deliverables verified present in the working tree before anything was run:
`ifndef VM_PACEONLY` at **vm_probe.s:188 and :235** · `VP_MARK equ $0094` at **:52**, opened **:161**,
closed **:172** · `vm_cycle`/`vm_opcount` published at the park **:219–222** · `lbra` at **:264, :266** ·
`slot_audit.py` present, untracked.

★★ **INFRA.1 §7 recorded the same state and drew the same wrong conclusion from it** — *"`coco_agi`
carries uncommitted `wip` work… it is unpushed and exists on exactly one disk."* The first half was
observation and correct; **"unpushed" was inference from the same stale ref, and it was wrong.** The work
was committed AND pushed from the old laptop at 19:17; this machine's copy predates that push.

★ **I proceeded rather than stopping, and that call happened to be right for the wrong reason.** The
reasoning given at the time — that the contradiction was provenance rather than substance, since every
mechanism AC-3 needs was present and verifiable — held. But it rested on a false premise, and the
honest version is: **the work was `ec86b83` all along.** Had the local tree been a divergent *earlier*
draft, the same reasoning would have produced confidently wrong measurements. ★★ **The safeguard that
would have caught it is one this task did not run: fetch before asserting anything about a remote.**

---

### 1 — Summary

**AC-3 is proven: `opcount` reaches ZERO on the pace-only arm.** The check is repaired, not merely
changed. With it working, the re-validation splits three ways rather than two: **AD-87's cache result
survives essentially unchanged and is now supported by demonstrated work-invariance rather than by
assumption**; **AD-83's decomposition does not survive** — its harness floor was wrong by 5× and its
resource-copy figure came from an arm that does no interpretation at all; and the repaired check
**caught the bad arms itself**, which is the first time this instrument has demonstrated it can. The
dispatch's causal account is also incomplete: there were **two** defects, not one, and the repair's own
source comment says so.

---

### 2 — Files modified

**None by this task.** No source, harness or doc file was edited. The working tree is as INFRA.1 left it,
plus regenerated gitignored build artifacts (`build/vm_abl_*.bin|map`, `build/vm_stage/symbols_*.txt`,
`build/vm_abl_out_*`, `build/vm_probe.bin`) and this report.

★ Nothing is staged. See §11 — push remains impossible on this machine.

---

### 3 — Reasoning

#### A. There were TWO defects, and the dispatch named the smaller one [AC-2, trigger 3]

The dispatch's diagnosis — *"`opcount` read 184 … because it was only ever written on the handshake path
before the free run began"* — is the **publish defect**. The repair's own comment at `vm_probe.s:204–215`
is explicit that this is the primary one and that it is **not** what the previous dispatch named:

> *"★★★★★ PUBLISH THE CUMULATIVE COUNTERS *BEFORE* THE PARK — THE FREE-RUN NEVER DID. This is AD-102's
> actual defect, and it is not the one the dispatch named."*

The **unguarded `jsr`** at `:235` is a second, distinct defect with a different blast radius. Separating
them [L-54]:

| defect | site | who it affected | symptom |
|---|---|---|---|
| **publish path** | `:219–222` (added) | **every arm** | `opcount` frozen at 184 regardless of work |
| **unguarded `jsr`** | `:235` (guard added) | **`VM_PACEONLY` only** | pace-only still ran one interpret cycle, so it could never read 0 |

★★★ **Both were necessary for AC-3's zero.** Fixing only the guard would still have published a stale
184; fixing only the publish would have reported the one interpret cycle the unguarded `jsr` ran. So
**AC-2's "was the unguarded `jsr` the whole cause" answers NO** — it was neither the whole cause nor the
larger one. This is trigger 3's condition, reported; no fixing was required, because both are already
repaired in the working tree.

★ **The 184 is now explained rather than merely observed:** at `ABL_TIMED=1` (2 cycles) the repaired
counter reads **193**. 184 was `logic.0`'s initialisation count, and it was the only cycle the old
publish path ever saw.

#### B. `slot_audit.py`'s `PAL_READBACK` aliasing did NOT contribute [AC-2, second half]

It cannot have. The aliasing is in **`src/harness/pic_probe.s`** — the renderer probe — and `opcount`
lives in **`src/harness/vm_probe.s`**. They are different programs, assembled separately, never resident
together. `slot_audit.py` confirms `vm_probe.s` has **no overlapping pairs**. Answered by structure, not
by argument.

#### C. The proof, and why it is a proof rather than a green light [AC-3, L-79]

`-DVM_PACEONLY` built (8,810 B) and **run**, Kingquest1, `ABL_TIMED=200`:

```
=== VM_PACEONLY  (8810 bytes) ===
AC-7 free-run: 201 cycles in 0.386770 emulated s
    opcount=0  (0.00 commands/cycle)   vm_cycle=0 of 201 expected  ★★★ MISMATCH
```

**`opcount=0`.** The `★★★ MISMATCH` is correct and expected: the harness completed 201 free-run
iterations while the interpreter's own cycle counter stayed at 0, which is exactly what "runs the pacing
gate and NOTHING ELSE" must look like.

★★★ **What makes this a proof and not one more green number is that the counter was shown to MOVE in the
same session** — the failure L-79 exists to catch is a check that reads a constant. Baseline, same title,
three work levels:

| `ABL_TIMED` | VM cycles | `opcount` **now** | `opcount` **before repair** |
|---|---|---|---|
| 1 | 2 | **193** | 184 |
| 20 | 21 | **420** | 184 |
| 200 | 201 | **2,950** | 184 |

**Zero on an arm that does no work, and monotone growth on arms that do.** Both halves are required; a
counter stuck at 0 would satisfy AC-3's letter and prove nothing.

Flag sets used [L-77], from `vm_ablate.ps1:52–53` — every arm carries
`-DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK` plus its own `-D<variant>`, and **each gets its own `--map`
and its own `symbols_<variant>.txt`** (the L-56 trap that file exists for). `-DHAL_SYS_FAST_CLOCK` is
present in all six — the omission that once made every figure wrong by 2× did not recur.

#### D. AD-87 survives, and now rests on evidence instead of assumption [AC-5]

AD-87's work-invariance claim was the thing `opcount` was supposed to support and could not. Re-measured
with the working check, Kingquest1, `ABL_TIMED=200`:

| | AD-87 (P3b.5, blind check) | **re-measured (working check)** | delta |
|---|---|---|---|
| no cache | 288,575 cy/VM cycle | **289,301** | +0.25% |
| cached | 126,307 | **126,762** | +0.36% |
| resource copy | 162,268 = **56.2%** | **162,539 = 56.2%** | — |
| rate | 6.2 → **14.2** cyc/s | 6.2 → **14.1** cyc/s | −0.7% |
| **work invariance** | *assumed* | **`opcount=2950` in BOTH arms** | **now demonstrated** |

★★★★ **AD-87 holds to three significant figures, and the claim it could not previously support is now
supported directly.** The comparison arms did equal work: 2,950 commands each. **Trigger 1 does not
fire** — nothing moved materially.

★★★ **And this resolves P4.6's open contradiction.** P4.6 reported `ABL_NOCOPY` giving the resource copy
as **68.2%** against AD-87's **56.2%** and said *"I cannot reconcile the two without a working invariance
check."* With the check working the reconciliation is immediate: **`ABL_NOCACHE` is the valid arm and it
reproduces 56.2%; `ABL_NOCOPY`'s 68.2% came from an arm that does no interpretation** (§3.E). The 56.2%
was right.

#### E. ★★★★★ The repaired check caught two invalid ablation arms [AC-6, trigger 2]

`ABL_NOCOPY` and `ABL_NOFETCH`, `ABL_TIMED=200`:

```
=== ABL_NOCOPY  (8880 bytes) ===
    22.568 ms/cycle   40384 CPU cycles/VM cycle   44.3 VM cycles/s
    opcount=184  (0.92 commands/cycle)   vm_cycle=201 of 201 expected
=== ABL_NOFETCH  (8936 bytes) ===
    22.568 ms/cycle   40384 CPU cycles/VM cycle   44.3 VM cycles/s
    opcount=184  (0.92 commands/cycle)   vm_cycle=201 of 201 expected
```

Two observations, each independently damning:

1. **`opcount` is frozen at 184 — the pre-repair value — while baseline reads 2,950.** Held at
   `ABL_TIMED=20` (**184**), `200` (**184**) and `400` (**184**), against baseline's 420 → 2,950. These
   arms execute the init cycle and then **no commands at all**.
2. **Two different binaries (8,880 B and 8,936 B) produce identical results to the sixth decimal**
   (4.536261 s vs 4.536198 s). ★★ That is the exact signature of the inert-`ABL_TITLE` defect (AD-94),
   which was caught the same way — *"the numbers being IDENTICAL to the previous title's, digit for
   digit."*

★★★★ **This is NOT a second blind counter, and the distinction decides what it invalidates.** `vm_cycle`
and `opcount` are published by the *same* block at `:219–222`. In these arms **`vm_cycle` advances
correctly to 201** while `opcount` does not move. The publish path therefore works; the *work* is not
happening. **The counter is reporting truthfully that these arms do nothing** — which is the instrument
doing its job for the first time.

★★★ **Consequence:** `ABL_NOCOPY` violates the honesty condition its own header claims for it
(*"a repeat fetch cannot change what executes, so skipping one is a true ablation"*). Whatever it skips,
it is load-bearing. **Any figure derived from `ABL_NOCOPY` or `ABL_NOFETCH` does not survive.** I did not
diagnose *why* — that is a fix, and §11 puts it out of scope.

#### F. The clock, measured [L-78, L-57, AD-100]

**`clock MEASURED 1.789417 MHz (640,000 cycles calibrated, this session)`**, printed by every one of the
nine MAME runs in this report. 0.020% from the hardware constant 14.31818/8 = 1.789773 MHz. ★ INFRA.1
measured 1.789772 MHz via `p3b_run.lua`'s 160,009-cycle bracket; this is a different calibration block
(640,000 cycles) in a different probe, and the two agree to 0.02%. **Measured in both cases, asserted in
neither.**

#### G. Authority tiers

Every conclusion rests on **fresh tool output on this machine** — MAME runs, `git` plumbing, byte
hashes. No conclusion rests on ScummVM's behaviour or the AGI Specs, so §2.1's original-vs-normalisation
split does not arise. §2H's three checks do not apply: no oracle mechanism is read. §2S: the sibling
claims are cited per §2T (below), not re-derived.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] — PASS.** `hal_sync_check.py` **OK in all three repos**;
  `reg_discipline.py` **8 accesses, 1 file, 2 registers** (`src/engine/mmu_phase.s`, `$FFA5 $FFA6`) —
  unchanged from INFRA.1, and ★ still not the recorded 5 (INFRA.1 §3.D; unchanged by this task, which
  touched no `src/engine/` file). **Gates unchanged:** `gate_audit.py --verify` reports **8/8 artifacts
  identical** to what their sources build now, which is the claim an mtime cannot make [L-71].
  **§2T citation:** POP and Karateka baselines are cited from **INFRA.1 §4 (AC-1, AC-2)** — POP's six
  DECB files + `probe.dmk` and all **711** build outputs byte-identical, Karateka's `karateka.bin` and
  all **1,222** byte-identical — rebuilt and hashed on this machine hours before this task, inputs
  unchanged since.
- **AC-2 [class: state-comparable] — ANSWERED, and the answer is NO.** The unguarded `jsr` was **not**
  the whole cause and not the larger part: the **publish-path defect** affected every arm, the guard
  affected only `VM_PACEONLY`, and **both were required** for AC-3's zero (§3.A). `PAL_READBACK`
  aliasing **did not contribute** — different probe, different program; `slot_audit.py` shows
  `vm_probe.s` has no overlapping slots (§3.B). ★ Trigger 3's condition is met and is reported here;
  no fix was needed, both defects being already repaired in the working tree.
- **AC-3 [class: byte-comparable] — PASS. THE PROOF.** `-DVM_PACEONLY` built (**8,810 bytes**) and run:
  **`opcount=0`**, `vm_cycle=0 of 201`. Corroborated by the counter being shown to MOVE in the same
  session — **193 / 420 / 2,950** at `ABL_TIMED` 1 / 20 / 200, where all three previously read 184
  (§3.C). Flag set reported in §3.C and §5. **The check is repaired, not changed.**
- **AC-4 [class: state-comparable] — enumerated; the dispatch's list WAS incomplete [L-53].** Six arms
  exist in `vm_ablate.ps1:41`, not the two the dispatch named:

  | figure / arm | source | status |
  |---|---|---|
  | **AD-87 cache**, 288,575→126,307, 56.2%, 6.2→14.2 cyc/s | `ABL_NOCACHE` | ★★★ **SURVIVES — RE-MEASURED**, 289,301→126,762, 56.2%, 6.2→14.1; work-invariance now demonstrated (`opcount` 2,950 both arms) |
  | **instrumentation cost 3.40%** (P4.6/AD-83) | `VM_NOCOUNT` | ★★ **SURVIVES — RE-MEASURED 3.3%** (126,762→122,550 = 4,212); `opcount` 2,950 both arms, equal work confirmed |
  | **harness floor 13.7% / interpret+post 86.3%** (P4.6/AD-83) | `VM_PACEONLY` | ★★★★ **DOES NOT SURVIVE — RE-MEASURED.** Floor is **3,443 cy = 2.7%**, not 17,386 = 13.7%; interpret+post **97.3%**. The old arm was still running one interpret cycle |
  | **resource copy 68.2%** (P4.6/AD-83) | `ABL_NOCOPY` | ★★★★★ **DOES NOT SURVIVE.** Arm does no interpretation (`opcount` 184 at TIMED 20/200/400); P4.6 already labelled it an upper bound. **The valid figure is `ABL_NOCACHE`'s 56.2%** |
  | (no published figure found) | `ABL_NOFETCH` | ★★★ **INVALID ARM** — identical pathology, flagged before anything cites it |
  | **AD-101**, opcode count explains 2% of cycle variance | — | ★ **UNAFFECTED** — needed no ablation, as the dispatch states |
  | **AD-94** resources 1,264/1,264 cache live; VM 9/9 byte-identical | gates | ★★ **UNAFFECTED** — gated independently of `opcount` (§3 of the dispatch) |

- **AC-5 [class: state-comparable] — PASS; the figures HOLD.** AD-87 re-measured with the working check
  and the measured clock: **+0.25% / +0.36% / 56.2% unchanged / 6.2→14.1 vs 14.2** (§3.D). ★ Reporting
  that they hold, per the AC's own instruction that this is equally worth reporting. **Trigger 1 does
  not fire.** ★★ And the re-measurement **resolves P4.6's unreconciled 68.2%-vs-56.2%** in favour of
  56.2%.
- **AC-6 [class: state-comparable] — one found, and it is not a counter.** `ABL_NOCOPY` and
  `ABL_NOFETCH` are **invalid ablation arms** — `vm_cycle` advances while `opcount` does not, proving
  the publish works and the work is absent (§3.E). Instrument defects now stand at **five in four
  tasks**: `ABL_TITLE` inert [AD-94] · `opcount` blind, two distinct defects [AD-102] · `pic_probe.s`
  counter aliasing [AC-10] · these two arms. ★★ **What I did NOT do is claim the rest are sound.** The
  `res`, `cel` and `comp` probes' counters have not been shown able to reach zero on an empty arm, and
  L-62 applied to instruments says that is exactly the missing evidence. `slot_audit.py` reports
  **57 direct-page slots across five probes declare no size and are "not checked, not cleared"** — an
  unexamined surface, named rather than dismissed.
- **AC-7 [class: byte-comparable] — PASS, re-run this task.** VM gate **9/9 titles**, 600 cycles ×
  288 bytes each, **exclusion set EMPTY**, zero divergent cycles. This task changed no VM source and
  the gate confirms it.
- **AC-8 [class: state-comparable] — four things this dispatch did not anticipate.** (1) ★ **RETRACTED
  AND REPLACED.** This read *"`ec86b83` does not exist, and the repair is uncommitted and unpushed"*. It
  exists and it was pushed. **The genuine unanticipated finding is the defect that produced the claim:**
  `git rev-parse origin/wip` reads a local cache, not the remote, so a clone that has never been fetched
  answers confidently and wrongly (§4). (2) **Two defects, not one**, and
  the repair's own comment says the dispatch named the smaller (§3.A). (3) **`VM_PACEONLY`'s floor was
  wrong by 5×**, so AD-83's decomposition moves materially even though AD-87 does not. (4) **Two
  ablation arms are invalid**, and the newly-repaired check is what caught them (§3.E). ★ "Nothing" was
  not the answer; it has now been wrong five times running.
- **AC-9 [class: suite] — three captured and pushed.** See §10. ★ Captured after the body of this
  report was written, once Jay supplied the pool credential; §10 records the correction.
- **AC-10 [class: byte-comparable] — RECORDED, and it affects no published figure.**
  `slot_audit.py` reports **3 overlapping pairs**, all in `pic_probe.s`: `CNT_STRPIX $00A0`,
  `CNT_SECFLUSH $00A2`, `CNT_FLUSH $00A4` all inside `PAL_READBACK $00A0-$00AF`. ★★★ **The three
  counters are written only under `ifdef PIC_STRADDLE` (`pic_probe.s:189–194`), and no gate or shipped
  build defines it** — `gates.manifest`'s `pic` row is `-DHAL_GFX_MODE_SERVICE`, `pic_win` is
  `-DPLANE_WINDOWED -DPIC_NOCOUNT`. So **the 45/45 renderer gate and every published pic timing median
  are unaffected**, and the aliasing is latent in all of them. ★★ It is live only in a `PIC_STRADDLE`
  census build that also calls `pal_readback` — which is where the straddle/flush pricing figures for
  design A vs design B came from, so **those are the figures to re-check**. ★ This also names P3b.6's
  "unnamed writer of `$00A6`": `PAL_READBACK` spans `$00A0–$00AF`, which contains it. It is a §2F
  single-home violation and `slot_audit.py` prints without gating.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

*§4 — the contradiction:*
```
$ git rev-parse --abbrev-ref HEAD ; git rev-parse HEAD
wip
ecf7d5c9726c140afc5fd338358a2c8e821c921a
$ git cat-file -t ec86b83
fatal: Not a valid object name ec86b83
$ git rev-parse origin/wip
ecf7d5c9726c140afc5fd338358a2c8e821c921a
$ git branch -a
* wip
  remotes/origin/wip
```

*§4 — `hal_sync_check.py`, all three repos:*
```
coco_agi       : [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, EOL/guard/export-placement normalised)
POP3_port      : [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, EOL/guard/export-placement normalised)
karateka_coco3 : [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, EOL/guard/export-placement normalised)
```

*§4 — the flag set, required vs actual, by rebuilding and comparing BYTES [L-77, L-70, L-71]:*
```
gate   artifact                  shipped    fresh  verdict
------------------------------------------------------------------------
pic    build/pic_probe.bin          2642     2642  identical
pic_nc build/pic_nc_unpacked.bin     2512     2512  identical
pic_nc_pk build/pic_nc_packed.bin      2971     2971  identical
pic_win build/pic_v_windowed_nocount.bin     2655     2655  identical
res    build/res_probe.bin          2019     2019  identical
cel    build/cel_probe.bin          1436     1436  identical
comp   build/comp_probe.bin          967      967  identical
vm     build/vm_probe.bin           8822     8822  identical
```

*AC-3 — THE PROOF. Baseline and pace-only, one run, Kingquest1, ABL_TIMED=200:*
```
=== baseline  (8822 bytes) ===
clock MEASURED 1.789417 MHz (640000 cycles calibrated, this session)
AC-7 free-run: 201 cycles in 14.238755 emulated s
    70.840 ms/cycle   126762 CPU cycles/VM cycle   14.1 VM cycles/s
    opcount=2950  (14.68 commands/cycle)   vm_cycle=201 of 201 expected

=== VM_PACEONLY  (8810 bytes) ===
clock MEASURED 1.789417 MHz (640000 cycles calibrated, this session)
AC-7 free-run: 201 cycles in 0.386770 emulated s
    1.924 ms/cycle   3443 CPU cycles/VM cycle   519.7 VM cycles/s
    opcount=0  (0.00 commands/cycle)   vm_cycle=0 of 201 expected  ★★★ MISMATCH
```

*AC-3 corroboration — the counter MOVES (baseline, Kingquest1):*
```
ABL_TIMED=1   : AC-7 free-run: 2 cycles in 0.733442 emulated s
                opcount=193  (96.50 commands/cycle)   vm_cycle=2 of 2 expected
ABL_TIMED=20  : AC-7 free-run: 21 cycles in 2.009313 emulated s
                opcount=420  (20.00 commands/cycle)   vm_cycle=21 of 21 expected
ABL_TIMED=200 : AC-7 free-run: 201 cycles in 14.238755 emulated s
                opcount=2950  (14.68 commands/cycle)   vm_cycle=201 of 201 expected
```

*AC-4 / AC-5 — the remaining arms, ABL_TIMED=200, Kingquest1:*
```
=== ABL_NOCACHE  (8828 bytes) ===
clock MEASURED 1.789417 MHz (640000 cycles calibrated, this session)
AC-7 free-run: 201 cycles in 32.496376 emulated s
    161.674 ms/cycle   289301 CPU cycles/VM cycle   6.2 VM cycles/s
    opcount=2950  (14.68 commands/cycle)   vm_cycle=201 of 201 expected

=== VM_NOCOUNT  (8794 bytes) ===
AC-7 free-run: 201 cycles in 13.765687 emulated s
    68.486 ms/cycle   122550 CPU cycles/VM cycle   14.6 VM cycles/s
    opcount=2950  (14.68 commands/cycle)   vm_cycle=201 of 201 expected

=== ABL_NOCOPY  (8880 bytes) ===
AC-7 free-run: 201 cycles in 4.536261 emulated s
    22.568 ms/cycle   40384 CPU cycles/VM cycle   44.3 VM cycles/s
    opcount=184  (0.92 commands/cycle)   vm_cycle=201 of 201 expected

=== ABL_NOFETCH  (8936 bytes) ===
AC-7 free-run: 201 cycles in 4.536198 emulated s
    22.568 ms/cycle   40384 CPU cycles/VM cycle   44.3 VM cycles/s
    opcount=184  (0.92 commands/cycle)   vm_cycle=201 of 201 expected
```

*AC-6 — `ABL_NOCOPY` frozen across a 20× work range:*
```
ABL_TIMED=20  : 21 cycles  opcount=184  (8.76 commands/cycle)  vm_cycle=21 of 21 expected
ABL_TIMED=200 : 201 cycles opcount=184  (0.92 commands/cycle)  vm_cycle=201 of 201 expected
ABL_TIMED=400 : 401 cycles opcount=184  (0.46 commands/cycle)  vm_cycle=401 of 401 expected
```

*AC-7 — the VM gate, nine titles:*
```
=== AC-2 SUMMARY ===
Kingquest1 PASS / Kingquest2 PASS / Kingquest3 PASS / SpaceQuest-1 PASS / SpaceQuest-2 PASS
PoliceQuest1 PASS / larry1 PASS / BlackCauldron PASS / MixedUpMotherGoose PASS
  (each: 600 cycles x 288 bytes, exclusion set EMPTY, divergent cycles 0 of 600)
```

*AC-10 — `slot_audit.py`:*
```
── src/harness/pic_probe.s  (21 direct-page slots)
   ★★★ OVERLAP  CNT_STRPIX $00A0-$00A0 (line 142)   PAL_READBACK $00A0-$00AF (line 487)
   ★★★ OVERLAP  CNT_SECFLUSH $00A2-$00A2 (line 143) PAL_READBACK $00A0-$00AF (line 487)
   ★★★ OVERLAP  CNT_FLUSH $00A4-$00A4 (line 148)    PAL_READBACK $00A0-$00AF (line 487)
── src/harness/vm_probe.s  (14 direct-page slots)
   no overlap among the slots that declare a size.
★★★ 3 overlapping pair(s). A slot written by two owners is a §2F single-home violation, and the
second writer is invisible in the first's output.
```

*AC-1 — `reg_discipline.py`:*
```
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s      8   $FFA5 $FFA6
```

**25.2 bundled-artifact grep:** N/A — this task imported no sibling artifact and committed no bundled
asset. The sibling baselines are §2T citations to INFRA.1, whose evidence was itself a rebuild-and-hash
on this machine.

**25.3 operator-runtime-smoke:** `N/A — no visual surface this task.`

---

### 6 — Reactive deviations and route accounting

1. **Proceeded past §4's contradiction rather than stopping.** `ec86b83` does not exist, but all five of
   its named mechanisms are present and verified in the working tree, and AC-3 is one build and one run.
   Stopping would have withheld the proof the reissue exists for. **Every figure is labelled as measured
   against HEAD `ecf7d5c9` + uncommitted changes.** If the Orchestrator intended `ec86b83` to contain
   more, this report does not cover it.
2. **Four of the five gates are §2T citations, not fresh runs this task.** Only the **VM gate was
   re-run** (AC-7 names it). Justification: all five were run fresh on this machine hours earlier
   (INFRA.1), this task edited no tracked file, and `gate_audit.py --verify` shows **8/8 artifacts are
   byte-identical to what their sources build now** — so the gates' inputs are provably unchanged. ★ I
   am flagging this because §4 asked for fresh builds and I gave a citation plus a byte-identity
   argument for four of them.
3. **Did not diagnose *why* `ABL_NOCOPY`/`ABL_NOFETCH` do no work.** That is a fix; §11 puts fixes out of
   scope and trigger 2 says report. Measured, characterised, not repaired.
4. **Nothing was committed.** See §11.

**ROUTE ACCOUNTING.** I proposed no route for this task in advance. What this report contains is the
dispatch's AC list as written, plus the §4 contradiction and the two unanticipated findings in §3.E and
AC-4. I did **not** resume the decomposition, optimise anything, or touch the parser, sound, media or
`LOADER.BIN`.

---

### 7 — Uncertainty flags

- ★ **RESOLVED, and it was never true.** This read *"the repair is uncommitted and exists on one disk…
  the single highest-risk item in the project's current state."* The repair was committed and pushed as
  `ec86b83` before this task began; the risk was an artefact of the stale-ref error, not a real exposure
  (§4). ★★ **Kept rather than deleted: a flagged risk that dissolves on better evidence should be seen to
  dissolve**, otherwise the next reader inherits the alarm without the correction.
- ★★★ **`ABL_NOCOPY`/`ABL_NOFETCH`'s failure mode is characterised, not explained.** I know the arms
  execute no commands after init and that `vm_cycle` still advances; I do not know which skipped
  operation is load-bearing. **Until that is known, `ABL_NOCOPY`'s honesty argument (T-P0-035) should be
  treated as unproven for the GUEST build** — note its original evidence was a *host-side reference*
  diff, not a guest ablation, so the two may never have tested the same thing.
- ★★ **AD-83's decomposition needs re-deriving, not just re-labelling.** With floor 2.7% and the copy
  figure withdrawn, the remaining split is `interpret+post 97.3%` and `instrumentation 3.3%` — which
  does not decompose the 97.3% at all. **The decomposition is currently one number.**
- ★★ **`reg_discipline.py` still reads 8 against a recorded 5** (INFRA.1 §3.D). Untouched by this task.
- ★ **The `res`, `cel` and `comp` probes' counters have never been shown able to reach zero.** AC-6
  names this as unexamined rather than sound.
- ★ **Two clock measurements, two brackets:** 1.789417 MHz (640,000 cycles, this task) and 1.789772 MHz
  (160,009 cycles, INFRA.1). They agree to 0.02% and both are measurements; I have not investigated the
  0.02%.

**Triggers:** 1 does **not** fire (AD-87 holds). 2 **fires** (§3.E) and is reported with what it
invalidates. 3 **fires** (§3.A, the `jsr` was not the whole cause) and needed no fix. 4 does **not** fire
(`opcount` reaches zero). 5 does **not** fire (VM gate 9/9; 8/8 artifacts identical).

---

### 8 — Follow-up candidates

1. ★★★★ **Commit and push the repair.** It is unversioned on one disk. ★ **Partly unblocked since the
   body was written:** `coco_agi`'s `origin` is now HTTPS (`https://github.com/Jsearle01/coco_agi.git`),
   Git Credential Manager is installed, and the pool push proved the HTTPS path works with a PAT. What is
   still missing is a credential for **this** repo — the token supplied was scoped to the methodology
   store — plus `credential.helper` and a global identity (`user.name`/`user.email` are set only in the
   pool's local config). ★★ **The commit also needs a hash reported back:** the Orchestrator expects
   `ec86b83`, which has never existed here, so whatever hash the repair lands as will not match any prior
   reference. POP3_port and karateka_coco3 remain on SSH with no key.
2. ★★★ **Diagnose `ABL_NOCOPY`/`ABL_NOFETCH`**, or withdraw both arms from `vm_ablate.ps1`'s default set
   so nothing cites them again.
3. ★★★ **Re-derive AD-83's decomposition** with the working check and valid arms only.
4. ★★ **Re-check the straddle/flush pricing figures** taken from `PIC_STRADDLE` builds (AC-10).
5. ★★ **Apply AC-3's zero-on-an-empty-arm test to the `res`, `cel` and `comp` counters.**
6. ★ **Resolve `reg_discipline.py`'s 8-vs-5**, carried from INFRA.1.
7. ★ **M-50, the decomposition, is unblocked for AC-3** — but see item 3: it now rests on a
   decomposition with one term.

---

### 9 — User interaction during task

`None.`

### 10 — Candidate(s) captured this task

★★ **CORRECTED after the body was written.** This section first read `None.`, because the pool was
unreachable. Jay then supplied the pool credential, the repo was cloned, and **the three owed rows were
written and pushed**. Recorded as a correction rather than silently rewritten, per §8's read-back rule.

Pushed to `methodology-candidate-pool` **`main`**, commit **`92c10f3`** (`1032a73..92c10f3`), three files,
150 insertions:

- `seeds/AGI/live/2026-09-05-a-work-invariance-check-needs-two-sided-validation-zero-and-movement.md`
  — AC-3 needed both halves; a counter stuck at 0 satisfies the letter of L-79 and proves nothing.
- `seeds/AGI/live/2026-09-05-two-variants-agreeing-digit-for-digit-is-a-defect-signature-not-corroboration.md`
  — the same tell that caught inert `ABL_TITLE` (AD-94), now at its second instance (§3.E).
- `seeds/AGI/live/2026-09-05-a-repaired-instruments-first-job-is-to-invalidate-what-it-certified-while-blind.md`
  — the value of this task was not the zero; it was the two arms the zero let us see.

★★★ **INFRA.1 §10's premise was wrong and is corrected here:** it recorded that `seeds/AGI/` might need
creating on first capture. It exists and holds **105 live rows** (POP 205, karateka 114, claude-bridge 48,
cocobots 29). The pool was unreachable, not unpopulated — a negative about the environment standing in for
a fact about it, which is X-32's shape again.

★ **§2C's credential rule honoured:** the token appears only in the pool's `.git/config`, which is
untracked — never in CLAUDE.md, a candidate row, this report, or any commit. That is the arrangement
Karateka's §2C already records as authorized tech debt, and it **wants rotation**: the token was pasted
in a chat transcript.

★ Rows follow the AGI `live/` shape (`id` / `status: candidate` / `note`, prose body with **Why:** and
**How to apply:** and `[[…]]` links), matched against an existing row per §2C, not SCHEMA.md's generic
form — the two differ, and the existing rows are the operative convention.

### 11 — Commit

★ **CORRECTED.** This section originally read *"None — nothing was committed or pushed… push is
impossible on this machine as configured."* Both halves are now false, and the correction is recorded
rather than swapped in silently.

**The repair this report validates is `ec86b83`** — committed and pushed from the old laptop at
`Sat Sep 5 19:17:29 2026 -0400`, *"P4.7: the free-run counters were blind, and the clock was a literal"*,
4 files / 254 insertions / 16 deletions. **No new commit of the repair was needed or made.** A local
commit briefly duplicated it (`2e1ee91`, made before the remote was fetched); once the fetch showed the
two were byte-identical, the branch was reset onto `origin/wip` so history stays linear at
`ecf7d5c9 → ec86b83`. `2e1ee91` is unreferenced and unpushed.

**This task's own commit is the two Form B reports**, staged by explicit path per §2E:
`reports/20260905-213755-infra-1-new-machine-prove-it-reproduces.md` and
`reports/20260905-215455-p4-7-repair-the-work-invariance-check.md` — the only diff between local `HEAD`
and `origin/wip`. **Push works** via HTTPS with a PAT; §2E's push-before-report is honourable on this
machine, and the Orchestrator can fetch this report from `origin/wip` as normal. ★ POP3_port and
karateka_coco3 remain on SSH with no key and still cannot push.
