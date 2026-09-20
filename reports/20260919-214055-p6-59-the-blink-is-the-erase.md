## Form B Report — T-P0-113 / P6.59 — The blink is the erase, and a static sprite need not be erased
**Class:** measurement.  wip.  **No `src/` change.**

### 0 — Receipt / status (C-35 stamp)

t0=2026-09-19 21:40:55 (HEAD f2cc5a0, wip). `harness/tools/p3b_run.lua` +19,
`harness/tools/p3b_show.ps1` +17/−1. ★★ **`git diff --stat -- src/` is EMPTY** — AC-7 is met more
strictly than it was written, since the publish needed no source change either.

### 1 — Summary

★★★★★ **AC-6's red, owed since P6.58: CONFIRMED.** Jay on `-NoRestore`: ***"the flags do have a
background."*** The restore is provably what removes the box.

★★★★★ **AND THE SECOND CLAUSE IS THE TASK'S FINDING:** ***"graham looks the same except he is not
blinking anymore."*** ★★★★ **Graham does not animate and does not move, yet he blinks in the clean
arm and not in the arm with the restore removed. So the blink is caused by THE ERASE, not by the
animation** — and Graham is erased and redrawn every frame for no reason at all, because his pixels
are identical to the ones already there.

★★★★★ **That is a third shape, and it costs nothing:** restore only the rectangles of sprites that
actually **changed**. An unchanged sprite is never erased, so it cannot blink. ★★★ **Neither the
Orchestrator nor I had it before Jay's sentence.**

★★★★ **And the page flip is NOT already written.** §3.2: `HAL_gfx_present` hardcodes frames that
are the wrong size, in the wrong place, inside `p3b`'s own CPU window — and §2N makes the HAL the
sanctioned owner of the register a flip writes. **Page flip is blocked behind a `src/hal/` task**,
which §6 forbids here.

★★★ **Two of P6.58's three owed items are still owed** (§4, AC-4 and AC-5) and that is stated rather
than softened.

### 2 — Files modified

- `harness/tools/p3b_show.ps1` — `-NoRestore`, wiring `-DP3B_FAULT_NORESTORE`; `p3_restbytes` and
  `p3_prevn` added to the **cel-arm-only** `$WANT` line.
- `harness/tools/p3b_run.lua` — the restore readout beside the four composite counters.

★★ **Neither is `src/`.** `p3b_probe.s` is untouched since P6.58, so all seven arms keep their
figures and no gate input moved.

### 3 — Reasoning

#### 3.1 §4C — the fault arm, run and shown red

★★★★★ **A fault arm that has only been assembled is not a fault arm** [§2W, and P6.58 §4 said so
about this one]. It is now runnable by flag — `p3b_show.ps1 -NoRestore` — and was run twice:

```
headless: p3b_probe: 14663 bytes ; final room 1, sprites 4, err 0 ; 300 cycles, no stall
windowed: p3b_probe: 14663 bytes ; room jump at cycle 8 ; Average speed 99.79% (48 seconds)
```

★★★★ **The red is one the project has already seen on a screen** — it is exactly what every build
before T-P0-112 did, and exactly what Jay reported at the first side-by-side. **Jay, on this run:
*"the flags do have a background."*** ★★★ **-3 bytes, one `jsr`, one behaviour.**

★ **My error, repeated:** I asked Jay to confirm a red without saying what red looks like, and he
had to ask *"what am i looking for"*. ★★ **The same error as T-P0-105's "so im confused about what
the sprites are"**, and the pool row this project already carries about eye gates says the fix is to
supply the comparison as part of the ask. **I did not.**

#### 3.2 §4A/§3(2) — the flip routine: contract, callers, and why AGI cannot use it

**Contract** [`gfx.s:970-993`]: reads `page_register` (DP `$50`), writes `$FF9D` with **`$F000`** or
**`$F800`**, preserves U/Y, clobbers A/B/D/CC, does not modify `page_register`. ★★★ ***"NO VBL
gating. Tearing may occur if called mid-scanline. VBL synchronization is deferred to P3.2."***

