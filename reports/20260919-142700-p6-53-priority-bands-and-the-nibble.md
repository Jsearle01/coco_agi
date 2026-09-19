## Form B Report — T-P0-108 / P6.53 — The priority bands exist; and the compositor never doubled the nibble
**Class:** integration (§4A).  wip.  Descends from `81478b4`.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-19 14:27 (HEAD 81478b4, wip). One `src/harness/` file; two harness tools.

### 1 — Summary

★★★★★ **Graham is on screen.** Jay: *"so i see graham this time."* ★★★ **The band table existed as
an address and nothing else since it was declared; it is 168 bytes of data and ~29 of code.**

★★★★★ **Measured, before and after, same scenario:** `co_rej_pri` **4,732 → 0** and `co_written`
**8,784 → 13,516** — ★★★★ **exactly +4,732.** Every pixel that was being rejected on priority is
now drawn.

★★★★★ **AND THE EYE GATE FOUND THE NEXT ONE, WHICH IS NOT MIRRORING.** Jay: *"him and the flags
look to be missing every other row of pixels."* ★★★★★ **`pic_core.s` stores `scr_dbl` — the colour
nibble DOUBLED, `(c & 15) * 17` — because in `p3b` the visual plane IS the 4bpp display
framebuffer. `composite.s`'s `co_put_visual` stores `co_col` RAW.** Every sprite pixel renders as
one black pixel and one coloured one. §7.1.

★★★ **I measured the plane before concluding: every row of every sprite's bounding box has
pixels.** The compositor's row walk is correct; the artefact is per-BYTE, not per-row.

### 2 — Files modified
- `src/harness/vm_objects.s` — `vm_pri_bands` (168 B), the derivation in `vm_update_objs`,
  `-DVM_NO_PRI_BANDS`, and one `bhi` → `lbhi`.
- `harness/tools/p3b_run.lua` — `co_written`/`co_rejkey`/`co_rejpri`, and the per-row plane census.
- `harness/tools/p3b_show.ps1`, `p3b_arms_check.ps1`, `probe_identity_check.ps1` — symbols and
  re-baselines.

### 3 — Pre-dispatch grep (C-13)

**§3(2) first.** ★★★★ **`MAP_PRI_BANDS` has exactly ONE reference in `src/`: its own declaration**
at `memmap.inc:310`. Everything else is prose in reports and the manifest. **The dispatch's premise
holds.**

**§3(1)** Seven arms and every probe at P6.52's figures ✔ (SHA-256).

**§3(3) — the four priority opcodes, and ★★★★ three of the four were already right.**

| opcode | ours | oracle |
|---|---|---|
| `set.priority` | sets `fFixedPriority`, writes `VMO_PRIORITY` | `op_cmd.cpp:415` ✔ |
| `set.priority.v` | same, from a var | `:424` ✔ |
| `release.priority` | clears `fFixedPriority` | `:432` ✔ |
| `get.priority` | reads `VMO_PRIORITY` | ✔ |

★★★★★ **`fFixedPriority` already existed** (`vm_tables.s:71` = `$0004`). ★★★ **Only the derivation
was missing**, and `vm_objects.s:401` says so in as many words: *"checkCollision()/checkPriority()
rollback omitted — both need the priority screen."*

**§3(4)** `co_depth` compares the screen's priority against `co_prio`, staged from `VMO_PRIORITY`
at `p3b_probe.s:1633`. Today's value for an underived object: **0**.

### 4A — ★★★★★ The oracle, four answers

**(1) The table** — `graphics.cpp:1400-1408`, tier 3 (ScummVM):
```cpp
void GfxMgr::createDefaultPriorityTable(uint8 *priorityTable) {
    int16 yPos = 0;
    for (int16 priority = 1; priority < 15; priority++)
        for (int16 step = 0; step < 12; step++)
            priorityTable[yPos++] = priority < 4 ? 4 : priority;
}
```
★★★★ **14 bands × 12 rows = 168 — `memmap.inc:310`'s figure is confirmed by the oracle, not by its
own comment.** Rows 0-47 are all 4 (the `< 4 ? 4` clamp folds four bands together); the default
table's maximum is **14, never 15**.

**(2) Where priority 0 is substituted — ★★★★★ IT IS NOT.** `checks.cpp:110-113`:
```cpp
if (!(screenObj->flags & fFixedPriority))
    screenObj->priority = _gfx->priorityFromY(screenObj->yPos);
```
★★★★★ **The test is the FLAG, not the value.** The dispatch's framing — *"priority 0 means derive
it from Y"* — is not what the oracle does; 0 is merely what an underived object happens to hold.
The only place the oracle tests `priority == 0` is `sprite.cpp:565`, in `add.to.pic`, a separate
legacy path. ★★★★ **And it writes back into the object's field**, which answers §4C: the oracle
rewrites `VMO_PRIORITY`, so we may.

