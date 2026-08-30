## Form B Report — P3b.6 — close P3b: a room and a script, running
**Class:** build. wip.
★★★★ **NOT CLOSED. The image boots and the VM runs, but the map's 8 KB phase SLICES cannot host
the planes' FLAT addressing — and AC-2's arithmetic never tested that.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-31 (HEAD `c58c5bb`, wip). git status clean at receipt.

---

### §3 — Pre-dispatch grep (verbatim, before the summary)

```
=== coco_agi ===        c58c5bb  wip   (clean)

=== siblings (§2T: cite P3b.5 §0) ===
POP3_port          104b197 wip  tracked-modified=0
karateka_coco3     29f8f0a wip  tracked-modified=1

=== hal_sync ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)

=== reg_discipline ===
  src/engine/mmu_phase.s                       5  $FFA5 $FFA6

=== the reservation [M-46] ===
MAP_CODE_END $5300   MAP_RESERVED $5300   MAP_RESERVED_END $6000   = 3,328 B
```

★★★★ **The phase arithmetic, checked BEFORE building as §3 required — and the cache HAD eaten
into it:**

```
  packed P3b code             12,651 B  (was 12,299 pre-cache)
  draw phase                  60,058 B  against 65,280
  spare                        5,222 B  (AD-85 recorded 5,574 pre-cache)
```
★ Trigger 1 did not fire on the arithmetic. **§3.1 is why that was not enough.**

**Gates:** resources **1,264** all clean · VM **nine titles PASS** · cels **6,782/6,782**.
★★ Renderer and compositing gates were **not re-run** — §6.

**No contradiction found. Proceeded.**

---

### 1 — Summary

★★★★ **The integrated image builds, boots, and runs the VM cycle on hardware** — 13,048 bytes,
five subsystems linked, **two MMU remaps per cycle** exactly as §3.4 requires. Getting there took
**six defects**, every one found by measurement rather than reading.

★★★★ **But P3b does not close, and the reason is a distinction I collapsed.** AC-2's arithmetic
counts both planes resident — 26,880 visual + 13,440 priority — and says 60,058 of 65,280. **The
map does not give them that.** It gives each draw phase an **8,192-byte slice** in slots 5 and 6,
while `put_pixel` and `co_rowset` index **flat** to 26,879:

> `FB_BASE $C000 + 26,879 = $128FF` → **wraps to `$28FF`, inside the code region `$2000–$5300`.**
> The renderer overwrites its own code. The CPU ends up executing the seed stack at `$0102`.

★★★ **I wrote that warning myself, in this probe, last task** — *"composite.s and pic_core.s both
address their planes as FLAT arrays… the map gives them 8 KB SLICES."* Then packing made the
SPACE fit and I treated the space question as the whole question. **Space and addressability are
different problems.**

★★ **A second, independent bug found on the way and fixed:** the LOGIC cache's relocation copied
**forward** into an overlapping destination. It is invisible to every existing gate because
`vm_probe`'s 21,760-byte arena separates the regions and p3b's 16,384-byte arena does not — **a
latent corruption inherited by any client with a smaller arena.**

---

### 2 — Files modified

- `src/harness/p3b_probe.s` — the cycle glue: `p3_run_vm`, `p3_room_check`, `p3_clear_planes`,
  `p3_stage_sprites`, `p3_composite_all`, plus five boot/ordering fixes (§3.2).
- `src/harness/res_core.s` — **`res_cache_stash` copies backward** (§3.3).
- `src/harness/pic_core.s` — `pic_render_at`, a **label only**; `pic_probe.bin` byte-identical.
- `src/engine/memmap.inc` — `MAP_RESERVED_MIN` floor added; boundary taken to `$5400` and
  **given back** (§3.4).
- `harness/tools/p3b_run.lua` — **new.** The integrated driver.
- `harness/tools/p3b_where.lua`, `src/harness/p3b_boot_test.s` — **new.** Localisers.

---

### 3 — Reasoning

#### 3.1 ★★★★ Why AC-2's arithmetic passed and the build still cannot render

AC-2 asks whether the phase **fits**. It does: 60,058 against 65,280. That figure sums the
planes' **sizes**. It says nothing about whether the plane is **contiguously addressable at the
base the code indexes from**, and the map's phase design is explicitly a *slice* model —
`MAP_PRI_SLICE` and `MAP_PHASE_WIN` are 8,192 bytes each.

| | needs | map gives |
|---|---|---|
| visual, flat from `FB_BASE` | **26,880 contiguous** | 8,192 (slot 6) |
| priority, flat from `PRI_BASE` | **13,440 contiguous** | 8,192 (slot 5) |

