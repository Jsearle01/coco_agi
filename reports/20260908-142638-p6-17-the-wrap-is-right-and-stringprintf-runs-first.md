## Form B Report — P6.17 — The wrap is right, and `stringPrintf` runs first
**Class:** build.  wip.

★★★★★ **`stringWordWrap` is transcribed and it is correct: 585 restore rectangles identical,
31,763 glyph positions identical, 30,183 checksums identical.** The text gate exists and runs.

★★★★★ **It reports FAIL, and the reason is a step I missed rather than a wrap defect:
`drawMessageBox` calls `stringPrintf` BEFORE `stringWordWrap` (text.cpp:463), expanding AGI's
`%v`/`%m`/`%o`/`%s`/`%w`/`%g` codes against live VM state. 11 of 596 messages carry one.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-08 14:26:38 (HEAD `cf7ca1e`, wip). `git status` clean apart from untracked
`coco_agi.code-workspace`, an editor file, not staged (§2E, explicit-path only).

---

### 4' — Pre-dispatch grep (C-13), verbatim, before the summary

```
=== coco_agi ===   cf7ca1e P6.16 the parser gate is sound, and three artifacts nobody reads   wip
=== POP ===        104b197 HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)
=== Karateka ===   29f8f0a HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)
=== hal_sync x3 ===  OK / OK / OK  (11 files compared)
=== reg_discipline ===  8 access(es), src/engine/mmu_phase.s, $FFA5 $FFA6
```
★ **§2T baseline cited, not rebuilt.** POP `104b197` / Karateka `29f8f0a` are P6.16 §0's refs.

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
**Flag sets** (L-77): one expected-on guard absent — p3b's `PIC_NOCOUNT`, **ninth consecutive task**.

**`stringWordWrap`'s source read before designing to it** [L-25, L-53] — text.cpp:1095-1201, whole,
plus `displayCharacter` (307-342), `drawMessageBox` (445-519), `closeWindow` (549-564) and
`charAttrib_Set`'s EGA branch (198-206). §3.1.

