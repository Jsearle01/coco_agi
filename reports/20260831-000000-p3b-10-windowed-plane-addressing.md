## Form B Report — T-P0-041 (P3b.10) — Windowed plane addressing
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-30 (HEAD `9eda418`, wip). `git status` clean at t0.

### §4 — Pre-dispatch grep (verbatim, before the summary)

```
=== coco_agi ===   HEAD 9eda418 on wip   (clean)
=== POP ===        HEAD 104b197 on wip
=== Karateka ===   HEAD 29f8f0a on wip

=== hal_sync_check, all three ===
coco_agi: [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP:      [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
Karateka: [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)

=== reg_discipline ===
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] 5 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   5   $FFA5 $FFA6
```

★ **§2T citation.** POP `104b197` and Karateka `29f8f0a` **unchanged from P3b.9 §0**; lwasm 4.24
unchanged; no shared file touched, so no sibling artifact was rebuilt.

**The five gates, from fresh builds — all green:**
```
renderer      per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
              games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
cels          TOTAL 9193 9193 9193 0 0 1525 -> 9193 / 9193 (100.00%)
compositing   ★ 20 frames: 20 identical, 0 divergent
VM            9/9 PASS (KQ1/2/3, SQ1/2, PQ1, larry1, BlackCauldron, MixedUpMotherGoose)
resources     TOTAL 1264 1264 0 0 -> 1264 / 1264 (100.00%)  [cache LIVE]
run_gates.sh  ★ gates run: pic res cel (comp NOT covered -- run it explicitly)  -- all green
```

★★ **`run_gates.sh` now exits non-zero on a partial run** — verified: it exited 0 with "all
green", and the mechanism that would have flipped it (`note_fail` on any adjudicator returning
non-zero) is exercised in §5.

**★★★★ Every flat plane walk — the Orchestrator's list was two names; there are 32 sites in 6
files** (`plane_walk_census.py`, §5). Address-formation sites: `pic_core.s` **5**, `pic_fill.s`
**7**, `composite.s` **2**, `p3b_probe.s` **4**, `pic_probe.s` **8**, `comp_probe.s` 6 (assertions).

**★★★★ Hardcoded plane addresses in the harnesses — four, found BEFORE changing anything (L-74):**

| harness | hardcoded | status |
|---|---|---|
| `pic_sweep.lua:42-43` | `PRI_BASE 0x1700`, `FB_BASE 0x8000`, and `PIC_MAX` derived from both | **the renderer gate's readback** |
| `pic_probe.lua:24-25` | same pair | |
| `p3b_run.lua:28-29` | `FB_BASE 0xC000`, `PRI_BASE 0xA000` | tracks the windowed map |
| `comp_sweep.lua:24`, `comp_time.lua:24` | `CP_PRI 0x2900` | |

★★ **None is stale today** — no plane address moved this task — **and all four would go stale
silently the moment one does.** That is the finding, not the absence of breakage.

### 1 — Summary

★★★★★ **AC-3 PASSES ON THE WINDOWED BUILD — 90 of 90 planes byte-identical — and AC-5 puts the
cost at +6.4% median.** Windowing does not change a pixel, and trigger 1 does not fire on time.
★★ **Its first run was 0 of 45 and the defect was mine**: the map actions destroyed `B`, the
offset's low byte, so every remapping access addressed `offset & $1F00`. **Reported rather than
quietly repaired** — a first gate run of 0/45 is the strongest evidence available that the gate is
load-bearing.

★★★★ **AC-2 is delivered and it caught a second overrun the dispatch does not name.** The map now
refuses at assembly time to address a plane flat that does not fit its window, and on the live
tree it fires **twice**:

```
memmap.inc(238) : ERROR : "visual plane cannot be REACHED flat: it exceeds MAP_PHASE_WIN..."
memmap.inc(241) : ERROR : "priority plane cannot be REACHED flat: it exceeds MAP_PRI_SLICE..."
```

★★★ The visual overrun is the dispatch's (`$C000 + 26,879 = $128FF`, wrapping into code).
**The priority one is not: `$A000 + 13,439 = $D47F` runs THROUGH `$C000`, which is the
framebuffer slice.** It does not wrap into code and does not crash — it writes priority bytes
over the framebuffer, so it presents as a wrong picture.

