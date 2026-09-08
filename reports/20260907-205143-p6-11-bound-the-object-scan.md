## Form B Report — P6.11 — Bound the object scan
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-07 20:51:43 (HEAD `da2e5e4`, wip). `git status` clean apart from untracked
`coco_agi.code-workspace`, an editor file, not staged (§2E, explicit-path only).

---

### 5' — Pre-dispatch grep (C-13), verbatim, before the summary

```
=== coco_agi ===
da2e5e4 P6.8b report: the VSYNC clock ruling -- source proved, vector page fixed, arm gated
wip
?? coco_agi.code-workspace

=== POP ===        104b197 HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)   wip
=== Karateka ===   29f8f0a HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)   wip

=== hal_sync x3 ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, EOL/guard/export-placement normalised)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, EOL/guard/export-placement normalised)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, EOL/guard/export-placement normalised)

=== reg_discipline ===
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   8   $FFA5 $FFA6
```

★ **§2T baseline, cited not rebuilt.** POP `104b197` / Karateka `29f8f0a` are the refs P6.10 §0
recorded, unchanged; lwasm 4.24 unchanged. **This task builds no sibling artifact and touches no
shared file**, so no sibling comparison is load-bearing.

**Gate rows — all pass from fresh builds** (25.1).

**Flag sets, enumerated and diffed** (L-77): one expected-on guard absent, **not new and not mine**
— p3b's `PIC_NOCOUNT`. Disposition in AC-8. `VM_OBJ_SCAN` no longer appears in any row (retired,
AC-8). `VM_OBJBOUND_FAULT` classifies correctly as an ablation.

**The clock, MEASURED in every arm** (L-78, AD-100), from the guest's own `VP_MARK`:
```
clock MEASURED 1.789417 MHz (640000 cycles calibrated, this session)
```
★ −0.02% against 14.31818/8 = 1.789773 MHz. **No arm was divided by a literal**; an arm whose log
carries no clock line is VOID.

