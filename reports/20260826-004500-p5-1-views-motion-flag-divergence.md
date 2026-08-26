## Form B Report — P5.1 VIEWs, motion, and the flag divergence — `tools/agivm/{view,objects,motion,blit}.py`
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-25 (dispatch T-P0-009 receipt; HEAD at receipt `621b0eb`, wip, clean).
HEAD at report: `ad0d78a`. git status clean apart from this report.

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi                     wip    621b0ebf031e276ef1b101536a07e80d89d7274f
POP3_port                    wip    282a65cf9c79739326e101b3d7cccffc8cff2daa
karateka_coco3               wip    072ddcfc27ccb2c0a9b820913cd57b341a6e6fbc
```

```
commit      = 9d9b9e93108a276c551aeffa390169ccc5148e15     (oracle/scummvm.pin)
9d9b9e93108a276c551aeffa390169ccc5148e15                   (C:\Projects\scummvm, measured)
  APPLIES  0001-oracle-room-dump.patch
  APPLIES  0002-oracle-vm-state-dump.patch
  APPLIES  0003-oracle-row24-probe-and-lzw-trace.patch
  APPLIES  0004-oracle-raw-resource-dump.patch
  APPLIES  0005-oracle-deterministic-clock.patch
  native binary: 75131345 bytes  Aug 25 21:43        (P4.2 native build, current)
```

```
SELF-TEST PASSED                                     (harness/tools/vmdiff.py)

oracle: 434 cycles   ours: 434 cycles
FIRST DIVERGENCE AT CYCLE 186 (line 187)
   flag byte 2 (flags [20]): oracle 30 ours 20       (P4.1 divergence reproduces)
