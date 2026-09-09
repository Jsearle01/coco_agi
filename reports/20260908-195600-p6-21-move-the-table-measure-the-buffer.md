## Form B Report — T-P0-077 (P6.21) — Move the table, measure the buffer, then build
**Class:** build.  wip.  ★★★★★ **A and B LANDED. C BUILT AND MEASURED, AND IT OVERFLOWS BY 84 BYTES
— §8 TRIGGER 1, on measured numbers rather than an estimate.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-08T19:56:40-04:00 (HEAD ea3cf03, wip). Working tree carries this task's changes only.
`coco_agi.code-workspace` is untracked editor state and is NOT staged.

---

### §5 — Pre-dispatch grep (verbatim, run not asserted)

```
=== coco_agi ===      ea3cf03  wip
=== POP3_port ===     104b197  wip   no dirty tracked files
=== karateka_coco3 == 29f8f0a  wip   M harness/smoke/last-run.log only

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi   (from POP)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi        (from Karateka)

★ gates run: pic res cel comp p3b  -- all green      [re-run AFTER the memmap.inc change]
  per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
  resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
  cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
  ★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ TEXT GATE PASS over all 9 titles     ★ PORT GATE PASS over all 9 titles
VM gate no-input arm: 9/9 PASS.  VM parser arm: 9/9 PASS, 6 of 9 fed input.
[reg-discipline] 8 register access(es) in 1 file(s): src/engine/mmu_phase.s $FFA5 $FFA6
```

★ **§2T:** P6.20 §0 recorded POP `104b197` and Karateka `29f8f0a`; **both unchanged and measured
again**, tracked source clean in both.

**Flag sets, enumerated and diffed** [L-77]:

| build | flags | bytes |
|---|---|---|
| `text_probe.bin` | *(none)* | 1,714 |
| `text_probe.bin` — wrap arm | `-DTXT_FAULT_WRAP` | 1,714 |
| `text_probe.bin` — printf arm | `-DTXT_FAULT_PRINTF` | 1,717 |
| `text_probe.bin` — **buffer arm, NEW** | `-DTXT_FAULT_PBUF` | 1,714 |
| `gs_probe.bin` — **NEW** | *(none)* | 2,375 |
| `reserved_fit.s` — **NEW**, red arm | `-DPLANE_WINDOWED` | *assertion fires* |
| `reserved_fit.s` — **NEW**, green arm | `-DPLANE_WINDOWED -DRF_NO_GETSTRING` | 2,432 |
| `text_show.bin` | *(none)* + `content/agi_palette.s` | 1,644 |

**Occupancy at HEAD, in bytes:** `MAP_RESERVED` 3,328 total — parser 954, text engine 1,411,
substitution buffer 768 → **195 free**. `MAP_VMSTATE` tail `$0DC0-$1000` → **576 free**.

**The substitution buffer's size, and what has ever measured it:** 768 B, and it *had* been
measured — `text_bufmax.py` in P6.18 reported max 490 and P6.19 sized 768 from it. ★★★ **But that
walk covered `swept_messages` only: 4,595 of 14,944 messages, 31%.** The dispatch's premise that
nothing had measured it is not quite right, and the real gap was coverage, not absence.

---

### 1 — Summary
**A and B landed and are gated.** The string table and input-line buffer moved to `MAP_VMSTATE`,
where they belong as VM state; the substitution buffer was re-censused at **99.99% coverage** and
the maximum is **still 490**, so it dropped 768 → 576 and returned 192 bytes. **C was built and
measured, which is what the ruling asked for, and the answer is a stop:** parser + text +
`get.string` is **2,836 bytes**, and with the 576 buffer that is **3,412 against 3,328 — over by
84.** The largest buffer that fits is **492**, two bytes above the measured maximum. ★★★★ **And
that is before the input line's key decoder, which does not exist: `HAL_input_poll` is
detection-only and returns no key code at all.** My P6.20 estimate of ~510 B of code was 9% low
against an actual 555 — good enough to have been trusted, and now it does not have to be.

---

### 2 — Files modified
- `src/engine/memmap.inc` — M. `MAP_STRINGS` (13 × 40 = 520 B) and `MAP_INPUTSTR` (42 B) in the
  VM state tail, with four assertions; 14 B spare.
- `src/engine/text.s` — M. Buffer 768 → 576 with the census recorded; `TXT_FAULT_PBUF` arm; the
  backspace arm of `txt_dispch`; `txt_clearcell` and `txt_celladdr`; `txt_ccb`.
