## Form B Report — P3b.17 — the corpus framing refuted, and the shadow buffer

**Class:** build. wip. Calibration-light — receipt stamp only.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-06 (dispatch carried no receipt timestamp; report written 2026-09-06T12:52:51-04:00).

---

## §4 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `wip` @ **`9bd5113da0132f6e49136fc3d1a564437929f515`**, `origin/wip` identical, **status clean at start** |
| POP + Karateka | §2T cite P3b.16 §0 |
| `hal_sync_check.py` | **OK in all three repos** |
| the gates, fresh builds | **8/8 artifacts identical** at start and end; §2T cite P3b.16 §0 for the five gate results |
| **flag sets — enumerated and diffed** | **8/8 identical**, start and end |
| **the clock — measured** | **1.789772 MHz** (`VP_MARK`, 160,009 cycles) |
| **the 45-picture corpus** | **T-P0-012**, weighted by fill count, KQ1 #80 forced in unconditionally, spread across three games [`picset.py:2-12`] — see §3.A |
| map headroom | untouched: no `MAP_RESERVED` byte was taken, and the shadow buffer costs **zero** CPU address space (§3.E) |

---

### 1 — Summary

★★★★★ **A's framing is refuted by measurement, and the refutation is the finding.** The dispatch
attributes the divergence to the gate corpus. **It is not the corpus:** pictures 22 and 53 are
*inside* the gated 45, pass byte-identical in `pic_probe`, and diverge **14.8%** and **23.9%** in p3b
**with zero sprites**. Picture 80 — the only clean sample — turns out to be the **minimum-fill picture
in the entire set** (2 fills against a median of 19), forced in unconditionally since T-P0-011.

★★★★ **The real cause is a path the project had already written down and nobody had connected:**
`pic_probe` forces `PLANE_PRI_FLAT` whenever windowing is on, so **the windowed PRIORITY walk is
exercised only by p3b and by no gate at all** — `pic_probe.s:86-89` says exactly that.

★★★ **A's corpus finding survives independently and is worth keeping:** the renderer gate can reach
**83 of 287 pictures (29%)**, bounded by a 1,263-byte poke window, carrying **17.5% of the corpus's
fills**.

★★★★★ **B is delivered and gated.** The picture renders into a shadow buffer and is blitted on
completion; **Jay confirms the castle room now appears rather than draws.** Picture 80 through the
blit is **0 of 26,880 on both planes**, gates 8/8, at **+0.2169 s per room** and four previously-unused
blocks.

---

### 2 — Files modified

- `src/harness/p3b_probe.s` — the shadow buffer: `P3_BLK_SHADOW`/`P3_BLK_VISIBLE`, `p3_present`, the
  render bracketed to the shadow, and a one-time clear of the visible plane at init.
- `harness/tools/p3b_show.lua` — the display follows `p3_blk_vis` rather than `ph_blk_fb`.

★ **No shared HAL file, no gate artifact's source, no `MAP_RESERVED` byte.** `reg_discipline.py`
still reports **8 accesses in 1 file over 2 registers** — `mmu_phase.s` remains the single sanctioned
owner, because `p3_present` maps through its entry points rather than writing `$FFA5`/`$FFA6` itself.

---

### 3 — Reasoning

#### 3.A A is refuted: it is not the corpus [AC-2, L-83]

The dispatch's premise is that the renderer is wrong on pictures outside the 45. **Seven p3b renders,
compared against the oracle's own references:**

| room | picture | in the gated 45 | sprites | differing |
|---|---|---|---|---|
| 80 | pic080 | **yes** | 1 | **0.0%** |
| **22** | **pic022** | **yes** | **0** | **14.8%** |
| **53** | **pic053** | **yes** | **0** | **23.9%** |
| 5 | pic005 | no | 1 | 20.7% |
| 17 | pic017 | no | 1 | 20.6% |
| 1 | pic001 | no | 4 | 28.8% |
| 3 | pic003 | no | 2 | 71.5% |

