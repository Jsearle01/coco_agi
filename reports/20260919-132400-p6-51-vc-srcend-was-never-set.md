## Form B Report — T-P0-106 / P6.51 — `vc_srcend` was never set; and the compositor addresses a windowed plane flat
**Class:** integration (§4A).  wip.  Descends from `864763a`.
★★★★★ **Two defects. The first is fixed and measured. The second is named and NOT repaired [§6].**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-19 13:24 (HEAD 864763a, wip). One `src/harness/` file, **three instructions**; two
harness tools.

### 1 — Summary

★★★★★ **`vc_srcend` — the only bound `VC_E_TRUNC` tests — was never set by `p3b`.** It held its
image value of **zero**, so `cmpx vc_srcend / blo` refused the first compressed byte of every cel
ever fetched. `cel_probe.s:153-154` sets it from `CP_VIEW + CP_VIEWLEN`; `p3b_probe.s` did not.

★★★★★ **`res_open` has always published `res_len`. Nothing in `p3b`'s decode path used it.** Three
instructions fix it.

★★★★★ **AND FIXING IT EXPOSES A SECOND DEFECT IMMEDIATELY: `composite.s` addresses the visual plane
FLAT while `p3b`'s planes are WINDOWED.** `co_rowset` does `addd #CP_VIS`, `CP_VIS equ FB_BASE` is
`$C000`, and row 100 lands at **`$FE80` — the vector stubs** while row 167 wraps to **`$2860` — the
code region.** ★★★★ **Both predicted addresses were observed**: pixel bytes at the IRQ vector
`$FEF7`, and the stall's hot PCs at `$2746`–`$276B` in `vm_rl_args`/`vm_rl_haveargs`.

★★★ **The first real cel composite crashes the machine, in cycle 10.** §7.1.

### 2 — Files modified
- `src/harness/p3b_probe.s` — `vc_srcend` set from `res_base + res_len`, recorded beside the call.
- `harness/tools/p3b_show.ps1` — the cel path's symbols, **scoped to arms that link it** (§6.2).
- `harness/tools/p3b_run.lua` — `vc_srcend`/`vc_src`/`vc_view` and `co_tested` in the readout.
- `harness/tools/p3b_arms_check.ps1` — `p3b` re-baselined with a retirement line.

### 3 — Pre-dispatch grep (C-13)

**§3(1)** Seven arms and every probe at P6.50's figures ✔ (SHA-256).

**§3(2) — the VIEW's journey, and every difference from `cel_probe`. ★★★★★ THIS GREP WAS THE TASK
AND IT TOOK ONE COMMAND.**

| | `cel_probe` (9,193/9,193) | `p3b` (0 drawn) |
|---|---|---|
| where the VIEW is | `CP_VIEW`, **host-staged** | `res_base`, **arena-resident** via `res_open` |
| `vc_view` | `CP_VIEW` | `res_base` ✔ |
| `vc_dest` | `CP_CEL` | `CP_CEL` ✔ |
| `vc_loop` / `vc_cel` | set | set ✔ |
| ★★★★★ **`vc_srcend`** | ★★★★★ **`CP_VIEW + CP_VIEWLEN`** | ★★★★★ **NEVER SET** |

★★★★ **`vc_srcend` has exactly three references in the whole tree**: its `fdb 0` declaration
[`view_cel.s:63`], the write in `cel_probe.s:154`, and the test in `view_cel.s:268`. **A grep for it
is the entire diagnosis.**

**§3(3)** `VC_E_TRUNC` tests **one thing**: `ldx vc_src / cmpx vc_srcend / blo vc_dc_haveb`. The
bound is **not** derived from the cel header, the VIEW header or the resource — ★★★ **the CALLER
supplies it**, because only the caller knows how long the resource is.

**§3(4)** `res_open` returns `res_len` for a VIEW. ★★★★ **Nothing in the decode path used it.** That
is the defect, stated as a one-line answer to the question the dispatch asked.

### 4A — ★★★★★ The two columns, measured

At the moment of failure, `p3b`, Kingquest1 room 1:

```
vc_view=$6000   vc_src=$615A   vc_srcend=$0000   vc_err=4   last cel 13x4
co_tested (cel pixels examined by the compositor): 0
CP_BLITS: 208
```

| | `p3b` | `cel_probe` |
|---|---|---|
| `vc_view` | `$6000` | `CP_VIEW` |
| `vc_src` | `$615A` | header + 3 |
| ★★★★★ **`vc_srcend`** | ★★★★★ **`$0000`** | **`CP_VIEW + CP_VIEWLEN`** |

