## Form B Report — T-P0-092 / P6.37 — The typed line reaches `said()`; the echo cannot be drawn
**Class:** integration (§4A).  wip.  **AC-5 MET, AC-3 FAILS — and the failure is attributed exactly.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-12 23:30 (HEAD 885bc81, wip). Six files modified; the two known untracked files.

### 1 — Summary
★★★★★ **A line typed on a real keyboard reaches `said()` and the room answers it.** Jay, on the eye
gate: *"i did get a message box that it couldn't understand what i typed."* The instrument agrees —
**23 keys reached the editor, last `$0D`**. Keys → editor → ENTER → bracketed parse → `said()` → the
game's own reply. **AC-5, end to end.**

★★★★ **The echo is not drawn, and the cause is arithmetic rather than a mystery.** The text window
covers **rows 0-18**; the prompt is at **row 22**. `txt_blit` "REFUSES a glyph that would cross the
end of the window rather than wrapping" — so every prompt character is silently declined, and so is
the row clear. **§6 STOP: the fix needs a fourth MMU slot in the text window, which is an MMU write
outside `mmu_phase.s`.**

★★★ **§4C is attributed and it is not a defect.** Jay, same run: *"it looped back around to the
title screen and the scrolling text worked as expected."*

### 2 — Files modified
- `src/engine/text.s` — the `TEXT_PROMPT` block: `txt_pkey`, `txt_predraw`, `txt_prompt_on/off`,
  `txt_editon/off`, `txt_clearline`, `txt_dispstr`, the state and the three caller vectors.
- `src/harness/p3b_probe.s` — `TEXT_PROMPT`, the vectors, `p3_poll_key`, the park-loop latch,
  `p3_parse_line` (the single bracketed call site), `HAL_input_init`, `input.s`, `P3_KEY/P3_NKEY`.
- `src/harness/vm_text_ops.s` — `accept.input` / `prevent.input` real; `set.cursor.char`'s evidence.
- `src/harness/vm_tables.s` — regenerated; two entries repointed.
- `harness/tools/p3b_run.lua`, `p3b_show.ps1` — the typed path and its observables.
- `harness/tools/gates.manifest` — three re-baselines, one new blocked row.

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| `p3b` / `p3b_text` / `p3b_notick` / `p3b_nomap` | the P6.36 hashes | ✔ all four |
| region A headroom | ~2,289 | **2,289** |
| `p3b_parse` | green, word-count adjudicated | ✔ |
| `reg_discipline.py` | 10, one file, two registers | ✔ |

★★★ **§3(4) — callers of `par_parse`: FOUR in the tree, not one.** `p3b_probe.s`, `vm_probe.s`,
`parser_probe.s`, `input_probe.s`. Only p3b's is bracketed, and only p3b needs to be: the other
three stage flat dictionaries and have no `phase_vocab_*` symbol at all. **The dispatch's "expect
one" is right within p3b and wrong across the tree**, and the distinction is the point — the bracket
is a property of the WINDOWED configuration, not of `par_parse`.

### 4A — The body, at `9d9b9e93`

**(1) Which keys.** `text.cpp:740` — the `default:` language arm accepts **`0x20`-`0x7F`**.
`0x08` backspace [:768], `0x0A` LF **explicitly ignored** [:780, a `break` with no body], `0x0D`
ENTER [:782]. ★★ **ESC is not handled here at all** — no `0x1B` arm; cancelling is
`promptCancelLine` [:816] and nothing in the corpus reaches it.
★★★ **§2.1: the range is a ScummVM NORMALISATION.** Its own comment reads *"Sierra didn't check for
valid characters"*. We reproduce ScummVM, and that is a fact about ScummVM.

**(2) ★★★★★ ENTER parses in place.** `text.cpp:789`:
`_vm->_words->parseUsingDictionary((char *)&_prompt);` — inside `promptKeyPress`, then
`_promptCursorPos = 0`, `_prompt[0] = 0`, `promptRedraw()`. **Parse first, redraw second**, which
decides §1.3 and also keeps two mappings disjoint (§4B).

