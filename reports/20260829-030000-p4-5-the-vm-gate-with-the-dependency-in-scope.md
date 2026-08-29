## Form B Report — P4.5, the VM gate with the dependency in scope — AC-2 green on nine titles
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-28 (HEAD `fb2f9fc`, wip). git status: 12 modified, 12 untracked at report time; all
listed in §2 and staged by explicit path (§2E).

### 1 — Summary

The VM gate is green. **256 variables + 32 flag bytes, byte-identical against `tools/agivm` on
every one of 500 cycles, across NINE titles, with an EMPTY exclusion set** — three times the
title count AC-2 asks for. Getting there took twelve defects, of which the state diff pointed
directly at none: it is an excellent detector and a poor localiser, and the gap between the two
is where the task went. Motion and the object update were in scope and are implemented,
including `motion_wander` and `motion_follow_ego`, which a prior measurement had reported
unreachable. Two mechanical instruments were built (`x_liveness.py`, `vm_coverage.py`) and one
previously-recorded conclusion was **withdrawn as wrong**.

★★ Two of the twelve were mine, introduced during this task after diagnosing their own class.
One was a wrong *cause* recorded in three files while the *observation* was correct.

### 2 — Files modified

Modified:
- `src/harness/vm_core.s` — opcode saved across the handler; test-opcode coverage counter; trace
  buffer windowed, logic-filtered and relocated; three short branches lengthened
- `src/harness/vm_cmds.s` — `position`/`position.v`/`reposition.to`/`reposition.to.v` reordered
  (operands first, object pointer last); `distance` implemented, then rewritten 16-bit
- `src/harness/vm_run.s` — `motion_wander` and `motion_follow_ego` implemented; `vm_check_step`
  16-bit; `vm_mul32` rewritten; `vm_div16by8` corrected to 16 iterations; `vm_rnd` helper;
  AC-3 fault injector behind `-DVM_FAULT`
- `src/harness/vm_objects.s` — position pass rewritten 16-bit signed
- `src/harness/vm_cycle.s` — two ego-direction sites fixed (B clobbered by `vm_obj`);
  `VM_TESTSEEN` cleared in `vm_start`
- `src/harness/vm_state.s` — state block relocated to `$4000`; instrument tables relocated;
  `fDidntMove_H`; the memory map, with a **correction** to a previously-recorded cause
- `src/harness/vm_probe.s` — `$FFDF` (all-RAM); arena self-test; pace-then-park; free-run for
  AC-7; `VP_FREE` initialised; **five** layout assertions where there was one
- `src/harness/vm_tables.s` — opcode `$45` bound to `vmop_distance`
- `src/harness/vm_tests.s` — carried in from the prior task, unchanged this task
- `harness/tools/vm_stage.py` — oracle uses `vm.run()`, not a loop over `interpret_cycle()`
- `harness/tools/vm_sweep.lua` — symbols from the map; object watch; AC-7 timing; both coverage
  tables; halt dump enriched
- `harness/tools/vm_run.ps1` — symbols via `vm_symbols.py`; `-DVM_TRACE`/`-DVM_FAULT`/`-DVM_PACEONLY`

New:
- `harness/tools/x_liveness.py` + `harness/tests/x_liveness_fixture.s` — register-liveness checker
- `harness/tools/vm_coverage.py`, `vm_condcov.py`, `vm_memory.py`, `vm_load.ps1`
- `harness/tools/vm_reftrace.py`, `vm_tracediff.py`, `mem_probe.lua`, `fix_signed_index.py`
- `harness/mame-cfg/{coco3,default}.cfg`

### 3 — Reasoning

**The twelve defects, and what each was found by.** None was found by reading code.

| # | defect | found by |
|---|---|---|
| 1 | `vm_op` is a global, read for the arg count AFTER the handler; `call`/`call.v` leave the callee's last opcode | per-opcode coverage diff (`0x16 call 1/0`) |
| 2 | `pshs a` placed after the `clra` that indexes `VMOP_TAB` — **mine, one line into fixing #1** | instruction trace, first divergence step 10 |
| 3 | arena sized 12 KB from a working set measured on a run that never nested | `RES_E_FULL` at bind time |
| 4 | `HAL_sys_init` never writes `$FFDF`, so `$8000-$FEFF` was ROM | guest-side arena self-test: first bad address `$8000` |
| 5 | oracle looped `interpret_cycle()` directly, bypassing `run()` | asking the reference directly |
| 6 | four handlers held the object pointer in `X` across an operand fetch | `x_liveness.py` |
| 7 | `vm_mul32` discarded the high byte of every partial product | seed on-trajectory, product wrong |
| 8 | `vm_div16by8` ran 8 iterations for a 16-bit dividend | `random` returning exactly its low bound |
| 9 | position pass held x/y in bytes | vars 4/5 on 16 of 500 cycles |
| 10 | `kMotionWander` unimplemented | its own loud halt, on BlackCauldron |
| 11 | `check_step`/`follow_ego`/`distance` byte deltas — **#12 written by me after diagnosing #9** | object watch: dir 6 vs 2 |
| 12 | `B` clobbered by `vm_obj` at two ego-direction sites | object watch: `dir 0` beside `var6 3` |

