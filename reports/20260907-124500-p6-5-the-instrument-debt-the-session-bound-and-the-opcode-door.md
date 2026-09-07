## Form B Report — P6.5 — The instrument debt, the session bound, and the opcode door
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-07 ~11:20 local (HEAD `fa16ff4`, wip). `git status` clean at t0.

---

### 6 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `fa16ff4`, `wip`, **clean** |
| POP + Karateka | §2T citation below |
| `hal_sync_check.py` | **OK in all three** — §5 |
| the gate suite, incl. p3b's new row | **all pass from fresh builds** — §5 |
| flag sets — enumerate and diff | produced and diffed; §5 |
| the clock — measure it | `1.789772 MHz`, guest-stamped [L-78]; §5 |
| every gate's `-seconds_to_run` vs measured use | ★★★★ **AC-6's table — all five measured** |
| every Orchestrator artifact's committed version | ★★★★★ **see below — two findings** |

#### §2T — sibling baseline, by citation

★ P6.4 §0 records POP `wip` `104b197` and karateka `wip` `29f8f0a`. **Both unchanged.** Tracked
modifications: POP **0**; karateka **1** — `harness/smoke/last-run.log`, the same harness run log
P6.4 §6 recorded, not source. **This task touches no file in §2M's SHARED list**, so no sibling
artifact can have moved; the check that matters is the sync check itself, `OK` in all three (§5).

#### ★★★★★ AC-10 — and it found two things, both §9 trigger 5

**1. Three sources named three different design-spec versions, and only one had ever existed.**

| source | names | in the tree? |
|---|---|---|
| `CLAUDE.md` v1.8, line 58 | `agi-coco3-design-v0.3.md` | ★★★ **never committed on any ref** |
| `docs/project/` | `v0.6` (`8028bb8`, P2.1a) | yes — and **six versions stale** |
| this dispatch's header | `v1.1` | no |

★★ `git log --all --name-only` shows **`v0.6` is the only design-spec filename ever present on any
ref**. CLAUDE.md points at a file the repository has never held.

**2. And then v1.1 and v1.2 appeared in the working tree, untracked, mid-task.** Both are now
committed to `docs/project/` (§3.F). **So the answer to §5's question is: of the two
Orchestrator-supplied artifact classes, CLAUDE.md was current at v1.8 and the design spec had
missed five releases.**

---

### 1 — Summary

**The instrument debt is paid and every new assertion has been shown to fail.** `res_aggregate.py`
gained an expected-total assertion — and the demonstration is the point: a volume re-run under a
3-second bound **fetched 58 of 132 and the old script printed `100.00%` and exited 0**, because
both sides of the ratio shrink together. `comp_sweep` clears its dumps; the **comp gate is now the
fifth row in `run_gates.sh`** and passes there at 124/124.

★★★★ **AC-6's table is the task's most useful number and it settles AC-7 on measurement.** Only
`pic` is anywhere near its bound — **308 of 900 emulated seconds, 34%**. Everything else is ≤9%.
**The early-exit handshake is DECLINED, and not on headroom alone: every sweep already calls
`machine:exit()` on completion**, so the proposed mechanism is already implemented and
`-seconds_to_run` is only reached by a sweep that never finishes.

★★★★★ **AC-9 caught me out and that is the finding worth reading.** The first nine-title parser run
printed **nine PASSes while feeding six titles**. That is `res_aggregate`'s own defect — 100% of a
smaller number — reproduced in the AC written to widen coverage, in the same task that fixed it
elsewhere.

★★★★ **And the opcode door has a shape.** `have.key`, `get.string`, `save`/`restore`/`restart.game`
are all **text-input infrastructure**, which is the next task. One of them hung the reference.

---

### 2 — Files modified

**New:** `harness/tools/comp_run.sh` (AC-4), `harness/tools/gate_budget_check.sh` (AC-6),
`harness/tools/fix_mojibake.py` (§3.G).
**Instruments:** `res_aggregate.py` (AC-2), `comp_sweep.lua` (AC-3), `run_gates.sh` (AC-4),
`said_gate.py` (AC-5), `vm_diff.py` (§3.D), `vm_input_script.py`, `vm_run.ps1`, `vm_stage.py`.
**The VM:** `vm_cmds.s`, `vm_core.s`, `vm_cycle.s`, `vm_probe.s`, `vm_tables.s`,
`tools/agivm/commands.py`, `tools/agivm/cycle.py` (AC-8, §3.C, §3.D).
**Landed, not authored:** `docs/project/agi-coco3-design-v1.1.md`, `v1.2.md`.

