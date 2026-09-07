# AGI Interpreter for the Tandy Color Computer 3 — design spec v1.2

**Status: draft for discussion.** Every AGI figure is from ScummVM's `engines/agi` source or the AGI
Specifications, cited. Every CoCo3 figure is from the sibling ports' measured findings, cited. **Nothing
here has been measured on AGI running on hardware.**

**Changes from v1.1** (2026-09-06) — ★★★★★ **fifteen tasks. P3b is CLOSED, the parser is ported and
gated, and several v1.1 figures are WITHDRAWN.**

- ★★★★★ **§6.2 — the fill is 2.832 s** (packed, windowed, shadow-blitted), and ★★★ **the renderer is
  53/53 on BOTH PLANES.** **v1.1's divergence figures measured ONE PLANE and are withdrawn** [L-88].
- ★★★★★ **§7.1 — compositing is 0.02107 / 0.03929 s per cycle at 2 / 4 sprites.** ★★★★ **v1.1's
  53% / 106% are WITHDRAWN — overstated 3.78× by a harness defect** [AD-76].
- ★★★★★ **§3.6 PARTIALLY REVISED — the picture renders into a SHADOW BUFFER and is blitted on
  completion.** ★★★ **The room appears rather than draws, matching the oracle's own architecture.**
  ★★ **Save-under is untouched; the compositing loop stays single-buffered and that question is open.**
- ★★★★ **§3.2 — planes are addressed THROUGH THE WINDOW, not flat**, and the priority plane is packed
  4 bpp. **Both were latent defects that shipped byte-identical gates** [AD-88, AD-121].
- ★★★★★ **§5 — the VM is 15.7 cyc/s on KQ1 after the LOGIC cache and the timer division came out; KQ3 is
  9.4 against a corpus that asks for 10.**
- ★★★★★ **§8 NEW — the parser: `WORDS.TOK`, tokenising and `said()`, ported and gated at 23,328 cases
  across five titles.**
- ★★★★ **§9 — the ranking is re-taken.** The fill is no longer rank 1 by urgency.

**Changes from v1.0** (2026-08-29) — ★★★ **all four ported subsystems are now on the 6809 and gated.**

- ★★★ **§6.2 — the fill is 2.746 s median**, 75.3% below the 11.102 s first measured. **Restructured, not
  tuned:** every counter invariant, cycles per boundary test down 3.25×. **AD-45's stack blast measured
  −0.1% and is CLOSED, not adopted.**
- ★★★ **§5.8 NEW — the VM is gated on NINE titles**, 500 cycles each, empty exclusion set.
- ★★★ **§7.1 NEW — compositing is gated and its cost is a FLOOR, not a figure.** ~53% of a second at two
  sprites, ~106% at four — **and the sample was ATTRACT MODE: the ego was composited zero times in 1,680
  frames.** ★★ **§3.6's single-buffer decision reopens but CANNOT be decided on this data.**
- ★★ **§4.2 — the resource layer is gated at 1,264 resources**; fetch is 1,022 cycles + 11.98/byte.
- ★★ **§8.10 NEW — the clock is 1.789390 MHz, calibrated by SLOPE** across five block counts. A single
  block cannot separate the loop from its harness.
- **§2.2 — the palette is verified**: 16/16 registers hold the intended value, bits 7–6 masked on
  readback.

**Changes from v0.9** (2026-08-26, from T-P0-011 — ★★★ **the first task with 6809 code on hardware**)

- ★★★ **§6.5 NEW — first pixels, gated.** One AGI PICTURE interpreted by 6809 code on a real CoCo3 in
  320×200×16; **both planes byte-identical to the oracle**, 26,880 bytes each.
- ★★★ **§6.6 NEW — three defects the port surfaced**, none of which offline Python could have found:
  **the AGI canvas is visual=15 / priority=4, not black**; **`rel_line` deltas are SIGN-MAGNITUDE**; and
  the probe must set `S` itself.
- ★★ **§8.9 NEW — a byte-identical buffer proves nothing about the screen.** AC-6 passed and the display
  was still wrong. **The byte gate and the eye gate are not redundant.**
- **§1A — `coco_agi` is the third participant in the HAL sync mesh**; mode 2 lives in its own
  `hal_globals.s` and touches no shared file.

**Changes from v0.8** (2026-08-26, from P5.1)

- ★★★ **§8.8 NEW — a SECOND oracle nondeterminism, and the state gate is amended.** Sound end-flags are
  set from **unsynchronized background threads** [`sound.cpp:169`] and fire at a cycle that varies run to
  run (186/185/185/184). ★★ **Two consecutive runs agree**, which is why P4.1's determinism work missed
  it — the L-30 trap recurring in a subsystem that work never exercised.
- ★★★ **§5.7 NEW — P4.1's flag attribution was CO-OCCURRENCE, not causation.** *KQ1's flag 20 was never
  an animation flag; it is a sound end-flag.*
- ★★ **§7 — VIEWs are oracle-verified**: **6005/6005 cels byte-identical across eight games**, mirroring
  included. The two genuine animation flags close (KQ2 33, KQ3 221).
- **§3.6 — the save-under backing-store bound is measured**, from P5.1's cost model.

**Changes from v0.7** (2026-08-25, from P4.1 and P4.2)

- ★★★ **§8.6 CORRECTED — the oracle determinism claim was established by a check that could not
  fail.** T-P0-003's verification compared two IDLE runs; the pacing gate pins cycle N to wall time
  N/40 on an unloaded machine, so an idle pair is byte-identical and *looks* deterministic. **Under
  load, vars 11/72/73 diverge.** Now fixed at source — **the exclusion set is EMPTY.**
- ★★ **§5.5 NEW — the VM is oracle-verified**: all 256 variables matching every cycle across three
  titles; one flag per title, all animation-completion flags awaiting P5.
- ★★ **§5.6 NEW — the dispatch table is BUILT, not loaded**, and mutates by version, platform, gameID
  and feature flags. Measured: version-driven mutations fire for **zero** pinned rows, feature-driven
  for **21, all fanmade.**
- **§8.7 NEW — the host toolchain fact was wrong for four tasks.** The oracle now builds natively under
  MinGW-w64; **WSL is dropped from the project.**

**Changes from v0.6** (2026-08-25, from T-P0-006 and T-P0-007)

- ★★★ **§11.1 RE-CLOSED, and the project's purpose stated plainly** (§1.2a). Running the CoCo3
  conversions would run **degraded** content — KQ1's conversion drops **26 of 48 sounds**. The point is
  the PC originals on better hardware.
- ★★ **§6.2 — the flood fill's MEMORY fear is measured away.** Peak seed-stack **102 entries = 204 bytes
  on a 6809**, median 7, over 498 pictures. **§9 rank 1 is now about TIME, not memory.**
- ★★ **§6.4 — the both-screens fill rule verified by FALSIFICATION**: rebinding the bound to the priority
  screen breaks **107 of 390** pictures.
- ★★ **§8.5 — a known oracle defect.** ScummVM mis-loads `Kingquest1` SOUND 34–37 from an **uninitialised
  stack header**; our refusal is more correct.
- **§4.2 — the three axes are recorded per row** in `games/manifests/corpus-classification.tsv`, each
  value carrying how it was established.

**Changes from v0.5** (2026-08-25, from T-P0-005's verdict — the resource layer is now
oracle-verified at **2410/2410**, so its findings outrank every prior inference about AGI formats)

- ★★★ **§11.1 REOPENED.** The CoCo3 ports are **V2-directory / V3-VOLUME hybrids** — 7-byte headers,
  LZW-compressed — not v2 as v0.4 and v0.5 both claimed. **`KQ3/Original` is the only V2-volume build in
  the entire CoCo3 corpus.** The v2-only ruling rested partly on a premise that is false [backlog X-28,
  AD-28].
- ★★ **§9 — LZW on a 6809 is demonstrated, not speculative.** Sierra's 1988 CoCo3 interpreter
  decompresses it, on the target machine, in the artifact we hold.
- **§4.2 gains the volume-header formats** — V2 five-byte, V3 seven-byte with `clen` — now read from the
  oracle rather than from the Specs.
- **§8.4 — the corpus is three populations, not two**, and most CoCo3 rows are out of scope for v2
  byte-comparison.

**Changes from v0.4** (2026-08-24, from T-P0-004's verdict — all three are executor measurements
overriding Orchestrator figures)

- ★★ **§8.1's tier-2 restoration is SCOPED.** Only **King's Quest III and Leisure Suit Larry** have
  `Original/` media. The other five titles are community conversions running Sierra's interpreter —
  **evidence about the interpreter, not about a Sierra release** [backlog X-26].
- ★★ **§4.5's duplication figures are corrected and now name their variant.** KQ3 **51.4%** on
  `Original` but **20.3%** on `Floppy 360K`; LSL **14.8%**, not 21% [X-25]. ★ *A duplication number
  without its variant is not a number* [L-24].
- **§4.5 media described correctly**: KQ3's `Original` is **five disks × two sides**, not ten disks.
- **§4.8 gains the interpreter-bytes exclusion** — `CMDS/`, `MODULES/`, `OS9Boot` are code our port
  replaces, ≈55 KB per disk, the same reasoning that removed `AGIDATA.OVL`.

**Changes from v0.3**

★★ **v0.4 is the first revision written against measured CoCo3 evidence rather than inference.** Seven
CoCo3-hosted AGI titles were acquired and parsed, including **Sierra's own shipped King's Quest III and
Leisure Suit Larry disk sets and Sierra's CoCo3 AGI interpreter itself** [backlog I-17].

- **§2.1 — display is 320×200×16** (Jay, tier 1). AGI's exact layout, at zero additional block cost.
  Resolves the row-24 finding rather than accommodating it. [AD-01]
- **§4 restructured around DEMAND STREAMING.** All seven CoCo3 titles exceed one floppy; four exceed the
  ≈376 KB resident ceiling; KQ4 exceeds it 3.7×. **The RAM-disk is demoted to the degenerate case.**
  [AD-21, M-01a]
- **§4.5 — a three-tier residency model, taken from Sierra's own disk layout**, with measured tier sizes.
  [AD-22]
- **§5 — 203 opcodes, not 319.** The value was right; its scope was not. [L-14]
- **§8 — tier 2 restored.** Sierra's CoCo3 interpreter is a runnable comparison target. [L-17 revised]
- **§1.4 — the HAL is synchronised, not shared**; §1.4.3's register rule is the four-part rule.
- **§11 — one design decision remains open: does this project target AGI v3?** [M-12]

**Corrections carried in** (backlog §2): the pre-render hypothesis for KQ3's ten sides was wrong — it is
**51% duplication** [X-13]; §1.1's SCI justification was factually false [X-15]; AD-01's original
reasoning checked the play area and not the text model [X-14].

---

## 1. Scope and relationships

### 1.1 Target

**AGI version 2 and 3 games.** King's Quest I–III, Space Quest I–II, Leisure Suit Larry 1, Police
Quest 1, Manhunter, Gold Rush, plus the fan-made library.

**Not SCI** — ★ **and v0.3's stated reason was wrong** [backlog X-15]. SCI's reference type is already
segmented (`reg_t` = `{SegmentId, uint16 offset}`, with direct access forbidden), so flat pointers were
never the model. **The real obstacle is allocation lifetime: AGI's state is fixed and preallocated — 256
variables, 256 flags, fixed tables — while SCI creates and destroys objects at runtime**, which needs a
memory manager across banked physical memory rather than a fixed table set. SCI0 also carries a third
full-resolution screen (control) and larger, multiply-resident scripts.

**Machine: CoCo3, 512 KB, CoCoSDC or floppy.** 128 KB is addressed in §3.7.

★ **Sierra shipped two AGI titles for the CoCo3 — King's Quest III and Leisure Suit Larry 1 — and both
required 512 KB.** 512 KB as the baseline is not a regression from the originals.

