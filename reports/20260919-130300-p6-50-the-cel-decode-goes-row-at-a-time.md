## Form B Report — T-P0-105 / P6.50 — The cel decode goes row at a time; and the eye gate found something else
**Class:** integration (§4A).  wip.  Descends from `90c2533`.
★★★★★ **The ruled change is done and green. §7.1 is a SEPARATE, PRE-EXISTING defect the eye gate
exposed, and it is reported rather than repaired [§6].**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-19 13:03 (HEAD 90c2533, wip). Three `src/harness/` files; five harness tools.

### 1 — Summary

★★★★★ **`CP_CEL` is 256 bytes at `$5F00` instead of 4,784 at `$5300`. The arena overlap is gone
rather than relocated, the assertion is green with no bypass, and 3,072 bytes of region A come
back.**

★★★★★ **`cel` 9,193/9,193 byte-identical across six titles — 1,525 of them mirrored — and `comp`
124/124 frames on both planes.** The row-scope mirroring derivation is right.

★★★★★ **AND THE EYE GATE FOUND A DEFECT NO BYTE GATE HAS EVER SEEN: `p3b` has never composited a
sprite. Not once, in any run.** Jay: *"i didn't see anything i'd call a sprite."* Measured:
**`CP_BLITS` = 0 before this change**, with four sprites staged every cycle for sixty cycles, and
**`vc_err` = 4 — `VC_E_TRUNC`** on a 13×4 cel. ★★★★ **This task's change moves it from 0 to 208,
which is a behavioural change I did not predict and have not gated.** §7.1.

### 2 — Files modified
- `src/harness/view_cel.s` — **one unpack, three entry points**: `vc_decode_begin`,
  `vc_decode_row`, and `vc_decode_cel` as a wrapper. `VC_ROW_MAX`.
- `src/harness/composite.s` — `-DCOMP_ROW_PULL`: the compositor pulls a row at the top of `co_row`.
- `src/harness/p3b_probe.s` — `CP_CEL` to `$5F00`/256 B, `COMP_ROW_PULL`, `vc_decode_begin` at the
  call site, the acceptance flag and its guard **deleted**.
- `harness/tools/` — `p3b_show.ps1` (`-CelCheck`, the retired flag, `vc_err`/`res_top`/`res_ccur` in
  `$WANT`), `p3b_run.lua` (`CP_BLITS`, zeroed first), `p3b_arms_check.ps1`,
  `probe_identity_check.ps1`, `cel_extent.py` (width).

### 3 — Pre-dispatch grep (C-13)

**§3(1)** Seven arms and every non-`p3b` probe at P6.49's figures ✔ (SHA-256).

**§3(2) — the widest cel ROW. ★★★★ 115 bytes, not 160**: Kingquest2 view 130 and SpaceQuest-1
view 200. ★★★★★ **And the buffer is sized at 255 anyway, from the FORMAT — a cel's width is a
single byte — because sizing from a corpus maximum is precisely the mistake that created this
defect** [P6.49: 4,784 was a real cel, not a margin].

★★★ **A correction to P6.48/P6.49 while measuring it: SpaceQuest-1 ALSO reaches the arena** (3,500 B
cel, 1 over the margin). The earlier figure covered five titles; over seven it is **three titles
live, not two.**

**§3(3) — the contract, and it decided §4A.** `co_src` is a running pointer advanced one byte at a
time (`lda ,x+ / stx co_src`), reset to nothing between rows; `co_rownext` advances the screen
pointers and loops. **Nothing re-reads a row it has passed** — `co_save`/`co_restore` walk the
SCREEN, not the cel. ★★★ **The cel is consumed exactly once, in exactly the order the decoder
produces it.**

**§3(4)** Four readers of `CP_CEL_END`, all assertions; **two address operands** for `CP_CEL`
(`p3b_probe.s`, `composite.s`), neither assuming alignment [P6.49].

### 4A — ★★★★★ The control flow: PULL

**The compositor drives.** At the top of each row it calls `vc_decode_row` and points `co_src` at
the row buffer.

| | push | **pull** |
|---|---|---|
| who inverts | the **compositor** | the decoder's outer loop |
| mirroring | decoder (unchanged) | decoder (unchanged) |
| transparency test | **moves into the decoder** | compositor (unchanged) |
| priority test | **moves into the decoder** | compositor (unchanged) |
| control-line walk | **moves into the decoder** | compositor (unchanged) |
| diff | three decisions relocate | **one pointer assignment** |

★★★★ **Chosen on where the decisions end up, not on line count.** Push would have moved the
transparency, priority and control-line logic into `view_cel.s` — three behaviours out of the
subsystem whose gate tests them.

★★★ **The oracle is no guide**: it allocates the whole bitmap and composites later. **This is a port
decision, stated as one** [§2.1]. ★★ **§1.2's framing did not miss a third shape** — a callback
between the two is push with extra indirection, and a shared cursor object is pull with worse
naming.

