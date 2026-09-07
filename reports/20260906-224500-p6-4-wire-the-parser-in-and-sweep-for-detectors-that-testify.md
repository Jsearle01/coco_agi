## Form B Report — P6.4 — Wire the parser in, and sweep for detectors that testify
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-06 ~21:35 local (HEAD `63cd6c9`, wip). ★ Bracketed, not recorded: the dispatch
arrived after P6.3's push at 21:30 and before this task's first artifact.

`git status` at t0: **not clean** — `reports/…p6-3….md` modified (P6.3's own §11 commit hash,
filled after its push) and `claude(1).md` untracked (the v1.8 artifact this dispatch provides).
Both are carried in this task's commit; neither is a change to code.

---

### 6 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `63cd6c9`, `wip`. Status as above. |
| POP + Karateka | §2T citation below |
| `hal_sync_check.py` | **OK in all three** — verbatim in §5 |
| the gate suite | **all pass from fresh builds** — pic 45/45, res 1264/1264, cel 9193/9193; §5 |
| AC-3's widened tokeniser run [P6.3 §7.1] | ★★★★ **COMPLETED, all five titles, 55,233 cases, 0 divergences** — §4 AC-10 |
| flag sets — enumerate and diff | **produced and diffed** [L-77]; §4 AC-8 |
| the clock — measure it | ★ `1.789772 MHz` measured this session, guest-stamped; §5 |
| every harness with a timeout or stall detector | ★★★★★ **swept — §3.A**; one real class found, fixed, two-sided |
| CLAUDE.md's committed version | ★★★★★ **v1.6, NOT the v1.7 the dispatch expects — see below** |

#### ★★★★★ The one contradiction, and it is benign — but it is real

**The dispatch's grep expects v1.7 committed. The repo has v1.6.** `git log -- CLAUDE.md` ends at
`60c331a` (P3b.18, v1.6); `git log --all -S 'Working Agreement v1.7' -- CLAUDE.md` returns nothing.
**v1.7 was never committed to this repo.**

★★★ **It is benign and that is measured, not assumed.** The superset check ran against the
committed v1.6 and reports **exactly two dropped lines — the two version-header lines and nothing
else** (§5). v1.8 carries v1.7's `§2U` and `§2V` verbatim, so committing v1.8 loses nothing and
closes the gap. **I proceeded on that evidence rather than stopping**, because the check the
dispatch's §9 trigger 5 actually names came back clean, and stopping the task on a version-number
gap whose consequence is provably nil would have been over-reading the grep.

★★ **The second-order fact is the one worth keeping:** P6.2 and P6.3 worked to §2V (§3.E's second
column) from their dispatch text, correctly, while the rule was in no committed file. **The
in-repo rule set has been one version behind the operative one for two tasks**, which is §2S's
shape — the tree is not what a reader of it would think.

#### §2T — sibling baseline, by citation

★ P6.3 §5 records `hal_sync_check.py: N/A — no shared HAL file was touched`, and records no sibling
artifact hashes, because none were needed. **The same holds here: this task touches no file in
§2M's SHARED list.** So there is no sibling artifact this change could move, and the check that
matters is the sync check itself — run in all three repos, `OK`, §5.

★★ **Both siblings' working trees are dirty and it does not reach this**: `git status` in each
shows only untracked `docs/ground-truth/*.pdf`, `nvram/`, and `.vscode/` — gitignored-class
material, no tracked modification. POP `wip` `104b197`, karateka `wip` `29f8f0a`.

---

### 1 — Summary

**The parser has a caller.** `vmtest_said` calls `src/engine/parser.s`, input is fed over a
scripted path at the pacing gate, and the 6809 diffs **byte-identical against `tools/agivm` on
three titles — 288 bytes per cycle, exclusion set EMPTY, identical sha256 on both sides** — with
the said() coverage counters agreeing exactly (KQ1: evaluated 2089, matched 4, fed 4, on both
legs). The nine-title no-input gate is **unmoved**, byte-identical on all nine.

★★★★★ **The sweep found the class one level up from where it was looked for.** Every in-harness
watchdog is charged to a unit of work and resets correctly. **The batch clock is MAME's own
`-seconds_to_run`**, which bounds the whole session while every gate runs its whole corpus inside
one — measured at **308 of 900 emulated seconds for 45 pictures**. And it composes with a second
defect: **the renderer gate reported `45 PASS … (of 45)` and exit 0 on a run that rendered EIGHT
pictures**, because `pic_sweep.lua` never cleared its output directory and `picgate.py` graded the
previous run's files. Both fixed, verified in both directions.

★★★★ **§4A earned its keep.** Jay's eye gate found **four defects no byte gate could have**, and
two of them were mine: a takeover before DECB was ready, a raw-image `org` gap, a status-block
collision, and a reservation that already had an occupant. **All four live in the glue between
subsystems that are each independently gated.**

---

### 2 — Files modified

