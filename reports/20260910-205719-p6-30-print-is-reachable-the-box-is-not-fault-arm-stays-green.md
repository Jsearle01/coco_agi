## Form B Report — T-P0-086 / P6.30 — `print` is reachable; the box is not. The fault arm stays green
**Class:** measurement.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-10 20:57 (HEAD b3317bf, wip). Clean but for the two untracked files that are not mine —
`agi-coco3-design-v1_3.md` (Orchestrator's, §2D) and `coco_agi.code-workspace` (Jay's).

### 1 — Summary
The census is **not empty**: 368 candidate rooms across eight titles contain a `print` on the entry
path. The room jump works, lands and is dispatched, and **`print` does execute on the port**. But
★★★★★ **the fault arm did NOT go red** — `-DTEXT_FAULT_NOTICK` and the clean build produce
identical observables, because `print` returns before it draws a box and therefore never enters the
wait loop. Measured, not inferred: a checksum of the substitution buffer is **byte-identical across
three different message numbers**, so nothing is being substituted. Per §4C and §6 that is a stop,
not something to tune. **AC-3, the task's deliverable, is UNMET**, and the reason is a defect
reachable only by changing `src/`, which this task does not do. AC-4 holds: no file under `src/` was
modified.

### 2 — Files modified
Tools and reports only.
- `harness/tools/print_reach_census.py` — NEW. §4A's static census.
- `harness/tools/print_first_cycle.py` — room jump with landing verification, `--rooms`,
  `--repeat`, `--set-var`, and the flag-15 branch column.
- `harness/tools/p3b_run.lua` — `P3B_ROOM`/`P3B_ROOM_AT`/`P3B_SETVAR`, landing evidence, and a
  checksum on the substitution buffer.
- `harness/tools/vm_stage.py` — `--room`/`--room-at`, so the staging run makes the same jump.
- `harness/tools/p3b_show.ps1` — passes the jump to the stager.

### 3 — Pre-dispatch grep (C-13)
| check | expected | found |
|---|---|---|
| `git status` | clean but for the two known untracked files | ✔ exactly those two |
| `p3b_text` | `AF0B2A02…` 15,036 B | ✔ |
| `p3b_notick` | `2268DAB7…` 15,033 B | ✔ |
| delta | 3 bytes | ✔ **3** |

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement] — §4A's census.** **MET.** Table below.
- **AC-2 [measurement] — §4B's confirmations.** **MET.** Landing evidence and repeats below.
- **AC-3 [state-comparable · fault injection] — the fault arm goes red.** ★★★★★ **UNMET.** Both
  arms are observationally identical. §4C.
- **AC-4 [byte-comparable] — no `src/` file.** **MET.** `git diff --stat`:
  ```
  harness/tools/p3b_run.lua          |  83 +++++++++++++++++-
  harness/tools/p3b_show.ps1         |   8 ++
  harness/tools/print_first_cycle.py | 172 ++++++++++++++++++++++++++++++++-----
  harness/tools/vm_stage.py          |  22 +++++
  4 files changed, 261 insertions(+), 24 deletions(-)
  ```
  plus one new untracked tool. **Nothing under `src/`.**
- **AC-5 [suite] — discharged by §2T citation.** **MET.** Cited from P6.29c §5: `pic` 45/45 · `res`
  1,264/1,264 · `cel` 9,193/9,193 · `comp` 124/124 · `p3b` · `p3b_text`, all green at `289b72e` in
  155.1 s. Nothing under `src/` was touched, and `p3b`/`p3b_text`/`p3b_notick` rebuild to their
  recorded hashes (§3), so no producer moved. Not re-run.
- **AC-6 [negative result].** ★★ **Partially.** The census was **not** empty, so this is not the
  clean negative AC-6 anticipated. What replaces it is a sharper negative one layer down: the
  candidates are reachable, and the box still is not. §7.1 states what it would take instead.
- **AC-7 [tooling]. MET.**
  ```
  [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
  [reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).   [unchanged]
  indexing check: OK -- 183 commands and 20 tests agree with dispatch.py, index == opcode
  commands wired: 179 of 183   tests wired: 15 of 20
  CHECK OK: src/harness/vm_tables.s matches optable.py.
  ```
- **AC-8 — candidates captured.** §10.

### 4A — The static census

Per title: LOGIC resources scanned, how many contain `$65`/`$66`, how many have one on the **entry
path** (not behind a `said()`), how many are **blocked by an unimplemented opcode first**, how many
are **message-only logics with no PICTURE**, and the surviving candidates.

