## Form B Report — P3b.11a–f — Windowing built, priced, and gated
**Class:** build.  wip.
**Provenance:** ★ **Not a numbered dispatch.** Follow-on work authorised directly by Jay after
T-P0-042 closed, in four exchanges: *"yes do that"* (make p3b runnable), *"measure both"* (the two
fill-windowing designs), *"yes"* (build the winner), *"yes"* (close the gating gap).

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-01, continuing to 2026-09-04. Base HEAD `cd08982` (the commit carrying T-P0-042's
report). Current HEAD `5676912`, wip, clean. lwasm 4.24.

**Commits covered — none previously reported:**
```
45aaef3  P3b.11a  p3b uses the real MMU remap, not the flat-backed one
6d22960  P3b.11b  price both fill-windowing designs from measured counts
955c428  P3b.11c  row-transition count inverts the design ranking
4dcc890  P3b.11d  sensitivity, and the structural argument the model missed
7e81dc4  P3b.11e  build A': the fill windowed, straddle by borrowed slot
5676912  P3b.11f  the windowed renderer is GATED: 45/45 both planes
```

### 1 — Summary

★★★★★ **The windowed renderer is gated and correct: 45/45 visual and 45/45 priority,
byte-identical to the flat build in the same configuration.** Every pixel takes a different route
— slice split, mask, MMU remap, straddle borrow — to the same place.

★★★★★ **Getting there found SIX defects, all in code written during this work, and NOT ONE was
visible to the assembler or to the byte-identity checks that had been standing in for a gate.**
The binary T-P0-042 delivered — "assembles, 12,782 of 13,056, 274 spare" — **could not have run**:
it was built `PLANE_WINDOWED` without `PLANE_WIN_MMU`, so it used the flat-backed map action and
reintroduced the exact `$C000 + slice*8192` wrap windowing exists to remove.

★★★★ **Both fill-windowing designs were priced from measured counts rather than built.** A′
(per-row hoisted) 4.00% of the render, B (dual-slot) 5.80%, unhoisted A 12.74%. **The model's own
2× threshold said 1.45× does not decide it**, so the choice was made on structure — and the
decisive fact was one the cost model had missed entirely.

★★ **`MAP_RESERVED` is untouched at 3,328 throughout.** p3b assembles at 13,010 of 13,056.

### 2 — Files modified

- `src/engine/mmu_phase.s` — `phase_draw_fb`, plus the cross-slot pair `phase_draw_fb_slot5` /
  `phase_draw_pri_slot6` for the straddle borrow.
- `src/harness/plane_win.s` — MMU map actions call `mmu_phase.s` instead of writing registers;
  `PLANE_PRI_WIN`; a corrected comment (see §7).
- `src/harness/pic_fill.s` — `ff_win_row` (the one seam), the borrow, `fill_check` windowed, the
  `-DPIC_STRADDLE` census.
- `src/harness/pic_core.s` — priority sites keyed on `PLANE_PRI_WIN`.
- `src/harness/pic_probe.s` — windowed-MMU gate mode, windowed `vis_clear`, census counters.
- `src/harness/p3b_probe.s` — `PLANE_WIN_MMU`; `plane_reset` at `phase_draw_enter`.
- `harness/tools/` — `window_cost.py`, `move_block.py` (NEW); `pic_sweep.lua` census columns.

### 3 — Reasoning

**★★★★ Why both designs were priced instead of built.** Each design's cost is *how often the
expensive thing happens* × *what it costs each time*. The first factor is a **content** property —
which rows the corpus's fills touch, how often a span writes a second plane — so it is measurable
in the existing flat probe; the straddle set is a property of the geometry, not the base address.
The second is 6809 arithmetic. **So the uncertain half was measured and the certain half computed**,
instead of writing two versions of the project's most tuned loop to answer a question the counts
settle. Measured over 45 pictures: 425,179 flushes, 12.80% row transitions, 0.67% straddling,
48.45% writing a second plane.

**★★★ The ranking inverted once A was hoisted, and that was the point of measuring.** A's cost was
dominated not by its straddle fallback but by recomputing the slice **once per span** — which is
where I had put the code, not a property of the design. Hoisting it to once per row removed ~87%
of that term. **Ranking unhoisted A against B would have chosen a design on the strength of an
implementation artifact.**

**★★★★ What actually decided it was not the number.** The sensitivity says each assumed cost would
need to be 2.2–2.8× wrong to flip the ranking, but one of those assumptions is mine and optimistic:
the per-flush row compare costed at 8 cycles is nearer 12, at which the margin falls to 1.22×.
**The deciding fact was structural and the cost model had missed it: 27.8% of `fill_check` calls
are priority-only.** B's 16 KB window is built from *framebuffer* slices, so for over a quarter of
the work it is the wrong plane — B needs a second mode, and then the secondary visual write at
flush has no visual plane mapped. **B is two designs plus a mode switch, and none of that is in
its 5.80%.**

