## Form B Report — T-P0-100 / P6.45 — Logic 102: the port runs a body the reference jumps out of
**Class:** measurement.  wip.  **§4D fired — and its inference does not hold. §6 stops here.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-16 02:00 (HEAD f6b8919, wip). One `src/` file, publish-only behind a flag; two harness
tools.

### 1 — Summary
★★★★★ **The operand is measured and it AGREES.** `lindirect.v(v2, v255)` — `p0 = 2`, which is
`VM_VAR_BORDER_TOUCH_EGO` — and **`var 2` is 0 in the port and 0 in the reference**, every cycle of
the window.

★★★★★ **So §4D's condition fired and its conclusion is wrong.** The dispatch predicted that an
agreeing operand means "the handler's READ diverged". It does not. **The reference never executes
that instruction at all.**

★★★★★ **Logic 102 opens with two guards and the reference leaves through the second:**
```
0000  if (! isset(2)) goto +3      ; ENTERED_CLI
0007  goto 0908
000A  if (isset(4)) goto +3        ; SAID_ACCEPTED_INPUT
0010  goto 0908                    <- the reference takes this and leaves
```
★★★★ **The reference's trace confirms it: four test rows in logic 102 and ZERO commands.** The port
falls through instead and runs the body, reaching a `lindirect.v` 2,300 bytes later.

★★★ **§1.2 was right** — the answer is in logic 102, which no trace had ever read.

### 2 — Files modified
- `src/harness/vm_state.s` — the P6.44 recorder extended: the watched variable is a parameter, and
  rows carry `p0`, `p1` and flag byte 0. **+162 bytes in the diagnostic arm; 0 in every shipped one.**
- `harness/tools/test_trace.py` — `--commands`, wrapping the reference's command handlers too.
- `harness/tools/p3b_run.lua` — `P3B_WATCHVAR` and the widened readout.

### 3 — Pre-dispatch grep (C-13)
Seven shipped artifacts at P6.40's hashes ✔; untracked one file ✔.

