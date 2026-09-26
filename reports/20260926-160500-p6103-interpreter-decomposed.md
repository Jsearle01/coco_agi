## Form B Report — T-P0-157 / P6.103 — The interpreter has never been profiled
**Class:** measurement, with §1.4's bounded licence.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-26 (dispatch T-P0-157, descends from `677117b` as specified). HEAD at start `677117b`
(wip), clean apart from untracked `coco_agi.code-workspace`. HEAD at report `fbd04f7`.

### 1 — Summary
**`interpret` = 0.07696 s per steady cycle = 137,720 CPU cycles = 450 CPU cycles per AGI opcode.**
The two figures §1.2 flagged reconcile: the harness's stage table is a **mean over all 120 cycles**
whose percentages are **shares of the stage sum, not of the cycle**, so P6.102's ~213,000 was
inflated by a room-render cycle and P6.101's 156,784 was simply a **stale build**. A new per-cycle
stage instrument makes the steady state readable, and it **overturns the dispatch's central
premise**: in a steady cycle **composite is 59.4% and `interpret` is 38.7%** — the interpreter is the
smaller half, and `roomcheck`'s 16% was entirely the room render. The label profile answers §4B in
one sentence: **the cost is the dispatch and the operand plumbing (59.3%), not the handlers (7.2%)**,
and the dispatch is *already* a table. Three changes were costed: **one taken (0.387% of a cycle),
one measured but refused because its fault arm cannot be made to go red, one rejected as a measured
regression.** ★★★★★ **And the suite is red on a clean tree: `fix_mojibake.py --check` false-positives
on a legitimate two-character sequence and its repair destroys content — presented to Jay, not yet
ruled on.**

### 2 — Files modified
- `harness/tools/p3b_run.lua` — per-cycle stage times, percentiles, the reconciliation, the
  frame-quantisation statement.
- `src/harness/vm_core.s` — E1 taken; E3 reverted with its arithmetic recorded at the chain;
  `VM_RL_SLOW` / `VM_RL_FAULT`.
- `src/harness/vm_state.s` — E2 behind `VM_CTRL_MASKTABLE` (opt-in, **not** shipped);
  `VM_CTRL_FAULT`.
- `harness/tools/p3b_show.ps1` — `-RlSlow`, `-CtrlMaskTable`; the deleted `-RlMarkSlow` explained.
- `harness/tools/vm_run.ps1` — `VM_RL_FAULT`, `VM_CTRL_FAULT`.
- `harness/tools/gates.manifest` — §4F's finding, and T-P0-156's suite-scope error.

Explicit-path staging only.

### 3 — Reasoning

**3.1 §2H's three checks, applied to the profile.** (1) *A second mechanism for a different object
class?* Yes, and it is the whole of §4B: `vm_rl_loop` (command fetch) and `vm_tic_loop` (test fetch)
are **two dispatch loops over the same byte stream**, with separate costs, separate marker sets and —
as E3 proved — **opposite optimal orderings**. Treating "the dispatch" as one thing is what produced
the regression. (2) *Name the calling routine.* `vm_arg`'s 7.7% is charged to `vm_op_return` because
the caller is a `bra` from `vm_p0`–`vm_p4`, not a `jsr`; the enclosing routine is the fact and the
profiler could not see it. (3) *Grep the reports for the same subsystem before citing one.* Done, and
it is what found the §1.2 conflict to be a **stale build plus my own contaminated mean**, rather than
two rival measurements.

**3.2 Authority tier.** Every figure here is **measurement of our own port** — tier: our
instrumentation, not the oracle. The single oracle-derived input is P6.102's **306 opcodes per
cycle**, used as the divisor; it is ScummVM-derived and **believed original, not a normalisation**
(§2.1), because it is a property of the game's own bytecode.

**3.3 Why the median and not the mean.** `interpret`'s max in the window is **4.46703 s in one
cycle** and `roomcheck`'s is **5.46816 s** — the room render. A mean over that window is not a
steady-state cost, which is P6.84's lesson and the direct cause of §1.2's discrepancy. ★ The stage
sum, not the cycle time, is the correct divisor: the cycle timer is frame-quantised and the stages
are instruction-precise.

