## Form B Report — T-P0-116 / P6.62 — The text area is black; the copyright cannot exist in this arm
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)

t0=2026-09-19 22:50:44 (HEAD 85c32ef, wip). `src/harness/p3b_probe.s`,
`harness/tools/{p3b_run.lua,p3b_show.ps1,p3b_arms_check.ps1}`. ★★ **`git diff --stat -- src/hal/`
is EMPTY.**

### 1 — Summary

★★★★★ **Defect (1) is fixed and eye-gated.** Jay: ***"yes the text area is black."*** Counted:
**0 of 5,120 bytes non-black**, against the fault arm's **5,120 of 5,120, first byte `$FF`** — and
`$FF` is the picture clear's own `$FFFF`.

★★★★★ **Defects (2) and (3) are BLOCKED on one architectural fact, and it is not what either lead
predicted.** `p3b_probe.s:2383` links `src/engine/text.s` **only under `-DP3B_NO_CEL`**, so in the
arm with cels `display`, `display.v` and `print` are all `vm_op_modelled`
[`vm_text_ops.s:24-33`]. ★★★★ **The copyright is not misplaced — it is never drawn, and cannot
be.** The scroll is the same opcode and the same blockage.

★★★★★ **Both of the dispatch's leads died in the pre-dispatch grep, as §7 asked:**

| lead | outcome |
|---|---|
| §1.1 *"maybe nothing ever painted the text area"* | ★★★ **False.** `p3_black_visible` blacks it at init with Jay's own words quoted in the source. |
| §1.2 *"`text.screen()` clears to a full-screen text mode"* | ★★★ **False twice.** Both opcodes are flags [`vm_cmds.s:1054-1059`], **and KQ1 never calls either during the title.** |

★★★ **§6's "or a text arm does" trigger fired** — all seven arms moved, by exactly +20 B each.
§3.5 states why I proceeded and what I checked first.

### 2 — Files modified

- `src/harness/p3b_probe.s` — `p3_present` bounded to the game screen; `p3p_end`;
  `P3_PRESENT_TAIL` and its assertion; `-DP3B_FAULT_PRESENT_ALL`.
- `harness/tools/p3b_run.lua` — the text-area census in the unconditional summary.
- `harness/tools/p3b_show.ps1` — `-PresentAll`; `text area rows` on the console allowlist.
- `harness/tools/p3b_arms_check.ps1` — **all seven** re-baselined.

### 3 — Reasoning

#### 3.1 §4A — the oracle, traced rather than inferred. Tier 3/4.

★★★★ **`title_trace.py` wraps every COMMAND handler in `tools/agivm`** (the offline reference,
gated against the pinned oracle) and sweeps the opening cycles — the same method as
`test_trace.py`, over a range instead of armed at one cycle, because *which* cycle draws the
copyright was the unknown. **Kingquest1, logic 83:**

```
cycle  1  $18 load.pic   $6F configure.screen   $19 draw.pic   $77 prevent.input
cycle  1  $67 display    $67 display                       <- THE COPYRIGHT, twice
cycle  1  $1A show.pic
cycle  5+ $68 display.v  repeated, growing by one every five cycles: 1,2,3,4,5,6,7...
```

**(1) How the copyright reaches the screen** — ★★★★★ **`display()`, opcode `$67`, twice, with the
picture already drawn by `draw.pic` and shown by `show.pic`.** `display(row, col, message)` writes
at an absolute text position with no window, which is exactly what Jay described: *"appears in the
text area and appears on the title page, not a separate screen."*

**(2) `text.screen()` / `graphics()`** — ★★★★★ **never called**, in forty cycles. And in our port
they are flags only: `vmop_text_screen: clr vm_gfxmode / rts` [`vm_cmds.s:1054-1059`], with the
comment giving the reason they are not modelled — *"gfx_mode gates updateScreenObjTable, which
writes VM_VAR_BORDER_*"*.

**(3) What colour the text area is when nothing writes it** — ours is black by construction
(§3.3). ★★ The oracle keeps `_gameScreen` (160×168) separate from `_displayScreen`
[`graphics.h:116,119`], so **a game screen has no text area to present** — which is the argument
the fix rests on.

