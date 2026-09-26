## Form B Report — T-P0-156 / P6.102 — The interpreter's per-opcode cost: take the 4.2%
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-26 (no dispatch document — Jay's direct instruction *"take the 4.2% and then we'll talk
strategy"*, following *"work interpret"* → *"measure the opcode count"* → *"cost noth also consider
possibly switching to lookup tables instead af diret lookup/if loops"*). HEAD at start `b8a5372`
(wip), clean apart from an untracked `harness/tools/opcount_ref.py` written under the preceding
instruction. HEAD at report `ca698e6`. `git status` clean except untracked
`coco_agi.code-workspace`, which is an editor file and not mine to commit.

★ **This task has no dispatch and therefore no dispatch-supplied AC list.** The ACs below are the
four costed changes plus the two verification obligations (§2W, the gate), stated so the verdict has
something to check.

### 1 — Summary
**306 opcodes per cycle is what the LOGIC requires**, confirmed on the oracle and invariant across
110 cycles: 138 `run_logic` fetches + 168 test-handler dispatches. So the volume is necessary and
the target is per-opcode cost. Six changes were costed at ~4.2% of a cycle; **four were taken, one
was rejected with its arithmetic, and one was substituted for something cheaper and better.**
Realised: **`interpret` 0.12694 → 0.11908 s/cycle, −6.19% of the stage = 2.69% of a cycle**, with
the build **9 bytes smaller**. The nine-title VM gate is 9/9 PASS with 0 divergent cycles of 600
after every group and again at the end. **The §2W work found something larger than the task: the
project's general fault arm passes on 3 of its 9 titles, and the first title in the list — the one a
spot-check reaches for — is one of them.**

### 2 — Files modified
- `src/harness/vm_core.s` — groups B, C, D; the rejected hoist's arithmetic recorded at `vm_su_lp`;
  two fault arms for group D.
- `src/harness/vm_state.s` — group A (`vm_bitmask`, `vm_getflag`, `vm_setflag`).
- `harness/tools/p3b_show.ps1` — `-MarkSlow` added; the four before-arms documented as a block.
- `harness/tools/vm_run.ps1` — `VM_MARK_FAULT` / `VM_MARK_FAULT_HALT`; **`VM_FAULT`'s measured
  scope**.
- `harness/tools/gates.manifest` — the fault-arm-scope finding as a standing note.
- `harness/tools/opcount_ref.py` — NEW (written under *"measure the opcode count"*, committed here).

Explicit-path staging only.

### 3 — Reasoning

**3.1 The opcode volume is necessary — authority: the oracle (ScummVM-derived reference, tier 3).**
`opcount_ref.py` counts on the reference rather than on our 6809 leg, because that answers *how many
opcodes the logic requires* rather than *how many we happen to run*. KQ1 room 1, cycles 11–120:
**138 `run_logic` fetches + 168 test-handler dispatches = 306 per cycle, min = max = mean** — an
invariant, not an average. **Believed original, not a ScummVM normalisation** (§2.1): this is the
logic's own instruction count, a property of the game data, and no interpreter choice is involved.
The consequence is that there is nothing to remove, and the target is **512 CPU cycles per AGI
opcode**.

**3.2 §2H's three checks, on the reference.** (1) *A second mechanism for a different object class?*
Yes, and it matters: `run_logic` fetches and in-expression test opcodes are **separate populations**
counted by separate machinery, and conflating them is what produced this task's first wrong number.
(2) *The calling routine, not the implementation.* The 168 figure comes from wrapping every handler
in the VM's own `tests` table, i.e. from the dispatch site; the caller is `test_if_code`, which runs
116 times a cycle — so **~1.45 test opcodes per expression**, which is what makes per-opcode overhead
dominate. (3) *Grep the prior reports for the same subsystem before citing one.* P6.102's profile
estimated ~215 test opcodes per cycle from a sampled share divided by a hand-counted loop cost; the
measured figure is **168**. The estimate was 28% high and its method multiplied two approximations.
**The measurement supersedes it; both are printed by the tool so the difference stays visible.**

**3.3 The first number was wrong and the tool says so.** The first cut reported **4,883** opcodes per
cycle from an instruction-pointer delta across each expression. That delta includes
`skip_instructions_until`'s advance past a whole false branch, so it counts **skipped body bytes as
evaluated test opcodes**. The exact count comes from wrapping handlers. `opcount_ref.py` prints both
and labels the span *"NOT a count"* — §2W.3's rule that a diagnostic must not be able to launder a
wrong answer into a plausible one.

**3.4 Twice the correct form was already in the same file.** Group B's ordering is spelled out twelve
lines below the defect at `vm_su_lp`, with comments giving the reason. Group D's single-compare trick
is spelled out forty lines below at `vm_skip_instruction`, in capitals. **The recurring defect is not
ignorance of the 6809 — it is that a routine written early never adopted what a later one learned.**
★ And `vm_rl_loop` still carries a comment asserting the spill constraint *as if it were inherent to
the processor*; it is a consequence of the ordering, and writing it down as a law is what protected
it. **Left alone in this task and flagged in §8** — it is a third site, not a fifth measurement.

**3.5 Sibling claims.** None. No `src/hal/` or `src/engine/` file was touched, so §2M's sync check
and §2N's census are both N/A, and no POP/Karateka ref is cited.

### 4 — Verification (AC-by-AC)

**AC-1 [class: state-comparable] The opcode volume is what the logic requires, measured on the
reference.** — `opcount_ref.py`, KQ1 room 1, cycles 11–120 (110 cycles): 138.0 `run_logic` fetches
per cycle (median 138, min 138, max 138, deciles all 138); 168.0 test handler dispatches (min 168,
max 168); 116.0 expression evaluations. **Total 306.0, invariant.**

**AC-2 [class: state-comparable] Group A — the flag mask table.** `vm_getflag`/`vm_setflag` index an
8-byte `vm_bitmask` instead of shifting 1 left by the bit number: **10 cycles flat, was ~47 mean and
89 worst.** `vm_setflag` fetches the mask *before* X is committed to the flag byte, which avoids a
`pshs`/`puls x` pair. — **`interpret` 0.12343 → 0.12051 s/cycle, −2.37% of the stage = 1.01% of a
cycle** (before arm `-FlagShiftLoop`, 16783 B; after 16779 B).

**AC-3 [class: state-comparable] Group B — advance ip while D still holds it.** The opcode is no
longer spilled to `vm_op` across a second `ldd vm_ip`; the spill now exists only under `VM_TRACE`,
which is all it was ever for. Verified by grepping **every** reader of `vm_op` in the file: none
appears between the old store and the dispatch's own store. — **`interpret` 0.12401 → 0.12212,
−1.52% of the stage = 0.65% of a cycle** (before arm `-TicSlow`, 16795 B). Predicted 0.64%.

**AC-4 [class: state-comparable] Group C — `abx` instead of building D.** `vm_skip_instruction` holds
the opcode in B from the start and indexes with `abx` (3 cyc) rather than `clra`/`tfr a,b`/`ldb
vm_op`/`leax d,x` (21 cyc). **The old body's `tfr a,b` was dead the instant the `ldb` after it
landed.** — **`interpret` 0.12212 → 0.12051, −1.32% of the stage = 0.56% of a cycle** (before arm
`-SkipSlow`). Predicted 0.60%.

**AC-5 [class: state-comparable] Group D — one unsigned compare for four markers.** Three of the four
are ≥ `$FC`, and the test is ordered so the common case ends on a **short branch taken**: `cmpa`(2) +
`bhs` not-taken(3) + `tsta`(2) + `bne` taken(3) = **10 cycles, down from 28.** `$FE` is not a marker
and falls through to the same `vm_test_unimpl` path it took before. — **`interpret` 0.12051 →
0.11908, −1.19% of the stage = 0.50% of a cycle** (before arm `-MarkSlow`, 16779 B; after 16790 B).

**AC-6 [class: state-comparable] The aggregate, and the four compose additively.** All four slow vs
all four fast: **`interpret` 0.12694 → 0.11908 s/cycle, −6.19% of the stage = 2.69% of a cycle.**
Build **16799 → 16790 bytes** (A/B/C remove 20, D adds 11). ★ The four individual figures sum to
**2.72%** against an aggregate of **2.69%** — additive to within 0.03 points, so **nothing is
double-counted and no pair interacts** [P6.84: a share is not a cost, and each change is measured
against its own before arm rather than inferred from a total].

**AC-7 [class: state-comparable] Behaviour is unchanged.** VM gate, nine titles, 600 cycles,
byte-identical state per cycle, exclusion set EMPTY: **9/9 PASS, 0 divergent cycles of 600** — run
after group B, after group C, after group D, and again clean at the end after the fault arms were
added. Kingquest1/2/3, SpaceQuest-1/-2, PoliceQuest1, larry1, BlackCauldron, MixedUpMotherGoose.

**AC-8 [class: byte-comparable] The instrument discriminates, and only what should move moved.** On
every one of the six builds, `pace(wait)` 0.0728 s, `sprites` 0.3377 s, `roomcheck` 5.4719 s and
`composite` 14.0100 s are **identical to four decimal places**; only `interpret` differs. A repeat
run of the after arm reproduced `interpret` 0.12051 / SUM 0.28628 exactly, so the timer is
deterministic, not noisy. The arms are distinct by binary size (16779 / 16783 / 16790 / 16795 /
16799). The picture-1 refusal and the 95.7% cel-cache hit rate appear **on both sides of every
pair** and predate this task — checked rather than assumed, because a result should not be reported
clean while an unexplained refusal sits in the log.

**AC-9 [class: eye-gated — NOT RUN, and it is not owed] The median moved, and its size is an
artefact.** 0.2169 → 0.2003 s/cycle, **4.61 → 4.99 cycles/second.** That is **13 frames to 12**: the
cycle was barely over 12 frames and now fits. **The quantised median reads +8.2% where the real gain
is 2.69%, and reporting the 8.2% would repeat P6.101's error in a new form.** ★ Per §4A this is a
component task and not an integration task — no two independently-gated subsystems are being
assembled — so the eye gate is not the first AC here. **But a frame boundary was crossed, which is
the class of change Jay can see, so it is offered in §8.**

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
AGGREGATE BEFORE  (-FlagShiftLoop -TicSlow -SkipSlow -MarkSlow)   p3b_probe: 16799 bytes
    median 0.2169 s/cycle = 4.61 cycles/second
       min 0.0668  p25 0.2003  median 0.2169  p75 0.2336  p90 0.2503  max 6.1246
       pace(wait)   0.0728 s total   0.00061 s/cycle    0.2%  (120 entries)
       interpret   15.2322 s total   0.12694 s/cycle   43.4%  (120 entries)
       sprites      0.3377 s total   0.00281 s/cycle    1.0%  (120 entries)
       roomcheck    5.4719 s total   0.04560 s/cycle   15.7%  (120 entries)
       composite   14.0100 s total   0.11675 s/cycle   40.3%  (120 entries)
       SUM         35.1247 s total   0.29271 s/cycle
    final room 1, sprites 4, err 0, status=$00

AGGREGATE AFTER   (no switches)                                   p3b_probe: 16790 bytes
    median 0.2003 s/cycle = 4.99 cycles/second
       min 0.0501  p25 0.2003  median 0.2003  p75 0.2169  p90 0.2336  max 6.1079
       pace(wait)   0.0728 s total   0.00061 s/cycle    0.2%  (120 entries)
       interpret   14.2902 s total   0.11908 s/cycle   41.8%  (120 entries)
       sprites      0.3377 s total   0.00281 s/cycle    1.0%  (120 entries)
       roomcheck    5.4719 s total   0.04560 s/cycle   15.9%  (120 entries)
       composite   14.0100 s total   0.11675 s/cycle   40.8%  (120 entries)
       SUM         34.1827 s total   0.28486 s/cycle
    final room 1, sprites 4, err 0, status=$00

PER-GROUP (each against its own before arm, same room / sprite count / cycle count):
  A  0.12343 -> 0.12051   -2.37% stage   1.01% of a cycle   (predicted 1.57%)
  B  0.12401 -> 0.12212   -1.52% stage   0.65% of a cycle   (predicted 0.64%)
  C  0.12212 -> 0.12051   -1.32% stage   0.56% of a cycle   (predicted 0.60%)
  D  0.12051 -> 0.11908   -1.19% stage   0.50% of a cycle   (substituted, see §6)
     sum 2.72%   vs aggregate 2.69%
```

```
opcount_ref.py  C:\Projects\agi-games\pc\Kingquest1 room 1, cycles 11..120 (110 cycles)
  run_logic opcode FETCHES per cycle:
     mean   138.0   median   138   min   138   max   138   total 15180
  deciles: 138 138 138 138 138 138 138 138 138 138
  if-expression evaluations (test_if_code CALLS) per cycle:
     mean   116.0   min   116   max   116   total 12760
  TEST OPCODES EVALUATED per cycle (handler dispatches -- the exact count):
     mean   168.0   min   168   max   168   total 18480
  ip SPAN across those expressions per cycle (INCLUDES skipped branches -- NOT a count):
     mean  4883.0   -- a naive delta would report this as the opcode count and be wrong
  TOTAL opcodes the LOGIC requires per cycle: 138.0 run_logic + 168.0 tests = 306.0
  BRANCH SKIPPING -- skip_instructions_until, the port's vm_su_lp:
     calls per cycle  110.0   BYTES WALKED per cycle    199.0   mean per call    1.8
```

```
vm_run.ps1 (clean, final)     === AC-2 SUMMARY ===
Kingquest1 PASS   Kingquest2 PASS   Kingquest3 PASS
SpaceQuest-1 PASS SpaceQuest-2 PASS PoliceQuest1 PASS
larry1 PASS       BlackCauldron PASS  MixedUpMotherGoose PASS
  (each: compared 600 cycles x 288 bytes, exclusion set EMPTY, divergent cycles 0 of 600)
```

```
fix_mojibake.py --check  (§2J.7, all six touched files)
src/harness/vm_core.s      clean      harness/tools/vm_run.ps1       clean
src/harness/vm_state.s     clean      harness/tools/gates.manifest   clean
harness/tools/p3b_show.ps1 clean      harness/tools/opcount_ref.py   clean
exit=0
```

`hal_sync_check.py`: **N/A — no `src/hal/` or `src/hal.inc` file was touched.**
`reg_discipline.py`: **N/A — §2N's scan window is `src/engine/**`; this task touched
`src/harness/` only, and no `$FFxx` register is named in any line changed.**

**25.1b §2W — the instruments shown able to FAIL (verbatim):**

```
-DVM_MARK_FAULT       (vm_tic_mark's OR and NOT targets swapped)
  Kingquest1 FAIL   larry1 FAIL     guest 1 cycles vs oracle 600
-DVM_MARK_FAULT_HALT  (marker boundary raised to $FD, so $FC falls into the test path)
  Kingquest1 FAIL   larry1 FAIL     guest 1 cycles vs oracle 600

-DVM_FAULT  (the project's standing arm: ble -> blt on delta == -step)
  Kingquest1           PASS     divergent cycles : 0 of 600
  Kingquest2           FAIL     divergent cycles : 188 of 600
  Kingquest3           FAIL     divergent cycles : 73 of 600
  SpaceQuest-1         FAIL     divergent cycles : 519 of 600
  SpaceQuest-2         FAIL     divergent cycles : 218 of 600
  PoliceQuest1         PASS     divergent cycles : 0 of 600
  larry1               FAIL     divergent cycles : 372 of 600
  BlackCauldron        PASS     divergent cycles : 0 of 600
  MixedUpMotherGoose   FAIL     divergent cycles : 1 of 600
```

**25.2 bundled-artifact grep:** N/A — no DECB artifact or disk image was built; this task changes
harness probe code only.

**25.3 operator-runtime-smoke:** **pending Jay.** Per §4A this is a component task, not an
integration task, so the eye gate is not owed as AC-1 — **but the median crossed a frame boundary
(13 → 12 frames, 4.61 → 4.99 cycles/s), which is the class of change Jay can see.** Offered in §8.

### 6 — Reactive deviations and route accounting

**ROUTE ACCOUNTING. I proposed six changes totalling ~4.2% of a cycle. This commit contains four of
them, realising 2.69%. Here is every difference, because a route I proposed is checked by nothing.**

1. **Groups A, B, C: implemented as described.** A came in at **1.01%** against a predicted 1.57% —
   **the prediction was 55% high and I am not treating it as noise**; the shift loop's *average* cost
   was estimated from a uniform bit distribution, and real flag numbers are not uniform. B (0.65% vs
   0.64%) and C (0.56% vs 0.60%) landed as predicted.
2. **REJECTED — `vm_su_lp`'s code-pointer hoist, estimated 0.95%.** It costs `pshs`/`puls u` (14 cyc)
   per **call** to save 6 per **iteration**, and the oracle measures **1.8 bytes walked per
   `skip_instructions_until` call over 110 calls a cycle** — about 1.5 iterations. **It is a loss.**
   ★ This is P6.98's lesson (*per-call overhead dominates short batches; an inner-loop cycle count is
   not a per-unit cost*) **firing before the change rather than after it**, for the first time. The
   arithmetic is recorded in the source at `vm_su_lp`, not only here.
3. **SUBSTITUTED — the 256-byte opcode class table, estimated 0.40%, became group D.** Two
   corrections, and the first is mine:
   - **My stated reason for dropping it was false.** I said region B lacked space and that region A
     had 110 bytes. **Region A has 1,081 bytes free** — `P3_CODE_END $5BC7` against
     `MAP_RESERVED_END $6000`, read from the map of the build being measured, not from a comment. The
     110 was a stale figure I was carrying. **Had I not checked, I would have dropped a change for a
     reason that did not exist.**
   - **The table is the wrong instrument anyway.** It needs `tfr`/`abx`/`ldb` and still costs ~21
     cycles. Group D's single unsigned compare costs **10**, and **no bytes at all**. It delivers
     0.50% against the table's estimated 0.40%.
4. **Not proposed, and added: two fault arms and a `gates.manifest` note**, under §2W. **This is
   where the task went over its stated scope, and the reason is in §7.1.**
5. **`opcount_ref.py` was written under the preceding instruction (*"measure the opcode count"*) and
   is committed here** rather than in a commit of its own, because it is the evidence for AC-1.

**Realised 2.69% against the 4.2% Jay approved. The 1.51% shortfall is: 0.95% rejected as a measured
loss, and 0.56% of estimation error spread across A (−0.56) and the D-for-table swap (+0.10).**
★ **No part of the 4.2% remains available to take.**

### 7 — Uncertainty flags

**7.1 ★★★★★ `-DVM_FAULT` PASSES ON THREE OF THE NINE GATE TITLES, AND THIS IS THE LARGEST THING IN
THE REPORT.** I ran it on **Kingquest1 alone** to show the divergence counter could go nonzero. It
printed **PASS, byte-identical, 600 cycles.** `vm_run.s:973` had already written down what that would
mean: *"NAMED, so a green run with VM_FAULT set would itself be the finding."* Across all nine it is
**6 FAIL / 3 PASS** — the injected `ble`→`blt` needs `delta == -step`, and Kingquest1, PoliceQuest1
and BlackCauldron never reach it in 600 cycles.
- **A fault arm's scope is part of its definition**, exactly as `vm_run.ps1`'s own header says the
  **gate's** scope is. Same disease, other face — there a gate ran a third of its corpus; here a
  fault is unreachable on a third of it while the message promises failure unconditionally.
- **Kingquest1 is the worst possible default for it**: first in the list, the one a spot-check reaches
  for, and one of the three that cannot see it.
- **MixedUpMotherGoose catches it on 1 divergent cycle of 600.** A corpus one title smaller could
  have retired a live arm as dead.
- Scope now recorded in the arm's own message and in `gates.manifest`. **What I have NOT done is
  audit the project's other fault arms for the same defect** — that is §8.1 and I believe it is the
  most valuable follow-up on the list.

**7.2 Group D's fault arms both fail by HALTING, not by diverging, and I believe that is correct
rather than a weakness.** A misrouted marker desynchronises the instruction stream; the stream then
reads an operand as an opcode; `vm_op_unimpl` halts by name. **AC-5 exists precisely so a desync
names itself instead of diverging silently hundreds of cycles later.** So this fault class has no
plausible-but-wrong-state signature. ★ **The consequence for the evidence: the green gate on §4D's
path is licensed by the gate catching a desync within one cycle, twice, by two different faults — it
is NOT licensed by having seen a wrong-flag divergence on that specific path.** Those are different
strengths and I am not going to blur them.

**7.3 The `$FE` fall-through is UNTESTED by the gate.** `$FE` as a test opcode is reachable in the
code and, as far as I can tell, used by no game in the corpus. Its behaviour is unchanged **by
construction** (it takes the same `vm_test_unimpl` path through `vm_tic_mark`) and by reading, **not
by measurement.** `[no-ref: no gate title executes test opcode $FE — discharge by a targeted probe
or by accepting it as unreachable]`.

**7.4 The A-group prediction was 55% high** (predicted 1.57%, measured 1.01%) and I have not chased
why beyond the uniform-bit-distribution hypothesis above. It does not affect the delivered figure —
the measurement is the finding — but it means **my cycle-counting estimates for this subsystem
should be read as leads, not findings** (§8's rule on unverified arithmetic).

**7.5 The figures are from one room, one title, 120 cycles.** KQ1 room 1 with 4 sprites. ★ **L-85's
warning applies in its own terms: "45/45" was a claim about 45 pictures, and "2.69%" is a claim about
this room.** The opcode *volume* is invariant across the 110-cycle window, but the *mix* of opcodes —
and therefore how much each group is worth — is not shown to be stable across rooms or titles.

**7.6 `vm_rl_loop` still has group B's defect**, at `vm_core.s:89/109/119`, with a comment asserting
the constraint as inherent. Not touched: it is a third site and this task had already made four
measured changes. §8.2.

### 8 — Follow-up candidates

1. ★★★★★ **Audit every fault arm for reachability, and record each one's scope in its own message.**
   §7.1 found one live arm that reads as dead on a third of the corpus. `vm_run.ps1` alone declares
   seven. **This is the highest-value item I have surfaced in several tasks** — a fault arm believed
   dead gets deleted, and then the gate it licensed enforces nothing.
2. **Apply group B's ordering to `vm_rl_loop`** and rewrite the comment that states the spill
   constraint as a property of the 6809 (§7.6). ~0.3% by analogy — **unverified arithmetic.**
3. **Inline `vm_skip_instruction`'s operand step into `vm_su_lp`** to drop the `jsr`/`rts` (12 cyc) on
   ~110 calls a cycle. This is the change the rejected hoist was reaching for, and unlike the hoist
   its saving is **per call**, which is the unit that matters here. Not costed.
4. **An eye gate on the frame-boundary crossing** (§4A / 25.3): 13 frames → 12. Whether 4.99 vs 4.61
   cycles/s is perceptible is Jay's to say, not mine, and it is the only part of this task's result
   that a person can see.
5. **Re-measure the four groups in a second room and a second title** (§7.5), to learn whether the
   per-group ranking is a property of the interpreter or of KQ1 room 1.
6. **Carried, unchanged:** the cel cache in the gated arms (open across ten tasks now); the room
   cache (0.237 s vs 6.16 s, ~5 s a door); a gated scene with overlapping sprites; assert `CP_SAVE`
   is undefined; audit the other `sz = 0` probe rows (`pic`, `res`); `prp_priority`'s hoist; the
   static/regular sprite split; `sierra_rooms.py`'s `min_fdc` floor; re-derive P6.94's load
   sensitivity on modal intervals; `MAP_PRI_BANDS` (**`memmap.inc` is a §6 stop trigger**).

### 9 — User interaction during task
Jay gave four direct instructions in place of a dispatch: *"work interpret"*, *"measure the opcode
count"*, *"cost noth also consider possibly switching to lookup tables instead af diret lookup/if
loops"*, and *"take the 4.2% and then we'll talk strategy"*. ★ **The third asked specifically about
lookup tables over if-chains, and the answer is split**: group A's lookup table replaced a shift
loop and is the largest single win (1.01%), while group D found that for the marker chain a **single
unsigned compare beats the 256-byte table** in both cycles and bytes. **So the instinct was right
about the mechanism class and the right answer was a table in one place and no table in the other.**
No question was put back to Jay; the strategy discussion he deferred is owed next.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-26-the-fault-arm-was-unreachable-on-a-third-of-the-corpus.md`
- `seeds/AGI/live/2026-09-26-the-correct-idiom-was-already-in-the-same-file.md`

Pool `main` `5cdf8bc..bc0a17a`, pushed.

### 11 — Commit
`ca698e6` — *T-P0-156 the interpreter's per-opcode cost: 2.69% of a cycle, 9 bytes smaller*
(pushed to origin/wip as `b8a5372..ca698e6` before this report).