★★★★ **22 and 53 are inside the corpus, pass 45/45 in `pic_probe`, and diverge in p3b with zero
sprites.** That eliminates the corpus, the compositor and the sprites in one table.

★★★ **And picture 80 is not a representative pass.** It carries **2 fills** against the gated set's
median of **19** and maximum of **26** — the minimum in the set. It is the one picture with almost
nothing to get wrong, and it is forced in unconditionally to reproduce T-P0-011.

#### 3.B What A's investigation eliminated, each by measurement

| hypothesis | test | result |
|---|---|---|
| the corpus | 22 and 53, inside the 45 | **eliminated** — they diverge in p3b |
| sprites / the compositor | 22 and 53 ran with **0 sprites** | **eliminated** — 576 and 435 unequal-nibble bytes anyway |
| unimplemented opcodes | `picset.py` over 83 and over 287 pictures | **eliminated** — *"no picture used an unimplemented opcode"*, *"implemented but NOT reached: none"*, both sets |
| pattern fills | same | **eliminated** — not reached by any of the 287 |
| `-DPRI_PACKED` | gate on the packed build | **eliminated** — 45/45 |
| genuine windowing | gate on `-DPLANE_WINDOWED -DPLANE_WIN_MMU -DPRI_PACKED` | **eliminated** — 45/45, 3,583 B |

#### 3.C ★★★★★ Three of my own tests were inert, and the source says why

P3b.15 and P3b.16 both report "the windowed renderer passes 45/45", built with `-DPLANE_WINDOWED`.
**Those runs did not test windowing.** `pic_probe.s:69-74`:

> *"The flat build addresses the visual plane at $8000 … The plane is contiguous, so a 'windowed'
> build in this map reduced to `addd fc_pbase` and **the 45-picture gate could not exercise one line
> of the windowing** — the code that ships in p3b was ungated."*

The call sites are guarded on **`PLANE_WIN_MMU`**, not `PLANE_WINDOWED` [`pic_fill.s:431` says so in
as many words]. ★★ **`-DPLANE_WINDOWED` includes `plane_win.s` and routes nothing through it** — the
binary grows, which is what made the runs look real.

★★ Re-run correctly (`-DPLANE_WINDOWED -DPLANE_WIN_MMU -DPRI_PACKED`, and `PLANE_WIN_MMU` alone is an
assembly error — `memmap.inc` requires both): **45/45, 3,583 bytes.** The conclusion survives; the
method that produced it did not. ★ Same class as P4.7's inert fault injection: **a flag that compiles
but does not reach the code under test.**

#### 3.D ★★★★★ The localisation, and the project had already recorded it

`pic_probe.s:86-89`, in the comment that introduces the windowed gate:

> *"★ PLANE_PRI_FLAT: only the VISUAL plane lives in blocks here. The priority plane stays at $1700 in
> the low map, so a FC_PRIORITY fill takes the flat path — 70.3% of fills are FC_VISUAL and it is
> those that this gates. **Stated rather than glossed: the priority walk's windowing is still
> exercised only by p3b.**"*

★★★★ **`PLANE_PRI_FLAT equ 1` is forced whenever `PLANE_WIN_MMU` is defined** [`pic_probe.s:90-91`],
so **`pic_probe` cannot window the priority plane in any configuration.** p3b windows both.

★★★ **That is the only path left**, and it fits every observation: fills that never ran (FC_PRIORITY
takes the windowed path), nibble-shaped damage in the *visual* plane (the fill's cross-slot borrow
takes slot 5, which in p3b holds the priority plane — `mmu_phase.s:85-90`), zero sprites required, and
picture 80 clean at 2 fills.

★★ **NOT FIXED, and not attempted.** It is shared renderer code, it is trigger 2's condition, and
naming it is what this task can honestly deliver. ★ **It is also not provable from here**: the
mechanism above is read from source, not demonstrated — see §7.

