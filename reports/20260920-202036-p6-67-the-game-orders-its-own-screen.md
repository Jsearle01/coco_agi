## Form B Report — P6.67 — The game orders its own screen: draw.pic, show.pic, configure.screen
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-20 (HEAD 2bde0c6, wip). git status clean at t0.

### 1 — Summary

★★★★★ **The three opcodes by which an AGI game orders its own screen are real, and the defect Jay
reported is fixed.** `draw.pic` ($19), `show.pic` ($1A) and `configure.screen` ($6F) were
`vm_op_modelled`; the picture was rendered by `p3_room_check`, a **port-side room-change detector**.
**Nothing in the binary could place the copyright between the render and the reveal**, which is
where the game puts it — so the text appeared and the picture arrived ~2.8 s later.

★★★★★ **Jay's eye gate, five questions, all five as predicted:** *"1. together, 2. yes, 3. yes,
4. yes, 5. no."* **Q1 is the fix** — picture and copyright now arrive together. Q2/Q3 are
non-regressions (picture unchanged, copyright readable, text area black). **Q4 and Q5 were
predicted NOT to change and did not**: `closeWindow()` is declared unported, and the credit scroll
is a different path, measured here and out of scope.

★★★★★ **AND THE OWNERSHIP MOVE HIT A REAL WALL, WHICH IS THIS TASK'S FINDING.** `draw.pic` runs
INSIDE a running logic, and `res_open` may evict the logic cache **only at depth 0** — above it the
cached bytes may be the bytes currently executing [res_core.s:309-314]. The retired detector ran
from the main loop at depth 0 and had that privilege ambiently. **Measured at the refusal: picture
1, `res_top=$6000`, cache floor `$643C`, depth 2 — 1,084 bytes free, the cache holding 14,788 of
16,384.** ★★★★ Evicting anyway is the approach that **halted all nine titles at cycle 0**, so §6
forbids it; a refused fetch is **deferred to depth 0**, counted, and reported as reverting that
room to the pre-task ordering.

### 2 — Files modified
- `src/harness/vm_pic_ops.s` — NEW. The three handlers, wired/modelled exactly as `vm_text_ops.s`.
- `src/harness/p3b_probe.s` — `p3_room_check` demoted to a diagnostic; `p3_pic_draw`/`p3_pic_show`/
  `p3_pic_pending` added; `p3_enter_vm_phase` factored (§2F); `PIC_WIRED`; state bytes.
- `src/harness/vm_tables.s` — REGENERATED (three entries; never hand-edited).
- `harness/tools/pic_order.py` — NEW. §4C/§4E's instrument.
- `harness/tools/p3b_show.ps1` — `-NoShowPic`, `-RoomDrive`, want-line, console allowlist.
- `harness/tools/p3b_run.lua` — the picture receipt, the arena readout, the deferral count.
- `harness/tools/p3b_arms_check.ps1` — re-baselined (+194 B, all eight); stale "7 arms" corrected.

### 3 — Reasoning

**§4A — the oracle, all four questions answered [tier: ScummVM, pin 9d9b9e93].**

1. **Who renders and who reveals.** `cmdDrawPic` = `eraseSprites` / `decodePicture` /
   `buildAllSpriteLists` / `drawAllSpriteLists` / `pictureShown = false` [op_cmd.cpp:1178-1210].
   `cmdShowPic` = `setFlag(VM_FLAG_OUTPUT_MODE,false)` / `closeWindow()` /
   `showPictureWithTransition()` / `pictureShown = true` [1212-1218]. `cmdLoadPic` loads only
   [1223]. ★★★★★ **`draw.pic` renders into `_gameScreen`; `show.pic` reveals into `_displayScreen`
   via `render_Block`** [picture.cpp:834-864]. **Believed ORIGINAL** (§2.1): it is the structure the
   opcode set requires, not a ScummVM normalisation.
2. **Flag 15.** `VM_FLAG_OUTPUT_MODE` [agi.h:297] has exactly two engine sites: this clear and
   `TextMgr::messageBox`, which consumes it for one non-blocking window [text.cpp:373-375].
   ★★★ **Nothing in the engine SETS it — the game does.**
3. **configure.screen.** `configureScreen(gameRow)` sets `_window_Row_Min/_Max` and forwards
   `gameRow*8` as a render start offset [text.cpp:92-98]; the constructor default is
   **`configureScreen(2)`** [text.cpp:74], not 0.
4. **Is the loaded picture retained until draw.pic?** Yes — `load.pic` loads and does not draw.

**§2H's three checks, on the reference.** (1) *A second mechanism for a different object class?*
Yes — `overlay.pic` and `add.to.pic` write the same planes and are **not** implemented here;
declared, not assumed absent. (2) *Name the CALLER.* `showPictureWithTransition` is called only by
`cmdShowPic`, and its transition branches are platform-gated — the PC branch is a plain
`render_Block`, which is what makes our `p3_present` a faithful analogue rather than a shortcut.
(3) *Grep the reports for the same subsystem.* `p3_room_check`'s five responsibilities were
described across P6.49/P6.58/P6.66; no contradiction found.