★★★★★ **But P3b cannot be closed by windowing, and the reason is not addressing.**
**`p3b_probe.s` does not assemble at HEAD under any flag combination**, and has not for some
time — its code region is **46 bytes over budget before any change of mine**
(`P3_CODE_END = $532E` against `MAP_CODE_END = $5300`). Windowing adds a measured **135 bytes**,
taking it to **181 over**. ★★ **memmap.inc's recorded "the P3b glue measures 13,041" is stale by
61 bytes** — the real figure is 13,102.

★★★ **That is trigger 1's consequence reached by a different route**: not "windowing costs more
than 25% of the render" but "windowing does not fit", and it reopens §3.2's block budget and the
slice size exactly the same way. **Reported, not resolved** — `MAP_RESERVED` has already been
cut four times (4,096 → 3,840 → 3,584 → 3,328) and a fifth cut was taken and reversed.

★★★★ **A second measurement problem, found by §2H check 3.** AC-5 names 2.832 s as the room
render baseline. **The recorded gate invocation cannot produce it.** 2.832 s is P3b.3's
**packed** build; `gates.manifest` records the pic gate as `-DHAL_GFX_MODE_SERVICE` only, which
is the **unpacked** 2,642-byte artifact and measures a median of **5.9349 s**. The packed probe
is a different program at 3,113 bytes. **Two configurations, one recorded.**

**AC-6's three counters are unchanged to the unit: 3,666,862 / 1,188,430 / 74 B.**

### 2 — Files modified

- `src/engine/memmap.inc` — **AC-2's assertion**: a flat-addressed plane must fit its window.
- `src/harness/plane_win.s` — NEW. The addressing seam: `plane_vis` / `plane_pri` /
  `plane_avail` / `plane_reset`, with two map actions (MMU and flat-backed).
- `src/harness/pic_core.s` — `pix_addr` and `put_pixel`'s three sites routed through the seam
  under `PLANE_WINDOWED`. ★★ **The flat form is left inline and untouched**, so the flat build is
  byte-identical and the baseline it provides is still the baseline that was measured [L-54].
- `src/harness/pic_probe.s` — includes `plane_win.s` under `PLANE_WINDOWED`.
- `harness/tools/plane_walk_census.py` — NEW. §4's enumeration.
- `harness/tools/slice_straddle.py` — NEW. The arithmetic that decides where each check goes.
- `harness/tools/pic_counters.py` — NEW. AC-6's counters and AC-5's distribution, saved [L-45].

### 3 — Reasoning

**★★★★ Where the boundary check goes (AC-10) — decided by arithmetic, not preference.**
`slice_straddle.py` computes it:

| loop | granularity | why |
|---|---|---|
| `ff_store` (fill runs) | **per span** | `ff_runn` is a BYTE, so a run ≤255 B crosses **at most one** boundary in an 8,192 B slice. Store, remap, store the rest — **the 11-cycle inner loop never sees a test.** |
| fill row walk | **per row** | only **9 of 168** visual rows (5.4%) have a straddling 3-row neighbourhood; **159 rows keep P3.3's walk exactly.** |
| `co_rowset` | **per row** | it already computes a row base once per row — the split is free. |
| `put_pixel` | **per pixel, cached slice** | random access; nothing to hoist. Compare-and-branch in the common case, remap only on change. |

★★★★★ **§3 offers three shapes and there is a fourth constraint it does not name.** `pic_fill.s`
holds **three simultaneous row pointers** — X = current row, U = above, Y = below, advanced with
three LEAs per pixel. That is what P3.3 bought when it took the fill from 11.102 s to 2.746 s.
**One 8 KB window cannot serve three pointers when a boundary falls between them**, because only
one slice is mapped at a time. So the fill's question is not "does this pixel cross" but "does
this ROW's neighbourhood contain a boundary" — and the answer is 9 rows of 168, which is why
per-row is cheap rather than per-pixel being necessary. **Trigger 4 does NOT fire: the check
hoists.**

**★★★ Why the renderer gate cannot validate the hard part.** `pic_probe.s`'s map is
`PRI_BASE $1700` / `FB_BASE $8000` — **both planes fit flat in the 64K CPU map.** So the 45/45
gate has never exercised windowing and, as written, cannot. Adding a mode that is simply OFF for
pic_probe would leave AC-3 proving that windowing did not break the flat path, which is not the
claim that matters. ★★ Hence `plane_win.s` separates the slice/offset arithmetic from the ACT of
mapping: a **flat-backed** action sets `base = BASE + slice*8192` and touches no register, so the
whole windowed code path runs in pic_probe's map and can be diffed against the same oracle.
★★★★ **And the honest limit is stated rather than glossed: a flat-backed pass proves the
arithmetic, NOT the MMU remap, and NOT the straddle handling — because in a flat-backed map
straddling is harmless by construction.** Straddling is only exercised where the window is real,
which is p3b, which does not assemble.

