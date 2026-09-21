## Form B Report — P6.68 — The scroll: the game draws it, and the GATE never showed it
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-20 (HEAD c95f501, wip). git status clean at t0.

### 1 — Summary

★★★★★ **The scroll was never broken. The eye gate was.** `p3b_room.lua:25` reads
`tonumber(os.getenv("P3B_ROOM") or "1")` — **the live path's default is room 1, not "no jump"** —
while the headless path defaults to 0. ★★★★★ **So the two gates have been running DIFFERENT
PROGRAMS by default.** The live run jumps rooms at **cycle 8**; the first credit line draws at
**cycle 5** and the second at **10**. **Every eye gate in this arc showed at most one line before
leaving the title screen**, which is exactly "the text doesn't scroll", reported three times.

★★★★★ **Jay, with the jump disabled: "1. yes, 2. yes, 3. yes, 4. looks correct."** The credits
scroll. Nothing in the engine was changed to achieve it.

★★★★ **Both dispatch hypotheses died by measurement, as §7 asked.** §1.2(a): `draw.pic` and
`show.pic` execute **once each in 80 cycles** against 130 `display.v` calls — no redraw loop, so
§4A's ruling is not triggered. §1.2(b): **the title screen stages ZERO sprites**, so no restore can
erase anything; the y=17 / y=100 / y=115 / y=161 coordinates are **room 1's** sprite list, offered
for a room-83 defect.

★★★ **§1.3's premise is also false and is reported as false:** `txt_close` landed, correctly, but
**cannot** be the 'press a key to continue' line — the title logic never calls `print` or `print.v`
in 90 cycles, so no window is ever open for it to close.

### 2 — Files modified
- `src/harness/vm_pic_ops.s` — `show.pic` reordered into the oracle's sequence and `txt_close`
  called; the stale "closeWindow() is NOT ported" note corrected (§9).
- `harness/tools/p3b_show.ps1` — `-NoRoomJump`, `-NoCloseWindow`, the launch banner, allowlist.
- `harness/tools/p3b_run.lua` — the scroll-band census and the per-cycle credit-row trace.
- `harness/tools/p3b_arms_check.ps1` — re-baselined; the task-stamped message de-stamped.

### 3 — Reasoning

**§3(2) FIRST, as §7 required, and it nearly ended the task.** `pic_order.py` over 80 cycles:
`load.pic` 1, `draw.pic` 1, `show.pic` 1, `display.v` 130, all picture opcodes at cycle 1. ★★★★
**No recurrence, so the scroll is not a picture-redraw loop.** The oracle's per-step cost question
[§4A] is therefore moot: the game issues no picture opcode per scroll step, and neither do we.

**§3(3) — the overlap arithmetic, reported although negative** [§7's instruction]. Room 83 stages
**`sprites 0`**. There is no rectangle, so the overlap is empty for every candidate; the lead
cannot apply at any coordinate. ★★★ **A measured zero kills it permanently where an argument
would only postpone it.**

**§3(4) — `txt_blit`'s bound is NOT the refusal.** `tx_window_enter` sets `txt_fbrow0 = 0` and
`txt_fbrows = TX_WIN_ROWS = 25` [vm_text_ops.s:79-111], so rows 0-24 are all drawable and rows
6-18 are accepted. ★★ And `vmop_display_f` resolves all three operands through `vm_v0/v1/v2`
[vm_text_ops.s:287-292], so the `"vvv"` signature is honoured. **Neither end of the write path
refuses the credits.**

**§4C — the census, and it had to be visible-vs-shadow.** Rows 6-18 are inside the picture, so a
non-black count is meaningless there. The shadow holds the picture as `pic_render_at` drew it and
is never written again after cycle 1 (measured above), so **every byte where visible differs from
shadow was drawn on top**. Per-cycle, within ONE run:

```
cycle  5: {18}                 cycle 30: {13,14,15,17,18}
cycle 10: {17,18}              cycle 35: {12,13,14,16,17,18}
cycle 15: {16,17,18}           cycle 40: {11,12,13,15,16,17,18}
cycle 20: {15,16,17}           cycle 45: {10,11,12,14,15,16,17}
cycle 25: {14,15,16,18}
```

★★★★ **The top row decreases by exactly one every five cycles — the measured cadence — in the
plane the display shows.** The same three messages are identifiable by byte count (148/130/211 at
columns 12/16/12) and move from rows 15/16/17 at cycle 20 to 7/8/9 at cycle 60.

**§4A's attribution.** The glyphs are written, they move, and the display shows that plane. The
loss was entirely in which program the operator was shown. ★★★★★ **`p3b_show.ps1:446` says it:**
*"THE HEADLESS INTEGRATION RUN. p3b_run.lua directly — no display script, **so no room jump**"* —
and `p3b_room.lua:59-61` hands its default of 1 to `p3b_run.lua`, *"whose own default is 0, meaning
no jump"*. **Both halves were documented and I read past them.**

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement]** ★★★★★ **The picture does NOT recur.** 1 `draw.pic`, 1 `show.pic`,
  1 `load.pic` in 80 cycles, all at cycle 1.
