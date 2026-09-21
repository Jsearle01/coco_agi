## Form B Report — P6.70 — STOPPED at §4A: the wait is `have.key`, not `set.key`
**Class:** recon (dispatched as integration; **stopped under §6 trigger 1 before §4B**).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-20 (HEAD 2b4131d, wip). git status clean apart from `harness/tools/pic_order.py`
(the instrument this task extended) and an untracked `coco_agi.code-workspace`, which this project
did not create and which is not staged. **All eight arms byte-identical to the recorded baseline —
no guest code was changed.**

### 1 — Summary

★★★★★ **STOPPED under §6's first trigger, and the dispatch's premise is falsified by measurement.**
Two independent findings:

1. ★★★★★ **§4A's STOP CONDITION FIRED.** `set.key` binds a **16-bit** AGI keycode
   [op_cmd.cpp:2119]; `HAL_key_scan` returns **8 bits** [hal_globals.s:249]. This title screen binds
   **F1-F10 as `$3B00`-`$4400`** and **Alt+D / Alt+Z as `$2000` / `$2C00`** — scancode-in-high-byte
   forms the HAL cannot produce at all, and whose CoCo-to-PC-scancode mapping this project has
   never established.
2. ★★★★★ **AND `set.key` IS NOT WHAT HOLDS THE TITLE SCREEN.** ★★★★ **Measured: posting a key
   into VAR 19 advances it.** The wait exits on **`have.key`**, and the 22 controller slots polled
   every cycle are KQ1's **global keyboard shortcut table**, not the title's wait.

★★★★★ **All three of Jay's side-by-side observations reproduce from that one variable:**

| opcode, 400 cycles | control | key `$0D` posted at cycle 200 |
|---|---|---|
| `draw` | 0 | ★★★★★ **4** — the alligators |
| `set.view` | 0 | ★★★★★ **3** |
| `clear.lines` | 0 | ★★★★★ **1** — 'press a key to continue' goes |
| `new.room` | 1 | **2** — the screen advances |
| `draw.pic` / `show.pic` | 1 / 1 | **2 / 2** |

### 2 — Files modified
- `harness/tools/pic_order.py` — test-opcode tracing, the controller/binding cross-reference, and
  `--post-key` / `--post-at`. **No guest code touched; all eight arms unmoved.**

### 3 — Reasoning

**§4A(1) — what `set.key` stores** [tier: ScummVM, pin 9d9b9e93; believed ORIGINAL, §2.1].

```c
op_cmd.cpp:2118  uint16 key = parameter[0] + (parameter[1] << 8);   // 16-bit
                 uint16 controllerSlot = parameter[2];
                 ... dedupe on (keycode, slot); a free slot has keycode == 0 ...
                 controllerKeyMapping[slot] = {key, controllerSlot};
                 state->controllerOccurred[controllerSlot] = false;
```

**§4A(2) — how a press becomes a bit, and when it is cleared.** `handleController` scans the
mappings and sets `controllerOccurred[slot] = true`, **returning true** [keyboard.cpp:527-533].
`resetControllers()` clears all [cycle.cpp:153-157] and is called at **cycle.cpp:279 and :289** —
the foot of `interpretCycle`, after `artificialDelay_CycleDone()`, two sites. ★★★ **Our
`vm_reset_ctrl` is called at `vm_cycle.s:268` and `:272`, the same two structural positions.**
**§1.2's claim about the reset point is CONFIRMED, not assumed.**

**§4A(3) — `handleController`'s order.** ★★★★ **Controller bindings come FIRST and return true
before direction keys are considered:**

```
key == 0                        -> return false                      [keyboard.cpp:481]
ESC: platform-gated menu; PC falls through to the ESC controller     [:489-518]
MH1/MH2 ENTER->space quirk (game-specific)                           [:520-523]
for each controllerKeyMapping: keycode == key -> occurred=true; TRUE [:527-533]
int16 newDirection = 0;  ... direction keys ...                      [:535+]
```