- `src/engine/getstring.s` — **NEW**, 404 B. `gs_get_string` / `gs_edit` / `gs_keypress` /
  `gs_edit_on` / `gs_edit_off` / `gs_finish`.
- `src/harness/gs_probe.s` — NEW. Drives the ported `get.string` over staged cases.
- `src/harness/reserved_fit.s` — **NEW. The assertion that is the stop.**
- `tools/agivm/text.py` — M. `display_character` (three arms, shared cursor), `InputState`,
  `string_key_press`, `string_edit`, `get_string`.
- `harness/tools/subst_census.py` — NEW. The substitution census at full coverage.
- `harness/tools/text_port_run.sh` — M. The `--fault-pbuf` arm, with a per-title prediction.

---

### 3 — Reasoning

**A. The string table's move is right on ownership, and the space is a consequence.** [memmap.inc]
`strings[]` is written by `set.string`, `word.to.string` and `get.string` and read by `%s` — VM
state in exactly the way vars and flags are. `MAP_VM_OBJ` holds 16 × 42 = 672 B ending at `$0DC0`
and `MAP_DIRS` begins at `$1000`: **576 bytes**, and the table (520) plus the input line (42) is
562 of it, leaving 14. ★★ **13 slots, not the oracle's 25** — `string_census.py`, 889 logics at
100% walk coverage, highest slot touched is 12.

**B. The census at full coverage, and the useful result is that nothing moved.** [measurement]
`subst_census.py` substitutes **every message in every logic** — 14,943 of 14,944, 99.99% — and
with the **stricter `%m` model**: each logic substituting from *its own* texts, which is what
`curLogicNr` means in gameplay, rather than the sweep's logic 0.

```
  CORPUS MAX  raw 490   substituted 490   wrapped 474
  13,612 messages under 128 B; 5 over 384; longest is larry1 logic 37
```

★★★★ **Tripling the coverage did not move the bound: 490 was right and was not known to be right.**
★★ The stricter model earned itself anyway — BlackCauldron's raw max is 222 and its *substituted*
max is 291, so substitution genuinely expands there and the gate's logic-0 model cannot see it.
★ The one message not substituted is a SpaceQuest-2 `%m` cycle that recurses without terminating;
it is counted and excluded rather than silently skipped.

**So 576, not 512.** 576 carries 86 bytes over the maximum (1.18×) and returns 192. 512 would
return 256 and leave 22 bytes — 4.5% — on a nine-title sample of a much larger AGI universe.

**C. The build, and the number that stops it.** [measurement]

```
  parser + text + getstring            2,836 B     [reserved_fit.s, assembled]
  + substitution buffer                  576 B
  = 3,412  against MAP_RESERVED's       3,328 B    ->  OVER BY 84
  largest buffer that fits:              492 B     ->  2 bytes over the census maximum
```

★★★★★ **`src/harness/reserved_fit.s` is the artifact, not the arithmetic.** It orgs the three
engine files at `MAP_RESERVED` and refuses to assemble past `MAP_RESERVED_END`. ★★★ **It is the
only place the three are assembled together** — parser, text and getstring each have their own
probe with a flat 64 KB map, so **no gate this project has ever run would notice the reservation
overflowing.** That is P6.11's code-region overrun in a new region.

★★★★ **And it is two-sided** (§2W): with `-DRF_NO_GETSTRING` it assembles at 2,432 bytes, which is
P6.19's shipped engine and known to fit. An assertion nobody has seen pass is as untrustworthy as
one nobody has seen fail.

**D. What is NOT in the 2,836, and it is the larger half.** [authority: the HAL at HEAD]
★★★★★ **`HAL_input_poll` cannot tell you which key was pressed.** Its own header says
*"directional decode deferred to R-p25+"*, it returns `B = 0`, and it reports only a pressed-row
mask — *whether any* key is down. So AD-134's scheme has **no software path at all**, and the
~140 bytes I estimated for key decode in P6.20 is work that does not exist rather than a port of
something that does. **AC-9 is not "unfinished"; it is unbudgeted.**

**E. §2H's three checks on `get.string`.** (1) *A second mechanism?* Yes, and it changes the event
stream: `_inputCursorChar`. When non-zero, `inputEditOn`/`inputEditOff` bracket **every** keypress
with a backspace and a cursor glyph, so one typed letter emits three events. `get.string` leaves it
0; the command-line prompt does not. (2) *Name the caller.* `stringEdit` is called by
`cmdGetString`, `cmdGetNum` **and** `askForSaveGameDescription`, the last with `stringMaxLen == 30`
which text.cpp:959 tests by value. (3) *Grep the reports.* P6.19 §4 AC-9 listed `get.string`'s
requirements and P6.20 §5 established what patch 0010 logs; both hold, and this adds the echo's
own structure.

