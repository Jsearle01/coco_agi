## Form B Report — T-P0-075 (P6.19) — Port the text engine
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-08T17:34:53-04:00 (HEAD 8ce5129, wip). Working tree carries this task's new files only
(§2). `coco_agi.code-workspace` is untracked editor state and is NOT staged.

---

### §4 — Pre-dispatch grep (verbatim, run not asserted)

```
=== coco_agi ===      8ce5129  wip   (clean but for this task's untracked files)
=== POP3_port ===     104b197  wip   (clean; untracked = gitignored ground-truth PDFs, nvram)
=== karateka_coco3 == 29f8f0a  wip   (untracked PDFs; M harness/smoke/last-run.log only)

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi  (from POP)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi       (from Karateka)

★ gates run: pic res cel comp p3b  -- all green
  per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
  resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
  cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
  ★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
VM gate no-input arm: 9/9 PASS.  VM gate parser arm: 9/9 PASS (6 of 9 fed input).
Reference text gate: ★ TEXT GATE PASS over all 9 titles.

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   8   $FFA5 $FFA6      ← text.s contributes ZERO
```

★ **§2T note:** P6.18 §0 did not record sibling artifact hashes, so §2T.1 item 4 applies and both
siblings were measured directly rather than cited. Neither has dirty tracked source.

**Flag sets, enumerated and diffed** [L-77] — three builds of one source:

| build | flags | bytes |
|---|---|---|
| `text_probe.bin` (gate) | *(none)* | 1,714 |
| `text_probe.bin` — AC-4 arm 1 | `-DTXT_FAULT_WRAP` | 1,714 |
| `text_probe.bin` — AC-4 arm 2 | `-DTXT_FAULT_PRINTF` | 1,717 |
| `text_show.bin` (eye gate) | *(none)*, + `content/agi_palette.s` | 1,644 |

★★ The printf arm is **3 bytes larger, and that mattered**: the extra bytes pushed `beq tp_g` out
of short-branch range, so the arm *would not assemble*. A fault arm that cannot be built is a
stage that cannot be tested — the dispatch's §7 trigger 3 in a form I did not expect. All six
dispatch branches are long now.

`MAP_RESERVED` before: 3,328 B total, parser 954 → 2,374 free. `MAP_CODE` spare: 5 bytes.

---

### 1 — Summary
The text engine is ported and gated: **9/9 titles, 4,594 rectangles and 293,648 glyphs identical in
position, colour and checksum** against the reference, at exactly the cases the reference matches
the oracle on. Both fault arms fail on all nine, at the same message indices the reference's own
arms produce. §2V's table has its second column: **nine predictions held, two differ — both making
the port smaller — and two structures were not predicted at all**, both of them "Python carries
metadata a byte does not". The engine is 1,411 bytes and its substitution buffer 768; `MAP_RESERVED`
is now 94% committed with sound unwritten, which is the number this report most wants read. AC-1 is
**pending Jay**, with a specific thing to look at.

---

### 2 — Files modified
- `src/engine/text.s` — NEW, 1,411 B assembled. `txt_printf` / `txt_wrap` / `txt_msgbox` /
  `txt_dispch` / `txt_close` / `txt_attrib` / `txt_blit`, plus §2V's filled table in the header.
- `src/harness/text_probe.s` — NEW. Drives the engine over the gate's messages, chunked.
- `src/harness/text_show.s` — NEW. AC-1's eye probe and AC-7's timing loop.
- `harness/tools/text_port_gate.py` — NEW. Emits the cases; diffs 6809 against the reference.
- `harness/tools/text_port_gate.lua` — NEW. MAME host: stages, paces, reads records.
- `harness/tools/text_port_run.sh` — NEW. The port gate over its declared nine-title corpus.
- `harness/tools/text_show.lua` / `text_show.sh` — NEW. The eye gate, throttled (§2U.2).
- `harness/tools/text_cost.lua` — NEW. AC-7, two arms.
- `harness/tools/text_bufmax.py` — NEW. Sizes the buffer from the corpus.
- `harness/tools/text_font_stage.py` — NEW. Font to `build/` only; NOT §2B's authored asset.
- `harness/tools/text_tail.py` — NEW. Answers Jay's scroll-panel question (§9).