| title | LOGICs | contain print | entry-path | blocked | no PICTURE | **candidates** |
|---|---|---|---|---|---|---|
| Kingquest1 | 90 | 88 | 71 | 0 | 5 | **65** |
| Kingquest2 | 133 | 84 | 48 | 0 | 15 | **32** |
| Kingquest3 | 125 | 106 | 71 | **2** (opcode 115) | 16 | **52** |
| SpaceQuest-1 | 101 | 84 | 55 | 0 | 15 | **39** |
| SpaceQuest-2 | 118 | 81 | 60 | 0 | 16 | **43** |
| PoliceQuest1 | 118 | 95 | 66 | 0 | 24 | **41** |
| larry1 | 46 | 41 | 37 | 0 | 5 | **31** |
| BlackCauldron | 85 | 79 | 78 | 0 | 12 | **65** |
| MixedUpMotherGoose | 73 | **1** | 1 | 0 | 0 | **0** |
| | | | | | | **368** |

Ranking is by earliest entry-path print. The head of the cross-title list: Kingquest2 98 `$0000`,
larry1 19 `$0006`, PoliceQuest1 80 and 92 `$0009`, larry1 2/3/4 `$000C`, BlackCauldron 63 `$001A`,
SpaceQuest-2 6 `$001C`, SpaceQuest-1 77 `$0029`, Kingquest3 43 `$002A`.

**4A.1 ★★★★★ The PICTURE column was not in the dispatch and the census is wrong without it.**
PoliceQuest1 room 97 looked like the ideal trigger: `print.v(v131); return()`, unconditional, no
quit, **112 print executions from cycle 8, identical on both runs.** On the port it gave
`res_err 1` = `RES_E_EMPTY` — the DIR slot is `FF FF FF`. **There is no PICTURE 97.** It is a
message-only logic that other logics `call`, not a room anything can be in. The offline reference
never noticed because it does not render; `p3b` does, every cycle. ★★★ **The two legs ask different
things of a room number, and only one of them draws it.**

**4A.2 ★★★★★ And the first version of that column could not fail (§2W).** It asked
`game.entry("PICTURE", nr)` and returned `e is not None` — but `entry()` returns a row for an empty
slot too; emptiness is detected in `load()`, which raises (`resource.py:92`). **The column read
`True` for all 476 candidates, including the room the probe had just rejected as empty.** Corrected
to ask `load()`, which reuses the reference's own emptiness test; 108 message-only logics then
dropped out and the count fell 476 → 368. ★★ **A column that agrees with every row is not a filter.**

**4A.3 ★★ The "blocked" column measures the wrong side, and it happens not to matter.** It uses the
**reference's** unimplemented set — 78 command opcodes. The **port** wires **179 of 183** (AC-7). So
the column is far more restrictive than the target warrants. It excluded 2 rooms of 370, so the
ranking is unaffected, but a future reader should not take it as a statement about the port.

### 4B — Dynamic confirmation

Jump at cycle 8, the same two writes `p3b_room.lua:49-51` makes: var 0 and flag 5. **Landing is
verified in both directions** [L-56]: `wrote` = var 0 and flag 5 read back as written; `dispatched`
= flag 5 **cleared** by the run's end, i.e. logic.0 consumed it. ★★★ The second is the one that
matters — a write nothing consumes is indistinguishable from a working jump until you ask.

**Every jump attempted landed and, except where the run raised, dispatched.** The jump mechanism is
not in question. What the census promised and the runs did not deliver is the print.

| title · room | runs | first print | hits | wrote | dispatched | note |
|---|---|---|---|---|---|---|
| PoliceQuest1 97 | 2 | cycle 8 | **112** | yes | yes | no PICTURE — §4A.1 |
| Kingquest2 98 | 2 | cycle 8 | 1 | yes | yes | clean |
| SpaceQuest-2 101 | 1 | cycle 8 | 1 | yes | yes | clean |
| Kingquest1 98 · BlackCauldron 98 · PoliceQuest1 98 · larry1 54 · SpaceQuest-1 98 | 1 each | cycle 8 | 1 | yes | yes | no PICTURE |
| Kingquest1 100/102/66/43/4/8 · BlackCauldron 26/32/48/63/70/100 · PoliceQuest1 109/80/92 · Kingquest2 50/70/159 · larry1 20/58 · Kingquest3 65/103/116 · SpaceQuest-2 110/100 | 1 each | **NEVER** | 0 | yes | yes | census over-approximated |
| larry1 2/3/4/6/19 · PoliceQuest1 3/72/106 · SpaceQuest-1 14/77/100 · Kingquest2 68/78 · SpaceQuest-2 6/95 · Kingquest3 35/67/87 · BlackCauldron 103/104 | 1 each | cycle 8-101 | 1 | yes | varies | **reference raises** — §7.2 |
| Kingquest3 43 | 1 | NEVER | 0 | yes | no | reference: recursion depth exceeded |