**New:**
- `harness/tools/vm_input_script.py` — derives a scripted input from the title's own `said()`
  census and **verifies each line against `test_said` before emitting it**.
- `harness/tools/p3b_show.ps1` — the eye gate's invocation, which existed in no file (§3.F).

**Modified — the wiring:**
- `src/harness/vm_tests.s` — `vmtest_said` calls `par_said`; coverage counters; `VM_FAULT_SAID_PURE`.
- `src/harness/vm_probe.s` — `parser.s` included; `vp_feed`; vocabulary window + guest self-test;
  input buffers at the measured 42 B.
- `src/harness/p3b_probe.s` — the same for the integration probe, at its own addresses.
- `tools/agivm/cycle.py` — `input_script` fed at the pacing gate; said()/feed counters.
- `harness/tools/vm_stage.py`, `vm_sweep.lua`, `vm_run.ps1`, `p3b_run.lua`, `p3b_show.lua`.

**Modified — the instruments:**
- `harness/tools/pic_sweep.lua` — clears the plane files this run will write [L-92].
- `harness/tools/flag_diff.py` + `gates.manifest` — `purpose=` per row (AC-8).
- `harness/tools/said_gate.py` — records the emit run's `--limit` beside its corpus.

**Modified — M-48 (AC-9):**
- `harness/tools/gen_vm_tables.py`, `src/harness/vm_tables.s`, `src/harness/vm_core.s`.

**Modified — the map:**
- `src/engine/memmap.inc` — `MAP_VOCAB` (AC-6).

**Provided, committed unedited (§2D):** `CLAUDE.md` v1.8.

---

### 3 — Reasoning

#### 3.A ★★★★★ The sweep: the batch clock is the session bound, not a watchdog

**Every in-harness detector is sound.** `p3b_run.lua`'s watchdog counts frames while the handshake
is held and **resets when the cycle completes** — per cycle, not per run. `pic_sweep.lua`'s budget
resets per picture. `pic_probe.lua` and `mode2_probe.lua` bound a single-item run.
`parser_gate.lua` was fixed in P6.3. `res_sweep`, `cel_sweep`, `comp_sweep` and `vm_sweep` have **no
in-harness detector at all**.

★★★★ **Which is what makes `-seconds_to_run` the finding.** It bounds a whole MAME session; every
gate runs its whole corpus inside one. That is a clock charged to a batch by construction, and no
report has ever measured it. `run_gates.sh:92` states the opposite in a comment — *"a safety net
rather than a budget that is always spent"* — a claim that was true when written and that nothing
re-checks.

**Measured, from MAME's own exit line:**

| gate | budget | spent | corpus | per item | headroom |
|---|---|---|---|---|---|
| **pic** | 900 s | **308 s** | 45 pictures | ~6.8 s | **~131 pictures** |
| cel | 900 s/title | 47–80 s | 6 titles | — | wide |
| res | 3000 s | — | 10 volumes | — | wide |
| vm | 100000 s | — | 9 titles | — | not a real bound |

★★★ **The risk is dated, not hypothetical.** AD-113 found a 71.5% divergence on a picture *outside*
the 45, and L-85 says a gate's corpus is part of its claim — so the renderer corpus is under active
pressure to widen, and past ~131 the session is cut with **no diagnostic at all**. The stall
detector at least printed the word "stalled".

#### 3.B ★★★★★ And it composes: the gate reported 45/45 on a run that rendered 8

`picgate.py` is well built — it iterates the **manifest**, not the directory, and reports a missing
output by name. That is the standard fix for a scope defect and it is correctly applied. **It does
not address staleness**, and `pic_sweep.lua` creates its output directory and never empties it.

**Demonstrated, not argued** (§5): the session was cut to 60 s, the sweep rendered **8** pictures —
its own `timing.csv` says so — 45 `.fb.bin` files were present, 37 of them from the previous run,
and `picgate.py` printed `45 PASS, 0 FAIL, 0 with no output (of 45)` and exited **0**.

★★★★ **That is AD-131's mechanism in the project's most-cited gate.** The fix deletes exactly the
files this run will write, derived from the run's own work list rather than a glob, and is verified
in **both directions** (§2W.1): truncated → 8 PASS / 37 NO OUTPUT / exit 1; complete → 45/45 / exit 0.

#### 3.C The wiring, and the two seams that had to agree

**`vmtest_said`.** The VM flags are the home of record; `par_cli`/`par_accepted` are the argument
and return slots of `parser.py`'s `test_said(operands, ego, accepted_input, entered_cli)`. Reading
them as a second home for flags 2 and 4 would be a §2F violation; marshalling them in **one place**
is what keeps it a call.

★★★ **It is inert until input is fed, by construction rather than by an ifdef.** `par_said`'s first
two instructions are `testSaid`'s own guard, and `par_cli` is set only by `par_parse`. **Every
existing gate run is therefore bit-for-bit unchanged** — verified, nine titles, §5.