★★★ **Both planes flat is 40,320 bytes and slots 5+6 are 16,384.** So the draw phase would need
four slots, not two — and that reopens the map, not the probe.

★★ **The measurement that named it:** the stuck run's most-visited PCs included `$43A1`, inside
`put_pixel`, alongside `$0102` in the seed stack. `$C000 + 26,879` wraps to `$28FF`, in the code.

#### 3.2 AC-9 — six defects, and "nothing" was never a risk

1. ★★★★ **`HAL_sys_init` enables MMUEN before writing `$FFA0..$FFA7`.** Between the two, slot *n*
   maps whatever its register held, so code in a slot fixed later vanishes mid-call. Every prior
   probe orgs at `$0700` — slot 0, fixed first, **never exposed**. The reconciled map spans slots
   1–2 and lands the HAL itself near `$4E00`. ★ Found with **progress markers**, not a PC
   histogram: marker `$A2` said it reached the instruction before `jsr HAL_sys_init` and never
   the one after. Fixed host-side; **no shared HAL file touched** (§2M).
2. ★★★★ **`vm_start` was never called.** The object table stayed uninitialised, every cycle
   staged the 16-sprite cap from garbage flags, and the run measured **1.93 cycles/second**.
   ★★ **It did not look like a fault; it looked like a slow interpreter** — and AC-5 is exactly
   the number this task exists to report, so it would have been reported [L-56].
3. ★★★ **The phase blocks were never allocated.** `mmu_phase.s` declares `ph_blk_pri`/`ph_blk_fb`
   *"filled at init by the allocator"* and **nothing filled them** — both phase slots mapped
   physical block 0. **A declaration that says "filled at init" is not an initialisation.**
4. ★★★★ **`phase_vm` never restores slot 5**, by design: *"SLOT 5 IS LEFT ALONE… the VM phase is
   defined by what it does NOT touch."* Correct for a phase where slot 5 holds nothing — but
   P6.1's map put `VM_OBJ` there *because* it is idle during draw. **Two individually sound
   decisions that break together.** The object table read priority-plane bytes after the first
   draw. ★ An **engine design gap**, patched harness-side and reported rather than slipped in.
5. ★★★ **The probe read `vm_roomnr`, not `VAR_CURRENT_ROOM`.** The oracle is in room **83 from
   cycle 0** (checked, not assumed); `vm_roomnr` only moves on the `new.room` command, so it
   stayed 0 for 300 cycles and the probe fetched PICTURE 0 → `RES_E_EMPTY`. **The room was right
   and the variable I read was not.**
6. ★★ **`P3_ROOM` and `P3_ERR` were never written by the guest**, so the host printed `room 0`
   and `err 255` from uninitialised bytes — a diagnostic reporting a failure that did not exist.

#### 3.3 ★★★★ The cache's overlapping copy — invisible to every gate

`res_cache_stash` relocates a freshly-fetched LOGIC from the stack scratch into the cache region.
It copied **forward**, and the two regions can overlap:

| arena | scratch ends | cache dest starts | overlap |
|---|---|---|---|
| `vm_probe` 21,760 B (`$6B00`–`$C000`) | `$8E27` | `$9CD9` | **none** |
| `p3b` 16,384 B (`$6000`–`$A000`) | `$8327` | `$7CD9` | ★★ **~1.4 KB** |

★★★ **Whether the bug bites is a property of the ARENA SIZE, not of the routine** — so the
nine-title gate passes and a client with a smaller arena inherits silent corruption. Fixed by
copying from the high end downward; the destination is always above the source here, so no
overlap test is needed. ★ **VM gate re-run after the change: nine titles PASS.**

#### 3.4 The reservation floor worked, and the proof is that I reversed a decision

T-P0-036 §8.4 asked for *"a stated floor and an owner before it is reduced a third time"*. This
was the third time, so `MAP_RESERVED_MIN` (3,072) landed **with** the reduction, and it fires
when tripped — verified.

★★★ Then it earned its keep. Halt detection needed 7 more bytes; the floor **refused the build**;
I moved the boundary to `$5400` deliberately (reservation to 3,072, exactly the floor); the
resulting run was worse in every respect — stack wild, status block scribbled. **So the 7 bytes
bought nothing and I gave them back.** ★★ **The reservation stands at 3,328.** The floor turned a
slide into a decision, and a decision made explicitly could be reversed.