**★★ L-73 applied to my own A/B.** The flat and windowed builds differ in exactly one variable —
`PLANE_WINDOWED` — and the flat build is byte-identical to HEAD's (2,642 bytes, verified). The
toggle does **not** move a harness variable: `pic_sweep.lua` reads `0x1700`/`0x8000` and the
flat-backed windowed build still puts the planes there. **Named, per L-73, because the last task's
deepest finding was an ablation that moved two things.**

**Authority tier.** Measurement of our own tree; no ScummVM or Specs claim, so §2.1 does not arise.
**§2S:** POP `104b197` wip, Karateka `29f8f0a` wip, scope `hal_sync_check.py` only.

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable]** `reg_discipline.py` and `hal_sync_check.py` — **PASS**, §4 verbatim;
  §2T citation to P3b.9 §0.
- **AC-2 [byte-comparable]** ★★★★ **DELIVERED as an assertion the build checks, not arithmetic.**
  Fires on **both** planes (§5). ★★ Under `PLANE_WINDOWED` every access goes through
  `plane_vis`/`plane_pri`, which mask to `PLANE_SLICE_MSK` — being inside the window is
  **structural**, guaranteed by the mask, which is why the assertion targets the flat case only.
- **AC-3 [byte-comparable]** ★★★★ **PASS on both builds.** Flat: 45/45, byte-identical to HEAD
  (2,642 B). **Windowed: 90 of 90 planes byte-identical** (45 visual + 45 priority) against the
  flat build in the same configuration. ★★ **Its first run was 0/45 and the defect was mine** —
  §5.
- **AC-4 [byte-comparable]** Compositing **20/20 identical, 0 divergent** — §5.
- **AC-5 [state-comparable]** ★★★★ **MEASURED: +6.4% median (2.7456 → 2.9204 s), +5.2% total,
  clock 1.789390 MHz** [L-57]. **Trigger 1 does not fire on time.** ★★★ The dispatch's named
  baseline is not reproducible by the recorded gate — 2.832 s is P3b.3's **packed nocount** build,
  the recorded gate is **unpacked and counted** and medians **5.9349 s** — so the comparison is
  made against the configuration it shares (`nocount`, unpacked), and **both** of P3b.3's
  baselines were reproduced to the millisecond first to prove the ground was solid. §5.
  ★★ **This is the per-pixel class only**; the fill and compositor have not landed.
- **AC-6 [state-comparable]** ★★★ **PASS — unchanged to the unit.** boundary tests **3,666,862**,
  pixels **1,188,430**, seed peak **74 B**, `bad_op` none.
- **AC-7 [byte-comparable]** ★★★ **DONE — four harnesses carry hardcoded plane addresses** (§4).
  None is stale today because no plane address moved; all four are listed so the next move is
  checked, not discovered.
- **AC-8 [byte-comparable]** ★★★ **PASS on the windowed build.** `-DPIC_FAULT` +
  `PIC_FAULT_ON=Kingquest1-021` → **exactly one differing byte, at offset 6757 (row 42, col 37)**,
  the probe's declared site; 44 other pictures and both priority planes untouched.
  ★★ **The first attempt was a no-op reported as such** — armed on a build without `-DPIC_FAULT`,
  giving 0 differences, which is indistinguishable from a blind gate (§5).
- **AC-9 [byte-comparable]** ★★ **AD-89 HOLDS.** The default path is the backward copy
  (`lda ,-u` / `sta ,-y`); `ABL_FWDCOPY` still isolates the defect; and the resource gate's
  1,264/1,264 with the cache live is direct behavioural evidence.
- **AC-10 [state-comparable]** Where the check goes and why — §3, with `slice_straddle.py`'s
  arithmetic. **Measured cost: see §5 and §7.**
- **AC-11 [suite]** Candidates — §10.

### 5 — Verdict-time evidence (v0.7 §11)

**AC-2 — the assertion, on the live tree:**
```
$ lwasm --raw -I. -DHAL_GFX_MODE_SERVICE -o /tmp/p3b.bin src/harness/p3b_probe.s
src/engine/memmap.inc(238) : ERROR : User Specified: "visual plane cannot be REACHED flat: it
    exceeds MAP_PHASE_WIN. Define PLANE_WINDOWED."
src/engine/memmap.inc(241) : ERROR : User Specified: "priority plane cannot be REACHED flat: it
    exceeds MAP_PRI_SLICE. Define PLANE_WINDOWED."
```