**The three unread artifacts** — dispositioned in P6.16 AC-8 and unchanged: `oracle_said.txt`
(diagnostic), `row24.txt` (dormant probe), `text_events.txt` (**now consumed by this task's gate**).

---

### 1 — Summary

★★★★★ **The wrap is right.** Against patch 0010's log, over the 585 messages the reference can
currently reproduce:

| | reference | oracle | |
|---|---|---|---|
| restore rectangles | 585 | 585 | ★★★★ **all identical** |
| glyph draws | 31,763 | 31,763 | ★★★★ **count identical** |
| glyph row / column / fg / bg | — | — | ★★★★★ **every one identical** |
| rolling checksum | — | — | ★★★ **30,183 identical, then this mode's own boundary** |

★★★★★ **The gate FAILS on the full 596 and the failure is exactly located.** `drawMessageBox` runs
`processedTextPtr = stringPrintf(textPtr)` **before** the wrap (text.cpp:463). The reference wraps
the raw message, so for any message carrying a format code it is wrapping different text than the
oracle did. **11 of 596 messages carry a `%`**, the first at index 555 — and the first rectangle
divergence on the full run is rectangle **555**.

★★★★ **The dispatch's own diagnostic split needed correcting.** §2 said *rectangles match + checksum
diverges = wrapping; rectangles diverge = geometry.* **The rectangle is DERIVED from the wrap** —
`backgroundSize_Width = textSize_Width * 4 + 10` — so a rectangle can diverge for a wrapping
reason, and the full run's rectangle 555 does exactly that. The gate classifies by **which field
moved** instead.

★★★★ **AC-5's fault fires**: with the wrap test changed from `>=` to `>`, rectangle 0 diverges
immediately and the glyph count moves by 37.

---

### 2 — Files modified

- `tools/agivm/text.py` — **new.** `stringWordWrap`, the message-box geometry, glyph emission, the
  EGA attribute rule, and §2V's structure table.
- `harness/tools/text_gate.py` — **new.** The gate, with rectangles and checksum separated and
  `--fault-wrap` / `--skip-format` arms.

**No `src/` change. No 6809 code.**

---

### 3 — Reasoning

#### 3.1 ★★★★★ What `stringWordWrap` does, and the four things that are easy to get wrong

Read whole from the oracle (text.cpp:1095-1201), not from the Specs [L-25] — and the engine names
three test cases in its own comments that the Specs do not mention: King's Quest 1's intro (padded
with spaces so old lines erase), the Apple IIgs restart UI (spaces used to widen the window), and
Gold Rush room 60's `"  Lake Michigan!"` at max length 9. **Those exist because the obvious
implementation gets them wrong.** The four load-bearing details, all transcribed:

1. ★★★★ **`word_len` INCLUDES a leading space.** `word_start` points at the space and `cur_read`
   has passed both space and word, so the span carries it.
2. ★★★★ **The wrap test is `>=`, not `>`.** A word that exactly fills the remaining width wraps.
   **This is AC-5's fault, because it is the most plausible transcription slip.**
3. ★★★ **The leading space is dropped only on the wrapping branch** — mid-line it is kept and
   counted, which is how the space-padded lines keep their width.
4. ★★★ **`box_height >= HEIGHT_MAX` breaks the LOOP**, so text past 20 lines is discarded rather
   than clipped at draw time.

★★ **Divergence from the AGI Specs: none identified**, because the Specs do not specify wrapping to
this depth. That absence is the finding L-25 anticipates — there was nothing to differ from.

#### 3.2 §2H's three checks

1. **A SECOND mechanism?** ★★★★★ **Yes, and it is the whole result: `stringPrintf` runs before the
   wrap.** I transcribed `stringWordWrap` faithfully and gated against a log produced by
   `stringPrintf` → `stringWordWrap`. **The first mechanism was real and was not the whole path.**
   ★★★ It was found by the gate rather than by reading, which is the cheap direction.
2. **Name the caller.** `drawMessageBox` (text.cpp:445) is the caller and does four things in
   order: `stringPrintf`, `stringWordWrap`, the geometry, `displayText`. **The reference now
   implements three of the four.**
3. **Grep the reports before citing.** P6.16 §3.3 verified the geometry by hand; this task's 585
   identical rectangles **confirm that by measurement**, and the verification did not have to be
   redone.

#### 3.3 ★★★★★ The checksum chain, verified rather than assumed

With `--skip-format` the gate reports the checksum diverging at draw 30,183 while every position
matches. **That is this mode's own boundary, not a defect**: patch 0010's checksum is *cumulative*
over every character the oracle drew, including the messages the mode excludes, so from the first
excluded message the two running values cannot agree however correct the wrap is.

★★★★ **Verified, not asserted**: the first checksum divergence lands inside kept-message **555**,
and the first format-bearing message index **is 555**. The two numbers were computed independently
and they coincide. ★★★ **So 30,183 draws are checksum-verified and the rest of that column is
uninterpretable in this mode** — the gate now prints that rather than leaving the number to be
misread.

#### 3.4 §2S — ref and scope

Siblings: §0's citation at POP `104b197` / Karateka `29f8f0a`. Oracle claims at the pin
`9d9b9e93108a276c551aeffa390169ccc5148e15`, scope `engines/agi` `text.cpp` / `text.h`. Gate results
are Kingquest1 only, 596 messages across 90 logics [L-85].

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] — PASS, every gate RUN, both arms.** §4'. `hal_sync_check.py` OK ×3;
  `reg_discipline.py` 8. §2T cited.

- **AC-2 [state-comparable] — DONE.** `string_word_wrap` in `tools/agivm/text.py`, transcribed from
  text.cpp:1095-1201 with its four load-bearing details stated (§3.1). **Behaviour stated; no
  divergence from the Specs identified because the Specs do not reach this depth** — recorded as
  the finding rather than as a match.

- **AC-3 [state-comparable] — PARTIAL, and the missing half is named.** The reference has the
  message-box path: geometry, glyph emission, the EGA attribute rule, the restore rectangle.
  ★★★ **It models POSITIONS, not pixels**, deliberately — the oracle's log is a call log for patch
  0001's stated reason, so a pixel buffer would model something the gate cannot see [§2O.1].
  ★★★★ **The eight opcodes are NOT implemented.** `print`, `display`, `clear.lines` and the rest
  remain `vm_op_modelled` in both legs; this task built the renderer they would call, not the
  wiring. **Stated plainly rather than counted as done.**