**★★★★★ Why "it assembles" was never evidence, stated as plainly as it deserves.** T-P0-042 closed
with p3b assembling and 274 bytes spare, and I described the remaining work as "the fill and
compositor windowing" — which understated it. As built, that binary would have wrapped into its own
code on the first pixel above slice 1. **The six defects below are the measure of the gap between
assembling and working**, and every one was found by 45 pictures and an oracle.

**§2S — sibling refs.** POP `104b197` wip, Karateka `29f8f0a` wip, unchanged; no shared file
touched.

### 4 — Verification (AC-by-AC)

★ **Self-assigned ACs**, since this was directed work rather than a dispatch.

- **AC-1 [byte-comparable]** ★★★★ **The windowed renderer gate: visual 45/45, priority 45/45**,
  byte-identical to the flat build in the same configuration (`-DPRI_PACKED -DPIC_NOCOUNT`). §5.
- **AC-2 [byte-comparable]** ★★★ **The flat build is byte-identical throughout** — 2,642 bytes at
  every step, verified after each change. The windowing is guarded and costs the flat path nothing.
- **AC-3 [byte-comparable]** ★★★ **p3b assembles windowed with the real MMU remap**: 13,010 of
  13,056, `P3_CODE_END = $52D2`, **`MAP_RESERVED` unchanged at 3,328**.
- **AC-4 [byte-comparable]** ★★ **`mmu_phase.s` remains the single register owner** —
  `reg_discipline`: 8 accesses, 1 file, 2 registers, after gaining three entry points. Writing the
  MMU in `plane_win.s` would have created a second owner in `src/harness`, which the census does
  not scan.
- **AC-5 [byte-comparable]** ★★ **All five gate artifacts byte-identical** (2,642 / 2,019 / 1,436 /
  967 / 9,036) — the windowing is `PLANE_WIN_MMU`-guarded and only p3b and the new gate mode
  define it.
- **AC-6 [state-comparable]** ★★★★ **Both designs priced; A′ chosen on structure.** §3, §5.
- **AC-7 [state-comparable]** ★★★ **Six defects found by the gate**, §5. **This is the AC that
  matters**: it is the evidence that the gate was worth building and that the prior standard —
  assembly plus byte-identity — was not a substitute.

### 5 — Verdict-time evidence (v0.7 §11)

**AC-1 — the windowed gate:**
```
flat identical (2642)
windowed: 3441 B
★★★★★ visual 45/45   priority 45/45
```

**AC-3 / AC-4 — p3b and ownership:**
```
p3b_probe.bin  13010 B     Symbol: P3_CODE_END = 52D2   (MAP_CODE_END = 5300)
MAP_RESERVED   $5300..$6000 = 3,328 B   unchanged
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s)
                 src/engine/mmu_phase.s   8   $FFA5 $FFA6
```

**AC-6 — the design pricing (`window_cost.py`, 45 pictures):**
```
runs flushed              425,179      row transitions   54,422 (12.80%)
flushes on straddling rows  2,855 (0.67%)   pixels in them 64,501 (5.43%)
flushes writing 2nd plane 205,994 (48.45%)

A   per-span (unhoisted)  15.957 s  12.74% of the 125.29 s baseline
A'  per-row  (hoisted)     5.012 s   4.00%
B   dual-slot 16 KB        7.270 s   5.80%
★ cheapest: A'  (next is 1.45x)  ★★★ TOO CLOSE TO CALL on this model alone

SENSITIVITY -- A' must gain +4,040,436 cy for B to win:
  row compare, per flush                 8 ->  17.5 cy  (2.2x)
  slice computation, per row transition 62 -> 136.2 cy  (2.2x)
  straddle penalty, per straddling pixel 34 ->  96.6 cy  (2.8x)
```

**★★★★★ AC-7 — THE SIX DEFECTS THE GATE FOUND:**