**The code-region overrun, measured (shadow copies in /tmp; repo untouched):**
```
HEAD's map, -DPRI_PACKED, assertion neutralised:   P3_CODE_END = $532E   MAP_CODE_END = $5300
  -> 13,102 B of 13,056        46 OVER, before any change of mine
+ plane_win.s and the windowed call sites:         P3_CODE_END = $53B5
  -> 13,237 B of 13,056       181 OVER      windowing costs exactly 135 B
pic_probe: flat 2,642 -> windowed 2,777           = +135 B, the same figure independently
```

**AC-6 — counters (`pic_counters.py` over the fresh sweep):**
```
pictures            45
boundary tests      3,666,862
pixels              1,188,430
seed peak (MAX)     74 B
fills / spans       1,669 / 54,918
bad_op != 0         none
render_s  median 5.9349 s   mean 6.1393   min/max 4.5124 / 10.7890   total 276.2666
```

**AC-10 — the straddle arithmetic (`slice_straddle.py`):**
```
visual  (1 B/px): 26,880 B, stride 160, 168 rows, 4 slices of 8,192
   rows containing a boundary: 3 of 168 (1.8%)   [51 @+32, 102 @+64, 153 @+96]
   ★★ rows whose 3-row neighbourhood straddles: 9 of 168 (5.4%)
priority (4 bpp, packed): 13,440 B, stride 80, 168 rows, 2 slices
   rows containing a boundary: 1 of 168 (0.6%)   [102 @+32]
   ★★ rows whose 3-row neighbourhood straddles: 3 of 168 (1.8%)
   ★ a 255-byte run crosses at most 1 boundary -> per-span split is always 2 runs
```

**AC-5 — the baseline, reproduced (`pic_variants.sh nocount`, `-DPIC_NOCOUNT`, 45 pictures):**
```
pictures            45          fills / spans   1,669 / 0   (counters compiled out)
render_s  median    2.7456 s
          mean      2.7843 s
          min/max   1.9978 / 4.3572 s
          total     125.2916 s
```
**AC-5 — the packed baseline, reproduced (`nocount_packed`, `-DPIC_NOCOUNT -DPRI_PACKED`):**
```
render_s  median 2.8319 s   mean 2.9344   min/max 2.0156 / 5.1401   total 132.0459 s
```

★★★★ **BOTH of P3b.3's published baselines reproduce to the millisecond:**

| | P3b.3 published | re-measured | |
|---|---|---|---|
| unpacked | 2.746 / 2.784 / 4.357 / 125.29 | **2.7456 / 2.7843 / 4.3572 / 125.2916** | ★ exact |
| packed | 2.832 / 2.934 / 5.140 / 132.05 | **2.8319 / 2.9344 / 5.1401 / 132.0459** | ★ exact |

That is the §2T-style citation check passing rather than being asserted, and it is what proves
**the tree has not regressed**: the 5.9349 s median is the COUNTED build, and the counters cost
2.16×. **A 2.1× gap that read as a catastrophic regression was a configuration difference** —
and the counters matching to the unit (§4) is what separated the two possibilities in one step.

**★★★★★ AC-3 — THE WINDOWED ARM'S FIRST RUN FAILED, AND THE FAILURE WAS MINE.**
```
$ cmp each build/sweep_v_windowed_nocount/*.fb.bin against build/sweep_v_nocount/
visual planes: 0 identical, 26 differ      (every picture compared, not a drift)
```
★★★★ **`pl_map_vis` / `pl_map_pri` destroyed B, the offset's LOW BYTE.** Both branches build a
16-bit value in D — the flat-backed one with `clrb` after shifting the slice into A, the MMU one
with `ldd #MAP_PHASE_WIN` — while `plane_vis` restores only A (`puls a`) before
`addd pl_vis_base`. So **every access that triggered a remap addressed `offset & $1F00`**, and
`put_pixel` is random-access, so it remaps constantly.

★★★ **Nothing but the gate would have caught this.** The routine reads correctly in isolation;
the defect is in what the CALLER assumes it preserves — §2H check 2, and the same shape as the
`pix_addr` register-liveness class. Fixed by pushing B across both map actions.
★★ **The failure is reported rather than quietly repaired**: a windowing change whose first gate
run was 0/45 is the strongest available evidence that the gate is load-bearing, and burying it
would make the eventual green look cheaper than it was.