- **AC-4 [byte-comparable] — GATED, AND IT FAILS, WITH THE CAUSE LOCATED.** Per title (Kingquest1;
  the only title captured):

  | run | rectangles | glyphs | result |
  |---|---|---|---|
  | full 596 | first divergence at **555** — width 23 vs 16 | 32,041 vs 31,973 (+68) | **FAIL** |
  | 585, format-bearing excluded | ★★★★ **585 / 585 identical** | ★★★★ **31,763 / 31,763, every position identical** | FAIL on the cumulative checksum only (§3.3) |

  ★★★ **Rectangles and checksum are reported separately**, and the classifier says which field moved
  — rectangle 555's `y` and `h` agree while `w` and `x` differ, which is a **width** divergence and
  therefore wrapping-shaped, not geometry.

- **AC-5 [byte-comparable] — THE GATE CAN FAIL.** `--fault-wrap` changes the wrap test from `>=` to
  `>` **in the reference module, not in the gate** (a gate that can manufacture its own failure
  proves nothing): **rectangle 0 diverges immediately — `h=42` against the oracle's `50` — and the
  glyph count moves by 37.**
  ★★★ **Honest note on the dispatch's wording**: AC-5 asked for a fault that moves the checksum
  *with the rectangles intact*. This fault moves both, because a wrap error changes the line count
  and the rectangle is derived from it. **A fault that moved only the checksum would have to change
  characters without changing layout, which is not a wrapping error at all** — so the requested
  shape does not exist for this mechanism, and this is the nearest true one.

- **AC-6 [state-comparable] — DONE.** §2V's table is the header of `tools/agivm/text.py`: seven
  rows, each naming the 6809 form and its cost. ★★★ Following `parser.py` §3.E's precedent, **the
  row most likely to be wrong is named in advance**: "the message is not copied" is the claim that
  conceals copies, and if the arena window is remapped between reading a message and drawing it,
  staging would be a copy the table has no row for. **Unknown until the port measures it.**

- **AC-7 [state-comparable] — UNCHANGED.** `get.string` needs the display buffer, a line buffer,
  **and the blocking input loop `messageBox` uses when `VM_FLAG_OUTPUT_MODE` is clear**
  (text.cpp:370-386). ★★ The renderer now exists; the blocking loop still does not.

- **AC-8 [byte-comparable] — PASS.** Nine titles, both arms, empty exclusion set — §4'.

- **AC-9 [state-comparable] — DISPOSITIONED.** `oracle_said.txt`: diagnostic, readable from P6.15's
  rename, **deliberately unconsumed**. `row24.txt`: dormant probe from a past investigation, **retire
  or give it a consumer** (follow-up). `text_events.txt`: ★★★★ **now consumed by
  `harness/tools/text_gate.py`** — the orphan this task was written to close.

- **AC-10 [state-comparable] — §7.**
- **AC-11 [suite] — §10.**

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 (verbatim).** Gates and both arms — §4'.

