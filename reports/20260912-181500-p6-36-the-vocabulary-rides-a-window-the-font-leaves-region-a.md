## Form B Report — T-P0-091 / P6.36 — The vocabulary rides a window; the font leaves region A
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-12 18:15 (HEAD 96cda7c, wip). Six files modified, the two known untracked files
otherwise.

### 1 — Summary
6,966 bytes of dictionary stopped being permanently resident. **Region A's headroom is 277 → 2,289
bytes**, past §1.2's 700-byte target with room to spare.

★★★★★ **What moved out of region A was the FONT, not code.** §1.1 asked for "move code from A into
B"; the thing with the weakest claim to region A was 2,048 bytes of authored glyphs reached only by
address, which is L-127's own test and is where `memmap.inc` has always put them (`MAP_FONT`
$E0B8). ★★★★ **Windowing the dictionary is what made that possible and the connection is not
incidental** — see §4B.2.

★★★★ **And the suite was not gating the parser at all, in either direction.** No row stages a
dictionary [§4E]. That is now a row.

### 2 — Files modified
- `src/engine/mmu_phase.s` — `ph_blk_vocab` / `ph_blk_slot5`, `phase_vocab_in` / `phase_vocab_out`,
  behind `-DPHASE_VOCAB`. Stale count corrected.
- `src/harness/p3b_probe.s` — the window, the block numbers, the font's new home, three assertions
  repointed. All scoped to `P3B_NO_CEL`.
- `harness/tools/p3b_run.lua` — block staging, the window-discrimination check, the parse readback,
  the stall dump's dictionary readout mapped before it is read.
- `harness/tools/p3b_show.ps1` — `-NoMap`, the new symbols, the zero-word adjudication.
- `harness/tools/run_gates.sh` — the `p3b_parse` row.
- `harness/tools/gates.manifest` — two re-baselines with retirement lines, two new rows.

★ `src/engine/parser.s` and `src/harness/parser_probe.s` are **unmodified** (`git diff --name-only`
returns nothing for either).

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| `p3b` | `58AD3C27…` 13,918 B | ✔ |
| `p3b_text` | `C4A4346B…` 15,555 B | ✔ , headroom **277** |
| `p3b_notick` | `2849A07A…` 15,552 B | ✔ |
| `reg_discipline.py` | — | **8** accesses, 1 file, 2 registers |
| `P3_VOCAB` / `_END` / `_BAD` / `par_vocab` | — | $E3BA / $FEF0 / MAP_STATUS+89 / parser.s:35 ✔ |

★★★★ **The dispatch's §3(3) figure and `mmu_phase.s`'s own comment both say 5. The census says 8.**
A number in a comment with no producer [AD-95], stale since the cross-slot borrow pair landed.
Corrected in the file because this task moves it again.

### 4A — What must be co-resident during a parse (enumerated fresh)

| | lives in | must be mapped with the dictionary? |
|---|---|---|
| `parser.s` code | slot 7, $E000-$E366 | **yes**, and slot 7 never moves |
| `par_vocab`, `par_ego`, `par_egon`, `par_fpos`, the `par_f*` scratch | slot 7 (inside parser.s) | **yes**, same slot |
| `par_inbuf` → P3_INBUF $E366 | slot 7 | **yes**, same slot |
| `par_clnbuf` → P3_CLNBUF $E390 | slot 7 | **yes**, same slot |
| the hardware stack, the HAL direct page | slot 0 | **yes**, and slot 0 never moves |
| the VBL handler | slot 1-2 code; touches DP $10/$11 only | untouched by any remap |
| **the vocabulary** | — | **this is the window** |
| the framebuffer, the priority plane, the font, the arena, VM_OBJ | slots 3-6 | ★★★★ **no** |

★★★★★ **The result is the whole design: everything par_parse needs except the dictionary is in slot
0 or slot 7, and neither ever moves.** So the tokeniser can run with any other slot pointed
anywhere.

★★★ **`par_parse` calls nothing outside `parser.s`** — `par_clean`, `par_is_sep`, `par_is_inv`,
`par_find`, `par_fi_cmp`, `par_fi_left`, and that is the complete list. **§2H's second check**:
`par_vocab` is dereferenced at `parser.s:233` and `:239`, both inside `par_find`, and `jsr par_find`
appears exactly once, in `par_parse`. There is no second consumer and no second caller.

★★ P6.32 §8B.2's hazard does not recur: substitution writes P3_PBUF in `MAP_INPUT`, slot 0, and the
window is slot 5.

### 4B — The slot decision, and it was already written down

