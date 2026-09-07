## Form B Report — P6.8 — The text work, on the corrected model
**Class:** build.  wip.  ★★★★★ **PARTIAL — AC-4a is answered and it is a §7 trigger 3. The build is
not done and is not claimed.**

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-07 ~22:00 local (HEAD `4ecb2f9`, wip). Clean apart from an untracked
`coco_agi.code-workspace`.

---

### 4 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `4ecb2f9`, `wip`, clean |
| POP + Karateka | §2T: P6.7 §0's `104b197` / `29f8f0a`, **both unchanged**; POP 0 tracked-modified, karateka 1 (`harness/smoke/last-run.log`, a run log) |
| `hal_sync_check.py` | **OK in all three** — §5 |
| the gate rows | ★★ **cited, not re-run** — no gated file is touched (§7.4) |
| flag sets — enumerate and diff | ★ unchanged from P6.7; the `p3b`/`PIC_NOCOUNT` row stands (§7.5) |
| the clock — measure it | ★★ **not measured this task — no timing figure is published here** |
| **the oracle's text path** | ★★★★★ **two buffers confirmed; the restore renders from `_activeScreen`** — P6.6 §3.A, unchanged |
| map headroom | ★ **`MAP_RESERVED` 3,328 B UNCHANGED**; `MAP_FONT` `$E0B8`, 2,048 B; **M-48's bytes not touched** |

---

### 1 — Summary

★★★★★ **Jay's question has a definite answer in the oracle, both halves are right, and answering it
turned up something bigger than the question.**

> **Jay:** *"It seems the game 'pauses' when messages are displayed to screen, the animation is
> paused. I think the game clock keeps running though."*

★★★★ **Both halves confirmed, with file:line** (§3.A): the message box runs an **inner loop** that
does not call `interpretCycle()` — so the cycle does not advance and sprites freeze — while calling
`inGameTimerUpdate()` **every iteration**, which writes `VAR_SECONDS/MINUTES/HOURS/DAYS` directly.

★★★★★ **And the bigger thing: the oracle's clock is driven by REAL ELAPSED TIME and both of our
legs count cycles instead.** ScummVM's timer reads milliseconds from a wall clock; our Python
reference and our 6809 both advance a *virtual* millisecond counter by 25 per pacing iteration.
**They agree with each other and differ from the oracle in the same way — so the 288-byte state
diff cannot see it.** That is §2O.1's named hazard, live.

★★★ **Not done: AC-1, AC-3, AC-5, AC-6, AC-7, AC-8.** The build is untouched. §7.1.

---

### 2 — Files modified

**None.** ★★ This task produced a finding and no code. The report is the artifact.

---

### 3 — Reasoning

#### 3.A ★★★★★ AC-4a — three questions, three answers, from the oracle

**The mechanism** [`text.cpp:395-409`]:

```cpp
_vm->inGameTimerResetPassedCycles();
_vm->cycleInnerLoopActive(CYCLE_INNERLOOP_MESSAGEBOX);
do {
    _vm->processAGIEvents();
    _vm->inGameTimerUpdate();
    if (windowTimer > 0) {
        if (_vm->inGameTimerGetPassedCycles() >= windowTimer)
            _vm->cycleInnerLoopInactive();          // auto-close
    }
} while (_vm->cycleInnerLoopIsActive() && !(_vm->shouldQuit() || _vm->_restartGame));
_vm->inGameTimerResetPassedCycles();
```

| question | answer | evidence |
|---|---|---|
| **Does the cycle advance while a window is up?** | ★★★★ **NO** | `interpretCycle()` is not in that loop. The loop calls only `processAGIEvents` and `inGameTimerUpdate` [`text.cpp:397-407`]. **Sprites freeze — Jay's first half, and it is AGI's design, not a port artifact.** |
| **Do `VAR_SECONDS/MINUTES/HOURS/DAYS` keep running?** | ★★★★★ **YES** | `inGameTimerUpdate()` runs every iteration [`text.cpp:399`] and writes the four vars **directly** — *"Read and write to VM vars directly to avoid endless loop"* [`global.cpp:292-313`]. **Jay's second half, confirmed.** |
| **Does the 25 ms tick keep running?** | ★★★ **YES, but the WINDOW's counter is scoped** | `curPlayTimeCycles = inGameTimerGet() / 25` and `_passedPlayTimeCycles += delta` accumulate [`global.cpp`]. ★★ But `inGameTimerResetPassedCycles()` brackets the loop [`text.cpp:395, 409`], so the *passed-cycles* counter is per-window — it is what the auto-close timer reads [`:402`] — while the **absolute** timer is untouched. **Two counters, one question, and they answer differently** [L-25]. |
| **`VAR_TIME_DELAY`?** | ★★★ **Not consulted** | It paces `interpretCycle` in the main loop, which is not running. ★ Structural, not separately evidenced. |

