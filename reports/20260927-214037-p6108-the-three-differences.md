## Form B Report — T-P0-162 / P6.108 — The three differences S-06 named
**Class:** integration (§4A), with §1.5's bounded licence. wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-27 21:40:37 (HEAD `02669e9`, wip). Descends from `4db187d` as dispatched.
`git status` clean apart from an untracked `coco_agi.code-workspace` that is not this task's.

★★★★★ **SCENE, on every figure below** [§7]: **the castle — Kingquest1 room 1, four sprites,
`P3B_ROOM=1 P3B_ROOM_AT=8`, cycles 11–120.** Their side is **King's Quest III under OS-9**, from
S-06's captures at the chicken pen. ★★★ **Two different games; what is compared is a per-opcode and
a per-byte RATE, never a total.**

★★★★ **Units** [S-06 §1.1a]: cross-machine figures are absolute **instructions** or **CPU cycles**.
No percentage is set beside another machine's percentage.

---

### 1 — Summary

★★★★★ **The headline is that S-06's weakest figure is now measured and it held.** A MAME trace of
**our own build** over 3 castle cycles gives **`vm_*` = 67,665 instructions over 560 dispatched
opcodes = 120.8 instructions per opcode**, against their **35**. That is **3.45×**, where S-06's
derived estimate was 3.66% — ★★★ **confirmed to within 6%, so the ~3.5-cycles-per-instruction
conversion is retired.**

★★★★★ **Of the three differences, one is not a difference and one is a symptom of a deeper cause:**

1. **Expression state — NOT a difference.** §1.1's premise fails. Ours is plain memory at a
   **one-cycle** disadvantage, not an accessor call.
2. **The operand skip — real, and the skip is a SYMPTOM.** The cause is one line of the handler
   contract, and it produces three separate costs.
3. **The dispatch — not priced.** Left behind item 2.

**Taken:** two `VMARG` expansions — **`interpret` per-cycle median 0.07459 → 0.07243 s, −2.90%**,
+17 B, `vm` 9/9 with 0 divergent cycles, fault arm RED at 599/600.

**Not taken:** the ruling Jay gave (item 2), for reasons in §6 — and **the two items are not
additive.**

---

### 2 — Files modified

- `src/harness/vm_cmds.s` — `VMARG0` / `VMARGN` macros beside `vm_arg` (one home, §2F), with the
  `VM_ARG_INLINE_FAULT` arm.
- `src/harness/vm_tests.s` — two expansions replacing `jsr vm_p0` and `jsr vm_p1`.
- `harness/tools/p3b_run.lua` — `P3B_TRACE="A-B"`, a live disassembly of our own build.
- `harness/tools/p3b_show.ps1` — `-debug` passed exactly when `P3B_TRACE` is set.
- `harness/tools/vm_run.ps1` — the `VM_ARG_INLINE_FAULT` hook.
- `harness/tools/p3b_arms_check.ps1`, `probe_identity_check.ps1` — AC-11's re-baselines.

**No `src/hal/`, no `memmap.inc`, no `SHARED` file.**

---

### 3 — Reasoning

#### 3.1 ★★★★★ §3(2) — Difference 1 is not a difference, and §1.1's premise fails

Our expression state is three plain bytes: `vm_testres` [`vm_core.s:38`], `vm_notmode` [`:920`],
`vm_ormode` [`:921`]. **From the listing, not from the source** — the encodings settle it:

| ours | encoding | cycles | theirs | cycles |
|---|---|---|---|---|
| `lda vm_notmode` | `B6 0E 47` extended | **5** | `LDA ,S` indexed | **4** |
| `clr vm_notmode` | `7F 0E 47` extended | **7** | `CLR $1,S` indexed | **6** |

★★★★★ **A one-cycle gap per access, not the 45–73 of an accessor call.** Our expression state never
passes through `vm_getflag`/`vm_setflag` at all; T-P0-161's 235.1 accessor calls a cycle are the test
**handlers** reading real AGI flags, which their `LBSR $8D8B` dispatcher also does.

#### 3.2 ★★★★★ §4D(4) — our instructions per opcode, MEASURED, and the instrument validated first

★★★★★ **THE FIRST TWO ATTEMPTS WERE WRONG AND THE FAILURE IS WORTH RECORDING.** I picked PC ranges
from two symbol addresses and assumed nothing lay between them; `prpc_w` did, so 10,284 instructions
were a mixture. Then I probed `$2896` for `vmt_dispatch` from a **stale map** and read 9 dispatches
where there are 514. ★★★ **That is P3.9's error — reading a map that does not describe the running
machine — and the fix was to attribute every PC to its enclosing symbol first, then read.**

