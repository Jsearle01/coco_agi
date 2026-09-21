## Form B Report — P6.69 — Three observations at the oracle: two are one defect
**Class:** recon.  wip.  (No dispatch — Jay's side-by-side against stock ScummVM.)

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-20 (HEAD fb44b2a, wip). git status clean (one untracked `coco_agi.code-workspace`,
not this project's file and not staged).

### 1 — Summary

Jay ran KQ1 on stock ScummVM beside the port and reported three differences. ★★★★★ **Two of them
are the same defect, and it is not the one either of us would have guessed: the port's TITLE SCREEN
NEVER ADVANCES.** The third is known and staged.

★★★★★ **Measured over 500 cycles of the offline reference: the credits stop at cycle 115 and the
title logic emits NOTHING from cycle 116 to 500.** `display.v` totals 221 at 150 cycles and 221 at
500. **The sequence finishes its roll and waits.**

### 2 — Files modified
None. This task changed no code. (This report only.)

### 3 — Reasoning

**Observation 1 — "'press a key to continue' does not disappear with the copyright, like the
oracle."**

★★★★ **No `clear.lines` is issued in 500 cycles.** Nothing in the title script erases that text.
★★★ **So the line is not drawn wrongly and is not failing to be cleared by a missing opcode** — in
the oracle the text disappeared because **the screen was replaced**, and Jay was pressing keys.
**On the port the title sits in its wait loop and the text stays because the screen never changes.**

★★★★★ **This closes P6.68 §7.2, which recorded the line as unexplained.** It also retires the
P6.68 §4D hypothesis completely: `closeWindow()` was never the mechanism, and neither is any text
opcode. **The mechanism is the room not advancing.**

**Observation 2 — "the oracle has alligators swimming in the moat; the port does not."**

★★★★★ **The title screen loads FOUR VIEWS and draws NONE.** Over 500 cycles:

```
load.view 4    animate.obj 1    set.key 21    prevent.input 1
draw 0   set.view 0   start.cycling 0   add.to.pic 0   overlay.pic 0   clear.lines 0
```

★★★★ **Four views are loaded and `draw` is never called**, so no object is ever placed on screen.
That is why `p3_stage_sprites` reports `sprites 0` on the title screen — **it is staging faithfully
from an object table into which nothing has been drawn.**

★★★ **The port's renderer is not implicated.** It is not being asked to draw them. The loaded views
are the alligators being made ready for a sequence that has not started.

**Observation 3 — "the flags still flash (blink) while animating."**

★★ **Known, unchanged, and staged.** It needs the page flip, which is blocked behind a `src/hal/`
task. Nothing in this arc touched it. Recorded here so the side-by-side is complete.

**The convergence.** ★★★★★ **Observations 1 and 2 are one defect with one cause: nothing on the
port answers the title screen's wait.** The script's own setup says what it is waiting for —
`prevent.input` at cycle 1 and **21 `set.key` controller bindings** installed in the same cycle.
★★★★ **The key-arbitration work carried as a follow-up since P6.61 now has a visible symptom
attached to it**, which is the difference between a backlog item and a dispatch.

**A separate finding, from the oracle run itself [§2Q].** ScummVM's detection of the pinned game
directory returns **two entries**:

```
agi:kq1   King's Quest: Quest for the Crown (2.0F 1987-05-05 5.25"/3.5"/DOS/English)
agi:kq1   King's Quest: Quest for the Crown (CoCo3/English)
User picked target 'kq1-1' ... Running ... (2.0F 1987-05-05 ... DOS/English)
```

★★★★ **Auto-detect ran the DOS release, not the CoCo3 one.** §2Q says *"'King's Quest I' is not a
specification"* and requires the game RELEASE to be pinned; this is that rule arriving in practice.
★★★ **Every visual comparison made against this reference so far has been against the DOS
variant**, and it is not established that the two releases share a title sequence.

### 4 — Verification

- **[measurement]** Credits stop at cycle 115; `display.v` 221 at both 150 and 500 cycles —
  `pic_order.py`, offline reference.
- **[measurement]** `load.view` 4, `animate.obj` 1, `draw` 0, `set.view` 0, `start.cycling` 0,
  `add.to.pic` 0, `overlay.pic` 0, `clear.lines` 0 over 500 cycles.
- **[measurement]** `set.key` 21 and `prevent.input` 1, both at cycle 1.
- **[eye-gated]** Jay, stock ScummVM 2.9.1 beside the port: the three observations above.
- **[measurement]** ScummVM detection returns two variants for the pinned directory; auto-detect
  chose DOS.

### 5 — Verdict-time evidence (v0.7 §11)

```
25.1  python harness/tools/pic_order.py --cycles 500 --watch draw,add.to.pic,set.view,
        start.cycling,clear.lines,new.room,show.pic,draw.pic,display.v,erase
      totals over 500 cycles:
          display.v 221   new.room 1   draw.pic 1   show.pic 1
      (last display.v at cycle 115; nothing emitted 116-500)

      python harness/tools/pic_order.py --cycles 150 --watch add.to.pic,add.to.pic.v,
        overlay.pic,discard.view,set.view,draw,animate.obj,load.view,start.cycling,
        cycle.time,accept.input,prevent.input,set.key,clear.lines
      totals over 150 cycles:
          set.key 21   load.view 4   animate.obj 1   prevent.input 1

      scummvm.exe --path=<pinned KQ1> --savepath=<scratch> --auto-detect
          agi:kq1  (2.0F 1987-05-05 5.25"/3.5"/DOS/English)
          agi:kq1  (CoCo3/English)
          User picked target 'kq1-1' ... Emulating Sierra AGI v2.917
25.2  N/A -- no artifact changed; no code changed.
25.3  Jay, stock ScummVM 2.9.1 side-by-side: the three observations in §3.
```

★ **§2P:** the game directory was opened read-only and `--savepath` was redirected to scratch, so
nothing was written into it. No message text and no screenshot appears in this report.

### 6 — Reactive deviations and route accounting
None. No code was changed and none was proposed. **ROUTE ACCOUNTING:** I stated that the next step
is a measurement (feeding a key to the offline reference) rather than an implementation, and I did
not begin the implementation.

### 7 — Uncertainty flags

1. ★★★★ **"The alligators are drawn after the title advances" is an INFERENCE, not a measurement.**
   It rests on our opcode stream matching the oracle's, which the nine-title state diff supports at
   9/9 — but **I did not verify this session that the diff's window extends past cycle 115 of KQ1's
   title**, and `vm_opcov`'s 600-cycle scope is a different instrument from the state diff.
   ★★★ **The cheap test is `vm_input_script.py`: feed a key to the offline reference and see
   whether `draw` then appears.** Until that is run, the claim is a lead.
2. ★★★ **It is not established that the DOS and CoCo3 releases share a title sequence.** If they
   diverge, part of what Jay compared may be a release difference rather than a port defect. **This
   applies retroactively to every visual comparison in this arc.**
3. ★★ **Whether the port's key path reaches the title's wait at all is untested.** `prevent.input`
   is active, and what the 21 controller bindings do under it is exactly the arbitration question.

### 8 — Follow-up candidates

1. ★★★★★ **Make a key reach the title screen's wait and see what the game does next.** This is the
   dispatch these three observations converge on, and it subsumes the carried key-arbitration item.
   **First step is the offline measurement in flag 1, before any 6809 code.**
2. ★★★★ **Pin the game RELEASE, not the title [§2Q].** Record which of the two detected variants is
   the reference, in `oracle/scummvm.pin` or beside it, and state it in every visual comparison.
3. ★★★ **The eye gate's default room jump should move past the title** [P6.68 §8.1], so the
   standard gate shows the title sequence AND the castle without anyone remembering a flag.
4. ★★ **`RESTORE COPIED NOTHING` should be conditioned on `p3_nspr > 0`** [P6.68 §7.3] — on the
   title screen it reads as a fault and is not one.
5. ★ Carried: the flags' blink / `src/hal/` page flip (staged) · the picture leaving the logic arena
   [P6.67 §7.1] · `configure.screen`'s render offset · `gates.manifest` row for the combined arm ·
   straddle clamp · `MAP_PRI_BANDS`.

### 9 — User interaction during task
Jay asked for KQ1 on stock ScummVM, ran it beside the port, and reported: *"so the 'press a key to
continue' does not dissapear with the copyright on the port like the oracle. also the oracle has
alligators swimming in the moat at the bottom of the screen which the port does not. also the flags
still flash (blink) while animating."*

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-20-the-number-that-settled-one-question-was-the-answer-to-another.md`

### 11 — Commit
`098f5c2` — 1 file changed, 157 insertions(+). Pushed to origin/wip (`fb44b2a..098f5c2`).
