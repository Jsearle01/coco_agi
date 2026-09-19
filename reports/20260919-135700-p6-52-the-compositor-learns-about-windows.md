## Form B Report — T-P0-107 / P6.52 — The compositor learns about windows; and the first sprite anyone has seen
**Class:** integration (§4A).  wip.  Descends from `c2d322c`.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-19 13:57 (HEAD c2d322c, wip). Two `src/harness/` files and `memmap.inc` (comment +
assertion); three harness tools.

### 1 — Summary

★★★★★ **The compositor drew a sprite. Jay: *"it looks like the flags above the castle are
animating."*** ★★★ **That is the first cel this project has ever put on a screen** — 9,193 of them
match our own reference and none had been seen.

★★★★★ **`comp_probe.bin` is byte-identical — 967 B `39F5D105`** — and `comp` is 124/124, `cel`
9,193/9,193, the suite green.

★★★★★ **And the eye gate immediately found the next defect, which is not this one.** Jay: *"i still
don't see graham... but [it] don't look right."* **Three of the four staged sprites carry
priority 0**, which in AGI means *derive it from Y* — ★★★★ **and `MAP_PRI_BANDS` is declared in
`memmap.inc` and referenced by nothing at all.** §7.1.

### 2 — Files modified
- `src/harness/composite.s` — four access sites windowed; `co_rowvis`/`co_rowpri` become **offsets**
  under `PLANE_WINDOWED`; `COMP_PLANE_SAFE` and its fault flag.
- `src/harness/p3b_probe.s` — the assertion that the compositor is windowed-safe.
- `src/engine/memmap.inc` — ★★★★ **the AC-2 exemption stops claiming what it cannot check.**
- `harness/tools/` — `p3b_run.lua` (the `$FEF7` check, the staged-sprite table),
  `p3b_show.ps1`, `p3b_arms_check.ps1`.

### 3 — Pre-dispatch grep (C-13)

**§3(1)** Seven arms and every probe at P6.51's figures ✔. **`comp_probe.bin` 967 B `39F5D105`** —
the figure §1.3 turns on.

**§3(2) — every flat plane address in `composite.s`.** ★★★★ **Five sites, and one is not compiled
in `p3b`:**

| site | what it addresses | how often |
|---|---|---|
| `co_rowset` :419/:427 | forms both row bases | **once per row** |
| `co_opaque` :182 | priority **read** | per pixel |
| `co_put_visual` | visual **write** | per drawn pixel |
| `co_depth` :236 | priority **write** | per drawn pixel |
| `co_checkctrl` :448/:461 | priority **column walk** | per control pixel, × rows below |
| ~~`co_save`/`co_restore`~~ | both planes, by row | ★★★ **inside `ifdef CP_SAVE`; `p3b` does not define it** |

**§3(3)** `pic_core.s` calls `plane_vis`/`plane_pri` **per access** (six call sites);
`p3_restore_box` walks **slice/`within`/straddle** per row. ★★★ **Both shapes exist in the tree.**

**§3(4)** ★★ **`p3b` windows BOTH planes** — `FB_BASE` = `$C000` and `PRI_BASE` = `$A000`, 8 KB
each, against 26,880 and 13,440 bytes. `PRI_PACKED` halves the priority offset, so the two planes
straddle at different points.

### 4A — ★★★★★ The enumeration, and the mechanism chosen per site

★★★★★ **Per-access `plane_vis`/`plane_pri` at all four live sites. Not per-row.**

**Why not per-row, which is the cheaper shape.** A row base is formed once per row, but the span
actually touched is `[rowbase + basex, + w)` — up to 255 bytes — and **a span at an arbitrary offset
can straddle an 8,192-byte slice**, about one row in 32 for the visual plane and one in 64 for the
packed priority plane. ★★★ **`plane_vis` returns an address valid only inside its slice**, so
per-row would need `p3_restore_box`'s split-the-span shape **in the compositor's hot loop**, which
also holds the transparency, priority and control-line decisions. ★★★★ **That is a restructure of a
loop gated at 124/124 by a probe that is FLAT and therefore cannot exercise any of it.**

**Why per-access is affordable here.** `plane_vis` caches the current slice, so an access in the
same slice is a shift, a compare, a mask and an add — **no MMU write**. ★★★ **And `p3b`'s timing
figures were retired at P6.47** when its binary moved, so this probe is a correctness instrument.
★★ **Measured:** composite goes to **0.135 s/cycle, 15.7%** of the cycle, with the run completing
60 cycles in 52.4 emulated seconds.

