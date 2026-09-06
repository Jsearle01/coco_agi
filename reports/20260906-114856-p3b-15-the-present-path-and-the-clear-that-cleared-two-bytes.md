## Form B Report — P3b.15 — the present path, and the clear that cleared two bytes

**Class:** build. wip. Calibration-light — receipt stamp only.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-06 (dispatch carried no explicit receipt timestamp; report written 2026-09-06T11:48:56-04:00).

---

## §4 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `wip` @ **`65d624ed38688db21443f3d32832e47512661291`**, `origin/wip` identical, **status clean at start** |
| POP + Karateka | §2T cite P3b.14 §0 |
| `hal_sync_check.py` | **OK in all three repos** |
| the five gates + the 24/24 composite | §2T cite P3b.14 §4; **the renderer's correctness gate was re-run on the WINDOWED build this task** — see §3.D |
| **flag sets — enumerated and diffed** | **8/8 identical** at start, and 8/8 at end — with one self-inflicted break in between (§4.1) |
| **the clock — measured** | **1.789417 MHz** (ablation harness) · **1.789772 MHz** (`VP_MARK`, p3b) |
| **`HAL_gfx_swap`'s contract** | read in full; **it cannot serve p3b** — §3.A |
| **`p3b_probe`'s phase structure** | slots 5 and 6 move, 0-4 and 7 mapped once [`mmu_phase.s:9-12`]; blocks allocated at init, **`ph_blk_pri`=0, `ph_blk_fb`=2** [`p3b_probe.s:179-181`] |
| `p3b_room.lua` | **reproduces** — room 1 → `sprites 4`, room 3 → `sprites 2`, room 2 → `sprites 0` |

### §4.1 ★★★ A gate artifact was broken and restored WITHIN this task, by me

`gate_audit.py --verify` mid-task:

```
pic    build/pic_probe.bin          2785     2642  ★★★ DIFFERS -- the gate is testing something else
```

§3.D's windowed-renderer experiment ends `cp build/pic_probe_win.bin build/pic_probe.bin`, and I left
the **windowed** build (2,785 B) sitting where the gate's build (2,642 B) belongs. Rebuilt with the
manifest's flags; **8/8 identical at task end, verified.**

★★★★ **This is the second consecutive task to leave a test build in a gate artifact's place** — P4.9
left a `-DVM_FAULT` binary and P3b.14's §4 caught it. **The check works and the gap is unchanged:
nothing re-checks at task END.** It is §8's second follow-up for the second time, and it has now cost
two tasks' opening minutes.

---

### 1 — Summary

**AC-2 cannot be satisfied as written, and that is a measurement rather than an opinion:
`HAL_gfx_swap` points the display at physical blocks p3b's compositor never writes.** A harness-side
display path was built instead — no target code, no shared HAL — and with it **P3b was watched
running for the first time.**

★★★★★ **The eye gate immediately found what four byte gates did not, exactly as trigger 5 anticipates.**
Jay saw the room come up **wireframe** — lines drawn, fills absent. The cause was `p3_clear_planes`:
an **assemble-time constant overflow** that silently truncated `$12900` to `$2900`, so the visual
clear stored **2 bytes instead of 26,880**, plus a priority clear that overran its aperture into the
framebuffer window. **Fixed. Picture 80 now renders BOTH planes byte-identical to the oracle
reference — 0 of 26,880 visual, 0 of 26,880 priority.**

★★★ **The room still does not look right to Jay, and nothing measured explains it.** That is stated
rather than closed.

---

### 2 — Files modified

- `src/harness/p3b_probe.s` — `p3_clear_planes` rewritten to walk slices through the phase entry
  points; the eight MMU writes it performs are added to `P3_REMAPS` rather than left uncounted.
- `harness/tools/p3b_show.lua` — **new.** The harness-side display path (§3.B).

★ **No shared HAL file and no gate artifact's source was touched.** `gate_audit.py --verify` is 8/8
identical, and `p3b_probe` is not a gate artifact.