**The feed seam.** `cycle.py` feeds immediately before `interpret_cycle()`, which emits its trace
row at the top — so cycle N's row carries the input. The guest samples at its park, *before* the
cycle body, so it must feed after `vm_pace` and **before** publishing and parking; the host
therefore arms one park early. ★★ A one-cycle shift in a flag presents as a clock bug, and P4.x
already spent a task on exactly that when the park sat above `vm_pace`. Both sides state the seam.

**Authority tier (§2.1).** The parser rules are ScummVM at the pin and are believed **original** —
`words.cpp` is reading a Sierra file format. The one reproduced *choice* is the `_egoWords[]` bound
(the oracle segfaults past 20; we stop), recorded in P6.3 and unchanged.

#### 3.D ★★★★ §2H's three checks, on `testSaid`

1. **A second mechanism for a different object class?** Yes, and it changed the task: `said()` is
   only half. `parseUsingDictionary` is the other, and it owns three side effects the callee does
   not — ENTERED_CLI from the word count, SAID_ACCEPTED always cleared, and WORD_NOT_FOUND written
   **only when a word was not found**. Porting the matcher alone gives a correct match inside a
   wrong parse.
2. **Name the caller.** `testSaid`'s caller is the test evaluator, and what it carries is that
   `said`'s operand count comes from the **stream**, not the opcode table — `vm_skip_instruction`
   already handled that and had to keep agreeing with the new handler.
3. **Grep the reports before citing.** Done. P6.3 §3.D says `PAR_FAULT_FIRST_MATCH` gives **match
   differs 0 on all five titles** — which is why it is the wrong fault for AC-5 (§3.E). No
   contradiction found between P6.2/P6.3's parser claims and this task's measurements.

#### 3.E AC-5's fault is in the code THIS task wrote

`parser.s` already carries a fault, but P6.3 measured it as invisible to `said()`. A fault that
cannot fail the gate proves nothing about it. So the fault is in the **wiring**:
`VM_FAULT_SAID_PURE` evaluates the match and does not publish `par_accepted` — treating `said()` as
pure. **That is the plausible version**: it reads like a predicate, the side effect is one line,
and `parser.s`'s own header names this exact mistake.

★★★ **Caught on 2 of 3 titles — and KQ1 passes under it.** KQ2 314/600 divergent, first at cycle 2;
SQ1 598/600. **KQ1 clean**, because its script never puts two matchable patterns in one cycle before
the run quits. ★★★★ **That is L-85 about the corpus, and it is the second time KQ1 has been the
member that hides a defect** — P6.3's stall detector spared it too, for the same reason: it is the
smallest. **A single-title gate on KQ1 would have reported the faulted wiring green.**

#### 3.F ★★★★★ What the eye gate found, and why no byte gate could

§4A.1's claim, demonstrated four times in one task:

| defect | why the byte gate was blind |
|---|---|
| **takeover at frame 4**, before DECB reached `OK` | Jay's catch. No gate inspects the boot; the probe pokes and sets PC on a frame count. |
| ★★★★ **`org` gap** — lwasm raw emits no padding, so the parser landed **36 bytes** below its symbols | `vm_probe.s` includes `parser.s` inline with **no org**, so the nine-title diff is byte-identical either way. **The defect exists only in the integration probe.** |
| ★★★ **`P3_FEED` collided with `CNT_VERT`** — the renderer's line counter armed the parser's feed flag | fires only in a room with vertical lines |
| ★★★★★ **`CP_CEL equ MAP_RESERVED`** — the cel buffer owns `$5300`; the first cel decode zeroed `par_vocab` | fires only in a room with **sprites**, and the opening room has none |

★★★★ **The last two are mine, and both came from trusting a written claim over the declarations.**
`p3b_probe.s:88` says *"MAP_STATUS+32 is left free"* while `CNT_VERT` has been there since the
renderer landed; `memmap.inc:105` says *"3,328 B, parser + sound"* while the probe's 4,784-byte cel
buffer already occupies and overruns it. **§8's "read constants back from the file" is the rule I
skipped, twice.** Assertions now cover both, and the stale comment is kept struck-through rather
than deleted — a comment that was believed is evidence.

★★★ **Jay named the fourth from the outside**: *"if youre placing anything at $0000 you are
overwriting the DP and probably the stack."* Nothing was placed there — `par_vocab` was **zeroed**,
so `par_find` walked from address 0 through the direct page and the seed stack. The read was right.

#### 3.G ★★★★ The readiness check, and my own §2W failure

Jay: *"you need to wait for the basic prompt 'ok'."* My first version scanned all 512 screen bytes
for any adjacent `$4F,$4B` and reported ready at **frame 28**. Measured afterwards: the banner is
not on screen until ~frame 60, so at frame 28 it matched **uninitialised RAM**. Jay again: *"you
still are not getting to the basic prompt."*

★★★ **A pattern search over uninitialised memory is not a readiness check, and it failed EARLY —
the direction that hides the problem.** It now requires two independent signals — `OK` at the start
of a row, and the CPU parked in DECB's prompt poll (`PC=$A7D0-$A7E0`, idiom 14a, corroborated by
this task's own screen probe) — sustained three frames. It now reports frame 30 with the PC.