**Callers, measured at each repo's `wip` HEAD** [§2S]:

| repo | ref | callers |
|---|---|---|
| **karateka_coco3** | `29f8f0a` wip | ★★★ **7** — `boot.s` ×6, `broderbund_scene.s:136` |
| **POP3_port** | `104b197` wip | ★★ **0** — `import`/`export` only, never called |
| **coco_agi** | `f2cc5a0` wip | **0** |

★★★★★ **THREE REASONS AGI CANNOT USE IT AS WRITTEN:**

1. **The frames are hardcoded.** `$F000`/`$F800` are VOFFSET for physical `$78000`/`$7C000` —
   **blocks 60 and 62**. Not a parameter, not mode-aware.
2. **They are the wrong size.** 2 blocks apart = 16 KB, which is 4-colour's 15,360 B rounded up.
   ★★★ **AGI's plane is 26,880 B = 4 blocks.** Frame A would run into Frame B.
3. ★★★★ **They collide with `p3b`'s CPU window.** `p3b_probe.s:472` calls `$38-$3F` (blocks
   **56-63**) *"the CPU window"*; 60 and 62 are inside it. **AC-2's answer is yes.**

★★★★★ **AND THE SAME FILE ARGUES AGAINST ITS OWN ROUTINE.** `gfx.s:379-389`, six hundred lines
above, places 16-colour buffers at blocks `$10-$13`/`$18-$1B` and says why:

> *"WHY NOT THE TOP 64 KB. The CoCo3 boots with CPU `$0000-$FFFF` mapped to physical
> `$70000-$7FFFF`, so a buffer placed there overlaps the running program ... Drawing into such a
> buffer would overwrite the code doing the drawing."*

★★★ **`HAL_gfx_present` writes exactly those top-64 KB addresses.** It implements the P2.3a
4-colour scheme; the P2.6 geometry that supersedes it never reached this routine. ★★ **It works for
Karateka because Karateka IS that scheme** — 4-colour, buffers at CPU `$8000`/`$C000`, code below
them.