★★★ **§2H, three checks, on the reference and on my own prior measurements.**

1. *Is there a SECOND mechanism serving a different object class?* Yes, twice. The RNG has
   **five** consumers, not one: `cmdRandom` plus four sites in `motion.py` (wander direction,
   wander count, follow direction, follow count). They share one generator, so a VM that
   implements only the opcode desynchronises the stream for every later draw. And
   `check_all_motions` is not the only out-of-scope step — `update_screen_obj_table` runs at the
   end of every cycle and writes the border variables. Both measured, §4 AC-4.
2. *Name the routine that CALLS it.* `motionWander`'s `while wander_count < 6` is a **retry
   loop, not a clamp** — it re-rolls until the value is ≥ 6, consuming the generator a variable
   number of times. `max(6, roll)` gives the same count and a different stream. The caller
   (`checkMotion`, gated on `stepTimeCount == 1` exactly) is what makes it rare enough to survive
   500 cycles on eight titles and fire on the ninth.
3. *Grep the reports for the same subsystem before citing a characterisation.* Done, and it
   **overturned two**. `vm_motion_which.py` had measured that the gated set never reaches wander
   or follow.ego; that measurement was true of the three-title set and false of BlackCauldron,
   which reaches `kMotionWander` at cycle 225. And P1.3's arena figure was measured while defect
   #1 truncated logic 0 three instructions before its own `call`, so the "depth 2-3" working set
   came from a run that never nested.

★★ **Authority tier.** Every behavioural conclusion here rests on **ScummVM via `tools/agivm`**
(tier 3), not on the running original (tier 2) and not on the Specs (tier 4). Per §2.1 the
following are stated as facts about ScummVM and **believed to be NORMALISATIONS, not original
Sierra behaviour**: the `Common::RandomSource` generator (`agivm/cycle.py` says so itself — the
shipped interpreter is free to differ and that will be a stated divergence); `motion_activated`
and `cycler_activated`, which the oracle's own comments call workarounds. The following are
**believed ORIGINAL** because they are transcriptions of observable interpreter structure with a
per-version distinction preserved: the `x <= 0` vs `x < 0` split at version `0x3086`, and
AGI 2.272 not calling `moveObj` from `move.obj`. ★ I have **not** run the original games to
confirm any of it; where §2.2 applies these are `[no-ref]`-class assertions against ScummVM,
discharged only to the extent that nine titles agree byte-for-byte with it.

★★★ **A recorded cause is withdrawn.** `mem_probe.lua` reported `$8900/$9300/$9400/$A900/$C900/
$E900` unreadable and everything below `$8000` fine. I concluded "MAME's program space does not
follow the GIME MMU above `$8000`" and wrote it into three files, then relocated two instrument
tables on its authority. **The cause was ROM**: `HAL_sys_init` does not enable all-RAM mode and
`sys.s:118-128` says so in as many words. Nobody's writes stuck up there, host or guest. The
observation was right and the mechanism was not; a host-side readback cannot distinguish "the
observer cannot see it" from "the thing is not RAM", and the five-line guest-side test that can
returns `$8000` exactly. Corrected in `mem_probe.lua`, `vm_state.s` and `vm_probe.s`.

★ **§2S — the ref and scope of every sibling claim.** POP `wip` `430a91c2`, Karateka `wip`
`78c8c276`, both read from the local working trees on 2026-08-29, not from a remote. Both are
**dirty on the SHARED file `src/hal/coco3-dsk/sys.s`** — the `HAL_SYS_FAST_CLOCK` block from
T-P0-024, present in all three working trees and **committed in none of the siblings**. All three
copies are content-identical (CRLF only; `normalise()` drops EOL, so not drift). **This task
touched no shared file**, so no sibling artifact can have moved and §2T's after-build does not
apply; see §7 for the risk this leaves open.

