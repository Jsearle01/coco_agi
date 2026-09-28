## Form B Report — Spike S-06 — How many instructions do they spend, per pixel and per opcode?
**Class:** recon (spike). wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-27 20:35:22 (HEAD `0800fac`, wip). `git status`: `harness/tools/sierra_trace.lua` modified
(the new gate), plus an untracked `coco_agi.code-workspace` that is not this task's.
★★★★★ **AC-6: zero files changed under `src/`** — verified by `git status --porcelain src/`.

★★★★★ **SCENE, stated once and carried on every figure below** [§7]: **King's Quest III, Sierra's own
1988 CoCo3 AGI interpreter under OS-9, the chicken pen, ego standing still, animals cycling.** Three
6-frame captures at t=169.68 / 169.82 / 170.03 s, armed after **3,814–3,835 frames (~64 s) of disk
silence.** Figures below are from the middle capture (`fill2.tr`, 40,538 instructions) unless said.

★★★★ **UNITS** [§1.1a, Jay's constraint]: every cross-machine figure is in **absolute CPU cycles or
instructions.** No percentage in this report is set beside another machine's percentage, and each
within-machine share says whose stream it is a share of.

---

### 1 — Summary

★★★★★ **The verdict splits, and the numbers force the split rather than my reluctance to choose.**

- ★★★★★ **The BLIT is ARCHITECTURE.** Their inner loop is **six instructions, 24 CPU cycles per byte
  written**, and **it contains no transparency test and no priority test at all** — a 16-entry table
  turns a 4-bit source value straight into a finished screen byte. Ours spends **~144 CPU cycles per
  pixel tested.** The per-pixel decision is not cheaper on their side; **it is not in the per-pixel
  path.**
- ★★★★★ **The INTERPRETER is TECHNIQUE.** Their evaluator is **structurally the same program as
  ours** — the same `$FC` OR marker, the same NOT, the same AND/OR modes, one call per dispatch — and
  it runs **≈35 instructions per opcode** against our **450 CPU cycles** (≈128 instructions at ~3.5
  cycles each, a conversion that is **mine and derived**).

★★★★ **AC-3a: their VM cycle is NOT measured**, so the interpreter comparison is **instructions per
dispatch**, which §6 sanctions and which needs no cycle boundary.

---

### 2 — Files modified

- `harness/tools/sierra_trace.lua` — a **steady-animation gate** (`SIERRA_GATE=steady`) and an
  **operator trigger** (`SIERRA_TRIGGER`). The proven fill gate is the default and is untouched.
- `reports/` — this report.
- ★★★★★ **Nothing under `src/`** [AC-6].

Scratchpad only, not committed: `traceform.lua` (§4A's form check) and `region.py` (§4C's range
reader).

---

### 3 — Reasoning

#### 3.1 ★★★★★ §1.1's correction, recorded so the next reader does not inherit the wrong line

**This project has traced Sierra's executing code since P3.9, at Jay's direction.** The tools are in
the tree — `sierra_trace.lua`, `sierra_readtrace.py`, `sierra_caller.lua`, `sierra_fill.lua` — and
Jay's own ruling is in `sierra_caller.lua`'s header: *"does it really matter what is in the buffer if
you can determine the code that puts it there? you can deduce what is going there from the code."*

★★★ **The spikes' "what address, how often, never what instruction" was S-01's boundary for a
DISPLAY-TIMING question**, and generalising it over a boundary settled a hundred tasks earlier was the
error. ★★ **The line this task held instead** is the one §1.2 and §6 draw: **measure costs and loop
geometry; do not transcribe their implementation.** No routine of theirs is reproduced in the repo;
what is recorded is instruction counts, cycle counts, region sizes and one sentence per half.

#### 3.2 §3(1) — what had rotted, and it was almost nothing

★★★★ **§3(1)'s "expect to repair them; that is the first cost" did not hold.** Verified by running
P3.10's own pre-build check on a plain boot, no operator, no repo change [`traceform.lua`]:

```
MAME 0.281
debugger present; execution_state=run
screens: [":screen"]=OK  :at(1)=OK
trace lines: 25033
  4187: STS    $6,Y
  418A: LEAY   $8,Y
  418C: CMPY   $5F02
```

★★★ **25,033 lines of real disassembly.** P3.10 got 1,013 on its check; more here because `noloop`
is on and the boot phase differs. ★★ **Both screen API forms resolve**, so my own suspicion that
`m.screens:at(1)` had been removed was wrong and is recorded as wrong.

★★★ **The one genuine rot:** `sierra_trace.lua:31` hardcodes a **different session's** scratchpad
UUID as `TRDIR`. `SIERRA_TRACE` overrides it, so nothing needed editing to run.

#### 3.3 ★★★★★ §3(2) is wrong about the gate, and the file says so in capitals

**The dispatch says the gate arms on a disk burst ending. It does not.** `sierra_trace.lua:310-320`:

> *"THE GATE, third cut: **THE DISK IS NOT THE TRIGGER AT ALL.** Cut 1 keyed on 'first disk burst >=
> 2000' and caught the GAME LOAD (51,409 accesses)… Cut 3 keyed on 'the instant the disk goes quiet'
> and burned all three captures inside half a second of the game LOADING, on three short bursts,
> screen writes 0. Every one of those was a proxy. The fill has a DIRECT signature… a sequential run
> of a FULL SCREEN ROW. PC_AT_RUN is 128… **the cel blitter tops out at 11.**"*

★★★★★ **So the fill/blit discriminator was already measured in this file — fill 159-byte runs, blitter
4-byte strips with maxrun 11 — and §4B's re-aim is that test inverted.** The steady gate arms on a
maxrun in the blitter's band (3–16) with **no** full-row run, the disk quiet, the screen being
written, and the GIME in graphics mode.

★★★★★ **AND MY FIRST STEADY GATE REPEATED CUT 3's DEFECT.** It fired at t=53.3 / 53.5 / 60.1 s,
wherever the game happened to be, burning all three captures before the operator had gone anywhere.
**Jay caught it before I analysed them:** *"i wasn't at the chicken pen"*, then *"it going to fire at
the same point it did last time"*.

★★★★ **The fix is an OPERATOR TRIGGER, not a better proxy** — a file the gate polls, created when the
operator is standing where they want measured. ★★★ **It is not an input path:** the audit line
`grep "set_value\|:post\|natkeyboard"` still returns **0 non-comment hits**, verified. A file read is
the operator talking to the host, not to the guest.

★★★ **§2W: the gate was shown to arm, on the right signature.** All three pen captures armed at
**maxrun 11** after ~64 s of disk silence.

#### 3.4 ★★★★★ §4B — the blit, and what is not in the loop

**`$E1A7–$E1C0`, 26 bytes, 8.0% of `fill2.tr`'s instruction stream, 524 stores.** The inner loop, 470
iterations, with 6809 cycle costs — ★★ **the cycle figures are mine, from the instruction set:**

| | | cycles |
|---|---|---|
| `$E1A9` | `LDA ,X+` | 6 |
| `$E1AB` | `ANDA #$0F` | 2 |
| `$E1AD` | `LDA A,U` | 5 |
| `$E1AF` | `STA ,Y+` | 6 |
| `$E1B1` | `DECB` | 2 |
| `$E1B2` | `BNE $E1A9` | 3 |
| | **per byte written** | **24** |

★★★★★ **AGAINST OURS: ~144 CPU cycles per pixel tested.** ★★★ Both absolute, both per unit of
per-pixel work [§1.1a].

★★★★★ **WHAT THE LOOP DOES NOT CONTAIN IS THE FINDING.** No transparency compare, no priority
compare, no plane read. `LDA A,U` is a **16-entry lookup** — mask four bits, translate, store. At 160
bytes a row for 320 pixels one byte is two pixels, so **the table also does the horizontal doubling
and the packing**, in the same 5 cycles.

★★★★ **A second bulk path, `$E98A–$E998`** (24 B, 7.1%, 830 stores), is a **16-bit block copy**:
`LDD ,U++ / STD ,X++ / CMPX <$AF / BCS` ≈ 24 cycles for **two** bytes = **12 cycles per byte**. Its
setup at `$E974` computes the destination with `LDA #$A0 / MUL` — ★★★ **their stride is 160 bytes a
row, the same as ours** [our `HAL_gfx_cur_stride`, hal.inc:463].

**AC-2's store cross-check** [§6, the instrument that caught P3.9's error]:

```
store instructions executed : 5197  (12.8% of THIS TRACE's instruction stream)
   hottest STORE sites:  $E994 512 STD ,X++ | $E1AF 470 STA ,Y+ | $8D8D 278 STX <$6C
```

★★★ **A traced routine that does not write cannot be the blit. This one writes**, and the two hottest
store sites are the two bulk paths above.

#### 3.5 ★★★★★ §4C — the interpreter, and it is our own program

**`$C76F–$C7D6`, 104 bytes, 52 distinct instructions, 18.6% of `fill2.tr`'s stream, 744 stores, 344
entries at 22.0 instructions per entry.** The structure, from the trace:

```
$C76F  LDB ,Y+ / TSTB / CMPB #$FF / CMPB #$FE      fetch, then marker checks
$C780  LEAY D,Y            ★ the whole operand skip, ONE instruction
$C784  LBSR $84A1          ★ command dispatch, ONE call            x24
$C792  LDA ,Y+ / CMPA #$FC / BHI / BNE            the $FC OR marker -- ours tests the same value
$C79A  LDA ,S / BNE / INC ,S                      OR state, ON THE STACK
$C7AA  CMPA #$FD → LDA $1,S / EORA #$01 / STA $1,S   NOT, ON THE STACK
$C7B6  LBSR $8D8B          ★ test dispatch, ONE call               x278
$C7B9  EORA $1,S / CLR $1,S / TSTA                apply NOT, clear it
$C7C0  LDA ,S / BNE $C792                         AND mode continues
```