#### 3.B ★★★★★ And the thing the question exposed: our clock is not the oracle's clock

★★★★ **The oracle's in-game timer is WALL-CLOCK driven.** `inGameTimerUpdate()` opens with
`uint32 curPlayTimeMilliseconds = inGameTimerGet();` — real elapsed milliseconds — and derives both
the 25 ms cycle count and the seconds from it. **That is why the clock survives a blocking window:
nothing has to tick it.**

★★★★★ **Both of our legs count cycles instead:**

| | mechanism |
|---|---|
| oracle | `inGameTimerGet()` → **real elapsed ms** [`global.cpp`] |
| our Python reference | `self.virtual_ms += 25` per pacing iteration; `timer_update()` reads `virtual_ms // 25` and `// 1000` [`cycle.py:122, 146-152`] |
| our 6809 | `vm_step_clock: vm_vms += 25` per call [`vm_cycle.s`] |

★★★★★ **They agree with each other and differ from the oracle in the same way, so the state diff is
blind to it.** §2O.1, verbatim: *"if the CoCo3 output is compared to the offline output, both can be
wrong in the same way and the suite reports green forever."* **The nine-title gate is byte-identical
per cycle and would be byte-identical whichever clock model we chose**, because both legs choose the
same one.

★★★ **The virtual model is a DELIBERATE and correct choice for the gate**, and `vm_stage.py`'s own
header says why: reproducing the pacing gate is *"what makes cycle number and virtual time track
each other — the relationship the timer vars depend on"*. **A wall clock would make the diff
non-deterministic.** ★★ So this is not a defect to fix; it is **a divergence from the original that
nothing currently measures**, and the message window is where it first becomes observable.

★★★★ **Two concrete consequences:**

1. ★★★★ **If our port blocks on a message window, our clock STOPS and the oracle's does not.**
   `vm_step_clock` is only called from `vm_pace`; a blocking window that does not pace freezes
   `VAR_SECONDS`. **A game that checks elapsed time across a long message diverges** — §7 trigger 3's
   exact wording, *"surfaces weeks later as a puzzle that will not solve"*.
2. ★★★ **Even with no window, our clock runs slow against a player's watch.** P6.7 measured
   **2.22 cycles/s** where the pacing model assumes the cycle rate the game asked for; our
   `virtual_ms` advances 25 ms per iteration regardless of how long that iteration took. **The
   game's sense of time is decoupled from the player's**, and P6.7's figure is what makes that
   concrete rather than theoretical.

★★ **What I have NOT done:** measured a divergence. **No game in the corpus has been shown to read
the clock across a message window.** This is a mechanism finding with a named risk, not an observed
failure — and saying which it is matters [L-25].

#### 3.C AC-10 — the glyph source, decided

★★★ **The corpus ships no font** [P6.6 §3.C: DOS/EGA/VGA falls back to
`Graphics::DosFont::fontData_PCBIOS`], so the glyphs are **ours to supply and their source is a
decision**. ★★ **Decision: an authored 8×8 table**, `MAP_FONT $E0B8`, 2,048 B (256 × 8) — already
reserved, and §2B already marks it a PROTECTED authored asset.