★★★★ **The highest ACTIVE slot each corpus title uses — all nine, not the three the ablation
covered** (§5's last row) — is AC-7 below. **Max 15.**

---

### 1 — Summary

★★★★★ **The two object loops are now bounded by `vm_objtop`, a mark the interpreter maintains, and
it is raised AT THE FUNNEL rather than at the activation sites.** "Active" is three flag bits all
set, and the last of them is written at **seven** sites; hooking those by name is how a bound goes
stale, and the failure is a sprite that silently stops moving. All seven pass through
`vm_objflags_set` with the object already in X, so **one hook covers them by construction.**
`VMO_FLAGS` has exactly three writers in the tree and all three are accounted for (§3.1).

★★★★★ **Measured, the change saves 10.06–10.49 ms of every VM cycle — 20.1% to 21.0% of a 50 ms
AGI tick — in every room tested, from zero active objects to four.** It is above P6.10's 9.881 ms
prediction because bounding the loop also removed its counter.

★★★★★ **9/9 byte-identical on the nine-title gate, and the gate is shown able to FAIL on the bound
with a prediction that was specific before the run**: with raising disabled, exactly Kingquest1 and
PoliceQuest1 — the two titles whose census max is slot 0 — still pass, and the other seven fail.

★★★★ **The first version of the hook was conservative (raise on any flag write) and MEASUREMENT
KILLED IT**: in attract mode the mark pinned at 255 and the whole gain vanished. The shipped hook
raises only on a write that leaves the object active. Both were gated; the better one ships.

★★★ **AC-6: the 6.516 ms rooms-1-vs-2 residual is IDENTICAL in both arms.** It is not traversal.

---

### 2 — Files modified

- `src/harness/vm_objects.s` — `vm_objtop` (the bound) and `vm_objhighp` (the census); `vm_update_objs`
  bounded, counter removed; census update under `-DVM_OBJCENSUS`.
- `src/harness/vm_state.s` — the raise hook in `vm_objflags_set`, with the ACTIVE test;
  `VM_OBJ_SCAN` retired.
- `src/harness/vm_run.s` — `vm_check_all_motions` bounded, counter removed.
- `src/harness/vm_cmds.s` — `vmop_animate_obj`'s hook removed with the §2H reasoning recorded.
- `src/harness/vm_cycle.s` — `vm_objtop` reset in `vm_start`.
- `harness/tools/vm_run.ps1` — `VM_OBJCENSUS`, `VM_OBJBOUND_FAULT`, `VM_PROG_PREBUILT` arms;
  `VM_OBJ_SCAN` and `VM_OBJBOUND_TIGHT` retired with throws.
- `harness/tools/vm_sweep.lua` — publishes `vm_objhighp` and `vm_objtop`.
- `harness/tools/objbound_gain.ps1` — **new.** Before/after against a build of the previous revision.

**No `src/engine/` file changed. No shared HAL file changed.**

---

### 3 — Reasoning

**Authority tier: measurement of our own port** throughout. No claim rests on ScummVM or the Specs,
so §2.1's original-vs-normalisation distinction does not arise.

#### 3.1 §2H's three checks

1. **A SECOND mechanism serving a different object class?** ★★★★★ **Yes, twice, and both mattered.**
   *(a)* "Active" is `fAnimated|fUpdate|fDrawn` [`vm_objects.s:27`], and `fUpdate` alone is set at
   **seven** sites — `vm_cmds.s:306, 631, 716, 839, 873, 886` and `vm_run.s:369` — any of which
   completes the triple. The obvious hook (`vmop_draw`) is one of eight doors, not the door.
   *(b)* ★★★ **There are THREE MORE 255-slot loops I did not bound**, found only after the room-83
   measurement came out wrong: `vm_run.s:364`, `vm_cmds.s:286` (`unanimate.all`) and
   `vm_cycle.s:69` (`vm_start`, once per run). **None is per-cycle**, so none explains a per-cycle
   cost — but I found them by measuring, not by looking, and that is the finding (§7.2).
2. **Name the routine that CALLS it.** Both bounded loops are called unconditionally, once per
   cycle, from `vm_interpret_cycle` (`vm_cycle.s:194`, `:273`). ★★ **The caller is what made the
   traversal unavoidable: there is no "are there any objects?" test anywhere above them.**
3. **Grep the reports before citing a prior characterisation.** P6.10's `9.881 ms` and
   `74.0 cycles/slot` are this task's premise. ★★ **I did not carry them: the before-side is
   re-measured from a build of the P6.10 revision, because the inputs changed** (§2T — a citation
   is only valid while the inputs are unchanged, and here they are the thing that changed).

#### 3.2 The mechanism, and what it does when a slot above the mark becomes active

**It cannot happen.** `VMO_FLAGS` has exactly three writers:

| writer | can it make an object ACTIVE? | hooked? |
|---|---|---|
| `vm_state.s:331` — the OR in `vm_objflags_set` | **yes** — every one of the seven `fUpdate` sites and every `fDrawn` set reaches here | ★★★★★ **yes, this is the hook** |
| `vm_state.s:374` — the AND in `vm_objflags_clr` | no — clearing bits can only deactivate | not needed |
| `vm_cmds.s:265` — `animate.obj`'s direct `std` | **no** — it ASSIGNS `fAnimated+fUpdate+fCycling`, which clears `fDrawn` | not needed, reasoning recorded in-source |

★★★ **The mark never falls.** `unanimate.all` clears the flags on all 255 slots and the mark stays.
A high-water mark that decays needs a rule for when, and a wrong rule loses objects; the cost of
never falling is bounded by the census, and measured at slot 13 worst case in the rooms tested.
★★ **Reset in `vm_start`**, for the reason `VP_FREE`'s initialisation exists: a stale HIGH mark
costs only speed, a stale LOW one loses objects, and a re-init after `restart.game` could go that
way.

#### 3.3 ★★★★★ Why the conservative hook was measured and rejected

The first hook raised on **any** flag write — safe by construction, and I argued in-source that
"cheap and safe beats tight and reasoned-about". **The measurement disagreed:**

| room | active objects | conservative mark | tight mark |
|---|---|---|---|
| 83 (attract) | 0 | ★★★★ **255** | **1** |
| 1 | 4 | 13 | 13 |
| 2 | 4 | 13 | 13 |
| 3 | 2 | 3 | 2 |

★★★★★ **In attract mode the conservative mark pins at the ceiling** — something in Kingquest1's
attract sequence writes flags on a high slot without ever activating it — **so the bound bought
nothing there**: 1.269 ms saved against 10.492 ms for the tight hook, and that 1.269 is only the
removed loop counter. ★★★ The tight test is four instructions at the same funnel, keeps the funnel
property intact, and was gated to the same 9/9 before replacing the default.

★★ **The flag was then removed rather than left default-on:** a knob whose other position is
known-worse is not a configuration, it is a way to ship the worse one by accident.

#### 3.4 §2S — ref and scope of the sibling claim

The only sibling claim is §0's citation at POP `104b197` / Karateka `29f8f0a`, both `wip`, scope =
HEAD and working-tree cleanliness. No sibling artifact built or compared.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable]** — `reg_discipline.py` 8 accesses / `mmu_phase.s` / `$FFA5 $FFA6`,
  unchanged. `hal_sync_check.py` OK ×3. §2T citation in §0. — 25.1.