★★★★★ **The first differing number is `vc_srcend`, and it is the third value compared.**

★★★★ **`co_tested` = 0 CORRECTS MY OWN P6.50 §7.1.** That report worried that T-P0-105's 208 blits
were drawing something ungated. **They examined zero cel pixels.** `CP_BLITS` counts entries to
`cp_composite`; each one aborted at row 0. ★★★ **208 is also not a shortfall from 240** — the room
jump lands at cycle 8, so 52 cycles × 4 sprites = 208 is the full count. **The dispatch's "240
staged, 208 drawn, 32 aborting" reads a shortfall that is not there.**

### 4B — Is the VIEW intact? ★★★★ Yes, and §1.2's lead was not needed

**The bytes were never in question**: the decoder refused to READ them, at the first byte, on a
bound that is not derived from the data at all. `vc_src` = `$615A` is a live arena address inside
the VIEW; `vc_srcend` = 0 is below it. ★★★ **No comparison against the game file could have shown
anything, because the failure is upstream of reading any byte.**

★★★ **So the checksum's blind spot 1 is NOT implicated**, and §1.2 is recorded as a lead that did
not pay — which §7 asked to be said plainly. ★★ The checksum's own result agrees: `-CelCheck` ran
1,220 baselines and 630 verifications with **0 mismatches** [P6.50 §4E].

### 4C — ★★★★★ What do the blits draw? Nothing — and then the machine dies

**Before the fix:** `co_tested` = 0. The 208 blits drew nothing at all, so there was nothing to gate
and P6.50's §7.1 concern resolves as "no change to gate".

**After the fix:** ★★★★★ **the run stalls in cycle 10 — the first cycle that composites a real
cel.** §7.1 names why.

★★★★ **So AC-5's comparison against `comp`'s reference cannot be made yet**, and that is the honest
answer rather than a partial one: there is no output to compare. ★★★ **What it would take** is
§7.1's defect fixed first; then `comp_stage.py`'s reference is the natural comparator, because it
composites the same cels — but from a flat plane, so the comparison would also need p3b's windowed
plane read back through `plane_vis` rather than flat.

### 4D — The fix, and only it
Three instructions in `p3_composite_all`. ★★★★ **§4A named one defect in this task's scope; the
second is structural and is reported** [§6].

### 5 — Verdict-time evidence (v0.7 §11)
```
AC-1  vc_srcend $0000 vs CP_VIEW+CP_VIEWLEN -- the third value compared, and the first to differ
AC-2  the VIEW's bytes are not implicated: the refusal is upstream of reading one
AC-3  CAUSE: p3b never set vc_srcend; res_open publishes res_len and nothing used it
AC-4  NOT MET -- the decode now succeeds and the run stalls in cycle 10 (§7.1)
AC-5  no comparison exists yet: co_tested was 0 before, and there is no run after
AC-6  cel 9193/9193 | comp 124/124 | vm 9/9 | res 1264/1264 | pic 45/45   ★ all fresh
AC-7  pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22 -- all green
      mojibake clean; RED ($44) inside the rect: 0
AC-9  p3b 13,941 D2C30D53 -> 13,950 36B1A1C3 (+9); every other arm and probe identical
      region A's 3,072 recovered bytes remain UNCLAIMED
AC-10 hal_sync x3 OK   reg-discipline 17/1/4   gen_vm_tables --check OK
```
**25.2:** N/A. **25.3: ★★★★★ NOT OFFERED, deliberately — see §7.2.**

### 6 — Reactive deviations and route accounting
1. ★★★★★ **§4A took one grep, not an instrumented run.** `vc_srcend`'s three references settle it;
   the measurement was taken anyway, **because a reading of the source is not a measurement** and
   the published `$0000` is what makes this a finding rather than a theory.
2. ★★★★★ **I BROKE FOUR GATE ROWS AND FIXED IT.** I put the cel path's symbols on `p3b_show.ps1`'s
   shared `$WANT` line; `-DP3B_NO_CEL` strips `view_cel.s` and `composite.s`, and `vm_symbols.py`
   fails the run on a missing name — so `p3b_text`, `p3b_box`, `p3b_parse` and `p3b_row22` all
   failed at once. ★★★★ **This file already warns about that trap three times** (MAP_FONT,
   P3_TXDIAG, tx_wt_*). Scoped with `if (-not $Linked)`; suite green.
3. ★★★ **§1.2's lead did not pay** and is reported as such (§4B).
4. ★★ **The dispatch's "240 staged, 208 drawn, 32 aborting"** is a miscount; 208 is the full number
   of staged sprites once the room jump is accounted for (§4A).
