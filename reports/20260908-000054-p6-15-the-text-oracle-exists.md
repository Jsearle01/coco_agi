## Form B Report — P6.15 — The text oracle exists
**Class:** build.  wip.

★★★★★ **The blocker that stopped two dispatches is gone: there is now an oracle for text.** 36,181
recorded decisions — 35,584 glyph draws and 596 window restores — across 90 logics of Kingquest1,
captured from the pinned ScummVM, verified inert when off, and reproducible from pin + patch.

★★★★ **The Python reference (AC-2) is NOT built.** The oracle side consumed the task; AC-2 and the
gate that compares to it are next, and they now have a precise target to hit.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-08 00:00:54 (HEAD `84a747d`, wip). `git status` clean apart from untracked
`coco_agi.code-workspace`, an editor file, not staged (§2E, explicit-path only).

---

### 4' — Pre-dispatch grep (C-13), verbatim, before the summary

```
=== coco_agi ===   84a747d P6.14 the text work has no oracle, and a clock regression ...   wip
=== POP ===        104b197 HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)
=== Karateka ===   29f8f0a HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)

=== hal_sync x3 ===  OK / OK / OK  (11 files compared, EOL/guard/export-placement normalised)
=== reg_discipline ===  8 access(es), src/engine/mmu_phase.s, $FFA5 $FFA6
```
★ **§2T baseline cited, not rebuilt.** POP `104b197` / Karateka `29f8f0a` are P6.14 §0's refs.

★★★★★ **EVERY GATE RUN, BOTH VM ARMS INCLUDED** (the arm that hid the clock regression):
```
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ p3b headless: 160 cycles, no stall
★ gates run: pic res cel comp p3b  -- all green
##### VM PLAIN #####        9/9 PASS
##### VM PARSER ARM #####   9/9 PASS  (6 of 9 fed with input)
```

**Flag sets, enumerated and diffed** (L-77): one expected-on guard absent — p3b's `PIC_NOCOUNT`,
pre-existing, **seventh consecutive task**.

**The eight no-op opcodes, confirmed at HEAD** — all nine of them, in fact:
```
65 print(s)  66 print.v(v)  67 display(nns)  68 display.v(vvv)  69 clear.lines(nns)
6C set.cursor.char(s)  6D set.text.attribute(nn)  70 status.line.on()  71 status.line.off()
                                                              -- every one vm_op_modelled
```

**What ScummVM emits for text, and whether it can be dumped** — §1 and §3.

---

### 1 — Summary

★★★★★ **Patch 0010 adds a TEXT DECISION LOG and a bounded text sweep, and the oracle now emits
something a text reference can be gated against.** Captured for Kingquest1: **35,584 glyph draws,
596 restore rectangles, 90 logics.**

★★★★★ **It logs CALLS, NOT PIXELS, and that follows the existing instrumentation's own reasoning.**
Patch 0001's `oracleDumpScreens` records why the display path is not dumped — *"it is a rendering
of these buffers, and diffing against a rendering would put ScummVM's upscaler inside our
baseline."* For pictures that is the whole argument; for text the display screen is where glyphs
primarily live, **but the concern transfers unchanged** — a 320×200 dump would carry the upscaler,
the font file and `translateFontPosToDisplayScreen` into the comparison. What a text renderer must
get right is **which glyph, where, in what colours**, and that is what the log holds.

★★★★★ **No game text is in the artifact.** §2P bites hardest in a task about rendering text, and it
improved the instrument: the character code is **not** logged. Position, foreground, background and
an **order-sensitive rolling checksum** are. The reference is handed the same resources, so the
checksum proves both sides laid out the same string while the file stays free of the script.

★★★★ **Verified inert when off** — patch 0006's lesson, not assumed: with the dump disabled, the
new binary's picture dumps are **164/164 byte-identical** to the existing baseline.

★★★★ **A pre-existing artifact was recovered.** `Common::DumpFile` writes `<name>.tmp` and renames
on close; a log held open for the process lifetime is never closed, because the run dies on a
wall-clock timeout. **`oracle_said.txt` — patch 0009's parser dump — has been sitting unread as
`.tmp` ever since it was written, and nothing in the harness reads it.**

---

### 2 — Files modified