#### 3.E B: the shadow buffer [AC-4]

★★★ **Narrower than double-buffering, deliberately.** The picture render happens once per room, so
only the render gets a shadow. **The compositing loop is untouched** — sprites still write the visible
plane directly with §3.6's save-under, which is §11's out-of-scope line and trigger 5's condition.

**Where it lives, and it costs no CPU address space at all.** The blocks were the question, not the
map: priority 0-1, shadow framebuffer 2-5, volumes staged at 8-13 and 14-38 (measured from
`p3b_run.lua`'s own staging log), CPU window $38-$3F. **Blocks 40-43 were free.** ★ No volume moved,
no `MAP_RESERVED` byte taken, and trigger 3 never fired.

★★ **§2K is not newly broken:** p3b already stages 31 blocks of volumes and has never been a 128 KB
harness. Stated rather than assumed.

**The mechanism.** `ph_blk_fb` selects which four blocks every `plane_win` and `phase_draw_fb` call
resolves against, so pointing it at the shadow redirects the **whole** render — clear, lines and fills
— with no change to `pic_core`. `p3_present` then walks four slices, mapping the destination into slot
5 and the source into slot 6 through `mmu_phase.s`'s existing entry points, and copies 8,192 bytes per
slice. ★★ **The borrow of slot 5 is safe only because of when it runs**: the picture is finished and
the sprites have not started, so nothing reads priority across the call — the same argument
`mmu_phase.s` makes for the fill's straddle borrow, made explicitly because this borrow is longer.

★ **The visible plane is cleared once at init**, because blocks 40-43 had never been written and the
first room's ~7 s render would otherwise display uninitialised RAM — a direct consequence of the
shadow, since the visible plane is no longer the one being drawn into.

#### 3.F A defect of mine: data in the instruction stream

The first shadow build hung before the guest ran. **`p3_blk_vis fcb 40` was placed between
`clr ph_blk_pri` and the following `lda`** — in the executable path — so the 6809 executed the byte 40
as `$28` (BVC) and derailed at init. ★★ **The symptom was the harness never setting the video mode**,
because its notifier waits on a cycle counter the guest never wrote; Jay named it as *"hung or never
changed video modes"*. Both bytes now sit after an `rts` and before the entry label.

★★ **Third instance in this project of data sitting where code runs** — `vm_icguard` at the top of a
cycle profile, `PAL_READBACK` aliasing the pic counters, and this.

#### 3.G Authority tiers

Every figure is fresh tool output on this machine (25.1); oracle planes are the reference per §2O.1.
§2H's three checks: the second mechanism was looked for and found — the divergence has a *fill* half
and a *nibble-damage* half, and they point at the same borrow; the calling routine is named at each
step (`ff_win_map` → `phase_draw_pri_slot6`; `ff_win_map_lo` → `phase_draw_fb_slot5`); the prior-report
grep is §3.C's retraction of P3b.15 and P3b.16's windowed claims.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] — PASS.** `hal_sync_check.py` **OK in all three**;
  `reg_discipline.py` **8 accesses, 1 file, 2 registers** — unchanged by `p3_present`, which maps
  through `mmu_phase.s` rather than writing the registers itself. Gates **8/8 identical** at start and
  end. §2T citation: P3b.16 §0.
- **AC-2 [class: state-comparable] — ANSWERED, AND THE ANSWER REFUTES THE QUESTION.** Seven pictures
  sampled (§3.A); **the divergence does not correlate with corpus membership.** ★★★ **Sampling
  method, per L-22:** the seven were chosen as three inside the gated 45 (80, 22, 53) and four
  outside (1, 3, 5, 17), rooms driven by the existing room jump. **Not random and not large** —
  chosen to test the dispatch's hypothesis, which it falsifies. ★ The rate among the six non-outlier
  samples is **14.8%-71.5%**, all six diverging.