**(3) A game can change it** — `set.pri.base` → `setPriorityTable(priorityBase)` [`op_cmd.cpp:2268`],
which rebuilds all 168 entries from a base. ★★★ **Not wired here, and named rather than wired**
[§6]. **No corpus title is known to call it** — unmeasured, and §7.4.

**(4) The derivation uses `screenObj->yPos`** — the object's own Y, its baseline.

### 4B — The table, where the harness can reach it
`vm_pri_bands`, 168 `fcb` bytes **in the code image**, with an `ifne` that fails the build if it is
not 168. ★★★★ **NOT at `MAP_PRI_BANDS` ($E000): in this probe $E000 is the parser**
[`P3_PARSER_BASE`], and `memmap.inc`'s own header says the harness keeps its own addresses.
★★ **168 bytes of region A; the 3,072 recovered at T-P0-105 are otherwise still unclaimed.**

### 4C — Substituted where the oracle substitutes, as nearly as this port allows
In `vm_update_objs`, once per **active** object per cycle, writing back into `VMO_PRIORITY`.
★★★★ **The oracle derives inside `checkPriority()`, called from `updatePosition()`/`fixPosition()`
— and this port has neither.** The derivation itself needs no priority screen; the rest of
`checkPriority` does. ★★★ **Stated as a port decision, not a transcription** [§2.1].

### 4D — ★★★★★ The measurement

Kingquest1, room 1, 60 cycles. **The derived priorities, against the table:**

| | y | derived | table says | |
|---|---|---|---|---|
| [0] Graham, view 0 | 100 | **9** | rows 96-107 → 9 | ✔ |
| [1] flags, view 97 | 17 | **15** | — | ★★★ **`fFixedPriority`; correctly left alone** |
| [2] view 107 | 161 | **14** | rows 156-167 → 14 | ✔ |
| [3] view 107 | 115 | **10** | rows 108-119 → 10 | ✔ |

★★★★ **AC-2 spot-checked at four rows in three different bands, not just row 0.**

| counter | before | after |
|---|---|---|
| `co_tested` | 31,824 | 31,824 |
| `co_rej_key` | 18,308 | 18,308 |
| ★★★★★ **`co_rej_pri`** | **4,732** | **0** |
| ★★★★★ **`co_written`** | **8,784** | **13,516** |
| `CP_BLITS` | 104 | 104 |

★★★★ **`CP_BLITS` does not move, and should not**: priority rejects PIXELS, inside a blit. §6.2.

### 4E — The eye gate
**Kingquest1, room 1, the ego.** Jay:

> ***"so i see graham this time. but he doesn't move and i can't move him. also him and the flages
> look to be missing every other row of pixels."***

| | |
|---|---|
| 1. Graham on screen? | ★★★★★ **yes — first time** |
| 2. same silhouette flipped? | ★★★ **still not answerable** — §7.1 shreds every sprite; he must look right before he can be compared to himself |
| 3. occludes correctly? | not reported; `co_rej_pri` = 0 means nothing occluded him in this room |
| 4. the flags? | ★★★★ **same defect** — which is what says it is not sprite-specific |

### 5 — Verdict-time evidence (v0.7 §11)
```
AC-1  four oracle answers quoted; (2) overturned the dispatch's framing, (1) confirmed 168
AC-2  bands derived correctly at y=100 ->9, y=115 ->10, y=161 ->14; y=17 left at 15 (fixed)
AC-3  co_rej_pri 4,732 -> 0   co_written 8,784 -> 13,516 (+4,732)   CP_BLITS 104 (unchanged)
AC-4  -DVM_NO_PRI_BANDS builds (14,120 B vs 14,149) and restores the measured prior behaviour
AC-5  comp 124/124 | cel 9193/9193 | pic 45/45 | vm 9/9 (0 of 600 divergent) | res 1264/1264
      ★ comp_probe.bin 967 B 39F5D105 -- BYTE-IDENTICAL
AC-6  Jay, live, RGB -- §4E
AC-7  suite all green; mojibake clean; RED ($44) inside the rect: 0
AC-8  ALL SEVEN p3b arms +199 B, and vm_probe 9,667 -> 9,866 (+199); pic/res/cel/comp identical
AC-9  hal_sync x3 OK   reg-discipline 17/1/4   gen_vm_tables --check OK
```
**25.2:** N/A. **25.3: PASSED in part — Jay, live, RGB.** ★★★ **Graham draws; he is shredded by
§7.1 and he does not move (§7.2).**