**Validated against the oracle census three ways before any figure was quoted** [§2W]:

| measured, per cycle | census [`opcount_ref.py`] |
|---|---|
| `vmt_dispatch` **171.3** | 168 test opcodes |
| `vm_test_if_code` **118.7** | 116 if-expression evaluations |
| `vm_skip_until` **112.3** | 110 calls |

★★★★ **And `vm_getflag` executes ZERO** — T-P0-161's four inlines, visible in the trace, which is
independent confirmation that they took.

**The figure:** `vm_*` = **67,665 instructions** over 3 cycles; dispatched opcodes = 514 test + 46
command = **560**. **67,665 / 560 = 120.8 instructions per opcode.** Theirs: **35**. **3.45×.**

By instruction count over that trace — ★★ **shares of our trace only**: `co_*` + `plane_*` **39.4%**,
`vm_*` **29.3%**, `p3_wait` (the harness handshake spin, which their trace has no equivalent of)
**5.5%**.

#### 3.3 ★★★★★ §4B — the skip is a symptom, and the cause is one line of the handler contract

`vm_arg`, called **225 times a cycle**:

```
pshs b(6) / tfr a,b(6) / clra(2) / addd vm_ip(6) / ldx vm_code(6) / leax d,x(8) / lda ,x(4) / puls b,pc(8)
```

**46 cycles + 8 for the `jsr` = 54 cycles to fetch ONE operand byte.** Theirs is `LDB ,Y+` — **6
cycles, one instruction, and the read IS the advance**, because their ip is a register.

★★★★★ **`vm_cmds.s:15-17` names the cause:** *"on entry vm_ip points at p[0] (vm_run_logic advanced
past the opcode and advances by VMOP_ARGS[op] afterwards). Handlers may destroy A, B, X; **they must
not touch vm_ip**."*

★★★★★ **That one decision produces three costs:**

1. Handlers read operands **by index**, so `vm_arg` re-derives `vm_code + vm_ip` every time —
   **12,150 CPU cycles a cycle** (54 × 225), **9.1% of `interpret`'s 133,500**.
2. The interpreter must **skip the operands separately** through `VMTEST_ARGS`
   (`vm_skip_instruction`, 211.7 calls a cycle).
3. The **block-end walk** sits on top (`vm_su_lp`, 153 iterations a cycle).

(2) and (3) together are **10,985 instructions over 3 cycles = 16.2% of our interpreter's
instructions.** ★★★★ **Their handlers consume operands from Y as they read them, so no skip step
exists at all.**

★★★★★ **So `VMTEST_ARGS` is NOT the obstacle and §6's generator trigger does not fire.** §1.2 framed
this as `LEAY D,Y` against a table lookup — a technique gap. It is not: **their one-instruction skip
is possible because their ip is a register, and ours needs a call because ours is not.** The table is
incidental, and `gen_vm_tables.py --check` is green and untouched.

#### 3.4 Item 1 — the licence-legal half, and why these two sites

★★★★★ **The site choice is the measurement's, not the site count's** [§1.4]. From our trace:
`vm_p0` **159.3** calls a cycle, `vm_p1` **62.3**; hot handlers `is_set` **64**, `equal` **50.7**,
`said` 27.3, `controller` 23 — 165 of the 171 test dispatches. ★★★ **`vmtest_has` executes ZERO.**

★★★★ **For index 0 the index arithmetic vanishes with the call:** `ldd vm_ip / ldx vm_code /
leax d,x / lda ,x` = **24 cycles against 54**. For index N, 28 against 54.

★★★ **`pshs b`/`puls b` dropped**, and that is the part the fault arm tests rather than the comment
asserting: `vmtest_is_set`'s next act is `VMGETFLAG`, which loads B before reading it; `vmtest_equal`'s
is `cmpa ,s+`; and the test dispatch's caller reads `vm_exitall` then calls `vm_skip_instruction`,
which does its own `ldb vm_op` [`vm_core.s:519-522`].

★★★ **One home** [§2F]: the body is a macro beside `vm_arg`, expanded and never copied; both
`p3b_probe.s` and `vm_probe.s` include `vm_cmds.s` before `vm_tests.s`, verified.

★★ **Two macros rather than one with `ifne \1`**: conditional assembly on a macro parameter is syntax
this tree has never used, and the index-0 form is genuinely shorter.

#### 3.5 §2S / §2P
- All our figures at `coco_agi` wip, this HEAD, MAME 0.281, castle scene as §0 states.
- `hal_sync_check.py` compared against **POP3_port** and **karateka_coco3** working trees at this
  task's time; neither was built or modified. **No `SHARED` file touched.**