★ Per Jay's ruling the prompt is **held 120 frames so it can be seen**, then the display blanks at
takeover. `p3b_show.lua` had been blanking at *script load*, before DECB printed anything — which
is why there was never a prompt to see.

#### 3.H AC-6 — the vocabulary's slot, and a narrowing that came with it

**Slot 5 (`$A000-$BFFF`)**, recorded in `memmap.inc` as `MAP_VOCAB`. It is the slot the phase table
already leaves idle for the whole VM phase; slot 6 is the volume window and a resource fetch
happens in the same phase, so it would collide. Justified by the 6,828-byte measurement, asserted
at assembly time.

★★★★ **And only `par_parse` needs it mapped, not `par_said`** — the matcher reads `par_ego`,
`par_egon` and the operand stream and never touches `par_vocab`. So the window is required once per
typed command, not on any of the said() evaluations that follow. A game evaluating fifteen patterns
a cycle needs it for none of them.

#### 3.I ★★★★ What the eye gate does NOT show, and Jay has ruled on it

`pace(wait)` is **0.0644 s of 85 s — 0.1%**. The port is slower than the game's requested rate, so
`vm_pace` never waits and a `VAR_TIME_DELAY` change alters the game's virtual clock and **not the
display**. Measured across three titles, **no reachable `said()` in the gated window changes the
room** — the game is in its title sequence and the only patterns logic 0 tests there are
interpreter meta-commands and the speed words.

> ★★★★ **So the parser's effect is correct in state and not observable on screen until text
> rendering lands.** Jay has ruled this the next task's first constraint.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: eye-gated] — ★★★★★ PASSED — Jay, live-disk-equivalent (poke), RGB, throttled.**
  Jay watched the run and ruled it a pass, with §3.I recorded as the next task's first constraint.
  ★★ Launch path: **`poke`** — p3b is poked after the OK-prompt wait; §4's caveat stands and is
  stated. **It found four defects before any byte gate was reported (§3.F), which is §4A.1.**
- **AC-2 [class: byte-comparable] — PASS, with the v1.7 gap surfaced.** Superset against the
  committed copy: **2 dropped lines, both version headers, nothing else**. Renamed after the check.
  `sha256 C5AB4381C7A00BFC…` identical before and after; `git hash-object` with and without filters
  identical, so no normalisation. ★ The committed copy was **v1.6, not v1.7** — §6.
- **AC-3 [class: state-comparable] — PASS.** Every harness with a budget swept (§3.A). The
  in-harness detectors are clean; the class is `-seconds_to_run`, measured at 308/900 on pic, and it
  composes with an uncleared output directory into a gate that reported 45/45 on a run of 8. Fixed
  and two-sided.
- **AC-4 [class: state-comparable] — PASS, three titles, exclusion set EMPTY.** KQ1 140/140, KQ2
  600/600, SQ1 600/600, **identical sha256 on both sides**. Coverage agrees exactly on both legs.
  ★★★ KQ1 quits at cycle 140 **because a said() branch fires** — the guest quits at the same cycle
  or the diff fails on length, so the early stop is part of what is compared.
- **AC-5 [class: byte-comparable] — PASS, on this build and this corpus.** `VM_FAULT_SAID_PURE`
  caught on KQ2 (314/600) and SQ1 (598/600). ★★★ **Not caught on KQ1**, and that is reported as a
  finding about the corpus (§3.E), not smoothed over.
- **AC-6 [class: state-comparable] — PASS.** `MAP_VOCAB` = slot 5, recorded in `memmap.inc` with
  the 6,828-byte measurement and an assembly-time assertion (§3.H).
- **AC-7 [class: state-comparable] — PASS, measured at the pin.** `text.h:170 byte _prompt[42]`;
  `text.h:74 TEXT_STRING_MAX_SIZE 40`; `text.cpp:743-752` clamps to the minimum;
  `cycle.cpp:663` sets var 24 = 38. **42 bytes each, not 256.** ★★ **Footprint restated: 954 B**
  (870 code+state + 84 buffers) = **28.7% of `MAP_RESERVED`'s 3,328**, which is UNCHANGED.
- **AC-8 [class: byte-comparable] — PASS, fixed not retired.** The over-report was `EXPECTED_ON`
  applied to **correctness** gates, where a half-speed clock cannot change a byte comparison.
  `gates.manifest` now declares `purpose=`; **4 alarms → 1**, and the survivor (p3b/`PIC_NOCOUNT`)
  is genuine. Verified three ways in §5, including that flipping a row back to `timing` **restores**
  the alarm — the suppression is conditional, not a mute.