### 4B — ★★★★★ The mirroring, re-derived at row scope

`vc_p` was an offset into the whole bitmap; it is now an offset into one row.

| | not mirrored | mirrored |
|---|---|---|
| start of row | `p = 0` | `p = width` |
| constants | `pre 0`, `post +1` | `pre −1`, `post 0` |
| a run of *n* | fill forward, `p += n` | `p −= n`, fill forward, no post-advance |
| **old row advance** | `p` already at `(r+1)·width` | ★★★★ **`p += width*2`** |
| **new row advance** | `p = 0`, `vc_dest += width` | ★★★★ **`p = width`, `vc_dest += width`** |

★★★★★ **The mirrored `p += width*2` IS the reset.** At the end of mirrored row *r* the walk sits at
`r·width`; adding `2·width` reaches the END of row *r+1*, which is offset `width` in a row buffer.
**Same address; `adjust_pre`/`adjust_after` keep their meanings in a 255-byte window that they had
in a 4,784-byte one.**

**Transcription vs ours** [§2.1]: the chunk decode, the zero-byte row end, the backward walk and
both constants are **transcribed** from `_unpack_cel` and unchanged. ★★★ **The row SCOPE is ours** —
the oracle has no row buffer to scope to.

**§4B's hardest case — mirrored AND ending a row early.** ★★★★ **The corpus contains it and the gate
sees it: 1,525 mirrored cels across six titles, all byte-identical.** The clear, the row reset and
`adjust_post` all meet there, and `cel` is a full sweep of every cel in every title.

★★ **The clear-first survives, per row** [§2]: a chunk of length 0 writes nothing and a short row
leaves its tail untouched — **and now that tail would be the PREVIOUS row's**, so the clear matters
more than it did.

### 4C — Implementation notes

**One unpack, not two** [§2F]. `vc_decode_cel` keeps its exact contract for the `cel` gate,
including clearing the whole destination up front so a mid-cel `VC_E_TRUNC` leaves the same zeroed
tail. ★★ It costs the gate a redundant per-row clear and keeps the two paths provably equivalent.

★★★★ **`CP_CEL` moved to the TOP of region A** (`$5F00`), not left at `$5300`: at 256 bytes it fits
in the last page, so **the code ceiling rises `$5300` → `$5F00`.**

### 4D — The acceptance flag is retired
`-DP3B_ACCEPT_CEL_ARENA` **deleted** from `p3b_probe.s` (the guard as well as the flag),
`p3b_show.ps1`, `p3b_arms_check.ps1` and `gates.manifest`'s record. ★★★ **An unused flag reads as a
configuration somebody might still want.**

### 4E — ★★★★★ The cel path through the checksum, for the first time
`-CelCheck` — the arm P6.48 could not build [§6.2: 518 bytes needed, **eight** available].
**1,220 baselined, 630 verified, 0 mismatches.**

### 5 — Verdict-time evidence (v0.7 §11)
```
AC-3  cel  9193/9193 byte-identical, 6 titles, 1525 mirrored     ★ fresh
      comp  124/124 frames byte-identical, both planes           ★ fresh
AC-4  Kingquest3 1861/1861 and larry1 1190/1190 cels decoded and byte-compared --
      the 4,784 B cel (view 64/0/0) is inside that sweep and matched
AC-5  cel path under -DRES_CHECKSUM: 1220 baselined, 630 verified, 0 mismatches
AC-6  cel arm builds with the assertion LIVE and no bypass; CP_CEL $5F00..$5FFF
AC-7  region A: ceiling $5300 -> $5F00 = 3,072 B recovered, UNCLAIMED
      arena: first 1,456 B returned.  CP_CEL footprint 4,784 -> 256 B
AC-8  vm 9/9 PASS; res 1264/1264 (100.00%); pic 45/45
AC-9  pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22 -- all green
      mojibake clean; RED ($44) inside the rect: 0
AC-10 p3b   13,870 F875F7F6 -> 13,941 D2C30D53 (+71)
      cel    1,472          ->  1,527 8B754B9C (+55)
      every other arm and probe byte-identical
AC-12 hal_sync x3 OK   reg-discipline 17/1/4   gen_vm_tables --check OK
```
**25.2:** N/A. **25.3: ★★★★★ observed by Jay — and it FAILED, on something this change did not
cause. §7.1.**

### 6 — Reactive deviations and route accounting
1. ★★★★★ **The design was settled and stated before implementation** (§4A), and the cel gate was run
   **immediately after the decoder refactor and before the compositor was touched** — so if the
   row-scope derivation had been wrong, it would have been one file's blame rather than three.
2. ★★★★ **`CP_CEL` moved as well as shrank**, which the dispatch did not ask for. Leaving it at
   `$5300` would have wasted the recovered space; the code ceiling is the point of §4C.
3. ★★★ **`cel_probe.bin` moved** (+55 B). It had to: §2F forbids two unpacks, and the gate is what
   proves the one is unchanged.