---

### 3 — Reasoning

#### 3.A ★★★★★ AC-2 — the count had no protection, and the demonstration is the argument

`res_aggregate.py` iterated the ten **pinned volumes**, which stops a glob dragging in scratch
dirs, and then reported whatever each sweep happened to contain. **A required set of VOLUMES and
no required set of FETCHES.**

**Shown, not argued.** One volume was re-run under `-seconds_to_run 3`:

```
Kingquest3-v2             132       58         58        0          0
resources byte-identical to tools/volread/: 1190 / 1190 requested (100.00%)
```

★★★★ **`100.00%` on a run that fetched 58 of 132.** The expected count now comes from
`res_stage.py`'s own `requests.txt` — one producer, two consumers — rather than the constant 1,264,
which would have been the cel gate's 6,782 fossil in a new place.

#### 3.B AC-6 and AC-7 — the table, and why the handshake is declined rather than deferred

| gate | the unit the bound applies to | budget | used | |
|---|---|---|---|---|
| **pic** | 45 pictures, ONE session | 900 | **308** | **34%** |
| cel | largest title (PoliceQuest1) | 900 | 80 | 9% |
| comp | largest corpus | 400 | 26 | 6% |
| p3b | 160 cycles, ONE session | 900 | 23 | 3% |
| res | largest volume (KQ3-v2) | 3000 | 4 | 0% |
| vm | per title | 100000 | — | not a bound in any practical sense |

★★★ **The unit differs by gate and that is the part a single number would have hidden:** `pic` and
`p3b` run a whole corpus in one session; `res`, `cel`, `comp` and `vm` launch MAME per item, so
their bound applies to the **largest single item**, not the total.

★★★★★ **AC-7: DECLINED.** The gate-speed note proposed a handshake in which the probe signals
completion and the Lua calls `machine:exit()`. **Every sweep already does exactly that** — measured,
2 to 8 call sites each — so `-seconds_to_run` is a backstop reached only by a sweep that never
completes, and `pic`'s 308 s is the *work*, not budget spent waiting. ★★ **The residual risk is not
the handshake, it is corpus growth**: at ~6.8 s/picture the bound covers about 131, and AD-113 has
already found a divergence outside the 45. That is a corpus decision and it is §8.

#### 3.C ★★★★ AC-8 — the three opcodes, read from the oracle rather than guessed

**`restart.game` does not restart anything.** `op_cmd.cpp:1913` stops sound, decides, and sets
`_restartGame` + `VM_FLAG_RESTART_GAME`. **The restart is the outer loop's** (`cycle.cpp:580-605`):
it breaks every interpreter loop, re-runs `agiInit()` and resets the timer. ★★★ The old error
message — *"it re-enters the whole game loop"* — **described the LOOP and attributed it to the
opcode.** The rest of that message was right, and is why this stops rather than restarts: *"would
silently restart the state diff mid-run"*. A leg that re-inits is comparing a fresh game against a
continuing one. **So: set the flag, signal, and halt** — the treatment `quit` already gets, which is
gated (KQ1 quits at 140 and the 6809 halts at the same cycle).

**`save.game` / `restore.game` are modelled as the CANCELLED dialog**, which is a real AGI path and
observably nothing: `cmdSaveGame` **ignores `saveGameDialog()`'s return value**, and the cancel path
returns having touched no VM state; `restore`'s `VM_FLAG_RESTORE_JUST_RAN` is set *inside* `doLoad`,
i.e. only on a restore that happened. ★★ **The successful branch is the storage layer's and is
declared, not stubbed into something that pretends.** ★ Recorded divergence: `VM_FLAG_AUTO_RESTART`
is not modelled — without a UI there is no dialog to decline.

★★★ **Result: KQ1 now runs 600 cycles where it stopped at 140.** `save`/`restore` no longer halt.