---

### 3 — Reasoning

**A. What the port is compared against, and why that chain is sound.** [authority: measurement]
The 6809 is diffed against `tools/agivm/text.py`, which `text_run.sh` re-gates against the pinned
oracle **in this same task** — 9/9, so the baseline is not stale [L-70]. Diffing the 6809 straight
against ScummVM would be the same comparison with a longer chain and one more thing to get wrong;
if the port ever diverges, bisecting is one step [L-36].

**B. §2V's second column, and the two rows that moved.** [authority: measurement]
Full table is in `src/engine/text.s`'s header, at the decision, as §2V requires. The two that
differ both made the port **smaller**:

- ★★★★★ **The wrap's 2,000-byte output buffer does not exist.** The prediction was emphatic that
  the two stages "cannot share one buffer because the wrap READS the printf output while WRITING
  its own." True of the oracle — and the port does not write one at all. The wrapped string's only
  consumer is `displayText`'s per-character loop, so the port **streams** it through a sink. The
  geometry must be known before the glyphs are placed, so the wrap **runs twice**: 1,024+ bytes of
  RAM traded for a second pass over at most 490 characters, and on this machine RAM is the scarce
  one.
- ★★★★ **The checksum is computed, and in 16 bits.** The table said "gate-only; the port has no
  reason to compute it" — but the port's gate needs it. It is 32 bits in the oracle and **16 here,
  exactly**: only the low 16 bits are ever logged, and multiply-and-add are closed mod 2^16, so a
  16-bit accumulator produces the identical sequence. Half the state, no 32-bit multiply.

The row `parser.py`'s precedent said to watch — *"'the message is not copied' is the claim most
likely to conceal a copy"* — **held.** No copy exists on the path.

**C. The two structures nobody predicted are the same lesson twice.** [authority: measurement]
★★★★★ **A NUL terminator.** `txt_printf` built the substituted string and never terminated it;
`txt_wrap` reads until NUL, so it walked off the end into the previous message's bytes. **Every
rectangle came out 30 wide and 21 tall** — max width, one past the height cap — and the gate
reported *"box WIDTH and HEIGHT both differ"* on message 0, with 235,071 glyphs against 32,105.
★★★★ **That names the wrap, and the wrap was correct.** A Python `str` carries its length; a 6809
byte buffer carries nothing. The second is `txt_fbrows` — how many character rows a framebuffer
window holds is a property of the *map*, 5 through one 8 KB slice and 24 through a flat plane, and
a constant there silently refuses every glyph below row 5.

> §2V.2 lists strings, residency, lookup and unbounded containers. **"A container that knows where
> it ends" belongs on that list and is not on it.** Both omissions produced plausible wrong output
> rather than a crash.

**D. §2H's three checks on the reference.** (1) *A second mechanism for a different object class?*
Yes — `%g`/`%w`/`%0` append **literally** while `%s`/`%m` **recurse**, so a `%` inside a `%g`
substitution is not a code. Reading only the recursion would have made all six the same. (2) *Name
the caller.* `drawMessageBox` is not the only caller of this pair: `cmdGetString` (op_cmd.cpp) runs
`stringPrintf → stringWordWrap(…, 40) → displayText` with max_width **40, not 30**, which is why
`txt_maxw` is a variable. (3) *Grep the reports for the subsystem.* P6.17 established the wrap,
P6.18 the substitution and that `%m` reads logic 0 in the sweep; this report contradicts neither.

**E. A latent divergence in the reference, found by porting.** [authority: ScummVM at the pin]
`startingRow = ((HEIGHT_MAX - height - 1) / 2) + 1` is **C division, truncating toward zero**;
Python's `//` **floors**. They differ only when the numerator is negative, i.e. `height == 20`. The
reference uses `//`, so **`text.py` disagrees with the oracle for any message that wraps to exactly
twenty lines.** Unreachable in the corpus — the reference matches all 4,594 rectangles, so no
message does — but the port follows the **oracle** (§2), and this is recorded rather than silently
matched. ★ A title outside the corpus can reach it.

**F. §2S refs.** POP `104b197` wip, Karateka `29f8f0a` wip, both measured this task, tracked source
clean in both. ScummVM at the pin `9d9b9e93`, with P6.18's sweep amendment in the working tree.