---

### 3 — Reasoning

#### 3.A `HAL_gfx_swap` cannot serve p3b [AC-2, triggers 1 and 3]

§2 asked whether the framing is required before designing to it [L-83]. It is not, and the reason is
four measured facts:

1. **p3b's planes are not the HAL's.** `ph_blk_pri`=0 (blocks 0-1) and `ph_blk_fb`=2 (blocks 2-5)
   [`p3b_probe.s:179-181`]. `GFX_DB_A_BLOCK`=$10, `GFX_DB_B_BLOCK`=$14 [`gfx.s:431-434`].
2. **So the swap points at the wrong RAM.** It writes VOFFSET `$4000`/`$5000` → physical
   `$20000`/`$28000` [`gfx.s:563-570`] — not blocks 2-5. ★ On a 128 KB machine $10/$14 alias to
   blocks 0 and 4: the **priority** plane, or the middle of the framebuffer [§2K].
3. **And it would tear the phase mapping.** After setting VOFFSET it remaps slot 6 to a GFX_DB block
   [`gfx.s:576-582`], which is the slot `phase_draw` owns [`mmu_phase.s:49-56`].
4. **The mode and palette half is worse.** They live in `HAL_gfx_set_mode`, which maps buffer A to
   **$8000 = `MAP_ARENA_WIN`** [`gfx.s:469-478`, `memmap.inc`] — where p3b keeps the LOGIC it is
   interpreting.

★★★★ **Trigger 1 (presenting changes what is mapped in an existing phase) and trigger 3
(`HAL_gfx_swap` does not suit) both fire.** Their stop exists because the HAL is shared across three
repos [§2M]. **The path taken changes neither the HAL nor the phase map**, so the hazard those
triggers guard is absent — but AC-2 as written is **not delivered** and §6 records that.

#### 3.B What was built instead, and what it is not

`p3b_show.lua` points the GIME at the planes the guest already wrote: `$FF98`/`$FF99` from
`gfx_mode_table` mode 2, the palette from `gfx.s`'s own `gfx_pal16`, and VOFFSET from the guest's own
`ph_blk_fb` byte (`blk * 1024`; block 2 → `$0800`, verified in the log). Mode before palette, because
palette writes do not latch until the mode is final [`gfx.s:145-148`].

★★★★ **It does NOT give the port a present path, and the report must not be read as if it did.**
The pixels are the guest's; the decision to display them is the harness's. **A real CoCo3 running
this port standalone still shows nothing.** AD-110 §3.F stands.

★ Jay's instruction — *"let the computer settle at the basic 'ok' before starting the program"* — is
carried as `-autoboot_delay 6`. `p3b_run.lua` stages at **frame 4**, ~66 ms after reset and well
before Disk BASIC reaches OK.

#### 3.C ★★★★★ The clear that cleared two bytes [AC-5, and the reason the phase looked wrong]

**Found by a human watching, not by a gate.**

```
20ED  8C 29 00    cmpx  #FB_BASE+(PIC_W*PIC_H)
```

`$C000 + $6900 = $12900`, **truncated to `$2900`** — read from the listing, not computed. X starts at
`$C000`, already above `$2900`, so `blo` failed on the first pass and the loop stored **once**.
**26,880 bytes of intended clear became 2**, and lwasm emitted it without a diagnostic.

AGI's fills are bounded by white. A visual plane never whitened gives the flood nothing to stop at —
**lines draw, fills do not.** That is the wireframe.

★★★ **The priority half was wrong differently:** `$A000+$3480 = $D480` does not overflow, but the
priority aperture is `$A000-$BFFF` (8,192 B), so it ran 13,440 and overran `$C000..$D480` — the
**framebuffer window**. T-P0-034 fixed the fill VALUE and the LENGTH at this site; the APERTURE was a
third term nobody had reason to look for.