#### 3.D ★★★★★ Two gate defects KQ3 exposed, and the second is the gate judging itself

**1. `vm_probe.s` tested `vm_quit` but not `vm_restart` after a cycle.** A restart fires *during* a
cycle body, so the probe looped, paced and parked once more before the pre-cycle guard caught it.
**Measured: oracle 508, guest 509.**

**2. `vm_diff.py` passed it.** Its rule was `len(guest) >= len(oracle)` and it compares `min()`, so a
guest that ran **past** the reference satisfied it and the extra row was never compared. It printed:

```
divergent cycles : 0 of 508
★★ cycle counts differ (508 vs 509)
AC-2 PASS -- byte-identical on every compared cycle
```

★★★★ **The gate passed on an asymmetry, by accident of its own length rule.** The rule had a reason
and it was the wrong one: it was written so a guest halting EARLY failed loudly, and "longer" was
left permissive as the harmless direction. **It is not harmless** — it means the two legs disagree
about when the run ends, a state difference that happens to fall outside the compared window.

Both fixed; both shown two-sided (§5). ★★ Each direction is named separately, because "stopped
early" and "ran past" have opposite causes and one message would send the reading wrong.

#### 3.E ★★★★★ The hang, and the stub that predicted it

`vm_input_script.py` classifies each candidate by running it. One KQ3 line put the **reference** into
a loop that never terminated, and `max_cycles` never fired — **the runaway is INSIDE one cycle and
the bound is checked BETWEEN cycles.** 700+ CPU seconds, no output. ★★ Two of them ran concurrently
on the same output file before it was noticed, because an interrupted run had left an orphan.

★★★ **The stack said where, and reading the interpreter would not have.** A repeating
`faulthandler` dump pointed at `run_logic` via `cmdCall`; a per-cycle instruction budget that
**raises with the logic and ip** took the same case from unbounded to **3 seconds** and named it.

**Logic 102, 81 bytes — the help screen:**

```
63: FF  IF (FD 0D)      = if NOT have.key
    branch-if-false +3 -> 72
69: FE  GOTO -9  -> 63  <-- spin
72: 78  accept.input
```

★★★★★ **`vm_tests.s` has said since P4:** *"This VM is headless with no input source, so this is the
'no key waiting' path — **FAITHFUL for a run with no input, which is what the diff compares, and
WRONG the moment input exists.**"* Input exists now. **`said()` was the stub this task's predecessor
retired; `have.key` is the next one behind the same door**, and the comment named the condition.

#### 3.F The design specs, and why §2D's gate is not in play

v1.1 and v1.2 appeared untracked mid-task. §2D's superset gate protects against **silent loss on
overwrite**; these are **added alongside** v0.6, which is untouched, so nothing is lost. The delta is
surfaced rather than adjudicated:

- **v0.6 → v1.2: 9 substantive lines dropped** — the title line, the pixel-queue/scanline-fill
  advice, a room-change-latency note, a save-under bound, and *"§11.1 REOPENED — the v2-only ruling
  rested on a false premise"*.
- **v1.1 → v1.2: 3** — the title line and a sprite-cost figure (*"~53% of a second at two sprites"*)
  **which v1.2's own changelog withdraws**.

★★ **Retiring v0.6 is the Orchestrator's call, not mine.** Three design specs in one directory is
untidy and it is honest; deleting the stale one is a content decision (§2D).

#### 3.G ★★★★ A defect I committed in P6.4, found by checking rather than by it failing

PowerShell's `Get-Content -Raw` reads UTF-8 as ANSI and `Set-Content -Encoding utf8` writes a BOM. I
used that pair for bulk edits the Edit tool would have made safely, **double-encoding every `★` and
`§` in six files, four already pushed.** Comment-only, every script still ran — which is why it
survived three commits.

★★★ `fix_mojibake.py` repairs it **run by run**, because the files are mixed: a blanket inverse
would repair the double-encoded stars and destroy the proper ones added afterwards. ★★★★ **Verified
before trusted**: the transform reproduces three witness files' pre-damage blobs with zero
unexpected losses. **Two rounds of that check found a real defect in the tool** — .NET maps five
cp1252-undefined bytes to control codepoints where Python refuses them, and `0x90` is the third byte
of `═`, so the first version declined every banner and *reported the file repaired*.

