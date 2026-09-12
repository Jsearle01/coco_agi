## Form B Report — T-P0-099 / P6.44 — `lindirect.v` in logic 102 writes var 0
**Class:** measurement.  wip.  **The cause is named. §6 stops here.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-14 06:00 (HEAD e353f4a, wip). Jay: **"do it"** — the command recorder P6.43 §8.1 asked
for. One `src/` file, publish-only behind a flag; two harness tools.

### 1 — Summary
★★★★★ **The room is zeroed by opcode `$09`, `lindirect.v`, executing in LOGIC 102.**
```
var-0 writers in vm_cycle 100 : 1
var0 <- 0    opcode $09  logic 102  caller $26BD
```
**One writer, in the whole cycle.** Not `new.room`, not `restart.game`, not logic 0.

★★★★★ **And the port's handler is byte-for-byte the oracle's shape.** `cmdLindirectV` is
`setVar(getVar(p0), getVar(p1))`; `vmop_lindirect_v` is `vm_v1 → B, vm_v0 → A, vm_setvar`, which is
the same two reads in the same roles. **The opcode is not mis-implemented.**

★★★★ **So the destination operand evaluated to 0 in the port.** `lindirect.v` writes *the variable
whose number is in `var[p0]`* — and in the port that number was 0. **The divergence is one variable
upstream, read mid-cycle, and that is the next task's first read.**

★★★ **The recorder was keyed on the EFFECT, not on three commands I would have guessed**, which is
why it caught a writer nobody had named. `new.room` and `restart.game` were both wrong guesses.

### 2 — Files modified
- `src/harness/vm_state.s` — `-DVM_VAR0DIAG`: every writer of var 0 in one cycle, with its opcode,
  logic and caller. Publish-only. **+101 bytes in that arm; 0 in every shipped one.**
- `harness/tools/p3b_show.ps1`, `p3b_run.lua` — `-Var0Diag`, arming and readout.

### 3 — Pre-dispatch grep (C-13)
All seven shipped artifacts at P6.40's hashes; untracked one file; `reg_discipline` 17/1/4.

### 4A — The instrument, and why it is keyed on the effect

P6.43 ended with **every predicate agreeing and the room changing anyway.** The obvious next
instrument was a recorder on `new.room`, `new.room.v` and `restart.game` — ★★★★★ **and all three
would have missed it**, because none of them ran.

`vm_setvar` is the single funnel for every variable write, so a guarded `jsr` at its top with a
`var == 0` test catches **every** writer. One row: value, caller, logic, opcode.

### 4B — Two instrument defects, both caught by their own output

★★★★★ **The stack offsets were wrong twice over, and one of them was invisible.**
```
0,s CC   1,s A   2,s B   3,s X    5,s -> back into vm_setvar    7,s -> ITS CALLER
```
The first version took the value from `1,s` — which is **A, the var number** — and the caller from
`5,s`, the return address of the recorder's own `jsr`.

★★★★★ **The value was right by coincidence**: this call writes var 0 with the value 0, so A and B
are both zero and the wrong offset read the right number. **Only the caller column exposed it** —
it reported `$24FA`, which the listing places *inside `vm_setvar` itself*. ★★★ An address inside
the routine doing the recording is self-evidently not a caller; a value that happens to match is
not self-evidently anything.

★★★★ **Then the corrected caller was still not the answer.** `$26AC`/`$26BD` is `vm_core.s:224`'s
`jsr ,x` — **the opcode dispatch**. It says "a command handler did it" and not which. One more
byte, `vm_op`, names the opcode outright. **Two iterations, each of which produced a checkable
statement that turned out to be about the instrument.**

### 4C — What the two implementations do