**§1.2 — the ownership ruling, reported before implementation** (in-session, before any handler was
written). The game drives; `p3_room_check` keeps **one** of five responsibilities:

| # | was | now | authority |
|---|---|---|---|
| 1 | detect room change, publish `P3_ROOM` | **KEPT, demoted to diagnostic** | — |
| 2 | fetch the PICTURE | **draw.pic** (folded, §2I) | op_cmd.cpp:1223 |
| 3 | clear + render into the shadow | **draw.pic** | op_cmd.cpp:1178 |
| 4 | present shadow → visible | **show.pic** | op_cmd.cpp:1212 |
| 5 | priority shadow | **draw.pic's tail** | §2H check 2 — before `drawAllSpriteLists` |

★★★★★ **The split needed no new mechanism: our shadow IS `_gameScreen` and our visible plane IS
`_displayScreen`.** `p3_room_check` was already doing both halves, in one call, at the wrong time.

**§4C — the ordering, MEASURED before it was believed** [`pic_order.py`, KQ1 cycle 1, logic 83]:

```
new.room 83 | load.pic v0=83 | configure.screen 0 21 0 | draw.pic v0=83
prevent.input | display 22 1 24 | display 24 5 25 | show.pic
```

★★★★ **The two `display`s land at rows 22 and 24 — BELOW the 21-row picture — so `show.pic` never
covers them.** That is why the game can draw text before revealing the picture.

**§4D — the extra line.** `configure.screen(gameRow=0, promptRow=21, statusRow=0)`. The oracle's
**default is gameRow 2** (picture 16 px down, rows 2-22 of 25); **the title screen asks for 0**,
which is the offset we already present at. ★★ **The three values are STORED; the render offset is
NOT yet consumed** — see §6.

**§4E — the scroll census.** The game scrolls itself: `display.v` is `"vvv"`, so `24 25 20` are
**variable numbers**, and the game redraws the whole visible list one row higher every 5 cycles —
msg1@18, then msg2@18/msg1@17, … msg6@18…msg1@13, column 12 throughout. ★★★★ **Rows 13-18 are
INSIDE the picture area**, a different path from the bottom strip where the copyright draws.
**Hypothesis, not a finding, and not fixed here.**

**§2S — sibling refs.** POP and Karateka untouched; `hal_sync_check.py` compared 11 files and
reports OK against both at their current `wip` HEADs. `src/hal/` and `memmap.inc` untouched.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: eye-gated]** The game orders its own screen, visibly — **Jay, live-disk, RGB,
  combined arm, 99.99% speed: "1. together"**. Ran FIRST per §4A, before these byte gates were
  reported.
- **AC-2 [class: eye-gated]** No regression in picture, text or background — **Jay: "2. yes,
  3. yes"**.
- **AC-3 [class: state-comparable]** The ordering matches the oracle's — `pic_order.py` above;
  our handlers execute in the order the reference issues them.
- **AC-4 [class: byte-comparable]** Renderer unaffected — **pic 45/45, both planes, every
  per-picture hash identical**.
- **AC-5 [class: byte-comparable]** Resources and cels unaffected — **res 1,264/1,264 (100.00%)**,
  **cel 9,193/9,193 (100.00%)**, **comp 124/124 both planes**.
- **AC-6 [class: suite]** Health gates — **p3b, p3b_text, p3b_box, p3b_parse, p3b_row22 all green,
  no stall, err 0**.
- **AC-7 [class: byte-comparable]** Arms re-baselined — **all eight moved by exactly +194 B**, a
  uniformity that is the evidence it is one change; re-verified OK after re-baselining.
- **AC-8 [class: state-comparable]** The nine-title `vm` gate — ★★★★ **`vm_probe`'s binary is
  UNCHANGED**: the three `equ`s to `vm_op_modelled` emit zero bytes. **Stated as a COVERAGE fact,
  not a correctness one** — the gate stays green because it does not contain this code, and citing
  it as evidence the handlers are right would be the §2W error.
- **AC-9 [class: eye-gated + byte-comparable]** Fault arm — **`-NoShowPic` goes red**:
  `drew=1 shown=0`, *"RENDERED, NEVER REVEALED"*, −9 B. ★★★ It proves §1.2's ruling: if the picture
  still appeared, something other than `show.pic` would be presenting it.
- **AC-10 [class: byte-comparable]** Comparison arm — **`-RoomDrive`** restores the retired driver
  AND models the opcodes (−28 B), so it is the pre-task binary shape rather than a double render.

### 5 — Verdict-time evidence (v0.7 §11)