★★ And the tool flagged **its own docstring**, which embedded the damaged form as an example.
Running the repair over the tree would have "fixed" the illustration and destroyed the one place the
defect is written down. The example is now spelt in codepoints. **A tool that cannot be run on its
own source is one somebody excludes from the sweep, and an excluded file is where the next instance
hides.**

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] — PASS.** `hal_sync_check` OK ×3; `reg_discipline` unchanged at 8 in
  `mmu_phase.s`. §2T citation in §6.
- **AC-2 [byte-comparable] — PASS, shown to fail.** 58-of-132 truncation → old behaviour `100.00%`
  exit 0; new assertion names the volume and exits 1. Expected count from `requests.txt`.
- **AC-3 [byte-comparable] — PASS.** `comp_sweep` clears the per-frame dumps it will write, from its
  own work list. ★ Stated rather than assumed: `compareFrame` reads RAM, not the files, so a stale
  dump cannot make a divergent frame report identical — **the dumps are diagnostics, and a stale
  diagnostic sends a reading to the wrong place**.
- **AC-4 [byte-comparable] — PASS.** `comp_run.sh` + a `comp` row in `run_gates.sh`: **124/124
  frames, both planes, six corpora.**
- **AC-5 [state-comparable] — PASS.** `said_gate.py` records the emit run's `--limit` beside its
  corpus and `--check` reads it back. ★ The corpus-defining parameter existed nowhere on disk and
  had to be recovered by bisection in P6.4.
- **AC-6 [state-comparable] — PASS.** The five-row table in §3.B, from MAME's own exit line. No gate
  modified, no host-side timing.
- **AC-7 [state-comparable] — DECIDED: DECLINED.** §3.B. Not deferred; declined on the measurement
  **and** on the mechanism already existing.
- **AC-8 [state-comparable] — DECIDED.** §3.C. Transcribed from the oracle with `file:line`.
- **AC-9 [state-comparable] — PASS, 9/9, and the coverage stated.** KQ1 600, KQ2 600, **KQ3 508**,
  SQ1 600, SQ2 600, PQ1 600, larry1 600, BC 600, MUMG 600 — all byte-identical, exclusion set empty.
  ★★★★ **6 of 9 fed with input.** SQ2's candidates all reach `get.string`; BlackCauldron and
  MixedUpMotherGoose call `said()` **zero times** in the gated window. **Not a failure and not
  hidden** — for two of them it is the strongest fact available.
- **AC-10 [state-comparable] — ANSWERED.** §6. Two findings, both §9 trigger 5.
- **AC-11 [byte-comparable] — PASS.** pic 45/45, res 1264/1264, cel 9193/9193, comp 124/124, p3b 160
  cycles. Every new assertion shown able to fail: §5.
- **AC-12 [state-comparable] — five things.** §7.
- **AC-13 [suite] — two candidates.** §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — AC-2, the assertion failing on a truncated run (verbatim):**

```
volume               expected requests  identical   mismat  guestfail
Kingquest3-v2             132       58         58        0          0
------------------------------------------------------------------------
TOTAL                    1264     1190       1190        0          0

resources byte-identical to tools/volread/: 1190 / 1190 requested (100.00%)
fetches requested vs STAGED-FOR: 1190 / 1264   ★★★ SHORT -- this run did not fetch what it was staged for
    ★★★ Kingquest3-v2        fetched 58 of 132 -- the sweep was cut short or the stage moved
exit=1
```

★★ **The `100.00%` line is the old script's entire output.** The two lines under it are the fix.
Restored and re-run: `1264 / 1264`, `exit=0`.

**25.1 — AC-6, the headroom table (verbatim):**

```
gate     unit the bound applies to            budget     used     pct
---------------------------------------------------------------------
pic      45 pictures, ONE session                900      308     34%
cel      largest title (PoliceQuest1)            900       80      9%
comp     largest corpus (KQ1ego1, 24)            400       26      6%
res      largest volume (KQ3-v2, 132)           3000        4      0%
p3b      160 cycles, ONE session                 900       23      3%

★ vm is bounded at 100000 emulated seconds per title -- two orders above any observed
  use, so it is not a bound in any practical sense and is reported as such rather than
  measured against.
```

