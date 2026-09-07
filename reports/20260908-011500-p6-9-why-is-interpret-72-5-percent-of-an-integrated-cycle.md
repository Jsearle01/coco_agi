## Form B Report — P6.9 — Why is `interpret` 72.5% of an integrated cycle?
**Class:** recon.  wip.  ★★★★★ **§7 trigger 5 fired: the 72.5% is real and the LABEL is wrong.**

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-08 ~00:40 local (HEAD `4c6df81`, wip). Clean apart from untracked
`coco_agi.code-workspace`. **No code changed this task.**

---

### 4 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `4c6df81`, `wip`, clean |
| POP + Karateka | §2T: P6.7 §0's `104b197` / `29f8f0a`, **both unchanged** |
| `hal_sync_check.py` | **OK in all three** — §5 |
| the gate rows | ★★ **cited, not re-run** — no gated file touched (§7.5) |
| **flag sets, BOTH builds** | ★★★★ **§3.A — comparable on the VM axis** |
| **`flag_diff --manifest`, every row** | ★★★★ **all nine dispositioned — §3.E** |
| the clock — measure it | ★★ **not measured this task**; no new timing figure is published — every figure here is P6.7's or the reference's |
| `opcount` on the pace-only arm | ★★ **not run — no ablation build was made** (§3.D, §7.2) |

---

### 1 — Summary

★★★★★ **The 72.5% is correct and "interpret" is not the interpreter.**

p3b's `interpret` bracket contains **`vm_check_all_motions` and `vm_update_objs`** as well as the
bytecode. **Both are O(active screen objects).** ★★★★ **Room 83 — where the standalone 15.7
cycles/second was measured — has ZERO screen objects. Room 1 has four.**

★★★★★ **So the comparison the dispatch is built on is not an integration comparison at all.** It
puts attract mode against a live room:

| | instructions/cycle | resource bytes/cycle | p3b `interpret` |
|---|---|---|---|
| room 83 (attract, 0 objects) | **107.6** | **13,714** | **0.07067 s** |
| room 1 (live, 4 objects) | **138.0** | **15,357** | **0.37547 s** |
| | **+28%** | **+12%** | ★★★★★ **+431%** |

★★★★ **Neither VM-side quantity explains the time.** ★★★★★ **Because the cost is native per-object
work that a bytecode counter cannot see** — which is also why five tasks of instruction-level
thinking never found it.

★★★ **Same-room, like-for-like, integration costs +31%** (15.7 → 11.98 cycles/s), not 7×.
★★ **AC-5's answer: the resource copy is NOT the driver here** — +12% of bytes.

★★★★ **And AC-7 found a second misclassified row:** the `vm` manifest row is `purpose=correctness`
while the project's headline VM timing figure — the 15.7 — comes from it, so the expected-on check
is switched off for exactly the build AC-2 needed to verify.

---

### 2 — Files modified

**None.** ★★★ **Recon. Nothing was changed, per §2 and §11.**

---

### 3 — Reasoning

#### 3.A ★★★★ AC-2 — the builds are comparable; the WORKLOADS are not

**The flag sets, from `gates.manifest`:**

```
vm    -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK
p3b   -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED
```

★★★ **On the VM axis they are the same configuration:** both carry the fast clock, and **neither
passes `VM_NOCOUNT`**, so both count VM opcodes and pay the same counter cost on the dispatch path
[`vm_core.s`]. ★★ p3b's two extra flags are **plane** flags — they change `pic_core`/`composite`
addressing, not `vm_*`. ★ So AD-136's trap is checked and is **not** what is happening here.

★★★★★ **The incomparability is elsewhere and it is larger.** The 15.7 figure is KQ1 in **attract
mode**: `vm_probe` runs the game as it starts, and KQ1 never leaves room 83 — measured at 300
cycles [p3b_room.lua; and P6.7 §7.4 measured *why*: it polls `have.key` once and `controller`
twelve times per cycle, waiting for input]. **Room 83 has zero screen objects.** The 2.22 figure is
room 1 with four.

> ★★★★★ **15.7 and 2.22 are not the same program doing the same work in two harnesses. They are
> two different workloads.**

#### 3.B ★★★★★ AC-3/AC-4 — where the 72.5% goes, and what `interpret` actually is

**Every `jsr` inside the 6809's `vm_interpret_cycle`** [`vm_cycle.s`]:

```
  vm_setvar    x6      vm_step_clock        x1
  vm_setflag   x4      vm_update_objs       x1     <-- O(objects)
  vm_obj       x3      res_cache_flush      x1
  vm_reset_ctrl x2     vm_check_all_motions x1     <-- O(objects)
  vm_getvar    x2      vm_call_logic0       x1     <-- the bytecode
```

