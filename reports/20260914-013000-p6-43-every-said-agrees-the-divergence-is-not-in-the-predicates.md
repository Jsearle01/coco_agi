## Form B Report — T-P0-098 / P6.43 — Every `said()` agrees; the divergence is not in `said()`
**Class:** measurement.  wip.  **AC-7's negative result is the deliverable.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-14 01:30 (HEAD 8333218, wip). One `src/` file, publish-only behind a flag; two harness
tools; one added.

### 1 — Summary
★★★★★ **Every `said()` the port evaluates at the fed cycle agrees with the reference — sixteen calls
across two logics, name by name, result by result.** Including the two that mattered:
`said(161)` at `$01FF` **TRUE on both**, and `said(31,146)` at `$022F` **FALSE on both**.

★★★★★ **The `par_accepted` guard works exactly as designed.** `flag4_on_entry` is 0 for the three
calls before the match and **1 for every call after it**, so the "first `said()` consumes the input"
rule is live and `-DVM_FAULT_SAID_PURE` is not in play.

★★★★ **So `restart.game()` at `$023A` did NOT execute at cycle 100** — the port goes on to evaluate
`said` at `$0382`, which is *past* `$023A` in logic 0, and then enters logic 1. **A restart would have
ended the cycle there.** Stated as an inference from the sequence, not a direct read (§7.1).

★★★ **§1.2's `controller(3)` lead is not supported either**, by the same argument: an identical
`said()` sequence across a branchy chain implies identical branch decisions through it.

### 2 — Files modified
- `src/harness/vm_tests.s` — `-DVM_SAIDDIAG`: a 16-row recorder, publish-only. **+133 bytes in that
  arm; 0 in every shipped one.**
- `harness/tools/test_trace.py` — **new.** Wraps the reference's test evaluator at runtime.
- `harness/tools/p3b_run.lua`, `p3b_show.ps1` — arming and readout.

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| seven artifacts | P6.40's hashes | ✔ all seven |
| untracked | one file | ✔ |
| `reg_discipline.py` | 17, one file, four registers | ✔ |

**§3(2)** The reference has **no** per-test log. `tests.test_if_code` is a single clean function, so
it and each bound handler are wrapped **at runtime** — `tools/agivm/` is not edited [§2D, §2O.1].

**§3(3)** `VM_CTRL` is `MAP_VM_CTRL`, written only by `vm_reset_ctrl` [`vm_cycle.s:156`], which is
called at `:256` and `:260`. ★★★ **So the controller table is cleared every cycle** and is not stale
garbage — §1.2's argument-against is confirmed.

**§3(4)** The port's OR group is `vm_ormode` [`vm_core.s:287-418`], structured statement-for-statement
like `tests.py:237-281`: first `$FC` enters OR mode, a true member short-circuits to the closing
`$FC`, a second `$FC` with nothing true makes the expression false.

### 4A — The reference's test log

`test_trace.py`, same scenario as `vm_stage.py` — same `Vm` construction, same vocabulary, same
script, same jump.

★★★★ **An off-by-one in my own tool, found and corrected before it was believed:** the reference
emits its record and **then increments `cycle_nr`** [`cycle.py:474-475`], so the body following
record N runs with `cycle_nr == N+1`. The first run logged `--at 100` and showed every `said()`
false — **the body before the feed took effect.** `--at 101` is the fed cycle.

### 4B — ★★★★★ The two logs, side by side

| ip | reference | port | `flag4_on_entry` (port) |
|---|---|---|---|
| `$01DB` | False | False | 0 |
| `$01ED` | False | False | 0 |
| **`$01FF`** | **True** | **True** | **0** |
| `$0211` | False | False | **1** |
| `$0220` | False | False | 1 |
| **`$022F`** | **False** | **False** | **1** |
| `$0382` `$03A9` `$044A` `$050A` `$0716` `$0C16` | False ×6 | False ×6 | 1 |
| logic 1: `$008C` `$0098` `$00A4` `$00B0` | False ×4 | False ×4 | 1 |

★★★★★ **Sixteen for sixteen.** The port's recorder caps at 16 rows; the reference continues with
more logic-1 calls, all False.