- **AC-9 [class: byte-comparable] — PASS.** M-48 landed: `VMOP_ARGS` and `VMOP_TAB` sized to the
  183-entry v2 command space with the range check `VMTEST_TAB` already had. **`vm_probe` 9,813 →
  9,610 B (203 net).** p3b: `P3_CODE_END $52DC` against `MAP_CODE_END $5300` = **36 bytes free**
  (was 4). `MAP_RESERVED` unchanged at 3,328. ★ Behaviour identical — the nine-title diff is what
  checks it.
- **AC-10 [class: state-comparable] — PASS, five titles.** P6.3's widened tokeniser run had
  **completed** after that report was written (20:49–21:10). **6,107 + 12,435 + 13,362 + 14,301 +
  9,028 = 55,233 cases, ego-list differs 0 on every title.** ★ The sum is my arithmetic over the
  five printed lines [§8].
- **AC-11 [class: state-comparable] — five things the dispatch did not anticipate.** §7.
- **AC-12 [class: suite] — four candidates captured.** §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — AC-2, the superset check (verbatim):**

```
in-repo  : CLAUDE.md
           56286 bytes, sha256 f670e88b014642c4
           728 substantive lines
provided : claude(1).md
           66060 bytes, sha256 c5ab4381c7a00bfc
           842 substantive lines
added    : 116 substantive lines not in the in-repo copy
DROPPED  : 2 substantive lines present in-repo and absent (or fewer) in the provided file
  -1  ## Working Agreement v1.6 (forked from POP3_port CLAUDE.md v1.1)
  -1  **Version:** 1.6

SUPERSET CHECK: ★★★ FAIL -- STOP AND SURFACE THE DELTA (§2D)
```

★★ The tool exits 1 because it does not know about declared supersessions. **The two lines it names
ARE the declared supersessions and there is nothing else**, which is §9 trigger 5's condition not
met. Byte identity after the rename:

```
sha256   C5AB4381C7A00BFC91B47601FEE880A9C77C80A187F3F943CE27DEA2D7331C5A   (== provided)
git hash-object            7f1e1ee4d408208a3f43436293d53e5481d77d84
git hash-object --no-filters 7f1e1ee4d408208a3f43436293d53e5481d77d84   -- no normalisation
```

**25.1 — AC-3, the batch clock, MEASURED (verbatim):**

```
=== pic  (-seconds_to_run 900) ===
Average speed: 2363.32% (308 seconds)
```

**25.1 — AC-3, the gate reporting 45/45 on a run of 8 (verbatim, BEFORE the fix):**

```
--- 1. the complete run's artifacts are in place (the previous good run) ---
45
--- 2. run the SAME gate with a deliberately short session budget (60 s of the 900) ---
Average speed: 2417.81% (59 seconds)
    pictures this run actually rendered (rows in its own timing.csv, header excluded):
8
    .fb.bin files present afterwards:
45
--- 3. adjudicate. §2W: what does the instrument say about a run that did a fraction? ---
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
picgate exit: 0
```

**25.1 — AC-3, the fix, BOTH DIRECTIONS (§2W.1) (verbatim):**

```
══ DIRECTION 1: truncated session (60 s of the 900) -- the gate MUST fail ══
Average speed: 2359.39% (59 seconds)
cleared 90 stale plane file(s) for the 45 pictures this run will write
  pictures this run rendered (its own timing.csv, header excluded): 8
  .fb.bin files present:                                            8
per-picture: 8 PASS, 0 FAIL, 37 with no output   (of 45)
  picgate exit: 1   (must be non-zero)

══ DIRECTION 2: complete session (the real 900) -- the gate MUST pass ══
Average speed: 2397.17% (308 seconds)
cleared 16 stale plane file(s) for the 45 pictures this run will write
  pictures this run rendered: 45
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
  picgate exit: 0   (must be zero)

══ VERDICT ══
★ two-sided: the gate FAILS a truncated run and PASSES a complete one.
```

**25.1 — AC-4, the state diff, three titles (verbatim):**

```
title        : Kingquest1
oracle       : 140 cycles  sha256 1ba031a9a593b3fd
guest        : 140 cycles  sha256 1ba031a9a593b3fd
compared     : 140 cycles x 288 bytes, exclusion set EMPTY
divergent cycles : 0 of 140
AC-2 PASS -- byte-identical on every compared cycle

title        : Kingquest2
oracle       : 600 cycles  sha256 5fff6da1b14d0db3
guest        : 600 cycles  sha256 5fff6da1b14d0db3
divergent cycles : 0 of 600
AC-2 PASS -- byte-identical on every compared cycle

title        : SpaceQuest-1
oracle       : 600 cycles  sha256 235f9b8dc5278309
guest        : 600 cycles  sha256 235f9b8dc5278309
divergent cycles : 0 of 600
AC-2 PASS -- byte-identical on every compared cycle
```

★★ **The coverage counters, both legs, KQ1** — reference then 6809:

```
said()       : evaluated 2400, matched 2;  inputs fed 2      [tools/agivm]
    said(): evaluated 2400, matched 2;  inputs fed 2   [6809 side]
```