★★★★★ **Option 2, and the engine had already chosen it.** `memmap.inc:287` has read
`MAP_VOCAB equ MAP_PRI_SLICE` since T-P0-060, with the measurement (6,828 B max, one 8,192 B
window, 1,364 B spare) and the reasoning (slot 6 is the volume window and a fetch happens in the VM
phase; slot 5 is idle). **This task did not choose a slot. It gave an existing line code.**

**Option 1 is not taken** — slot 7 does not become movable, and §6's first trigger does not fire.

#### 4B.1 Why the probe could not use slot 5 before, and why that objection dissolved

`p3b_probe.s:1534` and `memmap.inc:282` both say it plainly: **"this probe cannot use it: slot 5 is
p3b's PRIORITY slice, live in every draw phase."**

★★★★★ **That is true of a RESIDENT vocabulary and false of a WINDOW.** `par_parse` runs in the VM
phase, where slot 5 holds the object table rather than the priority slice, and it needs the
dictionary for the duration of one call. **The objection was about residency the whole time.** So
the probe's map converges on the engine's here instead of diverging further — which is the opposite
of what the last four map tasks did.

#### 4B.2 ★★★★ And that is why the FONT could move, which §1.1 did not anticipate

`p3b_probe.s:241` recorded the obstacle exactly: *"this probe orgs the PARSER at $E000 (slot 5 is
its priority slice, so the engine's vocabulary window is unavailable here), so $E0B8 is 184 bytes
INTO parser code and the vocabulary follows at $E3BA."*

★★★★★ **Both halves became false in the same change.** The vocabulary left region B, so $E3BA upward
is free, and the font went to the place `memmap.inc` always named. **Freeing B did not relieve A —
§1.1 is right about that — but what travelled was data, not code.**

#### 4B.3 The restore, and it closes a gap this file named itself

`p3b_probe.s:604` has said since T-P0-060 that *"the engine needs a `ph_blk_obj` and a `phase_vm`
that restores it, and that is a design change to report, not to slip into this task."* ★★★ **That
byte is `ph_blk_slot5`**, added here because windowing is the first thing that unmaps slot 5
mid-phase and the restore had to live somewhere. **The probe's `lda #$3D / sta $FFA5` is gone: it no
longer writes an MMU register anywhere.**

### 4C — ★★★ The 16 bytes that were not free, and the stale binary that nearly reported them

The first build put the two routines and two bytes in `mmu_phase.s` unguarded. `mmu_phase.s` is
included **unconditionally** by every windowed probe, so that is 16 bytes in `p3b` too — and `p3b`'s
`CP_CEL` guard refused the build, correctly.

★★★★★ **And the run that refused still printed `p3b 13,918 B 58AD3C27` — the baseline — because
lwasm errors without writing and I was hashing the previous run's file.** AD-90's shape exactly, one
task after §2W was amended for it. **Caught because the guard fired in the same output**; the
routines are now behind `-DPHASE_VOCAB` and every later build was preceded by deleting the output.

### 4D — What makes a pointer that is valid only while a mapping holds safe (§4D)

`par_vocab` now holds $A000 permanently and names real memory for two instructions per typed line.
The file's own history is the reason to ask: room 1's first cel decode zeroed `par_vocab` and
`par_find` walked from address zero [L-86, `p3b_probe.s:1489`].

Four things, and the third is the only one that is mechanical:

1. **The bracket is two instructions around one call**, in `p3_feed`, with no branch between them.
2. **There is exactly one consumer and one caller** (§4A), so no path reaches `par_vocab` outside
   the bracket. Verified by grep, not by reading.
3. ★★★★★ **The failure is LOUD, and it was run.** `-DP3B_VOCAB_NOMAP` drops the one `jsr` and the
   probe is **STUCK in the cycle the command was fed** — `par_find` computes `vocab + letter*2`
   into the object table and walks for a terminator that is not there. **A silently wrong parse
   would have been the bad outcome; a hang at the fed cycle is not it.**
4. **The host cannot stage into the wrong block silently** — see the discrimination check in §4E.

★★ **What is NOT mechanical: nothing asserts that `par_vocab` is only dereferenced inside the
bracket.** (2) is true today and a future caller could break it without any check objecting. §7.2.

### 4E — ★★★★★ The suite was not gating the parser, before this task or after

`vm_stage.py` writes `words.tok` **only when an input script is requested**. `p3b_text` and
`p3b_box` do not pass `-WithInput`, so both run with no vocabulary staged, `par_vocab` 0, and
`par_said`'s guard making the whole path inert.

> ★★★★★ **Every green run of those two rows says nothing whatever about the parser**, and that has
> been true since P6.4 wired it in.

