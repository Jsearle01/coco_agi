## Form B Report — P3b.1 — a room and a script, on hardware
**Class:** build. wip. ★★★★ **STOPPED ON §8 TRIGGER 1 — the five subsystems do not fit
simultaneously. The numbers are below and they are the answer P3b exists to get early.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-29 (HEAD `47ff5a7`, wip). git status clean at receipt.

---

### §3 — Pre-dispatch grep (verbatim, before the summary)

```
=== coco_agi ===
47ff5a7
wip
(git status clean)

=== siblings (§2T: cite P6.1 §0) ===
POP3_port          104b197  wip  tracked-modified=0
karateka_coco3     29f8f0a  wip  tracked-modified=1

=== hal_sync ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared,
           EOL/guard/export-placement normalised)

=== reg_discipline ===
[reg-discipline] 5 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   5   $FFA5 $FFA6

=== the map ===
ALL MAP ASSERTIONS PASS
MAP_ARENA_WIN   equ  $6000      MAP_ARENA_WIN_E equ  $A000   (16,384 B, two slots)
MAP_ARENA_BYTES equ  24576      MAP_PRI_BYTES   equ  13440
```

**The five gates, all re-run against the reconciled map:**

| gate | result |
|---|---|
| renderer | **45 PASS, 0 FAIL** (of 45), 3 games, both planes |
| resources | **1,264 byte-identical** across 10 (title, volume) sweeps, all clean |
| VM | **nine titles all PASS**, 0 divergent of 600 cycles × 288 bytes |
| cels | **6,782 / 6,782**, 995 mirrored, 0 mismatch |
| compositing | **20 frames: 20 identical, 0 divergent** |

**The room jump:** `vm_sweep.lua:357-358` — `write_u8(VM_VARS+0, ROOM)` then
`write_u8(VM_FLAGS+0, b | 0x20)`. Two host writes, reproducible.

★ **§2T:** sibling baseline cited from **P6.1 §AC-1** — POP `104b197`, karateka `29f8f0a`, both
unchanged; lwasm 4.24 unchanged. **This task modifies no shared file**, so no sibling rebuild.

**No contradiction found. Proceeded.**

---

### 1 — Summary

★★★★ **P3b stopped at §8 trigger 1, with the numbers, and this is the task working rather than
failing.** The five subsystems assemble into one image for the first time — **11,768 bytes** —
and then do not fit the machine:

> **The draw phase needs 72,194 bytes against the 65,280 available below the I/O page.
> Over by 6,914.**

★★★★ **And the fix is already in the map, unimplemented.** `memmap.inc` specifies the priority
plane **packed at 4 bpp (13,440 B)**. Every subsystem writes **one byte per pixel (26,880 B)**.
Packing saves exactly 13,440 and brings the draw phase to **58,754 — fits, with 6,526 spare.**
★★★ **So the 4 bpp decision is not a space optimisation to be scheduled. It is what makes the
draw phase fit at all** — and P6.1 (mine, one task ago) recorded it as *"a divergence whose cost
is a nibble extract on the cheap path"*, which is a true sentence that hid a requirement inside a
trade-off.

★★★ **The planes did not grow; the code did.** `pic_probe` is 2,642 B and `comp_probe` 967 B, and
both hold two flat planes comfortably. The full engine is **11,768 B** — +7,928 — and that plus
the cel staging is the entire overrun.

★★★★ **AC-5 answers separately and also says no.** The VM alone is **129–174 ms/cycle** [P4.5];
compositing 4 sprites is **56.07 ms** [P5.4]. **KQ1 + 4 sprites = 215.0 ms and KQ3 = 230.5 ms,
against a 200 ms budget** — over before motion, fetch or text. A room render is **2,746 ms**, a
**13.7-cycle stall.**

★★ **AC-8 is rich and is the other half of the value.** 33 undefined symbols on first assembly:
**three of the five "subsystems" were code fragments that depended on their probe.** The renderer
core (331 lines, including `put_pixel` and every PICTURE opcode) was extracted to
`src/harness/pic_core.s` — **verified byte-identical**.

---

### 2 — Files modified