**§3(2)** `vm_v0 = vm_p0 → vm_getvar`, so `lindirect.v` is `A = var[p0]` (the destination's number),
`B = var[p1]`. The operand bytes sit at `vm_code + vm_ip` **during** the handler — `vm_core.s`
advances `vm_ip` only after `jsr ,x` returns, which is what makes §4A readable at all.

**§3(3)** `test_trace.py` wraps tests by rebinding `vm.table.tests[op].handler`. Commands are the
same shape: `vm.table.commands[op].handler`. ★★ **It was as cheap as P6.44 §7.4 said.**

### 4A — ★★★★★ The operand, measured

```
var0 <- 0    opcode $09  logic 102  p0=2  p1=255  flag2=1 flag4=1  caller $26FA
```

| | port | reference |
|---|---|---|
| `p0` | **2** | 2 (same instruction) |
| `var[p0]` = `var 2` | **0** | **0** — cycles 97-103, unchanged |
| `var[p1]` = `var 255` | 0 | 0 |

★★★ **`var[p0] == 0` was never an inference.** The recorder's filter *is* "the destination number
equals the watched variable", so P6.44 §7.1's caution was over-stated — what was genuinely missing
was **which** variable `p0` names, and it is 2.

### 4B — Who writes `var 2`? ★★★★ Nobody, on either side

The reference's `var 2` is **0 across cycles 97-103** with no change, and the port's is 0 at the
write. ★★★★★ **There is nothing to trace: the divergence is not in `var 2`'s value, because both
sides have the same value.** §4B's writer table is empty by construction and the widened window
(§4B's fallback) is not needed — the variable never moves.

### 4C — Logic 101 and 102, read for the first time

**Logic 102** is 2,313 bytes and 46 messages. Its first four instructions are the whole story:
`isset(2)` is True on both sides, so the `!` makes the first expression **False** and both skip the
`goto 0908` at `$0007`. Then `isset(4)` decides.

★★★★★ **Reference at the fed cycle, in logic 102: `isset` $0003 True / EXPR $0001 False; `isset`
$000C True / EXPR $000B True — and no command rows at all.** EXPR True at `$000B` executes the
block at `$0010`, which is `goto 0908` — a jump, handled in the dispatch loop rather than by a
command handler, which is why the command trace is legitimately empty.

★★ The body it skips is a long `said()` chain — `$003C`, `$005C`, `$006C`, `$007C`, `$00A5` … — the
room's own command responses.

### 4D — ★★★★★ The condition fired; the inference did not

§4D says an agreeing operand means the handler's read diverged. **The handler never ran in the
reference.** The measured answer is better than the predicted one: **the divergence is which
instructions are REACHED, not what they read.**

★★★★ **And the guard that decides it is `isset(4)` at `$000A`** — `SAID_ACCEPTED_INPUT`, the flag
whose whole purpose is "this line has already been answered". The reference has it set when logic
102 runs, jumps out, and leaves the room alone.

### 5 — Verdict-time evidence (v0.7 §11)
```
p3b       13918 B 58AD3C27   p3b_text  16258 B 5B19334F   p3b_win3  16258 B 5400A30F
p3b_notick 16255 B F7AE0FCF  p3b_nomap 16255 B 9604AAAA   p3b_fault 15382 B 16DC35EF
p3b_flat  15367 B E7882A33            -- all seven at P6.40's hashes
p3b_v0    15544 B 93C12CD7            -- the diagnostic arm, +162 B over p3b_fault

git diff --stat -- src/ : src/harness/vm_state.s | 44 ++---  (publish only, all guarded)
★ source integrity: clean

port : var0 <- 0  opcode $09  logic 102  p0=2 p1=255  flag2=1 flag4=1
ref  : logic 102 at the fed cycle -- 4 test rows, 0 commands; EXPR $000B True -> goto 0908
ref  : var 2 = 0 at cycles 97..103, unchanged
```
**25.2:** N/A. **25.3:** N/A. ★★ **AC-7 by §2T citation to P6.40** — AC-5 holds.

### 6 — Reactive deviations and route accounting
1. ★★★ **The recorder was extended three times in one task** — the watched variable parameterised,
   then `p0`/`p1`, then flag byte 0. Each addition answered the question the previous row raised.
2. ★★★★ **Adding Y to the register save shifted every stack offset by two**, which the P6.44 comment
   predicted would happen silently. **It was caught by reading that comment before editing**, and
   the map in the source now lists Y's slot explicitly.
3. ★★ **§4B produced no table** because the variable it would trace never changes. Stated rather
   than padded.
4. **ROUTE ACCOUNTING.** §4A, §4B, §4C and §4D are all answered. **No fix attempted.**

### 7 — Uncertainty flags

**7.1 ★★★★★ The port's `isset(4)` at `$000A` was not read directly.** The recorder samples flags at
the **write**, thousands of instructions later, and reports **flag4 = 1** there. ★★★★ **So either
flag 4 was 0 when `$000A` was evaluated and became 1 inside logic 102's body — its `said()` chain
would do exactly that — or the port did not evaluate `$000A` at all.** **That is the one read that
separates the two, and it is the next task's first move.**

**7.2 ★★★ P6.43's said() log stopped before logic 102.** Its 16-row cap ended in logic 1, so **no
instrument has yet seen a `said()` inside logic 102** — which is where §7.1's first hypothesis would
be confirmed or killed.

**7.3 ★★ The reference's `lindirect.v` operands were not captured**, because the reference never
reaches the instruction. The `--commands` wrapper works — it added 17 rows elsewhere in the cycle —
so this is an absence, not a tooling gap.

**7.4 ★★ `memmap.inc`'s flag-packing comment is still stale**; `gates.manifest` still does not record
that `p3b` and `vm_probe` sample at different instants [P6.42], **third task carrying it**.

### 8 — Follow-up candidates
1. ★★★★★ **Read flag 4 at logic 102's entry** (§7.1) — one more publish, or raise P6.43's said() cap
   so logic 102's chain is visible. **This is the last hop and it is one read.**
2. ★★★★ **If flag 4 is 0 at `$000A`: what cleared it between logic 0's match and logic 102?** Both
   implementations clear it in `post_cycle`, which is the wrong end of the cycle.
3. ★★★ **`gates.manifest`'s seam note** (§7.4), now three tasks old.
4. ★★ `memmap.inc`'s packing comment · `RES_E_BIG`'s identity · `VM_ROOM` in the gate rows.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-16-the-divergence-was-which-code-ran-not-what-it-read.md`

### 11 — Commit
`e5935f3` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `8e12261`, one row under `seeds/AGI/live/`.
