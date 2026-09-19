## Form B Report — T-P0-101 / P6.46 — The cause: the AC-5 opcode counters write into the residency arena
**Class:** measurement.  wip.  **§6 STOP — the cause is named, demonstrated in both directions, and no fix attempted.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-19 10:40 (HEAD 10899bf, wip). Two `src/harness/` files, publish-only behind a flag; two
harness tools changed, three added.

### 1 — Summary

★★★★★ **Neither of AC-3's two defects. The guard reads the right flag AND takes the right arm —
the instruction it lands on has been overwritten.**

`VM_OPSEEN` (`$6400`) and `VM_TESTSEEN` (`$6300`) — the AC-5 coverage counters — sit **inside
`MAP_ARENA_WIN` (`$6000`–`$A000`)** in `p3b`'s memory map. Every dispatched opcode increments a byte
of whatever resource the arena has mapped there. **Kingquest1's LOGIC 102 loads at `$63F2`**, so its
`goto 0908` at offset `$0010` lands on `VM_OPSEEN+2` and is incremented once per execution of command
opcode `$02`.

```
file   $0010  FE F5 08      goto 0908
port   $0010  66 AA 63      (cycle 100)      9E 45 30   (cycle 50)
```

★★★★★ **So the port never leaves logic 102**, and runs 2,300 bytes the reference jumps over — which
is P6.45's finding, with its cause.

★★★★★ **Demonstrated by ablation, not by address arithmetic.** `-DVM_NOCOUNT` removes both counters
and nothing else: **28 bytes, and the restart is gone.**

| `-Fault`, 400 cycles, room jump at 8 | rooms | err |
|---|---|---|
| counters IN, 15,382 B | `c0->0 c1->83 c9->1` **`c100->0 c101->83`** | **1** |
| counters OUT, 15,354 B | `c0->0 c1->83 c9->1` — ends in room 1, 4 sprites | **0** |

### 2 — Files modified
- `src/harness/vm_core.s` — `-DVM_IFDIAG`: every `if` in one logic in one cycle, the flags it saw,
  the arm it took, the six bytes at the address it chose, and a 256-byte snapshot of the port's own
  copy. **+1,023 bytes in the diagnostic arm; 0 in every shipped one.**
- `src/harness/vm_tests.s` — the `said()` recorder widened to 48 rows and given a **logic column**.
- `harness/tools/p3b_run.lua` — `P3B_IFLOGIC`, the arming, the readout.
- `harness/tools/p3b_show.ps1` — `-IfDiag` and `-NoCount`.
- `harness/tools/p3b_arms_check.ps1` — **new.** Rebuilds the seven p3b arms and compares bytes.
- `harness/tools/logic_bytes.py` — **new.** Hex-dumps a LOGIC's bytecode beside its decode.
- `harness/tools/logic_copy_diff.py` — **new.** Diffs the port's resident copy against the file.

### 3 — Pre-dispatch grep (C-13)

**§3(2) first, as the dispatch directs.** ★★★ **`VM_FAULT_SAID_PURE` is undefined in every arm run.**
It appears in exactly two live places: `vm_run.ps1:95`, behind an environment variable, on the **VM**
probe's runner — which this task never invokes — and `vm_tests.s:267` as the `ifndef` it gates. **No
p3b arm passes it**, and the four diagnostic arms in `p3b_show.ps1` spell their flags out in full.

**§3(1)** Seven shipped artifacts at P6.40's hashes ✔ (and see §7.1). Untracked: one file.

**§3(3)** The port's `if` is `vm_core.s:252`'s `vm_rl_if` → `vm_test_if_code`. The branch word is
consumed at `vm_tic_end:434-453`: **true steps over the 16-bit skip, false adds it** — the polarity
P6.42 established from `op_test.cpp:509-513`, unchanged.

**§3(4)** The P6.44/P6.45 stack map was re-read before editing. **It did not apply**: this recorder
hooks the evaluator, not `vm_setvar`, and reads globals rather than stack slots.

### 4A — ★★★★★ Flag 4 at `$000A`, measured

Kingquest1, `-IfDiag -Headless -WithInput -Cycles 400`, `P3B_ROOM=1`, `P3B_SAIDAT=100`,
`P3B_IFLOGIC=102`:

```
if @expr $0001  flags0=$14  flag2=1 flag4=1  result=0  ip_after=$000A  [FF 07 04 FF 03 00]  not taken
if @expr $000B  flags0=$14  flag2=1 flag4=1  result=1  ip_after=$0010  [66 AA 63 FF 07 02]  TAKEN
if @expr $001D  flags0=$14  flag2=1 flag4=1  result=0  ip_after=$0025  [59 01 09 02 FF 02]  not taken
```

- **AC-1: flag 4 at `$000A` is 1.** The guard **was** evaluated, the expression was **True**, and the
  port fell into the block at `$0010` — ★★★★ **the same arm the reference takes** [P6.45 §4C: `EXPR
  $000B` True].
