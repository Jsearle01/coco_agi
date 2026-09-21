## Form B Report — P6.71 — `VAR_KEY` is published; the title screen advances
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-20 (HEAD 42a26c7, wip). git status clean at t0 (one untracked `coco_agi.code-workspace`,
not this project's and not staged).

### 1 — Summary

★★★★★ **The title screen advances, and Jay saw it: "1. yes."** The fix is **four instructions** in
`p3_poll_dir`'s existing "a key, but not a direction key" branch.

★★★★★ **That `rts` was the oracle's `return true` from `handleController`, thrown away.**
`cycle.cpp:347-349`: *if the key was NOT consumed as a controller or direction, `setVar(VM_VAR_KEY,
key & 0xFF)` — regardless of the prompt — and hand it to the editor ONLY if the prompt is enabled.*
The routine already computed exactly that predicate and discarded the answer.

★★★★ **Measured, with a real key through the matrix, prompt disabled:**

| | fix | `-NoVarKey` (fault arm) |
|---|---|---|
| `VAR 19 publishes` | **1 key, last `$0D`** | 0 |
| final room | ★★★★★ **1** | **83** — never advances |
| sprites | **4** | **0** |
| text area, non-black | **266** | **715** |

★★★★★ **AND THE EYE GATE FOUND A DEFECT MY MEASUREMENT HAD HIDDEN.** Jay: *"2. no the press a key
to continue stays on the title screen and tranfers to the castle screen."* ★★★★★ **`vmop_clear_lines`
is `rts` — a stub** [vm_text_ops.s:541]. The script issues `clear.lines` exactly once, at the
advance; nothing happens; and because the text area lies outside the picture `show.pic` replaces,
the line survives the room change.

### 2 — Files modified
- `src/harness/p3b_probe.s` — the VAR 19 publish in `p3_poll_dir`; `p3_varkey`/`p3_nvarkey`; the
  stale note at the old `p3_poll_key` site corrected and dated (§9).
- `src/harness/vm_text_ops.s` — **comment only** (the `clear.lines` stub is now known-visible);
  all eight arms byte-identical after it.
- `harness/tools/p3b_show.ps1` — `-NoVarKey`, the want-line entry, the console allowlist.
- `harness/tools/p3b_run.lua` — the VAR 19 readout and `P3B_KEY_AT` matrix key post.
- `harness/tools/p3b_arms_check.ps1` — two arms re-baselined.

### 3 — Reasoning

**§3(3) — where the publish may land, and it is favourable.** `vm_cycle.s:144` is the one-time
init [cycle.cpp:449, *"before the main loop"*]; `vm_cycle.s:347` is **`vm_post_cycle`**, *"the four
resets run() does after each interpreted cycle"* [cycle.cpp:574-577]. ★★★★ **So VAR 19 is cleared
AFTER the cycle, and a publish before `p3_run_vm` survives into that cycle's tests** — which is the
oracle's own ordering.

**★★★★★ §4A's split was UNNECESSARY, and that is a correction to the dispatch.** §1.2 assumed the
publish would have to come from the prompt-gated path and that the scan would need separating from
the consume. **It does not: `p3_poll_dir` already scans every cycle, ungated by `txt_penab`**, and
it is exactly where the oracle puts the publish. ★★★ **The editor's guard was not touched at all**,
and AC-2 proves it still holds.

**★★★★★ §4D's proposed order is BACKWARDS, and the oracle's is the other way round.** The dispatch
says *"VAR 19 publish → direction keys → editor"*. `cycle.cpp` runs `handleController` **first** —
controller bindings, then direction keys [keyboard.cpp:527-535] — and publishes **only if it did
not consume**. Implemented in that order; stated in the source with the gap for `set.key` marked,
so the slot it goes into is already named.

**★★★★ The scope limit, found by reading the nesting rather than by a failed build.**
`p3_poll_dir` is inside `ifdef P3B_CEL_LINK` **and** `ifdef HAL_KEYBOARD` [p3b_probe.s:1359-1360].
★★★ **So the five `P3B_NO_CEL` arms do not publish VAR 19 and cannot fire `have.key` at all.** They
are byte-identical after this change and their six gate rows are untouched — convenient, and a real
limitation to know.

**The stale note, corrected and dated** [§9]. `p3b_probe.s`'s *"the opcodes that read it are not
wired and writing it would be a side effect with no reader"* was true when written; `vmtest_have_key`
was wired afterwards, in another file, by a task about something else. **The old text is kept
verbatim beside the correction** so the next reader sees why it was true rather than only that it
was wrong.

### 4 — Verification (AC-by-AC)

- **AC-1 [state-comparable] PASS** — `VAR 19 publishes: 1 key(s), last $0D`, on the title screen
  with `prevent.input` active. ★★★ **Read from a sticky guest copy, not from VAR 19**: `vm_post_cycle`
  clears VAR 19 every cycle, so sampling the variable at the park reports zero however many keys
  were published. **The first run of this change advanced the screen and could not show the value
  that did it** — the instrument was fixed before the number was quoted.
- **AC-2 [state-comparable] PASS** — `keys to the editor 0`, `row 22: 0 of 1280 bytes differ`, with
  the prompt disabled. **The editor never ran, so `ENTERED_CLI` cannot have been set by a keypress
  during `prevent.input`.** §1.2's guard intact.
- **AC-3 [state-comparable] PARTIAL, and the difference is stated.** P6.70's 4/3/1/2/2/2 are
  **reference OPCODE counts**; the guest has no per-opcode counter, so what is reported here are
  **observable proxies**: `new.room` → final room 83→**1**; `draw`/`set.view` → sprites 0→**4**;
  `clear.lines` → text area 715→**266**. ★★★★ **The last proxy is where I over-read the data** —
  see §7.1.
- **AC-4 [state-comparable] PASS** — `p3b_row22` green (typing still reaches the editor) and `p3b`
  green (the cel arm, Graham's path). Both existing consumers unbroken.
- **AC-5 [byte-comparable] PASS** — **pic 45/45 · res 1,264/1,264 · cel 9,193/9,193 · comp 124/124**,
  fresh. ★★ **The nine-title `vm` gate was NOT re-run** — see §7.3.
- **AC-6 [suite] PASS** — `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` all green.
- **AC-7 [fault injection] PASS** — `-NoVarKey` removes the publish and nothing else (−13 B):
  **room stays 83, sprites 0, text area 715.** ★★★★ **Those are exactly the three symptoms Jay
  reported across P6.66-P6.69**, which makes this a known-good red in his own words.
- **AC-8 [eye gate — Jay]** ★★★★★ **Q1 PASS: "yes", the screen advances.** ★★★★★ **Q2 FAIL against
  my stated expectation: "no the press a key to continue stays on the title screen and tranfers to
  the castle screen."** Q3 (alligators) **not checked**. Q4/Q5 not reached.
- **AC-9 [manifest] PASS** — two arms re-baselined (`p3b` 15475/475064B0, `p3b_comb` 18611/7467F2BD,
  **+15 B each**); the five text arms byte-identical; 8/8 OK after.
- **AC-10 [tooling] PASS** — `hal_sync_check.py` OK against both siblings (11 files);
  `reg_discipline.py` 17 accesses, 1 file, 4 registers (unchanged, `src/engine/` untouched);
  `gen_vm_tables.py --check` OK; `p3b_arms_check.ps1` 8/8; `fix_mojibake --check` clean.
- **AC-11** Candidate captured (§10).

### 5 — Verdict-time evidence (v0.7 §11)

```
25.1  VAR 19 publishes: 1 key(s), last $0D
      final room 1, sprites 4, err 0, status=$00
      text area rows 168-199: 266 of 5120 bytes non-black
      row 22: 0 of 1280 bytes differ from $00 (prompt enabled=1, keys to the editor 0)
      -NoVarKey: final room 83, sprites 0, text area 715 of 5120 non-black

      per-picture: 45 PASS, 0 FAIL (of 45)
      resources byte-identical to tools/volread/: 1264 / 1264 (100.00%)
      cels byte-identical to the oracle: 9193 / 9193 (100.00%)
      ★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
      ★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22 -- all green
      ★ all 8 arms byte-identical to the recorded baseline (SHA256)
      [hal-sync] OK -- aligned with POP3_port, karateka_coco3 (11 files compared)
      [reg-discipline] 17 access(es) in 1 file(s) over 4 register(s)
      CHECK OK: src/harness/vm_tables.s matches optable.py
25.2  N/A -- probe and harness code only.
25.3  PASSED (Q1) / FAILED (Q2) -- Jay, live-disk, RGB, combined arm, -NoRoomJump, 180 cycles.
      "1. yes. 2. no the press a key to continue stays on the title screen and tranfers to
       the castle screen, 3.no, didn't check"
```

### 6 — Reactive deviations and route accounting

1. ★★★ **`p3_varkey`/`p3_nvarkey` were added after the first run**, because the run proved the
   screen advanced and could not show what advanced it. **Two bytes of diagnostic, +15 B total.**
2. ★★★ **`P3B_KEY_AT` posts a key through the matrix** and keys on VAR 19, because the existing
   typing loop keys on `P3_NKEY` — a counter incremented inside the prompt-gated `p3_poll_key`,
   which never runs on the title screen.
3. ★★ **A comment added at `vmop_clear_lines`** recording that the stub is now known-visible.
   Comment only; all eight arms byte-identical after it.

**ROUTE ACCOUNTING.** I said §4A's split would be needed and **it was not** — I implemented the
publish on the existing ungated scan instead, and said so above rather than letting the diff imply
a split happened. ★★★★ **I did NOT implement `clear.lines`**, although it is now the one visible
defect left on this path: it is a text-engine opcode landing in six gate rows, and slipping it into
a task about VAR 19 is the reshaping §8 forbids.

### 7 — Uncertainty flags

1. ★★★★★ **I over-read my own number and told Jay the wrong expectation.** The text area went
   **715 → 266** non-black bytes and I reported that as the text being cleared. **266 is not zero.**
   A number that moved in the right direction is not evidence that it reached the right value, and
   the eye gate caught what the byte count did not [§4A.1's pattern, from the other side].
2. ★★★★ **`clear.lines` is a stub and is the remaining visible defect** on this path. Named at the
   stub, with Jay's words, and §8.1.
3. ★★★ **The nine-title `vm` gate was not re-run.** The code change is confined to `p3b_probe.s`
   inside `ifdef P3B_CEL_LINK`, which `vm_probe` does not build, and the only edit to a file
   `vm_probe` links (`vm_text_ops.s`) is a comment — **so `vm_probe.bin` cannot have moved.**
   ★★ **That is a structural argument, not a measurement**, and it is recorded as such.
4. ★★★ **The alligators are unverified.** Sprites went 0 → 4, which says objects are staged, not
   that they are drawn correctly or animate. Jay did not check.
5. ★★ **Only ENTER (`$0D`) was exercised.** `have.key` is true for any non-zero VAR 19, so which
   keys a game accepts is untested — and direction keys are consumed before the publish by design.

### 8 — Follow-up candidates

1. ★★★★★ **Implement `clear.lines`** — the one thing standing between this path and Jay's Q2. Needs
   the oracle's row range and `txt_boxfill`; lands in the six `P3B_NO_CEL` gate rows.
2. ★★★★ **Check the alligators** (§7.4) — sprites are staged; whether they draw and cycle is
   unverified, and `start.cycling` is still unimplemented.
3. ★★★ **`set.key` and the controller raise**, with a ruling on the 16-bit gap [P6.70]: ASCII
   bindings are reachable today, F-keys and Alt-keys need a CoCo→PC scancode mapping that does not
   exist. **The slot in `p3_poll_dir` is already marked.**
4. ★★★ **The five text-only arms cannot publish VAR 19** (§3). Decide whether that matters or
   whether the cel-linked arms are the shipping shape.
5. ★★ **Pin the game release in the comparison procedure** — carried from P6.69/P6.70, still not
   done.
6. ★ Carried: the flags' blink · the picture leaving the logic arena · `configure.screen`'s render
   offset · `MAP_PRI_BANDS` (seventeenth task).

### 9 — Doc-edit deltas applied
- `p3b_probe.s` — the stale VAR 19 note **corrected and dated, old text kept verbatim**.
- `p3b_probe.s` — the publish site carries the oracle's citation, the three-consumer order, and the
  named gap where `set.key` will go.
- `vm_text_ops.s` — the `clear.lines` stub is now recorded as known-visible, with Jay's words.
- `p3b_arms_check.ps1` — why only two arms moved.
- **Design-spec text: none proposed** [§2D].

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-20-a-number-that-moved-the-right-way-is-not-a-number-that-arrived.md`

### 11 — Commit
`d1972b7` — 6 files changed, 333 insertions(+), 7 deletions(-).
Pushed to origin/wip (`42a26c7..d1972b7`).