- **AC-2 [state-comparable]** — ★★★★★ **The mechanism is `vm_objtop`, a pointer one past the last
  slot walked, raised at the `vm_objflags_set` funnel on writes that leave the object ACTIVE, reset
  in `vm_start`, never falling.** §3.2 answers *what happens when a slot above the mark becomes
  active*: **it cannot**, because all three writers of `VMO_FLAGS` are enumerated and the only one
  that can activate is the hooked one. ★★ "It is set at room load" is explicitly **not** the answer
  — the hook is on the activation itself.

- **AC-3 [byte-comparable]** — ★★★★★ **Nine-title state gate 9/9 byte-identical, empty exclusion
  set, at whatever the mechanism produces** (marks of 1, 2 and 13 in the rooms measured; not a
  fixed bound). — 25.1.
  ★★★★ The shipped default is **byte-identical (SHA-256 `05F56F5A454A2F9C…`) to the arm that scored
  that 9/9**, so the result transfers by hash rather than by assertion.

- **AC-4 [byte-comparable]** — ★★★★★ **The gate FAILS on the bound, and on exactly the predicted
  titles.** `-DVM_OBJBOUND_FAULT` disables the **raising** (it does not clamp the value — clamping
  would not stick, because the next `vm_objflags_set` would lift it again and the fault build would
  behave like the good one, which is a fault injection that cannot fail). **Prediction, made from
  AC-7's census before the run: the two titles whose max active slot is 0 must PASS, the other
  seven must FAIL.** Observed exactly that. — 25.1.
  ★★★ The fault binary is **byte-identical (`AB9431B77B924237…`) to the one that result was measured
  on**, after the default changed — so AC-4 stands without a re-run.

- **AC-5 [state-comparable]** — ★★★★★ **THE GAIN, measured, clock measured in every arm.** Before =
  a build of the P6.10 revision (`da2e5e4`), not a knob.

  | room | active objs | `vm_objtop` | before | after | **saved** | % of 50 ms tick | VM cycles/s |
  |---|---|---|---|---|---|---|---|
  | 83 (attract) | 0 | 1 | 67.802 ms | 57.310 ms | **10.492** | **21.0%** | 14.75 → 17.45 |
  | 1 | 4 | 13 | 113.495 | 103.433 | **10.062** | 20.1% | 8.81 → 9.67 |
  | 2 | 4 | 13 | 120.011 | 109.949 | **10.062** | 20.1% | 8.33 → 9.10 |
  | 3 | 2 | 2 | 79.154 | 68.693 | **10.461** | 20.9% | 12.63 → 14.56 |

  ★★★★ **A true constant, independent of object count — which is what the P6.10 ablation predicted
  — and slightly LARGER than its 9.881 ms**, because bounding the loop also removed the per-slot
  `pshs b` / `puls b` / `decb`. `opcount` is identical between paired arms in every room.
  ★★★★★ **T3 is NOT re-taken, and that is a gap, not an omission.** T3 is the p3b **integrated**
  figure and p3b's timing builds are the ones `flag_diff` flags as missing `PIC_NOCOUNT`
  ("counters cost 2.16x; a timing figure taken with them is not comparable"). **Re-taking T3 on
  that build would publish a number I would have to withdraw.** ★★ For scale only, and **labelled
  unverified arithmetic, not a finding** (§8): 10.3 ms off AD-135's 450 ms integrated cycle is
  ≈2.3%, i.e. 2.22 → ≈2.27 cycles/s. **The VM-side saving is 20%; the integrated saving is small
  because the integrated cycle is dominated by something else.**