**§4A(4) — the special codes.** `AGI_KEY_ESCAPE 0x1B`, `ENTER 0x0D`, `BACKSPACE 0x08` are ASCII;
**`UP 0x4800`, `LEFT 0x4B00`, `F1 0x3B00` … are `scancode << 8`** [keyboard.h:54-76]. ★★★★ **This
title screen uses both forms**, which is what fires the stop.

**§3(2) — `VM_CTRL`'s plumbing, checked rather than accepted** [§7's warning about §1.2].
`vmtest_controller` → `vm_ctrl_get` → `VM_CTRL`, a 32-byte packed array [vm_state.s:67, :396];
`vm_reset_ctrl` clears 32 bytes [vm_cycle.s:168]. ★★★ **Writers: none.** §1.2 is correct on every
point — **and it is correct about a mechanism this title screen does not wait on.**

**★★★★★ What the script actually polls** [new instrument]:

```
tests evaluated            total     late (>= cycle 120)
   isset                   23506    17907
   controller              11000     8382      <- 22 slots, every cycle
   said                     7500     5715
   equaln                   7045     5334
   have.key                  500      381      <- once per cycle
```

★★★★ **The 21 bindings are KQ1's global shortcuts** — F1-F10, Ctrl-C/E/R/S/X, TAB, `=`, `-`, `0`,
Alt+D, Alt+Z. **Installed once at cycle 1 by logic 0 and polled forever.** Several polled slots
(19, 22-25) are **never bound at all**, which is what a global handler looks like.

**★★★★★ The exit, measured.** `condHaveKey` is true iff `VM_VAR_KEY` is set, and **sets it when a
key arrives** [op_test.cpp:121-137]. Our `vmtest_have_key` is true iff VAR 19 is non-zero
[vm_tests.s:154-159], wired at `vm_tables.s:324`; the reference's `condHaveKey` is identical
[tests.py:126-135]. **So writing VAR 19 for one cycle IS a keypress on both sides** — and doing it
produced the table in §1.

**★★★★★ The port-side gap, and its stated reason has gone stale.**

```
p3b_probe.s:1269  "VM_VAR_KEY is NOT written here. cycle.cpp does set var 19, but the opcodes
                   that read it are not wired and writing it would be a side effect with no reader"
```

★★★★★ **`vmtest_have_key` IS the reader and IS wired.** The comment was true when written and is
false now. `vm_cycle.s:144` and `:347` clear VAR 19 every cycle, matching the oracle; **nothing
writes it.** ★★★ **That is §1.2's "every part green, the join missing" — the fifth instance the
dispatch itself counts — with a documented reason that expired** [the AD-28 / X-33 class: a note
describing how something ARRIVED, read as describing how it IS].

**§4E — the release pin.** ScummVM's auto-detect returns **two** entries for the pinned directory —
`(2.0F 1987-05-05 … DOS/English)` and `(CoCo3/English)` — and ran **DOS** [P6.69]. ★★ **Recorded;
the comparison procedure should name the variant.** No comparison was re-run.

### 4 — Verification (AC-by-AC)

- **AC-1 [citation · oracle]** ★★★★★ **Four answers above, quoted with file:line. (1) stopped the
  task**, exactly as the dispatch allowed for.
- **AC-2 … AC-6** ★★★ **NOT ATTEMPTED — stopped before §4B.** No `set.key` implementation, no
  controller raise, no arbitration table, no advance measurement on the target.
- **AC-4 [partial]** The arbitration ORDER is transcribed in §3 (§4A(3)) and is available for the
  re-scope; it was not turned into a three-consumer table because the third consumer was not built.
- **AC-7/AC-8 [byte-comparable · suite]** ★★ **Not re-run and not claimed** — no guest code
  changed, and `p3b_arms_check.ps1` reports **all 8 arms byte-identical to the recorded baseline**,
  which is the evidence that nothing could have moved.
- **AC-9 … AC-11** N/A — nothing implemented, nothing to re-baseline.
- **AC-12 [tooling]** `p3b_arms_check.ps1` 8/8 OK (above). The rest not re-run: no guest source,
  no `src/engine/`, no HAL and no generated table was touched.
- **AC-13** Candidate captured (§10).

### 5 — Verdict-time evidence (v0.7 §11)