- `src/harness/pic_core.s` — **new.** The renderer, extracted from `pic_probe.s` so a second
  image can hold it. ★ Pure move; `pic_probe.bin` **byte-identical**, verified.
- `src/harness/pic_probe.s` — the extracted region replaced by one `include`. **No behaviour
  change** (byte-identical binary).
- `src/harness/vm_state.s` — `ifndef` guard around the VM state addresses so the map can drive
  them. ★ Defaults unchanged; `vm_probe.bin` **byte-identical**, verified.
- `src/harness/p3b_probe.s` — **new.** The integration probe, and the armed trigger-1 assertion.

★ No game data, no resource bytes, no frames (§2P). No shared HAL file (§2M).

---

### 3 — Reasoning

#### 3.1 The measurement that stops the task

Both renderers address planes **flat**. `pic_core.s`'s `pix_addr`:

```
lda cur_y / ldb #PIC_W / mul        ; D = y*160
addb cur_x / adca #0                ; D = y*160 + x       -- to 26,879
addd #FB_BASE / tfr d,x             ; X = visual
ldd pix_off / addd #PRI_BASE        ; Y = priority, SAME offset, SAME stride
```

`composite.s`'s `co_rowset` computes `y*160` the same way. ★★ **Both planes are one byte per
pixel and both are indexed flat**, so during a draw phase the CPU must see, at once:

| region | bytes |
|---|---|
| visual plane, flat, 1 B/px | 26,880 |
| priority plane, flat, 1 B/px | 26,880 |
| **engine code (MEASURED, this build)** | **11,768** |
| decoded cel staging (corpus max) | 4,784 |
| picture seed stack (fills run in this phase) | 1,024 |
| hardware stack | 768 |
| status + counters | 90 |
| **total** | **72,194** |
| available `$0000`–`$FEFF` | **65,280** |
| ★★★ **over by** | **6,914** |

★★★ **With the map's 4 bpp priority: 72,194 − 13,440 = 58,754. Fits, 6,526 spare.**

★★ **The assertion is left ARMED in `p3b_probe.s`**, so this is a property of the tree and not a
paragraph [L-27]:

```
ERROR : User Specified: "DRAW PHASE DOES NOT FIT: planes+code+cel+stacks exceed $0000-$FEFF.
4bpp priority packing (memmap.inc MAP_PRI_BYTES) is unimplemented and is load-bearing."
```

`-DP3B_ACCEPT_OVERRUN` builds anyway, which is how the 11,768 was measured.

#### 3.2 Why every probe fitted alone

| image | code | planes | fits? |
|---|---|---|---|
| `pic_probe` | 2,642 | pri `$1700`–`$7FFF`, vis `$8000`–`$E8FF` | ✓ |
| `comp_probe` | 967 | pri `$2900`, vis `$9200`, both flat | ✓ |
| **`p3b_probe`** | **11,768** | both flat | ✗ **by 6,914** |

★★★ **The constraint is a property of the CODE SIZE, not the data** — and that is L-63 inverted.
L-63 (mine, two tasks ago) says the binding constraint is often a property of the data; here the
data was constant across all three images and the code quadrupled.

#### 3.3 §2H's three checks

1. **A second mechanism for a different object class?** ★★ **Yes.** The *renderer* needs the
   planes flat for `put_pixel`; the *compositor* needs them flat for `co_rowset`. Fixing one
   addressing scheme does not fix the other — they are two callers of the same assumption.
