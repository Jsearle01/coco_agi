## Form B Report — P6.12 — The clock in both legs, and a regression that broke p3b
**Class:** build.  wip.

★★★★★ **The text work did NOT land.** AC-1, AC-3, AC-5, AC-6 and AC-11 are **NOT DONE**, and §7
trigger 5 fires on a memory-map finding that blocks them. What did land: a regression P6.11
introduced and P6.11's report denied, the reference's VSYNC clock, and the integrated gain.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-07 22:00:50 (HEAD `6d250bb`, wip). `git status` clean apart from untracked
`coco_agi.code-workspace`, an editor file, not staged (§2E, explicit-path only).

---

### 4' — Pre-dispatch grep (C-13), verbatim, before the summary

```
=== coco_agi ===   6d250bb P6.11 bound the object scan          wip   ?? coco_agi.code-workspace
=== POP ===        104b197 HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)   wip
=== Karateka ===   29f8f0a HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)   wip

=== hal_sync x3 ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, EOL/guard/export-placement normalised)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, EOL/guard/export-placement normalised)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, EOL/guard/export-placement normalised)

=== reg_discipline ===
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   8   $FFA5 $FFA6
```

★ **§2T baseline, cited not rebuilt.** POP `104b197` / Karateka `29f8f0a` are P6.11 §0's refs,
unchanged; lwasm 4.24 unchanged. No sibling artifact built; no shared file touched.

**The gate rows — and this is where the grep CONTRADICTED the tree, per §4's "contradiction → stop
and report":**

```
=== nine-title VM gate, vm_objtop live ===
Kingquest1 PASS  Kingquest2 PASS  Kingquest3 PASS  SpaceQuest-1 PASS  SpaceQuest-2 PASS
PoliceQuest1 PASS  larry1 PASS  BlackCauldron PASS  MixedUpMotherGoose PASS

=== p3b ===
lwasm.exe : src/harness/p3b_probe.s(916) : ERROR : User Specified:
  "P3b code overruns the map's code region -- see the .map for the size"
```

★★★★★ **p3b did not build.** Reported in §1 and §3.1.

**The clock, MEASURED in every arm** (L-78, AD-100): `clock MEASURED 1.789772 MHz (160009 cycles
calibrated)` on the p3b arms and `1.789417 MHz (640000 cycles)` on the VM arms. No arm divided by a
literal.

**Flag sets, enumerated and diffed** (L-77): one expected-on guard absent — p3b's `PIC_NOCOUNT`,
**not new and not mine**, now named by a fourth consecutive task. Disposition in AC-2.

---

### 1 — Summary

★★★★★ **P6.11 broke the p3b build and P6.11's report claimed it had not.** Its AC-1 said "all gates
unchanged"; I ran the VM gate and asserted the rest. `P3_CODE_END` was `$52FD` at `da2e5e4` (3 bytes
under `MAP_CODE_END`) and P6.11's object bound put it at `$5317` — **23 bytes over**. The build has
failed since that commit, and the only reason it surfaced is that this task's §4 grep runs p3b.

★★★★ **Fixed in two steps, both measured.** Making the mark INCLUSIVE — it points at the highest
active slot rather than one past it — removed the pointer arithmetic and recovered 9 bytes. The
remaining 14 came from M-48's own transformation applied once more: the command table ended in **14
consecutive entries that were all the same address**, `vm_op_modelled`, and a range branch replaces
them for 9 bytes. **p3b now has 5 bytes spare — more than the 3 it had before P6.11.**

★★★★★ **AC-7 done: the reference models the VSYNC clock**, 60 ticks to the second and 3 to an AGI
tick, and the nine-title diff is unchanged — which is the equivalence I wrote into the source
*before* running it, not an explanation afterwards.

★★★★ **The integrated gain, both sides measured: 11.98 → 14.98 cycles/s, +25.0%**, with `interpret`
down **10.43 ms/cycle** — matching the VM-side 10.06–10.49 ms from a different harness.

★★★★★ **AC-10 is the finding that blocks the task: M-48's reserve is SPENT.** All four dispatch
tables are now sized exactly to their opcode spaces. **A text engine plus a 2 KB glyph table cannot
be placed in `MAP_CODE`'s 5 remaining bytes**, and there is no padding left to reclaim. §7 trigger 5.