**(3) The bound** [text.cpp:753-763]:
```
maxChars = dialogue_Open ? TEXT_STRING_MAX_SIZE - 4
                         : TEXT_STRING_MAX_SIZE - strlen(getString(0));
if (_promptCursorPos) maxChars--;
if (scriptsInputLen < maxChars) maxChars = scriptsInputLen;   // var 24
```
★★★ **At the limit the key is DROPPED SILENTLY** — the `default:` arm's `if (maxChars >
_promptCursorPos)` simply does nothing. No beep, no truncation. Worth stating: "nothing happens" is
indistinguishable from a dead matrix to anyone watching.

**(4) ★★★★★ The cursor, and it is why `set.cursor.char` stays a stub.** `_inputCursorChar` is **0**
at `text.cpp:58`, and `inputEditOn`/`inputEditOff` are **both no-ops while it is zero** [:673,
:682]. **The prompt renders completely without it.**
★★★★ **The ROW is 22, not 0.** `text.cpp:63` initialises `_promptRow = 0` and **`cycle.cpp:442`
sets it to 22 in `runGame()`**, before the main loop, with no game asking. ★★★ Reading only the
declaration would have put the command line at the top of the screen. **§2H's second check — name
the CALLER — is what found it.**

**(5) `promptRedraw`** [text.cpp:848-867]: guarded on `_promptEnabled`; `clearLine(_promptRow,
background)`, `charPos_Set(_promptRow, 0)`, then `getString(0)` → `stringPrintf` →
`stringWordWrap(40)` → `displayText`, then `displayText(_prompt)`.
★★ `prevent.input` clears with colour **0**, not the background attribute [op_cmd.cpp:1997] — the
oracle passes a literal there and `_textAttrib.background` in `promptRedraw`, and they are different
calls.

**(6) Box and prompt together.** `_messageState.dialogue_Open` only changes `maxChars` [:753-757].
In practice they do not coexist: `messageBox` blocks in its own inner loop, so the main cycle that
polls `promptKeyPress` is not running while a box is up. **Tier: ScummVM; believed original** — the
blocking box is AGI's own documented shape.

### 4B — §1.3's bracket, answered

★★★★★ **ONE call site, and the bracket is inside it.** `p3_parse_line` holds the only
`jsr par_parse` in this probe; the scripted feed and the command line's ENTER both enter there.
**A third caller cannot get the bracket wrong because there is nothing for it to get wrong.**

★★★★ **text.s never calls `par_parse` at all** — the parse is a VECTOR the probe installs
(`txt_parse`), the same idiom as `txt_restore`. That is what keeps an engine file free of a window
only the harness knows how to open.

★★★★ **THE PROPOSAL §1.3 ASKS FOR, stated and not taken.** Putting the bracket inside `par_parse`
would make the invariant structural for every client. It needs the `-DPHASE_VOCAB` treatment
`mmu_phase.s` got, because three of the four callers have no such symbol — a change to gated engine
source, and a task of its own [§22.5].

★★★ **A second mapping conflict, found by construction:** `tx_window_enter` maps the framebuffer
across slots 4-6, and **slot 5 is the vocabulary window**. They cannot both be open. The oracle's
own order — parse, then redraw — is exactly the order that keeps them disjoint, so the port follows
it for correctness and gets the mapping for free.

### 4C — AC-8: the single-line text, attributed

★★★★★ **It was the corpus doing what it should.** Jay, on this task's eye gate: *"it looped back
around to the title screen and the scrolling text worked as expected."*

★★★ The earlier observation was Kingquest1 **room 1**, where the substituted message is **16 bytes**
— one line at a 30-column wrap. `txt_wrap` is ported, `TXT_ROWS` is 25, and the title screen's
multi-line scroll renders correctly on the same build. **No defect; no change made.**

### 4D — ★★★★★ AC-3 FAILS, and the cause is two numbers

The echo path is `txk_char` → `txt_winon` → `txt_editon` → `txt_dispch` → `txt_blit`.

| | |
|---|---|
| the text window | `TX_WIN`, three blocks flat across slots 4-6 = 24,576 B = **rows 0-18** [vm_text_ops.s:68] |
| the prompt row | **22** [cycle.cpp:442] |

★★★★★ **`txt_blit` "REFUSES a glyph that would cross the end of the window rather than wrapping"**
[text.s's own header] and `tx_boxfill` skips any row at or past `txf_yhi` = 160 pixel rows. Row 22
is pixel row 176. **Every prompt glyph and the row clear are silently declined.**

★★★★ **So AC-2's first half is real and its second half is unobservable**: `accept.input` sets
`enabled=1` (measured, room 1) and `promptRedraw` runs, but nothing it draws can land. Jay: *"no
prompt line showed, i could not see keys typed."*

★★★★★ **THE FIX IS A §6 STOP.** Reaching row 22 needs ~29,440 bytes = a **fourth** contiguous block,
i.e. slot 3 as well — an MMU write at `$FFA3`, outside `mmu_phase.s`. `vm_text_ops.s` already writes
`$FFA4`/`$FFA5`/`$FFA6` and records that as an open §2N ownership question [its lines 62-64]; **this
task will not widen it by one more register inside another task's diff.** The alternative — a
non-zero `txt_fbrow0` — is refused outright by `tx_boxfill`'s own assertion.

### 4E — ★★★★★ AC-7's fault arm exists; the typed GATE does not, and five explanations were wrong

**The arm:** `p3b_nomap` — ENTER's parse without the vocabulary bracket. Re-shown **RED** on this
binary, STUCK in cycle 30.

**The gate:** `P3B_TYPE` posts characters through `natkeyboard` into the matrix. **It delivers
zero.** Not once in 180 posts, with the queue drained after every one.

★★★★★ **FIVE HYPOTHESES, EACH TESTED, EACH WRONG**, recorded because §6 requires it and because the
list is the finding:

| tried | result |
|---|---|
| `-nothrottle` distorting delivery | ★ `input_gate.lua` posts successfully with it |
| **`HAL_input_init` never called** | ★★★★ **true and not the cause** — `input.s` was not even linked; fixed anyway, input.s's header states the precondition and `input_probe.s:95` records it costing that probe its first run |
| posting the whole line at once | 2 of 5 keys; one per park handshaken → 0 of 5 |
| no key queue → a one-deep latch in the park loop | still 0 of 180 |
| `-video none` starving `natkeyboard` | still 0 of 180 |

★★★★★ **AND THE ANSWER CAME FROM THE EYE GATE IN ONE RUN: a HUMAN's keypress arrives.** 23 keys,
last `$0D`, and the game replied. **A finger holds a key for tens of frames; `natkeyboard` holds one
for two or three, and the guest looks once per cycle, twelve frames apart.** The port's real limit
is a fast typist, not a broken matrix.

★★★ **`p3b_type` is in the manifest as `purpose=blocked`**, with its invocation and this
measurement, so the next task inherits both rather than rediscovering them.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output.**
```
p3b          13918 B  58AD3C27164BD63FDE17E18041160B28   <- byte-identical, AC-9
p3b_text     16157 B  0D7EBA163C0D8DA3AACB375C5119A3E5
p3b_notick   16154 B  454576C1DC4D017914F4CA8950745218
p3b_nomap    16154 B  DC9260A0912806DCD7EF284D8466A693
p3b_fault    15286 B  200BF98F241785C88B8B5B6578E615E5
region A: P3_CODE_END $5945, headroom 1723 B   (the command line cost 566)