```c
// op_cmd.cpp  cmdLindirectV
byte varVal1 = vm->getVar(parameter[0]);   // the DESTINATION's number
byte varVal2 = vm->getVar(parameter[1]);   // the value
vm->setVar(varVal1, varVal2);
```
```
vmop_lindirect_v:
        jsr  vm_v1        ; A = var[p1]  -- the value
        tfr  a,b
        jsr  vm_v0        ; A = var[p0]  -- the destination's number
        jmp  vm_setvar    ; A = var number, B = value
```
★★★★ **The same two reads in the same roles.** The port's handler is correct, so `var[p0]` was 0
when it ran.

★★★ **Both sides reach logic 102 in that cycle** — the reference's test trace lists logics 0, 1,
101 and 102 — so this is not a control-flow divergence into a logic the reference never enters.

### 5 — Verdict-time evidence (v0.7 §11)
```
p3b       13918 B 58AD3C27   p3b_text  16258 B 5B19334F   p3b_win3  16258 B 5400A30F
p3b_notick 16255 B F7AE0FCF  p3b_nomap 16255 B 9604AAAA   p3b_fault 15382 B 16DC35EF
p3b_flat  15367 B E7882A33            -- all seven at P6.40's hashes
p3b_v0    15483 B D9FCC256            -- the diagnostic arm, +101 B over p3b_fault

git diff --stat -- src/ : src/harness/vm_state.s | 67 ++++++  (publish only, all guarded)
★ source integrity: clean

var-0 writers in vm_cycle 100 : 1
  var0 <- 0    opcode $09  logic 102  caller $26BD
vm_tables.s: fdb vmop_lindirect_v   ; 09 lindirectv(vv)
```
**25.2:** N/A. **25.3:** N/A — no shipped artifact changed. ★★ **Suite by §2T citation to P6.40.**

### 6 — Reactive deviations and route accounting
1. ★★★★ **`src/` touched under the same four bounds P6.43's publish used**: behind a flag, off by
   default, every shipped artifact byte-identical, publish-only, in `src/harness/`.
2. ★★★ **The recorder went from 4-byte to 5-byte rows** mid-task, to carry the opcode. The 4-byte
   version's answer was true and useless.
3. **ROUTE ACCOUNTING.** Jay asked for the command recorder; what was built records **every writer
   of var 0**, which is a superset and is why it found a command the narrower version would not
   have watched. **No fix attempted** — §6's first trigger is live and this stops.

### 7 — Uncertainty flags

**7.1 ★★★★★ The operand is not read.** The row names the opcode and the logic but not **which
variable `p0` is**, so "the destination number was 0" is inferred from the handler's shape rather
than measured. ★★★ **One more byte (the operand) settles it**, and it is the next task's first read.

**7.2 ★★★★ Why `var[p0]` is 0 in the port and not in the reference is unknown.** P6.42 established
the state blocks agree at the cycle boundary; this write is mid-cycle, so the variable could have
been set differently earlier in the same cycle — **by something in logic 101 or 102, neither of
which any instrument has looked at.**

**7.3 ★★★ Logic 102 has never been examined.** Every trace so far has filtered to logic 0. The
reference reaches 0, 1, 101 and 102 in this cycle.

**7.4 ★★ The reference's own `lindirect.v` calls at this cycle were not traced** — `test_trace.py`
wraps TESTS, not commands. Extending it is free and would give the reference's side of §7.1.

### 8 — Follow-up candidates
1. ★★★★★ **Record `lindirect.v`'s operands** and the value of `var[p0]` on both sides (§7.1, §7.4).
   **That is the last hop.**
2. ★★★★ **Trace logic 101 and 102**, which nothing has looked at (§7.3).
3. ★★ `memmap.inc`'s stale flag-packing comment · `RES_E_BIG`'s identity · `VM_ROOM` in the gate
   rows · `p3b`'s missing halt detection.

### 9 — User interaction during task
1. Jay: **"do it"** — build the command recorder P6.43 §8.1 proposed. Built as a var-0 writer
   recorder instead, which is a superset; §6.3 says so.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-14-key-the-recorder-on-the-effect-not-on-your-suspects.md`

### 11 — Commit
`3206cb1` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `348bb8a`, one row under `seeds/AGI/live/`.