**25.1 — §3.D, the length rule, both directions (verbatim):**

```
-- the PRE-FIX artifacts (guest 509, oracle 508): the rule must now FAIL --
divergent cycles : 0 of 508
★★★ THE GUEST RAN PAST THE ORACLE: 509 cycles against 508 -- the reference
    ended the run and the guest did not. The extra cycle(s) are OUTSIDE the
    compared window, so byte-identity below says nothing about them.
AC-2 ★★★ FAIL          exit=1     (it was exit 0 before)

-- the FIXED probe --
oracle       : 508 cycles  sha256 915b621cddf28bce
guest        : 508 cycles  sha256 915b621cddf28bce
divergent cycles : 0 of 508
AC-2 PASS -- byte-identical on every compared cycle
```

**25.1 — AC-9, all nine, with coverage (verbatim):**

```
=== AC-2 SUMMARY ===
Kingquest1           PASS  input fed
Kingquest2           PASS  input fed
Kingquest3           PASS  input fed
SpaceQuest-1         PASS  input fed
SpaceQuest-2         PASS  ★ NO INPUT -- not covered by this arm
PoliceQuest1         PASS  input fed
larry1               PASS  input fed
BlackCauldron        PASS  ★ NO INPUT -- not covered by this arm
MixedUpMotherGoose   PASS  ★ NO INPUT -- not covered by this arm

★ parser arm covered 6 of 9 titles with input; 3 ran without and are the plain gate.
```

★ Per-title sha256 pairs were identical on all nine; KQ3 is 508/508 and the rest 600/600.

**25.1 — §3.E, the hang and its cause (verbatim):**

```
lines classified : 11 continue, 4 end the run, 2 raise (see each reason)
   ★★★ said(253)         cycle 151 exceeded 100000 instructions inside one cycle
   ★★★ said(253,149)     cycle 151 exceeded 100000 instructions inside one cycle
elapsed: 3s   (was >600s and unbounded)

RAISED: cycle 151 exceeded 100000 instructions inside one cycle (logic 102, ip 68)
        -- a logic is not terminating
```

**25.1 — the gate suite, fresh builds, five rows (verbatim):**

```
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
fetches requested vs STAGED-FOR: 1264 / 1264
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ p3b headless: 160 cycles, no stall
★ gates run: pic res cel comp p3b  -- all green
```

**25.1 — `hal_sync_check.py`, all three (verbatim):**

```
coco_agi        [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port       [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3  [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)
```

**25.1 — `reg_discipline.py` (verbatim):**

```
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s                       8  $FFA5 $FFA6
```

**25.1 — the clock, guest-stamped [L-78]:** `clock MEASURED 1.789772 MHz (160009 cycles calibrated)`

**25.1 — the encoding audit, whole tree (verbatim):** `exit=0 (0 = all clean)` over every tracked
`.py`, `.lua`, `.sh`, `.ps1` and `.s`, **including `fix_mojibake.py` itself** (§3.G).

**25.2 — bundled-artifact grep:** N/A — no DECB artifact; every probe is poked.

**25.3 — operator-runtime-smoke:** **N/A.** Nothing in this task reaches the screen: it is instrument
work, an opcode decision and a state diff. ★ The eye gate's own invocation
(`p3b_show.ps1`) is unchanged and still passes headless (`p3b` row above).

---

### 6 — Reactive deviations and route accounting

**Deviations (§22.5):**

1. ★★★★ **I repaired an encoding defect I had committed in P6.4** (§3.G), in its own commit
   `280a1f1` before this task's work. Not in the dispatch; it was damage I caused.
2. ★★★ **I added a per-cycle instruction budget to the reference** (§3.E). Not asked for; without it
   AC-9 could not run at all.
3. ★★★ **I tightened `vm_diff.py`'s length rule** (§3.D). Not asked for; the gate was passing on an
   asymmetry.
4. ★★ **I made the parser arm report its coverage** (§3.A of AC-9). Not asked for; nine PASSes for a
   six-title arm is the defect AC-2 exists to fix.