- **AC-6 [state-comparable]** — ★★★ **The residual is UNCHANGED: 6.516 ms in both arms**, to three
  decimals (room 1 vs room 2: 113.495/120.011 before, 103.433/109.949 after). ★★★★ **Bounding the
  scan does not touch it, so it is a real per-room cost and not traversal** — which closes the
  question §3 of the dispatch left open, in the direction that keeps it alive. **Trigger 5 does not
  fire.** Reported, not chased.

- **AC-7 [state-comparable]** — ★★★★★ **The highest ACTIVE slot per corpus title, all nine**,
  measured in the guest on the loop the bound governs (`-DVM_OBJCENSUS`, `vm_objhighp`):

  | title | slot | | title | slot |
  |---|---|---|---|---|
  | Kingquest1 | 0 | | MixedUpMotherGoose | 9 |
  | PoliceQuest1 | 0 | | SpaceQuest-1 | 9 |
  | larry1 | 2 | | SpaceQuest-2 | 12 |
  | BlackCauldron | 7 | | **Kingquest3** | **15** |
  | Kingquest2 | 7 | | | |

  ★★★★★ **Max 15 — and P6.10's ablation used `VM_OBJ_SCAN=16`. That "behaviour-neutral, 9/9" proof
  was passing with exactly ONE SLOT of margin**, and had Kingquest3 used slot 16 it would have
  failed. ★★★ **That is the argument for a maintained bound over any fixed one**, and it is
  measured rather than asserted. **Trigger 3 does not fire**: 15 is not a high slot, and the bound
  is dynamic in any case.
  ★★ Scope, per L-85: 600 cycles of nine titles. **It is not a claim that no AGI game ever uses a
  higher slot** — which is exactly why the shipped bound is maintained, not fixed at 16.

- **AC-8 [byte-comparable]** — ★★★ **The `vm` manifest row.** AD-140's premise is right and
  **flipping the field would be wrong**: the 9/9 diff genuinely is a correctness gate, and
  `flag_diff.py:121-125` exempts those from `EXPECTED_ON` deliberately. **The defect was a missing
  row, and it was fixed in P6.10** — `vm_timed`, `purpose=timing`, which asserts
  `HAL_SYS_FAST_CLOCK` for the free-run build the timing figures actually come from. Verified
  present and clean this task (25.1).
  **Every remaining row dispositioned, line by line:**

  | row | disposition |
  |---|---|
  | `pic`, `res`, `cel`, `comp`, `vm` | `purpose=correctness`; `EXPECTED_ON` correctly not applied. Clean. |
  | `pic_nc`, `pic_nc_pk`, `pic_win` | timing; `PIC_NOCOUNT` present. The `~ HAL_SYS_FAST_CLOCK absent but HAL_gfx_set_mode is called` note is **correct and remains true** — fast mode is reached that way. |
  | `vm_timed` | timing; `HAL_SYS_FAST_CLOCK` ON. **Clean.** `VM_NOCOUNT` deliberately in the ablation class, not expected-on: measured at 1.44% [P3b.2] / 3.40% [P4.6], not `PIC_NOCOUNT`'s 2.16× class. |
  | `p3b` | ★★★★ **`PIC_NOCOUNT` EXPECTED-ON BUT ABSENT — a real finding, third right row, and OUT OF SCOPE here** (§3: one change, measured). It is the reason AC-5 declines to re-take T3. Carried to §8. |

  ★ **No row dispositioned as "noisy."** ★★ `VM_OBJ_SCAN` was retired this task because it had
  become a **dead knob that `flag_diff` reported as ON in every row** — a live-looking
  configuration that nothing read (§7.3).

- **AC-9 [state-comparable]** — ★★★★ **What the dispatch did not anticipate**, five things:
  1. ★★★★★ **The right hook is the FUNNEL, not the activation sites.** The dispatch's "what happens
     when a slot above the mark becomes active" has a structural answer, not a policy one.
  2. ★★★★★ **The conservative hook loses the entire gain in attract mode** (mark 255, 1.269 ms).
     The dispatch assumed a maintained bound would help; it helps only if it is raised on the right
     event, and that took a measurement to discover.
  3. ★★★★★ **AC-7's census max is 15 against P6.10's bound of 16** — a one-slot margin under a
     result that had read as comfortable.
  4. ★★★★ **The gain EXCEEDS the ablation's prediction** (10.06–10.49 vs 9.881 ms) because the
     bound took the loop counter with it. Trigger 4 is the *inverse* of what fired.
  5. ★★★ **Three further unbounded 255-slot loops exist** (§3.1), found by measurement not by
     looking.