★★★★★ **`vm_check_all_motions` and `vm_update_objs` are inside the bracket labelled `interpret`.**
The reference has the same shape — `motion.check_all_motions(self)` then the `run_logic(0)` loop
then `objects.update_screen_obj_table` [`cycle.py interpret_cycle`] — so this is **the oracle's
structure faithfully ported**, not a port artifact.

★★★★ **The measurements that isolate it** (the reference, KQ1, 200 cycles, window 20–200):

```
room 83 (attract)      cycles 179  instructions 19252  = 107.6 per cycle  rooms {83: 180}
room 1 (jumped at 8)   cycles 179  instructions 24702  = 138.0 per cycle  rooms {1: 180}

logics entered, room 83 : {0: 201, 83: 200, 102: 200}
logics entered, room 1  : {0: 201, 102: 200, 101: 193, 1: 192, 83: 8}
```

★★★★★ **+28% bytecode against +431% wall time.** The bytecode instruction counter — the project's
main VM instrument — **cannot see the difference**, because motion and object updates are native
6809 routines, not interpreted opcodes. ★★★ **That is why this survived five tasks of looking at
the VM: every instrument pointed at it counts the thing that did not change.**

★★ **A two-point estimate of the split, labelled as such** [L-41: a ratio is not a cost]. If the
bytecode share scales with instruction count, room 1's bytecode ≈ 0.07067 × 1.28 ≈ **0.0905 s**,
leaving ≈ **0.285 s/cycle — about 76% of the bracket — in per-object work**, ≈ 0.071 s per object
per cycle. ★★★★ **This is two points and an assumption, NOT an ablation** (§7.2), and I am not
entitled to call it a measurement.

#### 3.C AC-5 — the resource copy is not the driver here

**Resource bytes bound per cycle**, counting each `run_logic` entry against its RESOURCE size (not
its bytecode — `vm_state.s` records logic 0 as an 8,999-byte resource against 3,904 of bytecode):

| room 83 | | room 1 | |
|---|---|---|---|
| logic 0 ×201 | 8,999 B | logic 0 ×201 | 8,999 B |
| logic 102 ×200 | 3,817 B | logic 102 ×200 | 3,817 B |
| logic 83 ×200 | 853 B | logic 101 ×193 | 929 B |
| | | logic 1 ×192 | 1,631 B |
| **per cycle** | **13,714 B** | **per cycle** | **15,357 B** |

★★★ **+12%.** ★★★★ **AD-106's 63.6% was a KQ3-versus-KQ1 figure — a different comparison** — and it
does not transfer to room-83-versus-room-1 within KQ1. **The copy is a large constant in both
rooms, not the variable that moved** [L-54: attribute separately].

★★ **It remains a large constant**: ~13.7 KB of resource copied per cycle in *both* rooms is the
standing cost AD-106 named, and this task does not close it.

#### 3.D ★★★ AC-6 — what is unattributed, stated not distributed

★★★★ **The 76% figure in §3.B is an estimate from two points, not an ablation**, and I have not
separated:

- `vm_check_all_motions` from `vm_update_objs` — **both O(objects), neither measured alone**;
- either of them from the extra bytecode room 1 runs;
- the `res_cache_flush` per cycle.

★★★ **A real ablation needs a build with the per-object work switched off**, and §2/§11 put change
out of scope. ★★ **Five tasks have declined to distribute the unattributed remainder and this one
declines too.**

#### 3.E ★★★★ AC-7 — every row dispositioned

| row | disposition |
|---|---|
| `pic [correctness]` | ★★ **Correct.** `PIC_NOCOUNT`/`HAL_SYS_FAST_CLOCK` off is right for a byte gate; the manifest note already says *"counters in — not a perf figure"*. |
| `pic_nc`, `pic_nc_pk`, `pic_win` `[timing]` | ★★ **Correct.** Each carries `PIC_NOCOUNT`; `HAL_SYS_FAST_CLOCK` absent is excused by `flag_diff`'s own `HAL_gfx_set_mode` check, which pic calls. |
| `res [correctness]` | ★★ **Correct.** Byte-identity gate; the clock cannot change a byte. |
| `cel [correctness]` | ★★ **Correct.** |
| `comp [correctness]` | ★★★ **Correct, and note `HAL_GFX_MODE_SERVICE` is OFF** — comp is the only probe without it, which `run_gates.sh` records as recovered by byte-match ("comp 967 = no flags"). Not a defect. |
| **`vm [correctness]`** | ★★★★★ **WRONG, and it matters to this task.** The project's headline VM timing figure — **15.7 cycles/second** — comes from this build, so the row publishes a *timing* number while declared *correctness*. ★★★ **`EXPECTED_ON` is not applied to correctness rows** — I built that rule in P6.5 — **so nothing checks the configuration of the very build AC-2 exists to verify.** ★★ Currently harmless (its flags do carry `HAL_SYS_FAST_CLOCK`), and it disables the check that would catch the next one. |
| `p3b [timing]`, `PIC_NOCOUNT` absent | ★★★★★ **Correct, and it was right again.** P6.7 §3.A: comparing p3b's render against the 2.832 s `pic_nc_pk` figure would have reported a 2.3× integration cost that does not exist. **Third task running in which this row was right** [L-94]. |