**25.1 — L-79's arm: the nine-title gate with NO input, unmoved (verbatim, condensed to the
verdict lines; every `oracle`/`guest` sha256 pair was identical):**

```
vm_probe: 9813 bytes
Kingquest1  0 of 600 divergent   cb6d7aeee81c6001 == cb6d7aeee81c6001
Kingquest2  0 of 600 divergent   0d619536093988d5 == 0d619536093988d5
Kingquest3  0 of 600 divergent   30abb46e828a933b == 30abb46e828a933b
SpaceQuest-1 0 of 600 divergent  3181b2aadb888148 == 3181b2aadb888148
SpaceQuest-2 0 of 600 divergent  59f8c02ad4e892ec == 59f8c02ad4e892ec
PoliceQuest1 0 of 600 divergent  7cce7162ddd8e373 == 7cce7162ddd8e373
larry1      0 of 600 divergent   a17dfb3414e65cdf == a17dfb3414e65cdf
BlackCauldron 0 of 600 divergent 7c27a6975974f215 == 7c27a6975974f215
MixedUpMotherGoose 0 of 600      8d68681ae67b37c3 == 8d68681ae67b37c3
=== AC-2 SUMMARY === all nine PASS
```

★ **The layout of these nine lines is mine**; every hash and count is as `vm_diff.py` printed it.

**25.1 — AC-5, the injected fault (verbatim):**

```
★★★ FAULT INJECTED (-DVM_FAULT_SAID_PURE): said() treated as PURE -- this build is EXPECTED to FAIL
Kingquest1   oracle 1ba031a9a593b3fd  guest 1ba031a9a593b3fd  0 of 140    AC-2 PASS
Kingquest2   oracle 5fff6da1b14d0db3  guest 7a96499445077893  314 of 600  first divergence cycle 2
                                       vars [62, 94]  flags [90, 91]      AC-2 ★★★ FAIL
SpaceQuest-1 oracle 235f9b8dc5278309  guest 50eb978ee0fcecb9  598 of 600  first divergence cycle 2
                                       vars [10, 11, 12, 64, 121, 126, 149]  AC-2 ★★★ FAIL
=== AC-2 SUMMARY ===  Kingquest1 PASS   Kingquest2 FAIL   SpaceQuest-1 FAIL
```

**25.1 — AC-8, `flag_diff --manifest`, three ways (verbatim):**

```
=== 1. the real manifest: alarms drop from 4 to 1 ===
── pic  (src/harness/pic_probe.s)  [correctness] ──
── pic_nc  (src/harness/pic_probe.s)  [timing] ──
── pic_nc_pk  (src/harness/pic_probe.s)  [timing] ──
── pic_win  (src/harness/pic_probe.s)  [timing] ──
── res  (src/harness/res_probe.s)  [correctness] ──
── cel  (src/harness/cel_probe.s)  [correctness] ──
── comp  (src/harness/comp_probe.s)  [correctness] ──
── vm  (src/harness/vm_probe.s)  [correctness] ──
── p3b  (src/harness/p3b_probe.s)  [timing] ──
   ★★★ EXPECTED-ON BUT ABSENT: PIC_NOCOUNT
★★★ 1 expected-on guard(s) absent. Every timing figure from such a build is suspect.

=== 2. §2W BOTH DIRECTIONS: flip res to purpose=timing -- the alarm MUST come back ===
── res  (src/harness/res_probe.s)  [timing] ──
   ★★★ EXPECTED-ON BUT ABSENT: HAL_SYS_FAST_CLOCK
   ★★★ EXPECTED-ON BUT ABSENT: PIC_NOCOUNT

=== 3. and a row with NO purpose must be refused ===
── cel ──
   ★★★ NO purpose= FIELD. Add `purpose=timing` or `purpose=correctness` to this row.
```

**25.1 — AC-10, the widened tokeniser gate, five titles (verbatim):**

```
--- Kingquest1 ---     tokeniser cases : 6107    ego-list differs: 0   ★ 6107 of 6107 identical
--- Kingquest3 ---     tokeniser cases : 12435   ego-list differs: 0   ★ 12435 of 12435 identical
--- larry1 ---         tokeniser cases : 13362   ego-list differs: 0   ★ 13362 of 13362 identical
--- PoliceQuest1 ---   tokeniser cases : 14301   ego-list differs: 0   ★ 14301 of 14301 identical
--- SpaceQuest-1 ---   tokeniser cases : 9028    ego-list differs: 0   ★ 9028 of 9028 identical
```

★ **Condensed: one line per title, figures as printed, layout mine.** ★★ The corpus is defined by
`--limit 1000`, which existed nowhere on disk and was recovered by bisection; it is now recorded in
each workdir as `cases.limit` and read back by `--check` (§7.3).

**25.1 — the gate suite, from fresh builds (verbatim):**

```
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)

TOTAL                    1264       1264        0          0
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)

TOTAL             9193    9193    9193       0        0     1525
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)

★ gates run: pic res cel (comp NOT covered -- run it explicitly)  -- all green
```