- **AC-10 [suite]** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

AC-3 — nine-title gate, the shipped build:
```
=== AC-2 SUMMARY ===
Kingquest1 PASS   Kingquest2 PASS   Kingquest3 PASS
SpaceQuest-1 PASS SpaceQuest-2 PASS PoliceQuest1 PASS
larry1 PASS       BlackCauldron PASS MixedUpMotherGoose PASS
```

AC-4 — the same gate with `-DVM_OBJBOUND_FAULT`:
```
=== AC-2 SUMMARY ===
Kingquest1           PASS
Kingquest2           FAIL
Kingquest3           FAIL
SpaceQuest-1         FAIL
SpaceQuest-2         FAIL
PoliceQuest1         PASS
larry1               FAIL
BlackCauldron        FAIL
MixedUpMotherGoose   FAIL
```
★ Predicted before the run from AC-7's census: Kingquest1 and PoliceQuest1 (max active slot 0) pass.

Binary identity, so AC-3 and AC-4 transfer to the shipped default without re-running:
```
=== does the new DEFAULT match the gated arm byte-for-byte? ===
  default 05F56F5A454A2F9C
  tight   05F56F5A454A2F9C
  MATCH: True
=== does the FAULT build still match the one AC-4 was measured on? ===
  new  AB9431B77B924237
  AC-4 AB9431B77B924237
  MATCH: True
```

AC-5 — the gain (`objbound_gain.ps1`, before = build of `da2e5e4`):
```
★ arms verified distinct: vm_objtop absent in before, present in after
  room 83   before   67.802 ms   after   66.533 ms   (conservative hook)
  room 1    before  113.495 ms   after  103.433 ms   saved  10.062 ms =  8.9%  ( 20.1% of a 50 ms AGI tick)
  room 2    before  120.011 ms   after  109.949 ms   saved  10.062 ms =  8.4%  ( 20.1% of a 50 ms AGI tick)
  room 3    before   79.154 ms   after   68.729 ms   saved  10.425 ms = 13.2%  ( 20.9% of a 50 ms AGI tick)

  === shipped (ACTIVE-only raise) ===
  TIGHT room 83   objs 0  vm_objtop slot 1    57.310 ms/cycle   102552 CPU cycles/VM cycle  17.4 VM cycles/s
  TIGHT room 1    objs 4  vm_objtop slot 13  103.433 ms/cycle   185085 CPU cycles/VM cycle   9.7 VM cycles/s
  TIGHT room 2    objs 4  vm_objtop slot 13  109.949 ms/cycle   196745 CPU cycles/VM cycle   9.1 VM cycles/s
  TIGHT room 3    objs 2  vm_objtop slot 2    68.693 ms/cycle   122920 CPU cycles/VM cycle  14.6 VM cycles/s
clock MEASURED 1.789417 MHz (640000 cycles calibrated, this session)   [every arm]
```

AC-6 — the residual:
```
  before(255 fixed)  room1 113.495 ms   room2 120.011 ms   residual 6.516 ms
  after (vm_objtop)  room1 103.433 ms   room2 109.949 ms   residual 6.516 ms
```

AC-7 — the census (`-DVM_OBJCENSUS`, per title):
```
  BlackCauldron        highest ACTIVE slot = 7
  Kingquest1           highest ACTIVE slot = 0
  Kingquest2           highest ACTIVE slot = 7
  Kingquest3           highest ACTIVE slot = 15
  larry1               highest ACTIVE slot = 2
  MixedUpMotherGoose   highest ACTIVE slot = 9
  PoliceQuest1         highest ACTIVE slot = 0
  SpaceQuest-1         highest ACTIVE slot = 9
  SpaceQuest-2         highest ACTIVE slot = 12
```
★ The census run was itself 9/9, so the census build is behaviour-neutral.

AC-8 — `flag_diff.py --manifest`, the only absence:
```
── p3b  (src/harness/p3b_probe.s)  [timing] ──
   ★★★ EXPECTED-ON BUT ABSENT: PIC_NOCOUNT
       counters cost 2.16x; a timing figure taken with them is not comparable
★★★ 1 expected-on guard(s) absent. Every timing figure from such a build is suspect.
```

`hal_sync_check.py` ×3 and `reg_discipline.py` — verbatim in §0.

**25.2 bundled-artifact grep:** N/A — no bundled artifact; nothing shipped, no DECB image built,
no `LOADER.BIN` touched.