- **AC-2 [measurement]** ★★★★ **Negative, reported as numbers: `sprites 0` on the title screen.**
  The cited coordinates belong to room 1.
- **AC-3 [attribution]** ★★★★★ **The eye gate and the headless gate default to different room
  behaviour**; the live path cut the title sequence at cycle 8. Named, and fixed by `-NoRoomJump`.
- **AC-4 [state-comparable]** The per-cycle census above.
- **AC-5 [state-comparable]** ★★★ **`txt_close` IS called from `show.pic`, and the 'press a key'
  line is NOT gone — the dispatch's expectation was wrong and is reported as wrong.** No `print`
  or `print.v` executes in 90 cycles, so `txt_winactive` is 0 and `txt_close` falls through. The
  call lands anyway because `cmdShowPic` makes it [op_cmd.cpp:1216].
- **AC-6 [state-comparable]** Flag 15 cleared by `show.pic`, now in the oracle's order —
  `setFlag`, `closeWindow`, reveal [op_cmd.cpp:1215-1218]. P6.67 revealed first.
- **AC-7 [byte-comparable]** **pic 45/45 · res 1,264/1,264 · cel 9,193/9,193 · comp 124/124**,
  fresh.
- **AC-8 [suite]** `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green, no stall, err 0.
- **AC-9 [fault injection]** **`-NoCloseWindow`** — removes the single `jsr txt_close`, −9 B; it is
  every build before this task.
- **AC-10 [eye gate — Jay]** ★★★★★ **PASSED, live-disk, RGB, combined arm, 99.99%, 110 cycles,
  no room jump: "1. yes, 2.yes, 3.yes, 4.looks correct. still need the jump to the castle room."**
  Offered before the byte gates were reported.
- **AC-11 [manifest]** Arms re-baselined — **+9 B in the five `TEXT_WIRED` arms** (the `txt_close`
  call) and **same size / different bytes in the three without** (the `show.pic` reorder). ★★★ The
  second group is the case `p3b_arms_check.ps1`'s own comment predicted a hash baseline exists to
  catch; second instance in that file.
- **AC-12 [tooling]** `hal_sync_check.py` OK against both siblings (11 files) · `reg_discipline.py`
  17 accesses, 1 file, 4 registers (unchanged; `src/engine/` untouched) · `gen_vm_tables.py
  --check` OK · `p3b_arms_check.ps1` 8/8 OK · `fix_mojibake.py --check` clean.
- **AC-13** Candidates captured (§10).

### 5 — Verdict-time evidence (v0.7 §11)

```
25.1  per-picture: 45 PASS, 0 FAIL, 0 with no output (of 45)
      resources byte-identical to tools/volread/: 1264 / 1264 (100.00%)
      cels byte-identical to the oracle: 9193 / 9193 (100.00%)
      ★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
      ★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22 -- all green
      ★ all 8 arms byte-identical to the recorded baseline (SHA256)
      [hal-sync] OK -- aligned with POP3_port, karateka_coco3 (11 files compared)
      [reg-discipline] 17 access(es) in 1 file(s) over 4 register(s)  src/engine/mmu_phase.s
      CHECK OK: src/harness/vm_tables.s matches optable.py
      fix_mojibake --check: clean