★ **§2F.** No palette constant, no compiled span layout, no second resource index, no computed
priority band. The VM reads the game's own DIR tables and nothing else.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: suite]** Standing checks run. — `x_liveness.py` 0 findings on the tree and 2 on
  its fixture (so a zero is meaningful); `reg_discipline.py` 0 accesses in `src/engine/`
  (the tree has none yet; all VM work is in `src/harness/`, which §2N excludes). §2T baseline is
  **not cited and not rebuilt**: no shared file was touched, so no sibling artifact is at risk.
  Sibling refs and dirty state recorded in §3. Toolchain: lwasm 4.24, MAME 0.281, Python 3.13.7.

- **AC-2 [class: state-comparable]** ★★★ **THE GATE — PASS.** 500 cycles × 9 titles × 288 bytes,
  diffed per cycle against `tools/agivm`, **exclusion set EMPTY**, 0 divergent cycles on every
  title. Verbatim in §5. Nine titles = the full v2 corpus the census covers; the three v3-shaped
  titles present locally (GoldRush, KQ4, ManhunterNewYork) report "staging did not fit" and are
  **not** claimed — see §7.

- **AC-3 [class: state-comparable]** ★★ **The gate can fail.** `-DVM_FAULT` changes one branch in
  `vm_check_step` from `ble` to `blt` — one boundary, one case (`delta == -step`). No halt, no
  crash, nothing visually different. KQ2 fails first at cycle 260, KQ3 at 425, SQ2 at 161. ★ That
  a one-boundary error takes 161–425 cycles to surface is §2I's argument as a measurement: this
  gate measures behaviour, and a visual gate would not have seen it at all.

- **AC-4 [class: state-comparable]** Motion and the object update re-measured **against the
  reference**, 500 cycles × 9 titles, suppressing each and both. Suppressing both diverges on
  **6 of 9 titles**, up to 494 of 500 cycles (KQ3 first at cycle 6). So both steps are observable
  to the diff and neither could be excluded. ★ The **port-side** answer is AC-2: the port
  implements both and passes all nine, so this is confirmed rather than assumed. ★★ KQ2 and KQ3
  specifically: both clean.

- **AC-5 [class: suite]** Coverage measured **against the census's 181/98, not the old 61**, and
  in **both opcode spaces** — commands and tests are separate spaces and a single pool would be
  §2H's "319" error. **86 commands + 10 tests dispatched.** Of the census's UNIVERSAL set
  (present in all nine titles): **tests 9 of 9**, **commands 72 of 89**. Seven opcodes remain
  bound to `vm_op_unimpl` — `get.string`, `word.to.string`, `parse`, `get.num`, `save.game`,
  `restore.game`, `restart.game` — every one in the input/save class a headless gate cannot
  reach. ★ **0 opcodes were dispatched while bound to `vm_op_unimpl`**, i.e. the halt fires
  instead of a silent no-op, which is what AC-5 is for.

- **AC-6 [class: state-comparable]** Condition-block coverage, 500 cycles × 9 titles:
  **299,593 blocks** — or_mode 53,123; or short-circuit 5,402; not_mode 38,747; and short-circuit
  272,769; `said` 51,550; resolving true 26,824 / false 272,769. **No structural path of
  `test_if_code` is unexercised.** Paired with AC-2's byte-identical result, each path both ran
  and agreed. ★ Per-title holes exist (BlackCauldron reaches no `said`, MixedUpMotherGoose no
  or-mode); the totals close them.