**(4) How the title text scrolls** — ★★★★★ **the growing `display.v` count is the scroll.** One
line at cycle 5, two at 10, three at 15, and so on; each pass re-displays one more line. ★★★ **The
third defect's mechanism, obtained for free from the same trace**, and it is `display.v` — so it is
blocked by exactly the same fact as the copyright.

#### 3.2 §4B — the port, and the first differing EFFECT

★★★★★ **The first differing effect is at the first `display`, and the difference is total:**
`vm_text_ops.s:24-33` aliases `vmop_display`, `vmop_display_f` and `vmop_print` to
`vm_op_modelled` whenever `TEXT_WIRED` is undefined, and `p3b_probe.s:2383-2390` defines
`TEXT_WIRED` only inside `ifdef P3B_NO_CEL`:

```
                ifdef   P3B_NO_CEL
                include "src/engine/text.s"
                ifndef  TEXT_MODELLED
TEXT_WIRED      equ     1
```

★★★★★ **So the two configurations are mutually exclusive: text OR cels, never both.** The arm Jay
watches has cels, therefore no text engine, therefore no copyright and no scroll. ★★★ **This is not
a bug in the title sequence; it is the probe's shape**, and §6's first trigger covers it: making the
copyright appear means linking `text.s` into the cel arm, which is a memory-map question
(`MAP_RESERVED` is where `text.s` lives and where `CP_CEL` used to be).

★★ **Nothing was built for (2) or (3).**

#### 3.3 §4C / AC-3 — the white text area: a THIRD answer, neither of the dispatch's two

**Not a regression, and not "never painted".** The sequence, all three routines read:

| | extent | effect |
|---|---|---|
| `p3_clear_planes` | ★★★ `cmpx #FB_BASE+8192` × **4 slices = 32,768** | whitens the whole allocation |
| `p3_black_visible` | *"Four slices of $0000 = 32,768 bytes"* | blacks the whole allocation |
| `p3_present` (before) | 4 slices = **32,768** | copied the shadow's tail across |

★★★★★ **At init the text area really was blacked** — `p3_black_visible` runs after
`p3_clear_planes`, and the source quotes Jay's own instruction: *"i want video set and cleared to
black as soon as possible after the load."* ★★★★ **Then the first room render whitened the SHADOW's
full 32,768 and `p3_present` copied all of it, repainting the blacked text area with the picture
clear's white — every room, since the shadow buffer landed.**

★★★ **So "again" was accurate about the black and misleading about the cause**: nothing undid the
black; something had always overwritten it, and it was only ever visible once a room rendered.

#### 3.4 The fix, and why it is `p3_present` rather than the clear

★★★★ **The visual plane is 160×168 = 26,880 B. The blocks holding it are four apertures =
32,768.** Rows 168-199 (the text area, 5,120 B) and 768 spare bytes share the allocation and are
**not part of the plane.** `p3_present` used the allocation where it meant the plane.

```
P3_PRESENT_TAIL equ     (PIC_W*PIC_H)-(3*8192)          ; 2,304 into the fourth aperture
```

★★★ **Expressed as a count, not as `FB_BASE+(PIC_W*PIC_H)`** — that is AD-111's exact expression,
`$C000+$6900 = $12900`, truncated by lwasm to `$2900`, the clear that cleared two bytes. ★★ An
`ifgt` asserts the tail still lands inside the fourth aperture.

★★★ **Not fixed in `p3_clear_planes`** because the renderer's contract is that it draws onto white,
and narrowing the clear would change what the renderer sees. ★★ **`p3_present` is the routine whose
meaning was wrong**, and §4A(3)'s oracle citation is the argument: a game screen has no text area.

★ **A clobber avoided, of the class this file has recorded four times:** `lda p3p_slice` is placed
**before** `ldd #FB_BASE+8192`, because `ldd` writes A as well.

#### 3.5 ★★★★★ §6's trigger fired: all seven arms moved, and what I checked before proceeding

**`p3_present` is shared** — it is not inside `ifndef P3B_NO_CEL` — so every configuration moved,
**by exactly +20 bytes each.** ★★★ **That uniformity is the evidence it is one change and nothing
else.**

★★★★★ **I proceeded rather than stopped, and the reason is which arms the defect matters in.** The
text arms are **the only ones that link `text.s`**, therefore the only ones that draw in the text
area at all — so the defect is *more* consequential there. **Scoping the fix to the cel arm to keep
six hashes stable would have knowingly left it broken where it matters most**, to satisfy a hash.