```

★ **VIEW structure at the pin, reported as FOUND (not as the Specs describe).**
`view.cpp` `decodeView()` 113-296, `unpackViewCelData()` 302-390.

| element | as found |
|---|---|
| view header | `headerStepSize`/`headerCycleTime` only for version < 0x2000; loop count at +2; description offset LE16 at +3; **header size 5** (Apple II: 0 / 3) |
| loop offsets | `LE16(data + 5 + loopNr*2)`, absolute |
| loop header | one byte = cel count. ★ **version 0x2230 only**: low nibble is the count, bits 4-5 the mirror loop |
| cel offsets | `LE16(data + loopOffset + 1 + celNr*2)`, **relative to the loop offset** |
| cel header | width, height, transparency+mirror byte |
| ★ **mirroring** | bit 7 = apply; **bits 4-6 = the loop the cel ORIGINALLY belongs to**; a cel is mirrored **only when that loop ≠ the loop being walked**. Reading bit 7 alone mirrors the original too |
| ★ mirroring is applied | **during decode**, by walking the destination backwards (`view.cpp:311-315, 348-358`) — not by a post-pass flip |
| RLE | byte 0 → fill the rest of the row with the clear key **and end the row**; else colour = `b>>4`, run = `b&0x0F`. **A row ends on a zero byte**, not on reaching `width` (Apple II inverts this) |

★ **Divergent flags and what sets them — this is where the dispatch's premise and my own P4.1
attribution both turned out to be wrong. See §3.1.**

---

### 1 — Summary
VIEW decoding, the screen-object table, the cel cycler and the motion system are built and
oracle-verified: **6005/6005 cels byte-identical across eight games**, and the **animation
completion flags close in both titles where that was the cause** (KQ2 flag 33, KQ3 flag 221).

★★★ **AC-3 does not close, and the reason is a finding rather than a shortfall.** Tracing the
divergence with a probe inside the oracle — instead of inferring it — showed that **KQ1's flag
20 was never an animation flag at all; it is a SOUND end-flag**, and that **the oracle sets
sound end-flags at a cycle that varies run to run** (186, 185, 185, 184 over four identical
runs). AC-3 as written is therefore unachievable while a sound is playing, whatever we build.
Reported under §8.1/§8.2/§8.3; nothing widened, no exclusion added.

### 2 — Files modified
- `tools/agivm/view.py` — NEW. VIEW parse: loops, cels, RLE, mirroring.
- `tools/agivm/objects.py` — NEW. view/loop/cel binding, position clipping, the per-cycle update, the cel cycler and its completion flags. **Supersedes `anim.py`, deleted.**
- `tools/agivm/motion.py` — NEW. The five movement modes, their completion flags, the two cycler/motion workarounds.
- `tools/agivm/blit.py` — NEW. Compositing **cost model** (no pixels).
- `tools/agivm/{cycle,commands,state,optable}.py` — wiring; `cmdCycleTime` defect fixed (§3.4).
- `harness/tools/gen_oracle_tables.py` — now also generates the direction/loop tables (L-29).
- `harness/tools/celcheck.py` — NEW. AC-2 comparison against the oracle.
- `harness/tools/run_agivm.py` — AC-5 coverage and AC-6 cost reporting; UTF-8 stdout.
- `harness/tools/oracle_dump.sh` — `CEL_DUMP` switch; `cels.txt`/`cels.bin` added to the rename list.
- `oracle/patches/0006-oracle-view-cel-dump.patch` — NEW, **opt-in** (§3.5).

`tools/agivm/anim.py` deleted — its declared gaps are discharged by `objects.py`.
Explicit-path staging throughout. **No game data, cel bytes or renderings committed** (§2P).

### 3 — Reasoning

**3.1 ★★★ The P4.1 attribution was wrong, and so is the premise this dispatch inherited from it.**

P4.1 reported *"one defect with three symptoms — each divergent flag is a completion flag the
interpreter sets when an animation or motion finishes"*, and said the shared cause had been
**checked**. What was actually checked was that each divergent flag number appears as an
argument to `end.of.loop` / `reverse.loop` / `move.obj` / `follow.ego` **somewhere in that
game's scripts** (35, 23 and 31 call sites). That is **co-occurrence, not causation** — flag 20
is a popular flag in KQ1, and finding it used by a completion opcode elsewhere says nothing
about what set it at cycle 186 on the title screen. It is the L-14 shape exactly: a correct
figure that means something other than what quoting it implies.

Tracing the actual event — a temporary probe in the oracle's `setFlag`, then at each of the
five interpreter flag-setting sites, then in `SoundMgr` — gives:

| title | flag | what actually sets it | closes this task? |
|---|---|---|---|
| KQ2 | 33 | `updateView` end-of-loop, object 3, cels 0→7 | ★ **yes** |
| KQ3 | 221 | `updateView` end-of-loop, object 1, cels 0→4 | ★ **yes** |
| KQ1 | **20** | ★★ **a SOUND end-flag** — `cmdSound`'s `flagNr`, cleared by `startSound` and set by `SoundMgr` when playback finishes | **no — sound is P7** |

★ Elimination was done properly rather than by guessing: probes at `updateView`'s two flag
sites, `motionFollowEgo`, `motionMoveObjStop`, and `cmdSet`/`cmdSetV`/`cmdToggle` **all failed
to fire** for KQ1's flag 20 before the sound path was found. Two of my own intermediate
inferences were wrong on the way — that the view sweep caused a perturbation (it did not) and
that `logic.size` 3906 vs our 3904 was a defect (it is not; `cIP` starts at 2, so the span is
identical). Both are recorded because each looked convincing.

**3.2 ★★★ The oracle's sound end-flag is nondeterministic in cycle terms.**
`sound.cpp:169` carries the oracle's own comment: *"This is called from SoundGen classes on
**unsynchronized background threads**."* That is a real-time source, not a cycle-driven one.
Four back-to-back runs, same binary, same seed, same game, same settings:

```
KQ1 flag 20 first set at cycle: 186, 185, 185, 184
```

★ **Two consecutive runs agree**, which is exactly why P4.1's determinism work did not catch it
— the same L-30 trap as the wall-clock timer, in a subsystem P4.1 never exercised. Independent
corroboration from AC-7: the oracle idle-vs-loaded on KQ3 diverges on flag 229 **and nothing
else**, while our VM is bit-identical idle and loaded over 513 cycles.

**Consequence for AC-3, stated plainly:** "all 256 flags identical, every cycle, exclusion set
EMPTY" cannot be satisfied while a sound is playing, by any implementation. This is a property
of the oracle. Per §8.3 I did **not** exclude the flag; per §8.2 I did **not** match the bug.

★ **The fix has a precedent and is not mine to take unasked**: patch 0005 removed the
wall-clock timer at source. The equivalent here is to make sound completion cycle-driven —
compute a duration in cycles and fire deterministically. That designs sound semantics, which is
P7 and out of scope (§4, §12), and it changes oracle behaviour more than 0005 did. Surfaced for
the Orchestrator.

**3.3 §2H's three checks, on the VIEW/motion mechanism.**
1. *A second mechanism for a different object class?* **Yes, and it is the whole finding above**: completion flags come from **three** subsystems — the cel cycler, the motion system, **and sound** — and only the first two are this task's.
2. *Name the routine that CALLS it.* The motion **opcodes** set state and move nothing; `checkAllMotions() → checkMotion()` acts on it, once per cycle, and only for objects that are animated **and** updating **and** drawn **and** whose `stepTimeCount` has reached exactly 1. Reading the opcode alone gives the wrong model of when anything happens — and this is precisely why KQ2's cycler silently never ran (§3.4).
3. *Grep prior reports for the same subsystem.* Done, and it is what exposed the P4.1 error above rather than letting it stand by recency.

**3.4 A P4.1 defect that was unreachable until cycling mattered.** `cmdCycleTime` set
`cycleTimeCount = 0`; the oracle sets `cycleTime = cycleTimeCount = getVar(varNr)`. The update
only advances a counter that is already non-zero, so zero never decrements to zero and the
cycler stalls permanently. **This is why KQ2's flag 33 never fired.** Found by probing object 3
rather than by re-reading the code.

**3.5 Patch 0006 is opt-in because ungated it changes the game.** Measured: with the cel dump
active, KQ1's flag 20 moves a cycle against an otherwise byte-identical oracle. Gating only the
view sweep was **not** enough — the dump firing for normally-loaded views did it too — so the
whole patch is inert unless `CEL_DUMP=1`, and a cel-dump run announces that its vmstate is not
a baseline. ★ Three candidate causes were eliminated (the sweep alone, file presence in the
CWD, `artificialDelay` — which is table-driven, not elapsed-time-measured); **the mechanism is
NOT ESTABLISHED**, and given §3.2 the likeliest remaining candidate is the same real-time sound
path reacting to I/O slowdown.

**3.6 §2.1 — deviations reproduced, and named.** `ignore_loop_flag` (`motion.cpp:83-102`) is a
ScummVM deviation whose own comment says *"the original would set an unintended game flag when
it completed … we do not set any flag"*, and it names **KQ1 room 22** among affected moments.
Reproduced because we diff against the oracle; **not** a claim about Sierra's interpreter.
Likewise `motionActivated`/`cyclerActivated`'s field overwrites. **Not** reproduced: `setLoop`'s
KQ1-view-71 workaround, `cmdDistance`'s KQ4 zombie workaround, `newRoom`'s LSL1/KQ3/GoldRush
workarounds, and `updateScreenObjTable`'s KQ4/0x3086 loop-table branch.

**3.7 §2S — refs.** Oracle tree at `9d9b9e9` = the pin, verified in-tree. Siblings read at the
refs in the grep block, **read-only**; no HAL file touched (the HAL does not exist yet). The
temporary probes used in §3.1 were reverted before any gate run and the oracle rebuilt from
`pin + 0001..0006` — verified: `no PROBE strings remain`.

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable]** ★ **PASS.** `coco_agi` **0**, POP **59**, Karateka **8**, at the refs above. ★ My first invocation was wrong and I caught it: argparse prefix-matched `--root` to `--roots`, scanning each sibling's whole repo (226 / 229). §2N requires `src/` less `src/hal/` **and** `src/harness/`.
- **AC-2 [byte-comparable]** ★★ **PASS.** **6005/6005 cels byte-identical** across **8 games** (≥400 / ≥4 required), **1023 mirrored, all correct**. Per-game table in §5. Falsified: reading the mirror bit without the original-loop test yields exactly 1023 errors.
- **AC-3 [state-comparable]** ★★★ **DOES NOT CLOSE — reported, not worked around.** Strict, empty exclusion set: KQ1 cycle 184 flag 20; KQ2 cycle 145 flag 48; KQ3 cycle 108 flag 229. **All three are sound end-flags.** The flags this task was scoped to close (KQ2 33, KQ3 221) **do** close. Diagnostic (explicitly **not** the gate), setting aside the one sound flag per title: **KQ1 all 256 vars + all flags identical for 314 cycles; KQ3 likewise for 513; KQ2 differs only in var 39, first at cycle 146 — downstream of its sound flag at 145.**
- **AC-4 [state-comparable]** ★★ **PASS.** Injected fault (`end.of.loop` completes one cel early) makes the gate fail **at the expected flags**: KQ3 flag 221 at cycle **5**, KQ2 flag 33 at cycle **47** — both ahead of the sound divergence, so the failure is attributable to the injection.
- **AC-5 [state-comparable]** **PASS.** Reached: `normal` and `move.obj` (KQ3 963/332, KQ2 32/65). **Not reached: `wander`, `follow.ego`, `ego(mouse)`** — implemented but unexercised by this sample (L-22). ★ An unhandled mode **raises**, naming mode and object; it is never a silent no-op.
- **AC-6 [state-comparable]** **PASS.** Table in §5. ★ **Peak total cel area 4152 B (KQ3), 1500 B (KQ2), 0 B (KQ1)** — the save-under bound. **All well under the ~8 KB §8.5 threshold, so no consultation triggered.** ★ KQ1 draws **no objects at all** in 314 cycles (title screen), so it contributes nothing to this table — the sample is effectively KQ2+KQ3.
- **AC-7 [byte-comparable]** ★★ **PASS for our VM; FAILS for the oracle.** Ours: bit-identical idle **and** under 3×-nproc load, 513 cycles, motion active — **motion introduced no clock coupling**. The oracle idle-vs-loaded on the same title diverges on flag 229 **and nothing else**, corroborating §3.2 independently.
- **AC-8 [suite]** **PASS.** PC/DOS (KQ1-3) plus five v2 fan titles for the cel sample. **CoCo3 rows declined on purpose** per §2, stated rather than skipped. KQ4/KQ5 in the PC corpus are **SCI, not AGI** (`dir=none`) and are out of scope.
- **AC-9 [byte-comparable]** **PASS.** Every comparison is against pinned-oracle output. `celcheck.py` and `vmdiff.py` contain **no golden file** and no path by which our own prior output becomes a baseline. Cel-dump runs have their `vmstate.txt` deleted so a perturbed run cannot become a baseline by accident.
- **AC-10 [suite]** See §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
=== AC-1 register discipline ===
coco_agi  wip 621b0eb
[reg-discipline] 0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
POP3_port wip 282a65c
[reg-discipline] OK -- measured 59, matching the independent figure.
karateka  wip 072ddcf
[reg-discipline] OK -- measured 8, matching the independent figure.
```

