## Form B Report — T-P0-096 / P6.41 — The state diff: identical to cycle 99, divergent at 100
**Class:** measurement.  wip.  **No `src/` change.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-13 14:00 (HEAD 1f53433, wip). Two harness tools modified, one added. `git diff --stat --
src/` is **empty**.

### 1 — Summary
★★★★★ **Cycles 95-99 are byte-identical — all 288 bytes — against BOTH the reference and the
non-restarting port.** The first byte to differ is at **cycle 100**, the fed cycle, in the same
sample as the room change.

★★★★★ **The first divergence, named:**
```
port c100 vs oracle c100 :  1 flag, 4 vars
      flag 2    oracle=1  port=0      <- VM_FLAG_ENTERED_CLI
      var  0    oracle=1  port=0      <- VAR_CURRENT_ROOM
      var 10    oracle=2  port=4      <- VAR_TIME_DELAY
      var 11    oracle=10 port=9
      var 88    oracle=2  port=4      <- the game's speed shadow
```

★★★★★ **§4C's intersection lands exactly.** `var 88` and `var 10` are written by
`assignn(v88,N) / assignv(v10,v88)` blocks in logic 0 at `01F6`-`020B`, and **every one of those
blocks is guarded by a `said()`** — which is gated on flag 2. **The flag that differs is the gate on
the tests that write the variables that differ.**

★★★★ **`restart.game()` is in logic 0 at `023A`**, on the same fall-through chain, and the
trajectory `c100→0 · c101→83` is what it plus logic 0's own `new.room(83)` produces.

### 2 — Files modified
- `harness/tools/state_diff.py` — **new.** The 288-byte diff, by name, with evidence-chosen alignment.
- `harness/tools/p3b_run.lua` — `P3B_STATEDUMP`; `vm_restart` and live `res_err` published; §4D(1).
- `harness/tools/p3b_show.ps1` — `vm_restart` in the symbol list.

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| the seven artifacts | P6.40's hashes, incl. `p3b_flat` `E7882A33…` | ✔ |
| untracked | one file | ✔ `coco_agi.code-workspace` |

**§3(2) the state block:** `MAP_VM_VARS $0800` (256 vars) and `MAP_VM_FLAGS $0900`.
★★★★ **memmap.inc's comment on that line — *"256 flags, 1 byte each (not packed)"* — is STALE.**
Both probes store flags **packed**, 32 bytes: `vm_sweep.lua:714` reads 32 bytes and `p3b_run.lua`
tests flag 5 as bit 5 of byte 0. **The vm gate passes 9/9 with that packing**, so the storage is
packed and the comment describes an intent that was not taken. Reported, not edited [§2D].

**§3(3)** `vm_stage.py` emits the reference's state as one 288-byte record per cycle for the whole
run; there is no cycle-range option and none was needed.

### 4A — The samples

`p3b_text`'s modelled arm, Kingquest1, the jump, the eye gate's own script, `P3B_STATEDUMP=95-105`.
**Eleven records of 288 bytes, read from `VM_FLAGS`/`VM_VARS` by the host.** ★★★ **No `src/`
change: the addresses are in `memmap.inc` and the host reads memory freely.**

### 4B — The diff, and the alignment

★★★★★ **The alignment was chosen on evidence and it turned out not to matter.** `--scan` totals the
differing bytes at offsets −3..+3:

| offset | −3 | −2 | −1 | 0 | +1 | +2 | +3 |
|---|---|---|---|---|---|---|---|
| differing bytes | 67 | 68 | 69 | 73 | 73 | 77 | 81 |

★★★★ **Flat.** A timer-skew misalignment lights up dozens of bytes and produces a sharp minimum;
this varies by 20% across seven offsets. **The differing bytes are not counters**, so the one-park
seam difference [§1.2] does not confound this diff. Offset 0 is reported.

**The first cycle at which any byte differs is 100.** Cycles 95, 96, 97, 98 and 99 are identical on
all 288 bytes. From 101 onward the two diverge broadly (3 flags, 10-13 vars) as the restarted game
re-runs its intro.

★★★★★ **And the same diff against `vm_probe`'s `guest.bin` — a PORT, sampled at a park exactly as
p3b is — is byte-for-byte the same result.** That removes the sample-point question: it is not that
the reference records at a different moment in the cycle. **Both probes call
`pace → feed → interpret → post_cycle` and both are read at the park** [vm_probe.s:451-452,
p3b_probe.s:919-920].

### 4C — What logic 0 tests, and the intersection

```
01D8  if (|| said(160) controller(22) ||) goto +6
01E4  assignn(v88, 0)        01E7  assignv(v10, v88)
01EA  if (|| said(159) controller(23) ||) goto +6
01F6  assignn(v88, 2)        01F9  assignv(v10, v88)
01FC  if (|| said(161) controller(24) ||) goto +6
0208  assignn(v88, 4)        020B  assignv(v10, v88)
020E  if (|| said(44)  controller(6)  ||) goto +3      021B  quit(0)
021D  if (|| said(147,146) controller(2) ||) goto +1   022B  restore.game()
022C  if (|| said(31,146) controller(3) ||) goto +1    023A  restart.game()
```
Also in logic 0: `0023 new.room(1)`, `0095 new.room(83)`.