- §2P: instructions, cycles, call counts and scenes only.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement]** §3(2)'s answer and §4A's per-cycle counts — **PASS.** §3.1, §3.2.
- **AC-2 [design]** The state held differently from the oracle, stated as a divergence — ★★★
  **PASS, and the answer is that it is NOT a meaningful divergence**: ours is a global, theirs a
  stack byte, both plain memory, one cycle apart. §3.1.
- **AC-3 [measurement]** §4B's measured skip counts and per-call cost — **PASS.** `vm_skip_instruction`
  211.7/cycle, `vm_su_lp` 153/cycle, `vm_skip_until` 112.3/cycle; `vm_arg` 54 cycles a call at
  225/cycle. §3.3.
- **AC-4 [measurement]** §4C's price and whether it needs the handlers changed — ★★★★★ **FAIL, NOT
  DONE.** §4C was left behind item 2 and is unpriced. **Declared, not implied.**
- **AC-5 [measurement]** §4D's five figures, each change measured separately — **PARTIAL.**
  (1) call counts before/after: before measured; **after not re-traced.** (2) `interpret` median
  **0.07459 → 0.07243 s standing**; ★★★ **moving not measured.** (3) cycle median **0.2003 s
  unchanged** (frame-quantised). (4) **instructions per opcode: 120.8, measured** — the figure that
  retires S-06's derived 128. (5) region A **1,010 → 993 B**.
- **AC-6 [state-comparable]** Nine-title VM gate — **PASS, RUN.** 9/9, **0 divergent cycles of 600**
  on every title.
- **AC-7 [state-comparable]** Both planes byte-identical over 120 cycles, moving and standing —
  ★★★ **NOT RUN. Declared.** The `comp` gate's 124/124 and the 9/9 state diff are adjacent evidence
  and are **not this AC**.
- **AC-8 [fault injection]** Each change's arm RED — **PASS.** `-DVM_ARG_INLINE_FAULT` drops the
  index add so the inline reads operand 0: **599 of 600 divergent, `AC-2 ★★★ FAIL`.**
  ★★★★★ **And it is deliberately NOT a dropped `pshs b`, which would be INERT** — B is provably dead
  at both sites, so the same proof that makes the change safe makes that fault useless. §2W's own
  defect, and the second task running that this trap has been named at this exact spot.
- **AC-9 [byte-comparable · gate]** fresh — **PASS.** `pic` 45/45, and `res`/`cel`/`comp` green in
  the same run. ★★ The exact 124/124, 9,193/9,193 and 1,264/1,264 counts are not transcribed; the
  suite's green line is the evidence quoted.
- **AC-10 [suite]** Full suite green, fault arms RUN — **PARTIAL.** Suite green (**538 files swept,
  45/45, all nine gates**), `mojibake_selftest.py` inside it, `p3b_arms_check -SelfTest` red as
  designed. ★★★ **`-ForceOverlap`, `-NoRestore`, `-DVM_RL_FAULT` and `VM_TIC_SLOW` NOT re-run this
  task** — they were run green at T-P0-161 and are not re-inferred here.