★★★★ **So a windowed dictionary had nothing to be gated by, and neither did a flat one.** Two things
close it:

- **`p3b_parse`** — `p3b_text`'s binary and corpus with `-WithInput`, which is what stages a
  dictionary. Adjudicated on the **word count**, because a broken window parses to zero words and
  the run finishes normally [`p3b_show.ps1`'s `$nowords`]. In `run_gates.sh` and green.
- **`p3b_nomap`** — its fault arm, one `jsr` smaller and nothing else [L-73].

★★★ **This is §2F's "the scope and the invocation of a gate are part of its definition" for the
sixth time in this project — and the first five were about which corpus. This one is about whether
the subsystem is reached at all.**

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output.**

```
p3b          13918 B  58AD3C27164BD63FDE17E18041160B28   <- byte-identical, AC-5
p3b_text     15591 B  7B58CE6BD16CEE065B6F37CA7E56B671
p3b_notick   15588 B  5C4200DA58DD94031C75F98C3606EED1
p3b_nomap    15588 B  0A0B7F1B1775DFC1D5EE9347911C571C

★ source integrity: clean
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse  -- all green

  vocabulary 3144 B -> $A000 (block 6, slot 5; restored to 61); window self-test clean;
             33/33 sample points match OK
  ★ window discrimination: $A001 reads $00 shut and $3E open -- block 6 is distinct memory
  ★ parse at cycle 30: 1 word(s) [161] notfound=0 -- the dictionary was reachable
  ★ parse at cycle 60: 1 word(s) [160] notfound=0 -- the dictionary was reachable

AC-2 SUMMARY: Kingquest1 Kingquest2 Kingquest3 SpaceQuest-1 SpaceQuest-2
              PoliceQuest1 larry1 BlackCauldron MixedUpMotherGoose  -- 9/9 PASS

[reg-discipline] 10 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   10   $FFA5 $FFA6
[hal-sync] OK -- aligned with POP3_port, karateka_coco3 (11 files compared)     (from coco_agi)
[hal-sync] OK -- aligned with karateka_coco3, coco_agi (11 files compared)      (from POP3_port)
[hal-sync] OK -- aligned with POP3_port, coco_agi (11 files compared)           (from karateka)
CHECK OK: src/harness/vm_tables.s matches optable.py.

FAULT ARMS, both re-shown RED on THESE binaries:
  p3b_nomap   STUCK in cycle 30 after 1800 frames -- the cycle the command was fed
  p3b_notick  STUCK in cycle  9 after 1800 frames -- unchanged from T-P0-087
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact.
**25.3 operator-runtime-smoke:** **PASSED — Jay, live, RGB**, SpaceQuest-2 room 101, the T-P0-089
invocation. Jay: *"yes"* (it looks the same as then). ★★ Two observations from a second,
unapproved invocation are in §7.1 — **neither is a regression and both are real.**

### 5A — AC-4: the byte flow

| | before | after |
|---|---|---|
| region A code | $2000-$56EB | $2000-$570F (+36 B) |
| region A font | **$5800-$6000, 2,048 B** | ★ gone |
| region A ceiling | $5800 (the font) | $6000 (`MAP_RESERVED_END`) |
| **region A headroom** | **277 B** | ★★★★★ **2,289 B** |
| region B parser + buffers | $E000-$E3BA, 954 B | unchanged |
| region B vocabulary | **$E3BA-$FEF0, 6,966 B** | ★ gone |
| region B font | — | $E3BA-$EBBA, 2,048 B |
| region B free | 0 | **4,918 B** |
| the vocabulary | resident, slot 7 | block 6, slot 5, open during `par_parse` only |

★★ 277 + 2,048 − 36 = **2,289**. The 36 is the window's whole code cost: two calls around
`par_parse`, two around the boot-time self-test, four bytes of block setup, and a `jsr` replacing
`lda #$3D / sta $FFA5`.

★★★ **Two MMU writes per typed command.** Everything else in the phase model costs two per phase
transition, so the dictionary is now the cheapest mapped thing in the map.

### 6 — Reactive deviations and route accounting

1. ★★★★★ **§4A ORDERING WAS NOT FOLLOWED AND I AM REPORTING IT AS A DEVIATION, NOT AS A DETAIL.**
   The eye gate ran **after** the byte gates, not first. §4A exists because a byte gate cannot find
   a defect in glue it does not measure — ★★★ **and this task then discovered exactly such a gap
   (§4E) by reading, which is the argument for the rule rather than against it.** The eye gate did
   run before the report, and Jay's second invocation surfaced two things no byte gate names
   (§7.1), which is §4A.1's claim happening again.
2. ★★★ **A new gate row and a new fault row were added** (§4E). Not in the AC list. Without them
   the thing this task built would be exercised by nothing on the green path, which §2W forbids.
3. ★★ **`ph_blk_slot5` closes a gap the dispatch put out of scope by silence** (§4B.3). It is two
   bytes and the restore could not have lived anywhere else without the probe writing $FFA5 again.
4. **ROUTE ACCOUNTING.** I proposed no route beyond the dispatch's own. §1.1's "move code from A
   into B" is NOT what I did — **data moved, not code** — and §4B.2 says why that is better rather
   than merely different. Everything else in §4 and §5 is implemented as specified.
5. **`memmap.inc` untouched.** No `SHARED` file touched.

### 7 — Uncertainty flags

**7.1 ★★★★ The eye gate's second invocation, and both findings stand.** Kingquest1 jumped to room 1
with two fed commands — a configuration nobody had watched. Jay: *"it did not scroll all the text,
only the first line appeared. also no input line appeared to enter a command."*

- ★★★★★ **The absent input line is the tree's state, not a regression.** `promptKeyPress` has no
  port [T-P0-090]. Nothing draws a prompt and nothing can; the commands in that run were written
  into `P3_INBUF` by the host. **This is T-P0-092.**
- ★★★★ **The text is not attributed and I am not guessing.** `txt_wrap` (stringWordWrap) is ported
  and `TXT_ROWS` is 25, so multi-line display is implemented in principle. Whether the integrated
  path reaches it is a measurement nobody has taken. §6's "stop and report" applies; it is §8.2.
- ★★★ **The approved invocation is unchanged** and Jay confirmed it, so neither belongs to this
  task's diff.

**7.2 ★★★ Nothing asserts that `par_vocab` is dereferenced only inside the bracket.** §4D(2) is true
by grep today. A future caller could dereference it outside the window and get the object table,
and no check would object. ★★ The failure would be loud rather than silent (§4D(3)), which is why
this is a flag and not a blocker.

**7.3 ★★ The window is gated on ONE title's dictionary.** `p3b_parse` runs Kingquest1, whose
WORDS.TOK is **3,144 bytes** — under half the 6,828 the window is sized for. **A title that fills
the window is not exercised by any row** [L-86: a fixed sample that always passes is evidence about
the sample first]. The assertion covers the size; nothing covers a full window at runtime.

**7.4 ★ Block 6 is chosen from this file's own recorded allocation** (priority 0-1, shadow 2-5,
volumes 8-38, visible 40-43, $38-$3F the CPU window). The host's discrimination check is what proves
it is distinct memory rather than the arithmetic.