- ★★★★★ **AC-3 is therefore NEITHER.** The port did not fail to set the flag, and it did not take the
  wrong arm. **Both of the dispatch's branches are false**, and §4A(2) is why.

**§4A(2) — the row that broke the case open.** A **third** expression at `$001D`. The file says
`$0010` is `goto 0908`; taking it lands the port at `$0908` and the next `if` would be there.
`$001D` is nine bytes further **down**, and the `if` at `$0013` between them was never evaluated.
★★★★ **So the port did not execute the goto**, and the six bytes at the address it chose say why:
**`66 AA 63`, where the game file has `FE F5 08`.**

### 4B — The `said()` table, uncapped through logic 102

27 rows (P6.43's 16 ended inside logic 1): **12 in logic 0, 12 in logic 1, 3 in logic 101, and none
in logic 102** — the module exits before its chain. `flag4_on_entry` is 0 for the three rows before
the match at `$01FF` and **1 for every row after it**, logic 102's guard included.

★★★ **So P6.45 §7.1's first hypothesis is dead**: flag 4 was not clear at the guard and set later by
logic 102's own `said()`s. It was already 1, set by the match in logic 0, exactly as intended.

★★ **The logic column is not decoration.** P6.43 attributed rows by ip order; this run re-enters
logic 0 and visits three modules, and the ordering would have mis-assigned them.

### 4C — ★★★★★ The port's copy of logic 102, against the file

`logic_copy_diff.py`, 256 bytes, **two cycles**:

```
offset   file   port @c50   port @c100   delta over 50 cycles
$0010     FE       9E           66             +0xC8  = 4/cycle
$0011     F5       45           AA             +0x65  = 2/cycle
$0012     08       30           63             +0x33  = 1/cycle
$001B     00       50           B4             +0x64  = 2/cycle
$0024     19       69           CD             +0x64  = 2/cycle
$0025     FF       27           59             +0x32  = 1/cycle
$0035     65       B5           19             +0x64  = 2/cycle
$0054     07       2F           61             +0x32  = 1/cycle
```

★★★★★ **Eight offsets, the same eight at both cycles, and the values ADVANCE at whole numbers per
cycle.** That is not corruption — **it is a histogram.** Offsets `$0000`–`$000F` are clean, every
byte between the eight is clean, and **logic 0 (`$7CDB`) and logic 101 (`$72DB`) are clean at 0 of
256.**

**The arithmetic that names it:** the copy is at **`$63F2`**, so offset `$0010` is address **`$6402`**
and `VM_OPSEEN` is **`$6400`** — ★★★★★ **offset `$0010` is the execution count of command opcode
`$02`**, and all eight offsets are `VM_OPSEEN + <an opcode the run executes>`. Offsets `$0000`–`$000F`
fall in `VM_TESTSEEN+$F2..$FF`, **test opcodes that do not exist** (`VMTEST_MAX` is 20), which is why
they are clean.

### 4D — Why it is p3b's defect and not the VM gate's

`vm_state.s:64-70` wraps `VM_VARS`/`VM_FLAGS`/`VM_CTRL`/`VM_OBJROOMS`/`VM_OBJ` in `ifndef VM_VARS` so
a probe can relocate them — and `p3b` does, to `$0800`/`$0900` via `memmap.inc`. ★★★★★ **`VM_OPSEEN`
and `VM_TESTSEEN` at `:90` and `:93` are OUTSIDE that guard.** They are nailed to `$6300`/`$6400`,
which is `vm_probe`'s free space (its `RES_ARENA` starts at `$6B00`) and **`p3b`'s arena window**.

★★★★ **`vm_probe.s:608-620` asserts exactly this class of collision — three `ifgt`/`error` pairs
naming `vmtr_buf` and `RES_ARENA`.** `p3b_probe.s` names neither counter anywhere. ★★★ **This file's
own header already carries the lesson**: *"An assertion that names one of four neighbours reports
conformance for the other three"* [`vm_state.s:53`] — and the instance it was written for was
`VM_OPSEEN` colliding with the code image. **Same two symbols, same class, a different neighbour.**

★★ **The nine-title VM gate is unaffected**, and its 9/9 is not evidence about `p3b`: the collision
does not exist in that map.

### 5 — Verdict-time evidence (v0.7 §11)
```
p3b        13918 B 58AD3C27  p3b_text  16258 B 5B19334F  p3b_win3  16258 B 5400A30F
p3b_notick 16255 B F7AE0FCF  p3b_nomap 16255 B 9604AAAA  p3b_fault 15382 B 16DC35EF
p3b_flat   15367 B E7882A33          -- all seven, REBUILT, byte-identical
p3b_ifdiag 16405 B BEC485F8          -- the diagnostic arm, +1,023 B over p3b_fault

p3b_arms_check.ps1 -SelfTest : p3b 13890 B BB7C7378 MOVED (-DVM_NOCOUNT) -- the checker goes red
git diff --stat -- src/ : vm_core.s | 149 ++++  vm_tests.s | 20 ++  (publish only, all guarded)
[reg-discipline] 17 in 1 file over 4 registers      fix_mojibake --check: 7 files clean
```
**25.2:** N/A. **25.3:** N/A — no shipped artifact changed, nothing for the eye to gate.
★★ **AC-7 by §2T citation to P6.40** — AC-5 holds, so the suite's inputs are unchanged.

### 6 — Reactive deviations and route accounting

1. ★★★★★ **THE SCENARIO WAS MISSING AND THE FIRST THREE RUNS MEASURED THE WRONG THING.** The
   restart needs `P3B_ROOM=1`, and the first `-IfDiag` run did not set it: **the port matched the
   reference exactly, in an arm that does not diverge.** Two more arms were built chasing a
   suppression that was never there, and the plain `-Fault` arm — **byte-identical to the shipped
   artifact** — was the one that settled it by also not restarting. ★★★★ **`P3B_ROOM` is part of the
   instrument and is recorded in no gate row** [§8.3].
2. ★★★★★ **THE BYTE-IDENTITY CHECKER REPORTED ALL SEVEN ARMS MOVED, AND WAS WRONG** — see §7.1.
3. ★★★★ **The hooks were moved after the first build FAILED.** Six bytes at `vm_rl_if` pushed
   `beq vm_rl_return` (`vm_core.s:116`) past its reach. They now sit inside the evaluator, **after
   `vm_rl_return`**, so no short branch in the dispatch loop spans a guarded block.
4. ★★★ **The recorder grew twice**, each time to answer the row the previous one raised: six bytes at
   `ip_after`, then the 256-byte snapshot. **Neither was speculative** — the first was forced by an
   `ip_after` that could not be reconciled with the file, the second by eight damaged bytes whose
   pattern needed more than eight samples.
5. ★★ **One instrument was NOT built**: nothing reads the arena's allocation to say *why* logic 102
   lands at `$63F2`. **That is the next task's, and it is a placement question, not a VM one.**
6. **ROUTE ACCOUNTING.** §4A, §4B, §4C and §4D are answered. **AC-4 was not followed** — it selects
   between two branches and the measurement rejected both. **No fix attempted** (§6 stop).

### 7 — Uncertainty flags

**7.1 ★★★★★ THE BYTE-IDENTITY BASELINE IS A TRUNCATED SHA256, AND NO FILE RECORDED THAT.** Every
p3b hash this project has published is a `Get-FileHash` **default** cut to 32 hex — **exactly the
width of a full MD5.** The first `p3b_arms_check.ps1` used MD5 and reported **all seven arms moved**
after a `src/` edit, which is a plausible story with a plausible cause. ★★★★ **What killed it was
that all seven SIZES matched to the byte** — a guarded block that emitted code cannot leave seven
binaries the same length — **and then building `p3b` at `670fea4`, the commit that published the
baseline, reproduced the same supposedly-wrong bytes.** ★★★ **The algorithm is part of the baseline**
and is now recorded in the script, which also has a `-SelfTest` that makes its red reproducible.

**7.2 ★★★★ The exact placement rule is not measured.** Logic 102 lands at `$63F2` in this run; what
decides that, and which other resources can land on `$6300`–`$64FF`, is unmeasured. ★★★ **So the
blast radius is unknown**: every resource that has ever occupied those 512 bytes in any run has been
silently incremented, and **no gate looks at resource bytes after a bind.**

**7.3 ★★★ This may be the whole of P6.39's "absent in the CEL build".** A different arena occupancy
puts a different resource under the counters — which would make seven tasks of build-bisection a
measurement of *which resource landed at `$6300`*, not of any build flag. **Not yet checked.**

**7.4 ★★ `memmap.inc`'s flag-packing comment is still stale**; `gates.manifest` still does not record
the sampling seam [P6.42], **fourth task carrying it**, and now also does not record `P3B_ROOM` as
part of the restart scenario (§6.1).

### 8 — Follow-up candidates
1. ★★★★★ **Move `VM_OPSEEN`/`VM_TESTSEEN` inside `vm_state.s`'s `ifndef`, give `p3b` a home for them
   in `memmap.inc`, and port `vm_probe.s:608-620`'s adjacency assertions into `p3b_probe.s`.** The
   assertions are the half that stops it recurring.
2. ★★★★ **Then re-run the restart scenario.** If it is gone, six tasks of divergence hunting close
   with it; if it is not, what remains is a real VM divergence for the first time.
3. ★★★★ **Ask what else has been writing into the arena window**, and add a bind-time checksum so a
   resource that changes under the interpreter is caught by a gate rather than by a report.
4. ★★★ **Re-read P6.39's build bisection against §7.3.**
5. ★★ `gates.manifest`'s seam note and `P3B_ROOM` (§7.4) · `memmap.inc`'s packing comment.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-19-the-instrument-was-writing-into-the-evidence.md`
- `seeds/AGI/live/2026-09-19-a-truncated-hash-is-indistinguishable-from-a-different-one.md`

### 11 — Commit
`ccdd3fe` (pushed to origin/wip before this report).