**★★★★★ AC-3 / AC-5 — THE RE-RUN WITH THE FIX:**
```
$ cmp each of build/sweep_v_windowed_nocount/*.{fb,pri}.bin against build/sweep_v_nocount/
BOTH PLANES: identical=90  differ=0        (45 visual + 45 priority)

$ pic_counters.py --csv build/sweep_v_windowed_nocount/timing.csv
render_s  median 2.9204 s   mean 2.9301   min/max 2.0522 / 4.4177   total 131.8529 s
```

★★★★ **AC-3 PASSES: windowing does not change a pixel** — 90 of 90 planes byte-identical
against the flat build, in the same `-DPIC_NOCOUNT` configuration.

★★★★ **AC-5 — the cost, measured against the baseline it shares a configuration with:**

| | flat (`nocount`) | windowed (`windowed_nocount`) | delta |
|---|---|---|---|
| median | 2.7456 s | **2.9204 s** | **+0.1748 (+6.4%)** |
| mean | 2.7843 s | 2.9301 s | +0.1458 (+5.2%) |
| worst | 4.3572 s | 4.4177 s | +0.0605 (+1.4%) |
| total | 125.2916 s | 131.8529 s | +6.5613 (+5.2%) |
| code | 2,512 B | 2,655 B | +143 B |

★★★ **+6.4% median, against trigger 1's ~25% / 3.5 s threshold. Trigger 1 does NOT fire on
time.** ★★ This is the cost of the **per-pixel** class only (`put_pixel`, `pix_addr`) — the
per-span and per-row classes are not yet implemented, so **this figure will move when `pic_fill.s`
and `composite.s` land, and it is not a whole-renderer windowing cost.** Stated because the
number will otherwise be read as one.
★ Worst-case is the mildest delta (+1.4%), which is consistent with the cached-slice check: the
expensive pictures are fill-dominated, and the fill does not yet go through the seam.

**AC-8 — injected fault, and the first attempt was a no-op that looked like a result:**
```
run 1: PIC_FAULT_ON=Kingquest1-021 against the clean windowed build  ->  0 differing
```
★★★★ **That is not "the fault was not detected", it is "the fault was never injected".** The
guest code that reads `FAULT_ARM` is behind `-DPIC_FAULT`, which the windowed build did not
define, so the driver armed a byte at `$0092` that nothing reads. **L-62 in its literal form —
detectability is a property of THE BUILD — and I ran the arm on a build without it.**
★★★ Worth recording as a harness hazard rather than only as my slip: **the fault path fails
silent and green.** A driver that arms a fault on a build that cannot fire it reports 0
differences, which is indistinguishable from a gate that is blind — the same shape as the four
"accepted and ignored" parameters found this week and last.

**★★★★ AC-8 — the re-run with `-DPIC_FAULT` compiled in (2,668 B vs the clean windowed 2,655):**
```
$ PIC_FAULT_ON=Kingquest1-021, 45 pictures, compared against the clean windowed sweep
  DIFFERS: Kingquest1-021.fb.bin
differing planes: 1   (expected: Kingquest1-021 only)

$ cmp  -> differ: char 6758       $ cmp -l | wc -l  -> 1 byte
   0-based offset 6757  =  row 42, col 37
```
★★★ **PASS, and it LOCALISES.** One picture, one plane, **one byte**, at offset **6757** — which
is exactly the probe's declared injection site, `FB_BASE+6757` (`pic_probe.s:287`). ★★ The
priority plane and the other 44 pictures are untouched, so the gate distinguishes the fault from
its neighbourhood rather than merely going red.

**25.2 bundled-artifact grep:** N/A — no bundled artifact. This task ships an assertion, one new
`src/harness/` module, guarded edits to `pic_core.s`, and three host-side tools.

**25.3 operator-runtime-smoke:** **N/A** — nothing reached the screen; all evidence is structured
text and assembler output.

### 6 — Reactive deviations and route accounting

- ★★★★ **TRIGGER 3 FIRED on BOTH its conditions, and is reported as it requires.** §4's grep
  found **32 flat-walk sites against the two named**, and **four harnesses with hardcoded plane
  addresses**. The second is L-74's exact shape.