★★★★ **The flat build's instruction ORDER is preserved at every site, not just its behaviour** —
`ifndef PLANE_WINDOWED` around the `ldx`, `ifdef` around the `leax`. Reordering two instructions
would have moved `comp_probe.bin`, and AC-2 is the criterion §1.3 turns on.

★★★ **`co_rownext` needed no change at all**: `+PRI_W` / `+PRI_STRIDE` advance an offset exactly as
they advanced an address. **That is what made this a seam and not a rewrite**, and `plane_win.s`'s
own header predicted it — *"co_rowset already forms a row base once per row."*

### 4B — Windowed-safe
`co_rowvis`/`co_rowpri` hold **flat offsets**; each site does `addd co_rowXXX` + `jsr plane_XXX`.
`co_ctrloff` likewise. ★★ **P6.33's warning (a count in B and a `ldd` that clobbers it) does not
arise**: every site reloads `co_curx` from memory and holds no count across the call.

### 4C — ★★★★★ The assertion, RED

```
src/harness/p3b_probe.s(2161) : ERROR : User Specified: "composite.s is linked with
PLANE_WINDOWED but is not windowed-safe -- co_rowset would form CP_VIS + y*160 as a flat
ADDRESS, and CP_VIS is an 8,192-byte window: row 100 lands at $FE80 beside the vector stubs
and row 167 wraps to $2860, inside this probe's code. memmap.inc's AC-2 exemption assumes
every windowed access goes through plane_vis/plane_pri; this asserts it for the compositor."
```
`-DCOMP_FAULT_FLAT_PLANE` suppresses `COMP_PLANE_SAFE`; without it the build is green.

★★★★★ **And `memmap.inc`'s exemption no longer claims what it cannot check.** It said the windowed
case *"cannot violate"* the overflow because every byte goes through `plane_vis`/`plane_pri`.
★★★★ **An exemption is an assertion about code that is not in the expression** — it quantified over
every subsystem touching a plane and nothing rechecked it when a second arrived. **What replaces the
claim is a symbol, not better prose.**

### 4D — ★★★★★ The eye gate

**Kingquest1, room 1 — the castle. The ego, Graham.** Jay's words:

> ***"so i still don't see graham but it looks like the flags above the castle are animating, but
> don't look right."***

| question | answer |
|---|---|
| 1. a figure at all? | ★★★★ **yes — the flags animate.** No ego. |
| 2. same silhouette flipped? | **not answerable** — the ego is the mirroring case and it does not draw |
| 3. animates without tearing? | animates; *"don't look right"* |

★★★ **Question 2 remains open**, and it is the one the row-scope mirroring needs. **It cannot be
asked until §7.1 is fixed.**

### 4E / AC-8 — What the blits draw, compared against what?

★★★★ **No such comparison exists, and building one is more than this task can carry.** `comp`'s
reference composites the same cels **from a flat plane into a flat plane**; `p3b`'s planes are
windowed and live in blocks reached a slice at a time.

**What it would take**, stated rather than hand-waved:
1. **Read `p3b`'s visual plane back through the window** — 4 slices, mapping each, 26,880 bytes.
   `p3b_run.lua` already does this for the message box's rect, so the mechanism exists.
2. **A staged scenario both sides can run** — `comp_stage.py` picks frames and stages cels; `p3b`
   composites whatever the VM's object table holds. ★★★ **The two do not currently name the same
   frame**, and making them would mean `p3b` accepting a staged sprite list.
3. ★★★★ **§7.1 fixed first**, or the comparison gates three sprites that do not draw.

### 5 — Verdict-time evidence (v0.7 §11)
```
AC-1  five sites enumerated; co_save/co_restore not compiled in p3b (ifdef CP_SAVE)
AC-2  comp_probe 967 B 39F5D105 -- BYTE-IDENTICAL
AC-3  comp 124/124 | cel 9193/9193 | pic 45/45 | vm 9/9 | res 1264/1264   ★ all fresh
AC-4  no stall; 60 cycles in 52.4 emulated s; $FEF7 = 52 5D 5C 5F 5E, unchanged from takeover
AC-5  CP_BLITS 104, vc_err 0, co_tested = 31,824 cel pixels -- it had never examined one
AC-6  assertion RED with -DCOMP_FAULT_FLAT_PLANE, green without
AC-7  Jay, live, RGB: the flags animate; no ego; "don't look right"
AC-8  no comparison exists -- what it would take is in §4E
AC-9  suite all green; mojibake clean; RED ($44) inside the rect: 0
AC-10 p3b 13,950 36B1A1C3 -> 13,950 9F232F39 (same size, different bytes -- pinned by HASH)
      region A's 3,072 recovered bytes still UNCLAIMED
AC-11 hal_sync x3 OK   reg-discipline 17/1/4   gen_vm_tables --check OK
```
**25.2:** N/A. **25.3: PASSED in part — Jay, live, RGB.** ★★★ **A sprite draws; the ego does not,
for a reason that is not this defect (§7.1).**