- `oracle/patches/0010-oracle-text-decision-log.patch` — **new.** The instrumentation.
- `harness/tools/oracle_build.sh` — **new.** The rebuild recipe, runnable.
- `harness/tools/oracle_dump.sh` — `TEXT_DUMP=1`; renames the held-open `.tmp` logs.

**No `src/` change. No Python reference. No 6809 code** — §2V's order, which is the point of the task.

---

### 3 — Reasoning

#### 3.1 ★★★★★ Why a call log and not a pixel dump (AC-3, trigger 1)

Trigger 1 asks what happens if ScummVM's text output cannot be captured comparably. **It can be
captured — but not as pixels without cost.** Three things sit between `drawCharacter` and the
display buffer, and all three would enter a pixel comparison: `translateFontPosToDisplayScreen`,
the font (`agi-font-dos.bin` or a built-in PC-BIOS fallback, `font.cpp:70-116`), and the upscaler
the existing note names.

★★★ **So "gated" here means: the DECISIONS are gated exactly, and the rendering is not gated yet.**
That is a real answer to AC-3 and a real limit, stated rather than papered over. A pixel gate is
possible later and needs the font choice settled first — which is AC-9's question and is now
answerable from evidence rather than preference.

#### 3.2 §2H's three checks, on the glyph path

1. **A SECOND mechanism?** ★★★★ **No, and that is a finding worth having.** `drawCharacter` has
   **exactly one caller** — `text.cpp:333`, inside `TextMgr::displayCharacter`. Every glyph in the
   engine goes through one funnel, so one hook is complete by construction [L-98]. **The port
   inherits that: a 6809 text renderer needs one glyph routine, not a family.**
2. **Name the caller.** `closeWindow()` (`text.cpp:549`) is the restore's caller, and it settles the
   model at the source: *"Close the window by copying the game screen to the display screen"* →
   `render_Block(x, y, backgroundSize_Width, backgroundSize_Height)`. **No save-under buffer
   exists**, confirming P6.6's reading in the engine's own words.
3. **Grep the reports before citing.** P6.14 §3.4 specified this model from the pin; this task
   **instrumented** it rather than re-deriving it, and the capture confirms the spec.

★★ **One detail the spec did not have and the source gave up**: `closeWindow` logs the **clamped**
y, not `backgroundPos_y`. A reference reproducing the raw value would diverge on exactly the
MixedUpMotherGoose nursery-rhyme case the engine comments on (`print.at` with y=0 putting the
border over the menu bar, negative background y). **Logging what the engine ACTS on, not what it
stores, is the difference between a gate and a near-miss.**

#### 3.3 ★★★★★ The probe, and the four rebuilds it saved from a false finding

The log came out **empty** and stayed empty through three rebuilds. An empty log has two causes —
the game drew no text, or the writer never worked — **and they are indistinguishable from the
absence of a file** [L-97: only an address separates two states that produce the same output].

★★★★ **So a probe line was added from a path that always runs.** It also did not appear, which said
*writer*, not *corpus* — and that was **wrong too**, but productively: it ruled out the corpus
explanation and sent me to the writer, where the actual cause was that `Common::DumpFile` renames
on close and the handle is never closed. **The file existed the whole time, at 673,270 bytes, under
a name nothing looked for.**

★★★ **Two real findings came out of that hunt** and neither would have been found by a working
first attempt: the dump run is a **picture sweep followed by the game sitting in its credits**, so
text needs its own sweep; and **`oracle_said.txt` has the same unclosed-handle condition** and has
never been readable.

#### 3.4 §2V — the structures, and why AC-5's table is not in this report

★★★★ **AC-5 asks for the 6809 form of every structure the text reference commits to, in the source
at the decision. The reference was not written, so there are no decisions to annotate yet** — and
writing the table against structures that do not exist would be the inverse of what §2V asks.
★★★ What the capture DOES establish for the port is recorded in §3.2: one glyph funnel, and a
restore that is a clipped re-render with no save-under buffer.

#### 3.5 §2S — ref and scope