2. **The calling routine.** `put_pixel`'s callers are `pic_draw`'s line loops and `pic_fill`'s
   span filler, which walk **arbitrary** pixel order. ★★★ So a sliced framebuffer is not a
   remap-per-scanline problem, it is **remap-per-pixel in the worst case** — a flood fill wanders
   freely. That closes slicing as an option without measuring it (trigger 3's failure shape).
3. ★ **Grepped the reports before citing.** P6.1 §AC-3 and §7.1 both record the 4 bpp decision;
   neither states it as a fit requirement. **This report supersedes that framing.**

#### 3.4 The extraction, and why it was safe

`p3b_probe.s` named **33 undefined symbols**: the renderer core (`put_pixel`, `pix_addr`,
`cur_x/cur_y`, `scr_on/pri_on`, `pic_render` and the opcode handlers), the compositor's inputs
and counters, and ten instrumentation counters. ★★ The renderer core moved to `pic_core.s` —
same content, same order, same position, and nothing between the old regions emitted bytes — and
`pic_probe.bin` is **byte-identical across the change, verified rather than assumed.**

★★ **The instrumentation asymmetry is a finding**: `composite.s` guards its counters behind
`-DCOMP_NOCOUNT` (load-bearing — the counted build runs **1.75×** slower, which is why P5.4 took
timings from the no-count build); `pic_draw.s` and `pic_core.s` increment unconditionally.
**A shipped renderer currently cannot be built without its diagnostics**, and nobody decided that.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** ★★ **PASS.** All five gates re-run — §3's table.
  `hal_sync` OK in all three; `reg_discipline` 5 accesses / 2 registers / one owner. §2T cited
  from P6.1 §0. ★ Two byte-identity proofs added this task: `pic_probe.bin` across the
  extraction, `vm_probe.bin` across the guard.

- **AC-2 [class: state-comparable]** ★★★★ **NOT ACHIEVED — blocked by §3.1, reported per trigger
  1.** The image assembles (11,768 B) and the resource path is wired — `PIC_DATA equ
  MAP_ARENA_WIN`, so a PICTURE fetched by `(type, index)` lands where `pic_render` reads. **No
  room was drawn on hardware**, because the draw phase cannot be mapped. Title/room/cycles: **not
  reached.**

- **AC-3 [class: byte-comparable]** ★★★ **NOT ACHIEVED** — no framebuffer to hash. Blocked by
  AC-2.

- **AC-4 [class: state-comparable]** ★★★★ **NOT ACHIEVED** — the integration gate the dispatch
  calls the task did not run. ★★ **This is the one I most regret not reaching**, and it is
  genuinely blocked: the VM cannot run beside a renderer that cannot be mapped.

- **AC-5 [class: state-comparable]** ★★★★ **ANSWERED BY COMPOSITION, AND THE ANSWER IS NO.**
  ★★★ **This is arithmetic over separately-measured numbers, NOT a measurement** (§8; L-61 wants
  two ways and I have one). Clock **1.789390 MHz** [L-57].

  | component | ms/cycle | source |
  |---|---|---|
  | VM interpreter | **129.4 – 174.4** | P4.5, measured, 4 titles |
  | compositing, 2 sprites | 28.04 | P5.4, measured |
  | compositing, 4 sprites | **56.07** | P5.4, measured |
  | compositing, 6 sprites | 84.11 | P5.4, measured |
  | phase remaps (2 writes) | ≈0.008 | 14 cycles — negligible |
  | resource fetch, 3 KB picture | ≈20.6 | 1,022 cy + 11.98/byte |
  | **room render** | **2,746** | P3.3 — ★★★ **a 13.7-cycle stall** |

  **Against the 200 ms budget, VM + compositing alone:**

  | title | 2 sprites | 4 sprites |
  |---|---|---|
  | PoliceQuest1 (129.4) | 157.4 ✓ | 185.5 ✓ |
  | SpaceQuest-1 (137.1) | 165.1 ✓ | 193.2 ✓ *(96.6%)* |
  | Kingquest1 (158.9) | 186.9 ✓ *(93.5%)* | ★★ **215.0 ✗** |
  | Kingquest3 (174.4) | 202.4 ✗ | ★★ **230.5 ✗** |

  ★★★ **Two of four titles exceed 200 ms at four sprites; KQ3 exceeds it at two.** Nothing has
  headroom for motion, text or a fetch. ★★ **What dominates is the VM**, at 65–87% of the budget
  before anything else runs — and P4.5's fit attributes **66–80% of the interpreter to resource
  copying.**

- **AC-6 [class: state-comparable]** ★★ **PARTIAL — the mechanism is built and counted, not
  exercised.** `mmu_phase.s` moves exactly **two** slots (5 and 6); `p3b_probe.s` counts its own
  remaps into `P3_REMAPS`. ★★★ **But §3.3's check 2 closes the slicing question analytically:**
  `put_pixel`'s callers walk arbitrary pixel order, so a sliced plane is **remap-per-pixel**, not
  per-scanline. **The phases stay disjoint only because the planes are flat**, which is what does
  not fit.

- **AC-7 [class: byte-comparable]** ★★ **PARTIAL, and honestly so.** The injected fault could not
  be run on the P3b corpus because there is no P3b run. ★★★ **What IS proven on this task's own
  artifacts:** the trigger-1 assertion fires with its exact message, and the map assertion fires
  when the arena window is shrunk. ★ **Per L-62 I am NOT claiming the renderer's fault transfers**
  — it was re-proven on its own corpus in P6.1 (1 picture, pixel (37,42), other 44 pass) and that
  says nothing about an integrated corpus that does not exist.

- **AC-8 [class: state-comparable]** ★★★★ **PASS — and "nothing" was not the answer.** Four
  distinct breakages, each evidenced:
  1. ★★★ **The draw phase does not fit** — §3.1, 6,914 bytes, assertion armed.
  2. ★★★ **Three of five "subsystems" were not modules** — 33 undefined symbols; the renderer
     core (331 lines, incl. `put_pixel`) lived in its probe. Extracted.
  3. ★★★ **The VM state block is 8,736 B and P6.1's map allocated 2,048.** `VM_OBJ` is
     **255 × 32 = 8,160** [`vm_state.s:63-66`] because `SCREENOBJECTS_MAX = 255  # KQ3 uses o255`
     [`tools/agivm/state.py:32`] — a real index in a real title. ★★★★ **P6.1 said "16 × 42 B",
     which was my own arithmetic and not read from the source** — L-63 in the task that wrote
     L-63. Resolved by putting `VM_OBJ` in slot 5, idle during the VM phase (8,160 of 8,192 — a
     32-byte margin, which is uncomfortable and is reported as such).
  4. ★★ **The two subsystems disagree about whether instrumentation ships** — §3.4.

- **AC-9 [class: eye-gated]** ★★★ **NOT PRODUCED — nothing reached the screen.** No image, no
  animation. ★★ Had one been produced the launch path would be **`poke`**, which §2 and §4 say is
  never a delivery gate. **25.3: N/A, not "pending Jay"** — there is nothing for Jay to look at,
  and recording it as pending would misrepresent a blocked AC as a queued one.

- **AC-10 [class: suite]** ★ **Three rows** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
byte-identical resources: 1264 across 10 (title, volume) sweeps -- all sweeps clean
TOTAL             6782    6782    6782       0        0      995
=== AC-2 SUMMARY === Kingquest1..BlackCauldron : nine titles, all PASS
★ 20 frames: 20 identical, 0 divergent
```

```
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[reg-discipline] 5 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s                       5  $FFA5 $FFA6
```

```
★★★ BYTE-IDENTICAL — the extraction is a pure move        (pic_probe.bin)
★ BYTE-IDENTICAL — the guard changed nothing              (vm_probe.bin)
```

```
=== armed (expect the trigger-1 error) ===
src/harness/p3b_probe.s(264) : ERROR : User Specified: "DRAW PHASE DOES NOT FIT:
planes+code+cel+stacks exceed $0000-$FEFF. 4bpp priority packing (memmap.inc MAP_PRI_BYTES)
is unimplemented and is load-bearing. See the block above. -DP3B_ACCEPT_OVERRUN to build anyway."

=== with -DP3B_ACCEPT_OVERRUN (for measuring the parts) ===
  p3b_probe.bin: 11768 bytes
```

**AC-5's budget** — §4's tables, composed from P4.5 and P5.4 at 1.789390 MHz.
**AC-3's hashes:** none — no framebuffer produced.
**AC-4's diff:** none — the integrated loop did not run.

**25.2 bundled-artifact grep:** N/A — no bundled artifact. `p3b_probe.bin` builds only under
`-DP3B_ACCEPT_OVERRUN` and is not a runnable image.

**25.3 operator-runtime-smoke:** **N/A** — nothing reached the screen (AC-9). Launch path would
have been **`poke`**, which is never a delivery gate (§2, §4).

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **Stopped on trigger 1** rather than working around the overrun. The dispatch: *"Report
   the numbers and stop — that is a design constraint and it reopens §3.6 and §9, and it is the
   answer P3b exists to get early."*
2. ★★ **Extracted `pic_core.s` from `pic_probe.s`** — a structural change to a gated file the
   dispatch did not ask for. Justified by §4D ("five subsystems sharing one 64 KB map"), which is
   impossible while the renderer is welded to its probe. **Byte-identity verified.**
3. ★★ **Guarded `vm_state.s`'s addresses.** Same reason, same proof.
4. ★ **Left the trigger-1 assertion armed**, so `p3b_probe.s` does not build by default. That is
   deliberate — a finding that cannot fail is not a finding.

**ROUTE ACCOUNTING.** No route proposed beyond the AC list. ★★ **What I did NOT do:** did not
implement 4 bpp packing (that is the design call §8 trigger 1 hands back, and §12 forbids
optimising); did not slice the planes; did not run the integrated loop, draw a room, hash a
framebuffer, diff per-cycle state, or produce an image; did not touch the parser, sound, storage
or `LOADER.BIN`; did not measure the composed cost on hardware — **AC-5 is composition, not
measurement, and is labelled so.**

---

### 7 — Uncertainty flags

1. ★★★★ **AC-5 is arithmetic over prior measurements, not a measurement** (§8). L-61 asks for two
   ways; there is one. **The integrated measurement is exactly what was blocked.**
2. ★★★ **The 6,914-byte overrun uses the CURRENT code size (11,768 B) with STUB glue.**
   `p3_run_vm`, `p3_stage_sprites` and `p3_composite_all` are `rts`. **The real overrun is
   larger**, and the 6,526-byte margin after packing shrinks by however much the glue costs.
3. ★★★ **4 bpp packing is asserted to be sufficient, not demonstrated.** It closes the space gap
   arithmetically; its cycle cost is still unmeasured (P5.4 §7.1 carried the same flag) and it
   lands on the VM-dominated budget of AC-5, which is already over at four sprites.
4. ★★ **`VM_OBJ` in slot 5 leaves a 32-byte margin** (8,160 of 8,192). That is too tight to be
   comfortable and assumes the compositor never needs the object table mapped — true for a staged
   sprite list, unverified for anything else.
5. ★★ **P6.1's map is not yet corrected in the tree.** Its VM-state region (2,048 B) is wrong by
   6,688 and the code region (12,288 B) now has only 520 B of headroom against a stub build.
   ★ `memmap.inc` still says *"screen objects, 16 x 42 B"*.
6. ★ **The candidate push failed on auth** — third consecutive task. Rows are local only.

---

### 8 — Follow-up candidates

1. ★★★★ **The design call trigger 1 hands back:** implement 4 bpp priority packing, or revisit
   §3.2 / §3.6 / the priority screen's resolution. **Nothing integrates until this is settled.**
2. ★★★★ **The VM is the budget**, at 65–87% before anything else. P4.5 attributes **66–80% of it
   to resource copying**, and that is the single largest lever in the project.
3. ★★★ **Correct `memmap.inc`** — the VM-state region (8,736 B, not 2,048) and the code region's
   real headroom. The map is the artifact everything builds on and it is now known-wrong in two
   places.
4. ★★ **Guard the renderer's counters** behind a `-DPIC_NOCOUNT`, matching `composite.s`.
5. ★★ **The room render is 2,746 ms — a 13.7-cycle stall.** Whatever the per-cycle answer, a room
   change needs its own treatment.
6. ★ **AD-77** (the vacuous gameplay gate) remains open and out of scope.

---

### 9 — User interaction during task

`None.`

---

### 10 — Candidate(s) captured this task

Three rows in `seeds/AGI/live/`, committed locally. ★ **Push failed** — `Authentication failed`,
third task running — fire-and-forget per §2C, does not gate. No credential copied anywhere.

- `2026-08-29-a-divergence-recorded-with-its-cost-can-be-a-requirement-recorded-as-a-preference.md`
- `2026-08-29-the-unit-you-gated-is-not-the-unit-you-can-reuse.md`
- `2026-08-29-unguarded-instrumentation-quietly-becomes-part-of-the-product.md`

---

### 11 — Commit

`ad1cf1a` (pushed to origin/wip)