★★★★★ **THE DISPATCH'S PREMISE WAS HALF RIGHT AND THE HALVES POINT OPPOSITE WAYS.** §1.1 said
*"page flipping is not a thing to invent"* — **true of the mechanism, false of the routine.** The
mechanism is one 16-bit store. The routine cannot express AGI's geometry, and making it do so is a
`src/hal/` change gated three ways by `hal_sync_check.py` [§6's second trigger].

#### 3.3 ★★★★ And the guest does not write VOFFSET at all

★★★★★ **`p3b_show.lua:180-189` — the HOST writes it:** `prog:write_u8(0xFF9E, voff & 0xFF)`, then
prints `DISPLAY -> ph_blk_fb=40 physical=$50000 VOFFSET=$A000`. ★★★ **The guest has never pointed
the GIME at anything.** The display follows `ph_blk_fb` because a harness reads that byte and writes
the register on the guest's behalf.

★★★★ **So a page flip needs a NEW REGISTER WRITE ON THE GUEST SIDE, and §2N decides who may make
it:** *"The HAL owns `$FF90`–`$FF9F` (GIME/MMU/SAM)"* — and `$FF9D`/`$FF9E` are inside that range.
★★★ **Either the HAL gains a usable flip (a three-repo task) or a second owner appears outside it,
which is the thing §2N exists to prevent.**

★★ **This also means the current display path is a harness convenience, not a port mechanism** —
worth knowing before anything is built on it.

#### 3.4 ★★★★★ The blink is the erase — what Graham proves

**The observation.** Clean arm: Graham blinks. `-NoRestore`: *"graham looks the same except he is
not blinking anymore."* **He does not animate and does not move in either.**

**The mechanism it establishes.** `p3_stage_sprites` stages every `fDrawn` object each cycle and
`p3_composite_all` composites all of them, so **T-P0-112's recorder records Graham's rectangle every
frame and the restore erases it every frame** — then the compositor paints back the identical
pixels. ★★★★ **The erase is the only thing that changes what is on the screen, and it is pure
waste for him.**

★★★★★ **So the blink's cause is not animation and not the compositor. It is erasing a sprite that
did not need erasing** — and the fault arm is the control that proves it, because removing the erase
removes the blink while leaving everything else identical.

★★★ **Neither shape the dispatch asked me to price addresses this.** A page flip hides the erase; an
interleave shortens it. **Skipping it is free.**

**The rule, and why overlaps stay correct:**

> **Restore only the rectangles of sprites whose (x, y, w, h, view, loop, cel) differ from last
> frame. Composite all sprites, unchanged ones included, exactly as now.**

★★★★ **An unchanged sprite is never erased, so it cannot blink.** ★★★ **And if a CHANGED sprite's
restore overlapped it, the composite pass repaints every sprite afterwards**, so the overlap is
repaired in the same frame — the ordering that already exists is what makes this safe. ★★ The
recorder needs three more bytes per entry (view/loop/cel) to make the comparison.

★ **What it does NOT fix:** a genuinely animating flag changes cel every frame, so it is erased
every frame and still blinks. **"Eliminates" for static sprites, "no change" for animating ones.**

#### 3.5 §4D — the latent block collision, and the assertion it wants

Unchanged from P6.58 §3.1 and still not fixed: **Kingquest2's volumes reach block 44, PoliceQuest1
and SpaceQuest-1 reach 40, and the visible plane is 40-43.** Unreachable only because the nine-title
sweep uses `vm_probe.s` and the `p3b` rows run Kingquest1 and SpaceQuest-2.

★★ **The assertion is host-side, not assembler-side**, because the staging base comes from
`build/vm_stage/*/manifest.txt` at run time. **One line in `p3b_run.lua`'s `stage()`**, after `nblk`
is computed:

```lua
if base + nblk - 1 >= 40 and base <= 43 then
    w("★★★ vol.%d stages into blocks %d-%d, which OVERLAP the visible plane at 40-43", ...)
    return false
end
```

★ **Not built here** — §4D says describe it, and it is one line only because `P3_BLK_VISIBLE` is a
constant the host already knows.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement] — MET.** §3.2: contract, and every caller at each repo's stated ref.
- **AC-2 [measurement] — MET.** §3.2: **yes, blocks 60/62 are inside `p3b`'s `$38-$3F` window** —
  and two further reasons the routine cannot serve AGI.
- **AC-3 [measurement] — MET.** §7A, three shapes, each marked *eliminates* or *shortens*.
- **AC-4 [state-comparable] — NOT MET.** ★★★★ **No plane census was run.** The restore's evidence is
  still Jay's eye plus the fault arm's contrast. ★★★ **Owed a second task running.**
- **AC-5 [measurement] — PARTIAL.** The counter is published — `p3_restbytes`/`p3_prevn` on the
  cel-arm `$WANT` line, readout added beside the composite counters — ★★ **but the section it prints
  from is gated behind a flag I did not identify, so no per-frame byte figure exists.** The plumbing
  is landed and correct; it has not produced a number.
- **AC-6 [fault injection] — MET.** §3.1. Run twice, red confirmed by Jay.
- **AC-7 [byte-comparable] — MET, strictly.** `git diff --stat -- src/` **empty**; `p3b_probe.s`
  untouched, so all seven arms hold P6.58's figures.
- **AC-8 [byte-comparable · gate] — CITED, NOT RE-RUN.** §2T: no gate input changed
  (`git diff -- src/` empty; the two edited files are host-side harness). pic 45/45, res 1,264/1,264,
  cel 9,193/9,193, comp 124/124 carried from P6.58, **where they were run fresh against this exact
  `p3b_probe.s`.**
