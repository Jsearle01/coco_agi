## Form B Report — T-P0-085c / P6.29c — `print` blocks in place; the corpus cannot reach it
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-10 20:26 (HEAD b1898f2, wip). git status clean at start; two untracked files are NOT
mine and stay unstaged — `agi-coco3-design-v1_3.md` (the Orchestrator's, §2D) and
`coco_agi.code-workspace` (Jay's editor file).

### 1 — Summary
`print` now blocks inside the opcode, where the oracle blocks, dismissed by ENTER, ESC or var 21's
auto-close timer. The implementation is complete and its shape is read from the pin rather than
chosen. **Two findings changed the work as specified.** First, the oracle measures the auto-close
deadline in the *in-game timer's passed cycles* — the very counter §4A's census had told me to
protect — so the loop calls `vm_step_clock` whole and resets `vm_passed` on both sides, which is
the opposite of what I built before reading `text.cpp`. Second, and this is the blocker: **no title
in the pinned set executes `print` at all**, measured three ways, so AC-4 through AC-8 and AC-11
cannot be exercised and are reported UNMET rather than assumed. Everything not blocked is done:
both byte gates fresh, the full suite green, `p3b` byte-identical, the flag set landed and
re-baselined. Amendment 1 is answered and **confirms Jay's recollection at our exact platform**.

### 2 — Files modified
- `src/harness/vm_text_ops.s` — blocking `print`; `tx_wait_dismiss` and its `-DTEXT_FAULT_NOTICK`
  fault arm; the Amendment 1 finding recorded at the seam it constrains.
- `harness/tools/p3b_show.ps1` — `-DHAL_KEYBOARD` for every wired text arm; `-NoTick` switch;
  wired-only symbol exports.
- `harness/tools/p3b_run.lua` — var-21 arming (`P3B_VAR21`), the game-clock per-cycle delta, and
  the box's three observables on the completion path.
- `harness/tools/vm_input_script.py` — `--wants-print`, which classifies candidate lines by whether
  their run actually executes `$65`/`$66`.
- `harness/tools/print_first_cycle.py` — NEW. At which cycle does a title first reach `print`?
- `harness/tools/gates.manifest` — `p3b_text` re-baselined with a retirement line; `p3b_notick`
  row added; what this gate *cannot* gate recorded in the row.

### 3 — Reasoning

**3.1 The deadline is on the game clock, and §4A's census had it backwards.**
I built the wait loop first with the deadline on `hal_frame_hi/lo`, the free-running VBL counter,
specifically to avoid touching `vm_passed` — §4A's enumeration had flagged that `vm_step_clock`
bundles the pacing counter with the clock, so advancing it would make the next `vm_pace` short.
Reading the oracle inverted that:

```
text.cpp:395   _vm->inGameTimerResetPassedCycles();
text.cpp:397   do { _vm->processAGIEvents(); _vm->inGameTimerUpdate();
text.cpp:401        if (windowTimer > 0 && _vm->inGameTimerGetPassedCycles() >= windowTimer) ...
text.cpp:409   _vm->inGameTimerResetPassedCycles();
cycle.cpp:558  if (_passedPlayTimeCycles >= timeDelay) { ... inGameTimerResetPassedCycles(); }
```

`cycle.cpp:558` is the decisive line: **the pacing gate and the message box's deadline are the same
variable.** A short next pace is not a side effect to avoid, it is `text.cpp:409`'s behaviour. So
`vm_step_clock` is called whole and `vm_passed` is cleared on entry and exit. Tier: ScummVM
(secondary), and this is believed **original** rather than a normalisation — a single-threaded
interpreter has one clock and the box has to advance it or the timed window could never expire.

**3.2 The port's form, and one place it cannot follow (§2V.2).** `_passedPlayTimeCycles` is a
`uint32`; `vm_passed` is a byte and `var21 * 30` reaches 7,650. The deadline is therefore held as an
absolute 16-bit mark on `vm_vms`' low half — one `fdb`, no second counter to keep in step, compared
by signed difference so it is wrap-safe. Naming the 6809 form at the point of the decision, per
§2V.2's "residency / unbounded containers" rows.

**3.3 §4D's derivation, and it corrects the dispatch's clock.** The dispatch named 1.789390 MHz.
The tick here is the **vertical sync**: `vm_step_clock`'s own header calls its unit "one
VERTICAL-SYNC tick" and `vm_cycle.s:364` fixes it at 16.667 ms. The data-format fact is **1 unit =
0.5 s**, so `0.5 / 0.016667 = 30 ticks per unit`. ScummVM's `* 20` at `text.cpp:392` is **its own**:
its passed-cycles unit is 25 ms (`global.cpp:262`, `curPlayTimeMilliseconds / 25`) and 0.5 s / 25 ms
= 20. **20 and 30 are the same half-second in different units** — §2.1 split stated, and the same
shape as T-P0-085's `* 20` finding.

**3.4 §2H's three checks, on the message-box mechanism.**
1. *A second mechanism for a different object class?* **Yes, and it is the subject of Amendment 1 —
   see §4A below.** `print` is not the only opcode that blocks.
2. *The calling routine.* `messageBox` is called from `cmdPrint`, inside the opcode, inside the
   cycle. Nothing unwinds — which is what makes §1.3's invariant hold by construction.
3. *Grep the reports for the same subsystem.* T-P0-085 established the two governors already exist;
   T-P0-085b established the `getstring` analogy does not transfer. Neither contradicts this; both
   are cited, not re-derived.

**3.5 Sibling claim (§2S).** No sibling claim is load-bearing here. `hal_sync_check.py` was run and
reports OK across POP3_port and karateka_coco3, 11 files compared, at the working trees as of this
task. **`-DHAL_KEYBOARD` selects existing HAL code and is not a HAL change** — no shared file was
touched.

### 4 — Verification (AC-by-AC)

★ The AC texts below are **restated from the dispatch, not quoted**; the numbering is the
dispatch's.

- **AC-1 [class: state-comparable] — `vm` gate 9/9 after the change.** **MET.** Fresh run, all nine
  titles PASS, 600 cycles × 288 bytes, exclusion set EMPTY, 0 divergent cycles. `vm_probe.s` links
  `vm_text_ops.s` but does not define `TEXT_WIRED`, so `vmop_print` is `equ vm_op_modelled` there —
  **the vm gate structurally cannot hang on the new loop.**
- **AC-2 [class: byte-comparable] — `res` gate 1,264/1,264 after the change.** **MET.** Fresh run,
  10 (title, volume) sweeps, 0 mismatched, 0 guest-reported failures.
- **AC-3 [class: byte-comparable] — the blocking implementation lands and `p3b` is untouched.**
  **MET.** `p3b` reassembles to `58AD3C27…`, **13,918 B, byte-identical**, `P3_CODE_END` still
  `$52F8`, spare against `CP_CEL $5300` still **8**. Verified by rebuild, not assumed.
- **AC-4 [class: state-comparable] — the in-game timer advances across a held box.** ★★★ **UNMET —
  BLOCKED, not failed.** The instrument is built and reports honestly; there is no box to measure.
  See §7.1.
- **AC-5 [class: state-comparable] — flag 15 gives no wait; var 21 closes with no key and reads 0
  after.** ★★★ **UNMET — BLOCKED.** The code is present and matches `text.cpp:373-380` and `:411`;
  nothing exercises it. The headless run with `P3B_VAR21=2` ended with **`var21 now 2`** — the arm
  was never consumed, which is the instrument correctly refusing to claim a box appeared.
- **AC-6 [class: eye-gated] — ENTER releases the block.** ★★★ **UNMET — BLOCKED.**
- **AC-7 [class: eye-gated] — ESC dismisses.** ★★★ **UNMET — BLOCKED.** `tx_wt_key` is written so
  this becomes a measurement rather than an eye-only claim when a box can be reached. ★ **Cancel has
  no consumer**: the oracle's `messageBox` returns false and its caller acts on it; nothing in this
  port reads it yet. Recorded, not invented.
- **AC-8 [class: byte-comparable] — the fault arm makes the gate go red.** ★★★★★ **UNMET, AND THIS
  IS THE ONE THAT MATTERS MOST (§2W).** The arm exists and is **15,033 B, exactly 3 bytes smaller
  than the clean build** — the single `jsr vm_step_clock` and nothing else. **It has never been seen
  to go red**, because nothing reaches `print`. Per §2W the wait loop's adjudication is therefore an
  **unexercised assertion**, and no pass of `p3b_text` may be quoted as covering it. Recorded in the
  `p3b_notick` manifest row so a later reader cannot mistake its presence for its proof.
- **AC-9 [class: byte-comparable] — sizes and hashes for both rows.** **MET.**

  | row | flags added | bytes | SHA-256 | `P3_CODE_END` | spare/headroom |
  |---|---|---|---|---|---|
  | `p3b` | none | 13,918 | `58AD3C27164BD63F…` | `$52F8` | **8 B** to `CP_CEL $5300` |
  | `p3b_text` | `-DHAL_KEYBOARD` | 15,036 | `AF0B2A027A960DF4…` | `$5756` | **170 B** to `P3_FONT $5800` |
  | `p3b_notick` | `+ -DTEXT_FAULT_NOTICK` | 15,033 | `2268DAB7B3CFE6D0…` | `$5753` | 173 B |

  Growth 14,582 → 15,036 = **466 B** of 624 headroom (~318 B `HAL_KEYBOARD` [P6.24] + 148 B of wait
  loop). Retired identity `FA7F2FB9… 14,582 B` recorded in the row.
- **AC-10 [class: suite] — full suite green.** **MET.** `pic` 45/45 · `res` 1,264/1,264 · `cel`
  9,193/9,193 · `comp` 124/124 · `p3b` 160 cycles no stall · `p3b_text` 120 cycles no stall.
  **155.1 s** wall clock. ★ `p3b_text` ran headless and completed **without** needing the var-21
  dismissal, for the reason in §7.1.
- **AC-11 [class: eye-gated] — Jay confirms the message stays until ENTER or ESC.** ★★★ **UNMET —
  BLOCKED.** ★★ There is nothing to show. Per §4A.2 I am not offering an eye gate of a build whose
  new path cannot execute; that would be a gate on the old behaviour wearing this task's name.
- **AC-12 [class: byte-comparable] — flag set added and the row re-baselined.** **MET.** The flag
  lives in `p3b_show.ps1`'s flag block and `gates.manifest` (§2F, one home); `run_gates.sh`
  delegates to the former and needed no change.

### 4A — The enumeration (dispatch §4A), taken fresh

| what a cycle does | in the block |
|---|---|
| in-game timer (`vm_vms`, vars 11-14) | **SERVICED** — and it is what the deadline is measured in |
| `vm_passed` (pacing) | **ADVANCED AND RESET ON BOTH SIDES** — `text.cpp:395/409`; §3.1 corrects my earlier call |
| `vm_tdelay` recompute | advanced with it, harmless |
| the key scan | **SERVICED** — it is the dismissal |
| `hal_frame_hi/lo` | **SELF-SERVICING** ($010C IRQ) — the tick source, never the deadline |
| motion / sprites / cycle body | **NOT serviced, and that is fidelity** — the oracle's cycle is suspended too |
| sound | **not applicable — unimplemented.** See below |

**4A.1 Amendment 1 — does `sound` block? ★★★★★ YES, AND THE ORACLE NAMES THIS EXACT TARGET.**
Jay's recollection is **confirmed**, at `9d9b9e93`:

```
op_cmd.cpp:736  if (vm->getPlatform() == Common::kPlatformApple2 ||
op_cmd.cpp:737      vm->getPlatform() == Common::kPlatformCoCo3) {
op_cmd.cpp:738      // Play the sound until it finishes or until a key is pressed.
op_cmd.cpp:739      // Sound playback is a blocking operation on these platforms.
op_cmd.cpp:741      if (vm->getFlag(VM_FLAG_SOUND_ON)) {
op_cmd.cpp:742          vm->_sound->startSound(resourceNr, flagNr);
op_cmd.cpp:743          vm->waitAnyKeyOrFinishedSound();
op_cmd.cpp:744          vm->_sound->stopSound(); }
op_cmd.cpp:746      vm->setFlagOrVar(flagNr, true);
op_cmd.cpp:748  } else { vm->_sound->startSound(resourceNr, flagNr); }
```

1. **Returns immediately or waits?** **Waits — on CoCo3 and Apple II only.** Every other platform
   takes line 748 and returns at once.
2. **What sets the completion flag, and when?** Two different answers, and the split is §2.1's.
   **On our platform** `cmdSound` sets it itself at line 746, immediately after the blocking wait —
   so the flag is true by the time the next opcode runs. On non-blocking platforms `startSound`
   clears it (`sound.cpp:148`) and `soundIsFinished`/`stopSound` set it (`sound.cpp:164`, `:173`)
   from the sound generator — and `sound.cpp:170` is a `FIXME` about "unsynchronized background
   threads", so **that callback shape is ScummVM's own and is not ours.**
   ★ This also resolves the dispatch's counter-evidence: `sound(nn)`'s completion flag exists
   because of line 748's platform, not ours. The argument count implied nothing about blocking.
3. **An inner loop comparable to `CYCLE_INNERLOOP_MESSAGEBOX`?** **No.** `CycleInnerLoopType`
   (`agi.h:350-360`) has nine members and none is sound. `waitAnyKeyOrFinishedSound`
   (`keyboard.cpp:685-694`) is a plain `while` **inside the opcode** — `wait(10)` plus
   `doPollKeyboard()`. ★★★★ **So it is the same shape as our `print` block, and §4B's handshake
   covers both by construction: the host sees GO still set and a posted key releases it. No
   redesign, and the handshake did not have to be built twice.**
4. **Does the message-box path touch sound?** **No.** `text.cpp` references sound only for the
   status-line on/off label (`:616`, `:618`). A box leaves playback running.
5. ★★★★★ **The consequence that does bind us, and it is a near miss.**
   `waitAnyKeyOrFinishedSound` **does not call `inGameTimerUpdate()`.** The game clock advances
   across a message box and **does not** advance across a blocking sound. Had I factored
   `tx_wait_dismiss` into a general "block until a key" helper with the tick inside it — the obvious
   refactor the moment a second blocking opcode appears — **sound would have inherited a tick the
   oracle does not have.** The tick stays in `print`'s own loop, and that is now a recorded reason
   rather than an accident. Noted at the seam in `vm_text_ops.s`.

★★ Nothing to implement: 62/63/64 remain `vm_op_modelled` and `src/engine/sound/` is empty.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim, abridged to the verdict lines):**
```
=== AC-2 SUMMARY ===                     [vm_run.ps1]
Kingquest1 PASS   Kingquest2 PASS   Kingquest3 PASS   SpaceQuest-1 PASS   SpaceQuest-2 PASS
PoliceQuest1 PASS   larry1 PASS   BlackCauldron PASS   MixedUpMotherGoose PASS

=== TOTAL ===                            [res_run.ps1]
byte-identical resources: 1264 across 10 (title, volume) sweeps
all sweeps clean

per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ p3b headless: 160 cycles, no stall
★ p3b headless: 120 cycles, no stall
★ gates run: pic res cel comp p3b p3b_text  -- all green      [155.1 s]

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared,
           EOL/guard/export-placement normalised)

[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   8   $FFA5 $FFA6
```
★ `hal_sync_check.py` run although no shared file was touched, because the flag set gained
`-DHAL_KEYBOARD` and the claim "that is a selection, not a change" should be checked rather than
asserted. `reg_discipline.py` is unchanged at 8 — this task touched `src/harness/`, not
`src/engine/`.

**25.2 bundled-artifact grep:** N/A — no bundled artifact changed; `p3b` is byte-identical and the
two text binaries are harness probes, hashed in AC-9.

**25.3 operator-runtime-smoke:** ★★★ **NOT OFFERED THIS TASK, deliberately.** The new path cannot
execute on any available corpus (§7.1), so an eye gate would show the pre-existing behaviour under
this task's name. Per §4A.2 that makes this a component-level report, not an integration one.

### 6 — Reactive deviations and route accounting

1. **The wait loop was rebuilt after reading the oracle** (§3.1). The first implementation derived
   the deadline from the VBL counter to protect `vm_passed`; `cycle.cpp:558` showed `vm_passed` *is*
   the counter the deadline lives in. §22.5 change, and it is a correction to §4A's census as the
   dispatch framed it.
2. **`-DTEXT_FAULT_NOTICK` is the dispatch's preferred fault shape and it works as specified** —
   because the deadline sits on the game clock, one omitted `jsr` both freezes the timer and makes
   the box unclosable. It is built and **unexercised**; see AC-8.
3. **`vm_input_script.py --wants-print` and `print_first_cycle.py` are additions the dispatch did
   not ask for.** They exist because AC-4..AC-8 turned out to rest on an unstated premise — that
   something reaches `print` — and that premise is false. Measuring it was cheaper than guessing at
   a title.
4. **ROUTE ACCOUNTING.** I proposed no route this task beyond the dispatch's §4C–§4E. Of those:
   §4C (implementation) and §4E (flag set, re-baseline) are **fully implemented**. §4B's handshake
   question is **answered as "no change needed"** and Amendment 1 independently confirms that answer
   generalises to `sound`. **What I did NOT implement: the ENTER/ESC injection for the real arm.**
   I built the var-21 headless path and the observables, then stopped when the corpus measurement
   came back negative — posting a key to release a box that never appears would have been work with
   no possible result. Stated here because a diff cannot show it.

### 7 — Uncertainty flags

**7.1 ★★★★★ THE BLOCKER: nothing in the pinned set reaches `print`. Measured three ways.**

| instrument | scope | result |
|---|---|---|
| `vm_opcov.py` | 9 titles, 600 cycles, no input | `$65 print` and `$66 print.v` in the **NEVER-REACHED** list for every title |
| `print_first_cycle.py` (new) | 9 titles, **3,000 cycles**, no input | **`NEVER` for all nine**, 0 hits |
| `vm_input_script.py --wants-print` (new) | 6 titles, every synthesisable `said()` line | **0 of 59 lines reach it** |

★★★★ **Why, and it is not a defect.** Without input an AGI game sits in attract mode; the intro text
is `display` (`$67`/`$68` — 221 executions in Kingquest1's first 600 cycles), not `print`. And the
`said()` census that generates input lines is dominated by the **global** input handler's
meta-commands — Kingquest1's two `--eye` lines are the speed words — because the room-specific
`said()`s only enter the census while that room is current, and the titles never leave their intros.
PoliceQuest1 is the sharpest case: 28 patterns, and the eight gameplay-shaped ones reach
**unimplemented command opcode 75**, not `print`.

★★★ **This is L-86 one step further on.** The lesson says a fixed sample that always passes is
evidence about the sample first. Here the sample cannot reach the code at all, so `p3b_text`'s green
is a true statement about the wired opcodes and the decode and **says nothing whatever about the
wait loop.** That is now written into the manifest row rather than left to be inferred.

★★ **I am not proposing a route.** Getting a title into a playable room means driving its intro with
posted keys and then scripting a command — a multi-step playthrough whose reliability is unmeasured,
and choosing to build one is a dispatch-level decision, not mine to take under §22.5.

**7.2 The fault arm is unproven, and that is §2W's exact subject.** It is 3 bytes smaller than the
clean build, which is evidence the `jsr` is the only difference — it is **not** evidence the loop
hangs without it. Do not treat its existence as its demonstration.

**7.3 `tx_wt_key` has no consumer.** It is the port's `_messageBoxCancelled`. Written, read by the
harness, acted on by nothing.

**7.4 Var 21 is re-armed every cycle by the harness, by necessity.** `messageBox` zeroes it on exit
(`text.cpp:411`), so a single arm auto-closes exactly one box. The harness standing in for a player
who keeps pressing a key is stated in `p3b_run.lua` rather than hidden.

**7.5 `MixedUpMotherGoose` raises on command opcode 73 at cycle 831** in the offline reference. Out
of scope here and noted only because `print_first_cycle.py` surfaced it.

### 8 — Follow-up candidates
1. ★★★★ **Decide how the blocking path gets gated at all** (§7.1). Candidates, unmeasured: drive an
   intro to a playable room with posted keys; find a title whose intro *does* box; or accept that
   the wait loop is gated only by Jay's eye once a playthrough exists.
2. ★★★ **`sound` will block on this target** (§4A.1). When it is implemented it needs
   `waitAnyKeyOrFinishedSound`'s shape — a poll loop **without** the timer tick — and `VM_FLAG_SOUND_ON`.
3. ★★ **An owner-row ratchet for `$FFA4`** — `vm_text_ops.s`'s window blit is a second writer of the
   MMU register file (§2N.1); still reported, still not gated.
4. ★ **The allowlist filter in `p3b_show.ps1` dropped this task's new log lines** — the same shape its
   own comment warns about, third instance. Worth inverting to a denylist.

### 9 — User interaction during task
**Amendment 1 to T-P0-085c**, received mid-task: verify or kill Jay's recollection that `sound`
blocks. Answered in §4A.1 — **confirmed, and specifically for `kPlatformCoCo3`**. It added one item
to §4A and changed no AC. It also produced the §4A.1(5) near miss, which is the more useful half.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-10-a-premise-an-ac-rests-on-can-be-unstated-and-false.md`
- `seeds/AGI/live/2026-09-10-a-census-of-what-a-loop-must-service-can-be-inverted-by-the-reference.md`

### 11 — Commit
`289b72e` — the work and this report (pushed to origin/wip before reporting).
Pool: `methodology-candidate-pool` `7ed575b`, two rows under `seeds/AGI/live/`.