★ source integrity: clean
per-picture: 45 PASS, 0 FAIL   resources 1264/1264   cels 9193/9193   composites 124/124
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse  -- all green
AC-2 SUMMARY: nine titles, 9/9 PASS
[reg-discipline] 10 access(es) in 1 file(s) over 2 register(s).   src/engine/mmu_phase.s
[hal-sync] OK x3 (coco_agi, POP3_port, karateka_coco3)
CHECK OK: src/harness/vm_tables.s matches optable.py.

FAULT ARMS, both RED on THESE binaries:
  p3b_notick  STUCK in cycle 9    p3b_nomap  STUCK in cycle 30
```
**25.2 bundled-artifact grep:** N/A.
**25.3 operator-runtime-smoke:** **PASSED (partial) — Jay, live, RGB**, Kingquest1 room 1.
★★★ **The box answered a typed line; the echo did not appear.** Jay's words verbatim in §9.

### 6 — Reactive deviations and route accounting

1. ★★★★★ **§6 STOP on AC-3.** The echo needs a fourth MMU slot in the text window. Attributed,
   measured, not repaired.
2. ★★★★ **`HAL_input_init` and `input.s` were added.** Not in the dispatch. `HAL_key_scan`'s own
   precondition had never been asserted in this probe; leaving it unasserted while debugging the
   key path would have been debugging with a known-broken premise.
3. ★★★★ **A one-deep key latch in the probe's park loop.** A harness construct with no counterpart
   in a shipped interpreter, and the note in the source says so. It did not fix the posting problem
   and it is kept because it is the right shape for the real one.
4. ★★★ **A no-dictionary guard in `p3_parse_line`.** `par_said` has one; `par_parse` had none, and
   the typed path is the first caller that can arrive without a staged dictionary. **The first
   version cost `p3b` six bytes** — §6's own stop condition — and is now scoped to `TEXT_PROMPT`.
5. ★★ **`vm_tables.s` regenerated.** Two entries repointed; every probe that does not wire the text
   opcodes resolves them to the same `vm_op_modelled` address and is byte-identical.
6. **ROUTE ACCOUNTING.** I proposed the `par_parse`-internal bracket in §4B and did **not**
   implement it. Everything else in §4B was implemented as described. `set.cursor.char` remains a
   stub, with §4A(4)'s evidence rather than an intention.

### 7 — Uncertainty flags

**7.1 ★★★★ AC-4 is written and unexercised.** The bound follows `text.cpp:753-763` including the
`_promptCursorPos` decrement and the var-24 clamp. **No run has typed 40 characters**, and the
`dialogue_Open` arm is `get.string`'s and is out of scope. Untested code that looks right.

**7.2 ★★★ The prompt prefix cannot appear in this probe, and the reason is a named stub.**
`promptRedraw` draws `getString(0)` first; `vmop_set_string` is a bare `rts`, so no slot is ever
populated and `txt_strbase` is 0. The port skips the prefix when the base is null rather than
substituting from address 0 [the null-base read that walked the seed stack]. **A real interpreter
shows `>`; this shows nothing in front of what you type.**

**7.3 ★★ `err 1` recurred** in the typed run, and the run ended back at room 83 having left room 1.
Unexplained across five tasks now.

**7.4 ★ `p3b_fault` moved** (15,234 → 15,286) from the `input.s` link, which applies under
`HAL_KEYBOARD` regardless of `TEXT_MODELLED`. Re-baselined.

### 8 — Follow-up candidates
1. ★★★★★ **Reach row 22** — the text window against the MMU ownership question (§4D). **AC-3 and
   AC-2's second half are both blocked on it, and so is any status line.**
2. ★★★★ **A key queue, or a VBL-driven latch**, so a fast typist is not dropped (§4E).
3. ★★★ **`p3b_type` as a real gate**, once (1) or (2) makes posting viable.
4. ★★★ **The bracket inside `par_parse`** (§4B).
5. ★★ **`set.string`**, which is what the prompt prefix needs (§7.2).
6. ★★ **AC-4 exercised at the limit** (§7.1). ★ **`err 1`** (§7.3).

### 9 — User interaction during task
1. Eye gate, Kingquest1 room 1, Jay typing — *"no prompt line showed, i could not see keys typed
   but i did get a message box that it couldn't understand what i typed. also, it looped back
   around to the tiltle screen and the scrollinf text worked as expected. then mame closed."*
   → §4C (attribution), §4D (the echo), 25.3, and AC-5 met.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-12-the-test-harness-cannot-hold-a-key-as-long-as-a-finger.md`

### 11 — Commit
`101de9c` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `569b01d`, one row under `seeds/AGI/live/`.