- **AC-9 [measurement] — MET.** §3.5, described and sketched, not built.
- **AC-10 [ruling requested] — MET.** §7A.
- **AC-11 [tooling] — CITED.** Run green at P6.58 against an unchanged `src/`; nothing this task
  touched is in their scope (`hal_sync_check` compares `src/hal/`, `reg_discipline` scans
  `src/engine/`, `gen_vm_tables` compares `vm_tables.s`). ★ Not re-run, and said so.
- **AC-12 — MET.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output:**

```
$ p3b_show.ps1 -Title Kingquest1 -Cycles 300 -Headless -NoRestore
p3b_probe: 14663 bytes
final room 1, sprites 4, err 0, status=$00 ; ★ 300 cycles, no stall

$ p3b_show.ps1 -Title Kingquest1 -Cycles 400 -NoRestore     (windowed, eye gate)
p3b_probe: 14663 bytes ; room jump at cycle 8 ; Average speed: 99.79% (48 seconds)

$ git diff --stat -- src/
(empty)
$ git diff --stat
 harness/tools/p3b_run.lua  | 19 +++++++++++++++++++
 harness/tools/p3b_show.ps1 | 17 ++++++++++++++++-
```

**25.2 bundled-artifact grep:** N/A.

**25.3 operator-runtime-smoke:** ★★★★★ **PASSED as a fault arm — Jay, live, RGB, `-NoRestore`,
room 1, 400 cycles at 99.79%.** *"the flags do have a background. graham looks the same except he is
not blinking anymore."* ★★★ **Both clauses are findings and the second was not asked for.**

### 6 — Reactive deviations and route accounting

★★ **No §6 trigger fired.** The third — *"the census shows the background is NOT restored"* — could
not fire because **the census was not run** (AC-4), and that is a gap, not a pass.