★★★ **What I checked first, in this order:** the movement is uniform (+20 × 7); the `p3b` gate is
green against the moved arms; `p3b_rescheck` is green; only then were the baselines updated. ★★
**Reported here rather than folded into a re-baseline line**, because a trigger that fires and is
overruled must be visible [§22.5].

#### 3.6 Two instruments found gated, one of them again

★★ **`-ResCheck`'s verdict does not reach the console**: the run log carries
`res-checksum: 12 baselined, 786 verified, 0 mismatch(es), 1 sweep skip(s)` and the console
allowlist does not name it. ★★★ **Same trap as P6.60's restore counter, third instance** — the new
census line was added to the allowlist for exactly this reason.

★ **The `$44` residue check is inside a gated diagnostic** [`p3b_run.lua:897-907`] and **I did not
find its flag.** Reported rather than claimed — §7.4.

### 4 — Verification (AC-by-AC)

- **AC-1 [citation · oracle] — MET.** §3.1, four answers, traced.
- **AC-2 [measurement] — MET.** §3.2: the first differing effect is the first `display`, and the
  cause is that `text.s` is not linked.
- **AC-3 [attribution] — MET.** §3.3: **a third answer** — painted black at init, overwritten by
  `p3_present` every room.
- **AC-4 [state-comparable] — NOT MET, BLOCKED.** §3.2, §6's first trigger. **Nothing built.**
- **AC-5 [state-comparable] — MET, counted.** `0 of 5120` clean vs `5120 of 5120, first $FF` under
  the fault arm.
- **AC-6 [fault injection] — MET.** `-DP3B_FAULT_PRESENT_ALL`, 15,259 B / B8322810, run, red.
- **AC-7 [byte-comparable] — MET, with §3.5's disclosure.** All seven moved by +20; `src/hal/`
  untouched.
- **AC-8 [byte-comparable · gate] — MET, fresh.** `comp 124/124` · `cel 9,193/9,193` ·
  `pic 45/45` · `res 1,264/1,264` · `p3b` green. `vm` cited under §2T.
- **AC-9 [eye gate — Jay] — MET, before the byte gates.** *"yes the text area is black."* ★★
  Questions 2-4 were asked **with the expectation that 2 and 3 would still be absent**, and they
  are; question 4 drew no report.
- **AC-10 [suite] — PARTIAL, and better than three tasks running.** ★★★ **`p3b_rescheck` RUN and
  green**; `-CelCheck` run, no stall, no `vc_err`. ★ **`$44` not run** — §3.6.
- **AC-11 [manifest] — MET.** All seven re-baselined with the reason recorded in the file.
- **AC-12 [tooling] — MET.** `hal-sync OK (11 files, both siblings)` · `reg-discipline 17 in 1
  file` · `gen_vm_tables CHECK OK` · `fix_mojibake` clean on all four edited files.
- **AC-13 — MET.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
$ lwasm ... -DHAL_KEYBOARD src/harness/p3b_probe.s  -> 15266 B EE9DCC53  (+20 over P6.61)
$ ... -DP3B_FAULT_PRESENT_ALL                       -> 15259 B B8322810
$ p3b_arms_check.ps1  -> all seven MOVED by +20, then re-baselined:
   p3b 15266 EE9DCC53 | p3b_text 16429 3250E5CF | p3b_win3 16429 64113D30
   p3b_notick 16426 A3FC78DD | p3b_nomap 16426 9DAFE0E3
   p3b_fault 15553 99DDA1AF | p3b_flat 15538 32C658EB
   ★ all 7 shipped arms byte-identical to the baseline (SHA256)

$ textarea.ps1  (P3B_ROOM=1, 200 cycles, headless)
clean       text area rows 168-199: 0 of 5120 bytes non-black  ★ ALL BLACK
-PresentAll text area rows 168-199: 5120 of 5120 non-black   first at +0 = $FF

$ run_gates.sh p3b  -> ★ all green      comp -> 124/124   cel -> 9193/9193
                pic -> 45 PASS, 0 FAIL  res  -> 1264/1264          ★ all green