- **AC-3 [class: state-comparable] — the 45 were missing nothing of what the AC named.** Opcodes:
  clean negative on **both** the 83- and 287-picture sets — *"no picture used an unimplemented
  opcode"*, *"implemented but NOT reached: none"*. Pattern fills: not reached by any of the 287.
  Control lines: not the differentiator, since in-corpus pictures diverge too. ★★★★ **What they were
  actually missing is a code PATH, not content:** the windowed priority walk (§3.D).
- **AC-4 [class: byte-comparable] — PASS.** The picture renders into blocks 2-5 unseen and is blitted
  to blocks 40-43 on completion. **Jay: *"the castle room does appear and not draw as i expect."***
- **AC-5 [class: byte-comparable] — PASS.** Picture 80 **through the blit**: **0 of 26,880 visual,
  0 of 26,880 priority**, and 0 bytes with unequal nibbles. `gate_audit.py --verify` **8/8 identical**.
  The composite gate's inputs are untouched. Trigger 4 does not fire.
- **AC-6 [class: state-comparable] — measured, clock stated.** Clock **1.789772 MHz** (`VP_MARK`).
  **+0.2169 s per room** (cycle 1: 7.0758 s → 7.2927 s) ≈ **388,000 CPU cycles** for 26,880 bytes,
  **+10 remaps** (12 → 22), **four blocks** (40-43, previously unused), **zero CPU address space**,
  **zero `MAP_RESERVED`**. ★ Steady-state cycles unchanged: 0.3171 s, remaps 2. Against a ~2.8 s
  render the present is ~7.7%; against cycle 1's total, 3.0%.
- **AC-7 [class: byte-comparable] — NOT DONE.** No fault was injected on this build. The 45/45 runs in
  §3.B are coverage, **not fault-detectability** [L-62, L-81]. Stated rather than implied by green.
- **AC-8 [class: eye-gated] — PASSED BY JAY, and this is the first eye gate this phase has passed.**
  *"the castle room does appear and not draw as i expect."* Launch path **`poke`**. ★★ **The castle
  room's CONTENT is still wrong** (28.8%, §3.A) — B fixed *when* it appears, not *what* it contains,
  and the two must not be conflated.
- **AC-9 [class: state-comparable] — A and B attributed separately.** **A changed no code**: it is
  measurement and a refutation, and it delivered no fix. **B is the entire diff.** ★ B's win does not
  cover A's open defect (§3.D), and A's findings do not depend on B.
- **AC-10 [class: state-comparable] — four things this dispatch did not anticipate.**
  (1) ★★★★★ **The framing is wrong** — in-corpus pictures diverge (§3.A).
  (2) ★★★★★ **Three of my own prior "45/45 windowed" results were inert** (§3.C), and the flag that
  matters is `PLANE_WIN_MMU`.
  (3) ★★★★ **Picture 80 is the 2-fill minimum of the gated set**, so the one clean sample in eleven
  tasks is the least demanding picture available.
  (4) ★★★ **The shadow buffer cost no address space and no `MAP_RESERVED`** — the constraint was
  blocks, and four were free. §3's budget question had a cheaper answer than the framing assumed.
- **AC-11 [class: suite]** — see §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

*§4 — checks at both ends:*
```
coco_agi       : [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port      : [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3 : [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)
gate_audit --verify : 8/8 identical (start and end)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
```

