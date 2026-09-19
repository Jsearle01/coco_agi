## Form B Report — T-P0-104 / P6.49 — `CP_CEL` over the arena: asserted red, and the three shapes priced
**Class:** measurement.  wip.  Descends from `8654a56`.
★★★★★ **No fix attempted. §7 is addressed to Jay.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-19 12:25 (HEAD 8654a56, wip). One `src/harness/` file (an assertion, zero emitted bytes);
four harness tools.

### 1 — Summary

★★★★★ **The overlap is a static error now, and §1.1's arithmetic was wrong in the direction that
matters: the move-down cost is 1,456 bytes, not 688.**

★★★★★ **Shape 2 is blocked by measurement.** Arena occupancy had never been measured; it is
**15,376 of 16,384 in the text arm — 1,008 bytes free**, against the 1,456 that shape needs.

★★★★★ **Shape 3's oracle citation changes the question.** ScummVM has **no shared staging buffer at
all**: `unpackViewCelData` does `new byte[width * height]` **per cel** and keeps it with the loaded
VIEW [`view.cpp:358,365`]. ★★★★ **The 4,784-byte buffer is entirely ours**, and the decode is
row-oriented on both sides — so the buffer's natural size is one ROW, ~160 bytes.

★★★★ **And one fact the dispatch did not have: the decode CLEARS its whole destination first**
[`view_cel.s:184-188`]. An over-margin cel **zeroes** 1,456 bytes of the VIEW it is about to read.
Not a gradual overwrite — a wipe, before the unpack touches a byte.

### 2 — Files modified
- `src/harness/p3b_probe.s` — the assertion, the overlap recorded **beside `CP_CEL_END`**, and
  `-DP3B_ACCEPT_CEL_ARENA`. **Zero emitted bytes.**
- `harness/tools/gates.manifest` — the accepted-defect record, both live titles, the flag.
- `harness/tools/p3b_show.ps1` — the acceptance; `res_top`/`res_ccur` in `$WANT`.
- `harness/tools/p3b_run.lua` — **arena occupancy, which had no producer.**
- `harness/tools/p3b_arms_check.ps1` — the `p3b` row's acceptance flag.

### 3 — Pre-dispatch grep (C-13)

**§7's arithmetic check, first, because everything else rests on it.** ★★★★★ **`$5050` and `688`
are both wrong.** `$6000 − 4,784 = $4D50`; `$5050` would clear only 4,016 of the 4,784. **The
move-down cost is `$5300 − $4D50` = 1,456 bytes — exactly the overlap**, which is the arithmetic
that makes sense: you must move down by precisely what you overrun by.

**§3(1)** Seven arms and every non-`p3b` probe at P6.48's figures ✔ (SHA-256).

**§3(2) — every `CP_CEL` consumer. ★★★ There are TWO address operands, not one.**

| site | form | assumes |
|---|---|---|
| `p3b_probe.s:1695` | `ldx #CP_CEL` → `vc_dest` | address only |
| ★★★ **`composite.s:105`** | **`ldd #CP_CEL` → `co_src`** | **address only** |
| `p3b_probe.s:2087` | `CP_CEL_END equ CP_CEL+4784` | extent |

★★★★ **Nothing assumes alignment, a page boundary or a fixed offset** — both operands load the
address into a variable. **So moving `CP_CEL` is a pure `equ` change.** AD-191 named `ldx #CP_CEL`;
the second one is in `composite.s` and would have been missed by a grep of `p3b_probe.s` alone.

**§3(3) — the arena's occupancy ceiling. ★★★★★ IT HAD NEVER BEEN MEASURED.** `res_top` is exported
and read by `vm_run.ps1` and `vm_sweep.lua`, but only instantaneously, and **`res_ccur` — the
cache allocator, growing down — was read by nothing at all.** Occupancy is the sum of the two and
had no producer. Now sampled at every park:

| arm | scenario | peak used | free |
|---|---|---|---|
| cel (`p3b`) | KQ1, 160 cycles, room 1 | 13,669 / 16,384 | **2,715** |
| text (`-ResCheck`) | KQ1, 400 cycles, room 1, input | ★★★ **15,376 / 16,384** | ★★★★ **1,008** |

★★★ **Park-sampled, therefore a LOWER BOUND**, and reported as one: the peak is mid-cycle, while a
VIEW is open on top of the cached logics inside `p3_composite_all`, and the sample is taken at the
cycle boundary where that frame has already been popped. **Stack reads 0 at every park; the whole
figure is cache.**

**§3(4)** `vc_decode_cel` writes sequentially **after clearing `vc_tested` bytes** — see §1.

### 4A — ★★★★★ The assertion, RED

```
src/harness/p3b_probe.s(2116) : ERROR : User Specified: "the decoded-cel buffer overlaps
RES_ARENA by 1,456 bytes -- CP_CEL $5300 + 4,784 runs to $65B0 and the arena starts at $6000,
where res_top places the VIEW being decoded FROM. Kingquest3 (view 64/0/0, 4,784 B) and larry1
(3 cels) exceed the 3,328 B margin; KQ1/KQ2/PQ1 do not. -DP3B_ACCEPT_CEL_ARENA to build with the
defect, which is where this arm is until the shape is ruled on."
```
With the acceptance: **13,870 B `F875F7F6` — byte-identical**, because an assertion emits nothing.
Recorded in `gates.manifest` with both live titles and the reason every gate run has been clean.