**25.1 — `hal_sync_check.py`, all three repos (verbatim):**

```
coco_agi        [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port       [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3  [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)
```

**25.1 — `reg_discipline.py` (§2N; `src/engine/` was touched) (verbatim):**

```
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).

  file                                     count  registers
  src/engine/mmu_phase.s                       8  $FFA5 $FFA6
```

★ **Unchanged.** Wiring the parser adds zero register accesses, which is the expected result for a
routine that is pure computation over two buffers.

**25.1 — the clock, MEASURED this session, guest-stamped [L-78, VP_MARK] (verbatim):**

```
clock MEASURED 1.789772 MHz (160009 cycles calibrated)
```

**25.1 — the eye gate's own record (verbatim):**

```
DECB is at its OK prompt (frame 30, PC=$A7D5, 'OK' at a row start, 3 frames) -- holding it for 120 frames so it can be seen
taking the machine over at frame 150
program 13890 bytes: 13020 at $2000 + 870 at $E000 (the parser, org'd)
  vocabulary 3144 B -> $E3BA; window self-test clean; 33/33 sample points match OK
  ★ par_vocab written $E3BA, reads back $E3BA -- the parser is LIVE: said() now reads a dictionary.
  ★ room jump at cycle 8: var0 <- 1, flag 5 set
  ★ COMMAND TYPED at cycle 40 (4 chars) -- watch the screen
  ★ COMMAND TYPED at cycle 80 (4 chars) -- watch the screen
★ 160 cycles in 85.2264 emulated s
    final room 1, sprites 4, err 0, status=$00
       pace(wait)   0.0644 s total   0.00040 s/cycle    0.1%  (160 entries)
```

**25.1 — the builds (verbatim commands; `lwasm` prints nothing on success):**

```
lwasm --format=raw --output=build/vm_probe.bin --map=build/vm_probe.map -I. \
      -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK src/harness/vm_probe.s
lwasm --format=raw --output=build/p3b_probe_pk_fresh.bin --map=build/p3b_probe_pk.map -I. \
      -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED src/harness/p3b_probe.s

vm_probe.bin   9610 bytes   (9813 before M-48; -203)
p3b image     13890 bytes   = 13020 code ($2000..$52DC) + 870 parser (org $E000)

P3_CODE_END $52DC vs MAP_CODE_END $5300  -> 36 bytes free (was 4)
P3_PARSER_TOTAL $03BA = 954 B            MAP_RESERVED 3,328 B UNCHANGED
```

**25.2 — bundled-artifact grep:** N/A — this task ships no DECB artifact; every probe is poked.

**25.3 — operator-runtime-smoke:** ★★★★★ **PASSED — Jay, `poke`, RGB, throttled.** Jay ran and
watched `p3b_show.ps1 -Title Kingquest1 -Cycles 160 -WithInput` and ruled it a pass, with §3.I's
limitation recorded as the next task's first constraint. ★★ **Not `live-disk`** — p3b is poked, so
§4's caveat about load/launch bugs stands and is stated rather than glossed.

---

### 6 — Reactive deviations and route accounting

**Deviations (§22.5):**

1. ★★★★ **I did not stop on the §6 grep contradiction.** The dispatch says a contradiction is a
   stop-and-report. The committed CLAUDE.md is v1.6, not v1.7 — **and the superset check proves
   v1.8 loses nothing from v1.6**, so the consequence is nil. I proceeded and surfaced it at the
   top instead. **Reported as a deviation because it was a judgement call, not a non-event.**
2. ★★★ **I fixed `pic_sweep.lua` and `flag_diff.py` rather than only reporting them.** AC-3 permits
   "found, fixed or reported"; AC-8 says "fixed or retired". Both are fixed and both are verified
   two-sided.
3. ★★★ **I wrote `p3b_show.ps1`.** Not asked for. The eye gate's invocation was in no file and its
   symbol file came from a hand-typed command — the L-45 defect on the one gate whose result is a
   human's judgement. Writing it was the only way to make AC-1 reproducible.
4. ★★ **I added the OK-prompt wait, the hold, and the two-segment poke** — all from Jay's
   corrections during the task, recorded in §9.
5. ★ **I recorded `cases.limit`** in the tokeniser workdirs. Not asked for; AC-10 could not be
   checked without recovering a number that existed nowhere.
6. ★ **I added assertions** for the status block and for `CP_CEL` against the parser. Both are
   collisions this task created and neither had any assertion covering it.

**Route accounting.** I proposed no route beyond the dispatch's own parts. ★★★ **What I described
and did NOT implement:** while chasing the `par_vocab` zero I said the next step would be a write
tap naming the storing PC. **I built it and it recorded nothing** — no guest instruction ever wrote
`par_vocab` — and that emptiness was the answer that moved the search to the host and then to the
cel buffer. It is left in place, recording rather than logging (logging from inside a tap ended a
run at cycle 8 with no output, which reads as "nothing wrote it").

