## Form B Report — P6.29 (T-P0-085) — the oracle already has the flag: var 21 and flag 15
**Class:** integration (§4A) — **stopped at §6's trigger after §4A, before any code.**  wip.

★★★★★ **AD-183 is CONFIRMED and REFINED, and the design changes.** `print` does wait — but the
oracle already carries **two game-controlled dismissal controls**, so the harness flag §1.1 proposed
is the wrong mechanism:

- ★★★★★ **`VM_FLAG_OUTPUT_MODE` (flag 15)** — set, and the window is **non-blocking**: `messageBox`
  clears the flag, signals, and **returns without waiting at all**.
- ★★★★★ **`VM_VAR_WINDOW_AUTO_CLOSE_TIMER` (var 21)** — non-zero, and the wait **auto-closes** after
  N half-seconds with no keypress.

★★★★ **§4B anticipated exactly this — *"if §4A finds a real timeout variable, prefer the oracle's
mechanism over a harness one"* — and §6 makes it a stop: *"finds a timeout mechanism that changes
the design."* It does. Reporting before writing a byte.**

★★★ **Both symbols are already in `tools/agivm/optable.py`** (flag 15 at :423, var 21 at :448),
generated from the pin. **The mechanism is available today; it does not need inventing.**

★★★★ **And a second finding that halves the work: `display` does NOT wait and must not get the
wait.** Only `print` boxes.

---

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-085 dispatch receipt (HEAD `670fea4`, wip). ★★ **No source file was modified**;
`git status` shows only two untracked files, one of which is new — see §7.5.

---

### §3 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi === 670fea4 wip
  ?? agi-coco3-design-v1_3.md          ★ NEW, untracked, not mine to touch -- §7.5
  ?? coco_agi.code-workspace
=== POP3_port === 104b197      === karateka_coco3 === 29f8f0a
[hal-sync] OK x3 (11 files compared)
[reg-discipline] 8 in src/engine/mmu_phase.s -- $FFA5 $FFA6
CHECK OK: src/harness/vm_tables.s matches optable.py.