**3.4 No sibling claim is made.** No `src/hal/` or `src/engine/` file was touched; §2M and §2N are
N/A and no POP/Karateka ref is cited (§2S).

### 4 — Verification (AC-by-AC)

**AC-1 [measurement] §4A reconciled; the per-opcode figure stated once with its basis.** — The
harness prints `100*s/tot` where `tot` is the **sum of stages** (`p3b_run.lua:1855`) and `s/NCYC` as
a mean over the whole window. So P6.101's 156,784 = *share of the stage sum* × *frame-quantised
median cycle*; the product is approximately valid **because the stage sum ≈ the cycle** (0.19903 vs
0.20026 today), and its 36% gap from P6.102 is **a stale build, not a bad method** — its cycle was 14
frames, today's is 12. P6.102's 0.11908 s is the stage timer's **mean**, inflated 55% by the room
render. ★★★★★ **THE FIGURE: `interpret` = 0.07696 s/steady cycle = 137,720 CPU cycles = 450 CPU
cycles per AGI opcode.** Basis: per-cycle **median** of the write-tapped `P3_PHASE` timer, measured
clock **1.789772 MHz**, ÷ 306 opcodes.

**AC-2 [measurement] §4B's label table and the five-way split.** 19,067 samples at 997 Hz over cycles
30–120; 6,906 in the interpret stage; top 30 labels cover 96.7%; **0 samples in remapped slots 3–6**,
so every PC is attributable. Split of the stage: **fetch/dispatch 38.1% · skip walk 13.5% · operand
fetch 7.7% · variable/flag helpers 11.2% · handler bodies 7.2% · object motion 9.2% · resource
manager 5.3%.** ★ **Moving vs standing was NOT separated** — see §7.3.

**AC-3 [attribution] §4B's one sentence.** ★★★★★ **The cost is in the DISPATCH and the OPERAND
PLUMBING — 38.1 + 13.5 + 7.7 = 59.3% of the stage — and not in the handlers, which are 7.2%.** ★★★★
**Jay's lookup-table question has a specific answer: the dispatch is ALREADY table-driven and the
table is cheap** — `vmt_inrange` + `vmt_dispatch` = 7.4% together. **The loop around the table is the
cost, not the choice of table over if-chain**, and E3 shows a mis-ordered compare chain can cost more
than the table saves.

**AC-4 [measurement] §4C's changes, each measured separately, §1.4 answered per change.**

| | change | interpret | of a cycle | §1.4 |
|---|---|---|---|---|
| **E1** | `vm_rl_loop` stops spilling the opcode across the ip update | 0.07696 → **0.07619** | **0.387%** | all five hold — **TAKEN** |
| **E2** | `vm_ctrl_get` indexes `vm_bitmask` instead of shifting | 0.07696 → 0.07646 | 0.251% | **criterion 4 FAILS** — not taken |
| **E3** | the marker split applied to `vm_rl_loop` | **slower** | **−0.34%** | **REJECTED, measured** |

E1's five: one named cause (a spill that the ordering makes unnecessary) · local, no new mechanism ·
no observable behaviour moves (gate 9/9) · fault arm red 9/9 · no ruling needed. **1.00% of the
stage, build 16790 → 16784 B.**
E2 is measured and **refused**: §7.2. E3 is a **measured regression**: §6(2).

**AC-5 [state-comparable] The nine-title VM gate.** **9/9 PASS, 0 divergent cycles of 600**,
exclusion set EMPTY, on the shipped build. ★ Both planes byte-identical over 120 cycles was **not
separately re-run** — no plane-touching code changed, and §7.4 records that as reasoning rather than
measurement.

**AC-6 [byte-comparable · gate] comp / cel / res / pic.** ★★★★★ **NOT MET — the suite aborts before
them on the mojibake gate (§4F).** `src/` changed, so a §2T citation is not available. **Recorded as
unmet rather than worked around.**

**AC-7 [state-comparable · fault injection] Each change's arm RED.**
- `-DVM_RL_FAULT` (E1) — reinstates **L-37**: the opcode read before `ldd vm_ip` clobbers A.
  **9/9 FAIL at 599 divergent cycles of 600.** ★★★★ **It RUNS and diverges in state** rather than
  halting — the evidence P6.102's two marker arms could not give.