★★★ **"Over-reports" is not a disposition and none of the above says it.**

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] — PASS.** `hal_sync_check` OK ×3; `reg_discipline` unchanged at 8 in
  `mmu_phase.s`; §2T cited. **No gated file touched.**
- **AC-2 [byte-comparable] — ANSWERED, and the answer is "yes on the build, no on the workload".**
  §3.A. ★★★★ **§7 trigger 2's spirit fires**: the gap this task exists to explain is not the gap it
  was described as.
- **AC-3 [state-comparable] — PARTIAL.** §3.B locates the 72.5% structurally — motion + object
  updates + bytecode — but **the split is a two-point estimate, not an ablation**, and `opcount`
  per arm is **not reported because no arms were built** (§3.D, §7.2).
- **AC-4 [state-comparable] — ANSWERED, specifically.** ★★★★★ **What `interpret` does integrated
  that it does not standalone: per-object motion and screen-object updates for four objects instead
  of zero** — and the standalone figure had them switched off by its workload, not by its build.
  ★★ **"It is slower" is not the answer given.**
- **AC-5 [state-comparable] — ANSWERED.** §3.C. **+12%; not the driver here**, and AD-106's 63.6%
  is a different comparison.
- **AC-6 [state-comparable] — ANSWERED.** §3.D. **Stated, not distributed.**
- **AC-7 [state-comparable] — ANSWERED.** §3.E, all nine rows, one found wrong.
- **AC-8 [state-comparable] — see §6.** Ranked by measured share. ★★★★★ **Ranked, not acted on.**
- **AC-9 [state-comparable] — §7.1.**
- **AC-10 [suite] — one candidate.** §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — AC-2, both builds' flags (verbatim from `gates.manifest`):**

```
vm    -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK
p3b   -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED
```

**25.1 — AC-3/AC-4, the bracket's contents (verbatim, `jsr`s inside `vm_interpret_cycle`):**

```
  vm_setvar                x6        vm_step_clock            x1
  vm_setflag               x4        vm_update_objs           x1
  vm_obj                   x3        res_cache_flush          x1
  vm_reset_ctrl            x2        vm_check_all_motions     x1
  vm_getvar                x2        vm_call_logic0           x1
```

★ Two-column layout mine; names and counts as the grep produced them.

**25.1 — AC-4, the workload difference (verbatim):**

```
room 83 (attract)          cycles 179   instructions 19252     =   107.6 per cycle   rooms {83: 180}
room 1 (jumped at 8)       cycles 179   instructions 24702     =   138.0 per cycle   rooms {1: 180}

logics entered, room 83 : {0: 201, 83: 200, 102: 200}
logics entered, room 1  : {0: 201, 102: 200, 101: 193, 1: 192, 83: 8}
```

**25.1 — AC-5, resource bytes per cycle (verbatim):**

```
=== room 83 (attract) ===
  logic   entries  res bytes  bytes total
  0           201       8999      1808799
  83          200        853       170600
  102         200       3817       763400
  per cycle                                  : 13714 bytes

=== room 1 (jumped at 8) ===
  0           201       8999      1808799
  102         200       3817       763400
  101         193        929       179297
  1           192       1631       313152
  83            8        853         6824
  per cycle                                  : 15357 bytes
```

**25.1 — AC-7, the row that is wrong (verbatim):**

```
── vm  (src/harness/vm_probe.s)  [correctness] ──
   OFF (6): AGI_PAL_READBACK OBJTARGET PAR_FAULT_FIRST_MATCH POP_HAL_RUNTIME_BLIT VM_FAULT_SAID_PURE VM_TRACE
── p3b  (src/harness/p3b_probe.s)  [timing] ──
   ★★★ EXPECTED-ON BUT ABSENT: PIC_NOCOUNT
       counters cost 2.16x; a timing figure taken with them is not comparable
```

**25.1 — `hal_sync_check.py` / `reg_discipline.py` (verbatim):**

```
coco_agi        [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port       [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3  [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s                       8  $FFA5 $FFA6
```