The gate, wrap isolated:
```
=== text gate: Kingquest1 ===
  sweep region : 32348 events kept, 3611 dropped after the last restore
  reference    : 596 messages across 90 logics
  rectangles   : ours 585   oracle 585   -- 585 identical before any divergence
  glyphs       : ours 31763   oracle 31763
  OK rectangles identical (585)
  *** CHECKSUM DIVERGES at draw 30183: 63002 vs 24062
      -> 30183 draws matched in position, colour AND checksum before this point
      NOTE: --skip-format breaks the cumulative checksum chain at the first excluded message
```
The gate, full corpus — the divergence that located `stringPrintf`:
```
  rectangles   : ours 596   oracle 596   -- 555 identical before any divergence
  glyphs       : ours 32041   oracle 31973
  *** RECTANGLE 555 DIVERGES -- WRAPPING (box WIDTH differs)
      ours w=102 x=27  oracle w=74 x=43
  msg 555: logic 98, len 23, no newline, longest word 23, contains % -> codes ['v','m']
  messages with a % format code: 11 of 596
```
AC-5, the fault:
```
  *** FAULT INJECTED (--fault-wrap): wrap test >= became > -- EXPECTED TO FAIL
  rectangles   : ours 585   oracle 585   -- 0 identical before any divergence
  *** RECTANGLE 0 DIVERGES -- WRAPPING (box HEIGHT differs)
      ours h=42 y=59  oracle h=50 y=59
  *** GLYPH COUNT DIVERGES: 31800 vs 31763  (delta 37)
```
§3.3's independent confirmation:
```
  checksum first diverges inside kept-message index 555
  first format-bearing message index : 555
  format-bearing message indices     : [555,556,557,558,559,560,561,562,570,584,586]
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; nothing shipped, no DECB image.

**25.3 operator-runtime-smoke:** `N/A — no visual surface this task.`

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **The gate's diagnostic split was changed from the dispatch's.** §2 framed rectangle
   divergence as geometry; the rectangle is derived from the wrap, so the gate classifies by which
   field moved. **Reported rather than silently implemented as specified.**
2. ★★★ **`--skip-format` was added** to isolate the wrap from the missing `stringPrintf`. It is a
   scoping arm, and every run states how many messages it excluded, so the claim's corpus is part
   of the output [L-85].

**Route accounting.** ★★★★★ **What I got wrong and the gate caught: I transcribed
`stringWordWrap` and believed it was the whole path.** It was not — `stringPrintf` runs first, and
I found that from a rectangle divergence rather than from reading `drawMessageBox` carefully enough.
★★★ **The dispatch predicted the difficulty would be the wrap; the wrap was correct on the first
run and the difficulty was one line above it.**
★★★ **Three self-inflicted encoding failures this task**: `Set-Content -Encoding ASCII` replaced
every ★ with `?` (lossy, unrecoverable — the file was rewritten), then a `.Replace` with a literal
`` `n `` corrupted the argparse block and re-introduced 14 mojibake runs. **PowerShell string
surgery on source files is the wrong instrument and I used it three times after knowing that.**

---

### 7 — Uncertainty flags  (and AC-10: what the dispatch did not anticipate)

1. ★★★★★ **`stringPrintf` runs before the wrap and expands against LIVE VM STATE.** `%v` is a
   variable's value, `%o` an object name, `%m` another message. **The reference will need VM state
   coupling to reproduce those 11 messages** — a dependency the text model did not have before.
2. ★★★★ **The wrap was correct on its first run.** The dispatch's premise — that wrapping is the
   difficulty — did not hold; the difficulty was the step above it.
3. ★★★★ **The checksum is cumulative**, so any message-level exclusion breaks it. Verified (§3.3),
   but it means **partial-corpus text gating can never check the checksum past its first gap** —
   a per-message checksum in patch 0010 would remove that limit.
4. ★★★ **AC-5's requested fault shape does not exist** for this mechanism (§4 AC-5).
5. ★★★ **The eight opcodes remain unimplemented**; the renderer has no caller.
6. ★★ **One title only.** 596 messages, Kingquest1 [L-85].
7. ★★ **p3b's `PIC_NOCOUNT` absence is now nine tasks old.**

---

### 8 — Follow-up candidates

1. ★★★★★ **Implement `stringPrintf`** and re-run the gate on all 596. It is the last piece between
   here and a green text gate, and it needs VM state.
2. ★★★★ **A per-message checksum in patch 0010**, so partial-corpus runs can check it (§7.3).
3. ★★★★ **Wire the eight opcodes** to the renderer once `stringPrintf` lands.
4. ★★★ **Capture a second title** so the gate's corpus is more than Kingquest1.
5. ★★★ **`row24.txt`** — retire it or give it a consumer.
6. ★★★ **p3b's missing `PIC_NOCOUNT`** — ninth task naming it.

---

### 9 — User interaction during task

1. Jay: **"check results"** — answered mid-task with the gate's outcome and what it located.

---

### 10 — Candidate(s) captured this task

`None.` ★★ The row this task earns — **a faithful transcription of the wrong function is
indistinguishable from an unfaithful transcription of the right one until something gates it** —
belongs with the five unfiled from P6.12–P6.16 as one candidate about instruments and scope, not as
a sixth thin row.

---

### 11 — Commit

See the commit carrying this report; pushed to `origin/wip` before reporting.