★★★★★ **This is structurally our interpreter.** The same markers, the same NOT-by-EOR, the same
AND/OR modes, one call per dispatch.

**Measured in the window:** 278 test dispatches + 24 command dispatches = **302 opcodes**. The test
dispatcher `$8D8B–$8D9D` is **19 bytes, 2,780 instructions over 278 calls = 10 instructions per
dispatch.** With the evaluator's 25, that is **≈35 instructions per opcode.**

★★★★★ **AGAINST OURS: 450 CPU cycles per opcode** [P6.103, castle]. ★★★ At a 6809's ~3.5 cycles per
instruction that is **≈128 instructions** — ★★ **and that conversion is derived, not measured** [§8].

★★★★★ **THE THREE DIFFERENCES, NAMED, in the order they cost us:**

1. ★★★★★ **Their expression state is two bytes ON THE STACK, manipulated in place** — `LDA ,S`,
   `INC ,S`, `CLR $1,S`, `EORA $1,S`, 4–6 cycles each. **Ours calls `vm_getflag`/`vm_setflag`**, and
   T-P0-161 measured **235.1 accessor calls a cycle at ~45–73 cycles a call.**
2. ★★★★ **`LEAY D,Y` skips an operand in one instruction.** Ours calls `vm_skip_instruction`, which
   indexes `VMTEST_ARGS` — and T-P0-161 measured the skip walk at ~9.8% of our `interpret` stage.
3. ★★★ **`LBSR` straight to a 19-byte dispatcher.** Ours builds a 16-bit table index first —
   `tfr/clra/aslb/rola/leax d,x/ldx ,x`, ~35 cycles — before `jsr ,x` [P6.106 §3.6].

#### 3.6 §4B.1 — the shape

★★★ **Eight hot regions hold the bulk of `fill2.tr`.** Shares below are **of that trace's instruction
stream and of nothing else** [§1.1a]:

| region | bytes | instr | share of THIS TRACE | stores |
|---|---|---|---|---|
| `$C76F-$C7D6` interpreter evaluator | 104 | 7,554 | 18.6% | 744 |
| `$E75F-$E799` unidentified | 59 | 4,278 | 10.6% | 544 |
| `$E1A7-$E1C0` **the blit** | 26 | 3,237 | 8.0% | 524 |
| `$E98A-$E9A1` **16-bit block copy** | 24 | 2,896 | 7.1% | 830 |
| `$8D8B-$8D9D` test dispatcher | 19 | 2,780 | 6.9% | 278 |
| `$E953-$E96A` | 24 | 1,448 | 3.6% | 415 |
| `$9741-$9757` unidentified | 23 | 1,426 | 3.5% | **0** |
| `$A71C-$A727` | 12 | 906 | 2.2% | **0** |

★★★★ **Every hot region is under 110 bytes**, and the two largest per-pixel consumers are 26 and 24
bytes. ★★★ **2,035 distinct PCs in the window**, so the stream is not one loop — but the loops that
matter are tiny.

#### 3.7 §2S / §2P

- All figures from `coco_agi` wip at this HEAD, MAME 0.281, **King's Quest III** (Sierra's CoCo3 AGI
  under OS-9), `live.dsk` sha256[0..15] `20EA31A82087DA90`, matching P3.6's pin.
  ★★ **Not to be confused with our own measurements' scene**, which is Kingquest1 room 1 — the two
  sides of every comparison here are different games, and that is stated because a per-byte and a
  per-opcode rate are what is being compared, not a total.
- ★★★ **The disk is a COPY** (`%TEMP%\sierra_media\live.dsk`); the original under
  `C:\Projects\agi-games\coco3\` was opened read-only and is byte-unchanged [§2P].
- **Nothing was written into their machine** — audit verified at 0 non-comment hits (§3.3).

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: measured]** A trace, with what had to be repaired — **PASS.** §3.2: MAME 0.281,
  25,033 lines from a plain boot; one stale path, overridable, nothing edited to run.
- **AC-2 [class: measured]** Cycles per drawn pixel, theirs, with the store cross-check — **PASS.**
  **24 CPU cycles per byte written**, six instructions, `$E1A7–$E1C0`; cross-check 5,197 stores
  (12.8% of that trace), `$E1AF STA ,Y+` ×470. §3.4.
- **AC-3 [class: measured]** Cycles per opcode, theirs — **PASS AS INSTRUCTIONS, per §6.**
  **≈35 instructions per opcode** (25 evaluator + 10 dispatcher), from 302 measured dispatches.
  ★★★ **Not stated in cycles**, because AC-3a failed.
- **AC-3a [class: measured]** Their VM cycle — ★★★★★ **NOT MEASURED, and declared.** The 344 region
  entries are expression evaluations, not VM cycles, and no dispatch-loop boundary was found that
  could be counted. Per §6 the interpreter figure is instructions per dispatch, which needs no cycle
  boundary. **No per-opcode cycle figure for their side appears in this report.**
- **AC-4 [class: attribution]** The verdict — **PASS, and it is two sentences because the numbers
  force it** [§4D]: **the blit is architecture** — there is no transparency or priority test in their
  inner loop at all, a 16-entry table turns a 4-bit source value into a finished screen byte; **the
  interpreter is technique** — the same program in ~3.7× fewer instructions, chiefly because their
  expression state lives on the stack where ours lives behind accessor calls.
- **AC-4a [class: process]** No cross-machine percentage anywhere — **PASS.** Every cross-machine
  comparison is in absolute cycles (24 vs ~144) or instructions (≈35 vs ≈128). §3.6's table is
  labelled as shares of one trace and no second machine's share appears in it.
- **AC-5 [class: eye-gated]** N/A — nothing built. **§6A's findings gate RAN**; Jay's words are in §9.
- **AC-6 [class: byte-comparable]** Nothing under `src/` — **PASS**, `git status --porcelain src/`
  returns 0 lines.
- **AC-7 [class: record]** The histogram, the loop bodies, the two numbers, and §1.1's correction —
  **PASS**, §3.1 through §3.6. ★★ Recorded as a report rather than `NOTES.md` because S-06 has no
  `poc/` directory of its own.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

§4A, the form check on a plain boot:
```
MAME 0.281
debugger present; execution_state=run
screens: [":screen"]=OK  :at(1)=OK
trace lines: 25033
```

The gate arming at the pen, all three captures:
```
[f10168] t=169.684  steady gate: quiet 3814 f, 287 screen writes, maxrun 11
[f10174] t=169.784  ★★★ TRACE 1 OFF after 6 frames   maxrun in window: 49  screen writes: 653
[f10176] t=169.817  steady gate: quiet 3822 f, 470 screen writes, maxrun 11
[f10182] t=169.917  ★★★ TRACE 2 OFF after 6 frames   maxrun in window: 49  screen writes: 470
[f10189] t=170.034  steady gate: quiet 3835 f, 512 screen writes, maxrun 11
[f10195] t=170.134  ★★★ TRACE 3 OFF after 6 frames   maxrun in window: 49  screen writes: 459
MMU at trace start: 00 3E 3E 09 01 02 03 3F   screen start physical $76000
```

AC-2, the blit and the cross-check (`fill2.tr`, 40,538 instructions, 2,035 distinct PCs):
```
    $E1A9      470    1.2%  LDA ,X+
    $E1AB      470    1.2%  ANDA #$0F
    $E1AD      470    1.2%  LDA A,U
    $E1AF      470    1.2%  STA ,Y+
    $E1B1      470    1.2%  DECB
    $E1B2      470    1.2%  BNE $E1A9