**25.2 — bundled-artifact grep:** N/A — no binary is built or shipped by this task.

**25.3 — operator-runtime-smoke:** **N/A — no visual surface this task.**

---

### 6 — AC-8: candidates, ranked by MEASURED share. **Ranked, not acted on.**

| # | candidate | measured share | strength of evidence |
|---|---|---|---|
| **1** | ★★★★★ **Per-object work in `vm_interpret_cycle`** — `vm_check_all_motions` + `vm_update_objs`, O(objects) | ★★★ **≈76% of the bracket, ≈0.285 s/cycle at 4 objects** | ★★ **two-point estimate**, §3.B — the structure is certain, the share is not |
| **2** | ★★★ **The standing resource copy** [AD-106] | ★★ **13.7 KB/cycle in BOTH rooms** — a large constant, not the variable that moved | ★★★ **measured**, §3.C |
| **3** | ★★ **Room 1's extra bytecode** | ★★ **+28% instructions** | ★★★ **measured**, §3.B |
| **4** | ★ **`res_cache_flush` per cycle** | **unmeasured** | — |
| — | ★★★ **Not a candidate: the compositor** | **7.7%**, and it holds to +1.7% of its isolated figure [P6.7] | ★★★ **measured** |

★★★★ **The ranking's top entry is a structure, not a defect.** The oracle has the same shape
[`cycle.py interpret_cycle`], so "it does per-object work every cycle" is faithful. **What is
unknown is whether the 6809's per-object cost is proportionate**, and that needs the ablation §3.D
declines to build.

---

### 7 — Uncertainty flags

1. ★★★★★ **AC-9: the dispatch anticipated an integration cost and there is barely one.**
   Like-for-like, same room, integration is **+31%** (15.7 → 11.98 cycles/s). **The headline gap is
   a workload difference the framing did not consider** — attract mode against a live room. ★★★
   §7 trigger 5, and it makes the 72.5% correct but differently meaningful.
2. ★★★★ **§3.B's 76% is an estimate from two points.** It assumes bytecode cost scales with
   instruction count, which is not established [L-41]. **A build with the per-object work ablated
   would settle it and was out of scope.**
3. ★★★★ **`opcount` was not reported per arm because no arms were built** — AC-3 asks for it and I
   have not satisfied that. ★★ Nor was the pace-only `opcount == 0` check re-run [AD-105]; **no
   ablation was trusted, because none was made.**
4. ★★★ **The `vm` row's misclassification is currently harmless and disables a real check** (§3.E).
   Fixing it is a one-word manifest edit and was out of scope for a recon task.
5. ★★ **The gate rows were cited, not re-run.**
6. ★★ **All figures are P6.7's or the reference's.** No new hardware timing was taken, so **no new
   clock measurement was needed and none is published** — but that means these shares rest on
   P6.7's single run.
7. **Carried:** `CP_CEL` (p3b at 3 free bytes, trigger due); `pic`'s corpus; the patch series; the
   instruction budget; the surviving resource copy — **now with a measured standing cost, §3.C.**

---

### 8 — Follow-up candidates

1. ★★★★★ **Ablate the per-object work** — the one measurement that converts §6's rank 1 from a
   structure into a share. **A `-D` arm, measured, changing nothing** — T-P0-035's model.
2. ★★★★ **Reclassify the `vm` manifest row to `purpose=timing`** (§3.E) — one word, and it restores
   a check on the build that publishes 15.7.
3. ★★★ **Re-take the standalone VM figure in a POPULATED room**, so 15.7 and 2.22 become comparable
   at last. `vm_sweep.lua` already has the room jump.
4. ★★ **The standing 13.7 KB/cycle resource copy** [AD-106] — unchanged by this task and still
   unchased.

---

### 9 — Reactive deviations and route accounting

**Deviations (§22.5): `None.`** ★★ Recon as specified; nothing changed.

**Route accounting.** ★★★ I proposed no route. ★★★★ **What the dispatch asked for and I did NOT
deliver:** AC-3's ablation with `opcount` per arm. **I decomposed structurally and estimated the
split from two points instead**, because building an ablation arm is a code change and §2/§11 put
change out of scope. ★★ **That is a real gap in AC-3 and §7.2 states it rather than letting the
structural finding stand in for it.**

---

### 10 — Candidate(s) captured this task

One, in `seeds/AGI/live/`:

- `2026-09-08-a-bracket-is-named-for-its-largest-caller-not-its-contents`

★ **Not captured:** §3.A's workload-versus-build confusion is an instance of
`two-figures-for-one-quantity-differ-by-their-build-flags` (captured last task) generalised to
workloads; per §2C I have not edited that row and note the widening here.

### 11 — Commit

Report only; **no code changed this task.**