### 4B — ★★★★★ The three shapes, priced

| | shape | cost | from a measurement | verdict |
|---|---|---|---|---|
| **1** | **Move `CP_CEL` down to `$4D50`** | **1,456 B out of region A** | `size_decompose.py` over the cel arm's listing | ★★★ **not by shrinking — by MOVING** |
| **2** | **Shrink residency by 1,456 B** | 1,456 B of arena | **peak 15,376/16,384, 1,008 free** | ★★★★★ **BLOCKED — 1,456 > 1,008** |
| **3** | **Do not stage a whole cel** | ~160 B buffer, **frees ~4,624 B** | `view.cpp:358` + row-oriented decode | ★★★★ **largest win, largest risk** |

**Shape 1 — where would 1,456 bytes come from?** Region A holds **12,684 bytes** over `$2000-$5300`
and every one of them is the interpreter: `vm_cmds` 1,805 · `vm_run` 1,671 · `pic_fill` 1,431 ·
`res_core` 1,024 · `p3b_probe` 734 · `vm_objects` 697 · `vm_cycle` 591 · `pic_core` 588 ·
`vm_core` 571 · `composite` 546 · `vm_tables` 525 · `view_cel` 518 · `pic_draw` 457. ★★★★ **Nothing
here shrinks by 1,456 without deleting a subsystem.**

★★★★★ **But L-126 says ask what could MOVE first, and the answer is already built.** The cel arm
still uses a **FLAT vocabulary in region B** (`$E3BA-$FF00`, 6,982 B for a required 6,828 — **154
free**). The text arms window theirs into slot 5, which is P6.36's `PHASE_VOCAB`, already
implemented and gated. ★★★★ **Windowing the cel arm's vocabulary frees ~6,982 bytes of region B**,
and `composite.s` + `view_cel.s` + `pic_draw.s` = **1,521 bytes** could be org'd there. **So shape 1
is "window the cel vocabulary, move three files to region B, drop `CP_CEL` to `$4D50`"** — no code
is deleted.

**Shape 2 — blocked, and the measurement is why.** 1,008 free against 1,456 needed, and the figure
is a lower bound. ★★★ **Shrinking the arena also raises the eviction rate**, which `res_cevict`
already counts and which caused `RES_E_BIG` once before [T-P0-037].

**Shape 3 — ★★★★★ the buffer is ours.** [`view.cpp:357-370`, pin 9d9b9e93]
```
void AgiEngine::unpackViewCelData(AgiViewCel *celData, ...) {
    byte *rawBitmap = new byte[celData->width * celData->height];
    ...
    celData->rawBitmap = rawBitmap;
    ...  rawBitmap += celData->width;      // ← row by row
```
★★★★ **The oracle allocates per cel and keeps it for the VIEW's lifetime — it has no shared staging
buffer**, so "one 4,784-byte buffer" is not something AGI requires. It is the port's answer to not
being able to hold them all, which is §2V's cost-model divergence exactly.
★★★★ **And both sides decode ROW BY ROW**, and `composite.s` consumes `co_src` a row at a time with
`co_remh` — so a row-at-a-time decode needs **~160 bytes**, not 4,784.
★★★ **The risk is real and is the mirroring**: it is applied during the unpack, and reverses within
a row. **Per authority §2.1 this is ScummVM's structure, not a claim about Sierra's interpreter.**

### 4C — ★★★★ Would the shape free enough region A to host the checksum?

The instrument needs **518 bytes** and the cel arm has **eight** [P6.48 §6.2].

| shape | region A after | hosts `-DRES_CHECKSUM`? |
|---|---|---|
| 1 | unchanged (the 1,456 comes from region B) | ✘ **still 8 bytes** |
| 2 | unchanged | ✘ |
| 3 | ★★★★ **+~4,624 B** | ★★★★★ **yes, comfortably** |

★★★★★ **Only shape 3 lets the cel corpus ever be run through the checksum**, which is the one
measurement that would confirm a fix rather than infer it. **That is a selection criterion that no
byte count alone shows.**

### 4D — The two adjacent items
**`vmtr_buf` `$6500`** — still dormant; no `p3b` arm defines `VM_TRACE`. **`TX_WIN` `$6000`** — the
text window and the arena remain the same addresses in different phases, unasserted. ★★ Neither
touched; §3's enumeration turned up nothing new about either.