★★★ AC-6 CROSS-CHECK -- stores in the trace
   store instructions executed : 5197  (12.8% of the stream)
   hottest STORE sites:  $E994 512 STD ,X++   $E1AF 470 STA ,Y+   $8D8D 278 STX <$6C
```

AC-3, their interpreter:
```
fill2.tr  range $C76F-$C7D6
  instructions in region      : 7554  (18.6% of this trace)
  region ENTRIES              : 344
  instructions per entry      : 22.0
  distinct instructions        : 52
    $C780  LEAY   D,Y                x206
    $C784  LBSR   $84A1              x24
    $C792  LDA    ,Y+                x380
    $C794  CMPA   #$FC               x380
    $C7AE  LDA    $1,S               x28
    $C7B0  EORA   #$01               x28
    $C7B6  LBSR   $8D8B              x278
```

The no-input audit, after the gate change:
```
audit: set_value/:post/natkeyboard in non-comment lines = 0   (must be 0)
trigger reads: 1 (host-side file read, not guest input)
```

**25.2 bundled-artifact grep:** N/A — this task builds nothing.

**25.3 operator-runtime-smoke:** ★★★ **N/A by AC-5** — nothing was built to gate. **Jay drove the
capture himself**, which is a stronger form of operator involvement than a smoke test, and his
corrections are in §9.

---

### 6 — Reactive deviations and route accounting

1. ★★★★★ **The capture could not be automated, and that was not in the spike's plan.**
   `sierra_live.ps1:8` — *"The Lua sends NO input — it cannot, by design"* — so §4B needed Jay at the
   keyboard. **Reported before attempting anything else** rather than discovered halfway.
2. ★★★★ **A steady gate and an operator trigger were added** to `sierra_trace.lua`. Not in scope as
   written; §3(2) asked only that the needed gate be *stated*. **I first declined to build it**
   ("shipping an arming condition that has never been seen to arm is §2W's defect"), then built it
   when Jay committed to driving, so it could be exercised in the same session. **It was.**
3. ★★★ **The first three captures are discarded as scene-unknown.** Kept on disk as a possible
   cross-check on the per-byte rate, and **not analysed**, because §7 requires a scene.

**ROUTE ACCOUNTING.** ★★★★ **One route proposed and not carried out as described.** I told Jay the
unknown-room captures could serve as *"an independent cross-check on cycles-per-pixel"* because the
per-byte cost is a rate. **I did not run that cross-check** — the pen captures answered AC-2 directly
and the comparison was never made. **Said here because a diff cannot show an unperformed check.**

---

### 7 — Uncertainty flags

#### 7.1 Their VM cycle, and what it costs this report
★★★★★ **Not measured** (AC-3a). So **≈35 instructions per opcode cannot be converted to their cycles
per opcode**, and this report does not attempt it. ★★★ The comparison against our 450 cycles runs
through **my** ~3.5-cycles-per-instruction estimate for the 6809, which is derived.

#### 7.2 Two hot regions are unidentified, and one of them cannot be drawing
- **`$E75F–$E799`** — 59 B, 10.6% of that trace, 544 stores. Unidentified.
- **`$9741–$9757`** — 23 B, 3.5%, ★★★ **ZERO stores.** By §6's own rule a routine that does not write
  is not a drawing path. Unidentified, and **not** counted toward anything here.

#### 7.3 The window contains both subsystems
★★★ The 6-frame capture holds the interpreter and the blit together, so **no figure here separates
"their cycle" into stages.** That was not asked for and is not claimed.

#### 7.4 One instruction-cost caveat on the blit
★★ `LDA A,U`'s 5 cycles and the loop's 24 are from the instruction set, not from a cycle counter on
their machine. ★★★ **The instruction COUNT (six) is measured; the cycle total is derived.**

#### 7.5 The gate's banner still describes the fill
★★ MAME prints *"gate = graphics mode + a 128+ byte sequential run"* even under `SIERRA_GATE=steady`.
The real condition is printed when it arms. **A line that describes the wrong test is worth fixing**
and is §8's item.

---

### 8 — Follow-up candidates

1. ★★★★★ **Jay's ruling on the architecture half.** §8 of the spike frames it: accept ~4.4 cycles/s
   and go do the milestone run, or take a structural decision. **The remaining optimisation list
   cannot close a cost we incur and they do not.**
2. ★★★★★ **The technique half is actionable now and is already half-measured.** T-P0-161 measured
   **235.1 accessor calls a cycle**; their equivalent state is two stack bytes. That is a design task
   with our gates behind it (`vm` 9/9, `cel` 9,193, `comp` 124 byte-comparable).
3. ★★★★ **Identify `$E75F–$E799`** (10.6%, 544 stores) — the largest unidentified consumer, and it
   writes.
4. ★★★ **Fix the steady gate's banner** (§7.5) and consider whether the operator trigger belongs in
   `sierra_fill.lua` and `sierra_caller.lua`, which carry the same stale `TRDIR`.
5. ★★★ **Run the scene-unknown cross-check** that §6's route accounting records as unperformed.
6. **`memmap.inc:310`** — `MAP_PRI_BANDS`, **fifty-second task.**

---

### 9 — User interaction during task

★★★★★ **§6A ran, and Jay corrected the capture twice before any figure was published.**

1. *"lets do the run. start it."* — after I reported that the capture needed an operator.
2. ★★★★★ *"i wasn't at the chicken pen"* — **interrupting me as I was about to analyse the first
   three captures as the pen.** They were real steady-animation blit windows in an unknown room;
   publishing them as the pen would have been this session's third wrong-workload finding.
3. ★★★★★ *"it going to fire at the same point it did last time"* — **the defect in my gate, named
   before it wasted a second run.** It is cut 3's failure repeated, and it is why the operator trigger
   exists. §3.3.
4. *"ok"* / *"go"* — the boot, and the trigger.
5. *"report"* — §6A's close.

★★★ **Both corrections were about measurement scope, and both arrived before the numbers were
quoted.** ★★ That is the same shape as P6.106's and P6.107's corrections, and the third time this arc
that Jay's objection has been about *what was measured* rather than about the arithmetic.

---

### 10 — Candidate(s) captured this task

**None this task.** ★★★ The two strongest lessons here are already rows in the pool from the last two
tasks — `a-share-measured-on-the-wrong-workload-is-a-fact-about-the-workload` (the discarded captures
are its third instance) and `a-control-whose-parameter-arrives-but-whose-code-ignores-it`. ★★ A fourth
candidate — *a gate whose trigger is a proxy for where the operator is* — is the same principle as the
first and is recorded here rather than duplicated in the pool [§2C: folding is the reconciler's job].

---

### 11 — Commit

`<hash>` (pushed to origin/wip before this report).