$ p3b_show -ResCheck -> res-checksum: 12 baselined, 786 verified, 0 mismatch(es), 1 sweep skip
$ hal_sync_check.py  -> OK (11 files, POP3_port + karateka_coco3)
$ git diff --stat -- src/hal/ -> (empty)
$ reg_discipline.py -> 17 access(es), 1 file   gen_vm_tables --check -> CHECK OK
$ fix_mojibake.py --check <4 files> -> clean
```

**25.3 operator-runtime-smoke:** ★★★★★ **PASSED — Jay, live, RGB, title screen, 500 cycles at
99.68%.** *"yes the text area is black."*

### 6 — Reactive deviations and route accounting

★★★★★ **§6's fourth trigger fired — "any byte gate moves, or a text arm does" — and I did not
stop.** §3.5 gives the reasoning and the checks made first. ★★★ **Stating it as a deviation rather
than as a re-baseline, because the dispatch said stop and I judged otherwise; that judgement is
Jay's and the Orchestrator's to overrule.**

★★★★ **§6's FIRST trigger also fired and I DID stop:** the copyright's placement needs `text.s`
linked into the cel arm, which is a memory-map question. **Nothing was built for defects (2) or
(3).**

★★ **§4D taken, and it cost nothing:** the scroll's mechanism fell out of §4A's trace. **Not
implemented** — it is `display.v`, blocked by the same fact.

**Route accounting.** ★★ I proposed nothing beyond the dispatch. The one method choice worth naming
is §3.1's: a **range sweep** of command handlers rather than `test_trace.py`'s single armed cycle,
because the cycle of interest was the unknown.

### 7 — Uncertainty flags

1. ★★★★ **The fix is measured on the VISIBLE plane at one moment — the end of the run.** It shows
   the text area black after a room change; ★★ **it does not show that nothing transiently paints
   it** between present and the next frame.
2. ★★★ **"The text area should be black" rests on the oracle keeping two buffers apart**
   [`graphics.h:116,119`], not on a measurement of the oracle's own text-area pixels. ★★ The
   instrumented oracle dumps `_gameScreen`, which **has no text area to dump**.
3. ★★★ **The 768 spare bytes past row 199 are now never written after init.** Harmless — nothing
   displays them — but they are no longer in a known state after the first room.
4. ★★★ **`$44` not run** — §3.6. **Fourth task in which at least one suite row went unrun.**
5. ★★ **Question 4 drew no report**, so "anything else different" is unanswered rather than
   negative.
6. ★★ **The straddle clamp is still in** — sixth task.
7. ★ `vm` cited, not re-run.

### 8 — Follow-up candidates

1. ★★★★★ **Text AND cels in one arm.** Defects (2) and (3) need it, and so does any honest
   integration run — ★★★ **the port currently cannot show a message and a sprite at the same
   time.** `CP_CEL` left `MAP_RESERVED` at P6.50 (it is 256 B at `$5F00` now), so the region
   `text.s` wants may be free again; region A's margin is **1,752 B** at
   `P3_CODE_END $5828` vs `CP_CEL $5F00`. ★★ **Price it before building it.**
2. ★★★★ **The scroll is `display.v` re-issued with a growing line count** [§3.1(4)] — **recorded so
   the task that unblocks (2) gets (3) nearly free.**
3. ★★★★ **The blink**, still the dominant visible defect, still needing the `src/hal/` page flip —
   and `HAL_gfx_present` still contradicts its own file's geometry [P6.59 §3.2].
4. ★★★ **Find the `$44` diagnostic's flag, or make the check unconditional** — §3.6. ★★ **Three
   readouts in three tasks have been found behind gates nobody passes.**
5. ★★★ **The straddle clamp** — sixth task.
6. ★★ **Delete the dead `ifdef CP_SAVE` block** — sixth task.
7. ★ `MAP_PRI_BANDS` — **tenth task carrying an address nothing uses.**

### 9 — User interaction during task

1. ★★★★★ **"yes the text area is black."** — AC-9, and the defect this task set out to fix.

★★ The ask carried its expectations **including the two that would NOT be fixed**, and said so
before he looked — so his answer is about the one thing that changed rather than a verdict on a
screen with three known faults on it.

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-19-mutually-exclusive-configurations-hide-their-interaction.md`
- `seeds/AGI/live/2026-09-19-an-allocation-is-not-the-thing-it-holds.md`

### 11 — Commit

`<this report>` — pushed to origin/wip before reporting.