**F. §2S refs.** POP `104b197` wip, Karateka `29f8f0a` wip, measured this task. ScummVM at the pin
`9d9b9e93`.

---

### 4 — Verification (AC-by-AC)

- **AC-1** [class: **eye-gated**] — ★★★★ **NOT REACHED.** Both halves need work the stop blocks:
  the scroll panel needs `display`/`display.v` (still `vm_op_modelled`), and the echo needs the
  input line, whose key decoder does not exist (§3.D). ★★★ **P6.19 §9's prediction — white
  lettering at rows 6–18, columns 12–28 — stands unrefuted and untested.** §8 trigger 4 has not
  fired because the test has not run.
- **AC-2** [class: byte-comparable] — every gate RUN, verbatim in §5. `hal_sync` green ×3;
  `reg_discipline` unchanged at 8, all `mmu_phase.s`'s — **`getstring.s` adds zero.**
- **AC-3** [class: byte-comparable] — **the string table lives in `MAP_VMSTATE`** (`$0DC0`, 13 × 40),
  and the **nine-title state diff is unchanged, both arms, exclusion set EMPTY**: no-input 9/9,
  parser arm 9/9 with input fed to 6 of 9. The full suite was re-run *after* the `memmap.inc`
  change, not before.
- **AC-4** [class: state-comparable] — **the census, at 99.99% coverage**: substituted max **490**.
  Buffer sized to **576**, headroom **86 B = 1.18×**, named. §3.B.
- **AC-5** [class: state-comparable] — ★★★★★ **RE-STATED IN BYTES AND IT IS THE STOP.** 2,836 +
  576 = 3,412 against 3,328, **over by 84**; largest viable buffer 492, two bytes over the census
  maximum. Before the key decoder. §3.C.
- **AC-6** [class: byte-comparable] — ★★★★★ **the overflow arm, and it is self-checking.**
  `--fault-pbuf` shrinks the buffer to 256 and the gate must go red **on exactly the titles whose
  swept maximum exceeds 256**:

  | title | swept max | predicted | observed |
  |---|---|---|---|
  | Kingquest1 | 203 | agree | agree ✓ |
  | Kingquest2 | 248 | agree | agree ✓ |
  | Kingquest3 | 458 | **diverge** | diverge ✓ |
  | SpaceQuest-1 | 334 | **diverge** | diverge ✓ |
  | SpaceQuest-2 | 274 | **diverge** | diverge ✓ |
  | PoliceQuest1 | 275 | **diverge** | diverge ✓ |
  | larry1 | 490 | **diverge** | diverge ✓ |
  | BlackCauldron | 222 | agree | agree ✓ |
  | MixedUpMotherGoose | 55 | agree | agree ✓ |

  ★★★★ **An arm that merely "fails somewhere" would pass even if it failed for the wrong reason.**
  This one fails if a title diverges that should not, *or* agrees when it should not — and the
  runner encodes the set, so nobody has to read this table to check it. Trigger 3 does not fire.
  ★ The renderer and text gates are unchanged with the smaller buffer: 45/45 and 9/9.
- **AC-7** [class: state-comparable] — ★★★ **`get.string` in the reference**: `get_string`,
  `string_edit`, `string_key_press`, `_edit_on/_edit_off`, and `display_character` with its three
  arms over a shared cursor. **The text gate is 9/9 after the refactor**, which is what checks that
  moving the cursor out of `_display_text` changed no behaviour. ★★ **It is NOT gated against the
  oracle**: driving `get.string` there needs a keystroke-fed sweep, which is an oracle change this
  task did not reach. What patch 0010 would and would not see is settled (§3.E, P6.20 §5).
- **AC-8** [class: byte-comparable] — ★★ **`gs_probe.s` is written and assembles (2,375 B), and
  the gate was NOT run.** The port it would gate cannot ship: AC-5 says it does not fit. Running it
  would produce a per-title table for code that has no home.
- **AC-9** [class: byte-comparable] — **NOT REACHED, and §3.D is why.** No key in AD-134's scheme
  was found unreachable because none was read: **trigger 5 is untested, not clear.**
