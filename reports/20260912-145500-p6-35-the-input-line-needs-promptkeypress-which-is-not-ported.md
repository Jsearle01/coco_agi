## Form B Report — T-P0-090 / P6.35 — The input line needs `promptKeyPress`, which is not ported
**Class:** integration.  wip.  **STOP — §6 trigger 4, and a size wall.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-12 14:55 (HEAD f7766b1, wip). ★★★ **No file was modified this task.** `git status` shows
only the two untracked files that are not mine.

### 1 — Summary
★★★★★ **AC-1 is met and it stops the task, which the dispatch says is a pass.** The six citations
are below. Three of them change the work.

1. ★★★★★ **The oracle has TWO key handlers and the port has the wrong one.** The command line is
   `TextMgr::promptKeyPress` (`text.cpp:720`); `get.string`'s editor is `TextMgr::stringKeyPress`
   (`text.cpp:987`). **`gs_keypress` is a port of `:987`.** So §1.1's "the pieces are all green"
   holds for four components and **the edit loop this task needs has no port at all.**
2. ★★★★ **§1.2(4) is wrong: the per-cycle clear already exists and is already correct.**
   `vm_post_cycle` clears `FLAG_ENTERED_CLI` and `FLAG_SAID_ACCEPTED` every cycle, matching
   `cycle.cpp:275`.
3. ★★★ **§1.1's "the consumer is wired and waiting" is RIGHT**, and stronger than stated.

★★★★ **And it would not fit anyway**: the text configuration has **277 bytes** of headroom against
roughly 550-700 for a `promptKeyPress` port plus the prompt line plus the two opcodes.

### 2 — Files modified
**None.** Citation and measurement.

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| `p3b` | `58AD3C27…` 13,918 B | ✔ |
| `p3b_text` / `p3b_box` | `C4A4346B…` 15,555 B | ✔ , **headroom 277 B** |
| `p3b_notick` | `2849A07A…` 15,552 B | ✔ |
| untracked | the two known files | ✔ |

**§3(2) `par_parse`, quoted** — `parser.s`, its own header:
> *"par_cli is set from the word COUNT and par_accepted is always cleared here. Those two are
> par_said's entire guard, so they belong to this routine and not to its caller."*
It takes `par_inbuf` (raw, NUL-terminated), calls `par_clean`, and sets `par_egon`, `par_notfound`,
`par_cli`, `par_accepted`, `par_fpos`.

**§3(3) flag numbers** — `VM_FLAG_ENTERED_CLI` = **2**, `VM_FLAG_SAID_ACCEPTED_INPUT` = **4**
[`vm_tables.s:22,30`]. ★★★★ **These match the oracle** (`agi.h:284,286`), so **§6's first trigger is
NOT hit.**

**§3(4)** the five P6.28d stubs remain stubs, `set.cursor.char` ($6C) among them.

### 4A — The six citations, at `9d9b9e93`

**(1) Where the edit loop lives, and does it block?** ★★★★ **It does NOT block. It is per-cycle.**
```
cycle.cpp:350      if (_text->promptIsEnabled()) {
cycle.cpp:351          _text->promptKeyPress(key);
```
Inside the main cycle's key dispatch. ★★★ **This is the opposite of `messageBox`**, which blocks in
a nested inner loop [text.cpp:397-407], and it is the shape decision §4A(1) exists to settle: the
input line is polled, not waited on. **Tier: ScummVM (secondary); believed original** — a
single-threaded interpreter polling its keyboard once per cycle is the natural shape and the
blocking cases are the exceptions AGI marks explicitly.

**(2) What `accept.input` / `prevent.input` change.** A boolean and a redraw.
```
op_cmd.cpp:1985-1986   promptEnable();  promptRedraw();
op_cmd.cpp:1994-1997   promptDisable(); inputEditOn(); clearLine(promptRow_Get(), 0);
text.cpp:710-718       _promptEnabled = true / false;  promptIsEnabled()
```
★★ `prevent.input` also **clears the prompt row** — so it is not merely a flag, it erases what is
on screen.

**(3) ★★★★★ The flags and variables the input path touches — enumerated, not confirmed.**
`cycle.cpp:205-206`, this project's own oracle instrumentation:
> *"parseUsingDictionary() itself sets VM_FLAG_ENTERED_CLI and clears SAID_ACCEPTED_INPUT, so the
> two guards testSaid() checks are established by the same call a keystroke would make."*

Also touched: `VM_VAR_WORD_NOT_FOUND` (`words.cpp:407`, set to the 1-based index of an unknown
word), `VM_VAR_MAX_INPUT_CHARACTERS` (`text.cpp:722`, the length limit), `VM_VAR_KEY`.
★★★★ **Our numbers match** (§3(3)), so nothing here stops the task.

**(4) ★★★★ WHEN it is cleared — and we already do it.**
```
cycle.cpp:275      setFlag(VM_FLAG_ENTERED_CLI, false);
```
at the foot of the `while (runLogic(0) == 0 …)` loop, alongside `VM_VAR_WORD_NOT_FOUND = 0`. Two
further clears at `:446` and `:574`. **`vm_post_cycle` already clears both flags and both variables
every cycle** — the routine's own comment calls them "the four resets run() does after each
interpreted cycle". ★★★ **§1.2(4) is wrong and AC-7 would have passed without any work.**