**§4B(2)** — the `$01FC` group's true member is **`said(161)`**, measured True on both. The group's
`controller(24)` is False in the reference.
**§4B(3)** — `said(31,146)` is **False on both**. `controller(3)`'s value in the port is **not
measured** (§7.2).
**§4B(4)** — **flag 4 at `$022F` is 1** in the port: the guard that should reject a second `said()`
is set, and it did reject it.

### 4C — `restart.game` at cycle 100

★★★★ **Did not execute**, by inference from §4B: `$0382` is past `$023A` in logic 0 and the port
evaluated it, then entered logic 1. **A restart ends the cycle** [`cycle.py:489`'s
`not should_restart`], so the sequence could not have continued.

★★ **Not a direct read.** The recorder covers `said()` only; `vm_restart` at cycle 100 would need a
second publish, which §6 says is the next task's if it is wanted (§7.1).

### 4D — Not reached

The disagreement is not in the `||` group: the members agree and so do the results.

### 5 — Verdict-time evidence (v0.7 §11)
```
p3b       13918 B 58AD3C27  p3b_text  16258 B 5B19334F  p3b_win3  16258 B 5400A30F
p3b_notick 16255 B F7AE0FCF p3b_nomap 16255 B 9604AAAA  p3b_fault 15382 B 16DC35EF
p3b_flat  15367 B E7882A33          -- all seven at P6.40's hashes
p3b_said  15515 B CFC2B0AF          -- the diagnostic arm, +133 B over p3b_fault

git diff --stat -- src/ :  src/harness/vm_tests.s | 66 ++++++  (publish only, all guarded)
[reg-discipline] 17 in 1 file over 4 registers      ★ source integrity: clean
```
**25.2:** N/A. **25.3:** N/A — no shipped artifact changed.
★★★ **AC-6 by §2T citation to P6.40**: AC-4 holds, so the suite's inputs are unchanged.

### 6 — Reactive deviations and route accounting
1. ★★★★ **`src/` was touched, as §1.3 authorises**, and within its four bounds: behind a flag, off
   by default, every shipped artifact byte-identical, publish-only, and in `src/harness/` rather
   than `src/engine/`.
2. ★★★ **The reference's side needed no `src/` change and no emulator.** Wrapping its evaluator at
   runtime is what made §4A free, and it is what the dispatch's §4A hoped for.
3. ★★ **My tool's off-by-one was caught by cross-checking against the reference's own `var 88`**
   (§4A) rather than by reading the counter's definition first.
4. **ROUTE ACCOUNTING.** §4A, §4B and §4C are done; §4D was not reached because its precondition
   did not arise. **No fix attempted.**

### 7 — Uncertainty flags

**7.1 ★★★★ AC-3 is an inference, not a measurement.** `restart.game` almost certainly did not run at
`$023A` at cycle 100, because execution continued past it. **But the room still becomes 0 at that
cycle**, so something else does it — and the recorder cannot say what. ★★★ **Two candidates remain
and neither is measured: a `new.room` with a computed argument, or a restart raised from a later
logic.**

**7.2 ★★★ The port's `controller()` results are unmeasured.** §4B's indirect argument is strong — an
identical `said()` sequence across a branchy chain implies the branches agreed — **but it is an
argument, and the same shape of argument has been wrong three times this arc.** A controller
recorder is four more bytes on the same pattern.

**7.3 ★★★ The port's recorder caps at 16 rows and the reference's cycle has more.** The comparison is
complete for the range it covers and **says nothing about `said()` calls after logic 1's fourth.**

**7.4 ★★ `memmap.inc`'s flag-packing comment is still stale** [P6.41 §7.3]. Proposed text unchanged:
the 256 flags are stored **packed in 32 bytes**.

### 8 — Follow-up candidates
1. ★★★★★ **What writes `var 0` at cycle 100.** Every predicate examined agrees; the room changes
   anyway. **The next instrument is a recorder on the COMMANDS, not the tests** — `new.room`,
   `new.room.v` and `restart.game`, with their arguments, in that one cycle.
2. ★★★★ **The `controller()` results** (§7.2) — the same recorder, four more bytes.
3. ★★★ **Raise the row cap** (§7.3) or make it a ring rather than a stop.
4. ★★ `memmap.inc`'s packing comment · `RES_E_BIG`'s identity · `VM_ROOM` in the gate rows.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-14-wrap-the-reference-do-not-edit-it.md`

### 11 — Commit
`1d7ec46` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `e883395`, one row under `seeds/AGI/live/`.