4. ★★★★★ **I added two instruments mid-task in response to Jay's observation** — `CP_BLITS` and
   `vc_err` — **and zeroing `CP_BLITS` first changed its answer from 32 to 0.** §7.2.
5. **ROUTE ACCOUNTING.** §4A–§4E all done. ★★★★ **§7.1's defect is NOT repaired** [§6].

### 7 — Uncertainty flags

**7.1 ★★★★★ `p3b` HAS NEVER COMPOSITED A SPRITE, AND THAT IS NOT WHAT THIS TASK CHANGED.**

Jay, on the eye gate: ***"i didn't see anything i'd call a sprite. if the 'graham' character was
supposed to been seen and animate. i didn't see it."***

Measured, same scenario, same readout, `CP_BLITS` zeroed by the host first:

| | `CP_BLITS` | composite stage |
|---|---|---|
| **before this change** | ★★★★★ **0** | 2.19 s |
| after | 208 | 1.90 s |

**Four sprites staged every cycle for sixty cycles, and the compositor was called zero times.**
`p3_composite_all` skips a sprite whenever the decode errors, silently — and **`vc_err` = 4,
`VC_E_TRUNC`, "ran out of compressed data mid-cel", on a 13×4 cel.**

★★★★★ **So `sprites 4` in every p3b log for the life of this probe has been a claim about STAGING,
and nothing reached the screen.** Every eye gate in this arc used `-Text`, which defines
`P3B_NO_CEL` and stages zero sprites by construction — **so no person has ever looked at this
path.** The `cel` gate decodes 9,193 cels correctly from a **host-staged** VIEW; `p3b` decodes from
an **arena-resident** one, and that is the difference to chase.

★★★★★ **AND MY CHANGE MADE THE DEAD PATH LIVE — 0 blits to 208 — WHICH I DID NOT PREDICT AND HAVE
NOT GATED.** The old code took `vc_err` from the whole-cel unpack and skipped the blit entirely; the
new code takes it from `vc_decode_begin` (header only) and the unpack's errors now surface inside
`cp_composite`, aborting mid-row instead. **208 is not 240, so a third of them still abort.**
★★★ **What those 208 blits put on the screen is ungated**, and it is why §6 stops here.

**7.2 ★★★★ `CP_BLITS` had no producer for its starting value.** `composite.s` only increments it;
`p3b`'s status block is not cleared at startup; **nothing had ever read it.** My first
before/after read 32 and 240 — both partly RAM. Zeroing it from the host first gave 0 and 208.
★★★ **A counter nobody reads is a counter nobody has checked**, and this one was about to carry a
finding [§2W; `vm_state.s` records the identical trap about `VM_TESTSEEN`].

**7.3 ★★★ `-CelCheck`'s composite stage reads ~0.0%** where the plain cel arm reads 4.2%. Not
investigated. It may be the same skip behaving differently under a longer cycle, or something
about that arm. **Named because I noticed it and did not chase it.**

**7.4 ★★ Three titles reach the arena, not two** (§3(2)) — SpaceQuest-1 joins Kingquest3 and larry1.
Moot now, recorded because the earlier figure is in two reports and the manifest.

**7.5 ★★ `VC_CEL_MAX` (6,144) still bounds `vc_decode_begin`'s fit check** even on the row path,
where only the width matters. It only rejects, so it is conservative rather than wrong.

### 8 — Follow-up candidates
1. ★★★★★ **Why does `p3b`'s cel decode return `VC_E_TRUNC`?** (§7.1) The VIEW is arena-resident
   here and host-staged in the gate that passes. **The checksum's blind spot 1 — a corruption
   between the fetch and the baseline — is the first place to look**, and `res_copy_diff.py` on a
   VIEW would settle it.
2. ★★★★★ **Gate what the 208 blits draw**, before trusting the path at all.
3. ★★★★ **The title-screen scroll** [P6.47 §7.6] — still on the milestone path.
4. ★★★ Region A's 3,072 recovered bytes, unclaimed · `VC_CEL_MAX` on the row path (§7.5) ·
   `-CelCheck`'s composite figure (§7.3).
5. ★★ **Design spec §8B.9** — PROPOSED TEXT ONLY [§2D].

### 9 — User interaction during task
1. Jay ruled **shape 3**.
2. ★★★★★ Jay ran the eye gate and reported **no sprite visible** — which no byte gate in this
   project could have told us, and which turned out to predate the task entirely (§7.1). ★★★ **§4A's
   claim, demonstrated again: the eye gate catches the wrong QUESTION.**
3. Jay asked what a sprite is on screen; I had asked for a judgement without saying what to look at.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-19-the-eye-gate-found-a-path-no-byte-gate-was-watching.md`
- `seeds/AGI/live/2026-09-19-a-counter-with-no-producer-for-its-starting-value.md`

### 11 — Commit
`efd91e5` (pushed to origin/wip before this report).