Sibling claims: §0's citation at POP `104b197` / Karateka `29f8f0a`, both `wip`. Oracle claims at
the pin `9d9b9e93108a276c551aeffa390169ccc5148e15` (v2.9.1), scope `engines/agi`, files
`agi.cpp` / `graphics.cpp` / `graphics.h` / `text.cpp` / `font.cpp`, read and instrumented this task.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] — PASS, every gate RUN, both arms.** §4' above. `hal_sync_check.py` OK
  ×3; `reg_discipline.py` 8, unchanged. §2T cited.

- **AC-2 [state-comparable] — NOT DONE.** The reference has no display buffer and no glyph
  rendering, and the eight opcodes remain `vm_op_modelled`. **The oracle side took the task.**

- **AC-3 [byte-comparable] — THE ORACLE EXISTS; THE COMPARISON DOES NOT YET.** What ScummVM emits
  is now captured: 35,584 glyph decisions and 596 restore rectangles. **What "gated" can mean here**
  is §3.1: the decisions gate exactly, the rendering does not gate until the font and upscaler are
  settled. ★★ **There is nothing to compare it against yet** because AC-2 is not built — so this is
  an oracle, not a gate, and calling it a gate would be the self-referential trap §2O.1 names.

- **AC-4 [byte-comparable] — NOT DONE**, and honestly so: **a fault needs a gate to fail**, and
  there is no gate until AC-2 exists. ★★★ **Trigger 3's spirit applies to me here** — I will not
  claim a fault against an instrument that has no comparison in it.
  ★★★ What WAS shown able to fail is the **instrument**: the probe line distinguished writer from
  corpus, and the inertness check (164/164) shows the capture does not perturb the oracle.

- **AC-5 [state-comparable] — NOT DONE.** §3.4: no reference structures exist to annotate.

- **AC-6 [state-comparable] — ONE CASE NAMED, AND IT CAME FROM THE SOURCE, NOT A PREDICTION.**
  `closeWindow` clamps y to ≥ 0 before `render_Block`; a reference using `backgroundPos_y` raw would
  diverge on `print.at` with y=0. ★★★ **The corpus that reaches it is named — MixedUpMotherGoose's
  nursery rhymes, per the engine's own comment and bugs #13820 / #15241 — and it is NOT RUN**,
  because there is no reference to run it against. **L-100 says a written prediction is not a test,
  and this is a written prediction. It is recorded as owed, not as satisfied.**

- **AC-7 [state-comparable] — PARTIAL.** `get.string(nsnnn)` prompts at a row/column and blocks.
  From this task's reading: it needs the display buffer (for the prompt), a line buffer, **and the
  blocking input loop that `messageBox` uses when `VM_FLAG_OUTPUT_MODE` is clear** (`text.cpp:370-386`)
  — the same loop that made a naive sweep impossible and forced `drawMessageBox` instead. ★★ That
  third requirement is the one a line buffer does not cover.

- **AC-8 [byte-comparable] — PASS.** Nine titles, both arms, empty exclusion set — §4'.

- **AC-9 [state-comparable] — see §7.**
- **AC-10 [suite] — §10.**

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 (verbatim).** Gates and both arms — §4'.