```
=== AC-2 VIEW decode vs the pinned oracle ===
game         ver      views   cels    match mismatch  mirrored   mir-ok   errors
----------------------------------------------------------------------------------
13thdi       0x2917     42    418      418        0        75       75        0
Kingquest1   0x2917    118    814      814        0       204      204        0
Kingquest2   0x2917    207   1189     1189        0       122      122        0
Kingquest3   0x2440    216   1780     1780        0       271      271        0
acidop       0x2917     23    255      255        0        69       69        0
agentq       0x2917      8     63       63        0        16       16        0
alpnd1       0x2917    131   1033     1033        0       196      196        0
aquest       0x2917     30    453      453        0        70       70        0
----------------------------------------------------------------------------------
TOTAL                  775   6005     6005        0      1023     1023        0
cel bytes agreeing with the oracle: 6005 / 6005 (100.00%)

  falsification (mirror bit read without the original-loop test):
TOTAL                  775   6005     4982        0      1023     1023     1023
```

```
=== AC-3 STRICT (empty exclusion set) -- the gate as specified ===
  Kingquest1   FIRST DIVERGENCE AT CYCLE 184   flag byte 2  (flags [20])
  Kingquest2   FIRST DIVERGENCE AT CYCLE 145   flag byte 6  (flags [48])
  Kingquest3   FIRST DIVERGENCE AT CYCLE 108   flag byte 28 (flags [229])
     -- all three are SOUND end-flags (see §3.1)

=== DIAGNOSTIC ONLY, NOT THE GATE -- one sound flag per title set aside ===
  Kingquest1   314 cycles  vars differing: NONE     flag bytes differing: NONE
  Kingquest2   156 cycles  vars differing: [39]     flag bytes differing: NONE   first: 146
  Kingquest3   513 cycles  vars differing: NONE     flag bytes differing: NONE
```