- `-DVM_CTRL_FAULT` (E2) — indexes `vm_bitmask+1`. **9/9 PASS. The arm cannot be reddened**, and on
  the parser arm with input fed to five titles it is still 9/9 PASS. **That is why E2 is not taken.**
- ★ **Would `VM_FAULT` have caught either?** No. It injects a `ble`→`blt` in `vm_cs_0` and is
  unrelated to both sites; and per T-P0-156 §4E it is itself green on 3 of 9 titles.

**AC-8 [measurement] §4D's costed option.** §7.5 — the dispatch **is** implicated, so the option is
stated and **not started** (§6's third trigger).

**AC-9 [byte-comparable] Region A's headroom.** `P3_CODE_END` = **$5BC7** against `MAP_RESERVED_END`
$6000 on the all-slow arm = **1,081 bytes free**; the shipped arm is 6 bytes smaller still
(**1,087**). ★★★★ **T-P0-156 claimed region A had 110 bytes and that was wrong by a factor of ten** —
it was carried memory, and it had already caused that task to drop a change for a reason that did not
exist. Read from the map of the measured build this time.

**AC-10 [suite] Full suite green.** ★★★★★ **NOT MET. `run_gates.sh` fails on a CLEAN tree** — §4F.

**AC-11 [manifest] Arms re-baselined.** `gates.manifest` gains §4F and the T-P0-156 suite-scope note.
★ `p3b_arms_check` re-baselining **not run** — it is downstream of the suite (§7.6).

**AC-12 [tooling] `hal_sync_check` ×3, `reg_discipline`, `gen_vm_tables --check`,
`probe_identity_check`, `p3b_arms_check -SelfTest`.** ★★★ **NOT RUN.** `hal_sync_check` and
`reg_discipline` are **N/A by scope** (no `src/hal/`, no `src/engine/`); the remaining three are
inside the suite that §4F blocks. §7.6.

**AC-13 Candidates captured.** §10.

### 4F — ★★★★★ The mojibake gate is red on a clean tree, and its repair destroys content

`fix_mojibake.py --check` flags **`U+00D7 U+2013`** — a MULTIPLICATION SIGN followed by an EN DASH,
as in a ratio written *"2.8⟨times⟩⟨en-dash⟩4.7⟨times⟩"*. ★★ **Spelled in codepoints throughout,
because writing those two characters into this report would make the report itself fail the check** —
§2J.7's trap, now for the fourth time in this project.

★★★★★ **And the repair rewrites it.** `fix_mojibake.py <file>` turns `U+00D7 U+2013` into **`U+05D6`
(HEBREW LETTER ZAYIN)** plus a stray `U+00D7`. **It did exactly that to
`reports/20260926-104500-p6-101-the-proxy-is-wrong.md`, a correct file, and I caught it only by
reading the diff.** ★★★★ **`run_gates.sh` prints *"repair with: python
harness/tools/fix_mojibake.py <file>"*, so following the gate's own printed advice destroys
content.** Reverted with `git checkout --`; the report is byte-unchanged from `677117b`.

**The cause.** The tool reverses a candidate run and keeps the result **if it decodes as valid
UTF-8**. Two characters can satisfy that by accident: cp1252-encoding `U+00D7 U+2013` gives the bytes
`D7 96`, a well-formed two-byte sequence. **"Decodes as valid UTF-8" is necessary and not
sufficient.**

★★★★★ **Shown both ways, from codepoints** [§2W] — a harness built in the scratchpad, nothing tracked:

```
true-positive  (a damaged star)      expect flag=True  got flag=True   OK
      repair -> REWRITTEN ; non-ascii now: [U+2605]
false-positive (2.8x EN-DASH 4.7x)   expect flag=False got flag=True   *** WRONG
      repair -> REWRITTEN ; non-ascii now: [U+05D6 U+00D7]
      *** THE REPAIR DESTROYED LEGITIMATE CONTENT
clean          (a proper star)       expect flag=False got flag=False  OK
```

**So the detector is sound on real damage and the acceptance test is what is too weak.** A candidate
narrowing: require the run to be ≥3 characters, or require its first character to be one of the
cp1252 lead mis-decodes (`U+00C2` / `U+00C3` / `U+00E2`). ★★★★★ **NOT APPLIED — §2J.7 is a
CLAUDE.md-level gate and this is Jay's ruling** (§6's last trigger in spirit: the rule's own
enforcement mechanism). **Presented 2026-09-26; not yet ruled on** (§9).