**7.5 ★★ AC-3's gate was not re-run, and it could not have tested this.** `parser_probe.s` stages a
**flat** vocabulary at its own address and never maps a window, so the 23,328 cases are silent about
windowing in both directions. What is offered instead: `parser.s` and `parser_probe.s` are
byte-unmodified in git, and `p3b_parse` / `p3b_nomap` gate the thing the change actually touches.
★ **Say plainly if that substitution is not accepted** — re-running it needs the oracle's case
limit, which §4E's precedent says was recovered by bisection once already.

### 8 — Follow-up candidates
1. ★★★★★ **T-P0-092: port `promptKeyPress`** (`text.cpp:720`). 2,289 bytes of headroom now exist
   against P6.35's 550-700 estimate. **This task's purpose is discharged.**
2. ★★★★ **Why only one line of text appears** (§7.1). It is an integration question and the eye gate
   is the only instrument that has ever asked it.
3. ★★★ **Gate a full window** (§7.3) — SpaceQuest-2's 6,828-byte dictionary through `p3b_parse`.
4. ★★★ **The engine's own vocabulary window has no client.** `MAP_VOCAB` now has code and nothing
   in `src/engine/` calls it; only the probe does.
5. ★★ **An assertion for §7.2.**
6. ★★ **`err 1`** in the p3b_box run, still unexplained across four tasks.

### 9 — User interaction during task
1. Eye gate, Kingquest1 room 1 with input — Jay: *"it did not scroll all the text, only the first
   line appeared. also no input line appeared to enter a command."* → §7.1, §8.1, §8.2.
2. Eye gate, SpaceQuest-2 room 101, the T-P0-089 invocation — Jay: *"yes"*, it looks the same.
   → 25.3.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-12-the-objection-was-about-residency-not-about-the-address.md`

### 11 — Commit
`494d910` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `a185279`, one row under `seeds/AGI/live/`.