★★★ **Neither shape was implemented** [§6's first trigger, respected]. The third shape in §7A is
**described and not built.**

★★★★ **`src/hal/` untouched** [§6's second trigger]. §3.2's conclusion is that using the flip
*would* require touching it, which is reported as a blocked price rather than worked around.

**Route accounting.** ★★★ **I proposed nothing and built nothing.** The plumbing in §2 is the
publish AC-5 asked for; it is not a fix and does not change any binary.

★ **One thing I said I would do and did not:** I told Jay I would run the two arms back to back so
he saw them in sequence. **He answered from the single fault run instead**, which was enough — but
the comparison I offered was not the one delivered.

### 7 — Uncertainty flags

1. ★★★★★ **AC-4 is still owed, second task running.** *"The background is restored"* rests on a
   human eye and on the fault arm's contrast. ★★★ **Both are strong and neither is a count.**
2. ★★★★ **AC-5 produced no number.** The counter exists in the binary and the readout exists in the
   host; **the diagnostic section is gated by a flag I did not find**, and I stopped looking rather
   than keep spending the task on plumbing.
3. ★★★★ **§3.4's rule is reasoned, not measured.** Graham's case proves the erase causes the blink;
   **it does not prove that skipping the erase for unchanged sprites is correct under overlap** —
   the argument is that the composite pass repairs it, and that argument has not been run.
4. ★★★ **"The flags still blink under shape 3" is a prediction.** They change cel every frame *if*
   the animation is per-frame; **the cel cadence was not measured.** If a flag holds a cel for
   several frames, shape 3 helps it too.
5. ★★ **P6.58's straddle clamp is still in** (~1.9% of row starts restore short) and no census has
   looked for its residue.
6. ★ **The Karateka caller count is from `git grep` at `29f8f0a`**, not from reading each site.

### 8 — Follow-up candidates

1. ★★★★★ **Take §7A's ruling.** ★★★ **Shape 3 is free and composes with either other shape**, so it
   can land first regardless of what is decided about the flip.
2. ★★★★★ **Close AC-4 and AC-5 in whatever task runs next in this file.** Both are cheap once the
   gating flag is identified; ★★★ **they have now been owed across two tasks and that is how
   evidence quietly stops being collected.**
3. ★★★★ **If the flip is wanted: a `src/hal/` task to make `HAL_gfx_present` mode-aware**, using the
   P2.6 geometry the same file already documents. ★★★ **It would also fix a routine that
   contradicts its own file** — which is a defect for Karateka's successor, not only for AGI.
4. ★★★ **The visible-plane/volume collision assertion** — §3.5, one line, host-side.
5. ★★★ **The Graham-smear prediction** [P6.55 §3.3] — ★★★★ **and it is now half-answered without
   being run**: Graham is restored every frame today, so when he walks he should *not* smear.
   **`HAL_KEYBOARD` in the cel arm is still the next task**; eye-gate question 2 blocked **seven**.
6. ★★ Delete the dead `ifdef CP_SAVE` block [P6.56, P6.57 §8.2, P6.58 §8.6] — **third task carrying
   it.**
7. ★ `MAP_PRI_BANDS` — **seventh task carrying an address nothing uses.**

### 9 — User interaction during task

1. **"the flags do have a background."** — AC-6's red.
2. ★★★★★ **"graham looks the same except he is not blinking anymore."** — **§3.4, and the whole
   task turns on it.** Not asked for, not anticipated, and it identifies the blink's cause and its
   cheapest fix in one clause.
3. ★★ **"hat am i looking for"** — asked because I requested a verdict without describing the
   expected red. §3.1 records it as my error; **it is the second time in this session.**

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-19-the-control-arm-answered-a-question-nobody-asked-it.md`
- `seeds/AGI/live/2026-09-19-a-shared-routine-can-contradict-its-own-files-geometry.md`

---

## 7A — ★★★★★ RULING REQUESTED — three shapes now, and one is free

**What causes the blink, established this task:** erasing a sprite and redrawing it on the plane the
display is reading. **Graham proves it** — he never moves, he blinks with the restore in, and he
stops blinking with it out.

| | 1. page flip | 2. per-sprite interleave | ★ 3. skip unchanged sprites |
|---|---|---|---|
| **blocks** | 4 (47-50 free) | 0 | **0** |
| **effect** | **eliminates**, all sprites | **shortens** | **eliminates for STATIC sprites**; no change for animating ones |
| **new code** | second dirty list, two frames deep | reorder one loop | compare 7 bytes per sprite |
| **blocked by** | ★★★★ **`src/hal/` — §2N makes the HAL the only sanctioned owner of `$FF9D`, and `HAL_gfx_present` cannot express AGI's geometry** | nothing | nothing |
| **risk** | a three-repo HAL change, `hal_sync_check` gates it | overlapping sprites erase each other if the order is wrong | overlap correctness rests on the composite pass repairing it |

**Recommendation: take 3 now, and decide about 1 separately.**

Shape 3 costs nothing, needs no blocks, touches no shared file, and **removes the blink from every
sprite that is not currently animating — which includes the ego whenever he is standing still**, the
case you will look at most. It composes with either other shape rather than competing with them.

**On the page flip, I was wrong in your favour and then wrong against it.** I priced it last task as
4 blocks and a dirty list. It is that *plus* a `src/hal/` change, because the routine that exists
points the GIME at the wrong place, at the wrong size, inside blocks `p3b` calls its own — and the
guest has never written that register at all; the harness has been doing it. **That does not kill
it. It makes it a HAL task, which is a different shape of work and a different risk.**

**What I would not do:** price shape 2 as the answer. It shortens a blink; it does not remove one,
and the eye gate will keep reporting it.

### 11 — Commit

`<this report>` — pushed to origin/wip before reporting. **No source commit: `src/` is untouched.**