```
25.1  pic   45 PASS, 0 FAIL, 0 with no output (of 45)
      res   1264 / 1264 requested (100.00%)   0 mismat  0 guestfail
      cel   9193 / 9193 queued (100.00%)
      comp  124 / 124 frames (100.00%)  both planes
      ★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22 -- all green
      ★ all 8 arms byte-identical to the T-P0-121 baseline (SHA256)
      [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
      [reg-discipline] 17 register access(es) in 1 file(s) over 4 register(s)
                       src/engine/mmu_phase.s  17  $FFA3 $FFA4 $FFA5 $FFA6
      fix_mojibake --check: 7 files, all clean
      lwasm from lwtools 4.24
25.2  N/A -- no bundled artifact changed; this is probe and harness code.
25.3  PASSED -- Jay, live-disk, RGB, combined arm, normal speed.
      "1. together, 2.yes, 3.yes, 4.yes, 5.no"
```

★ **§2N note:** `src/engine/` was NOT touched (all changes are `src/harness/`), so the census is
unchanged and is quoted as a non-regression rather than as a new measurement.

### 6 — Reactive deviations and route accounting

1. ★★★★★ **The deferred-render fallback is a §22.5 deviation and the largest thing in this task
   that the dispatch did not ask for.** Without it every room change after the cache fills would
   fail to render. The common case keeps the fix; the full-arena case degrades to **precisely the
   pre-task ordering**, counted in `p3_nfall` and named in the summary.
2. ★★★★ **`load.pic`'s fetch is folded into `draw.pic`** — a **declared divergence under §2I**. The
   arena is a stack (`res_close` rewinds `res_top`), so a pointer held across the two opcodes would
   dangle or leak a depth level. **Costs:** a volume fetch moves one opcode later. **Saves:** a
   dangling pointer and a depth leak. **Output identical**; the ~2.8 s render is what moved and it
   is still at `draw.pic`.
3. ★★★ **`configure.screen` stores its three values; the render offset is not consumed.**
   `p3_present` copies slice-for-slice with source offset == destination offset, and a `gameRow`
   shift breaks that alignment (dest crosses a block the source does not). That is a rewrite of
   `p3_present` with its own eye gate. **It costs nothing today** — the measured title screen asks
   for gameRow 0, which is what we already use.
4. ★★★ **`show.pic`'s `closeWindow()` is not ported** — this probe has no open-window state to
   close. Declared. It is a live candidate for the 'press a key to continue' line.

**ROUTE ACCOUNTING.** I proposed the §1.2 ruling before implementing and **implemented all five
rows of it**, including responsibility 5 going to `draw.pic` rather than `show.pic`. I also said I
would not implement past the trace if the game did not issue the opcodes; it does, so that
condition never bound. **What I did NOT implement and said so at the time:** the render offset (3),
`closeWindow()` (4), and the credit scroll (§4E) — all three measured, none fixed.

### 7 — Uncertainty flags

1. ★★★★ **The deferral is a fallback, not a solution.** The right fix is that **a picture should
   not live in the logic arena at all** — a room-lifetime resource on a call-scoped stack, §2V.2's
   residency row exactly. **That is a memory-map decision and belongs to Jay/the Orchestrator.**
2. ★★★ **How often the deferral fires in real play is unmeasured.** One firing was observed, on an
   injected room jump. The arena state that causes it (cache floor at `$643C`) is ordinary, so the
   honest expectation is "often", and that is a guess, not a measurement.
3. ★★ **§4E's scroll cause is a hypothesis.** Rows 13-18 are inside the picture area; whether our
   text path reaches them is untested.
4. ★★ **Jay's eye gate ran on a stage cached with `--room 1`**, so his run also jumped to room 1 at
   cycle 8 — the deferred path. His "together" answers the title screen, which is what Q1 asked.
   ★★★ **The staging cache carrying a previous run's room-jump configuration is L-92's shape** and
   is a real harness gotcha: a run can inherit an earlier run's configuration without saying so.

### 8 — Follow-up candidates

1. ★★★★★ **Move the picture out of the logic arena** (flag 1 above). The blocking design question.
2. ★★★★ **`p3_present` with a `gameRow` offset**, consuming `configure.screen`'s geometry.
3. ★★★ **Why the credits do not scroll** — test whether the text path reaches rows 13-18.
4. ★★★ **`closeWindow()` at `show.pic`** — the likely 'press a key to continue' mechanism.
5. ★★ **The staging cache should record its configuration** and restage when it differs.
6. ★★ **`overlay.pic` / `add.to.pic`** remain modelled (§2H check 1).
7. ★ Carried: key arbitration (4th task), `gates.manifest` row for the combined arm, seed-stack
   high-water gate, straddle clamp (11th task), `MAP_PRI_BANDS` (15th task).

### 9 — User interaction during task
Jay answered the §4A eye gate with five numbered answers: *"1. together, 2.yes, 3.yes, 4.yes,
5.no"*. No other interaction.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-20-moving-a-call-to-its-right-owner-can-strip-an-ambient-privilege.md`
- `seeds/AGI/live/2026-09-20-the-instrument-built-to-catch-a-defect-carried-that-defect.md`

### 11 — Commit
`db181fc` — 8 files changed, 841 insertions(+), 34 deletions(-).
Pushed to origin/wip (`2bde0c6..db181fc`) before this report was surfaced.