25.2  N/A -- probe and harness code only.
25.3  PASSED -- Jay, live-disk, RGB, combined arm, 110 cycles, -NoRoomJump.
      "1. yes, 2.yes, 3.yes, 4.looks correct. still need the jump to the castle room"
```

### 6 — Reactive deviations and route accounting

1. ★★★★ **`-NoRoomJump` and the launch banner are §22.5 additions the dispatch did not ask for.**
   Without them there is no way to show a human the title screen past cycle 8, which is the whole
   subject of the task.
2. ★★★ **The per-cycle credit-row trace (`P3B_SCROLL_TRACE`) was added AFTER Jay's first "no"**,
   because the end-of-run census and the two-run comparison could not distinguish "drawn once" from
   "moving". **Two runs are not motion**, and the dispatch's §4C asked for the per-cycle form.

**ROUTE ACCOUNTING.** I said I would test §4A first and stop if it answered; it did not answer, so
I continued to §4B, then §4C, in that order. **What I did NOT do:** change any engine behaviour to
make the scroll work — nothing needed changing — and I did not consume `configure.screen`'s render
offset or touch the deferred-render fallback [both out of scope].

### 7 — Uncertainty flags

1. ★★★★ **Four errors of mine, three in one guard.** (a) I attributed P6.67's room jump to a
   **stale cached stage**; it is a **default in the eye gate's script**, and clearing `P3B_ROOM`
   never did anything. (b) My first banner sat **inside `if ($Headless)`** — invisible to eye
   gates, the only runs it protects; **P6.3's "guard that cannot fire"**, and it passed my test
   because I tested it headless. (c) Corrected, it then **keyed on `P3B_ROOM` being SET**, so it
   printed *"title sequence intact"* for precisely the runs that cut it. (d) ★★★★★ **I measured
   the scroll nine ways on the headless path and concluded the engine was fine, while Jay watches
   the live path.** Both are now fixed and the banner is shown firing in both directions.
2. ★★★ **'Press a key to continue' is unexplained.** It is one of the two `display` messages the
   game issues (message 24 at row 22, message 25 at row 24). Why the oracle does not show it is
   **not established** — §2P forbids quoting the text, so the next step is comparing the oracle's
   rendered rows, not its strings.
3. ★★ **`RESTORE COPIED NOTHING`** prints on the title screen because there are no sprites. It
   reads as a fault and is not one; a diagnostic that cannot distinguish "nothing to do" from
   "broken" is §2W.3's shape and should be conditioned on the sprite count.

### 8 — Follow-up candidates

1. ★★★★★ **Jay's request: the gate should run the title sequence AND THEN jump to the castle.**
   Demonstrated this task with `P3B_ROOM_AT=120`; the **default of 8 should move** so the standard
   eye gate shows both.
2. ★★★★ **`p3b_room.lua`'s default of 1 should be reconsidered**, or at minimum every gate should
   print the room configuration it will use. The banner does this now for `p3b_show.ps1` only.
3. ★★★ **The 'press a key' line** (flag 2 above).
4. ★★ **Condition `RESTORE COPIED NOTHING` on `p3_nspr > 0`** (flag 3).
5. ★ Carried: key arbitration (5th task) · `gates.manifest` row for the combined arm · seed-stack
   high-water gate · straddle clamp (12th) · `MAP_PRI_BANDS` (16th) · the picture leaving the logic
   arena [P6.67 §7.1] · `configure.screen`'s render offset.

### 9 — Doc-edit deltas applied
- `vm_pic_ops.s` — the "closeWindow() is NOT ported" note **corrected in place, not deleted**,
  because P6.67's report cites it and a reader arriving from there must find it superseded.
- `p3b_arms_check.ps1` — the baseline message de-stamped ("P6.47" had survived three re-baselines).
- **Design-spec text: none proposed this task** [§2D].

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-20-two-gates-believed-identical-differed-by-one-default.md`
- `seeds/AGI/live/2026-09-20-a-guard-tested-only-where-it-works.md`

### 11 — Commit
(recorded below; pushed to origin/wip before this report was surfaced)