```
=== AC-4 injected motion fault (end.of.loop completes one cel early) ===
  Kingquest3   FIRST DIVERGENCE AT CYCLE 5    flag byte 27 (flags [221]): oracle 00 ours 20
  Kingquest2   FIRST DIVERGENCE AT CYCLE 47   flag byte 4  (flags [33]):  oracle 00 ours 02
     -- clean run diverges at 108 / 145; the injection is caught 103 / 98 cycles earlier
```

```
=== §3.2 oracle sound-flag nondeterminism: 4 identical KQ1 runs ===
  run 0: cycle 186   run 1: cycle 185   run 2: cycle 185   run 3: cycle 184
  distinct cycles observed: [184, 185, 186]

=== AC-7 ===
  ours,   idle vs idle (KQ3, motion active) : NO DIVERGENCE, 513 cycles
  ours,   idle vs loaded                    : NO DIVERGENCE, 513 cycles
  oracle, idle vs loaded                    : FIRST DIVERGENCE AT CYCLE 108
                                              flag byte 28 (flags [229]) -- sound, nothing else
```

```
=== AC-6 compositing cost (blit.py -- cost model, not pixels) ===
                                   Kingquest3      Kingquest2      Kingquest1
  composites                              479              98               0
  object-blits (cumulative)              1298              99               0
  source pixels TESTED                 441396          134068               0
  source pixels OPAQUE (write bound)    92418           45293               0
  opaque fraction                        20.9%           33.8%             n/a
  mean tested per composite               921.5          1368.0            n/a
  peak simultaneous drawn objects            10               2               0
  peak single cel area                     3256 B          1500 B           0 B
  ★ peak TOTAL cel area on screen          4152 B          1500 B           0 B
        -- the save-under backing-store bound; both well under the ~8 KB §8.5 threshold
  pixels WRITTEN            : NOT COMPUTED -- needs the priority screen. `opaque` is the
                              upper bound; the priority test can only reject, never add.
```