---

### 4 — Verification (AC-by-AC)

- **AC-1** [class: **eye-gated**] — ★★★★★ **PENDING JAY.** `sh harness/tools/text_show.sh
  Kingquest1 12` runs it, **throttled** (§2U.2 — an eye gate nobody can watch at 2869% is not an
  eye gate). Launch path **`poke`**, RGB, `screen_config=1`. What to look for is in the script's
  header and in §9 below. **Headless readback confirms ink reaches the plane where the decision
  layer puts it** — box 1 draws into rows 10–14 and the port gate's own rectangle for that message
  is `srow=8, boxh=5, trow=10`. That is a framebuffer readback (structured text, §3), *not* a
  substitute for the gate: it cannot tell a letter from a smudge.
- **AC-2** [class: byte-comparable] — every gate RUN, verbatim in §4's grep and §5. `hal_sync`
  green in all three repos; `reg_discipline` shows **text.s contributes zero register accesses**.
- **AC-3** [class: byte-comparable] — **the port gated against the reference at the same cases.**
  Per title, not a total [L-10]:

  | title | messages | rectangles | glyphs | result |
  |---|---|---|---|---|
  | Kingquest1 | 596 | 596/596 | 32,105/32,105 | PASS |
  | Kingquest2 | 536 | 536/536 | 35,988/35,988 | PASS |
  | Kingquest3 | 743 | 743/743 | 56,290/56,290 | PASS |
  | SpaceQuest-1 | 515 | 515/515 | 32,825/32,825 | PASS |
  | SpaceQuest-2 | 574 | 574/574 | 43,376/43,376 | PASS |
  | PoliceQuest1 | 660 | 660/660 | 40,379/40,379 | PASS |
  | larry1 | 316 | 316/316 | 20,560/20,560 | PASS |
  | BlackCauldron | 427 | 427/427 | 27,933/27,933 | PASS |
  | MixedUpMotherGoose | 227 | 227/227 | 4,192/4,192 | PASS |
  | **TOTAL** | **4,594** | **4,594** | **293,648** | **9/9** |

- **AC-4** [class: byte-comparable] — **the gate can fail, on this build and this corpus, in both
  stages.** The faults live in `src/engine/text.s` (`TXT_FAULT_WRAP`, `TXT_FAULT_PRINTF`), not in
  the comparator, so the gate cannot manufacture its own failure. First divergent rectangle:

  | title | wrap fault | printf fault |
  |---|---|---|
  | Kingquest1 | 0 | 555 |
  | Kingquest2 | 3 | 371 |
  | Kingquest3 | 11 | 530 |
  | SpaceQuest-1 | 7 | 223 |
  | SpaceQuest-2 | 9 | 22 |
  | PoliceQuest1 | 16 | 431 |
  | larry1 | 18 | 36 |
  | BlackCauldron | 4 | 351 |
  | MixedUpMotherGoose | 79 | 1 |

  ★★★★ **These are the same indices the REFERENCE's own two arms produced in P6.18** — the same
  fault in either leg diverges at the same message. Two independent implementations agreeing on
  where a defect first shows is a stronger statement than either arm alone.
- **AC-5** [class: state-comparable] — **§2V's table with its second column filled**, in
  `src/engine/text.s`'s header at the decision. Eleven predicted rows: **nine held, two differ,
  two more were unpredicted.** §3.B and §3.C above.
- **AC-6** [class: state-comparable] — occupancy:

  | | bytes |
  |---|---|
  | `MAP_RESERVED` total | 3,328 |
  | parser (code + state + two 42 B buffers) | 954 |
  | **text engine** (code + state) | **1,411** |
  | **text substitution buffer** | **768** |
  | **remaining for sound** | **195** |

  ★★★★ **That is 94% committed with sound unwritten, and it is the number in this report I most
  want read.** It fits, so §7 trigger 2 did not fire on the letter of its wording — but it fits by
  consuming what sound will need, which is the spirit of it. **`MAP_CODE` spare is unchanged at 5
  bytes**: nothing this task touches lives there, and p3b's own `ifgt P3_CODE_END-MAP_CODE_END`
  assertion did not fire.
