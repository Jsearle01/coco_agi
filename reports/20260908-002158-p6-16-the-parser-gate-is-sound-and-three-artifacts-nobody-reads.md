## Form B Report — P6.16 — The parser gate is sound, and three artifacts nobody reads
**Class:** build.  wip.

★★★★★ **AC-6 is answered and the answer is that the gate stands.** `said_gate.py` reads
`oracle_parser_results.txt`, which is written by a **local** `Common::DumpFile` that closes
properly; the unread `oracle_said.txt` is a **different artifact** — a diagnostic trace, not the
gate's input. **Trigger 1 does not fire. The 23,328-case result is intact.**

★★★★ **AC-2 and AC-3 — the reference and its gate — are NOT built.** The geometry is verified by
hand against the oracle's own capture and `stringWordWrap` is the one piece left, named with its
edge cases.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-08 00:21:58 (HEAD `2bae6fa`, wip). `git status` clean apart from untracked
`coco_agi.code-workspace`, an editor file, not staged (§2E, explicit-path only).

---

### 4' — Pre-dispatch grep (C-13), verbatim, before the summary

```
=== coco_agi ===   2bae6fa P6.15 the text oracle exists                                     wip
=== POP ===        104b197 HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)
=== Karateka ===   29f8f0a HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)
=== hal_sync x3 ===  OK / OK / OK  (11 files compared)
=== reg_discipline ===  8 access(es), src/engine/mmu_phase.s, $FFA5 $FFA6
```
★ **§2T baseline cited, not rebuilt.** POP `104b197` / Karateka `29f8f0a` are P6.15 §0's refs.

★★★★★ **EVERY GATE RUN, BOTH ARMS:**
```
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ p3b headless: 160 cycles, no stall
★ gates run: pic res cel comp p3b  -- all green
##### VM PLAIN #####       9/9 PASS
##### VM PARSER ARM #####  9/9 PASS   (6 of 9 fed with input)
```

**Flag sets, enumerated and diffed** (L-77): one expected-on guard absent — p3b's `PIC_NOCOUNT`,
pre-existing, **eighth consecutive task**.

**The text opcodes at HEAD:** all **9** still `vm_op_modelled` (65, 66, 67, 68, 69, 6C, 6D, 70, 71).

**Every artifact the oracle patches produce, and what reads it** — AC-8, below.

---

### 1 — Summary

★★★★★ **The parser gate's oracle leg was never vacuous.** Patch 0009 writes **two** artifacts and
the gate reads the one that works:

| artifact | written by | closed? | consumed by |
|---|---|---|---|
| `oracle_parser_results.txt` | **local** `Common::DumpFile out`, with an explicit `out.close()` | **yes** | ★★★★ **`said_gate.py:279` — the gate** |
| `oracle_said.txt` | `static Common::DumpFile s_saidLog` | **never** | ★★★ **nothing** |

Eight workdirs hold `oracle_parser_results.txt` properly closed and sized (29–146 KB); the same
directories hold `oracle_said.txt.tmp` unclosed at 0.4–4.6 MB. **The gate compared against real,
consumed data. Trigger 1 does not fire.**

★★★★ **Three produced artifacts have no consumer** (AC-8), found by a tool written for the
question — and **the tool's own first two runs were wrong in both directions**, which is L-101
recursing on the instrument built to detect L-101.

★★★★★ **The text reference is not built, and the geometry is verified anyway.** Every number in
the oracle's first restore rectangle reproduces from the engine's constants by hand — so AC-2's
hard part is not the geometry, it is `stringWordWrap`.

---

### 2 — Files modified

- `harness/tools/artifact_consumers.py` — **new.** AC-8's producer/consumer survey.

**No `src/` change. No reference. No 6809 code.**

---

### 3 — Reasoning

#### 3.1 ★★★★★ AC-6, and why the two artifacts differ

The distinction is a C++ storage class, and it is visible in patch 0009 itself:

```
+			Common::DumpFile out;          <- local: destructor closes, DumpFile renames .tmp -> real
+			out.close();
+	static Common::DumpFile s_saidLog;     <- static: never destroyed, never closed, stays .tmp
```

★★★ `Common::DumpFile` writes `<name>.tmp` and renames on close. **A handle held for the process
lifetime is never closed, because the run dies on a wall-clock timeout** — so the data is complete
and correct under a name nothing looks for. That is exactly what happened to P6.15's own text log
before it was renamed, and it is why the mechanism was recognisable here.