---

### 2 — Files modified

- `src/harness/vm_state.s` — the mark made inclusive (−6 bytes).
- `src/harness/vm_objects.s`, `src/harness/vm_run.s`, `src/harness/vm_cycle.s` — inclusive-mark
  loops and init; `vm_objhighp` storage now behind `-DVM_OBJCENSUS` (−2).
- `src/harness/vm_core.s` — the `VMOP_MODELLED_LO` dispatch branch, and AC-8's fault.
- `harness/tools/gen_vm_tables.py` — emits `VMOP_MODELLED_LO` and truncates the trailing modelled run.
- `src/harness/vm_tables.s` — **regenerated** (never hand-edited; drift check OK).
- `src/harness/p3b_probe.s` — `-DP3B_ACCEPT_OVERRUN` now also suppresses the code-region guard.
- `tools/agivm/cycle.py` — **AC-7**: the VSYNC clock.
- `harness/tools/vm_run.ps1` — `VM_MODELLED_FAULT` arm.
- `harness/tools/p3b_gain.ps1` — **new.** Integrated before/after, both sides built.

**No `src/engine/` file changed. No shared HAL file changed.**

---

### 3 — Reasoning

#### 3.1 ★★★★★ The regression, and why the VM gate could not see it

`vm_probe` and `p3b_probe` include the same VM sources but have different code budgets. `vm_probe`
has room; `p3b_probe` had **3 bytes**. P6.11 added 26 bytes of object-bound code to files both
include, and only p3b noticed.

★★★★ **L-85's shape, one task after I quoted L-85 about somebody else's corpus.** "All gates
unchanged" was a claim about the gate I ran. The lesson is not "run more gates" but that **a claim's
scope is the set you actually exercised**, and mine was one of two.

★ **`-DP3B_ACCEPT_OVERRUN` now suppresses the code-region guard too.** The error said "see the .map
for the size" and lwasm had written no .map, because it errored — the advice pointed at a file the
failure prevents from existing.

#### 3.2 §2H's three checks, on the table reclaim

1. **A SECOND mechanism?** ★★★ Yes — `VMOP_ARGS` is a parallel table indexed by the same opcode, and
   it is **not** truncated: argument counts differ per opcode and the dispatcher reads it for every
   command. Only the handler table has a redundant tail.
2. **Name the caller.** The branch sits in `vm_core.s`'s command dispatch beside M-48's existing
   `cmpa #VMOP_MAX`, and falls into the same `ldx` / `jsr ,x`, so opcount, the stacked opcode, the
   argument advance and `vm_exitall` run identically.
3. **Grep the reports before citing.** P3b-11's "455 bytes remain in `VMOP_ARGS` (73),
   `VMTEST_ARGS` (236)" is **stale** — both have since been sized to their opcode spaces. ★★★★ I
   went looking for that reserve and **measured** the tables instead of trusting the figure:
   `VMOP_ARGS` 183, `VMTEST_ARGS` 20, `VMTEST_TAB` 40, `VMOP_TAB` 338. **Nothing is padded.**

#### 3.3 AC-7 — what changed, and what did not

The reference advanced `virtual_ms += 25` per pacing iteration and gated on `time_delay * 2`. It now
counts `vsync += 1` and gates on `time_delay * 3`, with seconds as `vsync // 60`.

★★★★ **Equivalent for every non-zero `time_delay`** — 2 × 25 ms and 3 × 16.667 ms are both 50 ms —
**and NOT equivalent for zero**, which I wrote into the source before the run: `time_delay = 0` means
one tick, which was 25 ms and is now 16.667 ms. **The nine titles stayed 9/9, so none sets it to zero
in the gated window.**

★★★ **What this does NOT do**, and L-95 is the reason to say it: the port's default leg still
computes 25 ms steps, because its VSYNC clock is behind `-DVM_VBLCLOCK` and still crashes [AD-142].
Both legs produce the same seconds, so the gate is green — **but they are green by arithmetic
agreement, not because both are counting the same physical thing.** The reference is now expressed
in the unit the target can measure; the port will match it when the runaway is fixed. **The clock
ruling is still half-applied and this task did not close it.**