*§3.A — the corpus provenance, and the seven samples:*
```
picset.py:2-12  "T-P0-012 AC-3/AC-4: choose the gated PICTURE set"
                "SELECTION IS BIASED TOWARD FILLS ON PURPOSE (L-38)"
                "includes KQ1 #80 unconditionally, so T-P0-011's result is REPRODUCED"

room  80  pic080  IN corpus  1 spr   differing 0     of 26880 ( 0.0%)
room  22  pic022  IN corpus  0 spr   differing 3983  of 26880 (14.8%)  unequal nibbles 576
room  53  pic053  IN corpus  0 spr   differing 6427  of 26880 (23.9%)  unequal nibbles 435
room   5  pic005  out        1 spr   differing 5558  of 26880 (20.7%)  unequal nibbles 778
room  17  pic017  out        1 spr   differing 5530  of 26880 (20.6%)  unequal nibbles 452
room   1  pic001  out        4 spr   differing 7745  of 26880 (28.8%)  unequal nibbles 1163
room   3  pic003  out        2 spr   differing 19217 of 26880 (71.5%)  unequal nibbles 401

fill counts: picture 80 = 2   picture 22 = 23   picture 53 = 26
gated KQ1 set: n=16  min=2  median=19  max=26      <- 80 IS the minimum
```

*§3.A / AC-3 — the corpus's reach, measured by raising the window limit:*
```
--max-bytes 0x4EF (1,263 -- the probe's PIC_DATA window)
  candidates with oracle dumps, implemented opcodes, and a resource that fits: 83
  fill counts across the set: min 0, median 9, max 26, total 816
  ★ implemented but NOT reached by this set (AC-4): none

--max-bytes 16384 (the arena p3b actually uses)
  candidates with oracle dumps, implemented opcodes, and a resource that fits: 287
  fill counts across the set: min 0, median 16, max 39, total 4669
  ★ no picture used an unimplemented opcode
  ★ implemented but NOT reached by this set (AC-4): none

★ 83 of 287 pictures = 29%;  816 of 4,669 fills = 17.5%
★ the exclusion is `if len(data) > args.max_bytes: continue` -- size, not content
```

*§3.B / §3.C — the gate on each configuration:*
```
-DHAL_GFX_MODE_SERVICE                                        2642 B   45 PASS 0 FAIL
-DHAL_GFX_MODE_SERVICE -DPLANE_WINDOWED                       2785 B   45 PASS 0 FAIL   ← INERT
-DHAL_GFX_MODE_SERVICE -DPRI_PACKED                           3113 B   45 PASS 0 FAIL
-DHAL_GFX_MODE_SERVICE -DPLANE_WINDOWED -DPRI_PACKED          3256 B   45 PASS 0 FAIL   ← INERT
-DHAL_GFX_MODE_SERVICE -DPLANE_WIN_MMU -DPRI_PACKED           ERROR: "visual plane cannot be
    REACHED flat: it exceeds MAP_PHASE_WIN. Define PLANE_WINDOWED."   [memmap.inc:245,248]
-DHAL_GFX_MODE_SERVICE -DPLANE_WINDOWED -DPLANE_WIN_MMU -DPRI_PACKED  3583 B  45 PASS 0 FAIL
```

*§3.D — the path no gate can reach, in the tree's own words:*
```
pic_probe.s:86-89  "PLANE_PRI_FLAT: only the VISUAL plane lives in blocks here ...
                    Stated rather than glossed: the priority walk's windowing is still
                    exercised only by p3b."
pic_probe.s:90-91  ifdef PLANE_WIN_MMU
                   PLANE_PRI_FLAT  equ 1
```

*AC-4 / AC-5 / AC-6 — the shadow buffer:*
```
p3b_probe_pk_fresh.bin  12856 B  (was 12723 -- p3_present and the init clear)
palette: 16 entries from gfx.s   visible-plane byte=$2141 (p3_blk_vis)
DISPLAY -> ph_blk_fb=40  physical=$50000  VOFFSET=$A000  (cycle 2)
cycle   1  7.2927 s  room  83  sprites  0  remaps 22  err 0     (was 7.0758 s, remaps 12)
cycle  40  0.3171 s  room  80  sprites  1  remaps  2  err 0     (unchanged)
final room 80, sprites 1, err 0, status=$00
dumping through the window: fb blocks $28.. pri blocks $00..     ($28 = 40, the visible plane)
clock MEASURED 1.789772 MHz (160009 cycles calibrated)

AC-5, picture 80 THROUGH the blit:
  bytes whose two nibbles DISAGREE (should be 0): 0
  differing bytes: 0 of 26880 (0.0%)      rows with any difference: 0 of 168
  PRIORITY differing: 0 of 26880
gate_audit --verify: 8/8 identical
```