```
25.1  python harness/tools/pic_order.py --cycles 400 --late 120 --watch draw,clear.lines,
        set.view,start.cycling,new.room,draw.pic,show.pic,display
      control:                 display 2  new.room 1  draw.pic 1  show.pic 1
                               (draw 0, set.view 0, clear.lines 0)
      --post-key 0x0D --post-at 200:
        ★ posted key $0D into VAR 19 at cycle 200
        draw 4   set.view 3   new.room 2   draw.pic 2   show.pic 2   clear.lines 1   display 2

      tests evaluated: isset 23506/17907, controller 11000/8382, said 7500/5715,
                       equaln 7045/5334, have.key 500/381
      ★ all 8 arms byte-identical to the recorded baseline (SHA256)
25.2  N/A -- no artifact changed.
25.3  N/A -- nothing to show Jay; the task stopped before any behaviour changed.
      ★★★ NOT "pending Jay": there is no build to gate [§4A.3 distinguishes these].
```

### 6 — Reactive deviations and route accounting

**None — that is the point.** §6's first trigger fired and §4B-§4D were not attempted.

★★★★ **I extended `pic_order.py` rather than stopping at the first citation**, because a stop that
says "blocked" is worth much less than one that says what is blocked and what is not. **That is
measurement, not repair, and it changed no guest byte.**

**ROUTE ACCOUNTING.** I proposed nothing beyond §4A. ★★★★★ **I did NOT implement the one-line fix
I identified** (writing VAR 19 from the key scan), although it is small and I am confident of it,
**because §8 forbids reshaping a dispatch silently and §6 told me to stop.** It is §8's first
follow-up, not something to slip in.

### 7 — Uncertainty flags

1. ★★★★★ **A correction I made mid-task, and it was my instrument's fault.** My first controller
   tracer reported *"controller(n): never tested"* — I rebound the module attribute and matched
   handler identity, but the dispatch table binds handlers from an impls dict, **so the wrapper
   never took effect and absence was indistinguishable from non-instrumentation.** I stated the
   premise was falsified on that basis; it was not. ★★★ **Corrected by wrapping each bound
   `t.handler` directly, which is what produced the 11,000/8,382 figures.** §2W, mine, again.
2. ★★★★ **`$0D` was posted; which key the game accepts is not established.** `have.key` is true for
   ANY non-zero VAR 19, so the advance is not evidence about a specific key.
3. ★★★ **The 22 polled controllers still need `set.key`** — they are the game's shortcuts and are
   real work. **The 16-bit representation gap is theirs, and it does not block the title screen.**
4. ★★ **Whether the port's `p3_poll_key` latch can supply VAR 19 at the right moment** (before the
   cycle's tests run, after `vm_cycle` clears it) is untested; the ordering is the same class as
   P6.61's key-to-direction join.

### 8 — Follow-up candidates

1. ★★★★★ **Write VAR 19 from the key scan** — the measured unblock, and the whole of Jay's three
   observations. ★★★ **Needs a ruling on ordering** (the clear at `vm_cycle.s:144/:347` versus the
   write) and on whether `p3_poll_key`'s latch or a new site owns it.
2. ★★★★ **Correct `p3b_probe.s:1269`'s stale note** — "the opcodes that read it are not wired" is
   false; `vmtest_have_key` reads it.
3. ★★★★ **`set.key` + the controller raise remain worth doing** for the shortcut table, **with a
   ruling on the 16-bit gap**: ASCII-only bindings (TAB, `=`, `-`, `0`, Ctrl-letters) are reachable
   today; F-keys and Alt-keys need a CoCo→PC-scancode mapping that does not exist.
4. ★★★ **Pin the game release in the comparison procedure** [§4E].
5. ★★ Carried: `draw`/`set.view`/`start.cycling` for the alligators (**now known to be reachable —
   the script issues them once the screen advances**) · the flags' blink · the picture leaving the
   logic arena · `configure.screen`'s render offset.

### 9 — User interaction during task
None during this task. It descends from Jay's three observations recorded in P6.69 §9.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-20-the-reason-not-to-do-it-expired-before-the-code-did.md`

### 11 — Commit
(recorded below; pushed to origin/wip before this report was surfaced)