### 1.2a ★★★ What this project is FOR — and why the CoCo3 conversions are not the target

**Sierra shipped two AGI titles for the CoCo3, and the community converted seven more. Those conversions
are what this project improves upon — they are not an input format.**

★★ **Measured** [`coco3-files.tsv` vs `pc-agi.tsv`]: **CoCo3 King's Quest I carries `snddir` 66 bytes =
22 sound slots. The PC release carries 144 bytes = 48.** The conversion **dropped 26 of 48 sounds.**
`object` (331) and `words.tok` (3,144) are byte-identical on both sides — **the vocabulary and object
table survived; the sounds were cut.** KQ3 shows the same shape: `words.tok` 4,463 against the PC's
5,657.

> **The purpose is to run the ORIGINAL PC resources on a CoCo3 — full sound complement, full vocabulary,
> undegraded content — at 320×200×16 with the exact EGA palette (§2.2), three-part harmony on an
> SN76489A where present (§5.3), and asynchronous audio (§5.2).**

★★★ **Therefore supporting V3 VOLUMES to read the CoCo3 conversions would be supporting the degraded
artifact** — reproducing Sierra's 1988 compromises on better hardware, which is the worst of both. **A
user who has the CoCo3 files can obtain the PC ones.**

### 1.2 What this is not

**Not a port.** Prince of Persia is one program reproduced faithfully against one oracle. **This is a
machine that runs dozens of games**, each exercising it differently. That difference changes the
verification method (§8) and it should not be papered over.

### 1.3 ★★ Prince of Persia is a sibling project and the architecture oracle

**The POP port has already solved, measured, and hardware-gated most of the CoCo3-specific problems this
interpreter will hit.** Its findings are cited throughout by backlog entry. **Before deriving any
CoCo3 architectural answer from first principles, check whether POP already measured it.**

**Where POP is authoritative:**

| question | POP's answer | where |
|---|---|---|
| GIME mode byte counts | HRES sets bytes/row, CRES sets pixels/byte, independently | `gfx.s:306-312` |
| MMU window cost | **7 cycles**, one register, no interrupt mask needed | §5.224 |
| Two-register remap under mask | 40 cy body / 48 with `jsr` | §5.224 |
| Page flip | `std $FF9D` — one 16-bit VOFFSET write | `gfx_sw_store` |
| Save-under is per buffer | *"an erase must restore what was saved INTO THAT BUFFER"* | `char_draw.s:107-110` |
| Capacity is measured in blocks, not bytes | a cel cannot straddle a boundary | §5.225 |
| Residency ≠ window occupancy | the distinction that took five dispatches | §5.222 |
| **Disk cost model** | **0.43 s motor / 0.20 s call / 1.24 s track** | **P5.13** |
| **DMK sequential vs JVC** | **JVC costs 2.5×** | **P3.6, idioms §29** |
| 512 KB free-block derivation | 64 − 12 mapped + 4 tails = **56** | §5.262 |
| Batching beats moving reads | 16 spin-ups ≈ 6.9 s | §5.271 |
| Register-access measurement | the four-part rule; a literal grep is invalid | **P5.17** |

★ **POP's standing invariants apply unchanged.** The ones most likely to recur here:
- *A sum is not a residency requirement.* **v0.1 committed exactly this error** — see §3.1.
- *Capacity in bytes is not capacity in allocation units.*
- *Sampling finds state; only a write tap finds events.*
- *A property of one input is not a property of the code.*
- *Check both ends of every pipe.*
- ★★ **NEW — *verify the claim at the right ref.*** Three successive versions of the HAL constraint were
  wrong, one of them because POP's `wip` was compared against Karateka's `main`, a month stale. **A
  measurement of a stale ref is not a measurement of the current regime.**

**Where POP is NOT authoritative:** anything about AGI's formats, timing, or semantics. POP's animation
rate, its cel model, its two-format ruling and its phase/facing findings are properties of *its* content.

### 1.4 ★★ The HAL constraint — three copies, held identical by tooling

**v0.2 described the HAL as a shared file. It is not.** It is one kernel in three copies, kept identical
by `harness/tools/hal_sync_check.py`, which runs as a pre-build step and **fails the build on substantive
drift.**

**Measured 2026-08-23** (POP `wip` `c30969c`, Karateka `wip` `072ddcf` — both current, hours apart):

| | `src/hal/coco3-dsk/gfx.s` | `hal_sync_check.py` |
|---|---|---|
| POP | 1,689 lines | `b6819237…` |
| Karateka | 1,695 lines | `b6819237…` (identical) |

#### 1.4.1 The contract

`SHARED` is ten files plus the script itself:

```
src/hal.inc
src/hal/coco3-dsk/{sys,time,irq_vbl,gfx,input,sound,file,mem,disk_read}.s
harness/tools/hal_sync_check.py          <-- checks itself
```

`PROJECT_LOCAL = {'src/hal/coco3-dsk/hal_globals.s'}` — the only sanctioned per-project file.

`normalise()` removes the sanctioned divergences: EOL, comments, whitespace runs, and a dormancy guard's
**own directives — never its contents.** Exports are compared as a **set**, independent of placement.

★ **The script is in its own `SHARED` list and derives the sibling path from `SIBLINGS` rather than a
per-repo constant.** That is what keeps the copies byte-identical: a repo cannot quietly configure its
own check.

#### 1.4.2 ★★ A third client makes this stricter, not looser

**AGI is 16-colour. POP is 4-colour with the mode service. Karateka is 4-colour and does not define
`HAL_GFX_MODE_SERVICE` at all.**

> **Every AGI addition to a shared file must assemble in a tree where the mode service is OFF.**
> `ifndef` fallbacks are **mandatory, not stylistic.**

★ **P5.18 found this twice: a one-line change referencing `HAL_gfx_cur_words` broke Karateka's build.**

And a guard is not an escape hatch. `normalise()` drops a guard's directives but **compares its
contents**, so guarded AGI code must still be substantively identical in all three trees. A guard is the
mechanism that lets *identical source* assemble *differently* — not a licence to diverge.

**Consequences:**

1. **Additive-behind-a-guard is the only correct style**, for a real reason: it is what lets one change
   land in all three trees at once.
2. **A change to a shared file lands in every repo or in none.** The script checks itself, so editing it
   in `coco_agi` alone drifts the other two and blocks both their builds.
3. **New AGI-only exports go in `hal_globals.s`** (already `PROJECT_LOCAL`) or arrive everywhere
   together. An AGI-only export in a shared file is drift even when guarded.

#### 1.4.3 ★★ Register discipline — the four-part rule, not a literal grep