*§3.F — the init derailment, and its repair:*
```
FIRST BUILD : p3_blk_vis fcb 40 placed between `clr ph_blk_pri` and the following `lda`
              -> the 6809 executes 40 as $28 (BVC); the probe never runs
              -> the harness never sets the video mode (its notifier waits on a counter
                 the guest never wrote)
AFTER       : 2012 7F22AA   clr ph_blk_pri     <- followed only by comments; pure code
              p3_blk_vis now at $2141, after an rts and before p3_present's label
```

**25.2 bundled-artifact grep:** N/A — nothing imported, no bundled asset committed. Oracle references
are the project's existing `oracle/dumps/base-Kingquest1/`, read only; the staged wide sets are in
gitignored `build/` and `%TEMP%`.

**25.3 operator-runtime-smoke:** ★★★★★ **PASSED — Jay, launch path `poke`.** *"the castle room does
appear and not draw as i expect."* ★★ **This gate covers WHEN the room appears, not WHAT it contains**
— the castle room's 28.8% content divergence is §3.D's open defect and is explicitly not covered here.

---

### 6 — Reactive deviations and route accounting

1. ★★★★★ **A was answered by refuting it rather than by executing it.** §2 asked for a divergence rate
   across a wider sample on the assumption that the corpus is the confound; the sample shows in-corpus
   pictures diverging too. **The wide-corpus sweep A envisages would have measured the wrong thing.**
   L-83, which §6 names as the pattern to follow.
2. ★★★★ **Three of my own prior results were retracted mid-task** (§3.C). P3b.15 and P3b.16 both claim
   a windowed 45/45 that did not test windowing.
3. ★★★★ **§3.D's defect was localised and NOT fixed.** Shared renderer code, trigger 2's condition.
4. **The shadow buffer took blocks 40-43 rather than negotiating the map's spare.** §3's budget
   question assumed CPU address space was the constraint; it was blocks, and four were free — so
   trigger 3 never fired and `MAP_RESERVED` was not touched.
5. **`p3_present` counts its own ten remaps**, as `p3_clear_planes` now does, rather than leaving
   AC-6's figure under-reporting.
6. **A one-time clear of the visible plane was added at init**, beyond the letter of AC-4, because the
   shadow makes blocks 40-43 visible before anything writes them.
7. **AC-7 was not attempted.**

**ROUTE ACCOUNTING.** No route proposed. **Delivered:** A's refutation with seven samples, A's corpus
finding (29% / 17.5%), the localisation to the windowed priority walk, and B complete and eye-gated.
**Not delivered:** A's fix (§3.D), AC-7 entirely. **Not attempted:** double-buffering the compositing
loop (§11), the surviving resource copy, M-48.

---

### 7 — Uncertainty flags

- ★★★★★ **§3.D's mechanism is READ, not demonstrated.** That the fill's cross-slot borrow corrupts the
  visual plane in p3b's map follows from `mmu_phase.s:85-90` and `ff_win_map`/`ff_win_map_lo`
  [`pic_fill.s:1035-1058`], and from the fact that every other candidate is eliminated. **No
  experiment isolates it.** ★★ It is the strongest remaining hypothesis, not a measured cause, and the
  next task should prove it before fixing it — this session has already had one near-miss where a
  fabricated number matched a real comment in the tree.
- ★★★★ **AC-2's sample is seven pictures, chosen to test a hypothesis, not drawn at random.** It
  falsifies the corpus framing, which needs only one in-corpus divergence. **It does not establish a
  divergence rate** and should not be quoted as one.
- ★★★ **Every p3b figure includes any sprite contribution.** Rooms 22 and 53 ran with zero sprites and
  still diverge, which is what carries the argument; the others do not isolate it.