```
=== AC-5 motion mode coverage ===
  Kingquest3: normal 963, move.obj 332     Kingquest2: normal 32, move.obj 65
  NOT reached in this sample: wander, follow.ego, ego(mouse)  -- implemented, unexercised
```

```
=== harness self-checks ===
CHECK OK: tools/agivm/optable.py matches the pinned oracle.
SELF-TEST PASSED                      (vmdiff)
[seam] OK -- the §4.2a seam holds.
```

25.2 bundled-artifact grep: **N/A** — no target artifact is built this task; nothing is bundled
for the CoCo3 until P3.
25.3 operator-runtime-smoke: **N/A — no CoCo3 visual surface this task.**

### 6 — Reactive deviations and route accounting
- **§8.1 triggered and honoured.** AC-3 does not close; I stopped and reported rather than reaching into P7 for sound. AC-4 shows the gate is still able to fail, so this is the better of the two §8.1 branches.
- **§8.2 triggered.** The residual divergence traces to the **oracle** (nondeterministic sound completion), not to us. Reported as a finding; the bug is not matched.
- **§8.3 partially triggered.** Nondeterminism exists, but it is the oracle's and pre-existing, **not** reintroduced by motion — AC-7 shows our VM is deterministic under load. **No exclusion added.**
- **§8.5 NOT triggered.** Peak cel area 4152 B < ~8 KB.
- **Deviation:** temporary probes were inserted into the oracle tree to trace the flag. They are **not** committed patches; the tree was reverted to `pin + 0001..0006` and rebuilt, verified probe-free, before any gate run.
- **Deviation:** five v2 **fan** titles were unpacked (outside the repo) to reach AC-2's ≥4 games — the PC/DOS corpus has only three AGI titles, KQ4/KQ5 being SCI. Titles carrying `GF_AGI256`/`GF_AGIMOUSE` were excluded because AGI256 uses a different cel encoding.
- **ROUTE ACCOUNTING.** I proposed no route beyond the dispatch's module list. All four modules exist (`view.py`, `objects.py`, `motion.py`, `blit.py`) and `anim.py` is deleted. **Not implemented, each declared in the module that would use it:** `fixPosition`'s spiral search and `updatePosition`'s collision/priority rollback (both need the priority screen); `updateView`'s cel advance is implemented but VIEW-cel-count-driven only; sound of any kind; the parser/`said`; input.