★★★★★ **The intersection is total.** The differing `var 88` and `var 10` are written **only** by
those three `assignn/assignv` pairs; each pair is guarded by a `said()`; `said()` is gated on
**flag 2**, which is the flag that differs. **Port and reference took different branches in that
chain, and the chain ends at `restart.game()`.**

★★★ **The eye script feeds "slow" (word 161) at cycle 100 and "fast" (word 160) at 200** — these are
the speed commands, which is why `VAR_TIME_DELAY` is the variable that moved.

★★ **The branch polarity is NOT asserted here.** The disassembler prints `goto +N` and I did not
verify whether it is the true or the false arm. **Which side matched and which fell through is the
next task's first question**, and stating it from a convention I have not checked would be the
twelfth wrong premise.

### 4D — Two instrument repairs, both made

1. ★★★★ **The `par_vocab` tap's captured `n`** — the same closure bug: `stage()` is defined above
   `local n`, so the tap bound a non-existent global and stored nil. **It fires only on the stall
   path**, which is exactly where a nil would kill the frame callback and take the whole stall dump
   with it. Now read from `P3_CYCLE`.
2. ★★★ **`vm_restart` and the LIVE `res_err` are published** beside the sticky `P3_ERR`.

### 5 — Verdict-time evidence (v0.7 §11)
```
git diff --stat -- src/ :  (empty)
p3b       13918 B  58AD3C27164BD63F     p3b_text  16258 B  5B19334FAD8E7AB0
★ source integrity: clean

port c95..c99  vs oracle : ★ identical, all 288 bytes   (five cycles)
port c100      vs oracle : flag 2, var 0, var 10, var 11, var 88
port c100      vs vm_probe guest.bin : the SAME five bytes
alignment scan: 67/68/69/73/73/77/81 over offsets -3..+3 -- flat
```
**25.2:** N/A. **25.3:** N/A — nothing shipped changed.
★★★ **AC-7 by §2T citation to P6.40:** no `src/` file touched, both sampled artifacts reassemble to
P6.40's hashes, toolchain unchanged.

### 6 — Reactive deviations and route accounting
1. ★★★ **`state_diff.py` takes a DIRECTORY, not a glob.** This build of Python on Windows expands
   wildcards in `argv` itself, so a quoted glob arrived as eleven arguments and argparse rejected
   ten. Neither quoting nor PowerShell's stop-parsing token helps; the expansion is inside the
   interpreter. The pattern lives in the tool.
2. ★★ **The diff was run against `vm_probe` as well as the reference**, which §6's third trigger
   sanctions. It was not needed as a fallback — both were available — and it is what rules out a
   sample-point explanation.
3. **ROUTE ACCOUNTING.** §4A, §4B, §4C and §4D are all as specified. **No fix was attempted.**

### 7 — Uncertainty flags

**7.1 ★★★★★ P6.39's "`restart.game` did not execute" was MY error and it was read from bytes that
cannot answer it.** I wrote *"`vm_quit` is 0 and `vm_badop` is 0 in every restarting arm, so
`restart.game` did not execute"*. **`vm_probe.s:440-443` says in as many words that
`restart.game` sets `vm_restart`, and that "badop stays 0 for both, so the byte is the only
discriminator."** The conclusion was drawn from two bytes that are 0 either way.

★★★★ **And the correction does not settle it either.** `vm_restart` reads **0** at the end of this
run — but a restart re-initialises VM state, so an end-of-run read cannot distinguish "never fired"
from "fired and was reset". **That is the same sticky-versus-live trap I named last task, and I
walked into its mirror image.** Settling it needs a sample at cycle 100, not at cycle 400.

**7.2 ★★★ Flag 2's direction is measured; its cause is not.** `ENTERED_CLI` is clear in the port and
set in both the reference and `vm_probe` at the end of cycle 100. All three call `vm_post_cycle`,
which clears it. **Why two implementations that clear the same flag at the same seam disagree about
it is unexplained**, and it is the first thing the next task should read — mid-cycle, not at the park.

**7.3 ★★ `memmap.inc`'s flag-packing comment is stale** (§3(2)). Not edited [§2D]; proposed text is
that the 256 flags are stored **packed in 32 bytes** and that `MAP_VM_FLAGS`'s remaining 224 bytes
are unallocated.

**7.4 ★ The branch polarity of `goto +N`** is unverified (§4C).

### 8 — Follow-up candidates
1. ★★★★★ **Sample flag 2 MID-CYCLE at cycle 100** — between the feed and `vm_post_cycle`, and again
   after. That distinguishes "the feed never set it" from "something cleared it early", and it is
   the whole remaining question.
2. ★★★★ **Verify the `goto +N` polarity** (§7.4), then say which side matched.
3. ★★★★ **Sample `vm_restart` at cycle 100** (§7.1).
4. ★★ **`memmap.inc`'s stale packing comment** (§7.3). ★★ **`RES_E_BIG`'s identity.**
5. ★ **`VM_ROOM` in the gate rows** — still queued; the passthrough exists and no row uses it.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-13-the-byte-that-cannot-answer-the-question.md`

### 11 — Commit
`682abaa` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `1c58c99`, one row under `seeds/AGI/live/`.
★★ The pool commit was amended: the first attempt's subject carried a **BOM**, because I wrote the
message with PowerShell's `Set-Content -Encoding utf8` — **the exact mechanism §2J.5 bans**, in the
one place the mojibake gate cannot see (a commit message is not a tracked file).