#### 3.4 §2S — ref and scope

Sibling claims are §0's citation at POP `104b197` / Karateka `29f8f0a`, both `wip`, scope = HEAD and
cleanliness. The "before" builds are `da2e5e4`, assembled here, not cited.

---

### 4 — Verification (AC-by-AC)

★★★★★ **AC-1 [eye-gated] — NOT DONE, and not "pending Jay".** There is nothing to show: no text
renders. §4A puts the eye gate first on an integration task, and the honest report is that this task
produced no visual surface. ★★ It was also **impossible for most of the task** — p3b did not build,
and p3b is the eye gate's probe.

- **AC-2 [byte-comparable] — PASS with one correction.** `hal_sync_check.py` OK ×3;
  `reg_discipline.py` 8 accesses, unchanged; `gen_vm_tables.py --check` OK. Nine-title gate **9/9**.
  **p3b builds again (5 bytes spare) — it did not at the start of this task.** §2T cited in §0.
  ★★ `flag_diff --manifest`: the single absence is p3b's `PIC_NOCOUNT`, pre-existing, **fourth task
  running**; it is why AC-9 declines to publish a p3b figure as comparable to anything but itself.

- **AC-3 [byte-comparable] — NOT DONE.** No text renders; no restore exists to compare.

- **AC-4 [state-comparable] — NOT DONE.** Depends on AC-3.

- **AC-5 [byte-comparable] — NOT DONE.** The input line is not implemented. AD-134's scheme remains
  proven readable at the matrix [AD-134] and unproven in software.

- **AC-6 [state-comparable] — NOT DONE.** `have.key` still spins; `get.string` is still absent.

- **AC-7 [state-comparable] — DONE.** `tools/agivm/cycle.py` counts vertical-sync ticks: 60 to the
  second, 3 to an AGI tick, seconds from the tick count rather than a millisecond accumulator.
  **Nine titles 9/9 byte-identical**, which is the equivalence test stated in the source before the
  run. The `time_delay == 0` non-equivalence is recorded at the line it affects. §3.3 states what
  remains open.

- **AC-8 [byte-comparable] — PASS, after my first fault was inert.** `-DVM_MODELLED_FAULT` drops the
  branch boundary so an implemented opcode is misrouted to `vm_op_modelled`:
  **MixedUpMotherGoose FAIL, 8 PASS.**
  ★★★★★ **The first version of this fault passed 9/9 and proved nothing.** I chose opcode `A0`
  because the corpus executes it 8 times — without checking that **`A0`'s own handler IS
  `vm_op_modelled`**, so misrouting it to `vm_op_modelled` was a no-op. The flag was verified to
  reach the build (hashes differ), so the fault was applied and inert. **A fault that cannot fail is
  the defect §2W exists to catch, and this one was mine.** `93` (`reposition.to`, executed 9 times,
  real handler) is the fault that works.
  ★★★ **Coverage, stated because it is thin:** of the 14 opcodes the branch serves, the corpus
  executes exactly **one** — `AD` (`hold.key`), **once**. A passing gate is nearly no evidence about
  the branch [L-86]; the fault is what carries it.

- **AC-9 [state-comparable] — PARTIAL, and the headline is NOT T3.** ★★★★★ **T3 as AD-135 defines it
  — 2.22 cycles/s AT 4 SPRITES, room 1 — is NOT re-taken.** The headless p3b arm performs no room
  jump, so it runs in room 83 with **zero** sprites. The first attempt produced 14.98 cycles/s and
  **that number is not T3**; labelling it so would be P6.10's room jump again.
  What is measured, both sides built and the arms asserted distinct:

  | attract mode, room 83, 0 sprites | before (`da2e5e4`) | after |
  |---|---|---|
  | median | 0.0834 s/cycle = **11.98 cyc/s** | 0.0668 s/cycle = **14.98 cyc/s** |
  | `interpret` | 0.07067 s/cycle (53.5%) | 0.06024 s/cycle (49.5%) |
  | `roomcheck` | 0.05705 s/cycle | 0.05705 s/cycle |

  ★★★★ **+25.0%, and `interpret` falls 10.43 ms/cycle** — against the VM free-run's 10.06–10.49 ms
  measured on a different harness in P6.11. **Two instruments, one number.** `roomcheck` is
  byte-identical between arms, which is the internal control: the bound does not touch it.
  ★★ The before arm reproduces P6.9's room-83 `interpret` figure (0.07067) exactly.