5. **ROUTE ACCOUNTING.** §4A, §4B, §4C and §4D are answered. **§4E was not offered** (§7.2).
   ★★★★ **No structural change made to `composite.s`, `view_cel.s` or the mirroring.**

### 7 — Uncertainty flags

**7.1 ★★★★★ `composite.s` ADDRESSES A WINDOWED PLANE FLAT, AND THAT IS THE NEXT DEFECT.**

`co_rowset` [`composite.s:419`] computes `co_rowvis = CP_VIS + y*160` and writes through it. In
`p3b`, `CP_VIS equ FB_BASE` = `MAP_PHASE_WIN` = **`$C000`**, an **8,192-byte window**.

| row | flat address | lands in |
|---|---|---|
| 0 | `$C000` | the window ✔ |
| ★★★ **100** | `$FE80` | ★★★★ **the vector stubs `$FEF0-$FF00` are 112 bytes away** |
| ★★★ **167** | `$12860` → **`$2860`** | ★★★★★ **the code region `$2000-$5F00`** |

**Both were observed.** The run reports the IRQ vector at `$FEF7` holding `52 5D 5C 5F 5E` — pixel
data — and the stall's most-visited PCs are `$2746`, `$2762`, `$276B`, which resolve to
`vm_rl_inrange+10`, `vm_rl_args+5` and `vm_rl_haveargs+4`: **the interpreter spinning on its own
overwritten dispatch.**

★★★★★ **`memmap.inc` PREDICTED THIS EXACTLY AND EXEMPTED IT FOR THE WRONG REASON.** Its AC-2 block
says *"visual 26,880 B into an 8,192 B window: `$C000` + 26,879 = `$128FF`, wrapping to `$28FF`,
inside the code region — the renderer overwrites its own code"*, and asserts **on the flat case
only**, because *"a build that defines `PLANE_WINDOWED` reaches every byte through `plane_vis` /
`plane_pri`, which mask the offset."* ★★★★★ **`composite.s` does not go through `plane_vis`.** The
exemption's premise is false for one of the two subsystems it covers.

★★★ **Not repaired** [§6: a change there is its own task]. ★★ `p3b_probe.s`'s own draw-phase block
already documents that `composite.s` is flat-addressed; what was missing is that nothing asserts it
against the **windowed** configuration.

**7.2 ★★★★★ THE EYE GATE WAS NOT OFFERED, AND THAT IS A DECISION I MADE.** §4E asks Jay to look at
the first mirrored cel anyone has seen in this project. **The run stalls in cycle 10, before any cel
reaches the screen.** ★★★★ **Asking Jay to watch a crash and report on silhouettes would waste his
time and produce nothing**, and P6.50's lesson was that a badly-framed eye gate costs more than it
returns. **It is owed the moment §7.1 is fixed**, and it is the first thing that should follow.

**7.3 ★★★ The `p3b` gate row passes because it never enters a room with sprites.** It runs without
`P3B_ROOM`, stays in room 83, stages zero sprites. ★★★★ **So the suite is green and the sprite path
is broken, simultaneously, and the manifest now says so.**

**7.4 ★★ `co_tested` is a 32-bit counter read big-endian by the host** and, like `CP_BLITS`, nothing
initialises it. It read 0, which is the value that matters here, but it carries P6.50 §7.2's caveat.

### 8 — Follow-up candidates
1. ★★★★★ **`composite.s` against a windowed plane** (§7.1). The renderer already solved this —
   `plane_win.s` exists and `pic_core.s` uses it. **The compositor is the one that does not.**
2. ★★★★★ **Then the eye gate that is owed** (§7.2): Kingquest1, room 1, the ego — is there a figure,
   is left-versus-right the same silhouette flipped, does it animate.
3. ★★★★ **Then gate what the blits draw** — AC-5, which cannot be answered until (1).
4. ★★★ **An assertion that `composite.s`'s plane base is windowed-safe**, so the next probe to link
   it cannot inherit this silently · the title-screen scroll.
5. ★★ Region A's 3,072 bytes, still unclaimed · `-CelCheck`'s composite figure [P6.50 §7.3].

### 9 — User interaction during task
None. ★★★ **§7.2 records why the eye gate was withheld rather than offered.**

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-19-the-caller-supplies-the-bound-and-one-caller-did-not.md`
- `seeds/AGI/live/2026-09-19-an-exemption-whose-premise-was-false-for-one-subsystem.md`

### 11 — Commit
`1f34b80` (pushed to origin/wip before this report).