★ Halt detection was then obtained **free**, host-side, by reading `vm_quit`/`vm_badop` through
the build's symbol table — no guest code, no code-region pressure.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** ★★ **PARTIAL.** `hal_sync` OK; `reg_discipline` 5/2/one owner;
  §2T cited from P3b.5 §0. **Resources 1,264 clean and VM nine titles PASS — both re-run AFTER
  the `res_core.s` change.** Cels 6,782/6,782. ★★★ **The renderer and compositing gates were not
  re-run** (§6); `pic_core.s`'s change is a label only and `pic_probe.bin` is verified
  byte-identical, so they cannot have moved — but that is an argument, not a run.

- **AC-2 [class: byte-comparable]** ★★★ **PASSES AS ASKED, AND THAT IS THE PROBLEM.**
  **60,058 against 65,280, spare 5,222**, reservation **3,328**. ★★★★ **The figure is a SIZE sum
  and the build still cannot address the planes** (§3.1). **AC-2 as specified does not test what
  it is being relied on for.**

- **AC-3 [class: state-comparable]** ★★★ **PARTIAL.** Title **Kingquest1**, room **83** resolved
  from `VAR_CURRENT_ROOM`, **PICTURE 83 fetched through the real path (`res_open`, `err 0`)** —
  not poked. The LOGIC cycle runs. ★★ **But the render corrupts the code and the run hangs**, so
  "a room drawn" is not achieved. Cycles: 300 clean before the room resolved; 1 after.

- **AC-4 [class: byte-comparable]** ★★★ **NOT ACHIEVED.** No trustworthy framebuffer to hash.

- **AC-5 [class: state-comparable]** ★★★★ **NOT ACHIEVED, AND THE FIGURES I DO HAVE ARE NOT IT.**
  Clock **1.789390 MHz**. Measured rates before the room resolved: **29.96 cycles/second**
  (VM + staging, no render, no sprites) and **59.92** once the room check short-circuited.
  ★★★ **Neither is AC-5**: no picture is rendered, no sprite is composited, and the VM has no
  halt detection, so a stalled VM would report a good rate. ★★ **Reporting either as "the budget"
  would repeat exactly the 1.93 cyc/s mistake** (§3.2 item 2).

- **AC-6 [class: state-comparable]** ★★★ **NOT ACHIEVED** — no per-cycle diff against
  `tools/agivm/` was run with the renderer and compositor live.

- **AC-7 [class: state-comparable]** ★★ **PASS on what could be measured.** `remaps total 2 =
  2 per cycle in which a draw phase is entered` — **exactly the pair, never per scanline.** Slot 5
  priority, slot 6 framebuffer/volume; slots 0–4 and 7 resident. ★ The phases stayed disjoint in
  every run. ★★ **Caveat: §3.1 means the draw phase cannot be the phase the map describes**, so
  this measures the mechanism, not a working render.

- **AC-8 [class: byte-comparable]** ★★★ **NOT ACHIEVED** — no injected fault on this corpus.
  ★ Per L-62 I am not claiming any other build's fault result transfers.

- **AC-9 [class: state-comparable]** ★★★★ **PASS — six defects, §3.2.** ★ P3b.1 found 33
  undefined symbols and three subsystems that were fragments [AD-80]; this found six more, all
  in the seam between correct parts.

- **AC-10 [class: eye-gated]** ★★★ **NOT PRODUCED.** Nothing renders correctly, so there is
  nothing to show. **25.3: N/A, not "pending Jay"** — a blocked AC must not be dressed as a
  queued one.

- **AC-11 [class: suite]** ★ **`None.`** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

```
  packed P3b code 12,651 B -> draw phase 60,058 vs 65,280, spare 5,222   [AC-2, before building]
  glue build 13,048 B; reservation 3,328 (floor 3,072)
```

```
  FB_BASE  $C000 + 26,879 = $128FF -> wraps to $28FF     [MAP_CODE is $2000-$5300]
  PRI_BASE $A000 + 13,439 = $0D47F -> $D47F
  map gives each phase slot 8,192 B; the planes need 26,880 and 13,440 FLAT
```

```
★★★ STUCK in cycle 1 -- most-visited PCs:
     $0102  x194        <- the seed stack, executed
     $43A1              <- inside put_pixel
     S=$07E9            <- stack HEALTHY: not the collision I first hypothesised
     room 83  sprites 0  err 0  remaps 2
```

```
  boot localisation: marker $A2 (reached `lds`, never reached the instruction after
  `jsr HAL_sys_init`) -> MMU slot exposure; fixed by pre-setting $FFA0..$FFA7
  boot test at $2000, 752 bytes:      PC parks $2010, GO=0   -- the org is innocent
  boot test + subsystems, 12,573 B:   runaway                -- the size/slot is not
```