**(5) The prompt character and the row.** `cmdSetCursorChar` (`op_cmd.cpp:2106-2112`) takes a
**message number**, not a character: it indexes `_curLogic->texts[textNr]` and passes the first
character to `inputSetCursorChar`. The row is `_promptRow`, initialised to **0** (`text.cpp:63`) and
settable via `promptRow_Set` (`text.cpp:696`).

**(6) How parsed words reach `said()`.** `parseUsingDictionary` writes `_egoWords[wordCount].id`
(`words.cpp:398`) and `testSaid` reads them back through `_egoWords[wordNr].id` (`words.cpp:437`).
★★ **Our `par_ego` is the same shape** — 20 × u16 word numbers — so the comparison §4A(6) asks for
is a match, not an assumption.

### 4B — ★★★★★ What §1.1 got wrong, and it is the finding

§1.1 lists four green components and says the missing piece is glue. **Four are green.** But:

| the dispatch's reading | measured |
|---|---|
| "the edit loop" exists, gated 10/10 [P6.24] | ★★★★★ what exists is `input_probe.s` driving `gs_get_string` / `gs_keypress` / `gs_finish` — **`get.string`'s editor**, `text.cpp:987` |
| the command line needs glue | it needs **`promptKeyPress`, `text.cpp:720`, which has NO port** |

`text.s` records its provenance line by line and ports six routines — `stringPrintf`, `stringWordWrap`,
`drawMessageBox`, `displayText`, `closeWindow`, `charAttrib_Set`. **`promptKeyPress` is not among
them and appears nowhere in `src/`.**

★★★★ **§1.3 is therefore right in a way it did not anticipate.** It says "a named-prompt opcode and
the interpreter's command line are different features" — and the only edit loop we have belongs to
the *other* feature. ★★★ **Reusing `gs_keypress` for the command line would be porting the wrong
oracle routine**, which is §6's fourth trigger in substance if not in letter: `get.string`'s
machinery is what would be pressed into service.

### 4C — The size wall, priced

`p3b_text` already links `text.s` and `parser.s`, so the delta is what is missing:

| component | bytes | source |
|---|---|---|
| `getstring.s` (if reused — and it should not be) | 404 | measured from `input_probe`'s listing |
| `input_probe.s`'s own loop scaffolding | 399 | same |
| a `promptKeyPress` port | not written | comparable to `gs_keypress`'s share of the 404 |
| `accept.input` / `prevent.input` + prompt redraw | ~60 | estimate, labelled as one |

**Headroom: 277 bytes.** ★★ Even the most favourable reading — reuse `getstring.s` wholesale, which
§4B says is the wrong routine — is 404 against 277.

### 5 — Verdict-time evidence (v0.7 §11)
**25.1 fresh tool output:** §3's three rebuilds, all MATCH; the `input_probe` decomposition in §4C.
★★ No gate was run: **nothing changed**, and every artifact is byte-identical to T-P0-089's close.
**25.2 bundled-artifact grep:** N/A.
**25.3 operator-runtime-smoke:** **Not offered** — AC-12 needs a working input line.

### 6 — Reactive deviations and route accounting
1. ★★★★★ **Stopped at AC-1**, which the dispatch states is a pass. The citations changed the task
   before a line was written — which is L-116's entire point.
2. ★★ **Nothing was implemented.** §4B means the first line of code would be a fresh port of
   `promptKeyPress`, and §4C means it would not fit; starting either would be work I could not land.
3. ★★★ **ROUTE ACCOUNTING.** I proposed nothing I did not do. AC-2 through AC-12 are unreachable
   without §4B's port and are reported as blocked rather than partially attempted.

### 7 — Uncertainty flags

**7.1 ★★★ I misread this myself before the citations corrected me.** Seeing `input_probe.s`
reference `par_inbuf` and drive a matrix-to-parser path, I concluded "the edit loop already exists"
and said so. It exists for `get.string`. ★★ **The provenance comment on `gs_keypress` — `text.cpp:987`
— is what settled it**, and it took one read. Recorded because it is the same shape as §4B's finding
one level up: a component that looks like the one you need because it does something similar.

**7.2 ★★★ The 277-byte wall is the same class as T-P0-089's and the technique that solved that is
spent.** `vm_tables.s` is already relocated and the seed-stack slack it used is consumed to within
14 bytes of its limit. ★★ I have not searched for a second relocation candidate; that is a map task,
not this one.

**7.3 ★★ `VM_VAR_MAX_INPUT_CHARACTERS` is in the enumeration and has no port.** `text.cpp:722` reads
it to bound the line. Whoever implements §4B needs it; it is not a blocker, it is an omission that
would otherwise be found late.

**7.4 ★ `set.cursor.char` takes a MESSAGE NUMBER, not a character** (§4A(5)). Worth stating because
the opcode's name invites the other reading, and it is one of the five stubs.

### 8 — Follow-up candidates
1. ★★★★★ **Port `promptKeyPress` (`text.cpp:720`)** — the actual missing component, and the thing
   this task assumed existed.
2. ★★★★ **The map, again** (§7.2). Every text-configuration feature since P6.28 has ended at a
   headroom wall; that is now a pattern rather than an incident.
3. ★★★ **`VM_VAR_MAX_INPUT_CHARACTERS`** (§7.3).
4. ★★ **`err 1`**, still unexplained.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-12-a-component-that-does-something-similar-is-not-the-component.md`

### 11 — Commit
★★ **No source commit — nothing was modified.** `wip` stands at `f7766b1`, unchanged from §0, and
this report is the only thing committed on top of it.
Pool: `methodology-candidate-pool` `7ffadac`, one row under `seeds/AGI/live/`.