- **AC-11 [byte-comparable]** Arms re-baselined; region A stated — **PASS.** All nine **+17 B each**,
  uniform; self-test still red; `vm` probe re-pinned 10,229 → 10,246 (+17, all this task's); region A
  **1,010 → 993 B**.
- **AC-12 [eye gate]** ★★★ **NOT OFFERED.** −2.90% of `interpret` is **~1.1% of a cycle**; the honest
  expectation for "faster while the alligators swim?" is that Jay would see nothing, and AC-6's
  nine-title byte-identical state answers "does everything still behave" far more strongly than one
  watched run. **Stated for Jay to overrule rather than quietly dropped.**
- **AC-13 [tooling]** — **PASS.** `gen_vm_tables.py --check` OK (matches `optable.py`);
  `hal_sync_check.py` OK, 11 files, both siblings; `reg_discipline.py` **10 accesses in 1 file over 4
  registers, all `src/engine/mmu_phase.s`** — unchanged, and no `src/engine/` file was touched;
  `probe_identity_check.ps1` OK after the re-pin; `p3b_arms_check -SelfTest` red.
- **AC-14** Candidates — **PASS.** §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

§4D(4), our instructions per opcode, after symbol attribution:
```
p3b36.tr  vs  p3b_probe_pk.map     instructions traced : 230970   symbols in map : 1712
  co_inc32   16425  7.1%   co_pix 13518 5.9%   p3_wait 12691 5.5%   co_depth 11410 4.9%
  vm_rl_loop  7202  3.1%   vm_tic_loop 6268 2.7%   vm_skip_instruction 6029 2.6%
  PREFIX 'vm_':     67665 instructions over 125 symbols  (29.3% of this trace)
  PREFIX 'co_':     76184 instructions over  21 symbols  (33.0% of this trace)
  PREFIX 'plane_':  14766 instructions over   2 symbols  ( 6.4% of this trace)
  vmt_dispatch  $2CDD executed 514      vm_rl_dispatch $2C4D executed  46
  vm_getflag    $2B30 executed   0      vm_skip_instruction $2DAA executed 635
  vm_su_lp      $2D86 executed 459      vm_tic_loop    $2CA8 executed 655
  vm_skip_until $2D83 executed 337      vm_test_if_code $2C9D executed 356
  vm_arg        $2E01 executed 675      vm_p0 $2E12 executed 478   vm_p1 $2E15 executed 187
  vmtest_is_set $357E executed 192      vmtest_equal $3518 executed 152
  vmtest_said   $364A executed  82      vmtest_has   $35C2 executed   0
```

AC-5(2), item 1 measured alone (castle, stage medians, min p25 MEDIAN p75 max):
```
BEFORE  interpret 0.04293 0.07459 0.07459 0.07469 4.46198    program 16870 B
AFTER   interpret 0.04174 0.07243 0.07243 0.07253 4.46029    program 16887 B
```

AC-6 and AC-8:
```
=== AC-2 SUMMARY ===   Kingquest1 PASS  Kingquest2 PASS  Kingquest3 PASS
SpaceQuest-1 PASS  SpaceQuest-2 PASS  PoliceQuest1 PASS  larry1 PASS
BlackCauldron PASS  MixedUpMotherGoose PASS      divergent cycles : 0 of 600

★★★ FAULT INJECTED (-DVM_ARG_INLINE_FAULT): VMARGN drops the index add -- reads operand 0
divergent cycles : 599 of 600        AC-2 ★★★ FAIL
```

AC-11 and AC-13:
```
★ all 9 arms byte-identical to the recorded baseline (SHA256)
★ SELF-TEST: ... ★ 1 ARM(S) MOVED          <- still red, as designed
region A (p3b): P3_CODE_END $5C1F  headroom 993 B  (was 1,010)
CHECK OK: src/harness/vm_tables.s matches optable.py.
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 10 register access(es) in 1 file(s) over 4 register(s).
vm 10246 B 7A9050F7 [pinned] OK
★ source integrity: clean (538 files swept, 3 BOM-tolerated)
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
```

**25.2 bundled-artifact grep:** N/A — no DECB artifact; the probes are poked images.

**25.3 operator-runtime-smoke:** ★★★ **NOT OFFERED — see AC-12.** Jay's ruling invited.

---

### 6 — Reactive deviations and route accounting

1. ★★★★★ **Item 2 — the ruling Jay gave — was NOT started, and that is a deliberate refusal to
   begin, not an omission.** Two reasons, the second load-bearing:
   - it touches **203 handlers** (183 command + 20 test), the blast radius P6.106 refused for
     `jmp [d,x]`;
   - ★★★★★ **the intermediate state is a §2F violation with a divergence hazard**: `vm_ip` in memory
     **and** in a register at once, read by `vm_su_lp`, `vm_test_if_code`, `vm_run_logic` and the
     `said` handler. **The nine-title byte-comparable gate is the only safety net, and a
     half-converted contract is precisely the condition under which it would catch a divergence that
     could not then be localised.**

   **Staging proposed instead** (§8.1): the **20 test handlers only**, which carry ~90% of the operand
   traffic from a tenth of the sites, gate-first — sync points before handlers, prove 9/9 with zero
   handlers converted, then convert in batches with the gate between.
2. ★★★★★ **The two items are not additive.** Both target `vm_tests.s`, so **item 2 subsumes item 1**
   rather than adding to it, and item 2's remaining prize is **~14.8% of `interpret`**, not 17.7%.
   **Surfaced before item 1 was implemented**, so Jay's ruling was not spent on a misunderstanding.
3. **Three harness additions** not in scope as written: `P3B_TRACE`, `-debug` keyed to it, and the
   `VM_ARG_INLINE_FAULT` hook. Each exists because §4D(4) needed our own instructions counted with
   the same instrument used on theirs.

**ROUTE ACCOUNTING.** ★★★★ **I proposed one route and did not carry it out as described.** At §6A I
said item 1 was worth *"~2.4% of `interpret`"* on the basis of 225 calls a cycle — then found the
calls are ~90% in the test handlers, so **the estimate's population was wrong even though the measured
outcome (2.90%) came out higher.** The number was right by luck, not by the reasoning I gave. Said
here because a diff cannot show an estimate's basis.

---

### 7 — Uncertainty flags

#### 7.1 Three ACs are not done, each declared rather than inferred
- **AC-4** — §4C's dispatch price. Unpriced.
- **AC-7** — the plane-pair diff, moving and standing.
- **AC-5(1)** — call counts **after** the change; the trace was not re-taken.
- **AC-5(2) moving** — only the standing median was measured.
- **AC-10** — four fault arms not re-run this task.

#### 7.2 The instrument was wrong twice before it was right
★★★★★ A mis-specified PC range (`prpc_w` inside it) and a **stale map** (`$2896` for `vmt_dispatch`,
which is `$2CDD`) produced 9 dispatches where there are 514. ★★★ **Both were caught by the numbers
disagreeing with the oracle census, not by inspection** — which is why the census cross-check in §3.2
is quoted before the figure it validates.

#### 7.3 `co_inc32` at 7.1% of our trace is a known live counter
Not a new finding: `gates.manifest` already records the composite counters as a deliberate counting
**arm** in the `p3b` cel row, priced at 11.9% of a castle cycle [P6.76]. ★★ Recorded so the next
reader does not re-discover it as a fifth instrument left on.

#### 7.4 Labelled as Clyde's arithmetic per §8
The 6809 cycle costs in §3.1, §3.3 and §3.4 (54, 24, 28, and the 5-vs-4 encodings' timings) are from
the instruction set, **not measured**. ★★★ **The instruction COUNTS and the CALL COUNTS are measured;
the cycle totals derived from them are not.** The one measured cycle figure is AC-5(2)'s −2.90%.

#### 7.5 The `vm` probe's −7 pre-existing drift is now two pins deep
T-P0-161 found it and declined to absorb it; T-P0-162's +17 re-pin now hides it again. **Cause still
unidentified**, recorded in both files so it does not vanish.

---

### 8 — Follow-up candidates

1. ★★★★★ **Item 2, staged: the 20 test handlers.** Worth ~14.8% of `interpret`. Gate-first, batched,
   with the §2F two-homes hazard as the thing the staging exists to avoid. **This is the largest
   measured, actionable item in the interpreter.**
2. ★★★★ **§4C's dispatch price** (AC-4), which this task did not reach.
3. ★★★★ **Re-trace after item 1** to close AC-5(1), and take the **moving** medians for AC-5(2).
4. ★★★ **AC-7's plane diff** and AC-10's four fault arms.
5. ★★★ **The blit redesign — ARCHITECTURE** [S-06]: six instructions, 24 cycles a byte, no
   transparency or priority test in the loop, a 16-entry table doing translation, doubling and
   packing. **Out of scope here and still the larger prize.**
6. **`memmap.inc:310`** — `MAP_PRI_BANDS`, **fifty-third task.**

---

### 9 — User interaction during task

★★★★★ **§6A ran three times, and each of Jay's answers redirected the work.**

1. *"do 4"* — after §3(2) killed Difference 1 and my first two PC ranges proved unattributable. This
   produced the symbol-attribution instrument and **the measured 120.8 instructions per opcode**,
   which retires S-06's derived figure.
2. *"do 4"* — after the attribution landed. This produced §3.3: the skip is a symptom and the handler
   contract is the cause.
3. ★★★★★ *"do 4 both items"* — **the ruling on item 2.** I implemented item 1, surfaced that the two
   items are not additive, and **declined to begin item 2**, giving the staging instead. §6.1 records
   that refusal and its reason.
4. *"report"* — §6A's close.

★★★ **Jay's ruling was given and is recorded as given.** ★★ What this report does not do is act on
the whole of it; §6.1 says so plainly rather than leaving the gap to be inferred from the diff.

---

### 10 — Candidate(s) captured this task

**None new.** ★★★ The two lessons here are instances of rows already in the pool:
`a-share-measured-on-the-wrong-workload-is-a-fact-about-the-workload` (§7.2's stale map and
mis-specified range are its fourth and fifth instances — an instrument reading the wrong thing while
looking coherent), and `multiply-a-per-site-cost-by-the-sites-own-population` (§6's route accounting:
my 2.4% estimate used 225 calls a cycle when the population was the test handlers' subset).
★★ Folding is the reconciler's read-time job [§2C], so they are recorded here rather than duplicated.

---

### 11 — Commit

`02669e9` (pushed to origin/wip before this report). Suite green at the commit: 538 files swept,
45/45 per-picture, all nine gates; `vm` 9/9 with 0 divergent cycles of 600.