- **AC-10 [state-comparable] — DONE, and it is the blocker.** `P3_CODE_END = $52FB` against
  `MAP_CODE_END = $5300`: **5 bytes spare.** `MAP_RESERVED` unchanged at `$5300`.
  ★★★★★ **M-48's 455 bytes are SPENT.** Measured, not cited: `VMOP_ARGS` 183 = `VMOP_MAX`,
  `VMTEST_ARGS` 20 = `VMTEST_MAX`, `VMTEST_TAB` 40, `VMOP_TAB` 338 = `VMOP_MODELLED_LO` × 2. **No
  table carries padding.** The 28 bytes this task reclaimed were new territory beyond M-48 and went
  entirely to repairing P6.11.
  ★★★ **So the text work needs a memory-map decision, not a byte hunt** — §7 trigger 5, reported.

- **AC-11 [state-comparable] — NOT DONE.** The glyph source is a decision with provenance and it
  should not be made in passing; nothing was authored, so §2B's protection is not yet engaged.

- **AC-12 [state-comparable] — see §7.**

- **AC-13 [suite] — §10.**

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 (verbatim).** The gate, current build:
```
=== AC-2 SUMMARY ===
Kingquest1 PASS  Kingquest2 PASS  Kingquest3 PASS  SpaceQuest-1 PASS  SpaceQuest-2 PASS
PoliceQuest1 PASS  larry1 PASS  BlackCauldron PASS  MixedUpMotherGoose PASS
```
AC-8, the fault:
```
AC-2 ★★★ FAIL
Kingquest1 PASS ... BlackCauldron PASS   MixedUpMotherGoose FAIL
```
AC-8, the INERT first fault (recorded because it passed and proved nothing):
```
-DVM_MODELLED_FAULT at $A0 -> AC-2 PASS, 9/9
  flag OFF: 750CBCD983F2D533   flag ON: FE48FA0402DD49F6   differ: True
  A0 -> fdb vm_op_modelled  ; A0 disable.item(n)  [modelled]
```
The regression and its repair:
```
BEFORE (da2e5e4)  Symbol: P3_CODE_END = 52FD      MAP_CODE_END = 5300   ->   3 bytes spare
P6.11             Symbol: P3_CODE_END = 5317                            ->  23 bytes OVER
after inclusive mark                      = 530E                        ->  14 bytes OVER
after table reclaim                       = 52FB                        ->   5 bytes spare
```
Table reclaim, generator + drift check:
```
* ★★★★ 14 trailing `modelled` entries (A9-B6) are NOT emitted: vm_core.s
VMOP_MODELLED_LO equ     169
CHECK OK: src\harness\vm_tables.s matches optable.py.
```
AC-9, integrated before/after (`p3b_gain.ps1`):
```
before 13923 bytes   after 13921 bytes
★ arms verified distinct: vm_objtop absent in before, present in after
=== before ===  120 cycles in 17.6894 emulated s   median 0.0834 s/cycle = 11.98 cycles/second
   clock MEASURED 1.789772 MHz (160009 cycles calibrated)
   interpret 0.07067 s/cycle 53.5%   roomcheck 0.05705 s/cycle 43.2%   final room 83, sprites 0
=== after  ===  120 cycles in 15.7870 emulated s   median 0.0668 s/cycle = 14.98 cycles/second
   clock MEASURED 1.789772 MHz (160009 cycles calibrated)
   interpret 0.06024 s/cycle 49.5%   roomcheck 0.05705 s/cycle 46.9%   final room 83, sprites 0
```
AC-10, the reserve, measured:
```
VMOP_ARGS ~183 bytes   VMTEST_ARGS ~20 bytes   VMOP_TAB ~338 bytes   VMTEST_TAB ~40 bytes
VMOP_MAX equ 183   VMOP_MODELLED_LO equ 169   VMTEST_MAX equ 20
```
Final state: `vm_probe` 9,656 B and `p3b_probe` 13,921 B both assemble; `hal_sync` OK ×3;
`reg_discipline` 8; `gen_vm_tables --check` OK; encoding check clean on all touched files.