| # | defect | how the gate named it |
|---|---|---|
| 1 | **Two slice caches for one MMU register.** `plane_vis` cached in `pl_vis_cur`; `ff_win_row` mapped the same slot independently | 0/45; fills reading garbage |
| 2 | **`vis_clear` was a flat plane walk** — `$C000..$128FF`, wrapping past `$FFFF`, so the plane never got its initial white | 508 non-zero bytes against 26,228 |
| 3 | **`ldd #$FFFF` destroyed the slice counter**, so `vis_clear` mapped and cleared slice 0 forever | **exactly 8,192** non-zero bytes — a window, not a picture |
| 4 | **`fill_check` still formed a flat address.** It is the per-seed test, so a bad read drops the seed and its region never fills | a few columns per row left `$FF` where the reference had `$77` |
| 5 | **Init order** — `ph_blk_fb` set after `vis_clear`, so the FIRST render whitened blocks 0–3 | **picture 1 wrong, pictures 2–31 byte-identical** |
| 6 | **`PLANE_PRI_WIN`** — priority routed through a window it does not live in | **45/45 visual, 43/45 priority** — one plane perfect, the other uniformly wrong |

★★★★ **Two of the six (2 and 4) were sites T-P0-041's own `plane_walk_census.py` had already
listed.** I wrote then that the Orchestrator's two names were "probably incomplete" and produced
32 sites — then wired three and left the rest. **The enumeration was right; acting on all of it is
what I failed to do, twice.**

★★★ **Each defect's signature named it, and the signatures are worth keeping**: a round number
equal to the window size; a first-iteration-only failure; one plane perfect and the other
uniformly broken. None of those is "the picture looks wrong".

**25.2 bundled-artifact grep:** N/A — no bundled artifact.
**25.3 operator-runtime-smoke:** **N/A** — nothing reached the screen; all evidence is structured
text and byte comparison.

### 6 — Reactive deviations and route accounting

- **Route accounting.** I proposed, and Jay authorised, four steps: make p3b runnable; measure both
  designs; build the winner; close the gating gap. **All four are in the tree.** ★★ **What I did
  NOT do:** run `p3b_probe.bin`; window the compositor (`co_rowset` is untouched); window the
  priority walk in the gate map.
- ★★ **`move_block.py` is committed and half-disowned.** Given ambiguous anchors it moved the wrong
  lines twice — the second time dropping 97 lines inside `ff_store`'s loop. `pic_fill.s` was
  restored from HEAD and the work redone with explicit edits. Kept because the move it performs is
  real; its anchors must be unique lines, never `endc` or `rts`.

### 7 — Uncertainty flags

- ★★★ **`p3b_probe.bin` assembles and has NOT been run.** That is unchanged from T-P0-042 and is
  now the largest open item.
- ★★★ **The gate covers the 70.3% `FC_VISUAL` path.** `PLANE_PRI_FLAT` keeps priority flat in
  `pic_probe`'s map, so the priority walk's windowing is exercised only by p3b.
- ★★ **The compositor is not windowed.** `co_rowset` still addresses flat; the per-row design is
  settled but unbuilt.
- ★★ **A′'s cost was priced, not measured on the built code.** The 4.00% is from the model; I did
  not re-time the renderer after building it.
- ★ **A comment in `plane_win.s` claimed `$FFA7` covers `$C000-$DFFF`.** It covers `$E000-$FFFF`;
  `$C000` is slot 6 at `$FFA6`. Corrected in place, and it was the reasoning that nearly added a
  second register owner.
- ★ **Three self-inflicted shell errors**, all the same shape — a shell mechanism where a file
  belonged: a heredoc that hung the terminal (§2J, third time this session), backticks in a commit
  message executed as command substitution, and the block-move anchors above.

### 8 — Follow-up candidates

1. ★★★★ **Run `p3b_probe.bin`.** It assembles and is now built from code that a gate has actually
   exercised — the first time that has been true.
2. ★★★ **Window the compositor** (`co_rowset`, per row — the design is in T-P0-041 §3).
3. ★★★ **Gate the priority walk's windowing**, by giving `pic_probe`'s map a blocked priority plane.
4. ★★ **Re-time the renderer** on the built A′ against the model's 4.00%.
5. ★ **Sweep every runner for fault/ablation builds left in a clean artifact path** — `res_run.ps1`
   was fixed, `vm_run.ps1` was not (carried from T-P0-042 §8).

### 9 — User interaction during task

Four authorisations from Jay, each redirecting the work: *"yes do that"* (make p3b runnable),
*"measure both"*, *"yes"* (build A′), *"yes"* (close the gating gap). ★ Also *"what are you waiting
for?"* — a fair challenge: I was blocking on a gate run whose outcome byte-identity had already
established, and should have committed instead. And *"did you report"*, which prompted this report.

### 10 — Candidate(s) captured this task

`None.` ★ The two candidates from the T-P0-042 window are already in the pool; the material here —
"assembling is not evidence", and the defect signatures in §5 — is worth a row and has **not** been
written yet. Flagged rather than silently skipped.

### 11 — Commit

`5676912` (pushed to origin/wip; this report is committed and pushed after it).