(3) p3b row:      13918 B  58AD3C27164BD63FDE17E18041160B28      ★ matches
(5) spare:        P3_CODE_END = $52F8   CP_CEL = $5300   SPARE = 8 bytes   ★ matches
(4) p3b_text row: 14582 B  FA7F2FB9CD542B58ED3D4E75D365C43E      ★ matches
(2) vm_probe.bin:  9667 B  771F147DE2A54688ABFA8823784323DB      ★ matches
```

★★ **§2T citation for checks (1) and (2)'s gate RUNS.** `res` 1,264/1,264 and `vm` 9/9 were measured
at P6.28h §5 on HEAD `1008d9d`. **No tracked file has changed since** — `git status` shows only
untracked files, and both probe binaries above hash to their P6.28h values. ★★★ **Artifacts are a
function of their inputs; the inputs are provably unchanged, so the outputs are** [§2T]. The two
runs were not repeated because this task modifies nothing and stopped before it could.

★★ **§2S:** siblings read at their **`wip` working trees**, not a public ref; same refs P6.28h §3
recorded.

★ **No stop condition fired in §3.** The stop came from §4A.

---

### 1 — Summary

The oracle check answered all four questions, confirmed the Orchestrator's tier-3 recollection about
a timeout variable, and **replaced the dispatch's design**. No code was written.

### 2 — Files modified

**None.** ★★ This report only.

### 3 — Reasoning — §4A, quoted at the pin `9d9b9e93`

**3.1 Q1 — where the wait lives.**

`op_cmd.cpp:2201` → `text.cpp:344` → `text.cpp:370`:

```
2201  void cmdPrint(AgiGame *state, AgiEngine *vm, uint8 *parameter) {
2202      int16 textNr = parameter[0];
2204      vm->_text->print(textNr);

 344  void TextMgr::print(int16 textNr) {
 346      if (textNr >= 1 && textNr <= _vm->_game._curLogic->numTexts) {
 347          logicTextPtr = _vm->_game._curLogic->texts[textNr - 1];
 348          messageBox(logicTextPtr);
```

and the wait itself, `text.cpp:395-407`:

```
 395      _vm->inGameTimerResetPassedCycles();
 396      _vm->cycleInnerLoopActive(CYCLE_INNERLOOP_MESSAGEBOX);
 397      do {
 398          _vm->processAGIEvents();
 399          _vm->inGameTimerUpdate();
 401          if (windowTimer > 0) {
 402              if (_vm->inGameTimerGetPassedCycles() >= windowTimer) {
 403                  // Timer reached, close automatically
 404                  _vm->cycleInnerLoopInactive();
 407      } while (_vm->cycleInnerLoopIsActive() && !(_vm->shouldQuit() || _vm->_restartGame));
```

**3.2 Q2 — what dismisses it. NOT "any key."**

`text.cpp:421-443`:

```
 421  void TextMgr::messageBox_KeyPress(uint16 newKey) {
 422      switch (newKey) {
 423      case AGI_KEY_ENTER:      _vm->cycleInnerLoopInactive(); break;
 426      case AGI_KEY_ESCAPE:     _messageBoxCancelled = true;
 428                               _vm->cycleInnerLoopInactive(); break;
 430      case AGI_MOUSE_BUTTON_LEFT:
 435          if (isMouseWithinMessageBox()) _vm->cycleInnerLoopInactive();
 440      default:                 break;
```

★★★★ **ENTER dismisses; ESCAPE dismisses and sets `_messageBoxCancelled`; a left click inside the
box counts as ENTER. Every other key does nothing.** ★★★ AC-7's wording — *"stays until a key"* —
would have been satisfied by a build that dismissed on any key, which is **not** what the oracle
does. ★★ This project has the ENTER/ESC decode already: `HAL_KEY_ENTER $0D` and `HAL_KEY_ESC $1B`
[hal_globals.s], gated 10/10 at P6.24.

**3.3 Q3 — the timeout. CONFIRMED, and it is a VM VARIABLE the game sets.**

`text.cpp:386-392` and `:411`:

```
 386      // timed window
 387      uint32 windowTimer = _vm->getVar(VM_VAR_WINDOW_AUTO_CLOSE_TIMER);
 390      // 1 = 0.5 seconds. NB: ScummVM runs at 40 fps, not 20, so we have
 391      // to multiply by 20, not 10, to get the number of cycles.
 392      windowTimer = windowTimer * 20;
 ...
 411      _vm->setVar(VM_VAR_WINDOW_AUTO_CLOSE_TIMER, 0);
```

`agi.h:237` — `VM_VAR_WINDOW_AUTO_CLOSE_TIMER, // 21`, and **`tools/agivm/optable.py:448` already
carries `VM_VAR_WINDOW_AUTO_CLOSE_TIMER = 21`**, generated from the pin.

★★ **A ScummVM normalisation is visible in the comment and is NOT ours to copy**: the `* 20` is
ScummVM's 40 fps correction. **The DATA-FORMAT fact is "1 = 0.5 seconds"**; the multiplier belongs
to the host's frame rate [§2.1 — this is exactly the split T-P0-084h §3.1 named].

**3.4 ★★★★★ Q3b — the finding the dispatch did not anticipate: `print` does not always block.**

`text.cpp:373-380`, **before** the wait:

```
 373      if (_vm->getFlag(VM_FLAG_OUTPUT_MODE)) {
 374          // non-blocking window
 375          _vm->setFlag(VM_FLAG_OUTPUT_MODE, false);
 377          // Signal, that non-blocking text is shown at the moment
 378          _vm->nonBlockingText_IsShown();
 379          return true;
 380      }
```

`agi.h:297` — `VM_FLAG_OUTPUT_MODE, // 15`, and **`optable.py:423` already carries it**.

★★★★★ **So "blocking or not" is ALREADY a game-controlled switch in the oracle, and "auto-close
after a delay" is a second one.** The dispatch's §1.1 proposed a *harness* flag selecting the
dismissal source. ★★★★ **The oracle supplies the same choice through real VM state that a LOGIC
sets** — which is better on every axis the dispatch cared about:

- **`p3b_text` gates the shipping program**, not a variant, because there is no second code path —
  §1.1's whole concern dissolves.
- **No bytes for a second arm.** With 8 bytes spare [AD-192] that is not a small matter.
- **The "auto arm" is a state the harness writes**, exactly as `p3b_room.lua` already jumps rooms by
  writing var 0 and flag 5 [AD-99] — an established, gated technique in this project.

**3.5 ★★★★ Q4 — `print` and `display` differ, and `display` must NOT get the wait.**

`text.cpp:240-260`: `display()` does `charPos_Push` / `charPos_Set` / `stringPrintf` /
`stringWordWrap` / `displayText` / `charPos_Pop`. ★★★ **No box, no inner loop, no wait.** Only
`print` reaches `messageBox`.

★★ **So the wait belongs in `vmop_print` / `vmop_print_f` alone.** The four handlers were wired
together at P6.28d; **they diverge here**, and a wait added to all four would block the scroll panel
that Jay's eye gate just passed.

**3.6 ★★ Authority, per §2.1.** All of the above is **§2 tier 3 — ScummVM, best secondary evidence,
not the original.** ★★★ What is **data-format** (and so binding on any implementation): that `print`
boxes and `display` does not; that var 21 is a half-second unit; that ENTER and ESC are the
dismissal keys, ESC additionally cancelling. ★★ What is **ScummVM's own** (and so not automatically
ours): the `* 20` fps correction, the mouse-click path, and `_noSaveLoadAllowed`.

**3.7 ★★ §2H's three checks.**

1. **A second mechanism for another object class?** ★★★★ **Yes, and finding it is this report.**
   `print` and `display` are the two object classes, and they differ exactly at the wait. **A first
   reading of `cmdPrint` alone would have put the wait in all four handlers.**
2. **The calling routine.** `messageBox`'s caller is `print`, whose caller is `cmdPrint` — but the
   *enclosing* facts are the two guards **above** the loop: flag 15 short-circuits it entirely and
   var 21 bounds it. ★★★ **The wait is not the mechanism; the wait plus its two governors is.**
3. **Grep the reports.** AD-183 has been carried through five tasks as *"print does not block"*.
   ★★ **It is confirmed** — and *"put it behind a flag"* turns out to describe something the oracle
   already does, which no prior report had checked.

### 4 — Verification (AC-by-AC)

★ **Per L-112, each AC names what observed it.**

- **AC-1 [citation · oracle]** ★★★★★ **MET, and it ended the task.** All four questions answered
  with file:line at the pin, tier named, the §2.1 split stated in §3.6. ★★★ **The dispatch called
  this "a pass for the process" and it is: a five-task-old open item is now specified, and a design
  that would have cost bytes and a second code path is retired before it was written.**
- **AC-2 [byte-comparable · gate]** ★★★ **MET by §2T citation** — `res` 1,264/1,264 and `vm` 9/9
  unchanged, because **no tracked file changed**; both probe hashes match P6.28h. See §3's note.
- **AC-3 [state-comparable · fault injection]** **NOT REACHED** — no implementation.
- **AC-4 [byte-comparable · assembler]** ★★ **MET as a baseline, not as a result.** `p3b` 13,918 B
  `58AD3C27…`; `p3b_text` 14,582 B `FA7F2FB9…`; **spare against `CP_CEL` = 8 bytes.**
- **AC-5 [suite]** **NOT RUN.** Nothing changed; the suite was green at P6.28h and its inputs are
  unchanged. ★★ Stated rather than skipped quietly.
- **AC-6 [state-comparable · injection]** **NOT REACHED.**
- **AC-7 [eye gate — Jay]** ★★★ **NOT RUN, and its wording needs revising before it is** — see
  §3.2: *"stays until a key"* is satisfied by a build that dismisses on **any** key, which the
  oracle does not do. **ENTER or ESC.**
- **AC-8 [byte-comparable · manifest]** **NOT REACHED.**
- **AC-9 [tooling]** ★★ **MET.** `hal_sync_check.py` OK ×3; `reg_discipline.py` 8 in
  `mmu_phase.s`; `gen_vm_tables.py --check` **CHECK OK**.
- **AC-10** One candidate; §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1** — §3's grep and §3.1–3.5's citations are the evidence, quoted from
`C:\Projects\scummvm` at `9d9b9e93` (`git rev-parse` confirms the pin). The two symbol definitions,
in both trees:

```
agi.h:237     VM_VAR_WINDOW_AUTO_CLOSE_TIMER, // 21
agi.h:297     VM_FLAG_OUTPUT_MODE,        // 15
optable.py:448  VM_VAR_WINDOW_AUTO_CLOSE_TIMER     = 21
optable.py:423  VM_FLAG_OUTPUT_MODE                = 15
```

**25.2** N/A — nothing built.
**25.3** ★★ **N/A — and explicitly not "pending Jay".** The task stopped before anything could reach
a screen. AC-7 is unrun and its wording is queried above.

### 6 — Reactive deviations and route accounting

**Deviation 1 — §4A was taken BEFORE §3's two gate runs.** §3 orders the grep first. ★★ The four
*static* checks were done first and all matched; the two *runs* are ~20 minutes and §4A can end the
task, so the cheap decisive check went first and the runs were then discharged by §2T citation
rather than repeated on an unmodified tree. **Stated because it inverts the dispatch's order.**

**ROUTE ACCOUNTING.** ★★★★ **§4A complete. §4B, §4C, §4D not started** — §6's trigger fired on
§4A's own terms. ★★★ **No code, no flag, no manifest edit, and the design spec was not touched**
[§2D — and §9 correctly asked for proposed text only this time].

★★ **I did not implement the harness flag anyway "to have something".** §4B says prefer the oracle's
mechanism; the oracle's mechanism is a different design, and building the superseded one first would
have been work whose only purpose was to be deleted.

### 7 — Uncertainty flags

1. ★★★★ **How our VM reaches `messageBox_KeyPress` is unmodelled.** The oracle dismisses through an
   event pump inside an inner loop (`CYCLE_INNERLOOP_MESSAGEBOX`), and **P6.21 §3 recorded that the
   port has no such re-entry** — `getstring.s` was split start/keypress/finish precisely so the
   caller owns the loop. **The wait's SHAPE on our side is therefore an open design question**, not
   a transcription.
2. ★★★ **Whether the byte budget can hold it is still unknown**, and now unknown for a smaller
   thing: a wait governed by var 21 and flag 15 needs no second arm. **8 bytes remains the
   constraint** and §1.2's three escapes remain closed.
3. ★★ **`_messageBoxCancelled` has a caller-visible meaning** — `messageBox` returns false on ESC —
   and what our port does with that return is unexamined.
4. ★★ **The `* 20` is ScummVM's frame-rate correction, not AGI's.** Our cycle rate is not 40 fps, so
   **the conversion from var 21 to our own timebase must be derived, not copied** [§2.1].
5. ★★ **`agi-coco3-design-v1_3.md` is new and untracked at the repo root.** Not committed, not
   read, not edited — flagged only because it appeared during this task and §2D makes the design
   spec the Orchestrator's.

### 8 — Follow-up candidates

- ★★★★★ **Re-issue with the oracle's mechanism**: the wait governed by **flag 15** and **var 21**,
  in `vmop_print`/`vmop_print_f` **only**; the harness sets var 21 for the headless arm exactly as
  `p3b_room.lua` writes var 0 [AD-99]. ★★★ **No harness flag, no second code path, no extra bytes.**
- ★★★ **Revise AC-7's wording** to ENTER or ESC (§3.2).
- ★★★ **Settle §7.1** — what shape the wait takes without an inner-loop re-entry — before estimating
  bytes.
- ★★ **Derive var 21's conversion to our timebase** (§7.4).

### 9 — User interaction during task

**None.**

### 10 — Candidate(s) captured this task

One, to `seeds/AGI/live/`:

- `2026-09-10-check-whether-the-reference-already-exposes-the-control-you-are-about-to-invent`
  — *initiator: executor*. A test-only flag was specified to make a blocking wait skippable
  headlessly; the reference already exposed both "do not block" and "close after N" as ordinary
  game-visible state. **A harness control invented alongside a reference that has one is a second
  code path the gate then cannot avoid testing instead of the real one.**

### 11 — Commit

**No source commit** — the tree is byte-identical to `670fea4`. This report only.