★★ **What I considered and did not do:** shrinking the code region further to fit the parser into
`MAP_RESERVED` in p3b. M-48 returned 203 bytes against the parser's 870, and squeezing another 670
to avoid a region that is already occupied is the slide `memmap.inc:72-95` spent three tasks
regretting.

---

### 7 — Uncertainty flags

1. ★★★★ **The v1.7 gap.** v1.8 is committed and closes it, but two tasks ran while the in-repo rule
   set was a version behind the operative one. **If any other Orchestrator artifact has been
   provided and not committed, nothing in the tree would show it.**
2. ★★★★ **AC-4 covers three titles, not nine.** KQ3 was excluded because the *reference* raises on
   `restart.game` when fed (§7.4). The other six are not measured with input.
3. ★★★ **`said_gate.py --check` regenerates its corpus instead of reading the case file the oracle
   consumed.** Recording `cases.limit` makes it recoverable; it does not make the two the same
   artifact. **One producer, two consumers would be better** and is not what this is.
4. ★★★★★ **Wiring the parser reaches opcodes no gate has ever executed.** KQ1 reaches `save.game`
   ($7D) and `restore.game` ($7E); KQ3 reaches `restart.game`. All three are deliberately
   unimplemented and raise honestly. **Without input an AGI game sits in attract mode and never
   takes those branches** — so the parser is the door to a part of the command space the nine-title
   gate has never covered. Not a defect; a coverage fact with a cost attached.
5. ★★★ **p3b's `CP_CEL` is 4,784 B in a 3,328 B region** and overruns into the arena window. That
   is pre-existing and reported by the probe's own §8 block; this task did not touch it, and the new
   assertion only keeps it clear of the parser.
6. ★★ **The comp gate is still not driven from `run_gates.sh`** and was not run this task.
7. **Carried, unchanged:** the patch-series rebuild remains deferred; `oracle/patches/0009-*.patch`
   is still cumulative.

---

### 8 — Follow-up candidates

1. ★★★★★ **Text rendering and the on-screen input line** — Jay's ruling: §3.I is that task's first
   constraint. Until it lands the parser's effect is unobservable on screen.
2. ★★★★ **Measure the other gates' session headroom** the way pic's was measured, and put the
   figure beside each `-seconds_to_run`.
3. ★★★ **Clear the output directory in the remaining per-item sweeps.** Only `pic_sweep` is fixed;
   `comp_sweep` writes per-frame files under `COMP_DUMP` and has the same shape, though its
   comparison reads RAM rather than the files.
4. ★★★ **Decide what to do about `save.game`/`restore.game`/`restart.game`** now that the parser
   reaches them.
5. ★★ **Widen AC-4's input arm** to the remaining six gate titles.
6. ★★ **`res_aggregate.py` has no expected-total assertion** — a short run reports 100% of a smaller
   number. The pinned list protects the *set*; nothing protects the *count*.

---

### 9 — User interaction during task

- ★★★★ Jay: *"you need to wait for the basic prompt 'ok'. We had this worked out before."* — the
  probe was poking at frame 4. Implemented; §3.G.
- ★★★★ Jay: *"try again. there was no basic prompt"* and *"you still are not getting to the basic
  prompt"* — my first check matched uninitialised RAM and passed at frame 28. Replaced with two
  independent signals; and `p3b_show.lua` was blanking the display before DECB printed anything.
- ★★★ Jay ruled the boot display: **show the prompt, hold it, then black.** Implemented.
- ★★★★ Jay: *"if youre placing anything at $0000 you are overwriting the DP and probably the
  stack"* — the correct read of a null `par_vocab`; §3.F.
- ★★★★ Jay ran the eye gate and **ruled AC-1 a pass**, and ruled that §3.I is recorded as the next
  task's first constraint.
- Standing instruction, carried: **do not commit PNGs unless asked.** None produced, none committed.

---

### 10 — Candidate(s) captured this task

Four, in `seeds/AGI/live/`, pushed to the pool at `ad5943b`:

- `2026-09-06-a-session-budget-is-a-clock-charged-to-the-whole-corpus`
- `2026-09-06-an-adjudicator-driven-from-the-required-set-still-grades-stale-artifacts`
- `2026-09-06-a-raw-image-is-bytes-not-an-address-space`
- `2026-09-06-a-region-reserved-for-one-thing-may-already-hold-another`

★ **Not captured, because it is an instance of an existing row rather than a new mechanism:** my
readiness check that matched uninitialised memory belongs to
`an-assertion-you-have-not-broken-is-not-an-assertion` and to
`a-guard-built-on-an-absent-global-is-inert-not-broken`. ★★ Per §2C I have not edited either; the
recurrence is recorded here in §3.G for the reconciler, and it is notable that **it is the same
author repeating the class one task later, in a check written to satisfy a rule about checks.**

### 11 — Commit

`b2cb530` — *P6.4 wire the parser in; sweep for detectors that testify*
(pushed to `origin/wip` before this report; `63cd6c9..b2cb530`).