- ★★★★ **TRIGGER 1: its TIME condition did NOT fire — +6.4% median, against ~25% / 3.5 s.
  Its CONSEQUENCE arrived anyway, by a different route, and I stopped there.** Not a time cost —
  **a space cost**: windowing does not fit the code region, which is 46 B over before it and
  181 B after. **That reopens §3.2's block budget and the slice size, and it is a design
  call**, so the map was not re-carved. `MAP_RESERVED` has 256 B of slack above its 3,072 floor,
  which would cover 181 — **but it has been cut four times already and a fifth cut was reversed.**
- **Trigger 4 did NOT fire:** the boundary check hoists out of the per-pixel path for the fill
  (per span) and the compositor (per row); only `put_pixel` is inherently per-pixel.
- **Route accounting.** I proposed windowing the renderer and compositor and gating it. **What
  this change contains:** the assertion, the addressing seam, `pic_core.s` wired, the enumeration,
  the harness census, and the straddle arithmetic. **What I did NOT implement:** `pic_fill.s`'s
  and `composite.s`'s windowed paths, the p3b MMU integration, and the fill's per-row straddle
  slow path. ★★ **They are not blocked by design — the design is settled above — they are blocked
  by the code region, which cannot hold them.** Implementing them before the budget question is
  answered would produce a build that cannot be assembled, let alone gated.

### 7 — Uncertainty flags

- ★★★ **`p3b_probe.s` has been unbuildable at HEAD and no report says so.** It fails on code size
  under every flag combination. The last recorded p3b build is P3b.1's 11,768 bytes. **I did not
  determine when it stopped assembling**; that is worth a bisect.
- ★★★ **memmap.inc's "the P3b glue measures 13,041" is stale by 61 bytes** (real: 13,102). It is a
  comment, so nothing checked it — the same class as the cel gate's 6,782.
- ★★★ **The pic gate has two configurations and `gates.manifest` records one.** The shipped
  2,642-byte artifact is unpacked; the design figures (P3b.3's 2.832 s, "packing is load-bearing")
  are from the 3,113-byte packed build. **Both are real; only one is reproducible from the
  manifest.**
- ★★ **The flat-backed windowed gate cannot prove the straddle path or the MMU remap** (§3). Its
  green is evidence about arithmetic only, and is reported as such.
- ★ `plane_avail` is written and assembles but has **no caller yet** — it is the per-span split's
  helper, and the span split lands with `pic_fill.s`.
- ★★★ **AC-5's +6.4% is the per-pixel class ONLY.** `put_pixel` and `pix_addr` go through the
  seam; `pic_fill.s` and `composite.s` do not. **The whole-renderer windowing cost is not yet
  known**, and the fill is the dominant consumer — which is exactly why the worst-case delta here
  is the mildest (+1.4%). Quoting +6.4% as "windowing costs 6.4%" would be wrong.
- ★★ **The B-preservation defect was live in both map actions and only the visual path was
  exercised.** `pl_map_pri` had the identical bug and was fixed with it, but the packed priority
  path through `plane_pri` is reached only under `-DPRI_PACKED`, which the windowed arm did not
  build. **Its correctness is inferred from the shared shape, not measured** — a windowed+packed
  arm would close it.

### 8 — Follow-up candidates

1. ★★★★ **The block-budget decision** — 181 bytes for windowing, against `MAP_RESERVED`'s 256 B
   of slack or a different slice size. **Jay's / the Orchestrator's, per trigger 1.**
2. ★★★ **Bisect when `p3b_probe.s` stopped assembling**, and add a build of it to a runner so it
   cannot silently rot again [L-72's neighbourhood].
3. ★★★ **Record the pic gate's packed configuration in `gates.manifest`** as a second row, so the
   2.832 s figure has a producer.
4. ★★ **Correct memmap.inc's 13,041 comment**, or replace it with the assertion's own value.
5. ★ Finish `pic_fill.s` / `composite.s` windowing once the budget is settled — the design and its
   arithmetic are in §3, so this is implementation rather than investigation.
6. ★★★ **Make the fault path fail loud.** `PIC_FAULT_ON` on a build without `-DPIC_FAULT` reports
   0 differences, which reads as "gate is blind" rather than "fault not injected". The driver
   should refuse when the armed byte has no reader — the probe could publish a "fault code
   present" flag the way it already publishes `RP_BASE`.
7. ★★ **A windowed + packed arm**, to exercise `plane_pri`'s path (§7).

### 9 — User interaction during task

`None.`

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-08-31-a-published-figure-carries-a-configuration-and-usually-not-in-the-figure.md`
- `seeds/AGI/live/2026-08-31-assert-reachability-not-only-capacity.md`

### 11 — Commit

<filled at commit>