The capture:
```
WARNING: oracle: rendered 82 pictures
WARNING: oracle: swept 596 messages across 90 logics
renamed  : oracle_said.txt   (Common::DumpFile leaves .tmp when the handle is never closed)
renamed  : text_events.txt   (Common::DumpFile leaves .tmp when the handle is never closed)
text_events.txt : 36181 events (673270 B)   G=35584  R=596  S=1
sha256 : 2866E6792A3DC4B0951E9E99D11B09D3
```
The artifact's shape — **no game text, §2P** (G: row col fg bg checksum; R: x y w h):
```
S 0 0 0 0 0
G 10 6 15 8 89        R 19 59 118 50 0
G 10 7 15 8 2870      R 19 67 118 26 0
G 10 8 15 8 23551     R 27 67 106 26 0
distinct restore sizes: 118x26 (66), 126x26 (59), 126x34 (50), 122x26 (47), 122x34 (41)
```
Inertness, the check patch 0006 taught this project not to skip:
```
baseline files: 164     identical: 164   differing: 0   missing: 0
```
The build, now recorded runnably:
```
g++.exe (x86_64-posix-seh-rev1, MinGW-Builds) 14.2.0    [C:\Projects\2600em\tools\mingw64\bin]
mingw32-make -j8   ->  scummvm.exe  75,210,531 bytes
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; nothing shipped, no DECB image.

**25.3 operator-runtime-smoke:** `N/A — no visual surface this task.`

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **The task's own order was inverted by necessity.** AC-2 (the reference) is listed first,
   but it cannot be gated without an oracle, and building it first is what §2O.1 warns against.
   **The oracle was built first and it consumed the task.**
2. ★★★ **The rebuild recipe was corrected.** `scummvm.pin`'s `build = make -j2` is the WSL recipe;
   the native toolchain ships `mingw32-make` and the pin's own `[build-native]` note says so. **Two
   recipes in one file and the one at the top fails** — now runnable in `oracle_build.sh`.
3. ★★ **`oracle_dump.sh` renames all `.tmp` logs**, which fixes a pre-existing artifact as a side
   effect. Attributed here rather than left as an unexplained improvement [L-54].

**Route accounting.** ★★★★ **What I described mid-task and had to withdraw twice:** I concluded
"`initVideo` is never called" from a missing warning — **the probe line `S 0 0 0 0 0` in the final
capture proves it runs.** And before that I was one step from reporting "the oracle draws no text"
as a finding, which the probe existed to prevent. **Both were caught by the instrument I added for
exactly that purpose, and neither reached a report before this one.**

---

### 7 — Uncertainty flags  (and AC-9: what the dispatch did not anticipate)

1. ★★★★★ **The oracle dump run is a PICTURE SWEEP, not gameplay.** Nobody had needed to know that;
   it is why text was absent and why every subsystem's oracle has needed its own sweep.
2. ★★★★★ **`oracle_said.txt` has never been readable** — patch 0009's artifact sat as `.tmp`, and
   nothing in the harness reads it. **§7 trigger 4: a pre-existing condition, since patch 0009.**
   Whatever the said gate was reading, it was not that file.
3. ★★★★ **Patch 0010 is CUMULATIVE for its four files, not incremental**, and its header says so.
   The series is kept as uncommitted changes stacked on the pin, so `git diff` cannot separate one
   patch from another. **Applying 0001–0009 then 0010 would conflict.** Splitting it needs the
   series committed — a change to how the whole series is kept, recorded rather than done in
   passing.
4. ★★★★ **AC-6's named divergence is NOT run** (L-100). It is owed.
5. ★★★ **The glyph source (AC-9 of the previous dispatch) is now answerable but not answered**:
   ScummVM loads `agi-font-dos.bin` and falls back to a built-in PC-BIOS font (`font.cpp:104-116`).
   **Which one this build actually used is not established**, and it decides what a pixel-level gate
   would compare against.
6. ★★★ **The capture is Kingquest1 only**, 8 messages per logic. L-85: that is the corpus and it is
   part of any claim made from it.
7. ★★ **p3b's `PIC_NOCOUNT` absence is now seven tasks old.**

---

### 8 — Follow-up candidates

1. ★★★★★ **Build the reference against this oracle** — the display buffer, glyph rendering and the
   nine no-op opcodes, gated on `text_events.txt`. **The target is now exact: 596 rectangles and
   35,584 glyph positions.**
2. ★★★★ **Run AC-6's named case** — MixedUpMotherGoose, `print.at` y=0, the clamped-y divergence.
3. ★★★★ **Commit the oracle patch series** so patches can be separated (§7.3), and check what the
   said gate has actually been reading (§7.2).
4. ★★★ **Settle the font** before any pixel-level text gate (§7.5).
5. ★★★ **p3b's missing `PIC_NOCOUNT`** — seventh task naming it.

---

### 9 — User interaction during task

1. Jay: **"check progress"** — answered mid-task with the oracle's status and the explicit note that
   the Python reference was not built.

---

### 10 — Candidate(s) captured this task

`None.` ★★ The candidate this task earns — **an artifact under a name nothing looks for reads
exactly like an artifact that was never produced** — is the same shape as the three still unfiled
from P6.12–P6.14, and they belong together as one row about instruments that fail silently rather
than as four thin ones.

---

### 11 — Commit

See the commit carrying this report; pushed to `origin/wip` before reporting.