**v0.2 specified `grep -rnE '\$FF[89ABD][0-9A-F]' src/engine/`. That is the instrument P5.17
discredited**, wrong in two directions at once: it counts register addresses quoted in **comments**
(85 of POP's 117 hits) and **misses every access through an `equ` alias** — `CEL_MMU`, `BANK_MMU`,
`SAM_SLOW/FAST`, `PALETTE`, `msys_player`'s `FF90`–`FF95` — **which are the majority of the real ones.**

★ **`PALETTE` is on that alias list**, so a literal grep would miss exactly the palette accesses §2.3
depends on being owned by the HAL.

**The rule:** a line counts only if it is *not a full-line comment, not the inline half after `;`, not an
`equ` definition, and carries a load/store mnemonic* — **with aliases resolved to their register,
including `+n` offsets.**

Re-measured under it: **POP 59, Karateka 8** (v0.2's 109 and 18 were the literal-grep figures).

★★ **"Engine touches no registers" is not the goal.** P5.17 found **71% of POP's accesses are hot** —
`msys_player`'s 23 are inside the FIRQ handler, and routing those through a `jsr` is the worst conversion
available. **The goal is ONE SANCTIONED OWNER per register.** POP's convertible tier was nine, not 109.

> **The HAL owns `$FF90`–`$FF9F` (GIME/MMU/SAM) and `$FFB0`–`$FFBF` (palette).**
> **Harness probes are allowlisted by explicit filename, never by pattern**, so adding one is a visible
> act.

★ **Install this on the empty repository, before the first engine file.** It costs nothing now and
retrofits expensively — and if it ships with the wrong instrument, the project inherits a false sense of
conformance rather than the real thing.

#### 1.4.4 ★ Inherited defects

**`HAL_gfx_clear` is the worked example.** It took its **base** from `page_register` (`$8000`/`$C000`)
*and* its **length** from `GFX_FB_WORDS` (`$1E00`, 15,360 bytes) — **both 4-colour assumptions.** In
16-colour there is **one 30,720 B buffer across all four blocks, and `$C000` is the bottom half of the
only page**, so a length-only fix clears the right number of bytes at the wrong address.

★★ **The defect was latent in Karateka too** — identical body, identical mode table — unreachable only
because Karateka never selects mode 1. **It was fixed in both trees as one change**, Karateka `wip`
`072ddcf`: *"HAL_gfx_clear asks the mode for its geometry (POP P5.18) — no change to karateka's bytes."*

**AGI inherits it already correct.** The standing lesson: ★ *do not assume a routine is mode-aware
because a neighbouring one is* — `gfx_clear_window` twenty lines above was correct the whole time.

### 1.5 Repository and build

| | |
|---|---|
| repo | `coco_agi` (`https://github.com/Jsearle01/coco_agi`) |
| branch | `wip`, per §2E |
| local path | `C:\Projects\coco_agi` |
| build mode | **linked**, as POP (Karateka is absolute) |
| siblings | `C:\Projects\POP3_port`, `C:\Projects\karateka_coco3` |

★ **`hal_sync_check.py` resolves participants by directory name** — `parents[2]`, then
`here.parent / sibling_name`. **The directory must be named `coco_agi` and must sit adjacent to both
siblings**, or the check prints a warning and returns 0. **The first post-commit verification is that it
reports `[hal-sync] OK` naming both siblings, not that it skips.**

★ The repo was renamed from `coco-agi`; **GitHub keeps the old URL as a permanent redirect**, and a clone
made from it lands in a directory called `coco-agi` — which the check would silently skip.

**Joining `SHARED` requires three edits to the script, landed in all three repos simultaneously:**
`SIBLINGS` from a 1:1 dict to a participant list with "everyone but me" derived; `PROJECT_LOCAL` from a
flat set to a per-repo mapping; graceful skip made per-pair, so a partial checkout compares what is
present and never blocks.

---

## 2. The display

**AGI's play area is 160×168, with a separate 160×168 priority screen** [`graphics.h:29-31`,
`graphics.h:116-117`]. Pictures are **vector drawing commands**, not bitmaps [AGI Specs §7].

### 2.1 ★★ 320×200×16

**AGI's own display was 320 physical pixels: graphics at 160 logical pixels doubled horizontally, text at
320 native.** Status line, input line and message windows are **40 columns**, which needs an 8-pixel font
at 320. At 160 physical you would need a 4-pixel font.

**So 320×192×16 is not a compromise — it reproduces the original arrangement.**

From the GIME reference, via POP's own mode table [`gfx.s:306-312`]:

| mode | bits/px | px/byte | bytes/row | ×192 | ×200 | blocks |
|---|---|---|---|---|---|---|
| **320×N×16** | 4 | 2 | **160** | 30,720 | **32,000** | **4** |
| 320×192×4 (POP's) | 2 | 4 | 80 | 15,360 | — | 2 |
| 160×192×16 | 4 | 2 | 80 | 15,360 | — | 2 |

★ **Note the collision: 15,360 is both POP's 320×192×4 framebuffer and a 160×192×16 one.** HRES sets
bytes per row and CRES only changes the interpretation. **Always name the mode when quoting the size.**

**Line count is 200** [backlog AD-01, Jay tier 1]. ★★ **200 lines costs ZERO additional blocks** —
32,000 B needs 3.91 blocks against 30,720's 3.75, and both round to 4 with 768 B spare.

**That gives AGI's exact layout:** row 0 status, rows 1–21 play (21 × 8 = 168), rows 22–24 bottom —
matching ScummVM's `FONT_ROW_CHARACTERS 25` model [`text.h:68`].

★★ **This resolves a measured problem rather than accommodating it.** At 192 lines only two bottom text
rows exist, and **136 of 150 pinned corpus titles (91%) address a text row above 23 before the player does
anything** — a boot-time lower bound, not a ceiling. Row 24 is reachable four ways, all driven by game
data rather than by the engine, and ScummVM's source names a shipped game that uses it (*Residence 44*,
`op_cmd.cpp:2149`). **v0.3's 192-line reasoning checked whether the play area fit and never checked
whether the text model did** [backlog X-14].

★ **Opens D-13:** the HAL mode table carries `320x192x16` with `GFX_MODE_MAX equ 1` in both siblings.
AGI needs a **new mode 2**, added at P3 across all three trees behind an `ifndef` fallback — **added, not
edited**, because editing mode 1 is the change P5.18 caught twice.

### 2.2 ★★ Palette — a transcription, not an eye decision

**v0.2 said the GIME/EGA mapping was "close and not exact" with "real freedom." That was wrong.**

**The GIME's RGB palette register is `R1 G1 B1 R0 G0 B0` — two bits per channel, 64 colours.** EGA's
output is also two bits per channel, 64 colours. **They are the same colour space**, so all sixteen EGA
entries are exactly representable. This is POP's palette situation, not its opposite: a transcription
with no freedom in it [§5.174].

**Register values** (`$FFB0`–`$FFBF`; **orchestrator arithmetic, unverified on hardware**):

| # | EGA name | R,G,B (0–3) | value |
|---|---|---|---|
| 0 | black | 0,0,0 | `$00` |
| 1 | blue | 0,0,2 | `$08` |
| 2 | green | 0,2,0 | `$10` |
| 3 | cyan | 0,2,2 | `$18` |
| 4 | red | 2,0,0 | `$20` |
| 5 | magenta | 2,0,2 | `$28` |
| 6 | **brown** | 2,1,0 | `$22` |
| 7 | light grey | 2,2,2 | `$38` |
| 8 | dark grey | 1,1,1 | `$07` |
| 9 | bright blue | 1,1,3 | `$0F` |
| 10 | bright green | 1,3,1 | `$17` |
| 11 | bright cyan | 1,3,3 | `$1F` |
| 12 | bright red | 3,1,1 | `$27` |
| 13 | bright magenta | 3,1,3 | `$2F` |
| 14 | yellow | 3,3,1 | `$37` |
| 15 | white | 3,3,3 | `$3F` |

**Decode cross-check:** the GIME boots with all palette registers at `$12` = `010010` → G1=1, G0=1, all
else 0 → full green, nothing else. Consistent with the documented boot colour.

★ **Entry 6 is the one that matters.** EGA brown is (170, 85, 0) — red at level 2, green at level 1,
blue off. **It is the only entry that is not a uniform low-bits or high-bits pattern**, and a naive
"duplicate the CGA bit" conversion yields dark yellow. AGI uses brown constantly for wood, dirt and
interiors.

**Composite is a different problem and is deferred.** In composite mode the same register means
`I1 I0 P3 P2 P1 P0` — intensity and phase, 16 colours × 4 shades — which has no relationship to RGB222.
The table above produces garbage on composite. **A composite table is a second 16-byte table and a
genuine eye decision.**

**Design rule, which makes composite a later data change rather than a rewrite:**

> **The palette is a 16-byte table loaded at init. Never inline a palette constant at a write site.**

★ §1.4.3's four-part check enforces this — but only because it resolves the `PALETTE` alias. **A literal
grep would not.**

★ **Selection must be a user setting, not a detection.** Both outputs are always driven, so the machine
cannot tell what is plugged in. Boot-time toggle, persisted. This is POP's *detection must fail toward
asking* [§5.277] applied to a case where detection is not even possible.

---

## 3. Memory

### 3.1 ★★ Residency is not window occupancy

**v0.1 listed 44,160 bytes of buffers and implied they must all be CPU-visible. That was wrong, and it is
POP's signature error** — the one that took five dispatches to separate [§5.222].

**Physical allocation and CPU-window occupancy are different quantities over different extents.**

### 3.2 Physical allocation

| buffer | resolution | bytes | blocks |
|---|---|---|---|
| framebuffer (displayed) | 320×200, 16 colours | 32,000 | 4 |
| priority | 160×168, 4bpp | 13,440 | 2 |
| **subtotal** | | **44,160** | **6** |

Plus interpreter, stack, current LOGIC, 256 variables + 256 flags, object and view tables, cel cache,
sprite backing store — **call it 3–4 blocks.**

**On 512 KB that leaves ≈46 of 56 free blocks — ≈376 KB — for the resource cache** (§4.5).

### 3.2a ★★★★★ Planes are addressed THROUGH THE WINDOW, and priority is packed

★★★★★ **Two latent defects shipped byte-identical gates, both the same class: code indexing a plane FLAT
while the map gives it an 8,192-byte SLICE.**

★★★★ **`FB_BASE $C000 + 26,879 = $128FF` wraps to `$28FF`, inside the code region** — **the renderer
overwrote its own code and the CPU ended up executing the seed stack** [AD-88]. ★★★ **The same assumption
survived into `ff_store_pri` and was found again two tasks later** [AD-123].

> ★★★★★ **FITTING and REACHING are different questions. A byte counted resident is not a byte
> addressable** [L-69].

★★★ **The priority plane is packed 4 bpp (13,440 B), and that is a REQUIREMENT, not a trade-off** —
★★★★ **without it the draw phase is over by 6,914 bytes and does not fit at all** [AD-95, L-64].

★★ **Windowing cost 6.4% of the render**, and ★★★ **the fill's byte-pointer walk survives untouched:
`fc_pbase` selects the test plane once per span and 70.3% of calls test the visual plane** — ★ **only the
6.4% priority walk became a nibble walk.**

### 3.3 The priority screen stays at 160

**Priority is a property of the logical pixel** — AGI's own priority screen is 160×168
[`graphics.h:117`]. Doubling it would store every value twice and buy nothing, since the sprite test
reads it once per logical pixel.

**Lookup during compositing is `x >> 1`.** One shift, against 13,440 bytes saved and a buffer that is
correct rather than merely smaller.

### 3.4 What is mapped, and when

| phase | mapped | frequency |
|---|---|---|
| **VM execution** | **nothing but the interpreter** | most of every cycle |
| picture draw | one framebuffer slice + one priority slice | once per room |
| sprite composite | one framebuffer slice + one priority slice | per cycle, per sprite |

★★ **The VM runs with no buffer mapped at all.** Opcode dispatch, variables, flags, LOGIC — none of it
touches a pixel. **That is the bulk of the work and it has the full address space.**

★ **The GIME scans the framebuffer from physical memory** — the video address registers point at
physical blocks and the CPU window is irrelevant to display. **The CPU needs a window only when it
writes.**

**And writes are local.** A sprite is a few rows; a picture line is one row. **An 8 KB slice is 51 rows
at 160 bytes/row** — map it, draw what falls inside, remap on crossing. POP measured that remap at
**7 cycles** [§5.224].

**Design rule: the interpreter declares which pair it needs before entering a phase, and the phases are
disjoint. Get this wrong and it becomes a remap per scanline.**

### 3.5 Priority cannot be discarded

AGI composites against per-pixel depth: a sprite pixel draws only where its priority is ≥ the priority
screen's value there. **That test is per pixel, every cycle, for every sprite.**

**Default bands are 14 bands of 12 rows** — `for priority 1..14, for step 0..11`, values below 4 clamped
to 4 [`graphics.cpp:1295-1303`]. 14 × 12 = 168 exactly. `setPriorityTable` lets a game override
[`:1305-1313`]. ★ **The banding is a lookup, not a computation** — a 168-byte table replaces a divide per
pixel.

### 3.6a ★★★★★ PARTIALLY REVISED — the picture renders into a SHADOW BUFFER

**Jay's ruling, 2026-09-06, taken on the oracle argument rather than the aesthetic one.**

★★★★★ **The picture render happens ONCE PER ROOM, so a shadow buffer for the RENDER ALONE fixes the
visible draw and does not touch save-under** — ★★★ **sprites still composite onto the visible plane with
§3.6's existing restore logic.**

★★★★ **This is what Sierra did.** `$E1B1` is a format conversion emitting an **already-rendered buffer**
— 24 cycles/pixel, **zero comparisons on pixel data** [T-P0-019]. ★★★ **Render then present is the
original's architecture, and Jay's raster observation is what led to finding it.**

★★ **Cost: +0.2169 s per room on four previously-unused blocks, against a 2.8 s render** [AD-117].
★ **The room appears rather than draws.**

> ★★★★ **STILL OPEN and still Jay's: double-buffering the COMPOSITING LOOP.** ★★★ **§3.6's objection was
> save-under complexity, not memory — *"on 512 KB a second framebuffer is 4 blocks of 56 — free"* — and
> that objection stands against the compositing loop, which erases.**

### 3.6 ★ Single-buffered, and why

**Recommendation: one framebuffer, VBL-synced, with save-under.**

**Memory is not the reason.** On 512 KB a second framebuffer is 4 blocks of 56 — free. **The flip is
free too**: `std $FF9D`, one 16-bit VOFFSET write.

**The cost is save-under state, and POP found it the hard way.** `char_draw.s:107-110`: ***"PEEL IS PER
BUFFER… an erase must restore what was saved INTO THAT BUFFER."*** Buffer A holds last frame; B holds the
one before. **Each buffer needs its own backing store and its own restore list** — double the
bookkeeping, and a bug class where a sprite trails on alternate frames only.

**And the benefit is smaller here than in POP.** AGI runs at roughly 5 cycles per second with a few small
sprites; a sprite jumps several pixels between frames, so a tear is a fraction of the motion rather than
a visible band. **POP needed double buffering for a full-screen character at 9.5 fps with a peel that
must not flicker. This is a different problem.**

★ **And it is cheap to revisit** — the second buffer is four spare blocks and the flip is one
instruction. **The version that might be good enough is also the version that is easy to abandon.**

**The alternative to save-under — recompositing from a pristine picture each cycle — is a 30,720-byte
copy per frame**, roughly a third of the CPU at AGI's rate. Not worth it.

### 3.7 128 KB — SDC only, and marginal

**16 blocks, 4 for framebuffer, 2 for priority, 3–4 for the interpreter — ≈6 blocks, 48 KB of cache.**

★★ **That forecloses the RAM-disk (§4.5), so 128 KB is streaming-only, which means SDC-only.** On floppy,
streaming is constant mid-game seeks and swaps — unplayable.

**128 KB survives as a stretch target on SDC with a minimal resource cache. Nothing else in §10 depends
on it.**

★ **Single-buffering keeps even that alive; double-buffering rules it out immediately** (10 blocks
against 8). **A second reason to start single-buffered.**

---

## 4. Resources and storage

★★ **This section is rewritten in v0.4 against measured evidence from seven CoCo3-hosted AGI titles,
including Sierra's own shipped disk sets** [backlog M-01a, AD-21, AD-22].

### 4.1 ★★ The originals run unmodified — demonstrated, not assumed

> **The user supplies original Sierra or community game files and they run.**

★★ **This is no longer a design premise. It is an observed fact about a 1988 interpreter.** Sierra's
CoCo3 AGI engine — `CMDS/Sierra` plus `MnLn`, *"AGI (c) copyright 1988 SIERRA On-Line, CoCo3 version by
Chris Iden"* — runs **seven titles, five of which Sierra never shipped for the CoCo**: KQ1, KQ2, KQ4,
Police Quest 1 and a fan-made KQ6, alongside the official KQ3 and LSL. The resource files are stock AGI
v2, differing from the PC releases only in filename case because OS-9 is case-sensitive.

**On SDC this is literal.** Copy the game directory to `/AGI/<GAME>/`; a startup validator discovers and
validates each. **On floppy the contents are unmodified and only the PLACEMENT is authored** (§4.7),
because the mapping from `(volume, offset)` to `(disk, track, sector)` does not exist in the original
data.

★★ **What this forces onto the target's critical path**, since the machine must handle original bytes:
the **`Avis Durgan` XOR** on v2 message text, and the RLE VIEW decode. **No host-side ingest is
permitted for v2.**

★ **v3 is deferred** (§11.1). Its LZW decompression and 4-bit PICTURE colour-code packing are therefore
**off the critical path for now** — but the resource layer is built so they can be added without a
rewrite (§4.2a).

★ **Game data is read-only, absolutely.** VOL and DIR files are never opened for writing; all builder
output goes to a separate tree. **A tool that opens a game file for writing is a bug.**

### 4.2 Format, and the index is read once

Game data lives in **VOL files** with **DIR files** as indexes — `LOGDIR`, `PICDIR`, `VIEWDIR`, `SNDDIR`
in v2; a single combined `*DIR` in v3 [AGI Specs §2.1, §5].

★★ **Volume record headers, read from the oracle** [`loader_v2.cpp:134-176`, `loader_v3.cpp`], not from
the Specs:

| | header | signature | length | compressed length |
|---|---|---|---|---|
| **V2** | **5 bytes** | `0x1234` **big**-endian | **little**-endian at +3 | — |
| **V3** | **7 bytes** | `0x1234` big-endian | little-endian at +3 | `clen` at +5; **LZW** |

★ **Mixed endianness inside one five-byte header** — a big-endian signature beside a little-endian
length. Not guessable; read it.

★★ **The volume format is INDEPENDENT of the directory format.** A game can have V2 directories
(`logDir`/`picDir`/`viewDir`/`sndDir`) and V3 volumes, and **most CoCo3 ports do exactly that** (§8.4).
**`volume.py` takes the header length as a parameter, not a branch** — design §4.2a's seam, exercised on
its first real case.

★ **There is no index to build.** The DIRs *are* the index — 3-byte entries of 4-bit volume plus 20-bit
offset, 256 entries max per type. **Measured on Sierra's KQ3: 1,836 bytes for all four**, and they ship
**alone on the boot side with no volumes at all** [backlog AD-23]. Read at boot, held in RAM, never
consulted on disk again.

### 4.2a ★★ The loader is separable — what makes v3's deferral reversible

**v2 is the build target. v3 is deferred, not abandoned** (§11.1), and that distinction is only real if
the architecture keeps it cheap.

> **The resource layer separates FINDING a resource from DECODING it.** The DIR walk yields
> `(volume, offset, length)`; a per-version loader turns those bytes into a resource. **v3 is a second
> loader plus a decompressor behind the same interface — not a change to the cache, the block layer, the
> renderer or the VM.**

★ **The concrete requirements, which cost nothing now and everything if skipped:**
1. **Version is detected once at game load**, from the DIR shape, and stored — never re-derived at a
   call site.
2. **No caller of the resource layer branches on version.** `view/`, `picture/`, `vm/` and `text/` see
   decoded bytes and never learn how they arrived.
3. **The decode step is a single seam** with one entry point per resource type, so a v3 loader is an
   added file under `storage/`, not edits spread across subsystems.

★★ **If a version test ever appears outside `src/engine/storage/`, the deferral has been spent.**

### 4.3 One block layer, three transports

> **The interpreter addresses logical 256-byte blocks. SDC, floppy and RAM are transports beneath it.**

**This is what keeps a storage problem from gating an interpreter problem.** The VM, the renderer and the
resource cache never learn which device is present.

### 4.4 ★★ Demand streaming is the mainline path

**Measured, unique AGI bytes, five media packagings agreeing** [backlog M-01a, L-18]:

| title | bytes | > 1 floppy | > ≈376 KB resident |
|---|---|---|---|
| King's Quest I | 256,857 | ✓ | |
| Leisure Suit Larry | 296,454 | ✓ | |
| King's Quest II | 364,044 | ✓ | |
| King's Quest III | 563,325 | ✓ | ✓ |
| Police Quest 1 | 702,192 | ✓ | ✓ |
| KQ6 AGI (fan) | 1,049,006 | ✓ | ✓ |
| **King's Quest IV** | **1,399,859** | ✓ | ✓ |

★★ **Every title exceeds one floppy. Four exceed the resident ceiling. KQ4 by 3.7×** — so the working set
is at most **27% of the game**, and that is the number the design is built for.

> **Demand-load with a pinned working set. The RAM-disk is not a separate strategy — it is the case where
> nothing ever evicts.** One mechanism, not two; the small-game case falls out for free.

★ **v0.3 had this backwards**, proposing a RAM-disk with streaming as a fallback, on a 250 KB nominal
figure that no real title matches.

### 4.5 ★★ Three-tier residency, taken from Sierra's own layout

Sierra's shipped KQ3 set duplicates resources across ten sides in three tiers, and **the taxonomy
transfers even though the constraint does not**:

**Measured on `KQ3/Original` — five disks × two sides** [backlog corrected 2026-08-24]:

| tier | KQ3 (`Original`) | LSL (`Original`) | role |
|---|---|---|---|
| **global** | `vol.0` 73,493 B + `object` 793 B, on **9 of 10** sides | `vol.0` 23,986 + `object`, on **3 of 3** | needed everywhere — **this is the pinned set** |
| **regional** | `vol.11` 8,062 ×3 · `vol.12` 15,037 ×5 · `vol.14` 5,596 ×2 | `vol.4` 14,719 ×2 | scoped to a region |
| **phase** | `vol.1`–`vol.9`, 23–64 KB, ×1 | `vol.1`/`2`/`3` | per-phase content |

★ **The global tier is ≈12% of KQ3's 640 KB and ≈10% of LSL's.** That is an empirical size for the pinned
set rather than a guess.

★★ **Duplication is 51.4% on `KQ3/Original` and 20.3% on the same title's `Floppy 360K` set; LSL is
14.8%.** *A duplication number without its variant is not a number* [backlog L-24] — v0.4 quoted a single
figure per title and LSL's 21% appears to have been the 360K answer for a different game.

★ **`vol.10` and `vol.13` are absent from EVERY KQ3 variant** — gaps in Sierra's own numbering, not
losses. The real loss is `vol.14`, dropped by SDC / DrivePak / DriveWire and kept by `Original` and
`Floppy 360K`.

★★ **And we are not reproducing Sierra's constraint.** With ≈376 KB resident we hold the global tier plus
several phase volumes simultaneously; Sierra could hold one. **We inherit the taxonomy and spend the
surplus on fewer swaps.**

★ **Duplication cost scales with the global tier, not with disk count** — KQ3 is 51% duplicate bytes and
LSL 21%, and the difference is a 73 KB shared pool against a 24 KB one [backlog I-18].

### 4.6 Floppy — DMK sequential, raw tracks, DECB as bootstrap

**Geometry: 35-track, single-sided.** 161,280 B raw; **156,672 B usable** after the directory on track 17.
★ **Confirmed against a shipped product**: Sierra's LSL disks 2 and 3 are exactly 161,280 B.

**Image format is DMK, interleave 0.** JVC has no physical order, so MAME synthesises a near-pessimal one
— 3.31 s/track in POP, 3.33 in Karateka. **JVC costs 2.5×** [POP P3.6, idioms §29].

```
imgtool create coco_dmk_rsdos <img> --tracks=35 --sectors=18 \
        --sectorlength=256 --interleave=0
```

★★ **Interleave 0 = sequential = fastest, inverting the RS-DOS convention** — a HALT-paced `m=1`
Read-Multiple reads a whole track under one command. Karateka's sweep: il=0 **10.66 s**, il=1 12.27,
il=9 25.07, il=13 31.46.

★ **DMK is read-only in MAME's floppy layer**; timing work uses the in-session CPU-hijack pattern
[idioms §3].

**Raw spans reserve granules as `$C9` with no directory entry.** The allocator skips any granule ≠ `$FF`
and never consults the directory. ★ **The reservation is what protects the data whether or not anything is
visible** — without it DECB reads 68 bytes of game data as a FAT.

**Track 17 is the directory, mid-disk** — granules 0–33 are tracks 0–16, 34–67 are 18–34, and **a span may
not cross 17**, so AGI uses **two spans per disk**. `disk_read_range` is the transport: whole tracks, no
directories, no granule chains. **AGI needs no per-file DECB access on target.**

★★ **DECB is a bootstrap and nothing more.** `LOADM` + `EXEC` a small loader; the loader switches to
all-RAM mode; nothing is ever called back into. **Two artifacts:** `LOADER.BIN` is the sole `LOADM`
target and the interpreter lives in the raw tracks as an ordinary payload. This narrows the `$010C`
problem to *the `LOADM` must survive itself* — a couple of KB of collision surface.

★ **Sierra went the other way and hosted on OS-9** (`OS9Boot` ≈21 KB, a `-Multitasking` flag)
[backlog I-19]. **AD-09 is unchanged** — owning the machine is right for us — but it means any timing
observed from Sierra's interpreter carries OS-9 overhead and is **a floor, not a ceiling**.

**Detection must fail toward asking** [POP §5.277]. Wrong disk → re-prompt. **Never depend on two drives.**

### 4.7 The image builder

**Host-side tool. Reads an unmodified game directory; writes N `.dmk` images to a separate tree.**
Placement, span tables, FAT reservation, signature sectors, `LOADER.BIN`, the per-disk label file. Never
writes to its input (§4.1).

★ **Repacking for locality is host-side, floppy-only, optional.** It cannot be a target-side tier: **SDC
has no seeks**, so the platform with writable free space gains nothing, and **floppy has seeks but no
space to write the output.** ★ Under demand paging its value rises — it is the lever that turns a phase
change into contiguous reads.

### 4.8 What lives in RAM

★ **Interpreter and host bytes are excluded from every storage figure.** `CMDS/`, `MODULES/` and
`OS9Boot` are code our port replaces — ≈55 KB per disk — the same reasoning that removed `AGIDATA.OVL`
[backlog AD-24]. A size-summing walk that counts them overstates every "does it fit" answer.

| item | source | why resident |
|---|---|---|
| DIR tables | disk, once | ≈1.8 KB measured; the resource index |
| the global tier | §4.5 | ≈10–12% of the game; never evicted |
| decompressed v3 resources | LZW on load | amortises §9's cost across re-entries |
| VIEW cels, RLE → blit-ready | decoded on load | §7 requires this regardless |
| `WORDS.TOK`, `OBJECT` | disk, once | parser needs them every cycle |

### 4.9 UX divergence

**SDC gets the `/AGI/` game picker; a floppy set is one game**, so the picker degrades to *which set is in
the drive*. ★ **The loading screen needs display and keyboard before the bulk read** — DECB's text output
is gone at the mode switch — so **§10's P3 is a prerequisite for the floppy loader**.

## 5. The virtual machine

**LOGIC is bytecode over a fixed command set.** ★★ **A v2/v3 target needs 203 opcodes, not 319.**
`opcodes.cpp` holds four tables — `opCodesV1Cond` 17, `opCodesV1` 99, `opCodesV2Cond` 20, `opCodesV2` 183
— summing to 319 across **two orthogonal axes**: two interpreter-version families (selected at runtime,
`opcodes.cpp:381-389`; a game uses ONE) and two dispatch classes (tests vs commands, separate opcode
spaces). **203 overstates it further** — `opCodesV2` marks entries Apple IIGS-only and AGI3+-only.
v0.3 quoted 319; the value was right and its scope was not [backlog L-14]. Most take 1–7 byte arguments; `0xFF` opens and closes a condition
block, `0xFE` is an else/branch with a 16-bit skip [AGI Specs §6].

**State is 256 variables and 256 flags, byte-indexed and flat** [AGI Specs §3]. **No heap, no pointers,
no allocation** — the property that makes this port tractable. A 6809 dispatch through a 256-entry jump
table with argument counts in a parallel table is a few hundred bytes.

**Each cycle:** poll input, run `logic.0` and the room's LOGIC, update view positions and animation,
composite, display. **The LOGIC re-runs from the top every cycle** — scripts are condition batteries,
not coroutines.

### 5.1 ★★★ Sound and the completion flag — a correctness requirement

**`sound(resourceNr, flagNr)` is how LOGIC waits for audio.** A script issues it, then tests the flag
before advancing. ★★★ **A backend that never sets that flag deadlocks the game permanently, in one
room** — not silently degraded, stuck.

**The reference already carries the rule, in a CoCo3-specific branch** [`op_cmd.cpp:701-719`]:

```c
if (platform == kPlatformApple2 || platform == kPlatformCoCo3) {
    // Sound playback is a blocking operation on these platforms.
    // If sound is off then playback is not started.
    if (getFlag(VM_FLAG_SOUND_ON)) {
        startSound(resourceNr, flagNr);
        waitAnyKeyOrFinishedSound();
        stopSound();
    }
    setFlagOrVar(flagNr, true);      // <-- OUTSIDE the if
} else {
    startSound(resourceNr, flagNr);  // <-- asynchronous, flag set on completion
}
```

> ★★★ **THE RULE: the completion flag is set unconditionally — sound off, no cartridge, resource
> missing, resource corrupt, backend unimplemented.** Whether a note was ever played is irrelevant to the
> VM.

★ **This is what makes PC sound resources safe to feed us before any audio work exists.** A stub emitter
that decodes nothing and sets the flag is a *correct* interpreter with no sound.

### 5.2 ★★ Blocking vs asynchronous playback — OPEN, and to be investigated

**Sierra's CoCo3 interpreter BLOCKS during sound.** That is why animation and input stop for the duration
of a song. ★ **It is a documented design, not a defect** — ScummVM encodes it per-platform, alongside the
Apple II.

★★★ **We are not bound by it** [backlog L-21, and Jay, 2026-08-25]. Every other AGI platform takes the
`else` branch: **asynchronous playback, flag set on completion, the game continues.** The reasons to
expect we can do better than 1988:

1. ★★ **The GMC's SN76489A mixes in hardware** (AD-27). The DAC path's cost was always the software
   mixer; with a PSG the emitter is a few register writes per note change and idles between them.
2. **POP established a FIRQ-driven player on this machine**, so the interrupt substrate exists.
3. **Sierra shipped two titles for a machine they abandoned.** *An observed behaviour is not a measured
   limit* [L-21] — the tradeoff may have been schedule, not cycles, and nothing in the artifact
   distinguishes them.

**The design intent, to be validated rather than assumed:**

| backend | target |
|---|---|
| **GMC (SN76489A)** | ★ **asynchronous** — the chip mixes; the emitter should not need to block |
| **stock 6-bit DAC** | **measure before choosing.** Async if the mixer fits the cycle budget beside animation; blocking only if measurement says so |

★ **Blocking is the fallback, not the default.** ★★ **And the completion-flag rule in §5.1 holds either
way** — it is orthogonal to this choice and must not be made conditional on it.

**Measurement: M-14**, at P7 or earlier if the sound seam lands sooner.

### 5.3 ★★ Backend selection — a user setting, and why detection cannot replace it

**Every detection route was examined and all of them fail the same way** [backlog AD-31]:

| route | why it fails |
|---|---|
| read the SN76489A | ★★ **write-only silicon.** MAME's GMC implements `scs_write` only, **no read handler at all** [`coco_gmc.cpp:91`]. A write to `$FF41` with no cartridge vanishes into the floating bus. **Neither error announces itself.** |
| ROM signature at `$C000` | ★ **the GMC is a FLASH cartridge** — the ROM is whatever game was flashed. **No constant to match.** |
| bank-switch probe (`$FF40`, read `$C000`, change bank, re-read) | real and observable, but detects **a banked cart**, not a GMC — *"exactly like the circuit developed for RoboCop and Predator"* — and **needs `$C000` mapped, so it must run before AD-09's all-RAM switch.** False-negative on a blank or single-bank flash. |
| CART line via PIA1 | a pak with autostart ties CART to **Q, the system clock** [`coco_pak.cpp:115-120`] — genuinely observable. ★★ **But autostart CLEARs the line when disabled, and a user booting our disk with a GMC installed has almost certainly disabled it. The signal is off in exactly the configuration we need it.** |

> ★★★ **Detection cannot even fail informatively here.** Writing to an absent GMC is silent; not writing
> to a present one is equally silent. POP's *detection must fail toward asking* [§5.277] applies with
> unusual force. **The backend is a USER SETTING. Detection is not the mechanism.**

#### 5.3.1 ★★ Where the setting lives — an injected menu, with NO resource modification

★★★ **The menu is interpreter RAM, not game data.** `set.menu` / `set.menu.item` populate a structure the
interpreter owns; `submit` finalises it. **Appending our own menu at submit time touches nothing on
disk** and preserves §4.1's unmodified-originals guarantee completely.

**The reference does exactly this** [`menu.cpp:166-190`] — a platform-conditional, config-gated
interpreter menu injected at submit:

```c
// WORKAROUND: For Apple II gs we add a Speed menu
if (platform == kPlatformApple2GS && ConfMan.getBool("apple2gs_speedmenu")) {
    ... scan for maxControllerSlot ...
    if (maxControllerSlot >= 0xff - 4)  warning("failed to add 'Speed' menu");
    else { addMenu("Speed"); addMenuItem("Normal", slot + 2); ... }
}
```

★ **Three details to take verbatim, because they are the non-obvious part:**

1. **Scan for the highest controller slot across the menu items AND the key mappings, then allocate
   above it.** The game assigns slots and does not know ours exist; **a collision fires a game action
   when the user picks our item.**
2. **Check for exhaustion and degrade.** A game consuming nearly all 255 slots gets **no sound menu** —
   correct behaviour, not corruption.
3. **Gate on config**, so the injection is itself opt-out.

★★ **`submit` returns early when the game defined no menus at all**, so a menu-less game gets no injected
item. **That case needs a separate route** — a dedicated key opening an interpreter-owned screen — and it
is also the fallback whenever slot allocation fails.

> **Separate the two concerns: HOW THE SETTING IS EXPRESSED (injected menu, interpreter screen, boot-time
> config) is independent of HOW THE BACKEND IS CHOSEN (§5.3's user setting). Neither constrains the
> other.**

★ **203 opcodes is volume, not difficulty.** ScummVM's `op_cmd.cpp` is 2,483 lines at the pin. The ones with substance are view control, the parser interface, and the window/message system.

---

### 5.8 ★★★ The VM is gated on NINE titles

**256 variables + 32 flag bytes, byte-identical against the oracle-gated reference on every one of 500
cycles, across NINE titles, with an EMPTY exclusion set** [T-P0-027] — three times the dispatch's
requirement.

★★ **Motion and `update_screen_obj_table` are in scope and implemented** — the dependency a
suppression experiment found, **run on the reference against itself with no assembly in the experiment.**

★★★ **Twelve defects, and the state diff pointed directly at NONE of them.** *"It is an excellent detector
and a poor localiser, and the gap between the two is where the task went."* ★ **Every gate in this
document is a detector; none localises. Budget the localiser alongside the gate.**

### 5.7 ★★★ The flag divergence — attributed WRONGLY, then traced

**v0.8 §5.5 recorded P4.1's finding as *"one defect with three symptoms — each divergent flag is a
completion flag the interpreter sets when an animation or motion finishes."* ★★★ That attribution was
co-occurrence, not causation, and it was carried into a dispatch and a verdict before anyone asked how it
had been checked.**

**What had actually been checked:** each divergent flag number appears as an argument to `end.of.loop` /
`reverse.loop` / `move.obj` / `follow.ego` **somewhere in that game's scripts** — 35, 23 and 31 call
sites respectively. ★ **In a 256-flag space with dozens of animation call sites, that is close to
guaranteed for any flag number.**

**Traced with a probe inside the oracle rather than inferred from call sites** [P5.1 §3.1]:

| title | flag | actual cause |
|---|---|---|
| KQ2 | 33 | **animation completion — CLOSED** by the cel cycler |
| KQ3 | 221 | **animation completion — CLOSED** by the cel cycler |
| **KQ1** | **20** | ★★★ **a SOUND end-flag. Never animation at all.** |

> ★★ **A shared cause claimed across symptoms needs its MECHANISM named, not its co-occurrence counted.**
> §2H's second check — *name the routine that CALLS it* — applied to the thing everyone had already
> agreed on.

### 5.4a ★★★★★ CURRENT: 15.7 cycles/second on KQ1

| | |
|---|---|
| KQ1, first measured | **6.2 cyc/s** |
| after the LOGIC cache | **14.2** [AD-87] |
| ★★★ **after the timer division came out** | ★★★★ **15.7** [AD-108] |
| KQ3 | ★★★ **9.4** |
| ★★★★ **the corpus asks for** | ★★★★★ **10 — 92 write sites, dominant value 100 ms, and NOT ONE site slower than 200 ms** [AD-82] |

★★★★★ **The LOGIC cache: the port re-copied a LOGIC on EVERY invocation — 3.01 times per cycle, 13,715
bytes, 99.7% of them the same bytes again — where the reference caches once per game** [AD-86, L-66].
★★★ **Index-keying beat depth-keying 99.7% to 33.0% and the keying was simulated before anything was
built.**

★★★★ **The timer division: a 32-iteration software long division per 25 ms tick, to detect a boundary a
counter gives free — 11.2% of the cycle** [AD-106].

★★★ **The inner loop is TITLE-INDEPENDENT — 64,902 cy/VM cycle on KQ1, 65,888 on KQ3, a 1.5% spread** —
★★ **so what separates the titles is elsewhere, and 63.6% of KQ3's extra cost is the resource copy still
running with the cache live** [AD-106].

★ **Opcode count is NOT the explanation: R² = 0.018 across six titles** [AD-101].

### 5.5 ★★ The VM is oracle-verified — and the divergence is attributed

**`tools/agivm/` executes LOGIC bytecode and emits the oracle's own per-cycle dump format**
[T-P0-008 / P4.1]. Diffed against the pinned oracle over three titles, **all 256 variables and all 256
flags, every cycle**:

> ★★ **All variables match for the whole run in all three titles. Each title diverges on exactly ONE
> flag.**

★ **One defect with three symptoms, not three defects.** Each divergent flag is a completion flag the
*interpreter* sets when an animation or motion finishes — **which needs the VIEW parser and motion
system the VM declares it does not have.** That is P5's work, not a VM fault.

★★★ **The exclusion set is EMPTY** — see §8.6. The obvious move was to exclude the clock-coupled
variables; **vars 72 and 73 are ordinary game variables, and excluding them would put real interpreter
state permanently outside the gate to work around a harness defect.**

### 5.6 ★★ The dispatch table is BUILT, not loaded

`setupOpCodes()` [`opcodes.cpp:372`] **does not load a static table.** It copies a base and mutates it by
**interpreter version, platform, gameID and feature flags.**

**Measured across all 194 classified rows:**

| mutation class | rows affected |
|---|---|
| version-driven | **zero** — every pinned version (`0x2272`, `0x2440`, `0x2917`, `0x3149`) sits above every threshold |
| feature-driven | **21, all fanmade** — `GF_AGIMOUSE` 18, `GF_AGI256` 4, one row carrying both |
| platform / gameID | none for this corpus |

★★ **So for the CoCo3 and Sierra DOS titles this project targets the table is effectively static — but
that is a measured result about THIS CORPUS, not a property of AGI.** The dispatch **refuses a
configuration it cannot run** rather than silently falling back to the base table.

★ **Constants are GENERATED from the pinned oracle, not typed.** Hand-writing the `VM_VAR_*` / `VM_FLAG_*`
set produced four wrong names or values; `gen_oracle_tables.py --check` gates drift. **L-25 escalated from
a lesson to a mechanism: reading the enum prevents one error, generating from source prevents the class.**

## 6. The picture renderer

**The single hardest component.**

### 6.1 Commands

Absolute and relative lines, pen/brush strokes, and **flood fill** [AGI Specs §7]. `0xF0` and `0xF2` set
the visual and priority pens; drawing to either screen is independently enabled.

### 6.2 The fill

Per the spec: fill from a seed into **white** on the visual screen, bounded by non-white; into **red** on
the priority screen, bounded by non-red. **With both enabled, the priority fill also stops at boundaries
present only on the visual screen** [AGI Specs §7].

The spec suggests a **queue-based four-way fill**.

★★★ **M-02 ANSWERED ON HARDWARE, and it is a design constraint** [T-P0-012, T-P0-013]. At 1.7898 MHz:
**median room 8.909 s, worst 16.963 s, 4 of 45 pictures still over 10 s** — after a 19.7% optimisation.
**94.4% of a room is the flood fill.**

> ★★★ **The unit of cost is the BOUNDARY TEST, not the pixel.** 3.67 M tests against 1.19 M pixels
> written — **3.1 tests per pixel** — and cycles-per-test is **flat to 1.11× across all 45 pictures**
> while cost-per-pixel-written varies 2.2×. **A picture can write the same pixels and cost twice as much
> because its regions are shaped so the fill tests more candidates.**

★★ **§6.3 is right that run structure beats per-pixel work — but the run that matters is the SCAN, not
the WRITE.** `fill_check` is now **86 cycles**: bounds 28 · row address 20 · plane test 14 · call/return
13 · dispatch 11. ★ **The remaining move the measurement names is hoisting the row address out of the
span** — along a rightward scan y is invariant and x increments by one, so the address becomes a pointer
the caller advances, **removing the `mul` and most of the bounds test together** [backlog M-21].

★★★★★ **CURRENT: 2.832 s median** — packed planes, windowed addressing, shadow-buffer blit
[AD-85, AD-95, AD-117]. ★★★ **And the renderer is 53 of 53 KQ1 pictures byte-identical on BOTH PLANES**
[AD-123].

> ★★★★★ **v1.1's divergence figures — 71.5%, 28.8%, 23.9%, 20.7%, 20.6%, 14.8% — measured the VISUAL
> PLANE ONLY and are WITHDRAWN.** The priority plane was dumped on every one of those runs and compared
> on none [AD-122, L-88].

★★★★ **The defect they described: `ff_store_pri` computed a flat offset up to 13,439 bytes into an
8,192-byte window and never mapped the slice it was writing** — ★★★ **so priority values were written
into the VISUAL plane, and the visual plane's wrong-colour damage and the priority plane's under-fill
were ONE CAUSE** [AD-123]. ★★ **A second site had the identical defect and was found by prediction, not
by search** [L-89].

★★★ **Costs, each measured: packing 1.0% of the gain · windowing 6.4% · the shadow blit +0.2169 s per
room.**

★★★ **RESTRUCTURED, AND THE FILL WORK IS FINISHED** [T-P0-021, T-P0-022]:

| | min | **median** | max | >5 s |
|---|---|---|---|---|
| first measured | 5.603 | **11.102** | 21.007 | 45 |
| after restructure | 2.168 | 2.973 | 4.599 | 0 |
| **after deferred write** | 1.998 | **2.746** | 4.357 | **0** |

★★ **75.3% below the original, with every counter invariant** — boundary tests 3,666,862 → 3,666,862,
pixels 1,188,430 → 1,188,430, seed peak 74 B. **Cycles per boundary test fell 3.25×.**
★★★ **The win was making each test CHEAPER, not doing fewer** — 3.09 tests per pixel is **one on the
pixel, one on the row above, one on the row below**, which is how a transition is detected. **Remove one
and you change which pixels get filled.**
★ **The stack blast measured −0.1% and is CLOSED, not adopted** — cheaper per byte (2.9 cycles against
11) but **paid per span, and the median span is 9 bytes.**
★★ **Fills are still 81.3% of the render** (2.233 s of 2.746) — **but at this figure "rank 1" no longer
means crisis**, and compositing (§7.1) is the larger open question.

★★★ **The MEMORY fear is dismissed** [T-P0-006 AC-5]: over **498 pictures the peak
seed-stack depth is 102 entries — 204 bytes on a 6809** at two bytes per seed. **Median 7.** Nothing
approaches the 2 KB threshold that would have been a design constraint.

★ v0.6 said *"a pixel queue is the wrong choice; the queue becomes the memory problem."* **It does not.**
Scanline fill remains preferable for speed, but **not for memory** — that concern is measured away.

★★ **What remains is TIME: 12.5 M pixels filled across 35,048 invocations** over the gated set. **That is
the figure M-02 must weigh against a room-change budget**, and it is now a number rather than an anxiety.

**This routine sets room-change latency, and room changes are the one moment an AGI player waits.**

### 6.5 ★★★ First pixels — gated, not admired

**One AGI PICTURE (KQ1 #80) interpreted by 6809 code on a real CoCo3 under MAME, 320×200×16.** Both
planes read back and diffed against the pinned oracle:

| plane | sha256 | bytes |
|---|---|---|
| visual | `ef1556f2…` | 26,880 |
| priority | `98cdf968…` | 26,880 |

★★ **Byte-identical.** The 4bpp CoCo3 buffer is **unpacked back to 160×168 indices and compared THERE**,
never by packing the oracle's — so an error in the packing cannot cancel an error in the rendering.

★ **`picdiff.py` does not import `tools/picrender/` and must not** [§8.2]. The offline renderer was used
**once, as a diagnostic**, to confirm the oracle dump is what we think it is — **never as the baseline.**

### 6.6 ★★★ Three defects the port surfaced — none findable offline

1. ★★★ **The AGI canvas is visual = 15, priority = 4. It is NOT black.** `HAL_gfx_set_mode` clears to
   index 0 — right for the HAL, wrong for a picture, because `draw_FillCheck` fills only where the visual
   is 15. **With a black canvas no fill can ever succeed.**
   > ★★★ **And row 0 agreed with the oracle throughout anyway, because row 0 is genuinely black. Two
   > buffers matching for DIFFERENT REASONS — a gate that checked only row 0 would have passed.**
2. ★★ **`rel_line` deltas are SIGN-MAGNITUDE, not two's complement** [`picture.cpp:640-643`:
   `if (dx & 0x08) dx = -(dx & 0x07)`]. Bit 3 is the sign, bits 0–2 the magnitude, so **`$F` is −7**; a
   two's-complement `ora #$F0` makes it **−1**. Every negative delta lands wrong.
3. ★ **The caller owns the stack** [`hal.inc:357-362`] and `S` must live below `$8000`. **The suggested
   `$7F00` is inside the probe's priority plane and cannot be taken literally** — leaving `S` where DECB
   put it aimed the hardware stack into the fill stack, and the first deep fill ate a return address.

### 6.4 ★★ The both-screens fill bound — verified by falsification

**With both screens enabled the fill is bounded by the VISUAL screen** [`draw_FillCheck` case 3].

★★★ **Proven by breaking it, not by passing.** Rebinding the bound to the priority screen **breaks 107 of
390 pictures** [T-P0-006 AC-6]. **The rule is load-bearing, not incidentally satisfied — a green
aggregate could not have shown that.**

### 6.3 Addressing

The framebuffer is 4bpp at 320 wide (2 px/byte); the priority screen is 4bpp at 160. **Every write is a
read-modify-write on a nibble unless the renderer works in pairs.** Line drawing and fills should
special-case full-byte runs — ★ the same lesson POP learned about its segment blitter, where run
structure beat per-pixel work [§5.210].

**Picture pixels are doubled once, at room load, into the 320 framebuffer** — not per frame.

---

## 7. Views and sprites

### 7.1 ★★★ Compositing is gated — and its cost is a FLOOR, not a figure

**Ported and gated** [T-P0-028]: **6,782 cels byte-identical across 5 titles; 100 composited frames
byte-identical on BOTH planes; a one-boundary injected fault fails exactly where the model predicted, to
the byte.**

> ★★★★★ **WITHDRAWN: the ~53% and ~106% figures were overstated 3.78× by a harness defect —
> `cp_do_free` inflated the work on frames where the control branch fires** [AD-76].

★★★★★ **CURRENT: 0.02107 s per cycle at two sprites, 0.03929 at four** [AD-109], **measured with the ego
composited every cycle.** ★★★ **Comfortably positive against a 100 ms budget**, and ★★ **the fill runs
once per room while this runs every cycle.**

★★★ **But 106% is a FLOOR, for four reasons, none of them in the number:**

1. ★★★ **The control-line branch is exercised by ZERO of 1,680 frames.** *"A per-pixel column walk of up
   to 168 steps — it could be the largest term in the composite and nothing measures it."*
2. **The MMU remaps the shipped banked layout needs are excluded.**
3. **Save-under restore cycles are unmeasured.**
4. ★★★★ **THE SAMPLE WAS ATTRACT MODE.** See §7.2.

### 7.2 ★★★★ The corpus was attract mode — the ego was composited ZERO times

**Raised by Jay after the verdict, then measured** [backlog AD-72]:

| | |
|---|---|
| frames captured | 1,680 across 5 titles |
| ★★★ **frames containing the EGO (object 0)** | ★★★ **0** |
| objects ever composited | `add.to.pic` decorations and attract elements |
| composited sprite area, median | **120 px** against a corpus cel median of **270 px** |
| ego `ySize` from the VM's own object table | **32–33** |

★★★ **Nothing the player controls was composited even once.** The 45-second windows never leave the
credits, **so every frame gated, timed and shown is an intro sequence.**

★★ **§7.1's control branch is now explained rather than mysterious:** *"control lines are what an ego
walks past — its absence here is a property of attract mode, not of AGI."*

> ★★★ **§3.6's single-buffer decision and §9's ranking both reopen — and NEITHER can be decided on this
> data.**

★★★ **The fix needs no keyboard injection: `room <n>`, `setvar`, `setobj`.** ★★ **The debug console's
room jump, adopted as a COVERAGE instrument, turns out to be the SAMPLING instrument too.**

### 7.3 The cel model

**VIEW resources are RLE-compressed cel bitmaps** — each byte carries a run length and a colour; a view
holds loops of cels, up to 255 each [AGI Specs §8].

★★ **ORACLE-VERIFIED: 6005/6005 cels byte-identical across eight games** [P5.1 AC-2], mirrored loops
included.

**Decode on load into a cel cache**, not per frame. The RLE is compact for storage and wrong for a blit
inner loop.

**Transparency is colour 0.** With the priority test, the inner loop is: *if source ≠ 0 and sprite
priority ≥ priority[x>>1], write.* **Two tests per pixel** — where the frame time goes.

★★ **MEASURED** [P5.1 AC-6]: peak simultaneous active objects and **peak total cel area on screen** are
the save-under backing-store bound, and the figure sits well inside the single-buffer budget. ★ **Save-under
bounds cost by total sprite area, not screen area** [§3.6] — now a measurement rather than an expectation.

---

## 8. Verification

★★ **POP's method half-transfers, and the half that does not must be named.**

POP has one oracle and a byte-comparable target. **An interpreter has no single correct output.**

### 8.1 ★★ There is no source, and ScummVM is not neutral

**Sierra's interpreter source is not public.** What exists is ScummVM's `engines/agi` — a
*reimplementation* — and the AGI Specifications, also derived by reverse engineering in 1997. ★★
**Neither is the source. Both are evidence about AGI's behaviour, produced by people who did not have
the source either.**

**Authority stack:**

1. **Jay** — ultimate.
2. ★★ **The original game running** — and for CoCo3-specific questions this EXISTS, **but only for two
   titles.** Sierra's CoCo3 AGI interpreter is in hand and **King's Quest III runs interactively under it
   in MAME** (T-P0-004 AC-8, live gate).
   ★★ **Scope it correctly** [backlog X-26]: only **KQ3 and LSL** have `Original/` media and are Sierra
   artifacts. **KQ1, KQ2, KQ4, PQ1 and KQ6 AGI are community conversions running Sierra's interpreter** —
   a palette or timing observation from those is **evidence about the interpreter, not about a Sierra
   release.** Do not let all seven carry the same weight.
   ★ **And its timings carry OS-9 overhead — a floor, not a ceiling** [I-19].
3. **ScummVM** — best secondary evidence for AGI's semantics; tested against dozens of games.
4. **The AGI Specifications** — good, older, known incomplete in places.
5. Comments and labels — lowest.

★ **ScummVM fixes original bugs, works around game-specific quirks, and normalises across interpreter
versions. Reproducing it faithfully may mean reproducing choices Sierra never made.** Where it and the
specs disagree, it is usually right about *what works*; it is not automatically right about *what the
original did.* **Say which you are reproducing.**

### 8.2 ★★ The baseline must not be self-referential

**Cluster A** [CODM §7, corroborated in Karateka as `empirical-validation-ground-truth-first` — a
rule-derived validation passed 109/109 while the rule was wrong]:

> **The CoCo3 renderer is diffed against the pinned oracle, never against our own offline renderer.**
> Both are clients of the same reference. **If the CoCo3 output is compared to the offline output, both
> can be wrong in the same way and the suite reports green forever.**

### 8.3 Evidence classes

**Every AC declares its class. An AC without a class is not an AC.**

1. **byte-comparable** — picture rendering. A room is a deterministic function of its PICTURE resource.
   ★ **The one component gateable as rigorously as POP's screens were.**
2. **state-comparable** — LOGIC execution. Instrument ScummVM to log variables and flags per cycle; run
   the same script with the same inputs; diff.
3. **eye-gated** — sprite compositing. Priority interactions are what a person notices and a diff
   summarises badly.
4. **suite** — the game library. Boot each game, walk a scripted input sequence, compare. **A regression
   suite, not a gate.**

★ **The failure mode is reaching for byte-identity where it does not apply and either over-claiming or
stalling.**

### 8.4 Pin both halves of the oracle

> **Pin the ScummVM commit. Pin the specific game releases** used as test data — AGI version, platform,
> release.

★★ **The corpus is THREE populations, not two** [T-P0-005 §3D]: the PC fan set (`agile-gdx@81c42ba`),
the PC Sierra drop (KQ1/KQ2/KQ3 AGI v2), and the CoCo3 set — **of which all but `KQ3/Original` are
V3-volume hybrids and therefore out of scope for v2 byte-comparison.** A test set that does not name its
population is not a test set.

★ **AGI games shipped in multiple interpreter versions with different command sets**
[AGI Specs §3.9-3.10]. ***"King's Quest I" is not a specification*** — and §11.1's disk-count measurement
is meaningless until the game set is pinned.

★ **The behavioural mandate.** Visual fidelity is necessary and not sufficient. **An AGI interpreter can
look perfect and be wrong** — a LOGIC opcode setting the wrong flag, an off-by-one in a `said()` match, a
variable updated in the wrong cycle: none of it visible until a puzzle becomes unsolvable forty minutes
in, in one game out of thirty. **Where behaviour is observable, it must match. Where it is genuinely
unobservable, a divergence that preserves output is legitimate.**

★ **Where a trace is needed, POP's rule holds: sampling finds state, only a write tap finds events**
[§5.239].

---

### 8.10 ★★ The clock is 1.789390 MHz, calibrated by SLOPE

**Two tasks measured two figures — 1.7898 MHz and 1.7871 — from single-block runs.** ★★★ **A single block
cannot separate the loop from the harness around it.**

**The slope over five block counts (1, 5, 25, 100, 500):** least squares gives
`elapsed = 0.089415962 × blocks + 0.333998 s` → **1.789390 MHz, 0.021% from the hardware constant
14.31818 ÷ 8 = 1.789772.**

★★ **1.7871 was scaffolding.** ★ **Every cycle figure in this document is stated against 1.789390 MHz**,
and **fast mode is asserted by the HAL at init** — not inherited from DECB or the probe harness.

### 8.9 ★★★ A byte-identical buffer proves nothing about the SCREEN

**AC-6 passed byte-identical and the display was still wrong.**

> ★★★ **A readback path and a display path are different paths** [idiom 19j]. The framebuffer can be
> correct while the mode, palette, VOFFSET or monitor type puts something else on the glass.

★★ **The byte gate and the eye gate are NOT redundant**, and this is why §8.3 ranks compositing
eye-gated and CLAUDE.md §4 demands the launch path on every gate. **Neither substitutes for the other.**

★ Two specific traps recorded: the flip must use `HAL_gfx_swap`, not `HAL_gfx_present`; and the probe
**asserts Monitor Type → RGB on every run** rather than assuming it — the palette is exact in RGB and
undefined in composite (§2.2).

### 8.5 ★★ A KNOWN ORACLE DEFECT — `Kingquest1` SOUND 34–37

**ScummVM mis-loads four resources and our refusal is more correct** [T-P0-007 AC-5].

`Kingquest1`'s SOUND 34–37 DIR entries point **past the end of `VOL.2`** — the only out-of-range entries
in the game. The oracle appears to succeed, emitting **206 zero bytes each**. ★★★ **206 is exactly the
length of SOUND 21, the last resource loaded before them.** `volumeHeader[7]` is an **uninitialised stack
local**: the seek lands past EOF, the read returns nothing, the buffer still holds SOUND 21's header, and
the `0x1234` check passes against stale data.

> ★★ **Any byte-comparison against these four resources will fail, and that is the correct outcome.
> Do NOT "fix" our loader to match.** Out-of-range DIR entries are **refused, never truncated or
> zero-filled.**

★ **This does not demote the oracle.** §8.1's ranking is unchanged — one defect is not a loss of
authority. But it is the first case where our output outranks it, and it is recorded so nobody
re-litigates it from a failing diff. → M-15: are there other stale-DIR cases in the corpus?

### 8.6 ★★★ Oracle determinism — CORRECTED, and how the original check failed

**v0.7 and earlier recorded oracle determinism as verified at T-P0-003. That verification could not have
failed.**

★★★ **It compared two IDLE runs.** The pacing gate [`cycle.cpp:449`] pins cycle N to wall time N/40 on an
unloaded machine, **so an idle pair is byte-identical and looks deterministic.** Measured under 3×-nproc
load on the unmodified oracle: **vars 11, 72 and 73 diverge**, first at cycles 38/39/39.

★ **And vars 12–14 did not diverge only because a 20-second run never crosses a minute** [L-22, in the
same measurement].

> ★★ **A check that cannot fail under the conditions it runs in establishes nothing** [L-23]. The
> original AC was written by the Orchestrator, passed, and was confirmed. **It carried a false assurance
> for four tasks.**

**The fix removes the cause rather than excluding the symptom.** `getTotalPlayTime()` returns real
wall-clock milliseconds; **patch 0005 replaces it with a virtual clock advancing 25 ms per main-loop
iteration** — the unit the pacing gate already counts in. Same idle-vs-loaded comparison afterwards, 807
common cycles: **all 256 vars and all 256 flags identical. Exclusion set EMPTY.**

★ **Patch 0005 is a deliberate DEVIATION from the oracle, adopted for determinism.** It is **not** a claim
about Sierra's interpreter. It happens to sit closer to the CoCo3 target, whose clock will be a 60 Hz VBL
count, **but that is a convenience and not the justification.**

★ **RNG**: `Common::RandomSource` seeds from time-of-day unless `random_seed` is set, and `--random-seed`
is a first-class CLI option — **no patch needed.** Runs pass a fixed seed.

### 8.8 ★★★ A SECOND oracle nondeterminism — and the state gate, amended

**Sound end-flags are not cycle-driven.** `sound.cpp:169` carries ScummVM's own comment: *"This is called
from SoundGen classes on **unsynchronized background threads**."* A real-time source, not a cycle-driven
one. Four back-to-back runs, same binary, same seed, same game, same settings:

```
KQ1 flag 20 first set at cycle: 186, 185, 185, 184
```

★★★ **Two consecutive runs agree.** That is precisely why §8.6's determinism work did not catch it — **the
L-30 trap recurring in a subsystem that work never exercised.** Independent corroboration: the oracle
idle-vs-loaded diverges on flag 229 **and nothing else**, while our VM is bit-identical over 513 cycles.

> ★★ **THE AMENDED GATE: all 256 variables and all 256 flags identical every cycle, EXCEPT sound
> end-flags while a sound is playing.** That exception is **a property of the oracle, not a concession to
> our implementation** — no implementation can satisfy the unamended form.

★ **Neither escape was taken.** The flag was **not excluded** (§8.6's precedent is to fix the cause, not
hide the symptom) and the bug was **not matched** (§8.2). ★★ **And the available fix was declined
unasked**: making sound completion cycle-driven — compute a duration in cycles and fire deterministically
— **designs sound semantics, which is §5.2's open question and P7's scope.** It changes oracle behaviour
more than patch 0005 did. → M-17.

### 8.7 ★★ The host toolchain — a wrong fact in a pinned file for four tasks

`scummvm.pin [host]` asserted from P0.2: *"NO C++ toolchain… no MSYS2 and no MinGW compiler… No SDL2
anywhere."*

★★ **Every clause was individually true of the places it looked** — PATH, `C:\msys64`, `C:\mingw64`,
both Visual Studio roots, Chocolatey, Strawberry, LLVM. **A complete MinGW-w64 14.2.0 toolchain was
present throughout, vendored inside a sibling project's tree**, invisible to a PATH-and-standard-roots
search.

> ★★★ **A negative result about the environment needs the same "what would this have missed?" question as
> a positive one — and once written into a pinned artifact it stops being re-examined.**

**The oracle now builds natively under MinGW-w64; WSL is dropped from the project entirely.** ★ **The
swap was licensed by an equivalence proof before anything depended on it**: same seed, 262 common cycles,
**zero divergence across all 256 vars and flags**, and the VM's known divergence reproduces identically
(cycle 186 / flag 20). **The pinned source is unchanged** — patches 0001–0005 untouched; the native build
is configure flags plus two invocation steps.


## 8A. ★★★★★ The parser

**Ported and gated: 23,328 cases across five titles — every distinct `said()` operand pattern in each —
zero divergence on both the tokenised word numbers and the match result.** ★★★ **The chain is
6809 → Python → ScummVM, both legs gated at the same cases.** ★★ **870 bytes of code and state.**

### 8A.1 The three pieces

★★ **`WORDS.TOK` → the vocabulary**, verified entry for entry in bucket order on five titles.
★★ **Tokenising** — split, look up, discard ignorables → a list of word numbers, gated independently of
`said()`.
★★★ **`said()` matching** — ★★★★ **including `1` (any word) and `9999` (rest of line).**

### 8A.2 ★★★★★ The stateful behaviour, which is not syntax

> ★★★★★ **`said()` sets `SAID_ACCEPTED_INPUT` on success, so the FIRST `said()` to match consumes the
> input and no later one can fire in that cycle.**

★★★ **Getting precedence wrong produces a game that responds to the WRONG SENTENCE** — ★★ **which passes
every byte gate and shows up as a puzzle that will not solve.**

### 8A.3 ★★★★ The opcode door

★★★★★ **Wiring the parser reaches opcodes no gate has ever executed.** KQ1 reaches `save.game` and
`restore.game`; KQ3 reaches `restart.game`. ★★★ **All three are deliberately unimplemented and raise
honestly.**

★★★ **Without input an AGI game sits in attract mode and never takes those branches** — ★★★★ **so the
parser is the door to a part of the command space the nine-title gate has never covered.** ★ **A coverage
fact with a cost attached.**

### 8A.4 ★★ What does not exist yet

★★★★ **Keyboard input, text rendering and the on-screen input line.** ★★★ **`parseUsingDictionary()` is
what a keystroke calls, and there is no keystroke** — ★★ **the engine stops on a typed command because a
null backend has no key to give it.**

★★★ **Jay's control scheme is ruled** [AD-134]: **arrows for cardinal movement, Ctrl+Q/E/Z/C for the
diagonals, Alt for the menu, arrows to navigate it, Enter to confirm.**

---

## 9. Ranked difficulty

### 9.0 ★★★★★ THE RANKING RE-TAKEN, 2026-09-06

★★★★★ **The fill is no longer rank 1 by urgency.** ★★★ **It is 2.832 s per room, once per room, on a
53/53 renderer** — ★★ **down 74.5% from where it started, and the player is waiting on a load anyway.**

| | was | is |
|---|---|---|
| the flood fill | ★★★★ **rank 1 since v0.2** | ★★ **finished work** |
| ★★★★ **the storage layer** | not ranked | ★★★★★ **rank 1 — everything has run from a poke harness with NO DISK, and `live-disk` is the only path that gates delivery** |
| ★★★★ **text and input** | not ranked | ★★★★ **rank 2 — the parser's effect is unobservable without it, and a real playthrough needs it** |
| compositing | rank 4 | ★★★ **measured and comfortable: 0.03929 s/cycle at four sprites** |
| ★★★ **the VM** | rank 2 | ★★ **15.7 cyc/s on KQ1 against 10 asked; KQ3 at 9.4 is the only figure short** |
| sound | rank 5 | ★ **unchanged, and not a blocker** [§5.1] |

★★★★ **The re-ranking is measurement, not preference:** ★★★ **every figure above was taken on hardware
at 1.789390 MHz, and the two that moved most — the fill and the VM — moved because they were
decomposed.**

1. **The flood fill** — bounded memory, acceptable latency, nibble addressing.
2. ★ **The residency manager** (§4.4–4.5) — *new at rank 2.* Every title exceeds the resident ceiling and
   KQ4 by 3.7×, so eviction is a mainline path, not an edge case. **Get the tiers wrong and room changes
   thrash.**
3. **The MMU phase discipline** (§3.4) — get the pairs wrong and everything is slow.
4. **Sprite compositing inner loop** — two tests per pixel, every cycle.

★★ **v3 LZW is off this list only while §11.1 stays deferred — and it is now demonstrably ACHIEVABLE.**
Sierra's 1988 CoCo3 interpreter decompresses LZW on this CPU, in the artifact we hold [§11.1]. **The open
question is its COST, not its feasibility** — M-13, measurable at P3's comparison gate.
6. **The parser** — `WORDS.TOK`, said/word matching.
7. **Sound** — AGI's PCjr source is 3 voices plus noise. ★ **POP established a FIRQ-driven monophonic
   player; three voices is a different problem**, scoped separately at P7. ★★ **Sierra's ports do not play
   music during animation — that is an OBSERVATION, not a measured limit** [backlog L-21]. Their
   `AGIVIRQDr` is 222 bytes, and the community added PSG and Speech/Sound-cartridge support to these same
   games in 2026. **We may do better and are permitted to.**
8. **The 203 opcodes** — volume, not difficulty.

---

## 10. Phasing

**P0 — oracle.** ScummVM building locally, pinned (§8.4), instrumented to dump rendered rooms and
per-cycle VM state. **Nothing is written for the CoCo3 until the reference can be diffed against.**
Includes §2.1's row-24 check and §11.1's game-size measurement.

**P1 — resources.** VOL/DIR parsing, v2 then v3 LZW. Offline tools. The image builder (§4.6) begins here.

**P2 — the picture renderer.** Offline first, byte-compared against the pinned oracle. **Then on the
CoCo3, against the same oracle — not against the offline renderer** (§8.2).

**P3 — the display.** GIME mode, palette table, first room on real hardware. **First eye gate. First HAL
contact** — §1.4's sync entry and §1.4.4's inherited-fix review happen here, not before.

★★ **P3b — the poke milestone.** A hardcoded room plus one LOGIC script running on real hardware:
resources placed in memory by MAME's Lua, a scripted input stub instead of the parser, **no disk at all.**

**Marginal cost is one harness.** It reuses P3's probe infrastructure and needs the renderer, the VM
dispatch and the cel compositor — **all three of which are on the critical path regardless.** It skips
`LOADER.BIN`, the DECB bootstrap, the block layer, demand streaming, the RAM-disk, the image builder and
the parser: **most of P6 and all of §4.**

★★★ **Its real value is that it front-loads the two largest unmeasured numbers in the project.** M-02's
fill latency and M-14's compositing cost are **time** questions that offline Python cannot answer — they
need real 6809 cycles. **A poke harness answers both before a byte of storage code exists**, and
discovering the fill is too slow after the loader is written is exactly the expensive order §10's
P2-before-P4 ordering was meant to avoid.

★★ **It can NEVER be a delivery gate.** *Poke hides load and launch bugs* — POP's freeze P2.7, the LOADM
ceiling P3.3 and the EXEC-overwrite P3.5 all lived on the real path and were invisible to poke
[CLAUDE.md §4]. **The launch path is recorded on every gate for this reason**, and `live-disk` remains
the only path that gates delivery.

★ **Sequenced after the renderer port, not before it** — by then the harness is a small addition to
something already working.

**P4 — the VM.** Dispatch, variables, flags, the cycle. State-diffed.

**P5 — views and compositing.**

**P6 — input, parser, and the floppy loader.** A game boots. ★ **The loader depends on P3** — the swap
prompt needs display and keyboard after DECB is gone (§4.8).

**P7 — sound.**

★ **P2 before P4 deliberately.** The renderer is the risk; the VM is volume. **Discovering the fill is
too slow after the interpreter exists is the expensive order.**

★ **§1.4.3's register check is installed before P0's first commit**, not at P3. It costs nothing on an
empty repository and retrofits expensively.

---

## 11. Open questions

### 11.1 ★★★ RE-CLOSED — v2 volumes; v3 deferred, and the scope is THREE PC TITLES

**Reopened 2026-08-25 on AD-28, then re-closed the same day when the corpus was read on both axes.**

**Measured across all 194 rows** [`corpus-classification.tsv`]:

| population | V2 volumes | V3 volumes |
|---|---|---|
| fan (PC) | **147** | 0 |
| PC/DOS | **3** | 0 |
| **CoCo3** | **1** (`KQ3/Original`) | **32** |

★★ **V3 volumes are a CoCo3 artifact exclusively** — Guillaume Major's conversions. **Nothing on the PC
side uses them.** ★ And the V2 classification is a positive result, not a default: `vol_method` reads
*"V3 walk hit a bad signature"* — the classifier tried V3 first and it failed.

**So the three tiers of "v3 support" are worth very different amounts:**

| | unlocks |
|---|---|
| **V2 volumes** — done, oracle-verified 2410/2410 | **all 153 PC-side rows** |
| v3 DIRs + V3 volumes | **three PC titles**: Gold Rush!, Manhunter 1, Manhunter 2 |
| ★ V3 volumes alone | the CoCo3 conversions — **content already stripped** (§1.2a) |

★★★ **The third tier is DECLINED on purpose, not on cost** (§1.2a). **The deferral in D-15 covers the
second tier only — three PC titles.**

★ **Feasibility is settled**: Sierra's 1988 interpreter decompresses LZW on this CPU. **Only cost is
open** (M-13), and §4.2a's seam already carries the header length as a parameter — proven on its first
real case in `volume.py`.

### 11.1a — REOPENED (2026-08-25), superseded the same day by the above

**Jay ruled 2026-08-24: build for v2, hold v3 deferred. ★★ One leg of the argument has since been
measured false and the decision should be re-taken, though nothing is blocked meanwhile.**

**What changed** [T-P0-005 §3D, backlog AD-28]:

> **Six of seven CoCo3 titles have V2 DIRECTORIES but V3 VOLUMES** — 7-byte headers, LZW-compressed.
> ScummVM's own comment names the cause: *"Fan ports of DOS games to CoCo3 use V3 volumes; presumably
> they used the Leisure Suit Larry interpreter."* **`KQ3/Original` is the single V2-volume build in the
> whole CoCo3 corpus** — one of the two genuine Sierra releases, exactly as that comment predicts.

★★★ **The consequence that matters: Sierra's 1988 CoCo3 interpreter decompresses LZW on a 6809.** The
thing §9 ranked as a risk is **demonstrated working on the target machine**, by the artifact in hand.
v0.4 and v0.5 both stated *"no CoCo3 precedent for v3"*; that was true of directories and false of
volumes.

**What this does NOT change:**
- v2 volumes remain the build target and P1's layer is oracle-verified against them.
- The three *v3-directory* titles are still only Gold Rush and the two Manhunters.
- **Nothing is blocked.** §4.2a's seam already carries the header length as a parameter.

**What it changes:** the deferral was argued on *"no precedent, one 106 KB sample, and a decoder gated on
nothing."* **There is now precedent on the exact CPU, and most of the CoCo3 corpus is LZW data.** ★ And
under §4.4's demand streaming the case was always performance rather than compatibility — **compressed
resources mean fewer track reads per room change**, on the titles that stream hardest.

**For Jay to re-take.** Recommended input first: **M-13 — what does LZW cost on the 6809**, measurable
against Sierra's interpreter at P3's comparison gate (D-14).

### 11.1a — the original ruling, retained for its reasoning

**What the decision actually covers, since this took two wrong turns to state clearly:**

- **v3 affects three games — Gold Rush!, Manhunter 1, Manhunter 2** [`agi.h:122,128,129`]. Everything else
  Sierra shipped, and the entire fan library, is v2.
- ★★ **All three already exist for the CoCo3 in v2 form.** Every one of the ten CoCo3-hosted titles
  parsed uses the v2 layout — separate `logDir`/`picDir`/`viewDir`/`sndDir`, no combined `*DIR` anywhere.
  **The community converted the LZW host-side**, which is the choice AD-12 forbids us but was open to
  them.
- **So a v2-only interpreter plays all three**, from converted community resources. **What it cannot do
  is accept the PC v3 release a user buys today.** That is the entire compatibility cost.

★ **The measured cost of their choice: conversion roughly DOUBLES the bytes.** Gold Rush 1,217,985 ·
Manhunter 2 1,207,033 · Manhunter 1 1,035,388 — **the three largest titles in the corpus**, and the three
furthest over the resident ceiling.

★★ **Which inverts the argument under §4.4's demand streaming.** The 1988 conversion traded space for CPU
because space was cheap and CPU was not. **Our constraint is the opposite**: compressed resources mean
fewer track reads per room change, on exactly the titles that stream hardest. **The case for v3 is
performance, not compatibility** — and it cannot be judged until §11.2's fill and streaming costs are
measured.

**Deferred to D-15** with an explicit trigger. §4.2a is what keeps the deferral honest.

### 11.2 Remaining measurements

1. ★★ **Fill latency** (§6.2). What room-change delay is acceptable, and does scanline fill meet it?
   **The project's largest technical risk**, and P2 is deliberately before P4 for this reason.
2. **Working-set behaviour under demand paging** (§4.4). The global tier is ≈10–12%; what does the phase
   tier cost at a room change on floppy, and on SDC?
3. **KQ3 consolidated media are ≈5,600 B short of the disk sets** [backlog M-11] — probably `vol.14`.
   Cheap to settle, and a dropped volume is a game that breaks somewhere specific.

**Closed since v0.3:** line count [AD-01] · per-game sizes [M-01a] · why KQ3 needed ten sides [M-10] ·
oracle determinism, with a clock-coupling qualification [M-08] · the row-24 question [AC-7].

**Deferred, not open:** composite palette table · builder-side v2 compression · sound scope at P7 ·
128 KB as an SDC-only stretch target.