★★ **`vmstate.txt` uses the same static pattern** (`s_vmLog`) and IS consumed — because
`oracle_dump.sh` has always listed the directory and something downstream reads it after the
runner's own handling. **So "static handle" is not by itself a defect**; the defect is a static
handle whose artifact nobody renamed or read.

#### 3.2 §2H's three checks, on AC-8's survey

1. **A SECOND mechanism?** ★★★★ Yes, and it broke my first result. Artifacts are named two ways in
   the patches: literal `open("x.txt")` and `String::format("pic%03d.%s.bin")`. **A survey matching
   only the first reports the renderer's 164 dumps as unconsumed.** Both shapes are matched now.
2. **Name the caller.** The consumer test is "a harness file mentions the name" — deliberately
   **over**-inclusive, because a false consumer hides an orphan and a false orphan is merely
   dispositioned. The two files that mention every name without reading any (this tool, and
   `oracle_dump.sh`'s rename loop) are excluded by name and the exclusion is written down.
3. **Grep the reports before citing.** P6.15 §7.2 recorded `oracle_said.txt` as unread; **this task
   established what that did and did not mean** rather than repeating it.

★★★★★ **The survey was wrong twice before it was right, and both errors are the survey's own
subject.** First run: `oracle_said.txt` reported as *read by* `artifact_consumers.py` and
`oracle_dump.sh` — its own docstring and a rename loop. **Mentioning a name is not reading a file,
which is L-101 exactly.** Second: `oracle_said_script.txt` reported as an unconsumed output when it
is an **input** the oracle reads via `Common::File` — the writer regex could not tell `DumpFile`
from `File`. Both fixed, with the reasoning in the source.

#### 3.3 ★★★★ The geometry, verified by hand against the capture

The engine's constants (`text.h:63-72`): `FONT_VISUAL_WIDTH 4`, `FONT_VISUAL_HEIGHT 8`,
`FONT_COLUMN_CHARACTERS 40`, `HEIGHT_MAX 20`. The formulas (`text.cpp:483-503`):

```
startingRow            = ((HEIGHT_MAX - textSize_Height - 1) / 2) + 1     [centred]
textPos.column         = (FONT_COLUMN_CHARACTERS - textSize_Width) / 2    [centred]
backgroundSize_Width   = textSize_Width  * FONT_VISUAL_WIDTH  + 10
backgroundSize_Height  = textSize_Height * FONT_VISUAL_HEIGHT + 10
backgroundPos_x        = textPos.column * FONT_VISUAL_WIDTH  - 5
backgroundPos_y        = startingRow    * FONT_VISUAL_HEIGHT - 5
```

Against the capture's first restore, `R 19 59 118 50`:

| from the log | implies | check |
|---|---|---|
| w = 118 | `textSize_Width` = 27 | — |
| h = 50 | `textSize_Height` = 5 | — |
| — | `column = (40−27)/2 = 6` | ★★★ **the first glyph is `G 10 6 …` — column 6** |
| — | `startingRow = ((20−5−1)/2)+1 = 8` | — |
| x = 19 | `6*4 − 5 = 19` | ★★ **exact** |
| y = 59 | `8*8 − 5 = 59` | ★★ **exact** |

★★★★ **Every number reproduces**, and `textPos.row = startingRow + _window_Row_Min` gives
`10 = 8 + 2`, consistent with the logged glyph row. **So AC-2's geometry is not a risk; the risk is
`stringWordWrap`**, which produces `textSize_Width/Height` and is 80+ lines with three edge cases
the source names by game (KQ1's space-filled intro, the Apple IIgs restart UI, Gold Rush's
`"  Lake Michigan!"` split at width 9).

#### 3.4 §2S — ref and scope

Siblings: §0's citation at POP `104b197` / Karateka `29f8f0a`, both `wip`. Oracle claims at the pin
`9d9b9e93108a276c551aeffa390169ccc5148e15`, scope `engines/agi` `text.cpp` / `text.h`, read this
task. Gate-artifact claims are from `build/parser/*` on this machine, listed in 25.1.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] — PASS, every gate RUN, both arms.** §4'. `hal_sync_check.py` OK ×3;
  `reg_discipline.py` 8. §2T cited.