★★★★ **The census over-approximates exactly as its header said it would**, and now there is a number
on it: of the picture-bearing rooms tried, **none printed on a cold jump**. Their entry prints sit
behind `isset(<flag>)` / `lessn(<var>)` guards that do not hold when a room is entered cold. **The
only rooms that print on a cold jump are AGI's error room** — `print.v(v17); quit(1); return()` —
which is exactly the room a game sends itself to when something has already gone wrong.

**4B.1 The oracle takes the BLOCKING branch, so the port should too.** `VM_FLAG_OUTPUT_MODE` is flag
15 (`agi.h:297`), confirmed against our table. Instrumented at the **first** print — it has to be
read there, because the handler consumes it — it is **clear** for Kingquest2 98 and SpaceQuest-2
101. So `text.cpp:373` falls through to the blocking window. The non-blocking branch is not the
explanation for what follows.

### 4C — ★★★★★ The two arms, side by side. The fault arm did not go red.

Trigger: Kingquest2, jump to room 98 at cycle 8, `P3B_VAR21=2`, `P3B_SETVAR=17=1`, 60 cycles.
Both binaries verified built and run: clean `AF0B2A02…` 15,036 B, fault `2268DAB7…` 15,033 B.

| observable | clean arm | fault arm (`-DTEXT_FAULT_NOTICK`) |
|---|---|---|
| completion | **60 cycles, no stall** | **60 cycles, no stall** |
| emulated time | 13.6843 s | **13.6843 s** |
| watchdog | did not fire | **did not fire** |
| game clock `vm_vms` | 355 | **355** |
| largest per-cycle delta | 6 ticks | **6 ticks** (armed var 21 wants ≥ 60) |
| var 21 after | **2 — unconsumed** | **2 — unconsumed** |
| `tx_wt_key` | 0 | 0 |
| jump | landed, dispatched, final room 98 | landed, dispatched, final room 98 |

★★★★★ **Identical to four decimal places.** Per §4C's own instruction this is a finding and a stop.

**4C.1 Why, as far as measurement can take it without touching `src/`.**
`vm_quit=1` proves the instruction *after* `print.v` executed, so the opcode ran. What did not happen
is the substitution. The buffer's checksum, over three different message numbers:

| `P3B_SETVAR` | printable | checksum |
|---|---|---|
| `17=1` | 26 of 26 | `$7B94` |
| `17=5` | 26 of 26 | `$7B94` |
| `17=9` | 26 of 26 | `$7B94` |

★★★★★ **Identical. Nothing is being substituted** — the buffer still holds a message the intro's
`display` left there. So `print` returns at `tx_print_common`'s `beq tx_print_out`: `tx_msgptr`
reports the message out of range, no box is drawn, and the wait loop is never entered. **With the
wait unentered the omitted `jsr vm_step_clock` is dead code, which is precisely why the two binaries
behave identically.**

**4C.2 ★★★★ The count was the wrong instrument and had been for two tasks.** "26 of 26 printable
ASCII — DECODED" read identically before and after var 17 was set, and reads identically for three
different messages. It was introduced in P6.28 to answer a decode question and it answers that
question honestly; **as evidence that `print` ran it is worthless, and it was about to be quoted
that way.** The checksum is one line and makes the buffer's identity falsifiable [§2W, L-88].

**4C.3 What was ruled out.** `res_err=6` (`RES_E_DEPTH`) looked like the culprit until the control
was run: **Kingquest2 with no jump at all reports the same `res_err=6`, the same `vm_badop=$F6`,
`vm_quit=1`, and ends in room 97 on its own.** The oracle ends in room 97 too, so that is the game's
behaviour on this corpus and not a jump artefact. ★★ Recording the exoneration because the number is
alarming and the next reader will suspect it again.

### 4D — What a gate row would need (description only, no row added)

- **Flags:** `p3b_text`'s, unchanged. **Env:** `P3B_TITLE`, `P3B_ROOM`, `P3B_ROOM_AT`, `P3B_VAR21`,
  `P3B_SETVAR`, and the staging must receive the same jump or it stages the wrong volumes.
- **Determinism evidence it would have to cite:** §4B's repeats. PoliceQuest1 97 is the only
  candidate that repeated identically at scale (112 hits, cycle 8, twice) and it has no PICTURE.
- **What it would cover:** that `print` is dispatched, that a room jump lands and is dispatched, and
  that the run survives a blocking opcode. ★★★★ **What it would NOT cover, and must say so in the
  row: the wait loop.** Until the box is drawn, a green row here is a statement about the opcode
  table and the jump, not about blocking — the same note `p3b_text` already carries.