- **AC-7** [class: state-comparable] — **rendering cost, measured, two arms differing in exactly
  one thing** (`TC_NOBLIT`), 50 iterations of one 105-glyph message, no clear and no handshake
  inside the interval:

  | arm | per message window | per glyph |
  |---|---|---|
  | decision + blit | **366,182 cycles** | **3,487** |
  | decision only | 54,360 cycles | 518 |
  | **blitter (difference)** | **311,822** | **2,970 — 85%** |

  Clock **894,886 Hz, read from the machine and printed beside the figure**, not labelled
  [p3b_run.lua printed "@1.789390 MHz" while running at 0.894]. `m.time` is emulated, so
  `-nothrottle` cannot move it (§2U.1). **What it competes with:** one message window is 366,182
  cycles ≈ 0.41 s at this clock, 0.205 s at 1.789 MHz — and P6.9 measured a p3b `interpret` cycle
  for room 83 at 0.07067 s, so **a message window costs roughly three AGI cycles' worth of time,
  and the cycle does not advance while it is up.** For a blocking message box that is invisible.
  ★★★ For the status line and the input line, which do **not** block, it is not: at 2,970
  cycles/glyph a 40-column status line is ~119,000 cycles, 6.6% of a 1.789 MHz second, every time
  it is redrawn. §7 trigger 5 — **reported, not fixed here.** The blitter uses extended addressing
  throughout; direct page and an unrolled inner loop are the obvious first moves.
- **AC-8** [class: byte-comparable] — **the nine-title state diff unchanged, both arms, exclusion
  set EMPTY.** No-input 9/9 PASS; parser arm 9/9 PASS with input fed to 6 of 9. Verbatim in §5.
- **AC-9** [class: state-comparable] — `get.string`'s requirements, now that the display buffer
  exists on both legs. Recorded at the foot of `tools/agivm/text.py` in P6.18 and **unchanged by
  this task except in one respect: its lead-in text path is now BUILT on the target too** —
  `txt_printf` → `txt_wrap` at `txt_maxw = 40` → `txt_dispch`. What remains is input and cursor
  state: a one-deep saved cursor, edit-state restored to *previous* rather than off, the 1,000-byte
  string table `%s` reads, and `cycleInnerLoopActive(CYCLE_INNERLOOP_GETSTRING)` — **which is a VM
  question, not a text one.** The port's main loop has no nested-cycle re-entry, the same shape as
  `have.key`.
- **AC-10** [class: state-comparable] — what this found that the dispatch did not anticipate: §7.
- **AC-11** [class: suite] — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
★ gates run: pic res cel comp p3b  -- all green
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
```

```
=== AC-2 SUMMARY ===  (VM gate, no-input arm)          === parser arm ===
Kingquest1 PASS  Kingquest2 PASS  Kingquest3 PASS       9/9 PASS, 6 of 9 fed input
SpaceQuest-1 PASS  SpaceQuest-2 PASS  PoliceQuest1 PASS
larry1 PASS  BlackCauldron PASS  MixedUpMotherGoose PASS
compared: 600 cycles x 288 bytes, exclusion set EMPTY;  divergent cycles: 0 of 600
```

```
★ TEXT GATE PASS over all 9 titles          (the reference leg, re-gated this task)
★ PORT GATE PASS over all 9 titles          (the 6809 leg)
=== port gate: Kingquest3 ===
  messages     : 6809 743   reference 743
  glyphs       : 6809 56290   reference 56290
  OK rectangles identical (743)
  OK glyphs identical in position, colour and checksum (56290)
```

```
★ wrap fault CAUGHT on all 9 titles -- the gate can go red on this stage
★ printf fault CAUGHT on all 9 titles -- the gate can go red on this stage
```

```
ARM noblit=0  iter=50  glyphs/msg=105
  20.4597 s emulated, 18309078 cycles total  [894886 Hz via coco3 power-on rate]
  per message window: 366182 cycles     per glyph: 3487 cycles
ARM noblit=1  iter=50  glyphs/msg=105
  3.0372 s emulated, 2717987 cycles total   [894886 Hz via coco3 power-on rate]
  per message window: 54360 cycles      per glyph: 518 cycles
