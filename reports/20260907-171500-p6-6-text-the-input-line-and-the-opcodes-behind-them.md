## Form B Report — P6.6 — Text, the input line, and the opcodes behind them
**Class:** build.  wip.  ★★★★★ **PARTIAL — 4 of 12 ACs. The build is not done and is not claimed.**

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-07 ~16:30 local (HEAD `595bb40`, wip). `git status` clean at t0 apart from an
untracked `coco_agi.code-workspace` (Jay's editor config; left alone).

---

### 6 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `595bb40`, `wip`, clean |
| POP + Karateka | §2T citation below |
| `hal_sync_check.py` | **OK in all three** — §5 |
| the five gate rows | ★★ **NOT RE-RUN — see §7.1.** They were green at `a51764a` two commits ago and nothing in this task touches a probe, a sweep or a gate. **Stated as a citation, not as a fresh run.** |
| flag sets — enumerate and diff | produced and diffed; §5 |
| the clock — measure it | ★★ **NOT MEASURED this task** — no timing figure is published here. §7.1. |
| `docs/project/`'s design specs | ★★★ **v0.6, v1.1, v1.2 at t0** → **v1.1, v1.2** after AC-2 |
| `Alt` under MAME | ★★★★ **reachable — measured, §3.B** |

#### §2T — sibling baseline, by citation

★ P6.5 §0 records POP `wip` `104b197` and karateka `wip` `29f8f0a`. **Both unchanged at t0.**
Tracked modifications: POP **0**; karateka **1** (`harness/smoke/last-run.log`, a run log, the same
file P6.4 and P6.5 recorded). **This task touches no file in §2M's SHARED list** — its only source
change is a Lua probe and a one-line citation fix — so no sibling artifact can have moved. The
sync check is `OK` in all three (§5).

★★ **And a citation is what §2T asks for when the inputs are unchanged** — but see §7.1, where I
say plainly which §6 rows I cited rather than ran, and why that is weaker than P6.5's.

---

### 1 — Summary

★★★★★ **This report is 4 ACs of 12 and I am not claiming the rest.** What is done is the
question-answering the dispatch's §3 asked for — *"questions, not instructions"* — and it was worth
doing first, because **the answer to the hardest one refutes the dispatch's framing of AC-4.**

★★★★★ **AGI does not save-under for text.** The dispatch frames AC-4 as *"§3.6's save-under
machinery applied to a new client"*. The oracle keeps **two buffers**, draws every glyph into the
**display** one, and restores the room by **re-rendering the covered rectangle from the untouched
game screen**. No save-under buffer, no new state — and the port already owns the machinery.

★★★★ **AC-10 and AC-5 are settled by measurement rather than by reading.** The character set is a
TABLE and the whole v2 corpus ships no font; every key in AD-134's scheme was **pressed and read
back out of the PIA matrix**, and the chords cannot ghost.

★★★ **AC-2 closed the documentation hole**: v0.6 retired, the superset adjudicated line by line,
CLAUDE.md's stale citation corrected. **`v0.3` was never on any ref**, so the dispatch's instruction
to retire it had nothing to act on.

**Not done: AC-1, AC-4, AC-6, AC-7, AC-8, AC-9, AC-11, AC-12.** §7.1.

---

### 2 — Files modified

- `CLAUDE.md` — **one line**: the design-authority citation (§3.C). ★ 1 insertion, 1 deletion.
- `docs/project/agi-coco3-design-v0.6.md` — **retired** (`git rm`).
- `harness/tools/keymatrix_probe.lua` — **new**; AC-5's instrument (§3.B).

★ **No probe, sweep, gate, engine or VM file is touched by this task.**

---

### 3 — Reasoning

#### 3.A ★★★★★ AC-4's mechanism, and the dispatch's framing is refuted

The dispatch: *"text draws into the same planes as the picture and sprites, and a message window
must not destroy the room behind it. That is §3.6's save-under machinery applied to a new client."*

★★★★★ **The oracle does not do that.** It keeps two buffers and text only ever reaches one:

| | oracle | this port already has |
|---|---|---|
| game screen, 160×168, 1 byte/pixel | `_activeScreen` | **the visual plane** — byte-identical to the oracle, 53/53 |
| display, 320×200 | `_displayScreen` | **the GIME-scanned framebuffer** |
| where a glyph goes | ★★★★ **`_displayScreen` ONLY** | — |
| closing a window | ★★★★ **`render_Block` re-renders the rect FROM `_activeScreen`** | **`p3_present`, restricted to a rectangle** |

**The evidence, at the pin:**

- `graphics.cpp:1194` `drawCharacter` → `:1214` `drawCharacterOnDisplay`; `:1223` the string path
  → the same. ★★★ **Every glyph path ends there**, and its own comment reads *"Draw a string to the
  **display screen** using **display** coordinates."*
- `text.cpp closeWindow()`: *"Close the window by copying the **game screen** to the **display
  screen**"* → `_gfx->render_Block(x, y, backgroundSize_Width, backgroundSize_Height)`.
- `graphics.cpp render_BlockEGA`: reads `_activeScreen[offsetVisual++]` and writes
  `_displayScreen[offsetDisplay++]` **twice** — which is the horizontal doubling design §2.1
  describes, and the same doubling this port's `scr_dbl = (colour & 15) * 17` performs.

★★★★ **So there is no save-under for text and there does not need to be.** The room is not
overwritten in the buffer that holds it; only the presented copy is. ★★★ **Consequence for AC-4's
byte gate, and it should be stated rather than discovered:** *"the planes byte-identical to the
oracle after the window closes"* is satisfied **because text is never written to the compared
plane at all**. A gate that can only pass is not a gate [§2W] — **the real gate is that the
re-presented rectangle matches, which is a DISPLAY comparison, and this project has never made
one.** That is a finding for whoever builds it, not a detail.

★★ **§2H's three checks, applied here:**
1. **A second mechanism for a different object class?** ★★★★ **Yes, and it is the whole answer.**
   Sprites use save-under [§3.6]; **text uses a second buffer.** Reading §3.6 and generalising it
   is exactly the first-mechanism error, and the dispatch made it.
2. **Name the caller.** `closeWindow`'s caller is the message-window teardown, and what it carries
   is that the rectangle is in **game-screen coordinates** — `MAX(0, backgroundPos_y)` exists
   because MixedUpMotherGoose passes `y=0` to `print.at` and the border lands over the menu bar
   [ScummVM bugs #13820, #15241]. ★★ **A port that assumes windows are inside the game screen is
   wrong on a title in our own corpus.**
3. **Grep the reports before citing.** Done. No prior report characterises text rendering;
   §8A.4 of design v1.2 says only that it does not exist.

#### 3.B ★★★★ AC-5 — pressed and read, not listed

★★★★★ **The first version of this probe was an instrument that could not fail.** It matched MAME
field names by **substring**: `"left"` hit *"rat mouse button 2 (left port)"*, `"E"` hit *"ENTER"*,
`"C"` hit *"ad stick y 2"*. It then printed **"★ every key in AD-134's scheme exists"** — a verdict
that was *true* while three of its supporting rows were garbage, and a matcher that loose could as
easily have "found" a key that was absent. ★★★ **That is §2W.3 exactly, in the check that gates a
§9 trigger-2 stop**, and it is the seventh instance of the class.

★★★★ **The rewritten probe presses each key and reads PIA0's matrix** — strobe a column at `$FF02`,
read the row bits at `$FF00`, a pressed key pulls its bit LOW. That is a fact about the machine, not
about MAME's naming:

```
  UP     column 3, row bit 3        CTRL   column 4, row bit 6
  DOWN   column 4, row bit 3        ALT    column 3, row bit 6
  LEFT   column 5, row bit 3        ENTER  column 0, row bit 6
  RIGHT  column 6, row bit 3
  Q (1,2)   E (5,0)   Z (2,3)   C (3,0)
```

★★★ **Ghosting is structurally impossible for these chords.** Three keys ghost when two share a
column and two share a row; `CTRL`+letter is **two** keys, and here CTRL(4,6) shares neither column
nor row with Q(1,2), E(5,0), Z(2,3) or C(3,0). ★ The positions are printed so a reader checks that
rather than trusting it.

★★ **The host question, and the limit of my instrument.** I drove ioport fields directly, which
proves **the guest can see ALT** — not that a *physical* Alt press survives the front-end.
`mame -showusage` documents `-ui_active` — *"enable user interface on top of emulated keyboard (if
present)"* — i.e. on a natural-keyboard machine the **emulated keyboard has priority** and the UI
sits behind a toggle. ★ **Residual: the Windows OSD's own ALT+ENTER fullscreen binding.** Not a
chord in AD-134's scheme, but a user pressing Alt then Enter quickly could trip it. **Reported, not
worked around.**

#### 3.C AC-10 — a table, and three sources already agreed

★★★★ **For DOS/EGA/VGA — the entire v2 corpus — the game ships no font.** `GfxFont::init()`
[`font.cpp`]: for `kRenderEGA`/`kRenderVGA` it calls `loadFontScummVMFile("agi-font-dos.bin")` — a
**ScummVM** file, not a game file — and if that is absent falls back to
`Graphics::DosFont::fontData_PCBIOS`, *"regular PC-BIOS font"*. **The interpreter supplies the
character set; on real DOS AGI that is the IBM ROM character generator.**

★★ **The exceptions are all outside our corpus:** Apple IIgs loads `AGIFONT` (*"Special font, stored
in file AGIFONT"*) — the one platform where it IS shipped; `GID_MICKEY` loads it from the
interpreter binary; Amiga/Atari ST/Hercules use platform fonts.

★★★ **So text is a TABLE, and this project decided that before the question was asked:**
`memmap.inc` carries `MAP_FONT equ $E0B8 ; the authored 8x8 40-column font, 2,048 B (§2B)` —
256 glyphs × 8 bytes — and design **§2.1** already requires it: *"text at 320 native. Status line,
input line and message windows are 40 columns, which needs an 8-pixel font at 320."*

★ **§2.1 divergence, stated:** the glyphs are **ours** (§2B marks the font an authored, PROTECTED
asset). We are not reproducing IBM's ROM bitmaps. **That is legitimate because the glyph shapes are
presentation, not behaviour** — what must match is the 8×8 cell and the 40-column grid, which is
what AGI computes windows in.

#### 3.D AC-2 — the superset, adjudicated line by line

★★★ **§9 trigger 3 makes this a hard gate**, so the nine dropped lines are accounted for
individually rather than waved through:

| dropped | verdict |
|---|---|
| `# … design spec v0.6` | version supersession, by definition |
| the pixel-queue / scanline-fill advice (3 lines) | ★★ superseded by the **declared** §6.2 rewrite — *"the fill is 2.832 s (packed, windowed, shadow-blitted)"*; v1.0's changelog already said *"Restructured, not tuned"* |
| *"This routine sets room-change latency… Measure it first (§11.2)"* (2) | ★★ an instruction to measure, and §6.2 **is** the measurement |
| *"Save-under bounds cost by total sprite area…"* (2) | ★★ supported the compositing cost claim that v1.2 **explicitly WITHDRAWS** — *"v1.1's 53% / 106% are WITHDRAWN — overstated 3.78× by a harness defect"* |
| `### 11.1 REOPENED — the v2-only ruling rested on a false premise` | ★★★★ **content intact, heading restructured** — v1.2 carries it at **:95** (changelog bullet, verbatim premise), **:135** (*"§11 — one design decision remains open: does this project target AGI v3?"*) and **:605** (*"v3 is deferred (§11.1)"*) |

★★★★ **No hard stop.** ★★ The last row is the one worth noting: **a whole-line superset check
cannot see a restructure**, so it reported a loss where the content had moved. The check is right to
flag it and wrong to be believed without the follow-up.

★★★ **`v0.3` was never on any ref** — `git log --all --pretty=format: --name-only` shows
`agi-coco3-design-v0.6.md` as the only design-spec filename ever present. **The dispatch's
instruction to retire it had nothing to act on**, and CLAUDE.md pointed at a file the repository has
never held. Corrected to `docs/project/agi-coco3-design-v1.2.md`.

#### 3.E ★★★ The plane representation, re-read rather than assumed

The visual plane stores **one byte per logical pixel with the colour doubled into both nibbles** —
`scr_dbl = (colour & 15) * 17` [`pic_core.s:92,113`]. ★★ **So 320-native text must write the two
nibbles of a byte independently**, and text deliberately breaks the invariant the picture renderer
maintains. ★ Under §3.A that is confined to the display buffer, where the invariant does not apply —
**which is the second reason the two-buffer design is the right one here and not merely the
oracle's.**

---

### 4 — Verification (AC-by-AC)

- **AC-1 [eye-gated] — ★★★★★ NOT DONE.** Nothing reaches the screen this task. **Not "pending Jay":
  there is nothing to watch.** §4A is not satisfied and this task is therefore **not reportable as
  an integration task** [§4A.2] — which is why this report is labelled PARTIAL.
- **AC-2 [byte-comparable] — PASS.** v1.2 was committed at `a51764a` (P6.5) and is byte-identical
  (`sha256 a662cf9642466686`, 95,132 B, unchanged since). Superset adjudicated (§3.D). v0.6 retired.
  v0.3 never existed. CLAUDE.md corrected, **1 insertion / 1 deletion**.
- **AC-3 [byte-comparable] — PARTIAL.** `hal_sync_check` OK ×3 and `reg_discipline` unchanged, both
  fresh (§5). ★★ **The five gate rows were NOT re-run** — cited from `a51764a`, §7.1.
- **AC-4 [byte-comparable] — NOT DONE.** ★★★★★ **But its mechanism is settled and the dispatch's
  framing is refuted** (§3.A). No text renders.
- **AC-5 [byte-comparable] — PASS on the hardware half.** Every key defined, pressed and read back
  (§3.B, §5). ★★ **The input line does not exist**, so "the input line accepts Jay's scheme" is
  unproven above the matrix.
- **AC-6 [state-comparable] — NOT DONE.** `have.key` and `get.string` unimplemented.
- **AC-7 [byte-comparable] — NOT DONE.** No new gate, so nothing to fault-inject. ★ The one new
  instrument (`keymatrix_probe.lua`) **was** shown able to be wrong — it was wrong first (§3.B).
- **AC-8 [state-comparable] — NOT DONE.** BlackCauldron and MixedUpMotherGoose unmeasured.
- **AC-9 [state-comparable] — PARTIAL.** `MAP_FONT` at `$E0B8`, 2,048 B, **already reserved** and
  confirmed correct (§3.C). ★★ **`MAP_TABLES` runs $E000–$FF00 and its declared entries end at
  $E8B8, leaving 5,704 B** — which is where the text state would go. **Not decided, not recorded**,
  because nothing consumes it yet. `MAP_RESERVED` untouched at 3,328 B; **M-48's bytes not spent.**
- **AC-10 [state-comparable] — ANSWERED.** §3.C. **A table.**
- **AC-11 [state-comparable] — two things.** §7.2, §7.3.
- **AC-12 [suite] — `None.`** ★ §3.A and §3.B are candidate-shaped, but both are instances of rows
  that already exist (`a-first-mechanism-is-a-hypothesis-about-the-whole-mechanism` and
  `an-instrument-must-be-shown-able-to-fail`); per §2C I have not edited them, and the recurrences
  are recorded here.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — AC-5, the keyboard, pressed and read back (verbatim):**

```
=== AD-134's keys: does the driver define them, EXACTLY? ===
  UP     "UP"       [:row3]          CTRL   "CTRL"     [:row6]
  DOWN   "DOWN"     [:row3]          ALT    "ALT"      [:row6]
  LEFT   "LEFT"     [:row3]          ENTER  "ENTER"    [:row6]
  RIGHT  "RIGHT"    [:row3]
  Q      "q  Q"     [:row2]   E "e  E" [:row0]   Z "z  Z" [:row3]   C "c  C" [:row0]

=== pressed, and read back through PIA0 ($FF02 strobe, $FF00 rows) ===
  UP     column 3, row bit 3          CTRL   column 4, row bit 6
  DOWN   column 4, row bit 3          ALT    column 3, row bit 6
  LEFT   column 5, row bit 3          ENTER  column 0, row bit 6
  RIGHT  column 6, row bit 3
  Q      column 1, row bit 2          Z      column 2, row bit 3
  E      column 5, row bit 0          C      column 3, row bit 0

=== CTRL + letter chords: two keys each, so ghosting is structurally impossible ===
  CTRL(4,6) + Q(1,2)     CTRL(4,6) + E(5,0)
  CTRL(4,6) + Z(2,3)     CTRL(4,6) + C(3,0)

★ every key in AD-134's scheme is defined AND reaches the guest.
```

★ The two-column layout of the first and second blocks is mine; every name, column and row bit is
as the probe printed it.

**25.1 — AC-2, the superset, v0.6 → v1.2 (verbatim):**

```
in-repo  : docs\project\agi-coco3-design-v0.6.md
           57297 bytes, sha256 e7c14e1f1ed7c675
           752 substantive lines
provided : docs\project\agi-coco3-design-v1.2.md
           95132 bytes, sha256 a662cf9642466686
           1207 substantive lines
added    : 464 substantive lines not in the in-repo copy
DROPPED  : 9 substantive lines present in-repo and absent (or fewer) in the provided file
  -1  # AGI Interpreter for the Tandy Color Computer 3 — design spec v0.6
  -1  ★★ **A pixel queue is the wrong choice on a 6809.** A large fill queues thousands of 16-bit coordinates
  -1  and the queue becomes the memory problem. **Use scanline fill** — push spans, not pixels — which cuts
  -1  queue depth by roughly the run width.
  -1  **This routine sets room-change latency, and room changes are the one moment an AGI player waits. Measure
  -1  it first** (§11.2).
  -1  ★ **Save-under bounds cost by total sprite area, not screen area** [§3.6]. Typical AGI rooms have 2–6
  -1  active views.
  -1  ### 11.1 ★★★ REOPENED — the v2-only ruling rested on a false premise

SUPERSET CHECK: ★★★ FAIL -- STOP AND SURFACE THE DELTA (§2D)
```

★★ **The tool's FAIL is correct and is not the verdict** — §3.D adjudicates all nine. It cannot see
a restructure, which is what the last line is.

**25.1 — AC-2, v0.3 was never on any ref (verbatim):**

```
=== was agi-coco3-design-v0.3.md EVER committed, on any ref? ===
  NEVER -- no ref has ever contained it
=== every design-spec filename ever present on any ref ===
docs/project/agi-coco3-design-v0.6.md
```

**25.1 — AC-2, the CLAUDE.md correction is exactly one line (verbatim):**

```
  line 58: authority is `docs/project/agi-coco3-design-v1.2.md`.
$ git diff --numstat CLAUDE.md
1	1	CLAUDE.md
```

**25.1 — `hal_sync_check.py`, all three (verbatim):**

```
coco_agi        [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port       [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3  [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)
```

**25.1 — `reg_discipline.py` (verbatim):**

```
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s                       8  $FFA5 $FFA6
```

★ Unchanged. **No `src/engine/` file was touched by this task.**

**25.1 — flag sets, enumerated and diffed (verbatim, condensed to the verdict):**

```
── pic [correctness] ── pic_nc [timing] ── pic_nc_pk [timing] ── pic_win [timing] ──
── res [correctness] ── cel [correctness] ── comp [correctness] ── vm [correctness] ──
── p3b [timing] ──  ★★★ EXPECTED-ON BUT ABSENT: PIC_NOCOUNT
★★★ 1 expected-on guard(s) absent. Every timing figure from such a build is suspect.
```

★ **Unchanged from P6.5 and expected:** p3b publishes per-stage timings with counters on. The row
layout is mine; the verdict lines are the tool's.

**25.1 — the encoding audit:** `CLAUDE.md` and `keymatrix_probe.lua` both **clean**.

**25.2 — bundled-artifact grep:** N/A — no DECB artifact; this task ships no target binary at all.

**25.3 — operator-runtime-smoke:** ★★★★★ **N/A, and that is the finding rather than a formality.**
Nothing this task produced reaches a screen. **Per §4A.2 an integration task with no eye gate is
not reportable**, so this report is PARTIAL rather than complete.

---

### 6 — Reactive deviations and route accounting

**Deviations (§22.5):**

1. ★★★★★ **I stopped rather than half-building the text path.** The dispatch's scope is intact and
   unreduced; I did not scale it down. **What I did instead was answer §3's questions first**, which
   the dispatch asked for — and one answer (§3.A) changes what AC-4 costs.
2. ★★★ **I rewrote `keymatrix_probe.lua` after its first version passed on false matches** (§3.B).
3. ★ **I did not re-run the five gate rows** and cited them instead (§7.1). ★★ P6.5 ran them; this
   task changes no gated file. **Stated because a citation is weaker than a run and the reader
   should know which they have** [§2T.3].

**Route accounting.** ★★★ **I proposed a route mid-task and did not complete it.** After settling
§3.A I said the remainder should be *"considerably cheaper than the dispatch assumed"* — **I did not
build it, and that claim is an estimate, not a measurement.** It rests on the port already owning
`p3_present`; **nobody has written a rectangle-restricted present or measured one.**
★ **What I described and did not build:** the font table, a `text_draw` routine, a rectangle
`p3_present`, an input line, `have.key`, `get.string`, and their gates.

---

### 7 — Uncertainty flags

1. ★★★★★ **Eight ACs are not done and two more are partial.** AC-1, AC-4, AC-6, AC-7, AC-8 have no
   work at all; AC-3 cites the gate rows rather than running them; AC-9 confirms `MAP_FONT` and
   decides nothing further. **The task needs another pass.**
2. ★★★★ **AC-4's byte gate as the dispatch words it can only pass.** *"The planes byte-identical to
   the oracle after the window closes"* is true **because text is never written to those planes**
   (§3.A). ★★★ **The gate that would mean something is a DISPLAY comparison** — the re-presented
   rectangle against what was there before — **and this project has never made one.** Whoever builds
   AC-4 should read this before writing the gate, or it will be an instrument that cannot fail.
3. ★★★★ **A message window can sit OUTSIDE the game screen.** `closeWindow` clamps with
   `MAX(0, backgroundPos_y)` because **MixedUpMotherGoose passes `y=0` to `print.at`** and the border
   lands over the menu bar [ScummVM #13820, #15241]. **A port that assumes windows are contained is
   wrong on a title in our own corpus** — and MUMG is one of the two titles AC-8 was about.
4. ★★★ **The 320-native text write breaks the visual plane's doubled-nibble invariant** (§3.E).
   Confined to the display buffer under §3.A, **but nothing enforces that confinement yet.**
5. ★★ **ALT+ENTER may be claimed by the Windows OSD** (§3.B). Not a chord in AD-134, unverified
   under a real front-end.
6. ★★ **`-ui_active`'s behaviour was read from `-showusage`, not exercised.** I proved the guest can
   see ALT by driving the ioport field, which **bypasses host key handling entirely**.
7. **Carried, unchanged:** `pic`'s corpus; `CP_CEL`'s overrun; the patch series; the 100,000
   instruction budget; the surviving resource copy.

---

### 8 — Follow-up candidates

1. ★★★★★ **Build AC-4 on §3.A's mechanism** — text into the display buffer, a rectangle-restricted
   `p3_present` to close a window. ★★ **And gate it as a DISPLAY comparison** (§7.2).
2. ★★★★ **Handle the out-of-bounds window** before MUMG is gated (§7.3).
3. ★★★ **The input line, `have.key`, `get.string`** — unchanged from this dispatch's §4.
4. ★★ **AC-8's measurement** — BlackCauldron and MixedUpMotherGoose, longer window or room jump.
5. ★ **Re-run the five gate rows** on the next task that touches a gated file.

---

### 9 — User interaction during task

- Jay: **"report"** — this document.
- ★ Standing instruction, carried: **do not commit PNGs unless asked.** None produced.

---

### 10 — Candidate(s) captured this task

**`None.`**

★ §3.A is an instance of `a-first-mechanism-is-a-hypothesis-about-the-whole-mechanism` and §3.B of
`an-instrument-must-be-shown-able-to-fail`; both rows exist and per §2C I have not edited them.
★★ **The recurrence is the point rather than a new row:** §3.B is the **seventh** instance of the
instrument class and I authored it in the check that gates a stop-and-report, one task after
writing the rule about it.

### 11 — Commit

`240460f` — *P6.6 (partial) the character set, the control scheme, and the document hole*
(pushed to `origin/wip` before this report).