5. ★★ **I landed v1.1 and v1.2** rather than only reporting the gap (§3.F).
6. ★ **`vm_input_script.py`'s classification heading** said *"reach an unimplemented opcode"* while
   the watchdog was firing — naming the usual cause instead of the actual one. That is P6.3 §3.F.3's
   mislabelled reference one task later, by the same hand. Fixed to print each line's own reason.

**Route accounting.** I proposed no route beyond the dispatch. ★★ **What I described and did NOT
build:** while diagnosing the 508/509 I said I would wait for KQ3's result before fixing, to get the
asymmetry as a measurement rather than a reading. **I did that**, and the measurement is §5's.
★ **What I chose not to do:** retire `docs/project/agi-coco3-design-v0.6.md`. It is a content
decision and §2D makes it the Orchestrator's.

---

### 7 — Uncertainty flags (AC-12)

1. ★★★★★ **The opcode door has a consistent shape and it is the next task's scope.** `have.key`
   (spins), `get.string` (unimplemented), `save`/`restore`/`restart.game` (decided here) are all
   **text-input infrastructure**. Three of the nine titles cannot be covered by the parser arm until
   it exists.
2. ★★★★ **Two titles call `said()` ZERO times in 600 cycles** — BlackCauldron and
   MixedUpMotherGoose. No input script can cover them; a longer window or a room jump might.
   **Unmeasured.**
3. ★★★ **`pic` is at 34% of its session bound and the corpus is under pressure to widen** [AD-113].
   At ~6.8 s/picture the bound covers ~131. Not urgent, and it is the one row that will move first.
4. ★★★ **The per-cycle instruction budget is set at 100,000 against a measured peak near 3,500.** It
   cannot fire on honest work today; **a title with a genuinely long cycle would need it raised**,
   and nothing tells you that except it firing.
5. ★★ **`CLAUDE.md` line 58 still names `agi-coco3-design-v0.3.md`.** It is a doc body and §2D makes
   it the Orchestrator's to fix; recorded here so it is not lost.
6. ★★ **Three design specs now sit in `docs/project/`.** See §3.F.
7. **Carried, unchanged:** `CP_CEL`'s overrun (trigger: before p3b's next code change); the patch
   series (trigger: before the next oracle patch).

---

### 8 — Follow-up candidates

1. ★★★★★ **Text rendering, the input line, `have.key` and `get.string`** — one task, and §7.1 is its
   scope. Jay's control scheme is ruled [AD-134].
2. ★★★ **Widen the parser arm's window or jump a room**, so BlackCauldron and MixedUpMotherGoose can
   be covered at all (§7.2).
3. ★★★ **Decide `pic`'s corpus**, which is what actually moves its 34% (§7.3).
4. ★★ **Retire `docs/project/agi-coco3-design-v0.6.md`** and correct CLAUDE.md line 58 (§7.5, §7.6).
5. ★★ **The successful `save`/`restore` branch** belongs with the storage layer (§3.C).

---

### 9 — User interaction during task

- Jay: **"check"** — which found the encoding damage of §3.G. It would not have surfaced otherwise:
  every affected script ran correctly.
- Jay: **"check for hang"** — §3.E. Two competing processes were writing one output file.
- ★ Standing instruction, carried: **do not commit PNGs unless asked.** None produced.

---

### 10 — Candidate(s) captured this task

Two, in `seeds/AGI/live/`, pushed to the pool at `21f7415`:

- `2026-09-07-a-bound-checked-between-units-cannot-see-a-runaway-inside-one`
- `2026-09-07-a-stub-declared-faithful-for-todays-inputs-is-a-dated-cheque`

★ **Not captured, as instances of existing rows:** the `100.00%`-of-a-smaller-number defect belongs
to `a-session-budget-is-a-clock-charged-to-the-whole-corpus` and
`the-scope-of-a-gate-is-part-of-its-definition`; the mislabelled classification heading belongs to
`a-label-naming-the-default-reference-lies-when-the-reference-is-switchable`. ★★ **All three are
recurrences by the same author within two tasks of writing the row**, which is the fact the
reconciler may want more than a fourth row.

### 11 — Commit

`280a1f1` — *repair a cp1252/UTF-8 double-encoding I committed in P6.4*
`a51764a` — *P6.5 the instrument debt, the session bound, and the opcode door*
(both pushed to `origin/wip` before this report).