**25.2 bundled-artifact grep:** N/A — no bundled artifact; nothing shipped, no DECB image, no
`LOADER.BIN`.

**25.3 operator-runtime-smoke:** `N/A — no visual surface this task (AC-1 NOT DONE).` ★ The p3b
headless arm reached its OK prompt and ran 120 cycles clean, but that is a build-health check, not a
25.3 gate: nothing was rendered for a person to judge.

---

### 6 — Reactive deviations and route accounting

1. ★★★★★ **The task turned into a regression repair.** §4's grep found p3b broken; fixing it
   consumed the session and the text work did not start. **Not a §22.5 judgement call — a broken
   build in the tree outranks new work**, and it was mine.
2. ★★★★ **Three changes landed, and I gated them in two runs, not three** [L-54]. The inclusive mark
   and the VSYNC clock were gated together; both passed, so nothing is unattributed — **but a
   failure would have been ambiguous and I should have separated them.** The table reclaim was gated
   on its own.
3. ★★ **`gen_vm_tables.py` was edited rather than `vm_tables.s`**, which is generated and says DO NOT
   EDIT; the drift check is in 25.1.

**Route accounting.** I proposed no route. ★★★ What I described and did not deliver: nothing —
this report claims no text work. ★★★★ **What I nearly reported wrongly, twice:** a stale
`p3b_headless/run.log` from a previous run read exactly like a fresh result after the build failed
[L-92], and the fresh attract-mode figure read exactly like T3 [AD-135's is at 4 sprites]. Both were
caught by reading the run's own `final room 83, sprites 0` line.

---

### 7 — Uncertainty flags  (and AC-12: what the dispatch did not anticipate)

1. ★★★★★ **P6.11 shipped a broken p3b build and its report said otherwise.** The dispatch opened by
   crediting P6.11's result; the first thing this task found was that the same commit broke a gate.
2. ★★★★★ **My AC-8 fault was inert and passed 9/9**, because I misrouted an opcode to the handler it
   already used. Caught only by asking what `A0` actually is.
3. ★★★★★ **M-48's reserve is spent**, which the dispatch's trigger 5 assumed was available. The text
   work is blocked on a memory-map decision.
4. ★★★★ **The branch's corpus coverage is one execution of one opcode** (`AD`, once). The fault
   carries the evidence, not the pass [L-86].
5. ★★★ **AC-7 leaves the clock ruling half-applied** (§3.3): both legs agree arithmetically, neither
   is yet reading a real VBL in the default build.
6. ★★ **The `-DVM_VBLCLOCK` runaway is untouched** and remains unexplained [AD-142].
7. ★★ **T3 proper is still not re-taken.** The p3b headless arm cannot reach a populated room;
   `p3b_room.lua` exists and was not used.

---

### 8 — Follow-up candidates

1. ★★★★★ **The memory-map decision for text** (AC-10). No table padding remains; `MAP_CODE` has 5
   bytes. This is the gate on AC-3/AC-5/AC-6 and it is the Orchestrator's or Jay's.
2. ★★★★ **T3 in a populated room** — teach the headless arm the room jump, or use `p3b_room.lua`.
3. ★★★★ **p3b's missing `PIC_NOCOUNT`** — fourth task naming it.
4. ★★★ **The `-DVM_VBLCLOCK` runaway**, then the port's half of AC-7.
5. ★★ **A build-all check.** One command that assembles every probe would have caught the regression
   at P6.11 instead of a task later.

---

### 9 — User interaction during task

1. Jay: **"check the gate"** — mid-task, while the AC-8 fault arm was running. Answered by
   diagnosing the inert fault (§4 AC-8) rather than reporting its pass.

---

### 10 — Candidate(s) captured this task

`None.` ★ Two are worth writing and I did not want to file them from a task this eventful without
checking they are not restatements of L-86 and L-98: *a claim's scope is the set you exercised, not
the set you meant* (the p3b regression), and *a fault must misroute to a DIFFERENT handler than the
target already uses*. Flagged here rather than filed thin.

---

### 11 — Commit

See the commit carrying this report; pushed to `origin/wip` before reporting.