★★★★ **WHY NO GATE COULD CATCH IT.** `pic_probe`'s map is FLAT: `FB_BASE`=$8000, so `$8000+$6900 =
$E900` — no overflow — and its plane is contiguous, so a flat clear is correct there. **The identical
expression is right in pic_probe's map and wrong in p3b's**, and `p3_clear_planes` is p3b-local code
that no gate builds.

**The fix** is `pic_probe.s:551-565`'s shape, which the 45/45 gate does cover: walk the slices,
mapping each through `phase_draw_fb` / `phase_draw_pri`, clearing one aperture at a time, with the
counter in memory because `ldd` destroys B [`pic_probe.s:541-549`]. Both planes walk here; pic_probe
only windows the visual one.

```
20F7  8C E0 00    cmpx  #FB_BASE+8192      ($E000)
2117  8C C0 00    cmpx  #PRI_BASE+8192     ($C000)
```

#### 3.D What the fix did NOT turn out to be — two hypotheses killed by measurement

★★★ **Both were plausible, both were wrong, and killing them cost less than acting on them would
have.**

1. **"The windowed renderer is not correctness-gated."** `gates.manifest`'s 45/45 row builds
   **without** `-DPLANE_WINDOWED`; the windowed row is `timing`. So I ran the **correctness** gate on
   the windowed build — a combination the manifest does not carry — and it passes **45 PASS, 0 FAIL,
   both planes**. The windowed renderer is sound.
2. **"The packed priority write zeroes every other pixel."** The histogram showed 13,440 zeros and
   every real band at exactly half its reference count — and **13,114 is literally the number in
   `pic_probe.s:616-625`'s own comment for that defect class.** It was my instrument.
   `p3b_run.lua:308-318` **already expands the packed plane when dumping** (*"it is expanded here;
   the oracle's copy is never packed"*), and I unpacked it a second time. **Compared correctly:
   0 of 26,880 differing.**

★★★★★ **I was one step from "fixing" working shared renderer code on the strength of a number that
matched a real comment in the tree.** The tell that saved it was arithmetic that was *too* clean —
every band exactly half — which is a signature of a systematic transform, not of a defect.

#### 3.E Three wrong comparisons, one file, one session [L-56]

Recorded because the pattern is the finding, not the individual slips:

| # | what I compared | why it was wrong | what it claimed |
|---|---|---|---|
| 1 | guest visual vs oracle visual, raw bytes | guest doubles each pixel into both nibbles (`$FF`=15); oracle stores `$0F` | **97.6% divergence** on a perfect render |
| 2 | priority band histogram in PowerShell | hashtable keyed by `byte` looked up by `Int32` — the reference column silently counted **nothing** | a reference with no pixels at all |
| 3 | priority, unpacking the dump | the dump was **already unpacked** | a textbook nibble defect that does not exist |

★★★ **All three produced confident, plausible, wrong numbers, and none of them failed loudly.** The
render was correct throughout. **§2O.1's rule that a baseline must never be self-referential has a
sibling: a comparison must state the ENCODING of both sides**, and none of the three did.

#### 3.F Authority tiers

Every figure is fresh tool output on this machine (25.1). The oracle's planes are cited as the
reference per §2O.1. §2H's three checks: the second mechanism was looked for and found twice — the
clear has a visual half AND a priority half, wrong for different reasons; and `HAL_gfx_swap` has a
VOFFSET half AND a remap half, both disqualifying. Calling routines are named at each step. The
prior-report grep is §3.A's reconciliation against AD-110 §3.F, whose inference this task **confirms
by measurement**.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] — PASS, after a self-inflicted break.** `hal_sync_check.py` OK in
  all three; `reg_discipline.py` **8 accesses, 1 file, 2 registers** — noted, not chased [AD-104].
  **Gates unchanged: 8/8 identical at task end**, after restoring the `pic_probe.bin` I overwrote
  (§4.1). §2T citation: P3b.14 §0/§4.
- **AC-2 [class: byte-comparable] — NOT DELIVERED AS SPECIFIED.** The probe does **not** present, and
  `HAL_gfx_swap` cannot make it (§3.A) — four measured reasons, triggers 1 and 3. **What was built is
  a harness-side display**, which is not the same thing and is labelled as such throughout (§3.B).
  ★ The phase question the AC asks is answered: the display writes happen **outside the guest
  entirely**, from a frame notifier, with nothing mapped or unmapped.
- **AC-3 [class: byte-comparable] — PASS.** Presenting alters no byte: the display path writes only
  GIME registers, never RAM. **`gate_audit.py --verify` 8/8 identical**, and the compositing gate's
  inputs are untouched. ★★ Stronger than asked: after the clear fix, **p3b's own render of picture 80
  is byte-identical to the oracle on BOTH planes** — 0 of 26,880 visual, 0 of 26,880 priority.
  Trigger 2 does not fire.
- **AC-4 [class: state-comparable] — measured, clock stated.** **The display costs the guest
  nothing** — it is host-side, per frame, outside the emulated CPU. ★★ **The CLEAR fix has a real
  cost and it is attributed separately** [L-54]: cycle 1 **6.0411 s → 7.0758 s** and **remaps 4 →
  12**, because the clear now clears 40,320 bytes instead of 2 and performs six slice maps plus the
  restoring pair. Clock **1.789772 MHz measured** (`VP_MARK`). ★ Per **room change**, not per cycle:
  steady-state cycles still report `remaps 2`.
- **AC-5 [class: eye-gated] — WATCHED, and NOT PASSED. "pending Jay."** ★★★★★ **P3b was seen running
  for the first time** — a room through the real resource path, a LOGIC script driving it, sprites
  composited. Jay reported **wireframe**; that was diagnosed and fixed (§3.C); he then reported
  *"some fills, but I still see wireframe in places and it definitely doesn't look right."*
  ★★★ **That second report is unexplained by anything measured here** and is the honest state of this
  AC. Launch path **`poke`**. ★ Room 80 renders byte-perfect on both planes with 1 sprite; the room
  under the eye is room 1 with 4 sprites, and **sprites over a live render have never been
  byte-checked** — the 24/24 gate stages frames rather than running the integrated path (§8.1).
- **AC-6 [class: byte-comparable] — NOT DONE.** No fault was injected on this build. The renderer's
  correctness gate was re-run windowed and passes 45/45 (§3.D.1), which is coverage, **not
  fault-detectability**. Stated rather than implied by the green result [L-62, L-81].
- **AC-7 [class: state-comparable] — STILL OUTSTANDING, recorded.** `vm_lastsec` and `vm_lastcyc`
  remain referenced only by their declarations and the four zeroing `std`s — 8 bytes plus ~12 of
  reset code, dead. Unchanged from P3b.14 AC-8; removing them changes `vm_probe.bin` and this
  dispatch has no VM-gate AC either. ★ It is A's residue and has now been carried by three tasks.
- **AC-8 [class: state-comparable] — five things this dispatch did not anticipate.**
  (1) ★★★★★ **The clear cleared two bytes** (§3.C) — an assemble-time truncation lwasm did not flag,
  in code no gate builds, correct in the other probe's map.
  (2) ★★★★ **`build/p3b_probe_pk.map` is five days older than the `.bin`.** It sent the display to
  `$21EC` for `ph_blk_fb` (actually `$2226`), which pointed VOFFSET at **block 0 — the priority
  plane** — and reported success while doing it.
  (3) ★★★★ **Nothing in the tree builds `p3b_probe_pk`.** Its build line exists nowhere on disk —
  the L-45 defect `gates.manifest` exists to fix. **Recovered by byte-matching:
  `-DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED`**, which also shows the
  shipped artifact is **110 bytes stale** — it still contains the timer division P4.9 removed.
  (4) ★★★★ **`-DPRI_PACKED` has no correctness row.** It appears in `gates.manifest` once, in
  `pic_nc_pk`, marked `timing` — and that row is annotated "★ THE CURRENT ROOM-RENDER FIGURE".
  **The headline room-render timing comes from a configuration whose correctness is ungated.**
  ★★ Not a defect: the packed plane measured byte-identical here (§3.D.2). A coverage gap.
  (5) ★★★★★ **Three of my own comparisons were wrong before one was right** (§3.E), and the third
  would have had me change working shared code.
- **AC-9 [class: suite]** — see §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

*§4 — hal-sync, and the flag set at both ends of the task:*
```
coco_agi       : [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port      : [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3 : [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)

AT START : 8/8 identical
MID-TASK : pic  build/pic_probe.bin  2785  2642  ★★★ DIFFERS -- the gate is testing something else
AT END   : 8/8 identical   (pic 2642 2642 identical, after rebuild with the manifest's flags)

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
```

*§3.A — why HAL_gfx_swap cannot serve (read, not assumed):*
```
p3b_probe.s:179-181   clr ph_blk_pri / lda #2 / sta ph_blk_fb      -> pri blocks 0-1, fb blocks 2-5
gfx.s:431-434         GFX_DB_A_BLOCK $10, GFX_DB_B_BLOCK $14, A_VOFF $4000, B_VOFF $5000
gfx.s:563-570         std $FF9D  <- VOFFSET = $4000/$5000 = physical $20000/$28000
gfx.s:576-582         gfx_map_blocks -> remaps slot 6 to a GFX_DB block
gfx.s:469-478         HAL_gfx_set_mode maps buffer A to $8000 = MAP_ARENA_WIN
```

*§3.C — the defect, from the listing:*
```
BEFORE
20ED 8C2900    cmpx    #FB_BASE+(PIC_W*PIC_H)      ; $C000+$6900 = $12900 -> emitted $2900
20FA 8CD480    cmpx    #PRI_BASE+(PIC_W*PIC_H/2)   ; runs 13,440 through an 8,192 aperture

AFTER
20F7 8CE000    cmpx    #FB_BASE+8192
2117 8CC000    cmpx    #PRI_BASE+8192
```

*AC-3 / AC-5 — p3b's own render against the renderer gate's reference, picture 80:*
```
VISUAL    guest 26880 B   ref 26880 B
          bytes whose two nibbles DISAGREE (should be 0): 0
          differing bytes: 0 of 26880 (0.0%)
          rows with any difference: 0 of 168

PRIORITY  differing: 0 of 26880 (0.00%)
          [dump is already expanded -- p3b_run.lua:308-318]
```

*AC-4 — the clear fix's cost, and the display's:*
```
BEFORE   cycle   1  6.0411 s  room  83  sprites  0  remaps  4  err 0
AFTER    cycle   1  7.0758 s  room  83  sprites  0  remaps 12  err 0
steady   cycle   N  0.3171 s  room   1  sprites  4  remaps  2  err 0
clock MEASURED 1.789772 MHz (160009 cycles calibrated)
display: host-side, 0 guest cycles
```

*§3.D.1 — the renderer's CORRECTNESS gate on the windowed build (not a manifest row):*
```
build/pic_probe_win.bin  2785 bytes   (-DHAL_GFX_MODE_SERVICE -DPLANE_WINDOWED)
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
--- picgate exit: 0 ---
```

*AC-8(3) — the build line, recovered by byte-match:*
```
target: 12833 bytes
A  FAILED   -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK
B  FAILED   ... -DPLANE_WINDOWED
C  FAILED   ... -DPRI_PACKED
D  12723    -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED
E  12581    ... -DPIC_NOCOUNT
F  FAILED   ... -DPRI_PACKED -DPIC_NOCOUNT
★ D is the flag set; the 110-byte gap to 12,833 is P4.9's timer division, still in the shipped artifact.
```

*AC-8(4) — `-DPRI_PACKED` has no correctness row:*
```
pic       -DHAL_GFX_MODE_SERVICE                                  correctness 45/45
pic_nc    -DHAL_GFX_MODE_SERVICE -DPIC_NOCOUNT                    timing
pic_nc_pk -DHAL_GFX_MODE_SERVICE -DPIC_NOCOUNT -DPRI_PACKED       timing -- ★ THE CURRENT ROOM-RENDER FIGURE
pic_win   -DHAL_GFX_MODE_SERVICE -DPLANE_WINDOWED -DPIC_NOCOUNT   timing
```

*§3.B — the display path, and the guest's own values:*
```
MONITOR TYPE -> RGB
palette: 16 entries from gfx.s   ph_blk_fb=$225B
DISPLAY -> ph_blk_fb=2  physical=$04000  VOFFSET=$0800  (cycle 2)
★ room jump at cycle 8: var0 <- 80, flag 5 set
final room 80, sprites 1, err 0, status=$00
```

**25.2 bundled-artifact grep:** N/A — no sibling artifact imported, no bundled asset committed. The
oracle planes used as reference are the project's existing `oracle/dumps/base-Kingquest1/`, read only.

**25.3 operator-runtime-smoke:** **pending Jay — and INCOMPLETE.** Launch path **`poke`**. P3b was
watched running; the wireframe it revealed is fixed and byte-verified; **Jay's follow-up report that
the room still does not look right is unexplained and open** (AC-5). ★ Not self-certified, and not
recorded as passing.

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **AC-2's mechanism was refused on measurement.** `HAL_gfx_swap` is what the AC names and it
   cannot serve (§3.A). Triggers 1 and 3 fire; their stop protects the shared HAL, and the path taken
   touches neither the HAL nor the phase map — so the work continued rather than stopping, and
   **AC-2 is reported as not delivered as specified** rather than as satisfied by a substitute.
2. ★★★★★ **A defect was fixed that this dispatch did not scope.** `p3_clear_planes` is target code.
   It was fixed because the eye gate the dispatch exists to deliver could not be read without it, and
   because Jay said to. **It is attributed separately from the display path throughout** [L-54].
3. **`P3_REMAPS` now counts the clear's eight MMU writes.** They are real and were previously
   uncounted; the alternative was a counter that under-reports, which is this project's own disease.
   ★ It changes the published per-room-change remap figure from 4 to 12.
4. **Three wrong comparisons were made and corrected before any conclusion was acted on** (§3.E).
   The second and third each produced a report-ready "finding" that did not exist.
5. **AC-6 was not attempted.** No fault was injected on this build.
6. **A test build was left in a gate artifact's place mid-task and restored** (§4.1).

**ROUTE ACCOUNTING.** No route was proposed in advance. **Delivered:** the measured refutation of
AC-2's mechanism, a harness display path, the first watched run of P3b, the clear fix with both
planes byte-verified, and four coverage findings. **Not delivered:** AC-2 as specified, AC-5's pass,
AC-6 entirely, AC-7 again. **Not attempted:** the compositing path in the integrated probe, which is
where AC-5's remaining symptom most likely lives (§8.1).

---

### 7 — Uncertainty flags

- ★★★★★ **AC-5's remaining symptom is unexplained.** Room 80 renders byte-perfect on both planes with
  one sprite; Jay is watching room 1 with four. **Nothing in this report explains "still wireframe in
  places".** The untested difference is sprites over a live render.
- ★★★★ **The capture runs end early and I do not know why.** Runs stop at roughly 20-35 emulated
  seconds regardless of snapshot settings, which is why no PNG sequence was produced from this task;
  Jay watched the live window instead. **Not diagnosed.**
- ★★★ **The p3b figures in this report come from `p3b_probe_pk_fresh.bin`**, built from current source
  after recovering the flags. The **shipped** `p3b_probe_pk.bin` is 110 bytes stale. Any prior p3b
  figure was taken on the stale artifact, including AD-109's compositing share.
- ★★★ **§3.A's fourth point is read, not run.** That `HAL_gfx_set_mode`'s $8000 mapping would clobber
  the arena follows from `memmap.inc` and `gfx.s`; it was not demonstrated by calling it.
- ★★ **One picture, one room.** Byte-identity is established for picture 80 only.
- ★ `reg_discipline.py` still reads 8 against a recorded 5 [AD-104]; `scummvm.pin` still records five
  patches against eight applied. Carried, untouched (§11).

**Triggers:** **1 and 3 both FIRE** (§3.A) and are reported; the work continued because the taken path
touches neither the shared HAL nor the phase map. **2 does not fire** — presenting alters no plane
byte. **4 does not fire** — the display reached the glass; the register state is in §5. **5 FIRES,
and it is the task's most valuable outcome**: the eye gate found a defect four byte gates could not
(§3.C), and reported it in full.

---

### 8 — Follow-up candidates

1. ★★★★★ **Byte-check the compositor in the INTEGRATED path.** Dump p3b's planes after sprites and
   compare against the oracle's `after` planes. **This is where AC-5's remaining symptom most likely
   lives**, and the 24/24 gate does not cover it — it stages frames rather than running the render.
2. ★★★★★ **Re-check gate artifacts at task END.** Two consecutive tasks have left a test build in
   place. This is P3b.14's follow-up 2, unactioned, and it has now happened again.
3. ★★★★ **Add a `pic_pk` CORRECTNESS row** (`-DHAL_GFX_MODE_SERVICE -DPRI_PACKED`) to
   `gates.manifest` and teach `picgate.py` to expand. The room-render headline comes from an ungated
   configuration (AC-8.4).
4. ★★★★ **Record `p3b_probe_pk`'s build line** in `gates.manifest` and rebuild the shipped artifact;
   it is 110 bytes stale and its map is five days older still (AC-8.2, AC-8.3).
5. ★★★ **Give the port a real present path** — AD-110 §3.F's design question, still open. §3.A now
   says what it cannot be.
6. ★★★ **Diagnose the truncated capture runs** so a PNG sequence can be produced without a human at
   the window.
7. ★★ **Remove `vm_lastsec` and `vm_lastcyc`** (AC-7, third task carrying it).
8. ★★ **Widen §3.C's check** — one picture proves the clear; the other 44 would prove the fix.

---

### 9 — User interaction during task

1. Jay: *"you need to let the computer settle at the basic 'ok' before starting the program"* —
   carried as `-autoboot_delay 6` (§3.B). `p3b_run.lua` stages at frame 4, far before OK.
2. Jay, watching the run: *"i see the king's quest title screen. then another room overwrites it but
   it is wireframe only"* — **the observation that produced §3.C**, and the reason this task has a
   defect to report at all.
3. Jay, after the fix: *"some fills, but i still see wireframe in places and it definitely doesn't
   look right"* — recorded as AC-5's open state (§7).
4. Jay: *"go to make the fix"*, then *"write it up"*.

### 10 — Candidate(s) captured this task

Pushed to `methodology-candidate-pool` **`main`**, `seeds/AGI/live/`:

- `2026-09-06-a-comparison-must-state-the-encoding-of-both-sides.md` — §3.E: three wrong comparisons
  of one pair of files, each confident and plausible, none failing loudly.
- `2026-09-06-a-constant-that-overflows-its-operand-is-a-silent-truncation-not-an-error.md` — §3.C:
  the same expression correct in one memory map and silently wrong in another.

★ **INFRA.1's two rows remain owed** (its §10).

### 11 — Commit

Committed on `wip` and pushed to `origin/wip`, staged by explicit path per §2E:
`src/harness/p3b_probe.s`, `harness/tools/p3b_show.lua`, and this report. ★ No game content is in
that list (§2P); nothing was captured to disk this task, and Jay watched the live window.