★★★★ **Provenance, and it is a §2.1 divergence stated rather than hidden:** we are **not**
reproducing IBM's ROM bitmaps. What must match is the **8×8 cell in a 40-column grid**, because that
is what AGI computes window geometry in [design §2.1]; the glyph shapes are presentation.
★★ **§2V's row for it:** in the reference a font is a `const byte*` of 2,048 bytes; on the 6809 it is
a resident table at a fixed address, indexed `MAP_FONT + char*8`, **no allocation, no copy** — the
one structure in this subsystem that transfers unchanged.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [eye-gated] — NOT DONE.** Nothing reaches the screen. **Not "pending Jay": there is nothing
  to watch.** §4A unsatisfied; hence PARTIAL.
- **AC-2 [byte-comparable] — PASS.** `hal_sync_check` OK ×3, `reg_discipline` unchanged at 8.
  §2T cited. `MAP_RESERVED` unchanged at 3,328 B.
- **AC-3 [byte-comparable] — NOT DONE.** No text renders.
- **AC-4 [state-comparable] — NOT DONE.** The restore is unmeasured. ★★★ **But §3.A answers the
  half of it that §2A.1 asked**: the cycle is blocked while a window is up, so **the restore's cost
  lands inside a stall the player is already in, not inside a frame.** ★★ That is the "what does it
  compete with" question, answered ahead of the measurement.
- **AC-4a [state-comparable] — ANSWERED, and it is §7 trigger 3.** §3.A, §3.B.
- **AC-5 [byte-comparable] — NOT DONE** above the matrix. ★ P6.6 proved the keys reachable; the
  software path does not exist.
- **AC-6 [state-comparable] — NOT DONE.**
- **AC-7 [byte-comparable] — NOT DONE.** No new gate, so nothing to fault-inject.
- **AC-8 [state-comparable] — NOT DONE.**
- **AC-9 [state-comparable] — PARTIAL.** `MAP_FONT` `$E0B8`/2,048 B confirmed correct and already
  reserved; `MAP_RESERVED` unchanged; **M-48's bytes not touched.** ★ Text *state* placement is not
  decided because nothing consumes it yet.
- **AC-10 [state-comparable] — ANSWERED.** §3.C.
- **AC-11 [state-comparable] — §3.B.** ★★★★ The dispatch anticipated a save-under correction and a
  restore cost; **it did not anticipate that answering Jay's clock question would expose a
  gate-invisible divergence between our clock model and the oracle's.**
- **AC-12 [suite] — one candidate.** §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — AC-4a, the message-box inner loop (verbatim, `engines/agi/text.cpp:395-409`):**

```cpp
	_vm->inGameTimerResetPassedCycles();
	_vm->cycleInnerLoopActive(CYCLE_INNERLOOP_MESSAGEBOX);
	do {
		_vm->processAGIEvents();
		_vm->inGameTimerUpdate();
		if (windowTimer > 0) {
			if (_vm->inGameTimerGetPassedCycles() >= windowTimer) {
				// Timer reached, close automatically
				_vm->cycleInnerLoopInactive();
			}
		}
	} while (_vm->cycleInnerLoopIsActive() && !(_vm->shouldQuit() || _vm->_restartGame));

	_vm->inGameTimerResetPassedCycles();
```

**25.1 — AC-4a, the clock writing the game vars (verbatim, `engines/agi/global.cpp:292-313`):**

```cpp
	int32 playTimeSecondsDelta = curPlayTimeSeconds - _lastUsedPlayTimeInSeconds;
	if (playTimeSecondsDelta > 0) {
		// Read and write to VM vars directly to avoid endless loop
		uint32 secondsLeft = playTimeSecondsDelta;
		byte   curSeconds = _game.vars[VM_VAR_SECONDS];
		byte   curMinutes = _game.vars[VM_VAR_MINUTES];
		byte   curHours = _game.vars[VM_VAR_HOURS];
		byte   curDays = _game.vars[VM_VAR_DAYS];
```