```
=== AC-2 SUMMARY ===  nine titles all PASS      [after res_cache_stash's backward copy]
byte-identical resources: 1264 across 10 sweeps, all clean
cels byte-identical to the oracle: 6782 / 6782
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; `p3b_probe_pk.bin` is a harness probe.

**25.3 operator-runtime-smoke:** **N/A** — nothing reached the screen (AC-10).

---

### 6 — Reactive deviations and route accounting

1. ★★★ **Renderer and compositing gates not re-run.** `pic_core.s` gained a label and nothing
   else; `pic_probe.bin` is byte-identical, so they cannot have moved. **Stated as an argument,
   not a measurement** — they are owed.
2. ★★ **`MAP_RESERVED_MIN` added** — implementing T-P0-036 §8.4's recommendation, not new scope.
3. ★★ **A fourth reservation reduction was taken and reversed** (§3.4).
4. ★ **Three diagnostic files added** (`p3b_run.lua`, `p3b_where.lua`, `p3b_boot_test.s`). The
   boot test is a bisection fixture and is worth keeping.

**ROUTE ACCOUNTING.** ★★ **What I did NOT do:** did not relay the map for flat planes (§3.1 — a
design change, and the reason this stops); did not render a room, hash a framebuffer, diff
per-cycle state, inject a fault, or produce an image; did not add halt detection to the guest;
did not touch the parser, sound, storage or `LOADER.BIN`.

---

### 7 — Uncertainty flags

1. ★★★★ **§3.1 is the blocker and it reopens the map, not the probe.** Both planes flat is
   **40,320 bytes** against slots 5+6's 16,384 — the draw phase needs four slots.
   **AC-2's arithmetic cannot detect this and passed throughout.**
2. ★★★★ **The AC-5 figures in §4 are NOT the budget** and must not be cited as one. No render, no
   sprites, and no halt detection.
3. ★★★ **The VM has no halt detection in this probe.** A halted VM is currently indistinguishable
   from a fast one, which is the shape of two defects already found this task.
4. ★★★ **`res_cache_stash`'s overlap bug shipped in T-P0-036 and every gate passed.** It is fixed,
   but **the class — a defect whose presence depends on a caller's arena size — is not covered by
   any gate**, and the VM gate's arena is the only one exercised.
5. ★★ **Fix 4 (slot 5 restore) is patched in the harness**, not in `mmu_phase.s`. The engine needs
   a `ph_blk_obj` and a `phase_vm` that restores it.
6. ★★ **`CP_CEL` is `MAP_RESERVED` ($5300) and a decoded cel can reach 4,784 bytes** → `$66B0`,
   which runs into `MAP_ARENA_WIN` ($6000). Not yet reached, and wrong.
7. ★ **Pool push still failing on auth** — eighth task. Eighteen rows local only.

---

### 8 — Follow-up candidates

1. ★★★★ **Decide the plane addressing.** Either give the draw phase four contiguous slots for
   flat planes, or make `put_pixel`/`co_rowset` slice-aware — **which T-P0-034 §3.3 already
   measured as remap-per-pixel in the fill's arbitrary walk order.** This is the next dispatch.
2. ★★★ **Fix `mmu_phase.s`**: `ph_blk_obj` plus a `phase_vm` that restores slot 5, and an
   allocator that actually fills `ph_blk_pri`/`ph_blk_fb`.
3. ★★★ **Add halt detection to the P3b probe** once the code region allows — AC-5 cannot be
   trusted without it.
4. ★★ **Move `CP_CEL`** out of the reservation (§7.6).
5. ★★ **Re-run the renderer and compositing gates** (§6.1).
6. ★ **AD-77** remains open and out of scope.

---

### 9 — User interaction during task

★★ Jay interrupted twice. First **"check" / "check progress"** — I gave a status summary
mid-task. Then, after I offered to stop or continue, **"keep going, i want you to limit your tool
runs to 30 secs unless you have a valid reason to go longer"**.

★ The second is a standing working preference and is recorded to memory. ★★ It changed how the
rest of the task ran: MAME diagnostic runs went from `-seconds_to_run 600` to 30–60 with a
watchdog that reports a hang early, which is what made the six defects tractable one at a time
rather than one 10-minute run at a time.

---

### 10 — Candidate(s) captured this task

`None.` ★★ Two rows are clearly earned — a size-dependent latent bug invisible to every gate
(§3.3), and a fits-check that measures sizes while the real constraint is addressability (§3.1).
★★★ **They are not written because the pool has been unpushable for eight tasks** and adding two
more local-only rows to eighteen is bookkeeping, not capture. ★ They are recorded here in §3 and
§7 so nothing is lost, and should be written once the remote is reachable.

---

### 11 — Commit

`<filled at commit>` (pushed to origin/wip before this report)