- ★★★ **No row should be added until AC-3 passes.** A row whose fault arm cannot go red is the
  unexercised assertion §2W is about, with a gate's authority attached.

### 5 — Verdict-time evidence (v0.7 §11)
**25.1 fresh tool output:** §3's rebuild, §4A's census, §4B's runs, §4C's two arms, and AC-7's three
checks, all quoted above.
**25.2 bundled-artifact grep:** N/A — no artifact changed; `p3b`, `p3b_text` and `p3b_notick`
reassemble to their recorded hashes.
**25.3 operator-runtime-smoke:** **Not offered.** Measurement task, no `src/` change, and the path
under test does not execute. An eye gate would show the pre-existing behaviour.

### 6 — Reactive deviations and route accounting
1. **Stopped at §6's first and second triggers.** The measurement exposed a defect reachable only in
   `src/` (`print` bailing before substitution), and the fault arm will not go red. Reported, not
   repaired.
2. **Added `--set-var` / `P3B_SETVAR`**, not in the dispatch. The only cold-jump printers are the
   error room, which prints message `var17 - 1`; cold, var 17 is 0 and the index is invalid. Setting
   it is what the game does before sending itself there — the same class of poke as var 0 and flag 5.
   It did not rescue the trigger, and the negative is more informative for having been tried.
3. **`vm_stage.py` learned the jump.** A run that jumps touches volumes a no-jump run does not; the
   stager decides what to stage from its own reference run. Both legs now receive one env var.
4. ★★★ **ROUTE ACCOUNTING.** §4A, §4B and §4D are delivered in full. §4C is delivered as a **stop**:
   the two arms were run and compared, which is what it asked, and the expected red did not appear.
   **I did not build a scripted playthrough** (§6, out of scope) and **did not fix the reference's
   print defect** (§7.2) or the port's (§7.1).

### 7 — Uncertainty flags

**7.1 ★★★★★ The port's `print` does not substitute a message, and that is a `src/` defect.**
`tx_msgptr` reports out-of-range for message numbers 1, 5 and 9 against a logic with 32 messages.
The arithmetic looks right by inspection — `sta tx_msgno / beq` rejects 0, `cmpa ,x / bhi` rejects
above the count — so the suspicion falls on its **inputs**: `vm_code` + `vm_codelen` locating the
message section of the currently bound logic. **Stated as a lead, not a finding** [§8]: I did not
instrument it, because doing so means changing `src/`.

**7.2 ★★★★ The offline reference cannot print a real message either.** Every room that resolves a
valid message raises `sequence item 0: expected str instance, int found` — twenty-one rooms across
seven titles in §4B. The rooms that "succeeded" were all printing an invalid index, i.e. nothing.
★★★ **So the oracle leg of any future box gate is currently broken too**, and it is in
`tools/agivm/`, not `src/`. I did not fix it: the `vm` gate diffs against that reference, so a change
there can move a 9/9 result and does not belong inside a measurement task.

**7.3 ★★★★★ I corrupted a file with PowerShell and had to repair it.** Mid-task I patched
`print_first_cycle.py` with `Get-Content -Raw` / `[IO.File]::WriteAllText`, which double-encoded
**34 runs** of `★` — the exact failure my own standing note forbids, on a file I had just written.
Caught by checking, repaired with `harness/tools/fix_mojibake.py`, and **all eight files touched this
task now verify clean**. ★★ Recorded rather than quietly fixed: the rule existed, was written down,
and was broken anyway, which is a fact about the rule's placement and not only about the slip.

**7.4 The census's guard analysis is a nesting approximation.** `if (cond) goto +size` bodies are
treated as properly nested; an `else` is a trailing goto inside the body. That can only lengthen a
guard list, never drop a `said()`, so it over-approximates in the safe direction — and §4B shows the
over-approximation is large.

### 8 — Follow-up candidates
1. ★★★★★ **Find why `tx_msgptr` rejects a valid message number** (§7.1). This is the single thing
   standing between the wait loop and a gate, and it is a `src/` task.
2. ★★★★ **Repair the reference's print path** (§7.2), as its own task, with the `vm` gate re-run.
3. ★★★ **The message-only logics are a corpus fact worth keeping**: 108 of 476 entry-path printers
   have no PICTURE. Any future "jump to a room" work needs that filter.
4. ★★ **`p3b_show.ps1`'s allowlist filter dropped this task's new log lines again** — fourth
   instance, still open from P6.29c §8.4.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-10-a-filter-that-accepts-every-row-is-not-a-filter.md`
- `seeds/AGI/live/2026-09-10-two-legs-of-a-gate-ask-different-things-of-the-same-identifier.md`

### 11 — Commit
`<filled at commit>`  (pushed to origin/wip before this report)