**25.1 — §3.B, the wall clock (verbatim, `global.cpp`, `inGameTimerUpdate`'s first lines):**

```cpp
	uint32 curPlayTimeMilliseconds = inGameTimerGet();
	uint32 curPlayTimeCycles = curPlayTimeMilliseconds / 25;
```

**25.1 — §3.B, both of our legs (verbatim):**

```
tools/agivm/cycle.py:146   def timer_update(self):
                    :147       cur_cycles = self.virtual_ms // 25
                    :152       cur_seconds = self.virtual_ms // 1000
     (virtual_ms is advanced by `self.virtual_ms += 25` per pacing iteration in run())

src/harness/vm_cycle.s     vm_step_clock:
                                   ldd     vm_vms+2
                                   addd    #25
                                   std     vm_vms+2
```

**25.1 — `hal_sync_check.py` / `reg_discipline.py` (verbatim):**

```
coco_agi        [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port       [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3  [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s                       8  $FFA5 $FFA6
```

**25.1 — the map, unchanged (verbatim):**

```
  MAP_RESERVED    equ     $5300
  MAP_RESERVED_END equ    $6000           ; 3,328 B, parser + sound (floor 3,072)
  MAP_FONT        equ     $E0B8           ; the authored 8x8 40-column font, 2,048 B (§2B)
```

**25.2 — bundled-artifact grep:** N/A — no target binary is built or shipped by this task.

**25.3 — operator-runtime-smoke:** **N/A.** Nothing reaches a screen (AC-1).

---

### 6 — Reactive deviations and route accounting

**Deviations (§22.5):**

1. ★★★★★ **I answered AC-4a first and stopped there.** §5 lists AC-3 and AC-5 as "the task"; I did
   neither. **AC-4a was the cheapest item and a §7 trigger 3**, and what it found bears on every
   timing-dependent behaviour in the port — which seemed worth more than a partial renderer.
   **Scaling the task down is Jay's call, so the scope is intact and unreduced.**

**Route accounting.** ★★ I proposed no route. ★★★ **What I have NOT built and did not claim:** the
glyph table, `text_draw`, the rectangle-restricted present, the input line, `have.key`,
`get.string`, and their gates. ★ P6.6's route-accounting note stands: *"considerably cheaper than
the dispatch assumed"* remains an **estimate**, still unmeasured.

---

### 7 — Uncertainty flags

1. ★★★★★ **Six ACs untouched.** AC-1, AC-3, AC-5, AC-6, AC-7, AC-8. **The task needs another pass**
   and this report does not claim otherwise.
2. ★★★★★ **§3.B is a mechanism finding, not an observed divergence.** No corpus game has been shown
   to read the clock across a message window. ★★★ **The risk is real and the failure is not
   demonstrated** — and per §2W I am not entitled to call it a defect until it is.
3. ★★★★ **Our clock model cannot be checked by the existing gate**, because both legs share it
   (§3.B). ★★ **Checking it needs a comparison against the ORACLE's trace, not against our Python** —
   which is a different instrument from the one this project has.
4. ★★★ **`VAR_TIME_DELAY`'s answer is structural, not evidenced.** I did not find a line proving it
   is unread during the inner loop; I inferred it from `interpretCycle` being absent.
5. ★★ **The gate rows were cited, not re-run.**
6. **Carried:** `CP_CEL` (p3b has 3 bytes free, so its trigger is due); `pic`'s corpus; the patch
   series; the instruction budget; the surviving resource copy.

---

### 8 — Follow-up candidates

1. ★★★★★ **Decide the clock model** (§3.B) — virtual-for-determinism versus wall-clock-for-fidelity,
   and what happens to `VAR_SECONDS` when a window blocks. **This is a design ruling, not a fix.**
2. ★★★★ **Build the text path** on P6.6 §3.A's model; §3.A here adds that its cost lands in a stall.
3. ★★★ **An oracle-trace comparison for the timer vars** — the instrument §7.3 says does not exist.
4. ★★ **Evidence for `VAR_TIME_DELAY`** (§7.4).

---

### 9 — User interaction during task

- ★★★★★ Jay: *"It seems the game 'pauses' when messages are displayed to screen, the animation is
  paused. I think the game clock keeps running though."* — **both halves correct** (§3.A), and the
  second half is what led to §3.B.
- ★ Standing instruction, carried: **do not commit PNGs unless asked.** None produced.

---

### 10 — Candidate(s) captured this task

One, in `seeds/AGI/live/`:

- `2026-09-07-two-legs-that-share-a-model-cannot-check-it`

★ **Not captured:** the save-under refutation belongs to
`a-first-mechanism-is-a-hypothesis-about-the-whole-mechanism`, which exists.

### 11 — Commit

Report only; **no code changed this task.**