### 6 — Reactive deviations and route accounting
1. ★★★★★ **§1's framing was wrong and §4A(2) is the citation.** "Priority 0 means derive it" — the
   oracle tests `fFixedPriority` and never tests 0 on this path. **The conclusion survived and the
   mechanism did not**, which matters because it decides what happens to an object whose fixed
   priority genuinely is 0.
2. ★★★★★ **TWO CORRECTIONS TO MY OWN P6.52.** I wrote that `CP_BLITS` 104-of-208 *"is exactly the
   two view=107 entries never surviving"* — **wrong twice**: blits are not priority-gated (priority
   rejects pixels *inside* a blit), and 208 was never the denominator, since `p3_nspr` only reaches
   4 late in the run. And I quoted `co_tested` as evidence a sprite draws; **`co_written` is the
   counter that means that**, and `co_tested` did not move at all here.
3. ★★★ **I measured the plane before believing Jay's "every other row"** — a per-row census over
   each sprite's bounding box showed **every row populated**. Without it I would have gone looking
   in the row-scope decode, which is where the phrase points and is not where the defect is.
4. ★★ **One `bhi` became `lbhi`** — the derivation pushed `vm_uo_done` out of a short branch's reach.
5. **ROUTE ACCOUNTING.** §4A–§4E answered. ★★★★ **§7.1 is NOT repaired** [§6].

### 7 — Uncertainty flags

**7.1 ★★★★★ THE COMPOSITOR NEVER DOUBLES THE COLOUR NIBBLE, AND THE RENDERER ALWAYS HAS.**

`pic_core.s:113` stores **`scr_dbl`** — *"the doubled byte, precomputed"*, and `:91` says it is
*"identically `(scr_color & 15) * 17`"*. `composite.s`'s `co_put_visual` stores **`co_col`**, the
raw AGI colour index.

★★★★★ **In `p3b` the visual plane IS the display framebuffer** — `CP_VIS equ FB_BASE`, mode 2, 4
bits per pixel, **two screen pixels per byte**. A byte of `$0c` is a black pixel beside a coloured
one; a byte of `$cc` is two coloured pixels. **So every sprite pixel is half black**, which shreds
a small figure and is invisible across flat background — exactly what Jay reported, for both
sprites.

★★★★ **The `comp` gate cannot see it**: `comp_probe`'s plane is a scratch buffer compared against a
reference in the same one-byte-per-pixel format, and **nothing displays it.** ★★★ **Third instance
of this arc's one shape: two subsystems green, no gate on the join** [L-121].

★★★ **Not repaired.** `co_put_visual` is in the file `comp` gates at 124/124, and the reference's
format is the question — changing the write without settling what the gate's reference means would
move a gate on an unexamined premise [§6].

**7.2 ★★★ Graham does not move and cannot be moved.** Not investigated. ★★ The cel arm defines no
`HAL_KEYBOARD` (a text-configuration flag), so there is no input path at all in this build; whether
motion would run without input is a separate question.

**7.3 ★★★ `co_rej_pri` = 0 after the fix.** Nothing occluded any sprite in this room, which is
plausible for the castle exterior at bands 9-15 but is **untested as a positive** — no scenery
nearer than a sprite appeared. ★★ **The priority test is now exercised and has never been seen to
REJECT correctly.**

**7.4 ★★ `set.pri.base` is unwired** (§4A(3)). Named, not wired [§6]. **Whether any corpus title
calls it is unmeasured.**

**7.5 ★★ The clamp is ours.** A `yPos ≥ 168` would index past the table; the oracle asserts, this
clamps to the bottom band. ★ Stated because it is a divergence, however small.

### 8 — Follow-up candidates
1. ★★★★★ **The nibble doubling** (§7.1) — **Graham cannot be judged until it is fixed**, and
   eye-gate question 2 is blocked behind it for the third task running.
2. ★★★★ **Then question 2 at last**: is the ego the same silhouette flipped.
3. ★★★ **Why Graham does not move** (§7.2) · `set.pri.base` (§7.4) · a case where a sprite is
   correctly occluded (§7.3).
4. ★★ Region A's remaining 2,904 bytes · the windowed composite's gate [P6.52 §4E].

### 9 — User interaction during task
1. Jay ran the eye gate and reported three things in one sentence. ★★★★★ **The third — *"missing
   every other row of pixels"* — located §7.1**, a defect no byte gate in this project can see.
   ★★★ **Both of the last two tasks' findings came from that gate**, and neither was a verdict.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-19-the-conclusion-survived-and-the-mechanism-did-not.md`
- `seeds/AGI/live/2026-09-19-two-writers-one-plane-two-formats.md`

### 11 — Commit
`697f804` (pushed to origin/wip before this report).