★★★★★ **And the reason it survived a whole task: T-P0-156 NEVER RAN THE SUITE.** Its 25.1 listed
`fix_mojibake.py --check` over **the six files it touched**, which reads as discharging §2J.7 — a rule
that defines the check as **every tracked text file**. ★★★ **Third instance of the scope disease in
two tasks** (VM_FAULT's corpus; the parser arm announcing nine titles and running eight; this) — **and
the only one of the three I committed myself.**

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
── §4A per-cycle stage times, 120 cycles recorded ──   [SHIPPED build, 16784 B]
   stage            min       p25    MEDIAN       p75       max
   pace(wait)   0.00012   0.00061   0.00061   0.00061   0.00067
   interpret    0.04397   0.07609   0.07619   0.07629   4.46495
   sprites      0.00259   0.00270   0.00270   0.00278   0.00403
   roomcheck    0.00003   0.00003   0.00003   0.00003   5.46816
   composite    0.00016   0.10992   0.11823   0.13175   0.20558
   ★ stage SUM per cycle: median 0.19826 s   CYCLE median 0.20026 s
   ★ gap per cycle: median 0.00847 s (4.2% of the median cycle); worst |gap| 0.01774 s at cycle 1
   ★★★ 120 of 120 cycle times are exact multiples of 1/60 s: the CYCLE timer is FRAME-QUANTISED
   ★★★ one frame = 0.01667 s = 8.3% of the median cycle, so a gap of 0.00847 s is BELOW the
       timer's resolution and is NOT evidence of unattributed work
   ★ divide by the stage SUM, not the cycle time -- same resolution as the stages

ARMS (P3B_ROOM=1, -Headless -Cycles 120, -nothrottle):
  -RlSlow -CtrlMaskTable  16790 B  interpret 0.07696  SUM 0.19903   <- reproduces 677117b exactly
  -CtrlMaskTable          16781 B  interpret 0.07569  SUM 0.19776
  -RlSlow                 16790 B  interpret 0.07696  SUM 0.19903
  SHIPPED                 16784 B  interpret 0.07619  SUM 0.19826
  clock MEASURED 1.789772 MHz (160009 cycles calibrated)
```

```
pc_profile.py profile.txt p3b_probe_pk.map --stage 3 --labels --top 30
# window cycles 30-120  hz 997  samples 19067  span 19.1234 s   [--stage 3 only]
  interpret  6906  100.0%          PCs in remapped slots 3-6: 0 samples
TOP LABELS   1 vm_rl_loop 9.3%   2 vm_arg 7.7%   3 vm_tic_end 7.4%   4 vm_tic_loop 6.9%
             5 vm_su_lp 6.1%   6 vm_skip_instruction 5.8%   7 vm_up_next 4.6%
             8 vm_getflag 4.5%   9 vmt_dispatch 3.8%  10 vmt_inrange 3.6%
     top 30 cover 96.7% of samples; 59 routines seen
BY SUBSYSTEM  VM interpret 84.2%  object update/motion 9.2%  resource manager 5.3%
              VM cycle/pacing 0.6%  parser 0.6%
```

```
vm_run.ps1 (clean, shipped build)   === AC-2 SUMMARY ===   all nine PASS
  each: compared 600 cycles x 288 bytes, exclusion set EMPTY, divergent cycles 0 of 600

VM_RL_FAULT  (E1's arm)   9/9 FAIL, divergent cycles 599 of 600 on every title
VM_CTRL_FAULT (E2's arm)  9/9 PASS, divergent cycles 0 of 600 -- CANNOT BE REDDENED
VM_CTRL_FAULT + VM_INPUT  8 rows, all PASS; 5 titles input-fed, 3 not
```

```
run_gates.sh                  ★★★ GATES FAILED: mojibake
  reports/20260926-104500-p6-101-the-proxy-is-wrong.md  1 run(s) double-encoded   <- FALSE POSITIVE
  (the only other hit is the allowlisted P3.2 report)
fix_mojibake.py --check  on the six files this task touched:  all clean, exit=0
```

`hal_sync_check.py`: **N/A — no `src/hal/` or `src/hal.inc` file touched.**
`reg_discipline.py`: **N/A — §2N's window is `src/engine/**`; this task touched `src/harness/` only.**

**25.2 bundled-artifact grep:** N/A — no DECB artifact or disk image built.

**25.3 operator-runtime-smoke:** **pending Jay.** A component task, not an integration task (§4A), so
the eye gate is not owed as AC-1. ★ **Nothing visible changed**: E1 is worth 0.387% of a cycle and
does not move the frame-quantised median (0.20026 s on every arm).

### 6 — Reactive deviations and route accounting

1. **§4A was extended beyond reconciling two numbers**: reconciling them required a per-cycle
   instrument that did not exist, so `p3b_run.lua` gained one. **Not in the dispatch; without it the
   steady state cannot be quoted at all.**
2. **E3 was BUILT, MEASURED, AND REVERTED.** I proposed applying group D's marker split to
   `vm_rl_loop` and it measured **609 CPU cycles per game cycle slower**. `$FF` is **84% of that
   chain's arrivals** (116 expressions of 138 fetches) and the existing order exits on it first in 5
   cycles; mine took 11. **The arm was deleted with the change** — an arm that switches between a
   build and a worse build is not evidence. The arithmetic is recorded at the chain in `vm_core.s`.
3. **E2 was BUILT AND MEASURED AND IS NOT SHIPPED**, per §1.4 criterion 4 and §6's second trigger.
   Its guard is **inverted** (`VM_CTRL_MASKTABLE`, opt-in) so the default is unchanged and the work is
   recoverable.
4. **§4C's `setdp` question was answered and not acted on**: the hot scalars are at `$2BDB`–`$366A`,
   so direct addressing needs a variable move **and** a DP change — and the 6809 stacks DP on IRQ
   while the HAL's handler assumes 0. **A ruling, not a local change.** §4D.
5. **Two fault arms were added** (`VM_RL_FAULT`, `VM_CTRL_FAULT`) — not in the dispatch, required by
   AC-7.
6. **The mojibake finding was investigated, demonstrated, and NOT fixed** (§4F). **What I did do**:
   reverted the damage and recorded it in `gates.manifest`.

**ROUTE ACCOUNTING.** I told Jay in the preceding strategy exchange that `roomcheck`'s 15.9% was
"very likely one big event divided by 120". **Confirmed, and it is more extreme than I said: 0.015%.**
I also gave a bound of **2.37× if the interpreter and roomcheck were free**; on the steady-state
figures that bound is **2.46×** and the composition is different — **composite is 59.4%, not 40.8%.**
★★ **The conclusion I drew from it stands and the arithmetic behind it was contaminated.**

### 7 — Uncertainty flags

**7.1 ★★★★★ The dispatch's central premise did not survive.** §1.1 opens *"the gap is in the
interpreter"*; in a steady cycle **`interpret` is 38.7% and `composite` is 59.4%**. P6.101's headline
survives but weakens: `interpret` alone is **1.15–1.54×** their whole cycle (137,720 against
89,489–119,318), not 1.31–1.75×. **Any further interpreter-first plan should be re-argued against
this.**

**7.2 E2 is measured, correct as far as anything can tell, and unshippable.** The change is a
20-line mirror of `vm_getflag`, the gate is green on it, and **that green means nothing**: no
controller bit is set in any gate arm, so `0 & mask` is 0 for every mask and a wrong bit index is
invisible. ★ **`vm_ctrl_get` IS called** — 120 samples in the profile — it simply always answers 0.
To take it the gate needs an arm where a controller is set (`set.key` plus a posted key that maps to
it). **§8.2.**

**7.3 Moving vs standing was not separated, and §4B asked for both.** The headless arm reports
`restore 0 bytes over 120 cycles`, which is consistent with nothing animating; a moving window needs
`-WithInput` and a walk. **The figures here are one room, one title, standing, 120 cycles** — L-85's
warning in its own terms.

**7.4 AC-5's plane-byte half is reasoning, not measurement.** No plane-touching code changed, so I
did not re-run the 120-cycle plane comparison. **Stated as an inference** rather than reported as
evidence.

**7.5 §4D's options are unvalidated arithmetic** (§8's rule). **(a) The operand-fetch contract:**
`vm_run_logic` already holds `code+ip` in X to fetch the opcode and **discards it**; every operand
fetch re-derives it through a `jsr` at ~48–61 cycles, ~200 calls a cycle, **7.7% of the stage**.
Passing the pointer makes an operand `lda n,x` at 4–5 cycles — **upside ~2.5% of a cycle** — but it
changes the handler contract at `vm_cmds.s:15-17`, so **every handler using `vm_p0`–`vm_p4` must
preserve X**. ~200 handlers to audit. **A ruling.** **(b) The skip walk, 13.5%:** the walk from a
given ip is **invariant** because the logic is static, so it is cacheable — the cel cache's shape in
the interpreter. Up to **~5% of a cycle**; not costed. **(c) Direct page:** §6(4).

**7.6 AC-6, AC-10, AC-11's re-baseline and AC-12's three suite-resident checks are UNMET, all for one
reason** (§4F). ★ **I have not established that the tree is otherwise green**, only that the one red
is a false positive in the detector. **Do not read this report as a green suite.**

**7.7 The parser arm announces nine titles and reports eight.** Its header printed *"all 9 gate
titles"* and the summary listed 8 rows, with Kingquest1 absent and Kingquest2 running 508 cycles of
600. **Noticed, not investigated** — it is the same disease as §4E and §4F and it is not this task's.
**§8.3.**

### 8 — Follow-up candidates

1. ★★★★★ **Rule on `fix_mojibake.py`** (§4F). It is red on a clean tree **and its repair is
   destructive** — the two conditions that get a gate switched off and that corrupt a file while
   someone follows its advice. **Highest priority on this list.**
2. ★★★★ **A gate arm in which a controller is set**, which would license E2 (0.251%) and, more
   importantly, **would make `vmtest_controller` gated at all**.
3. ★★★ **The parser arm's 9-announced/8-run** (§7.7).
4. ★★★★★ **The operand-fetch contract** (§7.5a) — the largest single item in the interpreter,
   ~2.5% of a cycle, needs a ruling on the handler contract.
5. ★★★★ **The skip-walk cache** (§7.5b), ~5% of a cycle, invariant-work removal of the cel cache's
   shape.
6. ★★★★★ **Composite is 59.4% of a steady cycle and is now the larger half.** Whatever comes next
   should be argued against that, not against P6.101's ordering.
7. **Moving-window figures** (§7.3), and the five-way split re-derived on a second room and title.
8. **Carried, unchanged:** the cel cache in the gated arms; the room cache; `CP_SAVE` asserted
   undefined; the other `sz = 0` probe rows (`pic`, `res`); `prp_priority`'s hoist; the static/regular
   sprite split; `sierra_rooms.py`'s `min_fdc` floor; `MAP_PRI_BANDS` (**`memmap.inc` is a §6 stop
   trigger; forty-eighth task**).

### 9 — User interaction during task
§6A was performed: the findings were presented to Jay in plain terms — the reconciled figure, the
steady-state split, the three candidates with E2 refused and E3 rejected, the failed dispatch
premise, and §4F's blocked suite — **before this report was written.**

**Jay's response, in his words:** *"stop. right your previous report and then continue on this new
dispatch"*, accompanied by **Spike S-01 (rev B)**.

★★★★★ **He did not rule on §4F.** The mojibake detector therefore stays **red on a clean tree with a
destructive repair**, recorded in `gates.manifest` and carried as §8.1. ★★ **Nothing in the findings
was corrected or redirected**, and no conclusion in this report changed as a result of the exchange.
★ The strategy discussion that preceded this task is recorded in §6's route accounting, because two
of its figures are superseded by §4A.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-26-the-repair-destroyed-what-the-check-flagged.md`
- `seeds/AGI/live/2026-09-26-the-share-and-the-median-are-different-questions.md`

### 11 — Commit
`fbd04f7` — *P6.103 the interpreter, decomposed: the cost is the dispatch, not the handlers*
(pushed to origin/wip as `677117b..fbd04f7` before this report).