- **AC-2 [state-comparable] — NOT DONE.** No display buffer, no glyph rendering; all nine text
  opcodes remain `vm_op_modelled` (confirmed at HEAD, §4'). §3.3 records what IS established.

- **AC-3 [byte-comparable] — NOT DONE.** Nothing to gate. ★★ Per-title counts are not reported
  because there is no comparison to count [L-10 applies to what a total would be hiding, and here
  there is no total].

- **AC-4 [byte-comparable] — NOT DONE**, and deliberately not claimed: **a fault needs a gate to
  fail**, and AC-3 does not exist. ★★★ Trigger 3's spirit — I will not inject a fault into an
  instrument with no comparison in it.

- **AC-5 [state-comparable] — NOT DONE.** No reference structures exist to annotate; §2V asks for
  the table *at the decision*, and no decisions were taken.

- **AC-6 [state-comparable] — ★★★★★ ANSWERED: THE GATE STANDS.** `said_gate.py:279` reads
  `oracle_parser_results.txt`; patch 0009 writes it through a **local** `Common::DumpFile out` with
  an explicit `out.close()`, so it renames and is consumable. **Eight workdirs hold it, closed and
  sized.** `oracle_said.txt` is a **separate** said-script trace from `static s_saidLog`, and it is
  the artifact nothing reads. **No leg was vacuous; trigger 1 does not fire; the 23,328-case result
  is unaffected.** — 25.1.

- **AC-7 [byte-comparable] — CLOSED, by P6.15's change.** `said_gate.py`'s flow is `--emit` → *run
  the oracle in the workdir* → `--check`, and that oracle run goes through `oracle_dump.sh`, which
  **already renames every held-open `.tmp`** as of P6.15. Any future parser run produces
  `oracle_said.txt` readable. ★★ **Nothing "should consume it"** — AC-6 establishes it is a
  diagnostic, not a gate input, so the correct outcome is that it exists and is readable, not that
  a consumer is invented for it.
  ★ The existing `build/parser/*/oracle_said.txt.tmp` files predate the fix and are gitignored
  build artifacts; they are left rather than renamed by hand.

- **AC-8 [state-comparable] — DONE, with a tool.** `harness/tools/artifact_consumers.py`:
  **13 artifacts produced, 3 with no consumer.**

  | orphan | disposition |
  |---|---|
  | `oracle_said.txt` | ★★★ patch 0009's said-script trace. **Genuine.** Diagnostic, not a gate input (AC-6); readable from now on (AC-7). |
  | `row24.txt` | ★★ patch 0003's `oracleRow24` probe — a one-off from a past AC-7 investigation. **Genuine, dormant.** |
  | `text_events.txt` | ★★★★ **mine, from P6.15, and its consumer is this task's AC-3** — which is not built. **Expected, and it is the one orphan with a named owner.** |

  ★★ Two names were reported as orphans by earlier versions of the tool and are **not**:
  `pic%03d.%s.bin` (a stem-matching bug in my tool) and `oracle_said_script.txt` (an oracle
  **input**, opened via `Common::File`). §3.2.

- **AC-9 [byte-comparable] — PASS.** Nine titles, both arms, empty exclusion set — §4'.

- **AC-10 [state-comparable] — UNCHANGED from P6.15.** `get.string` needs the display buffer, a
  line buffer, **and the blocking input loop `messageBox` uses when `VM_FLAG_OUTPUT_MODE` is clear**
  (`text.cpp:370-386`). ★★ The display buffer still does not exist, so the requirement is restated,
  not advanced.

- **AC-11 [state-comparable] — §7.**
- **AC-12 [suite] — §10.**

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 (verbatim).** Gates and both arms — §4'.

AC-6, the two artifacts side by side:
```
build\parser\full_Kingquest1\oracle_parser_results.txt      36475     <- CLOSED, read by said_gate
build\parser\full_Kingquest3\oracle_parser_results.txt     146491
build\parser\full_larry1\oracle_parser_results.txt         109310
build\parser\full_PoliceQuest1\oracle_parser_results.txt   138408
build\parser\full_SpaceQuest-1\oracle_parser_results.txt    46610
build\parser\gate_kq1\oracle_parser_results.txt             29713
build\parser\full_Kingquest1\oracle_said.txt.tmp          1467342     <- NEVER CLOSED, read by nothing
build\parser\full_PoliceQuest1\oracle_said.txt.tmp        4590542
patch 0009:  + Common::DumpFile out;   + out.close();   |   + static Common::DumpFile s_saidLog;
said_gate.py:279:  p = pathlib.Path(workdir) / "oracle_parser_results.txt"
```

AC-8, the survey:
```
13 produced, 3 with no consumer
  oracle_parser_results.txt    read by: harness/tools/said_gate.py
  oracle_parser_cases.txt      read by: harness/tools/parser_gate.lua, harness/tools/said_gate.py
  vmstate.txt                  read by: harness/tools/run_agivm.py, harness/tools/vmdiff.py
  pic%03d.%s.bin               read by: harness/tools/agi_palette.py, ... (164 dumps)
  cels.bin / cels.txt / frame%03d.* / oracle_%s_%03d.bin / oracle_words.bin   read
  oracle_said.txt              ★★★ NO CONSUMER
  row24.txt                    ★★★ NO CONSUMER
  text_events.txt              ★★★ NO CONSUMER
```

AC-2's geometry, verified by hand — §3.3's table.

**25.2 bundled-artifact grep:** N/A — no bundled artifact; nothing shipped, no DECB image.

**25.3 operator-runtime-smoke:** `N/A — no visual surface this task.`

---

### 6 — Reactive deviations and route accounting

1. ★★★★★ **AC-6 was done first, not in AC order**, because trigger 1 hangs on it and a vacuous gate
   leg would have changed what the rest of the task meant.
2. ★★★★ **The reference was not started.** `stringWordWrap` must be transcribed statement-for-
   statement — it has three edge cases the source names by game — and transcribing it without room
   to gate it would produce exactly the half-built artifact the last four tasks avoided. **Reported
   rather than begun.**
3. ★★ **`artifact_consumers.py` is new tooling the dispatch did not ask for by name**, but AC-8 asks
   for "a list" and a hand-made list of 13 producers is the kind of thing that is right once.

**Route accounting.** ★★★★ **What I got wrong and corrected inside the task: my own AC-8 tool
reported two false orphans and one false consumer**, and every one of those errors is the failure
mode the tool exists to detect. **None reached a claim** — the report contains the third run.

---

### 7 — Uncertainty flags  (and AC-11: what the dispatch did not anticipate)

1. ★★★★★ **The parser gate is sound, which the dispatch treated as the open question.** §3 asked
   "if the answer is that a leg was vacuous" — it was not, and the reason is a C++ storage class:
   **local `DumpFile` closes, static `DumpFile` does not.**
2. ★★★★ **`vmstate.txt` uses the same static-handle pattern and IS consumed**, so "held-open
   handle" is not by itself the defect (§3.1). The defect is a held-open handle nobody renamed.
3. ★★★★ **My AC-8 tool committed L-101 twice** before reporting correctly (§3.2, §6).
4. ★★★ **`text_events.txt` is an orphan whose owner is this task**, and this task did not build the
   owner. It will stay an orphan until AC-3 exists — stated so it is not later found and treated as
   a discovery.
5. ★★★ **AC-2's geometry is verified but `stringWordWrap` is not started**; the wrap decides
   `textSize_Width/Height` and therefore every rectangle.
6. ★★ **The capture remains Kingquest1 only** [L-85].
7. ★★ **p3b's `PIC_NOCOUNT` absence is now eight tasks old.**

---

### 8 — Follow-up candidates

1. ★★★★★ **Transcribe `stringWordWrap` and build the reference**, then gate on `text_events.txt`.
   The geometry is verified (§3.3); the wrap is the work, and its three edge cases are named in the
   engine's own comments.
2. ★★★★ **Widen the text capture past Kingquest1** once the gate exists.
3. ★★★ **`row24.txt`** — a dormant probe; delete it or give it a consumer.
4. ★★★ **p3b's missing `PIC_NOCOUNT`** — eighth task naming it.
5. ★★ **Run `artifact_consumers.py` when a patch is added.** It is cheap and it would have found
   `oracle_said.txt` the day patch 0009 landed.

---

### 9 — User interaction during task

1. Jay: **"check progress"** — answered mid-task with AC-6's result and the explicit note that the
   reference was not built.

---

### 10 — Candidate(s) captured this task

`None.` ★★ The row this task earns — **a tool written to find unread artifacts reported its own
docstring as a reader** — belongs with the four unfiled from P6.12–P6.15 as one candidate about
instruments that fail silently, not as a fifth thin row.

---

### 11 — Commit

See the commit carrying this report; pushed to `origin/wip` before reporting.