- **AC-10** [class: state-comparable] — **NOT REACHED** (the input line's cost). ★★ P6.19's
  measured 2,970 cycles/glyph still bounds it: a 40-column redraw is ~119,000 cycles, 6.6% of a
  second at 1.789 MHz, **and the input line does not block**.
- **AC-11** [class: state-comparable] — §2V's table. ★★★ **Per L-105, the structures BUILT are
  enumerated first**, then diffed against the prediction:

  | built | predicted? | form | verdict |
  |---|---|---|---|
  | string table, 13 × 40 | yes (P6.20) | flat array in VM state | held; **13 not 25**, measured |
  | `_inputString`, 42 B | yes (P6.20) | fixed buffer | held exactly |
  | 10 edit scalars | yes (P6.20) | one byte each | held; **but they live with the CODE, not at a `MAP_` address** — indexed addressing to save 10 B in a 387 B region is a bad trade |
  | `gs_key` | **no** | 1 B | **NEW** — `stringKeyPress` takes its key by value; the 6809 needs it saved across `gs_edit_on` |
  | `gs_done` | **no** | 1 B | **NEW** — the inner loop is the CALLER's, so its exit flag must be shared state rather than a return value |
  | `txt_ccb` | **no** | 2 B | **NEW** — backspace needs its own callback because patch 0010 does not log it, so it is a different record type |
  | `txt_celladdr` | **no** | ~40 B | **NEW** — factored out of `txt_blit` so the clear and the draw cannot drift |

  ★★★★ **Three of the four unpredicted rows exist because the inner loop does not transfer.** The
  engine re-enters its event pump without advancing the cycle; the port cannot, so start/keypress/
  finish are split and the state that a C function would hold in locals becomes shared bytes.
  ★★★ **That is the L-105 shape again: the prediction described the DATA and the miss was in the
  CONTROL FLOW**, which the table has no column for.
- **AC-12** [class: state-comparable] — occupancy after:

  | region | contents | free |
  |---|---|---|
  | `MAP_RESERVED` 3,328 | parser 954, text 1,478, buffer 576 | **320** *(without `get.string`)* |
  | | + `get.string` 404 | **−84 — does not assemble** |
  | `MAP_VMSTATE` tail 576 | string table 520, input line 42 | **14** |

  ★★★ **320 B for sound if `get.string` does not land; −84 if it does.** Sound remains unsized.
- **AC-13** [class: state-comparable] — §7.
- **AC-14** [class: suite] — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
★ gates run: pic res cel comp p3b  -- all green
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ TEXT GATE PASS over all 9 titles
★ PORT GATE PASS over all 9 titles
=== AC-2 SUMMARY === (no-input) all nine PASS
=== AC-2 SUMMARY === (parser)   all nine PASS, 6 fed input
compared: 600 cycles x 288 bytes, exclusion set EMPTY;  divergent cycles: 0 of 600
```

```
title                 logics     msgs printf'd   raw max subst max  wrap max
Kingquest1                90     1441     1441       294       294       294
Kingquest2               133     1321     1321       251       251       251
Kingquest3               125     2072     2072       458       458       458
SpaceQuest-1             101     1772     1772       477       474       474
SpaceQuest-2             118     1828     1827       323       323       323
PoliceQuest1             118     3416     3416       310       310       310
larry1                    46     1850     1850       490       490       344
BlackCauldron             85      968      968       222       291       291
MixedUpMotherGoose        73      276      276       108       108       108
coverage: 14943 of 14944 messages substituted (99.99%)
CORPUS MAX  raw 490   substituted 490   wrapped 474
  at  512 B: headroom   +22  ★ 1.04x
  at  576 B: headroom   +86  ★ 1.18x
  at  768 B: headroom  +278  ★ 1.57x
```

```
★ pbuf fault CAUGHT on all 9 titles -- the gate can go red on this stage
```

```
=== reserved_fit.s, RED (with get.string) ===
src/harness/reserved_fit.s(39) : ERROR : User Specified: "MAP_RESERVED OVERFLOW -- parser +
text + getstring + substitution buffer exceed the reservation. This is the stop, not a nudge:
M-48 is spent, MAP_CODE has 5 bytes, and growing the region is a map change."

=== reserved_fit.s, GREEN (-DRF_NO_GETSTRING) ===
assembled OK: 2432 bytes

=== the arithmetic the assertion enforces ===
parser+text+getstring = 2836
  + buffer 576 = 3412  vs 3328  -> over by 84
  max buffer that fits  = 492   vs census max 490 -> headroom 2
```

```
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[reg-discipline] 8 register access(es) in 1 file(s): src/engine/mmu_phase.s $FFA5 $FFA6
```

**§2W — instruments shown able to fail:**
- The **buffer arm** fails on exactly the five predicted titles and correctly agrees on the other
  four; the runner asserts the set, not merely "something failed" (AC-6).
- The **fit assertion** is two-sided: red with `get.string`, green without, at 2,432 bytes.
- `subst_census.py` prints coverage beside its answer and **refuses to print a bound when nothing
  was substituted** — the discipline `string_census.py` needed twice in P6.20.
- The wrap and printf arms still fail on 9/9 (P6.19's arms, re-run under the smaller buffer).

**25.2 bundled-artifact grep:** N/A — no delivery artifact is produced or changed. `reserved_fit.s`
deliberately produces nothing anybody runs; assembling it *is* the test.

**25.3 operator-runtime-smoke:** **N/A — not reached.** AC-1 depends on work the stop blocks.

---

### 6 — Reactive deviations and route accounting
**Deviations (§22.5):** one, and it is Jay's ruling rather than mine. P6.20's trigger 1 said stop;
Jay chose **(a) — resolve the estimate by building and let the assertions be the stop.** I built A,
B and C and stopped at the assertion. ★★ The estimate is now retired: ~510 predicted against 555
actual, 9% low.

★ **One correction made in passing:** the first draft of `memmap.inc`'s new block declared
`MAP_INPUTSTATE` for the ten edit scalars, and the port keeps them with its code. **A declared
address the engine does not use is a §2F violation with no symptom** — the map says one thing and
the code does another and nothing ever disagrees out loud. Removed.

**Route accounting: what I did NOT implement, explicitly.** The `gs_probe` gate run (AC-8) — the
probe assembles but gating code that cannot ship would produce a per-title table for nothing. The
input line and its key decoder (AC-9), the cost (AC-10), and the eye gate (AC-1). An oracle sweep
for `get.string` (AC-7's oracle leg).

---

### 7 — Uncertainty flags
- ★★★★★ **The key decoder is unbudgeted, not merely unwritten.** `HAL_input_poll` returns no key
  code. Whatever number closes the 84-byte gap must also carry AD-134's decode.
- ★★★★ **A 492-byte buffer would "fit" with two bytes over the measured maximum.** I did not take
  it. 0.4% headroom on a nine-title sample is not a margin, and the failure mode is a truncated
  message in a title nobody gated.
- ★★★ **13 slots is a corpus maximum, not a bound**; agi.h's is 25. `MAP_STR_SLOTS` is one constant
  and the assertion moves with it, but a 25-slot table needs 1,000 B and the tail has 576.
- ★★★ **`get.string`'s reference is not oracle-gated.** It matches the reference's own model of the
  pin; the oracle has never executed it under instrumentation.
- ★★ **Backspace is invisible to patch 0010** (`clearBlock` has no `drawCharacter`), so the 'C'
  records are 6809-against-Python only. One `oracleLogText` call would fix it.
- ★ **Sound is still unsized**, and now has 320 B rather than 195 — but only while `get.string`
  stays out.

---

### 8 — Follow-up candidates
- ★★★★★ **The 84 bytes — Jay's.** The options the dispatch names: `MAP_CODE` (5 bytes, M-48
  spent) or `MAP_DIRS`, where 1,024 B/type serves 341 slots against a 216 present max — **~1,504 B
  recoverable there**, and it is the only place with room for both the gap and the key decoder.
- ★★★★ **The eight text opcodes** — `display`, `display.v`, `print`, `print.at`, `clear.lines`,
  `close.window`, `status.line.on/off`. ★★★ **They need no string table, no input buffer and no key
  decode**, and `get.string` staying out leaves 320 B. **This is the reachable slice of AC-1.**
- ★★★ **`HAL_input_poll`'s key decode** — R-p25's deferred work, and a HAL change is a three-repo
  change (§2M).
- ★★ One `oracleLogText` in `clearBlock`; the message-box border; §2B's authored font.
- ★ p3b's missing `PIC_NOCOUNT` (thirteen tasks); `-DVM_VBLCLOCK` runaway into `$0400-$05FF`.

---

### 9 — User interaction during task
★★★ **One.** Mid-task I reported that AC-5's gap was inside my own estimate's error bar, and that
`HAL_input_poll` turned out to be detection-only, and asked whether to (a) resolve the estimate by
building and let `memmap.inc`'s assertions be the stop, or (b) stop on the estimate. **Jay: "a".**
This report is that instruction carried out: A, B and C built, and the stop taken at the assertion
rather than at the arithmetic.

---

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-08-no-gate-sees-the-region-every-component-is-gated-in-isolation.md`

---

### 11 — Commit
`6a96379` — pushed to origin/wip, carrying every file in §2 including this report. ★ Corrected by
one follow-up commit, since a report cannot name the hash of the commit that contains it.