- **AC-7 [class: suite]** Cycle cost in **fast mode, 1.7898 MHz** (`-DHAL_SYS_FAST_CLOCK`; the
  probe's own `$FFD9` write, §5 of `sys.s`), measured in **emulated** time over a 2,001-cycle
  free-run with the handshake removed — through the gate the guest spins a whole frame per cycle
  and wall time would measure MAME.

  | title | total CPU cyc/VM cyc | pacing only | interpreter | ms/cycle | VM cycles/s |
  |---|---|---|---|---|---|
  | Kingquest1 | 284,365 | 14,091 | 270,274 | 158.9 | 6.3 |
  | Kingquest3 | 312,084 | 7,553 | 304,531 | 174.4 | 5.7 |
  | SpaceQuest-1 | 245,288 | 14,165 | 231,123 | 137.1 | 7.3 |
  | PoliceQuest1 | 231,511 | 7,598 | 223,913 | 129.4 | 7.7 |

  **VM/harness split: pacing is 3–6% of the total; the interpreter is 94–97%.** ★★ A
  two-parameter least-squares fit over the four titles gives
  `interpreter ≈ 15.9 × (LOGIC bytes copied) + 3,614 × (commands dispatched)`, residuals −4.4%,
  −4.2%, **+11.9%**, −0.6%. Under it, resource copying is **66–80%** of the interpreter's cost.
  ★ **This fit is my own arithmetic over four points and is a LEAD, not a finding** (§8): the
  +11.9% residual says the model is incomplete, and the first version of it — from two points —
  was exactly determined, unfalsifiable, and gave a *negative* per-byte coefficient. ★★★ The
  measured figures above are findings; the decomposition is not.

  ★★ **The port is currently too slow for its own pacing.** With `VAR_TIME_DELAY = 2` the games
  ask for a cycle every 100 ms; the port takes 129–174 ms. It is 1.3–1.7× short. See §8.

- **AC-8 [class: suite]** Determinism. Five titles run **concurrently** in five MAME instances
  against a pre-built binary (`vm_load.ps1` deliberately does **not** rebuild — that is the shape
  of T-P0-024's withdrawn `probe.dmk` measurement) produce guest output **byte-identical** to the
  sequential runs: BlackCauldron `7D5619922BA969E5`, Kingquest1 `3357906363F4A4A0`, Kingquest3
  `5D6CDE0F08B63F65`, SpaceQuest-2 `DA1C12753B92275B`, PoliceQuest1 `63025FA700DBDD23`.

- **AC-9 [class: suite]** Memory. Image **9,059 bytes** at `$0700`. Per module, from the listing:
  VM proper 7,450 (tables 1,579 / cmds 1,787 / run 1,668 / cycle 711 / objects 697 / core 557 /
  tests 263 / state 188), resource layer 695, HAL 731, probe 158. Regions: RES_DIRS 4,096; VM
  state 576; VM_OBJ 8,160; **arena 21,760 against a measured peak of 12,816 — 70% headroom**;
  coverage tables 512 and trace buffer 1,536, both **harness-only**. ★ All of it inside the first
  64 KB; §2K's 512 KB target is not stressed by the VM.

- **AC-10 [class: suite]** Five candidates captured — §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
=== AC-2 SUMMARY ===
BlackCauldron PASS
larry1       PASS
Kingquest1   PASS
Kingquest2   PASS
Kingquest3   PASS
SpaceQuest-1 PASS
SpaceQuest-2 PASS
PoliceQuest1 PASS
MixedUpMotherGoose PASS
```

per title, e.g. Kingquest2:
```
title        : Kingquest2
oracle       : 500 cycles  sha256 d732446819486a32
guest        : 500 cycles  sha256 d732446819486a32
compared     : 500 cycles x 288 bytes, exclusion set EMPTY

divergent cycles : 0 of 500

AC-2 PASS -- byte-identical on every compared cycle
```

guest-side arena self-test, every title:
```
  arena self-test: clean -- every byte held its pattern
```

`x_liveness.py` on the tree, then on its fixture (a zero that can still fail):
```
0 site(s) hold a register across a clobbering call
2 site(s) hold a register across a clobbering call
```

`reg_discipline.py` (§2N):
```
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
```

`hal_sync_check.py`: **N/A — no shared HAL file was touched this task** (§2M.6: `coco_agi` has
not joined `SIBLINGS`; entry is at P3).

25.2 bundled-artifact grep: **N/A — this task ships no bundled artifact.** The deliverable is a
harness probe (`build/vm_probe.bin`, gitignored) plus source and tools.

25.3 operator-runtime-smoke: **N/A for this task, and stated rather than skipped.** The VM probe
renders nothing — it deliberately does not call `HAL_gfx_set_mode` — so there is no screen to
gate. Per §2O this AC's class is state-comparable, not eye-gated. ★ The first 25.3 gate belongs
to picture rendering, not here.

### 6 — Reactive deviations and route accounting

**Deviations (§22.5).**
1. **Nine titles instead of three.** AC-2 asks for ≥3; the census covers 9 and the extra six
   found four defects the three-title set never reached (wander, `distance`, the `B` clobber, the
   `check_step` width). Scope increase, reported.
2. **`motion_wander` and `motion_follow_ego` implemented.** They were `vm_op_unimpl` halts on the
   strength of a measurement that turned out to be scope-limited. Motion was in this dispatch's
   scope; implementing them is the fix the halt was designed to trigger.
3. **`distance` (`$45`) implemented.** Reached by BlackCauldron; it writes a variable, so a
   state diff cannot pass without it.
4. **The memory map was relaid twice** (state block to `$4000`; instrument tables above VM_OBJ).
   Neither was planned; both were forced by measurements.
5. **A previously-recorded conclusion was withdrawn** rather than worked around (§3).

**ROUTE ACCOUNTING.** I proposed no route this task beyond the ACs. What I *said* mid-task and
must reconcile: after the first nine-title sweep I reported "six titles pass, three fail" and
listed the three as findings rather than work. **I then fixed all three**, so the final state
exceeds that description. ★ I also said, at the six-title point, that I would "report the three
additional titles as measured findings and move on"; I did not move on, and the extra work is
what produced defects #10–#12. The divergence is in the direction of more work, and it is stated
here because a plan that differs from its commit is invisible in a diff.

### 7 — Uncertainty flags

1. ★★★ **Both siblings are dirty on a SHARED HAL file.** `src/hal/coco3-dsk/sys.s` carries the
   uncommitted `HAL_SYS_FAST_CLOCK` block in POP and Karateka. All three trees agree today. **If
   one repo commits it and another does not, `hal_sync_check.py` fails both siblings' builds.**
   AGI depends on that block. This is not mine to commit (§2G: back-ports are separate explicit
   tasks in the receiving repo) and it is a live hazard.
2. ★★ **Three v3-shaped titles are untested.** GoldRush, Kingquest4 and ManhunterNewYork report
   "staging did not fit" — a harness staging-capacity limit, not a VM result. **No claim is made
   about AGI v3.**
3. ★★ **AC-7's cost decomposition is a lead, not a finding** (§4). The measured totals and the
   pacing split are solid; the per-byte/per-command attribution has an 11.9% outlier.
4. ★ **`follow.ego` is implemented and NOT exercised** by the gate — it is in the census's
   universal set but not dispatched in 500 cycles. Its correctness rests on transcription, not on
   evidence. Same for 16 other universal commands (AC-5).
5. ★ **The RNG is ScummVM's, not Sierra's**, and is reproduced bit-for-bit only so the diff means
   something. This is a stated divergence for the shipped interpreter, not a claim about AGI.
6. ★ **Everything here is tier-3 evidence.** No original game was run on period hardware or in an
   accurate emulator during this task.
7. The arena's 21,760 bytes are sized against a peak measured on **these nine titles at 500
   cycles**. A deeper call chain elsewhere would raise it; `RES_E_FULL` reports rather than
   corrupts, which is why that is a bounded risk.

### 8 — Follow-up candidates

1. ★★★ **A resident-logic cache.** `res_open` copies the whole LOGIC resource on every `call` —
   13,687 bytes per cycle on KQ1, 1,501 `run_logic` calls in 500 cycles. The port runs at
   129–174 ms/cycle against a 100 ms budget. This is the single largest lever and AC-7 localises
   it (with the caveat in §7.3).
2. **Raise the staging ceiling** to admit the v3-shaped titles, then census AGI v3's opcodes.
3. **Implement the seven declared holes** — `get.string`, `word.to.string`, `parse`, `get.num`,
   `save.game`, `restore.game`, `restart.game`. All need input or persistence, so they need a
   harness that can supply them, not just handlers.
4. ★ **Exercise the 17 universal commands the gate never reaches**, `follow.ego` first — a longer
   run or a driven-input harness.
5. **§2N.1's owner-row ratchet** now has owners to record: `$FFA6` (storage, `res_map_block`) and
   `$FFDF` (this probe). Both are declared in-source; neither is in a baseline file yet.
6. ★ Extend `x_liveness.py` to A and to `U`/`Y`, and consider whether the same shape applies to
   `vm_ip`/`vm_op`-style globals across nested calls — three of this task's defects were that.

### 9 — User interaction during task

None. The task ran from the dispatch through to this report without operator input. ★ One
environment instruction received mid-session directed that file edits be made with shell
heredocs; **CLAUDE.md §2J v1.5 forbids `<<`/`<<-`/`<<<` in any bash invocation for any purpose**,
and §8 makes project invariants override task-level instruction, so it was not followed. Recorded
here rather than silently.

### 10 — Candidate(s) captured this task

Pushed to `methodology-candidate-pool` `ac21bb8`, `seeds/AGI/live/`:
- `2026-08-29-an-instrument-that-models-one-register-cannot-see-the-same-defect-in-another`
- `2026-08-29-a-value-fits-the-type-a-difference-of-two-values-does-not`
- `2026-08-29-the-baseline-must-be-the-reference-running-not-a-loop-around-its-interior`
- `2026-08-29-an-assertion-that-names-one-neighbour-reports-conformance-for-the-others`
- `2026-08-29-a-mechanism-that-explains-the-observation-is-not-thereby-the-mechanism`

### 11 — Commit

See below — pushed to origin/wip before this report was filed.