- ★★ **The 287-picture figure is itself bounded** by the arena's 16,384 bytes. Pictures larger than
  that are in neither number.
- ★★ **B's borrow of slot 5 is argued, not asserted, but not proven either** — it rests on nothing
  reading priority between the render's end and the sprites' start. AC-5's 0/26,880 on both planes is
  consistent with that and does not prove it in general.
- ★ Carried, untouched: `reg_discipline.py` 8 vs a recorded 5 [AD-104]; `scummvm.pin`'s five patches
  against eight applied; `p3b_probe_pk`'s unrecorded build line and stale shipped artifact.

**Triggers:** **1 does not fire** — the divergence is not a corpus problem, so "the renderer is broadly
wrong" is not the finding; the phase-level finding is §3.D and it is reported. **2 FIRES** (§3.D names
a path no gate reaches) and is reported without a fix. **3 does not fire** — the shadow buffer fit in
free blocks. **4 does not fire** — 0/26,880 both planes. **5 does not fire** — the compositing loop is
untouched.

---

### 8 — Follow-up candidates

1. ★★★★★ **Prove and fix the windowed priority walk** (§3.D). It is the cause of every divergence in
   §3.A's table and it is ungated by construction. **Prove first** — §7's first flag.
2. ★★★★★ **Give `pic_probe` a windowed PRIORITY mode** so the path can be gated at all. Today
   `PLANE_PRI_FLAT` is forced whenever windowing is on, which is why eleven tasks of 45/45 never
   touched it.
3. ★★★★ **Correct the record on `PLANE_WINDOWED` vs `PLANE_WIN_MMU`** — `gates.manifest`'s `pic_win`
   row carries `-DPLANE_WINDOWED -DPIC_NOCOUNT`, and by §3.C that does not enable windowing either.
   **The published windowed timing figure (2.9204 s, +6.4%) may be measuring a non-windowed build.**
4. ★★★★ **Retire picture 80 as the reassurance case** — it is the 2-fill minimum and it is the only
   picture p3b renders correctly.
5. ★★★ **AC-7** — inject a fault on this build.
6. ★★★ **Widen the renderer corpus past 1,263 bytes**, or state that 45/45 is a claim about 29% of
   pictures and 17.5% of fills.
7. ★★ **Re-check gate artifacts at task END** — carried from P3b.14, P3b.15 and P3b.16.

---

### 9 — User interaction during task

1. Jay, mid-run: *"check"* — reported the elimination table as it stood.
2. Jay: *"yes run it"* — authorised the straddle/borrow investigation that produced §3.D.
3. Jay: *"shadow buffer"* — authorised B.
4. Jay, on the first shadow build: *"looks like it hung or never changed video modes"* — **named
   §3.F's defect from the symptom.** The video-mode half was the diagnostic: the harness waits on a
   counter the derailed guest never wrote.
5. Jay: ★★★★★ ***"the castle room does appear and not draw as i expect."*** — **AC-8 passed.**

### 10 — Candidate(s) captured this task

Pushed to `methodology-candidate-pool` **`main`**, `seeds/AGI/live/`:

- `2026-09-06-a-flag-that-compiles-is-not-a-flag-that-reaches-the-code.md` — §3.C: three green results
  from a build option that included a module and routed nothing through it.

★ **Not captured, deliberately:** the "one clean sample was the least demanding case" observation
(picture 80's 2 fills). It is a second instance of
**[[a-test-corpus-that-cannot-fail-must-be-built-not-found]]**, and §7's own rule about three-sample
correlations applies to my own capture decisions too — it earns a row when §3.D is proven.

★ INFRA.1's two rows remain owed (its §10).

### 11 — Commit

Committed on `wip` and pushed to `origin/wip`, staged by explicit path per §2E:
`src/harness/p3b_probe.s`, `harness/tools/p3b_show.lua`, and this report. ★ No game content (§2P).