### 5 — Verdict-time evidence (v0.7 §11)
```
AC-1  assertion RED in the cel arm (message above); -DP3B_ACCEPT_CEL_ARENA green,
      13,870 B F875F7F6 -- byte-identical; gates.manifest records both live titles
AC-2  1,456 B (not 688) / blocked at 1,008 free / ~160 B with view.cpp:358 cited
AC-3  arena peak MEASURED for the first time: cel 13,669 free 2,715; text 15,376 free 1,008
      -- park-sampled lower bounds; res_ccur had never been read by anything
AC-4  only shape 3 frees region A enough to host the checksum (518 B against 8)
AC-5  all 7 p3b arms + vm/pic/res/cel/comp byte-identical (SHA-256); the acceptance emits nothing
AC-6  vm 9/9 PASS; res 1264/1264 (100.00%); renderer 45/45
AC-7  pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22 -- all green
      p3b_rescheck: 12 baselined, 1586 verified, 0 mismatches
      mojibake clean; RED ($44) inside the rect: 0
AC-9  hal_sync x3 OK   reg-discipline 17/1/4   gen_vm_tables --check OK   arms self-test red
git diff --stat : gates.manifest 19 | p3b_arms_check 6 | p3b_run.lua 28 | p3b_show.ps1 13
                  p3b_probe.s 29   -- zero emitted bytes
```
**25.2:** N/A. **25.3:** N/A — no shipped artifact changed.

### 6 — Reactive deviations and route accounting
1. ★★★★★ **§1.1's arithmetic was wrong and I used the corrected figure throughout.** 688 → **1,456**.
   Had I priced shape 1 at 688 it would have looked half as expensive as it is, and shape 2's
   blockage would have read as a near-miss rather than a 448-byte shortfall.
2. ★★★★ **The acceptance flag is passed UNCONDITIONALLY in `p3b_show.ps1`**, not only on the cel
   branch: `CP_CEL` does not exist under `-DP3B_NO_CEL`, so it is inert there, and one line beats
   remembering which arm needs it next time.
3. ★★★ **`res_ccur` was added to `$WANT`** — it existed and nothing read it, which is why §3(3) had
   no answer to give.
4. **ROUTE ACCOUNTING.** §4A, §4B, §4C and §4D are answered. ★★★★★ **Nothing was moved, shrunk or
   re-shaped. No fix attempted.**

### 7 — ★★★★★ THE RULING, FOR JAY

**The defect:** in the cel configuration a decoded cel can be 4,784 bytes from `$5300`, and the
arena starts at `$6000`. **Kingquest3 has exactly such a cel; larry1 has three.** The 1,456-byte
overrun **zeroes** the VIEW the decode is reading from. Every gate run uses Kingquest1, where the
largest cel is a quarter of the margin — **which is why this has never been seen.**

**Three shapes:**

**1 — Move `CP_CEL` down to `$4D50`.** Costs 1,456 bytes of region A, and **no code need be
deleted**: window the cel arm's vocabulary (P6.36's mechanism, already built and used by every text
arm), which frees ~6,982 bytes of region B, then org `composite.s`/`view_cel.s`/`pic_draw.s`
(1,521 B) there. ★★ **Forecloses nothing. Leaves region A as tight as it is today**, so the cel arm
still cannot host the checksum.

**2 — Shrink the arena.** ★★★★★ **Blocked by measurement: 1,008 bytes free against 1,456 needed**,
and that figure is a lower bound. **Not available without also reducing residency**, which raises
eviction and has caused `RES_E_BIG` before.

**3 — Decode a row at a time.** ★★★★★ **The oracle keeps no shared staging buffer** — it allocates
per cel and holds it with the VIEW — **so the 4,784-byte buffer is our design, not AGI's.** Both
sides decode row-wise and the compositor already consumes rows, so the buffer becomes ~160 bytes.
★★★★ **Frees ~4,624 bytes of region A**, eliminates the overlap outright, and is **the only shape
that lets the cel corpus be run through the resource checksum.** ★★★ **The risk is the mirroring,
applied inside the unpack and reversing within a row** — a real behavioural change to a gated
subsystem, against `cel` 6 titles and `comp` 6 titles.

**My ranking, not a decision:** ★★★★ **3, then 1.** Shape 3 is more work and more risk and it is the
only one that leaves the configuration better than it found it; shape 1 is safe, mechanical, and
leaves the arm unable to verify itself. **Shape 2 is off the table.**

### 8 — Follow-up candidates
1. ★★★★★ **Whichever shape Jay rules**, then re-run the cel corpus.
2. ★★★★★ **The title-screen scroll** [P6.47 §7.6] — still next on the milestone path.
3. ★★★★ **A guest-side arena high-water mark.** The park-sampled figures are lower bounds and the
   true peak is mid-cycle; shape 2's blockage is therefore understated, not overstated.
4. ★★★ **`TX_WIN`/arena phase invariant** and **`vmtr_buf`** (§4D) · PICTURE and SOUND checksum sites.
5. ★★ **Design spec §8B.9**: resource bytes ARE gated after a bind, with P6.48's four exclusions —
   **PROPOSED TEXT ONLY** [§2D].

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-19-the-headroom-nobody-had-measured-decided-the-design.md`
- `seeds/AGI/live/2026-09-19-ask-the-oracle-whether-the-buffer-is-even-ours.md`

### 11 — Commit
`2f9df3c` (pushed to origin/wip before this report).