### 7 — Uncertainty flags
- ★★ **AC-3 cannot close as specified while a sound plays.** Not a matter of more work on this VM.
- **Patch 0006's perturbation mechanism is NOT ESTABLISHED** (§3.5). Three candidates eliminated; the gate makes it moot but the cause is unknown.
- **`wander`, `follow.ego` and `ego(mouse)` are implemented but never exercised** by this sample. Their transcription is unverified against the oracle. `motion_follow_ego`'s signed-byte `follow_count` handling in particular is a place I expect a defect if one exists.
- **AC-6's sample is two titles**, and KQ1 contributes nothing. Peak cel area from a title-screen-heavy sample is likely an **under**-estimate of in-game peaks; the 4152 B figure should not be treated as the corpus maximum.
- **The CoCo3 branch of `cmdSound` was found and not pursued** (§8, follow-up 2) — it is directly relevant to this project's target.
- **v3/LZW untested**; CoCo3 rows declined by dispatch.

### 8 — Follow-up candidates
1. ★★★ **Decide how the oracle's sound completion should be made deterministic** — the patch-0005-shaped fix. Until then no state diff can be empty on a title that plays sound, and that constrains every future gate. **Orchestrator decision, not mine.**
2. ★★ **`cmdSound` has an explicit `kPlatformCoCo3` branch** (`op_cmd.cpp`): on CoCo3 *and* Apple II, sound playback is **blocking** — play until finished or a key is pressed, then set the flag immediately. That is a direct statement about our target platform's interpreter behaviour and it makes the completion flag **deterministic** there. Worth folding into the design.
3. Exercise `wander` / `follow.ego` on a title that uses them, and re-run AC-3.
4. Re-measure AC-6 on in-game scenes rather than title screens before the single-buffer decision is finalised.
5. Carried: report the ScummVM uninitialised-`volumeHeader` defect upstream (P1.2).

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
One, to the shared pool (`seeds/AGI/live/`), pushed at `857d084`:

- `2026-08-26-co-occurrence-is-not-causation-trace-the-event.md` — an attribution supported by
  a flag number appearing at 35 call sites survived a whole task and shaped the next dispatch,
  and was wrong; the fix is to probe the actual event, not to count correlates.

`project: AGI`, `source: live`, `instance_count: 1`, `initiator: executor`.

### 11 — Commit
`ad0d78a` — P5.1 views and motion: cels, objects, movement — offline, oracle-verified
(pushed to origin/wip before this report)