**25.3 operator-runtime-smoke:** `N/A — no visual surface this task.` ★ Nothing reaches the screen:
the change is inside two object loops and the gates are byte comparisons.

---

### 6 — Reactive deviations and route accounting

1. ★★★★★ **The hook was replaced mid-task after measurement.** The conservative version (raise on
   any flag write) was implemented, gated 9/9, measured, and **rejected on its numbers**; the
   ACTIVE-only version replaced it and was gated to the same 9/9. §22.5 deviation from my own first
   design, not from the dispatch — §2 asked for "whatever the object lifecycle actually supports"
   and did not name a mechanism.
2. ★★★ **`VM_OBJ_SCAN` and `VM_OBJBOUND_TIGHT` were retired with throws**, not left inert. Beyond
   the dispatch, and the reason is in AC-8/§7.3.
3. ★★ **`VM_PROG_PREBUILT` was added to `vm_run.ps1`** so the before-arm could be a build of the
   previous revision. An instrument change, not a target change.

**Route accounting.** I proposed no route. ★★★★ **What I described mid-task and had to correct:
I reported the conservative hook's "cheap and safe beats tight" reasoning in the source before
measuring it, and the measurement refuted it.** The in-source comment now records both. **AC-5's
first sweep also reported a gain of 0.000 ms in all four rooms and I did not report that as a
result** — see §7.1.

---

### 7 — Uncertainty flags

1. ★★★★★ **My own before/after sweep was initially the same program twice, and it is only luck of
   presentation that it was caught.** `objbound_gain.ps1` put `-I.` before `-I$srcRoot`, so the
   extracted revision's `include "src/harness/*.s"` all resolved to today's tree and both arms were
   today's binary. **The tell was before and after identical to three decimal places in four
   rooms** — the same signature as P6.10's silent room jump, one task later, and I had written a
   pool candidate about that failure mode hours earlier. Fixed, and the script now **asserts
   `vm_objtop` is absent from the before map and present in the after** before it will report a
   number. ★★ **The clock-line VOID branch remains untested** (asserted, not demonstrated).
2. ★★★ **Three 255-slot loops remain unbounded** (§3.1). None is per-cycle so none is on the hot
   path, but **I have not measured them** and "not per-cycle" is a reading of the callers, not a
   measurement. §8.
3. ★★ **`VM_OBJ_SCAN` was retired, so P6.10's ablation is no longer reproducible by a flag.** The
   supersession and how to reproduce it (build that revision) are recorded in-source at the point
   the symbol used to be defined. Reports citing it remain valid at their own ref.
4. ★★ **AC-5's figures carry the VM counters** (`VM_NOCOUNT` measured at 1.44%/3.40%), stated
   rather than silent. **T3 is not re-taken** — AC-5.
5. ★ **The census and the gain are Kingquest1 for the room sweep**, nine titles for the census and
   both gates. Rooms 1/2/3 are one title's rooms; the constancy of the 10.06–10.49 ms across four
   rooms and three object counts is the evidence it is a constant, not a claim about all titles.

---

### 8 — Follow-up candidates

1. ★★★★ **The three unbounded 255-slot loops** (§3.1) — `vm_run.s:364`, `vmop_unanimate_all`,
   `vm_start`. Measure before bounding; two of them clear flags and the third is once per run.
2. ★★★★ **p3b's missing `PIC_NOCOUNT`** — it blocks re-taking T3 and makes every p3b timing figure
   suspect, including P6.9's `+431%` table. **This is now the third task to name it.**
3. ★★★★ **The 6.516 ms rooms-1-vs-2 residual is confirmed real** (AC-6). It is not traversal and
   not object count and not opcount. Next question.
4. ★★★ **The zero-object floor is now 57.310 ms/cycle** and is the largest remaining item —
   `res_cache_flush` and AD-106's surviving resource copy live in it.
5. ★★ **`objbound_gain.ps1`'s clock-VOID branch** wants a red test (§7.1).

---

### 9 — User interaction during task

`None.`

---

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-08-maintain-an-invariant-at-the-chokepoint-not-at-the-call-sites.md`
- `seeds/AGI/live/2026-09-08-a-fault-injection-should-predict-which-cases-fail-not-just-that-some-do.md`

---

### 11 — Commit

See the commit carrying this report; pushed to `origin/wip` before reporting.