```

```
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s    8   $FFA5 $FFA6
```

**§2W — every instrument shown able to fail:**
- Both fault arms: FAIL on 9/9, at distinct and reproducible indices (AC-4).
- ★★★★★ **The fault arms themselves failed their first outing, and that is the §2W finding of this
  task.** `text_port_run.sh` originally passed the fault to **both legs** — `-DTXT_FAULT_WRAP` to
  the assembler *and* `--fault-wrap` to the comparator — so the 6809 and the Python were faulted
  identically, agreed, and the arm printed **PORT GATE PASS over all 9 titles** from a build whose
  entire purpose was to fail. **That is L-73 exactly** (an ablation moving the same variable in
  both arms exonerates nothing), and it is §2W in its most embarrassing form: the instrument
  written to prove the gate could go red was the one that could not.
- The probe's result-buffer bound check **overflowed and therefore passed** when it should have
  failed (`tx_out + 4812 < TX_RES_END` wraps past `$FFFF`); the cursor ran to `$173E` and wrote
  glyph records over the probe's own code. Replaced with a subtraction, which cannot wrap that way.
- The cost instrument's first form measured the harness: a 3-glyph message "cost" 84,626
  cycles/glyph and a 96-glyph one 6,067. **A per-unit cost that falls as units are added is a fixed
  overhead being divided** — a plane clear and frame-quantised handshakes. Replaced with the
  iteration loop in §4 AC-7.
- `text_font_stage.py` refuses to write a table that is not exactly 2,048 bytes of byte-valued
  entries [AD-125: a wrong table assembles fine and means something else].

**25.2 bundled-artifact grep:** N/A — no delivery artifact (`LOADER.BIN`, DMK) is produced or
changed by this task. The engine is a source file and two probes.

**25.3 operator-runtime-smoke:** **pending Jay** — AC-1, `sh harness/tools/text_show.sh
Kingquest1 12`, launch path **`poke`**, RGB. Not a delivery gate: `poke` hides load and launch bugs
(§4), and this is a component eye gate.

---

### 6 — Reactive deviations and route accounting

**Deviations (§22.5):** three, all reported rather than absorbed.

1. ★★★★ **§4A's ordering was NOT met: the byte gate ran before the eye gate.** §4A binds the eye
   gate first on integration tasks and I ran AC-3 first. The honest reason is that there was
   nothing to show until the engine was correct — the first three runs produced a blown stack, a
   runaway write cursor and 235,071 glyphs — but *that is a reason, not a justification*, and §4A
   exists precisely because "I'll show it once it works" is how a defect reaches a byte gate that
   cannot see it. **Reported as a deviation; AC-1 is still pending Jay and the task is not closed
   without it.**
2. **A font was staged from the oracle into `build/`.** §2B's authored 8×8 font does not exist yet,
   and an eye gate with placeholder letterforms cannot answer "is this right?". `text_font_stage.py`
   extracts ScummVM's PC-BIOS table **to `build/` only**, never to `content/`, never committed. The
   tool is to be deleted when §2B's font is authored.
3. **`text_show.s` maps the framebuffer flat across slots 4–7**, where `memmap.inc` gives it one
   window in slot 6. `src/harness/` keeps its own addresses by that file's own header; the engine
   is unchanged and takes the window base as a parameter, so **the gate probe and the eye probe run
   the same object code**.

**Route accounting:** I proposed no route beyond the dispatch's AC list. Everything in §2 is an
AC's deliverable or one of the three deviations above. **What I did NOT implement, explicitly:**
the message box's *border* — the oracle's `_gfx->drawBox` at text.cpp:507. The reference does not
model it either (patch 0010 logs no box draw), so it is outside both gates; Jay will see white
text cells with black letters and **no red border**. That is a gap, not an oversight, and it is in
§8.

---

### 7 — Uncertainty flags
- ★★★★ **`MAP_RESERVED` is 94% committed and sound has 195 bytes.** The engine fits; sound does
  not, on any plausible estimate. ★★★ **One concrete option, offered rather than taken:** the
  substitution buffer is 768 B and `MAP_SEEDSTACK` is 768 B, and the two are never live at the same
  time — a message window is not open while a picture is flood-filling (§2R.1's disjoint phases).
  Aliasing them is a *design* decision with a real hazard, so it is surfaced here, not done.
- ★★★ **The blitter is 85% of the rendering cost and is unoptimised.** 2,970 cycles/glyph, all
  extended addressing. Material for the non-blocking status and input lines (AC-7).
- ★★ **`%0` and `%s` are still untested against real data.** `%0` appears in no staged title; `%s`
  appears 189 times but both legs read an empty string table because the sweep runs at init. **The
  recursion path in `txt_printf` has no positive evidence** — the source-stack rewrite is gated
  only on `%m`, which the corpus does exercise 1,044 times.
- ★★ **`text.py` has a latent divergence from the oracle** at `height == 20` (§3.E). Unreachable in
  this corpus; the port follows the oracle.
- ★ **The eye gate's launch path is `poke`**, which hides load and launch bugs (§4).
- ★ **`txt_blit` refuses a glyph that would straddle its window** rather than remapping. That is a
  display-driver question (§2R.1) and belongs with the display driver.

---

### 8 — Follow-up candidates
- ★★★★ **The eight text opcodes** — `display`, `display.v`, `print`, `print.v`, `print.at`,
  `print.at.v`, `clear.lines`, `clear.text.rect`, `close.window`, `status.line.on/off` are all
  still `vm_op_modelled`. **The engine they need now exists and is gated.** §9 shows this is what
  the empty scroll panel is waiting on.
- ★★★ **The message-box border** (`drawBox`, text.cpp:507) — unmodelled on both legs, so it needs
  an oracle change before it can be gated, not just a port change.
- ★★★ **`MAP_RESERVED`'s budget** — a decision, not a task. See §7.
- ★★ **The blitter's cost** — direct page and an unrolled inner loop (AC-7).
- ★★ **§2B's authored 8×8 font**, which `text_font_stage.py` is standing in for.
- ★ **`get.string`** — AC-9; blocked on the VM's missing nested-cycle re-entry, shared with
  `have.key`.
- ★ p3b's missing `PIC_NOCOUNT` (eleven tasks); `-DVM_VBLCLOCK` runaway into `$0400-$05FF`.

---

### 9 — User interaction during task

**Jay, mid-task, watching a live run:** *"I see the title screen, but the scroll area — the middle
part of the screen — is just black with no words."*

★★★★★ **Answered: the words are TEXT, and Jay's reading was right against the Orchestrator's
expectation that the scroll's lettering is picture geometry.** Three pieces of evidence, all from
work already in the tree:

1. **The oracle draws them, and they are text.** `harness/tools/text_tail.py` (new) cuts patch
   0010's log at the last restore rectangle; everything after it is the *game running* rather than
   the sweep. Kingquest1 has **3,611 glyph draws** there, in a solid block at **rows 6–18, columns
   12–28**, plus rows 22 and 24. A centred rectangle 13 rows tall and 16 wide is the scroll panel.
   Colours are `fg15/bg0` — **invert bit clear**, which is `display`'s attribute, not a message
   box's `(15,8)`.
2. **Our leg cannot draw them.** `display` (103) and `display.v` (104) are `modelled` — declared
   no-ops. The panel is empty because nothing has ever tried to fill it.
3. **It is not dropped picture geometry.** Picture 83 renders byte-identical to the oracle on both
   planes. We draw exactly what the oracle draws, so an empty panel on our side means the oracle's
   picture 83 is empty too — **the words were never in the geometry.** The border Jay can see is
   the picture. ★★ So the renderer is not implicated and there is no finding behind the 53/53.

★★★★ **This makes AC-1 checkable rather than impressionistic**, which is what the note asked for:
when the `display` opcodes land, the scroll should fill with white lettering at **rows 6–18,
columns 12–28**. ★★ Two cautions for whoever runs that gate: the per-row counts climb steadily
(176, 192, … 372), so the panel is **redrawn repeatedly** — the title screen cycles; and P6.13
found the room goes 83 → 1 across 200 cycles, so **a short capture can miss it entirely** and read
as a failure.

---

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-08-an-ablation-that-moves-both-arms-exonerates-nothing.md`
- `seeds/AGI/live/2026-09-08-a-high-level-object-carries-metadata-a-raw-buffer-does-not.md`

---

### 11 — Commit
See §11 note in the follow-up commit.