### 6 — Reactive deviations and route accounting
1. ★★★★★ **I chose per-access over per-row and the dispatch expected the opposite** (§1.2 pointed at
   `p3_restore_box`). The straddle argument is why, and **the cost was measured rather than
   assumed**: 15.7% of a cycle, on a probe whose timing figures are already retired.
2. ★★★★ **One of P6.51's two "observed" symptoms was misattributed, and it was mine.** I reported
   pixel data at the IRQ vector `$FEF7` as the compositor's doing. **Those bytes are present at
   takeover, before any compositing** — this run prints both and they are identical. The arithmetic
   and the fix stand; that evidence did not. §7.3.
3. ★★★ **Two instruments added after Jay's observation** — the `$FEF7` readback and the staged-sprite
   table — which is what turned *"i don't see graham"* into a named priority defect.
4. **ROUTE ACCOUNTING.** §4A–§4E answered. ★★★★ **The mirroring was not touched; `plane_win.s` was
   not touched; region A's bytes stay unclaimed.**

### 7 — Uncertainty flags

**7.1 ★★★★★ PRIORITY 0 MEANS "DERIVE IT FROM Y", AND NOTHING DERIVES IT.** The staged sprites:

```
[0] x=110 y=100 prio=0   view=0   loop=0 cel=0     ← Graham
[1] x=5   y=17  prio=15  view=97  loop=0 cel=2     ← the flags Jay saw
[2] x=147 y=161 prio=0   view=107 loop=0 cel=7
[3] x=124 y=115 prio=0   view=107 loop=0 cel=7
```

★★★★★ **Three of four carry priority 0.** `co_depth` compares the screen's priority against the
sprite's and rejects when the screen is nearer, so a sprite at 0 is rejected almost everywhere —
**`CP_BLITS` 104 of a possible 208 is exactly the two `view=107` entries never surviving**, and the
one at 15 draws. ★★★★ **`MAP_PRI_BANDS` is declared at `memmap.inc:310` — *"§2F.4: 168-byte LOOKUP,
never a computation"* — and `git grep` finds NO other reference in the tree.** The band table has
never been implemented, and `p3b_probe.s:1633` stages the raw `VMO_PRIORITY`.

**7.2 ★★★ *"don't look right"* is unresolved** and I did not chase it. The flags draw at priority 15
through a path where three of their neighbours do not, so the frame is incomplete by construction;
whether the flags themselves are also wrong is a separate question. ★★ **It needs §7.1 fixed and
then question 2 of the eye gate asked again.**

**7.3 ★★★★ P6.51 §7.1's `$FEF7` evidence is withdrawn** (§6.2). ★★★ **What remains is stronger than
what it replaced**: the wrap arithmetic, and the fact that windowing the compositor removed the
stall with nothing else changed.

**7.4 ★★★ The windowed compositor is gated by almost nothing.** `comp` is flat and cannot exercise
it; the evidence is "no stall", `co_tested` > 0, and a person seeing flags. ★★★★ **That is the same
shape that let the flat-addressing defect survive**, and §4E is the honest statement of what a real
gate would cost.

**7.5 ★★ `hal_frame` is 0 in the cel arm** — it does not define `P3B_IRQ`, which is a
text-configuration flag. Pre-existing; noted because the stall dumps mention it.

### 8 — Follow-up candidates
1. ★★★★★ **Priority banding** (§7.1) — `MAP_PRI_BANDS` exists as an address and nothing else.
   **Graham does not draw until it does.**
2. ★★★★★ **Then ask eye-gate question 2** — is the ego the same silhouette flipped. ★★★ **The
   row-scope mirroring has never been seen by a person.**
3. ★★★★ **A gate for the windowed composite** (§4E, §7.4), with the three steps costed.
4. ★★★ *"don't look right"* (§7.2) · region A's 3,072 bytes · the title-screen scroll.

### 9 — User interaction during task
1. ★★★★★ Jay ran the eye gate: ***"i still don't see graham but it looks like the flags above the
   castle are animating, but don't look right."*** **That one sentence is AC-7, and it located
   §7.1** — a report of what was on the screen, which is what the question asked for this time.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-19-an-exemption-is-an-assertion-about-absent-code.md`
- `seeds/AGI/live/2026-09-19-the-first-thing-a-revived-path-shows-you-is-the-next-defect.md`

### 11 — Commit
`e653e0a` (pushed to origin/wip before this report).
