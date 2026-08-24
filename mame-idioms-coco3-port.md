> ## ★★ INHERITED — UNVERIFIED FOR AGI (coco_agi banner, added at P0.1, 2026-08-23)
>
> **This file arrived in `coco_agi` as a byte-for-byte copy of POP3_port's
> `mame-idioms-coco3-port.md` at POP `wip` `282a65c` (SHA-1 `3c862de2…`), which is itself
> Karateka-derived.** It is carried over under CLAUDE.md §2G and is a **mandatory read point**
> under §2A — but **nothing below has been re-verified against an AGI build, because none
> exists yet.**
>
> **What transfers and what does not:**
>
> - **The MACHINE idioms transfer.** MAME debugger syntax, `bpset`/`wpset`/tap forms, the
>   `execution_state="run"` headless requirement, the frame-notifier GC gotcha, `-seconds_to_run`
>   being emulated seconds, Windows paths needing forward slashes in Lua, `disk11.rom` being
>   required for `LOADM`, and DMK/SDF being read-only in MAME's floppy layer (§2A.3) are
>   properties of MAME and the `coco3` driver. They hold here unchanged.
> - ★★ **The CONTENT constants do NOT transfer, and the colour depth is the trap.** **AGI is
>   16-colour; POP and Karateka are both 4-colour** (CLAUDE.md §2G). Every prod SHA-1, binary
>   size, screen geometry, framebuffer word count, mode-register value and palette entry below
>   describes a 4-colour port. **Confirm each constant for AGI before relying on it** — reuse the
>   mechanism, never the number.
> - ★ **POP's `mame-idioms-apple2e-oracle.md` is deliberately NOT carried over** (§2A). AGI's
>   oracle is ScummVM on the host, not a second machine under emulation. **There is no second
>   emulated target in this project.**
>
> **Additions made for AGI must be marked as AGI-verified when they are made** (§2A.4), so that a
> later reader can tell an inherited assertion from a measured one. Until then, treat every
> unmarked entry as `[no-ref: inherited from POP — unverified for AGI]` per CLAUDE.md §2.2.

# MAME idioms & quirks — CoCo3 target (the Karateka port)

**Purpose:** a standing, self-contained reference so instrumentation and boot quirks on the
`coco3` target (the `karateka-coco3` port) are **looked up, not rediscovered each dispatch.**
Every entry is traced to the pass that established it and, where one exists, to the **tool**
that exercises it and the **exact command/Lua syntax** that works. Read this before
instrumenting or booting the port under MAME.

**Target:** `mame coco3`, 6809 CPU, ~0.89 MHz slow / ~1.78 MHz double-speed, GIME video +
MMU, WD1773 FDC on a 5.25″ floppy. **Prod baseline (never mutate under a read pass):**
`karateka.bin` SHA-1 `88eba89b15cdf17c8d25e082d2d3e1f3cce57d38`, 17978 B. **Co-equal target:**
a MAME **failure** on coco3 is a **shipping bug** (C-11 / I-BOTH), not deferrable to hardware
— but a MAME **success** on a hardware-edge question is **not** a hardware guarantee (§7).

> This file **incorporates** the earlier `mame-idioms-addendum.md` item A (GIME register
> ordering) and D (pixel-colour provenance), plus the cross-cutting debugger/Lua mechanics,
> tap-GC gotcha, and live-gate flags shared with the apple2e oracle.

---

## 0. Measuring the port's per-frame COST: no Lua cycle counter — count **VBLs via frame_number**
**MAME 0.281's Lua device wrapper exposes neither `cpu.clock` nor `cpu:total_cycles()`** (both
`nil` — probed, `build/logs/b2_probe.txt`), and **`manager.machine.time` is quantised to the
scheduler timeslice**, so an intra-frame `machine.time` delta around a routine reads as ~4 cycles
and is **useless for cost** (it looks like the work is free). `scr:frame_number()` **is** exact.
So: **measure cost in VBL units** — read-tap each routine's entry address (6809 read-taps fire on
opcode fetch, §10) and diff `frame_number` between marks. 1 VBL = the entire per-frame budget, so
"this routine costs 5 frame-deltas" is already the verdict; convert with
**VBL = 29,859 cycles** (coco3 maincpu 894,886 Hz from `mame -listxml coco3`, **×2** because
`HAL_gfx_init` writes `$FFD9` SAM double-speed, `src/hal/coco3-dsk/gfx.s:198`; ÷59.94 Hz).
- **A whole-frame overrun is also directly visible**: tap the frame loop's `HAL_time_vbl_wait`
  entry and diff `frame_number` per iteration — 1 = fits, ≥2 = the frame missed its VBL. This is
  the cheapest go/no-go and needs no cycle counting at all.
- **⚠ ARM the taps after the `.bin` is loaded.** Driver routines living in low RAM (`$02xx-$04xx`)
  are addresses **DECB/BASIC itself executes** during boot (§5 overlap), so unarmed taps fire at
  ~f22 and a "first hit only" rule burns on BASIC, not the driver — it reads as the routine running
  impossibly early. Gate every tap on an `armed` flag set when PC is set to the driver's entry.
Tools: `harness/tools/stageb2_budget.lua` (frame-loop overrun), `stageb2_initcost.lua`
(per-routine VBL cost + blits/frame). *Established:* Stage-B2 §0 VBL-budget gate 2026-07-20.
*Candidate:* `measure-cost-in-vbls-when-the-emulator-exposes-no-cycle-counter`.

### 0a. The VBL spin-wait IS a cycle counter — how to verify the live CPU CLOCK by execution
MAME exposes **no clock accessor either** (`cpu.clock` / `configured_clock` / `unscaled_clock` /
`clock_scale` all nil — `build/logs/clk_probe.txt`), so "are we at 0.89 or 1.78 MHz?" must be
answered **behaviourally**. `HAL_time_vbl_wait` spins in a 2-instruction loop
(`cmpb <hal_frame_lo` = 4 cyc + `beq` taken = 3 cyc = **7 cycles/iteration**), burning every cycle
the engine is *not* working. Read-tap `hal_vbl_spin` and count hits per frame:
`spins*7 = idle cycles`, so **`spins*7` is a hard LOWER BOUND on the frame's cycle budget** — and a
bound is often all you need: measuring **29,736** cycles inside one frame *disproves* 0.89 MHz
outright, because that window only holds 14,929.
- **A/B/A control makes it conclusive and self-calibrating:** poke `$FFD8` (SAM speed LO) from Lua
  mid-run, then `$FFD9` (HI) to restore. Work per frame is unchanged, so with phase-matched samples
  `total_fast = 14*(spins_fast - spins_slow)` — no datasheet trust and no absolute-clock assumption.
  Measured: 1.76–1.79 MHz across 13 phases; forced-slow segment capped at 14,805 ≈ the 0.89 MHz
  window (0.8%), confirming MAME models the bit and the engine runs the doubled clock.
- **⚠ Phase-matching breaks where the work differs between segments** (a phase state-machine
  advances at different points when the clock changes) — those phases yield nonsense (0.007 MHz);
  use the assumption-free `max(spins)*7` bound as the primary, the differential as corroboration.
Tool: `harness/tools/verify_cpu_speed.lua`. *Established:* CPU-speed verification 2026-07-20 —
the engine's ONLY speed write is `HAL_gfx_init`'s `$FFD9` at `pc=$1E9B` (boot-time, not per-scene).
*Candidate:* `a-spin-wait-loop-is-a-free-cycle-counter-for-clock-verification`.

---

## 1. The load-bearing one: **the CoCo3 has NO autoboot**
Inserting a disk **runs nothing.** There is no autoboot. The entry point is **Disk BASIC
(DECB)** — you reach the game by having DECB `LOADM` + `EXEC` the binary (or an equivalent
boot front-end). **Do not expect `-flop1 <disk>` to boot the game** — it mounts the disk;
DECB is the ROM running, and it does nothing until told. The boot path is DECB, whose live
low-RAM and IRQ-vector usage **overlap the game's load region** (§5). *Candidate:*
`coco3-has-no-autoboot-entry-is-DECB`. *Established:* disk-boot / DECB-overlap arc.

---

## 2. **Autoboot script ↔ interactive input are mutually exclusive** — use `natkeyboard:post`
MAME's `-autoboot_script` and interactive input don't coexist cleanly here. To drive DECB
(type `LOADM"…"` / `EXEC`) under automation, **post keystrokes to the natural keyboard**:
```lua
manager.machine.natkeyboard:post('LOADM"PROG"\r')   -- note the trailing \r (ENTER)
manager.machine.natkeyboard:post('EXEC\r')
```
Drive it **after boot settles** (~frame 240). The documented method: `disk11.rom` (Disk BASIC
ROM) + `imgtool` (build the image) + `mame coco3` + `natkeyboard:post`, working around the
autoboot mutual-exclusion. *Candidate:*
`mame-autoboot-and-interactive-are-mutually-exclusive-use-natkeyboard-post`. *Established:*
disk-boot / DECB-overlap verdict (AC-4 reachability).

---

## 3. Disk images: **`imgtool`**, `.dsk` vs DMK, and **MAME can't write DMK/SDF back**
- **`imgtool`** builds coco3 disk images for MAME. **A `.dsk` is always 18 sectors/track** —
  no native short-track fixture; a short-count / worst-case track points at **DMK** (or JVC).
- **JVC createopts came back empty; DMK is the format for track-geometry control** (DMK
  createopts unchecked at last note — verify before relying). Boot images are
  **whole-track-aligned** in our `.dsk` layout (keeps raw game tracks contiguous).
- **`.dsk` fixtures are gitignored / throwaway** — a shared fixture once broke an AC (3b-1);
  **generate per-task, don't share.**
- **MAME write-back is format-limited (a real gotcha).** **DMK and SDF are READ-ONLY** in
  MAME's floppy layer (`floptool` shows `dmk r-`, `sdf r-`) — a guest that formats a mounted
  `.dmk` runs fine but the file is **byte-unchanged on exit**. Only `jvc` and `coco_rawdsk`
  save back, and JVC is a **logical** image (discards physical sector order). So you **cannot
  image a guest-formatted disk to inspect its interleave**, and MAME Lua exposes no floppy
  track-data accessor.
  - **Workaround — in-session CPU hijack (§10 proxy pattern):** boot the guest, let it format
    in the in-memory floppy, then from Lua load a standalone read harness and time a read of
    the just-formatted disk (no write-back needed). **Validate the hijack with a control**
    (read a known-good pristine disk the same way; it must reproduce the normal time). Detect
    guest-op completion by watching FDC command writes (`$FF48`) for an idle gap.

*Candidates:* `dsk-is-always-18-sectors-use-DMK-for-short-tracks`,
`mame-dmk-writeback-hijack-proxy`. *Established:* BUILD #3b passes + the DECB-BACKUP refutation.

---

## 4. **Track-17 is the DECB directory** — mid-disk, do not overwrite
The DECB directory lives on **track 17, mid-disk.** A raw game-track span crossing track 17 is
**silent corruption** (bootloader reads directory as game data, or the raw layer overwrites
the directory). **Keep the raw game track range clear of track 17** (or account for it
explicitly); reserved raw tracks must stay **contiguous and clear of 17**, and DECB must
**tolerate the reservation** (it can flag reserved tracks as an inconsistency if done wrong).
*Candidate:* `decb-directory-is-track-17-keep-raw-tracks-clear`. *Established:* BUILD #3b-3.

---

## 5. The disk-boot overlap: **DECB `LOADM` overwrites `$010C`** (M1) — confirmed mechanism
When DECB `LOADM`s the binary, segment-1 lands on DECB's regions — specifically **M1: the
`$010C` IRQ-vector overwrite** (hang at `$C60F` in the trace). `$0100-$01FF` is **contested
during LOADM** — the M1 watchpoint on it pinpointed the overlap. The fix (a separate gated
task, M4): a bootable `.dsk` + a loader that avoids the overlap; the raw-underlayer approach
chains through this. **M2** (a second overlap hypothesis) was **unreachable/unproven** in the
trace — flagged, not smoothed over. *Candidate:* `decb-loadm-overwrites-010C-irq-vector`.
*Established:* disk-boot / DECB-overlap verdict (M1 confirmed by trace).

---

## 6. **The WD1773 FDC** — the CoCo3 disk-controller programming model
- **Four memory-mapped registers** in the `$FF4x` area (command/status, track, sector, data;
  command/status at **`$FF48`**) — confirm base/order against **DECB Unravelled** (register
  base/order is the F1 risk if assumed).
- **DECB assumes slow; it does not FORCE slow**, and **does not use HALT for double-density.**
  The absence of a `$FFD8` (slow-speed poke) in the disk path is the evidence — "assumes
  slow" ≠ "forces slow."
- **Capture the density / motor / settle sequence** (addresses, latch bits, DECB's
  motor/settle/density order) when tracing disk I/O.

*Candidate:* `decb-assumes-slow-does-not-force-slow`. *Established:* FDC read-primitive recon +
DECB speed passes.

---

## 7. What MAME **cannot** answer here — do not over-trust the emulator
MAME shows *behaviour*; only real hardware / a faithful timing model settles some questions.
Flag these **MAME-can't-confirm**; don't launder a clean run into "verified":
- **Fast-speed FDC survival** at ~1.78 MHz — doc-supported-**unsafe** (Lomont fast-speed ROM
  failure; MFM DD polling fails at 0.89 MHz empirically) but the **edge is not
  MAME-authoritative** → real silicon.
- **HALT + NMI-completion timing** — if the fix depends on HALT-enable / NMI-completion and
  there's no INTRQ path, it may be **UN-TESTABLE in MAME**; report as such (may still be
  correct, just not MAME-provable).
- **Seek-Error reliance / FDC edge fidelity** → real silicon.
- **GIME MMU 128K range conflict** — MAME does **not** resolve the doc-vs-hardware MMU-range
  question; tracked as a 25.3-H(divergence) item, not closed by a clean run.

**Rule:** a MAME **failure** on a co-equal target is a real bug (C-11); a MAME **success** on
a hardware-edge question (fast-speed FDC / HALT timing / MMU range) is **not** a hardware
guarantee — hold it as `inferred`, gate to silicon. *Candidate:*
`mame-success-on-a-hardware-edge-question-is-not-a-hardware-guarantee`. *Established:*
DD-slow-speed feasibility, DECB fast-speed viability, GIME-MMU recheck.

---

## 8. Speed control: **force-slow → do-I/O → restore-speed** wrapper
Where slow speed is needed for disk I/O, poke the speed down, do the transfer, restore.
`$FFD8`/`$FFD9` are the speed pokes (slow/fast). The **boot primitive itself doesn't need it**;
the wrapper is owned at the I/O-caller layer. DECB assumes slow but won't protect you at fast
speed (§6) — a missing `$FFD8` in a disk path means "assumes slow," not "forces slow."
*Established:* DD-at-slow-speed feasibility + FDC viability follow-up.

---

## 9. **GIME register write ORDER: palette must be written AFTER video mode** (addendum A)
A real hardware/emulator behaviour, not a style preference: **palette register writes
(`$FFB0-$FFB3`) do not latch correctly until the GIME's video mode is already set.** Writing
palette **before** `$FF98`/`$FF99` leaves the mid-range indices **not rendering** — only the
extremes ($00 black / $3F white) survive; indices 1/2 (orange, blue/cyan) come out wrong or
absent. **Symptom:** a four-band palette test shows only 2 bands; Brøderbund logos render
without orange/blue.

**The required order** (addresses confirmed present in *Karateka's* `src/` — **POP: confirm each GIME address
against POP's own display-init code on first use; POP's `src/` does not yet contain these**):
1. **`$FF90`** (CoCo3 mode) **first** — the `$8000+` framebuffer needs CoCo3 mode for CPU
   access.
2. clear buffers.
3. GIME mode/offset/SAM setup: **`$FF98`/`$FF99`** (video mode + resolution), **`$FF9D`/
   `$FF9E`** (offset), **`$FF9C`**, **`$FF9F`**, **`$FFD9`**, **`$FFDF`**.
4. **palette `$FFB0-$FFB3` LAST.**

Empirical (GFXMODE3.ASM + Jay: "the GIME needs to be completely initialized before palette
values are written"), **not** Sockmaster-documented. Cost of not knowing it: the P2.3a
display-init arc burned multiple followups (followup-2 NOT CONFIRMED, chasing palette
*values* when the cause was *ordering*) before the reorder fixed it. *Candidate:*
`gime-palette-writes-must-follow-video-mode-set`. *Established:* P2.3a.6 followup-3 (the
reorder). Tool (Karateka's — **POP `harness/tools/` is an empty skeleton; these do not exist in POP yet**):
`harness/tools/palette_derive.py` (index derivation), `harness/tools/decode_framebuffer.py` (framebuffer
verify). The GIME write-order constraint itself is CoCo3 hardware behaviour and transfers to POP unchanged; it
is only the tooling and the confirmed-addresses that are Karateka-specific.

---

## 9a. **OPAQUE blit + a sub-byte shift writes the shifted-in edge zeros as BLACK bars**
`HAL_gfx_blit_sprite_opaque` stores **every** pixel of the sprite's byte span. When the sprite is
placed with `blit_subbyte > 0`, the sub-byte shift brings **zeros (index-0 black) into the leading/
trailing edge pixels** of the partial edge bytes — and opaque mode writes them, so each shifted
sprite shows a **thin black vertical bar at its left and right edge** (a transparent blit keys these
out, so the bug only appears with opaque). **Symptom:** a stack of opaque backdrop sprites shows
1-2px black bars at every sub-byte-shifted sprite's edges (scene-6 Fuji: A9B8 sub1 + A948 sub2 →
4 bars at X144-145 / X174-175). **Fix (backdrop):** **byte-align** the sprites (`blit_subbyte = 0`);
the ≤3px position loss is negligible for a static backdrop and the shifted-in zeros disappear. (For
sub-pixel-critical actors, pad the cel's edge with the sky index or use a masked/transparent blit
instead.) *Established:* scene-6 Stage-1 Fuji backdrop gate. Tool: `harness/tools/scene6_stage1_confirm.lua`
+ a per-column black-count framebuffer scan.

## 9b. **Index-0 is overloaded (transparent-pad vs meaningful-black) — flood-fill to separate them**
The Apple→CoCo3 converter emits index-0 (black) for BOTH the sprite's meaningful black AND the
transparent bounding-box padding/edges, so a single opaque/transparent blit flag can't render both
right (opaque → padding shows as black boxes/bars; transparent → the real black shows sky). Separate
them by **flood-fill from the cel border through {index-0, index-2(sky-blue)}**: black *reached* from
the border is edge/outline (choose per the art); black *walled off by index-3 white* is interior. On
scene-6's Fuji, Jay's ruling was **edge-connected black = OPAQUE** (mountain outline), **white-
surrounded interior black = TRANSPARENT** (sky-holes → convert to blue), plus **fully-black columns =
trim-boundary artifact → blue**. Tool: `harness/tools/floodfill_bg_sky.py`. *Established:* scene-6
Stage-1 Fuji cel-data fix.

## 10. Instrumentation — **6809 read-taps WORK** (the key cross-target asymmetry) + shared Lua
- **On 6809, program-space read-taps DO fire** — unlike the 6502 oracle side, where opcode
  fetches bypass them. So the single most important cross-target difference: **on coco3 you
  can read-tap an execution address directly; on apple2e you can't** (use a bp / write-tap /
  watch-the-result there). *Candidate:* `6809-read-taps-work-6502-read-taps-dont`.
- **`screen.refresh_attoseconds` is a PROPERTY, not a method** (P3.101, cross-cutting — the
  apple2e side is identical). Written as `scr:refresh_attoseconds()` the script dies at load
  with `attempt to call a number value (method 'refresh_attoseconds')` and MAME reports only
  `Fatal error: Error running autoboot script … runtime error`, so the tool looks broken rather
  than mistyped. Use `local HZ = 1.0e18 / scr.refresh_attoseconds`. **Take the rate from the
  machine, never a literal 60:** coco3 is **59.922748 Hz** and apple2e is **60.000000 Hz**, so
  a frame is 16.688 ms on one and 16.667 ms on the other — comparing two machines' frame
  COUNTS without either machine's frame RATE is the same class of error as comparing a 7 px
  column against a 4 px one.
- **A write tap on shared scratch reads whoever wrote it last, not the object you care about**
  (P3.101). `bc_lead`/`bc_keep` are one clip window reused by every character's every pass, so
  a tap on them attributed to "the vizier's draw" actually returns whichever draw ran most
  recently — it came back pinned at 6 while the column ran 43→128 and could not settle the
  question it was installed for. Where the engine has one scratch and many users, the tap has
  to be gated on the user (`ch_idx` **and** `ch_cp`), not merely sampled near it.
- **Sampling order inside a routine matters as much as the address** (P3.101, third instance in
  three dispatches). `co_setup` stores `ch_dest` and computes the clip window *afterwards*, so
  a tap on the `ch_dest` write reads the PREVIOUS draw's window. Same family as P3.99's
  `ch_dest`-at-the-`cad_idx`-tick (stale) and P3.100's tap on `ch_dest` alone (high byte only).
  **Check where in the routine the value you want is written relative to the one you tapped.**
- **Tap-GC gotcha (cross-cutting, applies here too):** `install_read_tap`/`install_write_tap`
  and `emu.add_machine_frame_notifier` return an object you **must keep referenced** (`_G._tap
  = …`, `_G._n = …`) or it is garbage-collected and **silently stops firing** (empty log =
  false "never happens"). Taps work **headless** (no `-debug`).
- **The debugger/Lua toolkit is MAME-general** (same as apple2e §4) and useful on coco3 for
  boot-time watchpoints and forcing:
  ```lua
  pcall(function() manager.machine.debugger.execution_state="run" end)  -- unpause headless -debug (else HANGS)
  local cpu = manager.machine.devices[":maincpu"]
  cpu.debug:wpset(cpu.spaces["program"], "w", 0x010C, 2, nil, 'tracelog "M1 pc=%04X",pc; go')  -- catch the $010C overwrite
  cpu.debug:bpset(0xADDR, nil, 'pb@0xZP=0xNN; go')     -- force a value at a read
  manager.machine.debugger:command("trace C:/…/out.tr,0")   -- run any debugger cmd from Lua
  ```
  **Syntax:** registers `a b d x y u s pc cc dp` (6809 set); byte read `b@0xADDR`; poke
  `pb@0xADDR=v`; **bp-action `tracelog` is brace-FREE** (`tracelog "…",pc; go`), **trace-command
  action is BRACED** (`{tracelog "…",pc}`) — mixing fails silently. Debugger `printf` is **NOT
  captured headless** — use `tracelog` into an open trace. Write Lua output via `io.open`, not
  `print()` (console not captured).

*Established:* cross-target instrumentation note + the M1 `$010C` watchpoint + the shared
debugger toolkit from the `$6540` pass (commit `634e0c3`).

### 10a. A read-tap hit is **NOT** proof of execution — compare **PC against the tapped address**
§10 says 6809 read-taps fire on opcode fetch, and they do. What it does not say is that they
fire on **data and dummy reads of the same address too**, so *counting tap hits is not counting
calls.* Measured on `blit_cel` (P3.43): with its only caller NOPped out, the tap still logged
**0.23 hits/iteration** — which reads as "the routine still runs" and is wrong.
- **The discriminator is the PC at the moment of the hit** (`cpu.state["PC"].value`, wrap in
  `pcall` — the accessor is not guaranteed across builds):
  - **`PC == addr`** → the byte was read but **not executed as an opcode** (data/dummy read).
  - **`PC == addr + 1`** → the opcode was fetched and the PC advanced: **a real execution.**
  Both were observed on the *same* address in the *same* session, which is what makes this a
  discriminator rather than a theory: ablated run → `PC=$391B`, live run → `PC=$391C`.
- **⚠ The inflation is not uniform, so a ratio will not save you.** In the same run `blit_save`
  tapped at exactly `2.00`/iteration (true) while `blit_erase` tapped at `4.01` for **two** real
  calls — one primitive doubled, its neighbour did not. There is no constant to divide out.
- **So: gate an ablation on the ENTRY COUNT of the routine you ablated, not on a downstream
  primitive.** Entry taps on `chars_frame` / `flicker` came out as clean `1.00` / `0.00` per
  iteration and were unambiguous; the primitive counts were not. Keying on a shared primitive
  additionally forces an argument about *which caller* reaches it — the character path and the
  flame path both reach `blit_cel` — and that argument is an assumption, not evidence.
- **Corollary for cost work:** a difference between two runs is only a component cost if the
  ablation is independently confirmed. Report it as UNCONFIRMED otherwise — a subtraction
  between two runs that did the same work is noise with a plausible magnitude.
Tools: `harness/tools/frame_baseline.lua` (the PC diagnostic + entry-count gates),
`harness/tools/frame_baseline_report.py` (refuses to print an unconfirmed component).
*Established:* P3.43 frame re-baseline. *Candidate:*
`a-tap-hit-is-not-an-execution-check-the-pc`.

---

## 11. Visual authority is **Jay's live MAME**, never a Clyde snapshot
Every colour / position / on-screen claim is **Jay's** to gate off a live coco3 MAME run. The
CoCo3 side is **palette-based** (GIME explicit palette) — once colour is fixed on the Apple
read side, the CoCo3 index is baked correctly and there is nothing to re-check at render time;
but **whether it reads right on-screen is still Jay's eye**, and 25.3 is his MAME observation.
A `wpset` PC-confirm shows *code ran*, not *what it looks like*.

**Pixel-colour provenance (addendum D — applies to any capture file):** filename labels
("TRUE"/"reference"/"ground truth") establish nothing; **content + creation method +
timestamp** do. MAME's rendered palette ≠ the conversion tool's constants (MAME blue ≈
`(25,144,255)` vs tool `(0,0,255)`). **These specific constants and the `palette_derive.py` they were
confirmed in are Karateka-measured — POP must re-measure MAME's palette against POP's own tooling before
relying on the exact values; POP's `harness/tools/` is empty.** The *principle* — a "ground truth" file whose
pixels carry the tool constant rather than MAME's rendered colour is a tool render, not a capture — transfers
to POP unchanged and reinforces CLAUDE.md §3 (visual authority is Jay's; never interpret PNG pixels). **Automated-check tautology:**
"N/N pixels match the rule" is tautological if the rule generated the predictions — validate
against independently-grounded pixels. *Candidates:*
`tool-render-is-not-a-mame-capture-verify-by-pixel-colour`,
`automated-check-tautology-validate-against-ground-truth-not-rule-predictions`. *Established:*
standing; Content Wave 1 (commit `0b5825b`).

**`-nothrottle` snapshots lie for motion (cross-cutting, mirrored from the apple2e file §6).**
`-nothrottle` is fine for **traces** (full trace fast), but a `-nothrottle` **still-frame
snapshot manufactures phantom motion artifacts** — a mid-frame no-throttle grab ≠ the live
rendered frame. So a coco3 snapshot tool (`gate1_snap.lua` / `comp_snap.lua`, §13) is **not a
live gate**, and colour/position from a snapshot is not authoritative regardless — the on-screen
truth is Jay's live MAME (above). *Established:* the nothrottle/motion caveat +
`nothrottle-snapshots-unreliable-trust-live-gate`.

**Live-gate viewing flags (Jay's preference — viewing-only, no cadence change):**
```
mame coco3 -rompath C:\mame\roms -window -prescale 3 -resolution 1920x1152 -speed 8 \
     -autoboot_script tools\<gate>_live.lua
```
`-speed 8` (fast-watch; `-speed 16`/`-nothrottle` for max), `-prescale 3 -resolution
1920x1152` (3× window, size only). The `*_live.lua` loads the boot-excluded `.bin` and sets
PC. *Established:* `mame-live-gate-viewing-flags`.

### 11a. Prove a behavior-preserving RENDER refactor with a FRAMEBUFFER DIFF (not a re-gate)
For a "changed the code, not the output" refactor (extract a shared draw module, de-dup, reorganize
includes), the objective proof is a **framebuffer byte-diff**, not Jay's eye: dump **Frame A
`$8000-$BBFF`** (15360 B) at the driver's **hold PC** BEFORE the change, refactor, rebuild, dump
AFTER, `cmp` — require **byte-identical** for every affected driver. The pixel diff catches a
sub-visual one-pixel/one-colour drift the eye misses, is instant/repeatable, and doesn't spend a
human gate cycle (the live gate is for NEW visual behaviour). Pair with a single-source `grep` to
prove the structural goal (no duplicated routines remain). Dump via the same DECB-load Lua as the
`*_live`/`*_confirm` scripts, then `for a=0x8000,0xBBFF do o:write(string.char(mem:read_u8(a))) end`.
*Candidate:* `prove-a-render-refactor-with-a-framebuffer-diff-not-a-visual-re-gate`. *Established:*
scene-6 backdrop shared-include refactor (commit `7bfb24c`; both drivers pixel-identical pre/post).
Tool: `harness/tools/*` DECB-load pattern + a Frame-A dump.

### 11b. Render PNGs at NATIVE 1:1 square pixels — MAME `screen:snapshot()` STRETCHES
For oracle-vs-port **by-eye** matching, a MAME `screen:snapshot()` is NOT square-pixel: **apple2e
snaps are 560×192** — each logical HGR dot is rendered as **2 horizontal pixels** (280 logical → 560;
~97% of even-column pairs are identical, differing only at NTSC colour fringes), so at 1:1 the image
is ~2.9:1, badly horizontally stretched vs the real ~4:3 display. Precise visual matching is
impossible against a stretched render. **Fix (standing):** emit native-resolution 1:1 square-pixel
PNGs — **apple2e: halve the 560 width → 280×192** (NEAREST, keep the left of each pair; box-resize
blends the fringe); **coco3: decode the raw `$8000-$BBFF` framebuffer (2bpp MSB-first, 80 B/row) →
320×192** directly (already square, no MAME snapshot involved). Optionally **uniform integer upscale**
(×N NEAREST) for visibility — never fractional. Pixel-aspect is 1:1 **logical** (not 4:3 hardware-
corrected); use the SAME convention for both targets so an apple2e px X lines up with coco3 px X+20
(the port's +20 centering of 280-in-320). *Candidate:*
`render-native-square-pixel-pngs-mame-snapshot-stretches-apple2e-560-is-280-doubled`. *Established:*
wall-top reference capture 2026-07-14 (commit TBD). Tool: `harness/tools/render_square.py`
(`--apple2e <560png>` / `--coco3 <15360 dump>` / `--scale N`); pairs with `fbdump_stage.lua`.

### 11c. Render a cel PREVIEW in the REAL palette + a NON-palette transparency mark (decode the mask)
A sprite preview must use the **actual 4-index scene palette** the cel will ship in (0 blk / 1 orange
/ 2 blue / 3 white — MAME-authoritative RGB), and show **transparency in a colour that CANNOT occur
in that palette** (a **gray checkerboard**), with the convention **stated** in the image/report. Two
traps this avoids, both real defects on this project: (1) a **debug placeholder colour** (magenta)
reads as "the art is wrong" when it's a render artifact — Jay's gate flagged a magenta sheet whose
composite (same bytes) looked correct; the tell that it's the render not the art is *same source,
different output*. (2) The **index-0 collision**: opaque-black (`b`) and transparent (`t`) BOTH pack
to colour index 0 — distinguished ONLY by the mask plane. So a preview must **decode the MASK** (mask
00 → transparent-checker, 11 → `PALETTE[colour]`), not the colour index — ignore the mask and `t`
looks like whatever bg (blue), or a wrong flag paints it magenta. **Render FROM the packed
color+mask bytes** (and assert the decode matches the authored grid) so the preview is faithful to
what ships AND validates the packing. Emit **1:1 AND integer-NEAREST magnified** (factor stated).
*Candidate:* `render-cel-preview-in-real-palette-decode-the-mask-checkerboard-transparency-not-a-debug-colour`.
*Established:* wall post/rail preview fix 2026-07-15 (2nd preview defect after the 560-stretch).
Tool: `harness/tools/gen_wall_post_rail.py` (`render_from_planes`).
**Refinement (2026-07-16, HS-10):** DEFAULT the transparent background to the **real sky (index 2)** —
it shows the cel as it will actually appear (why the composite read right). Use the checkerboard
**only** when the cel's own palette **includes** the bg index (then sky is ambiguous). Post/rail
palette is {w=3,b=0} with no blue → sky default is unambiguous. `--bg sky|checker` (default sky).

### 11d. A cross-platform side-by-side MUST be reconciled onto ONE stated coordinate system
Comparing oracle (apple2e) vs port (coco3) pixel positions is worse than useless unless both are on
**one coordinate system with the mapping STATED** — else it invents a phantom offset. Apple HGR = 280
logical px (7 px/byte); CoCo3 = 320 px (4 px/byte); the bridge is the port's **+20 centering**:
`CoCo3_px = Apple_px + 20` ((320−280)/2), and the native oracle render is 280 wide (the 560 MAME snap
halved, §11b) → **pad it +20 left** into 320-space. Then integer-NEAREST only (no interpolation — it
blurs the boundaries being read), **stack vertically (oracle top / port bottom) with columns aligned**
(X-checking is the point, not literal left-right), overlay a **byte ruler** (4-px CoCo3 boundaries +
mark the target bytes), crop to the band, emit **1:1 + magnified**, and **print the mapping on the
image**. Sanity check the reconcile: oracle post (Apple col 23 sh5 = px166) +20 = **px186** must equal
the port target byte 46 sub 2 = 46*4+2 = **px186** — they land together only because sub 2 is the fix.
*Candidate:* `cross-platform-side-by-side-needs-one-stated-coordinate-system-plus20-integer-nearest`.
*Established:* wall-top placement side-by-side 2026-07-16. Tool: `harness/tools/walltop_side_by_side.py`.

### 11e. Decompose authored art into an OPAQUE block + uniform FILLS to avoid a masked-blit primitive
When authored art seems to need a per-pixel masked composite blit (opaque-black `b`=0 vs transparent
`t`=0, both index 0), **check whether the transparency is separable by geometry** before building the
primitive. The scene-6 wall post (9×7) put **every** `t` in **one column** (col 6) that is itself a
**uniform repeating rail** → the art decomposed into (a) **cols 0–5 = a fully-opaque block** (no `t`
anywhere → no mask; the plain opaque blit suffices — and `HAL_gfx_blit_sprite_opaque` DOES sub-byte
shift 0–3, sharing `blit_dispatch`), and (b) **col 6 = the rail = direct horizontal ROW-FILLS** (every
tiled column identical → white/black row-runs, no cel/mask/tiling). This **designed out** the
substantial Stage-4 masked-composite primitive entirely. **Assert the decomposition** (no `t` in the
opaque region; the transparent column == the fill pattern) — don't assume it. Watch the **§9a edge**:
an opaque *shifted* blit stamps the shifted-in leading pixels black (pre-shift with a sky-filled edge,
or flag for the gate). *Candidate:*
`decompose-authored-art-into-opaque-block-plus-uniform-fills-to-avoid-a-masked-blit-primitive`.
*Established:* wall-top 9×7 placement 2026-07-16 (`scene6_cliff_walltop.s`; framebuffer-diff-verified,
zero leak outside the band). The combatants may still need the primitive (non-decomposable art).
*Gotcha caught by the framebuffer-diff:* `ldd #colour` **clobbers B** — if a fill routine takes the
row in B, load the colour into **U** (survives `MUL`) instead; the diff flagged a stray row-0 fill.

---

## 12. Quick command idioms (coco3)
```bash
# Boot to DECB + drive it (needs disk11.rom present):
mame coco3 -flop1 <image.dsk>        # then natkeyboard:post 'LOADM"PROG"\r' / 'EXEC\r' (§2)
# Build an image:  imgtool ...        # .dsk = 18 sec/track fixed; DMK for track geometry (§3)
# Operator live-watch (§11):  -speed 8 -prescale 3 -resolution 1920x1152 -window -nomax
# Fast headless trace:  -nothrottle -video none -sound none -seconds_to_run <N> -script tools/<lua>.lua
# Headless DEBUGGER run:  add -debug AND unpause in Lua (execution_state="run", §10)
```
- **Windows-path-in-Lua gotcha (shared):** `"C:\k…"` is an invalid Lua escape → the script
  **silently fails** and MAME runs the full duration with **no tap, no error.** Use forward
  slashes (`C:/…`) or `\\`.
- **Script must be at MAME's cwd** (`-script tools/foo.lua` resolves from the run repo) —
  copy from `harness/tools/` if needed.
- **`-seconds_to_run` is EMULATED seconds**, not wall-clock; if a `-nothrottle` run drags for
  minutes real-time, throttle isn't in effect — fix the invocation.
- **Never mutate prod under a read pass:** `karateka.bin` `88eba89…` must stay byte-identical.

---

## 13. Tool index — which tool exercises each idiom
| Idiom | Tool |
|---|---|
| live visual gate (boot-excluded `.bin` + set PC) | `harness/tools/gate1_live.lua`, `gate2_live.lua`, `comp_live.lua` |
| gate trace / framebuffer verify | `harness/tools/gate1_trace.lua`, `gate2_trace.lua`, `decode_framebuffer.py` |
| GIME palette index derivation | `harness/tools/palette_derive.py` |
| sprite convert / parity / render | `harness/tools/sprite_convert.py`, `flip_parity_inplace.py`, `sprite_visualize.py` |
| snapshot capture (⚠ not a live gate) | `harness/tools/gate1_snap.lua`, `comp_snap.lua` |

---

## Appendix — candidate names (MAME cluster, coco3)
Sourced to specific disk-boot / FDC / GIME / display-init passes:
- `coco3-has-no-autoboot-entry-is-DECB`
- `mame-autoboot-and-interactive-are-mutually-exclusive-use-natkeyboard-post`
- `dsk-is-always-18-sectors-use-DMK-for-short-tracks` · `mame-dmk-writeback-hijack-proxy`
- `decb-directory-is-track-17-keep-raw-tracks-clear`
- `decb-loadm-overwrites-010C-irq-vector` · `decb-assumes-slow-does-not-force-slow`
- `mame-success-on-a-hardware-edge-question-is-not-a-hardware-guarantee`
- `gime-palette-writes-must-follow-video-mode-set`
- `6809-read-taps-work-6502-read-taps-dont`
- `tool-render-is-not-a-mame-capture-verify-by-pixel-colour`
  · `automated-check-tautology-validate-against-ground-truth-not-rule-predictions`
- **cross-cutting (shared, in the apple2e file's appendix):**
  `mame-frame-notifier-return-must-be-referenced-or-gcd`,
  `mame-debugger-printf-not-captured-headless-use-tracelog`,
  `mame-bp-action-tracelog-is-brace-free-trace-action-is-braced`.

---

## Cross-reference
The **Apple IIe / oracle** quirks (6502 read-tap bypass, watch-the-seed, seed-determinism of
the attract loop, `FD_STATEFORCE`, tap-every-draw-entry, trace-through-a-boundary,
`-nothrottle` motion-snapshot lie, boot-time-static bytes, the full debugger/Lua toolkit) are
in the companion **`mame-idioms-apple2e-oracle.md`**. The two targets differ most at §1/§10:
**6809 read-taps work; 6502 read-taps don't** — the single most important cross-target
difference. The debugger/Lua mechanics (`execution_state="run"` headless-unpause, `bpset`/
`wpset`, `b@`/`pb@`, `debugger:command`, trace+`tracelog`, the brace rule) and the
tap-GC/visual-provenance/`-seconds_to_run` gotchas are **shared** and appear in both files.

---

## Verify a VBL animation runs headless — sample the frame-index ZP + check for dwell-drift
To confirm a port ANIMATION actually runs (not just assembles), load the driver `.bin` into
coco3 (fbdump DECB-inject + set PC=exec, `harness/tools/fbdump_stage.lua` pattern) and sample
the controller's **frame-index ZP** (e.g. `cl_idx $40`, `cl_dwctr $41`) + `page_register $50`
every N frames. Two things fall out at once:
- **It runs** iff the index cycles through its range (crawl: `cl_idx` 0→6→0) and `page_register`
  toggles ($20↔$40 = double-buffer flipping).
- **Each render fits ONE VBL** iff the measured per-frame **dwell does not DRIFT** — if a heavy
  render (clean-restore + composite blit) overran its VBL, `HAL_time_vbl_wait` would miss the
  next VBL and the dwell would stretch run-to-run. Exact, stable dwells (21 / 7×5 / 60 VBL as
  authored) ⇒ the render completes within budget. This is a cheaper one-VBL-budget check than
  cycle-counting the render path. *Established:* climb-crawl first-animation build 2026-07-13
  (`scene6_climb_crawl_driver`, `climb_controller.s`).

### 11f. Verdict a placement on the OBSERVED framebuffer, never on the intended value
A placement report claimed "posts sub 2 → sub 1 → px 185" and was verdicted CONFIRMED on the *claim* —
the value that shipped was never measured. (It later turned out the sub-1 HAD landed, but that was luck,
not evidence.) **Fix the class like the art-bytes check does — with evidence:** (1) quote the placement
lines from the BUILT source (`grep`/`sed` of the real file post-edit, not a restatement of intent), and
(2) DUMP the framebuffer and report the OBSERVED pixel columns / band rows (`fbdump_stage.lua` +
per-pixel decode). If observed ≠ expected, STOP — do not reconcile in prose. Corollary: also measure the
CURRENT state before applying a "correction" — the delta may already be there (here the post was already
at px185, so "1px left" meant px184, not the dispatch's stated px185). *Candidate:*
`verdict-placement-on-the-observed-framebuffer-not-the-intended-value`. *Established:* wall-top placement
correction 2026-07-16 (`scene6_cliff_walltop.s`; posts measured at px184/268 post-edit).

### 11d. A "don't commit until X" hold needs an explicit RELEASE TRIGGER + SCOPE, or it strands work
The 07-12 Stage-3 WIP was held under *"don't commit Stage-3 until the static image is correct."* The
hold had **no release trigger and no scope**: when the static image *was* gated (the wall-top, months
later), nobody re-derived the hold, so the WIP sat in the working tree — and it had become
**load-bearing** (`scene6_backdrop.s`'s `draw_fuji_cels`/`fill_walltop` are called by the shipped
fallback). Consequences: (1) **the gated render was not reproducible from HEAD** — it lived only on
disk; (2) every subsequent *"file X unchanged"* byte-identity claim was **quietly ambiguous**
(unchanged vs HEAD, or vs the churned disk?). Confirm load-bearing cheaply before assuming: `git stash
<file>` → build → observe the failure (here: `Undefined symbol fill_walltop`/`draw_fuji_cels`) → pop.
**Rule:** a commit-hold must name (a) the exact **release trigger** and (b) its **scope** (which files
/ which change), or unrelated work accreting in the same working tree gets stranded and byte-identity
claims made afterwards are unsound. *Candidate:*
`a-dont-commit-until-X-hold-needs-an-explicit-release-trigger-and-scope`. *Established:* churn commit
2026-07-18 (`891dc63`).

### 11e. A transition/carryover artifact is ONLY visible in the LIVE sequence — per-item renders LIE
A **carryover** artifact (previous-pose pixels surviving into the next frame because the restore bbox
doesn't cover the previous pose's extent) exists **only in the running animation** — the state is
`restore-previous → draw-current`. **Rendering each pose standing alone on a clean substrate CANNOT
reproduce it** (there is no "previous" to leak), so every frame comes back innocent and the case is
**falsely closed**. This is exactly how the prior orange diagnosis answered the wrong question (it
tested the *substrate alone* at rows 152–168 — faithful, true — but the artifact is *carryover at the
player's lower body*). **Rule:** to capture carryover, run the gated build live and dump the DISPLAYED
framebuffer **once per pose, in sequence**, detected from the controller's frame index — never
independent per-pose renders. *Candidate:*
`carryover-artifact-only-in-live-sequence-per-item-renders-falsely-exonerate`. *Established:* per-pose
climb capture 2026-07-18 (`climb_pose_capture.lua`).

### 11f. Live per-pose capture: gate on the DWELL counter, not just the frame index (`cl_idx` reads 0 pre-init)
Capturing pose 0 of the crawl by "first frame where `cl_idx`($0040)==0, a couple frames after PC=exec"
grabbed a **half-drawn substrate**: the substrate blitting takes several frames after `PC=exec`, and
`cl_idx` reads 0 the whole time (ZP is 0 before `cl_init` writes it), and `page_register`($0050) still
read `$00` (uninitialized). The dump had only 123 rows of content vs 175–188 for real frames — an
invalid "anim_00." **Fix:** gate the capture on `cl_dwctr`($0041) `!= 0` — it is 0 until `cl_init` runs
`cl_load_dwell` (loads dwell 21) and is *never* left at 0 mid-crawl (`cl_tick` reloads it the same tick
it hits 0). So `cl_dwctr != 0` is the objective "init complete, pose 0 rendered on the fully-drawn clean
substrate" signal — the sanity anchor for HS-2 (anim_00 clean = clean **by construction**, first render
with no predecessor). Also: the DISPLAYED buffer = **opposite** of `page_register` (it holds the *back*
buffer; `cl_render` presents then toggles), so dump `(pr==$20)?$C000:$8000`. And per §11b, dump the
framebuffer **memory** and decode square-pixel — `scr:snapshot()` stretches and cannot show a 1px line.
*Candidate:* `gate-live-pose-capture-on-dwell-counter-not-frame-index-cl-idx-reads-0-preinit`.
*Established:* per-pose climb capture 2026-07-18.

### 11g. A mechanism that explains the artifact but NOT its exclusivity is incomplete — the negatives are the test
The anim_02 orange was diagnosed as double-buffer carryover: `cl_render` draws into the *back* buffer,
so a pose's carryover source is **two poses back** ⇒ anim_02 inherits anim_00 (the Y158 outlier, "must
draw below the box"). The story fit anim_02 perfectly — **and was wrong.** Computing every pose's drawn
extent from the pose table (`fcb col,sub,row` + cel `fcb height,width`) showed **all 7 poses are fully
contained in the restore bbox** (cols 20–32, rows 112–167); anim_00's bottom row is 165, *inside* 167.
So `cl_restore` repaints every pose's whole footprint — **zero carryover for ANY pose.** Empirical diff
of each captured displayed frame vs the clean substrate (buffer B at pose0): **orange outside a pose's
own body extent = 0, all 7 poses.** The real cause: anim_02's *own* cels introduce ~3–4× the orange of
the other poses (72 vs 18–39 introduced px) — pose-specific **cel content**, not a restore leak.
**Rules:** (1) a carryover claim must explain the **negative cases** (why NOT the other buffer-A poses)
— if it can't, it's incomplete → STOP, don't fix on a one-frame-fit story; (2) **compute the drawn
extent from cel dims before invoking an out-of-bbox mechanism** — "the low pose must overflow" is an
assumption, the `fcb height` is the fact; (3) diff against a **clean-substrate reference** (an untouched
double-buffer half is a free one) to separate cel content from carryover. This is the second time this
arc a plausible orange mechanism answered the wrong question (cf. the substrate-rows-152-168 finding).
*Candidate:* `carryover-claim-must-explain-the-exclusivity-compute-extent-from-cel-dims-not-assume`.
*Established:* anim_02 orange diagnosis 2026-07-18 (`anim02-orange-finding.md`).

### 11h. When the operator doubts an analysis, render the underlying DATA — and let it falsify the claim
The anim_02 "orange is in the cel data (72 px vs 18–39)" finding was argued from **framebuffer pixel
counts**. Jay doubted it (his eye has overruled analysis every time in this arc). The right response is
not more counts defending the finding — it is to **render the underlying data and let it falsify the
claim.** Decoding all 7 climb poses' cels straight from `converted.s` (per-pixel, mask/index-0 handled,
real palette, square-pixel) gave raw index-1 counts of **anim_02=126, but anim_04=88 / anim_05=92 /
anim_03=86** — i.e. **every pose's cels carry substantial orange; anim_02 is highest but ~1.4×, NOT the
3–4× outlier the earlier framebuffer numbers implied.** The two measurements differ because the prior
"introduced-vs-substrate within the bbox" count suppresses cel orange that lands on already-orange
substrate — a *different basis*, so the raw sheet **does not reproduce** the 72/18–39 ratio. **Rules:**
(1) an analysis-vs-eye dispute is settled by rendering the **data under test**, not by recounting;
(2) **state the measurement basis** — "orange introduced in the composited frame within the bbox" and
"raw index-1 px in the cel" are different numbers and conflating them manufactures a false
outlier/agreement; (3) present the falsifier **neutrally** — a result that undercuts your prior finding
is the method working, not a failure. *Candidate:*
`when-operator-doubts-analysis-render-the-data-to-falsify-state-the-measurement-basis`.
*Established:* climb-cel sprite sheet 2026-07-18 (`render_cel_sheet.py`).

### 11i. Entangled causes (what an index LOOKS like vs WHICH index a pixel is) — test ONE per render
The anim_02 orange had two live candidate causes: a **palette** change (alters what index 1 looks like)
and a **blue↔orange swap** (alters which index a pixel is). Rendered together, a "fixed" frame can't
attribute the fix — and a *wrong pair can cancel out and look right* (a swap that's wrong plus a palette
that's wrong can land on a plausible frame). **Rule: one variable per comparison render.** Judge the
palette at the current cel data (no swap); run the swap at the palette under which the mismatch was
observed (here CURRENT `$1B`/`$26`). Only combine after each is settled independently. Corollary for the
swap test specifically: **report the NEGATIVE band too** — a blanket index swap is all-or-nothing, so it
must be checked against the rows that CURRENTLY match (here base rows 166/167), not only the mismatch
rows; if it fixes the mismatch band but breaks the matching band, it is **not a clean swap** — and that
is the finding, not a failure. *Candidate:*
`test-one-variable-per-render-a-wrong-pair-can-cancel-and-look-right-check-the-negative-band`.
*Established:* anim_02 palette/swap renders 2026-07-18.

### 11j. Scope a colour/swap test to the ARTEFACT under test — and read the FUSED view, not just per-pixel
Two follow-ons from the anim_02 arc. (1) **A global re-colour conflates sprite and substrate and voids
the result.** The first blue↔orange swap flipped *every* index-1 pixel and "broke base rows 166/167" —
but those are substrate, never part of the hypothesis; the test never tested the sprite-scoped claim.
To scope a swap to one cel, **replay its blit** (placement byte-col/sub/row + cel data, in draw order)
to build a per-pixel source mask, and **validate the replay against the real captured frame** (here the
sim matched pose_2 1404/1404 px) before trusting the mask. Mind draw order: the over-cel overdraws the
back-cel in the overlap, so the swapped region can be far smaller than the cel's extent — state the
visible rows so a scoping success isn't misread as partial failure. (2) **On striped/alternating content
the FUSED (1:1) read is the gate, not the per-pixel map.** Apple HGR artifact colour physically blends on
a composite display; discrete GIME indices don't — so a frame can be per-pixel correct yet read wrong, or
per-pixel wrong yet read right. Ship 1:1 (fused) AND the ×8 countable crop; the operator rules from the
fused view. And when a palette must change for the sandbox but prod builds from the same `src/`, apply it
in the **sandbox/fallback** (override after `HAL_gfx_init`), not shared `gfx.s`, or prod moves on rebuild;
prove palette-only with an **identical index-frame diff** (the RGB framebuffer diff is global and proves
nothing). *Candidate:*
`scope-swap-to-the-cel-via-validated-blit-replay-and-gate-on-the-fused-read-not-per-pixel`.
*Established:* anim_02 hybrid-apply + $A4A4 swap 2026-07-18.

### 11k. Asset-pipeline safety: catalog before converting; one pass / two outputs; derive geometry once
Two pipeline idioms (asset-side, recorded here per the pre-conversion-safety dispatch).
**(1) Before any bulk re-conversion, prove which assets are pure converter output — re-convert + diff.**
Hand-edited/authored work is **not reproducible from the oracle**; a bulk re-run **silently destroys** it.
The behavioural test beats a git-history read (it catches *converted-then-edited* that rode in on a bulk
commit): re-convert each cel fresh from the oracle to a **scratch dir** (never over `content/`) and byte-diff
the CEL DATA (H,W header + H*W bitmap; ignore comment/ORIGIN lines). Identical ⇒ pure ⇒ safe; ANY diff ⇒
protected. **Report the diff SHAPE, don't adjudicate:** LOCALISED (few bytes, an edge) = hand-edit;
SYSTEMATIC across the *whole* set = converter drift — opposite treatments. A localised edit that *recurs
across a themed subset but not the whole tree* (the Mt-Fuji edge-fill-to-`$AA`: 4 of 188) is an authored
edit, not drift. Over-inclusion is free; a wrong "safe" is not. Protection must be **structural** (a
checked-in protected manifest + a converter hard-stop that refuses to overwrite), never "remember not to run
it on those". Determinism is a precondition — verify same-input→same-output before trusting any diff.
**(2) When one artefact must be DERIVABLE from another, produce BOTH in ONE pass from a single
classification.** A second pass recomputes extents/trims independently and **shifts the result inside an
identically-sized box** — the converter already does this (`sprite_convert.py` trims leading/trailing
all-zero columns per-cel; a separate "clean" pass would trim a different count than "fringed" and mis-register
the sprite). Derive geometry once in the superset frame; the subset **inherits** the trim, never computes its
own. And the discriminating classification often lives in the decode's **branch structure**, not its output —
so filtering the output (e.g. "drop the chroma index") conflates categories that need opposite treatment
(edge fringe vs a solid coloured body). *Candidates:*
`catalog-by-reconvert-diff-before-bulk-convert-report-shape-protect-structurally`,
`one-pass-two-outputs-derive-geometry-once-or-a-second-pass-shifts-inside-the-same-box`.
*Established:* pre-conversion-safety dispatch 2026-07-18.

### 11l. MAME coco3 HAS a Monitor Type config (Composite default / RGB) — set it via the screen_config ioport
**CORRECTION (supersedes the earlier "no toggle" claim — that was wrong; Jay was right there is an RGB
switch).** MAME `coco3` has a **"Monitor Type" machine configuration**: ioport tag **`:screen_config`**,
mask 1, **`Composite`=0 (default)** / **`RGB`=1** (visible in `-listxml coco3`; there is also a separate
`gime:artifacting` config). The earlier search failed because **`-listconfig` is not a MAME command** (it
errors "unknown option") — the configs are enumerated by **`-listxml`**, not a `-listconfig` flag, and I
stopped too early. **It is a MACHINE CONFIG, not a CLI flag** — there is no `-monitor`/`-rgb` command-line
switch; set it either in the MAME UI (TAB → Machine Configuration → Monitor Type) which persists to
`cfg/coco3.cfg`, or **headless from Lua**: find the field named `"Monitor Type"` on port `:screen_config`
and set `field.user_value = 1` (RGB) / `0` (Composite) **before the palette registers are written**, then
snapshot (`monitor_mode_snapshot.lua`). **Measured, same climb frame, same GIME regs $00/$26/$2D/$3F:**
| reg | Composite (default) | RGB (Monitor Type=1) |
|---|---|---|
| `$26` orange | (245,115,58) | (255,85,0) |
| `$2D` blue | (54,179,247) | **(255,0,255) magenta** |
| `$1B` blue | (94,44,255) | (0,255,255) cyan |

RGB mode = the digital bitpack (R1 G1 B1 R0 G0 B0, 2b/channel); Composite = the intensity/hue artifact
decode. **The palette study + everything gated so far was judged through the DEFAULT = Composite.**
Consequence for the RGB clean-vs-fringed gate: **MAME CAN show the RGB-monitor look** — set Monitor
Type=RGB; no real hardware or external decode tool required for that gate (hardware is still needed only
for true-silicon fidelity, per 25.3-H). **Gotcha:** set the config **once, early** (before the fallback's
`HAL_gfx_init` palette write) and let the mode settle before snapshotting — re-asserting it on the grab
frame catches a mid-transition geometry change and yields a truncated PNG. *Candidate:*
`mame-coco3-monitor-type-is-a-screen_config-ioport-composite-default-rgb-set-via-lua-not-a-cli-flag`.
*Established:* MAME mode-check + correction 2026-07-18 (`monitor_mode_snapshot.lua`).

### 11m. Fix a per-cel systematic bug by DERIVING the parameter from ground truth, not a hand-override list; verify the RULE against a control
The climb chroma-parity was set by a `pick_parity('orange')` heuristic + a hand-maintained `FLIP_OVERRIDE`
list — which silently inverted `$A4A4` (it passed its hue gate while blue↔orange swapped). The right fix
for a **systematic per-cel bug** is to **derive the parameter from ground truth** — here each cel's
**traced render column** (`start_col = byte_col*7 + sub`), the same model the cliff cels already used — so
parity is correct by construction, no heuristic and no exception list. **Verify the RULE, not every
asset:** (1) it must **reproduce every existing hand-override automatically** (they become derivations —
if any isn't reproduced, the rule is incomplete → STOP); (2) it must flip a **known control** (`$A4A4`
MUST flip, Jay-ruled — if it doesn't, the rule is wrong → STOP). Prove both in a **scratch** re-convert +
byte-diff before touching `content/`; adopt only the cel(s) whose DATA changed; **framebuffer-diff** the
one render that moves and surface it — don't self-certify. **Parity fixes which index a pixel gets, not
its look ⇒ no hue-gate re-run.** *Candidate:*
`derive-the-systematic-parameter-from-ground-truth-not-an-override-list-verify-the-rule-against-a-control`.
*Established:* column-parity fix 2026-07-18 (`stage3_convert_climb.py`; A4A4 the missed cel).

### 11n. coco3 `gime:artifacting` = the composite NTSC artifact-colour model (Off/Standard/Reverse) — a NO-OP for palette-mode content
`-listxml coco3` config `Artifacting` (tag `gime:artifacting`, Off=0/Standard=1/Reverse=2) on the coco3
GIME (`gime_ntsc`) device — distinct from the CoCo1/2 VDG `:artifacting`. **It is classification A (an
emulator composite-render model), not a monitor-independent GIME register:** "artifacting" with a
Standard/Reverse *phase* is the composite NTSC artifact-colour model (the GIME has no such register; the
phenomenon lives only on the composite signal), and measured behaviour is **RGB-invariant** to it.
**Load-bearing:** it is a **NO-OP for Karateka** — measured, the same frame renders **pixel-identical**
across Off/Standard/Reverse under BOTH Monitor Types — because Karateka uses the GIME **4-colour palette
mode**; artifacting only applies to the **1-bit/2-colour high-res modes** where alternating pixels artifact
into colour. **Rule:** classify an emulator "artifacting" option by what it DRIVES (composite artifact
phase ⇒ A) not its name, enumerate exhaustively (§2A.4) before concluding scope, and **exercise it on
representative content** — a knob that does nothing on palette-mode frames is irrelevant regardless of its
A/B label. Set it (like Monitor Type) via the `Artifacting` field `user_value` on port `:gime:artifacting`
(`gime_artifact_snapshot.lua`); there is no CLI flag. *Candidate:*
`coco3-gime-artifacting-is-the-composite-artifact-model-a-no-op-for-palette-mode-content`.
*Established:* GIME-artifacting recon 2026-07-18.

### 11o. A two-record post-mortem is corroborated by INDEPENDENT reconstruction, then reconciliation
When two parties each hold half of a history (here: the executor's trace/build/commit record and the
Orchestrator's planning/verdict record), the value is the **cross-check**, and it only works if each half
is reconstructed **independently first** — read the other record before drafting yours and you anchor to
it, turning corroboration into transcription. Draft from your OWN artifacts (commit spine, reports, diffs,
hashes), THEN diff against the other and build an agree/disagree/coverage-gap table; **flag discrepancies,
don't smooth them; surface conflicts for the ground-truth owner, don't resolve them unilaterally.** And
**no invented precision** — if a SHA/measurement isn't in your record, "not in my record" is a valid,
useful entry (it shows which claims only one half supports); echoing the other record's number as if
independently confirmed defeats the exercise. If the other record is **inaccessible**, say so and provide
your side's discrepancy-candidates as inputs to the table rather than faking the diff. *Candidate:*
`two-record-postmortem-independent-reconstruction-then-reconcile-never-read-the-other-first`.
*Established:* post-mortem Vol II 2026-07-18.

### 11p. Preview coco3 RGB-monitor palette candidates by the BITPACK decode (= MAME Monitor Type=RGB), not per-candidate snapshots
To build an RGB palette-selection panel square-pixel, render the index frame with each candidate's **bitpack
RGB** (6-bit value → R1G1B1R0G0B0, 2 bits/channel scaled 0/85/170/255) — this is **exactly what MAME renders
under Monitor Type=RGB** (verified: `$19`→(0,170,255), `$26`→(255,85,0), `$34`→(255,170,0), `$2D`→(255,0,255),
`$1B`→(0,255,255)). It avoids MAME's stretched 640-wide snapshots and lets one image sweep many candidates.
**Verify the mode took** by measuring one candidate in real MAME RGB (`rgb_palette_snapshot.lua`: set the
Monitor Type field + poke `$FFB1`/`$FFB2`) — the framebuffer must show the RGB triple, not the composite one.
And **value-verify the composite anchor** before building the panel (poke nothing, Monitor=Composite → assert
the recorded hybrid `$2D`→(54,179,247)/`$26`→(245,115,58); mismatch = drift, STOP). Finding worth surfacing:
in RGB mode the digital bitpack can land **closer to the oracle** than the composite decode (C1 blue `$19`
d36 / orange `$26` d36 vs composite `$2D` d46 / `$26` d60) — native-strong RGB may beat the composite look;
the fused 1:1 read decides, not the metric. *Candidate:*
`preview-rgb-palette-candidates-by-bitpack-decode-equals-mame-monitor-type-rgb-verify-the-anchor`.
*Established:* RGB palette selection study 2026-07-18.

### 11q. Two palettes for one build = a two-row table + a boot-time selection byte (NEVER monitor-detect)
The CoCo3 GIME emits composite AND RGB simultaneously and the **6809 cannot read which monitor is
attached** — so "which palette" is a **boot-time CHOICE per monitor, not an auto-detect**. Land it as a
named `palette_sets` table (4 bytes/row = `$FFB0..$FFB3`) with one row per look, and a `pal_select` byte
(a runtime byte a future boot menu can write) read at boot; `apply_palette` does `pal_select*4` (MUL) →
`leax d,#palette_sets` → copy 4. Keep the two sets a **one-entry difference** where possible (here composite
`$00,$26,$2D,$3F` vs RGB `$00,$26,$19,$3F` — only index 2/blue differs) so the two looks are provably the
same art under a different decode. Build the variant with `lwasm -DPAL_SEL_DEFAULT=1` (guard the default
with `ifndef`), not an edit/revert. Verify BOTH variants against their monitor: composite+Composite →
(54,179,247)/(245,115,58) unchanged (regression), RGB+RGB → (0,170,255)/(255,85,0). Identical pixel COUNTS
across variants prove the index frame is untouched (palette is a pure index→RGB remap; the parity fix and
the palette compose orthogonally). *Candidate:*
`two-palette-sets-one-build-selection-byte-at-boot-never-monitor-detect-one-entry-diff`.
*Established:* RGB palette landing 2026-07-18 (`scene6_climb_crawl_driver.s`).

---

## 14. Disk-boot + natkeyboard: the five things that make DECB `LOADM` actually work
*(Filed by Clyde under §2A.3 during P1.1 — the build→test loop stand-up, POP3_port.
**PROVISIONAL, flagged for Jay's confirmation**: the §2A.3 authorship ruling is still open.
Every item below was measured in this repo, not inferred.)*

Getting a build from `imgtool` onto a running CoCo3 under automation failed five distinct
ways before it worked. Each has a one-line fix. Tool: `POP3_port/harness/smoke/probe_test.lua`.

- **14a. `-ext fdc` is MANDATORY.** A bare `mame coco3 -flop1 x.dsk` has **no disk
  controller** — it boots to Extended Color BASIC, `LOADM` does nothing, and the program
  silently never runs (observed: `status=0`, `PC=$CFFD`). §12's quick-command line omits
  it; `karateka docs/project/disk-boot-decb-overlap.md:67` has the correct form. With the
  FDC attached, DECB's prompt poll sits at `PC=$A7D7`/`$D7D5`. `disk11.rom` ships inside
  `coco3.zip` — and note `mame coco3 -verifyroms` reporting **"bad" is benign**: the only
  missing files are three *alternate* DOS ROMs (`rgbdos_mess`, `hdbdw3bck`, `hdbdw3bc3`).
- **14b. `natkeyboard.in_use` defaults to FALSE, and arming it in the same frame as the
  first post SCRAMBLES that post.** `PRINT 7*6` arrived as `PREPRINT` → `?SN ERROR`. Set
  `manager.machine.natkeyboard.in_use = true` **at script load**, frames before any key.
- **14c. Posting is ASYNCHRONOUS and slow — gate on `nk.empty`, never on a frame gap.** A
  12-character `LOADM"PROBE"` took **~130 frames** to drain. A fixed gap races it and the
  next post lands mid-string. Both `"\n"` and `"\r"` work as ENTER on this target.
- **14d. `LOADM` itself takes ~400 frames (drive spin-up + seek) — POLL for the image,
  don't settle-and-hope.** Watch the load address until the expected opcode appears, then
  proceed. This also converts a load failure into a *reported load failure* rather than a
  mystery crash downstream.
- **14e. A DECB-`LOADM`'d binary MUST NOT contain a `$0100` segment** — this is §5's
  overlap hit from the other direction, and it is the subtle one. karateka's scripted
  drivers open with an 18-byte vector block at `$0100-$0111`; **do not copy that into
  anything DECB loads.** Those drivers are *poked in* by Lua with the CPU already halted,
  so nothing of DECB's is live. Under `LOADM`, `$010C` is DECB's **live IRQ dispatch
  vector**: the load succeeds and the image is byte-correct (`$0200 = 7E 02 08` verified),
  but DECB is left executing its own destroyed vector — `PC` observed wandering
  `$010D → $FEF9 → $FE0B → $C60B`, never returning to the prompt. Omit the block; if the
  program masks `CC.I/F` for its whole run it needs no vectors at all.

*Candidates:* `ext-fdc-is-mandatory-a-bare-coco3-has-no-disk-controller`,
`natkeyboard-in-use-must-be-armed-frames-before-the-first-post`,
`gate-natkeyboard-posts-on-empty-not-on-a-frame-gap`,
`poll-for-the-loaded-image-dont-settle-and-hope`,
`never-ship-a-0100-vector-block-in-a-DECB-LOADM-binary`.
*Established:* P1.1 build→test loop stand-up 2026-07-25 (POP3_port).

### 14f. Scrape the DECB text screen at `$0400` to see what the guest ACTUALLY received
The fastest way to debug a natkeyboard problem is to read the 32×16 VDG text screen
directly instead of guessing from behaviour. **Screen codes are not ASCII:** space is
**`$60`**, and ASCII `$20-$3F` (punctuation, including `"` → **`$62`**) is stored as
**ASCII+`$40`**; ASCII `$40-$5F` (uppercase) is stored as-is. Decoding it wrongly makes a
*correctly* typed command look mangled — `LOADM"PROBE"` reads as `LOADM.PROBE` under a
naive ASCII map, which sends you hunting a quote-key bug that isn't there.
```lua
for row = 0, 15 do
  local t = {}
  for col = 0, 31 do
    local b = mem:read_u8(0x0400 + row*32 + col)
    t[#t+1] = (b == 0x60) and " "
           or (b >= 0x40 and b <= 0x5F) and string.char(b)          -- uppercase, as-is
           or (b >= 0x60 and b <= 0x7F) and string.char(b - 0x40)   -- punctuation, -$40
           or "?"
  end
  log("|" .. table.concat(t) .. "|")
end
```
*Candidate:* `scrape-the-vdg-text-screen-to-see-what-the-guest-received-screen-codes-are-not-ascii`.
*Established:* P1.1 2026-07-25.

### 14g. `.bat` files MUST be CRLF (build-side, not MAME — but it breaks the build contract)
`cmd.exe` cannot parse an LF-only batch file: it mangles the whole file into truncated
command names (`'wasm' is not recognized`, `'bat' is not recognized`) and "fails" in a way
that looks like a missing toolchain rather than a line-ending problem. `build.bat` is the
`CLAUDE.md §1` build contract, so this is load-bearing. Pin it in `.gitattributes`
(`*.bat text eol=crlf`) rather than relying on any developer's `core.autocrlf`. Repair with
`read_bytes`/`write_bytes` — **never** Python `write_text`, which silently rewrites every
line ending in the file (the P1.2 `.gitignore` corruption).
*Candidate:* `pin-bat-crlf-in-gitattributes-cmd-cannot-parse-lf-only-batch`.
*Established:* P1.1 2026-07-25.


---

## 15. Build/tooling gotchas from the sprite-tooling port (P1.2)
*(Filed by Clyde under §2A.3. Same class as §14g: not MAME itself, but each one
breaks the build/verify loop and each cost real time here. **PROVISIONAL** — the
§2A.3 authorship ruling is still open.)*

- **15a. `lwasm` resolves `include` relative to the SOURCE FILE's directory, not
  the CWD.** `include "build/cel_include.s"` inside `src/harness/cel_probe.s`
  resolves to `src/harness/build/cel_include.s` and fails with
  *"Cannot open include file"*. Pass **`-I .`** (or the needed root) so
  repo-relative includes work. This is the same root cause as karateka
  `build.bat`'s standing note that source args must use forward slashes — lwasm
  derives the include base by splitting the source path. *Candidate:*
  `lwasm-include-base-is-the-source-dir-not-the-cwd-pass-dash-I`.

- **15b. Python `read_text()`/`write_text()` on Windows silently round-trips
  UTF-8 through cp1252.** Copying a UTF-8 source file and rewriting it with the
  default encoding turns every `—` (`â`) into a lone ``: the
  file is no longer valid UTF-8, and nothing raises. Detected here only because a
  `str.replace` on a line containing an em-dash silently found no anchor. **Use
  `read_bytes().decode('utf-8')` / `write_bytes(t.encode('utf-8'))`**, and assert
  every replace anchor was found. This is the *same failure class* as the P1.2
  `.gitignore` LF→CRLF corruption — Python text I/O on Windows rewrites what it
  round-trips. *Candidate:*
  `python-text-io-on-windows-silently-transcodes-use-bytes-with-explicit-encoding`.

- **15c. POP and karateka cel headers are BYTE-SWAPPED.** karateka:
  `byte0 = HEIGHT, byte1 = WIDTH`. POP: `byte0 = WIDTH(bytes), byte1 = HEIGHT`
  [ref: `HIRES.S:180-186`]. Reading POP cels with karateka's order produces a
  transposed sprite that still "converts" without raising — a silent-garbage
  failure, not a crash. Any tool ported between the two must have this checked,
  not assumed. *Candidate:* `pop-and-karateka-cel-headers-are-byte-swapped`.

- **15d. A decimal `fcb` header parsed as hex is a silent, sample-maskable bug.**
  `converted.s` headers are DECIMAL (`fcb 24,2`). PA.9's throwaway POC reader
  used `re.findall(r'\$?([0-9A-Fa-f]{1,2})')` + `int(v, 16)`, reading `24` as
  `0x24` = 36. It never fired in PA.9 because all four karateka cels sampled
  there have every header digit < 10, where hex and decimal coincide — so PA.9's
  published numbers are unaffected. It fires immediately on POP cels (24-41 rows).
  **Use `sprite_tool/celio.Cel`, the canonical reader, rather than a second
  ad-hoc parser.** *Candidate:*
  `a-validation-sample-that-doesnt-span-the-input-space-can-certify-a-broken-tool`.

*Established:* P1.2 sprite-tooling port 2026-07-25 (POP3_port).


---

## 16. Cel ROW ORDER: POP stores bottom-first, karateka top-first (P1.2-fix)
*(Filed by Clyde under 2A.3. **PROVISIONAL** pending the standing authorship ruling.)*

**POP cel data is stored BOTTOM-ROW-FIRST.** Three code sites in `HIRES.S` establish
it — code, not comments:
1. **PREPREP**: `IMAGE += 2` past the `[width][height]` header, so `IMAGE` points at
   **data row 0** when drawing begins.
2. **CROP**: `TOPEDGE = YCO - HEIGHT`, with `YCO` the *"Y-coord of lowest visible line
   of image"* — `YCO` is the **BOTTOM** scanline.
3. **draw loop** (`*  Next line up`): `IMAGE += WIDTH` advances the source **FORWARD**
   while `DEC YCO` walks the destination **UP**, terminating at `TOPEDGE`.

=> data row 0 is drawn at the BOTTOM scanline; data row h-1 at the TOP.

**The `HIRES.S:187` comment says the opposite** — *"image bytes read left-right,
top-bottom"*. Read as visual orientation it contradicts all three code sites, and
taken at face value it makes the original game render upside down, which it does not.
It describes sequential storage. `CLAUDE.md` 2 ranks comments **lowest**; the
mechanism wins. **This comment is a live trap for anyone porting POP art.**

**karateka is the other way round** (cel row 0 = visual top), so a converter ported
from karateka must **reverse the row order** on ingest. The colour model needs no
change — it is per-row — but the row loop does. Symptom: every cel, and every
compiled sprite built from one, renders vertically flipped.

*Candidates:* `pop-cel-rows-are-stored-bottom-first-the-source-comment-says-otherwise`,
`porting-a-converter-between-two-apple-ii-games-check-row-order-not-just-colour`.
*Established:* P1.2-fix 2026-07-25 (POP3_port), after Jay caught the flip by eye.

### 16a. A self-consistent check cannot see an orientation error — anchor to the SOURCE
P1.2's colour spot-check compared the CoCo3 framebuffer against the converter's
output and passed **1152/1152 pixels on cels that were upside down**. It could not
have failed: both sides are downstream of the same converter, so a consistent flip
round-trips perfectly. The guard that closes it (`harness/tools/verify_orientation.py`)
compares against the **original cel binary** in `oracle/source/.../IMG.CHTAB*` plus the
blitter's documented row-order semantics — an input the converter cannot influence.
Demonstrated failing on the real pre-fix data recovered from git.
**Rule: for any property with a ground truth (orientation, scale, handedness, colour),
at least one check must be anchored OUTSIDE the pipeline under test.**
*Candidate:* `at-least-one-check-must-be-anchored-outside-the-pipeline-under-test`.
*Established:* P1.2-fix 2026-07-25.


---

## 17. `PSHU D,X,Y` byte order, and the codegen-simulator trap (P1.3)
*(Filed by Clyde under 2A.3. **PROVISIONAL** pending the standing authorship ruling.)*

**Measured on the real 6809 under MAME** (`src/harness/pshu_probe.s`: load D/X/Y with
distinguishable constants, one `PSHU`, dump memory with canaries either side):

    LDD #$A1A2 / LDX #$B1B2 / LDY #$C1C2 / PSHU D,X,Y
    ascending from the final U:   A1 A2 B1 B2 C1 C2

So for a compiled-sprite burst: **run[0:2] -> D, run[2:4] -> X, run[4:6] -> Y.**
(PSHU pushes Y first, so Y lands at the HIGHEST addresses.) The PA.9 POC had this
inverted and it shipped through two dispatches undetected.

**17a. Why it went undetected — the trap worth remembering.** The POC's soundness
simulator handled PSHU as `for v in reversed(chunk): mem[u]=v` — it replayed the
`chunk` list the emitter had handed it and **never modelled A/B/X/Y**. The register
assignment is the *only* decision the emitter makes there, and it sat outside the
checker's model, so the check validated the tokenizer and the addressing arithmetic
while being blind to the encoding. It reported ALL PASS on every cel.
**Rule: a codegen simulator must consume ONLY the emitted instruction stream and
execute the target's registers.** If it takes anything else the emitter computed, it
is replaying intent, not testing the lowering.

**17b. `PSHU` is not always the cheapest store.** 6 bytes = 11 cy (1.83/byte), 4 = 9
(2.25), but 2 = 7 — worse than `STD d,U` at 6 cy, which also leaves U alone (no
`LEAU` to reposition). Glen's own file mixes 46 `PSHU` with 14 `STD` / 16 `STX` /
18 `STA` for this reason. Cost both forms per run; do not burst greedily.

**17c. Burst optimizations are worthless without long homogeneous runs.** On POP's
cels (thin limbed figures, ~60% of drawn bytes "mixed" at 2bpp) only **7% of opaque
bytes sit in runs of 4+**, `PSHU` fires in 0.4% of cycles, and all four of Glen's
optimizations together buy ~3%. The predictor is cheap and needs only the input:
**measure the run-length distribution before building the optimizer.**

*Candidates:* `pshu-dxy-byte-order-d-first-y-last-verify-on-hardware`,
`a-codegen-simulator-must-execute-registers-not-replay-the-emitters-chunk-list`,
`measure-run-length-distribution-before-building-a-burst-optimizer`.
*Established:* P1.3 production sprite compiler 2026-07-26 (POP3_port).


---

## 18. MAME's coco3 Monitor Type defaults to COMPOSITE — set it or the colour gate lies (P1.3-fix)
*(Filed by Clyde under 2A.3. **PROVISIONAL** pending the standing authorship ruling.)*

`mame -listxml coco3` (the 2A.4 enumeration surface):
```
<configuration name="Monitor Type" tag="screen_config" mask="1">
    <confsetting name="Composite" value="0" default="yes"/>   <-- MAME's DEFAULT
    <confsetting name="RGB"       value="1"/>
</configuration>
```
**`CLAUDE.md` §4 makes RGB the project's monitor gate, but MAME's own default is
Composite.** Every harness run that does not set it is rendering in the wrong mode,
and nothing in a byte-level check can tell — the framebuffer holds palette INDICES;
the monitor type only changes how `$FFB0-$FFB3` are DECODED. Set it explicitly:
```bash
mame coco3 -cfg_directory dist/mame-cfg/rgb ...   # ships a coco3.cfg with value="1"
```
(MAME rewrites that cfg on exit, adding mixer/video/image blocks — harmless; the file
is a template, not a constant. Confirm the mode took by re-reading `value=` after.)

**18a. The palette registers mean DIFFERENT THINGS in the two modes.**
[ref: `docs/ground-truth/SockmasterGime.md`] — *"The color set when using composite
monitors is different than above (which applies to RGB monitors). On composite
displays, Bits 5-4 control 4 levels of intensity, and bits 3-0 control 16 hues."*
So the same byte is two different colours:

| byte | RGB decode (R1G1B1 R0G0B0) | Composite decode (intensity, hue) |
|------|----------------------------|------------------------------------|
| `$26` | R=3 G=1 B=0 — **orange** | intensity 2, hue 6 — **orange** (both, luckily) |
| `$19` | R=0 G=2 B=3 — **blue** | intensity 1, hue 9 |
| `$2D` | R=2 G=3 B=1 | intensity 2, hue 13 — **blue** |
| `$24` | R=3 G=0 B=0 — red | intensity 2, hue 4 — **yellow** |

karateka's MAME-verified sets: **RGB `$00,$26,$19,$3F`**, **composite `$00,$26,$2D,$3F`**
(they differ only at index 2 — see §11q).

**How this was caught, and the lesson.** P1.3's harness picked `$24`/`$12` by
hand-computing the RGB bit-pack, then ran without setting the monitor type — so the
values were decoded as composite and `$24` rendered as **hue 4, yellow**. Every
automated check passed: the framebuffer byte-diff was green (1968/1968 px), because
palette indices were correct and only the DECODE was wrong. **Jay spotted it in a
screenshot.** Byte-level verification is structurally blind to palette-register
semantics, exactly as it was blind to orientation in P1.2-fix. Same rule: for a
property with a ground truth outside the pipeline, a byte-diff is not the check.

*Candidates:* `mame-coco3-monitor-type-defaults-to-composite-set-it-explicitly`,
`palette-registers-decode-differently-per-monitor-type-a-byte-diff-cannot-see-it`.
*Established:* P1.3 palette/monitor-mode fix 2026-07-26 (POP3_port), after Jay
reported orange rendering yellow.


## 19. The object/linked build model (P2.1–P2.6, filed retrospectively)

**Why "retrospectively".** §2A.3 rule 3 says a discovered idiom goes in the applicable
file. That was honoured through P1.3-fix — seven commits touch this file — and then
LAPSED: P2.1–P2.5 recorded their findings in source comments and reports instead, while a
report counter tracked "§2A.3 authorship deferrals" up to twenty-one. There was no ruling
to wait for; see §19h. These are the lapsed entries, filed now.

### 19a. FOUR directive classes are object-target-only, not three
`lwasm --decb` (absolute) rejects `export`, `import`, `section`/`endsection`, **and
`setdp`**. P2.3-recon enumerated the first three from toy probes; `setdp` only surfaced on
real HAL code, because a toy probe has no direct-page usage to declare:
```
SETDP not permitted for object target
```
One source serves both build models by guarding all four behind `ifdef OBJTARGET`; the
absolute output is then byte-identical to a source that never had them. Verified:
karateka's production binary `88eba89b…` unchanged across the whole conversion.
*Established:* P2.4 (POP3_port).

### 19b. `lwlink --section-base` is SILENTLY IGNORED — only a script places sections
No error, no warning, exit 0, and the section still lands at the default address. A
conversion that used the flag and checked only the exit code would place everything wrong
and look healthy. A linker script works:
```
section prog load 0200
section code load 3000
entry probe_entry
```
*Established:* P2.3-recon D4; used in `link/pop.link` from P2.4.

### 19c. `lwlink` only errors on a REFERENCED undefined symbol
An `import` that nothing calls links clean. The ABI is therefore enforced at the point of
USE, not of declaration — so "the contract's imports resolve" is only a real claim for
symbols something actually calls. Measured both ways:
```
import never_defined_symbol, NOT called -> lwlink exit 0
import never_defined_symbol, JSR'd      -> External symbol ... not found, exit 1
```
Consequence worth having: a deliberately-dormant entry point that is declared but not
exported becomes a link error naming the symbol, rather than a jump into whatever occupies
the address.
*Established:* P2.4.

### 19d. A linked DECB binary has MULTIPLE segments — gate on the LAST one
`lwlink --decb` emits one record per section. The program segment lands FIRST, so a
harness that polls the entry address and posts `EXEC` on sight types into a still-running
`LOADM`: the program never runs, and it presents as a code fault rather than a race.
Verify every segment's first AND last byte before proceeding. Gating on the last segment
instead of the first holds for any segment count, so adding sections later cannot silently
re-break it.
*Established:* P2.4, after P1.1's single-segment gate broke on the first linked build.

### 19e. GIME 16-colour: `$FF99 = $1E`, 160 B/row, 30,720 B
CONFIRMED from two independent sources, not derived:

| mode | bpp | B/row | HRES | CRES | `$FF99` (192 lines) | bytes |
|------|-----|-------|------|------|---------------------|-------|
| 320×192×4  | 2 | 80  | 101 | 01 | `$15` | 15,360 |
| 320×192×16 | 4 | 160 | 111 | 10 | `$1E` | 30,720 |

GIME-RM §10's Video Mode Reference gives `$1E` directly; SockmasterGime.md:108-136's bit
layout reconstructs the same byte (`%0 00 111 10`). Palette is `$FFB0-$FFBF`, 16 registers.
A wrong stride does not fail loudly — it skews the image into a diagonal — so the mode
service PUBLISHES the stride rather than letting each caller assume it.
*Established:* P2.5.

### 19f. Mode-set ordering DIVERGES from GIME-RM §14, deliberately
The manual's example loads the palette at step 4, before the mode registers, and writes
`$FF90` late. This codebase does neither:
- **`$FF90` FIRST** — framebuffers at `$8000+` are ROM territory until the CoCo3 all-RAM
  map exists, so nothing can be cleared before it.
- **Palette LAST** — palette writes do not latch until `$FF98`/`$FF99` hold their final
  values; indices render black otherwise.

Per CLAUDE.md §2, observed behaviour outranks documentation: the trace wins on fact, the
manual wins on intent.
*Established:* karateka `HAL_gfx_init` constraints A/B; carried into `HAL_gfx_set_mode` P2.5.

### 19g. Double-buffering lives in PHYSICAL RAM — there is no 64 KB wall
P2.5 recorded a worry that 16-colour double-buffering would need 60 KB of the 64 KB CPU
window. **That was wrong**, and the error was reasoning about the CPU's view instead of the
machine's. Framebuffers are addressed by the GIME's VOFFSET (`physical / 8`); the CPU sees
only an MMU-mapped window onto part of it. 512 KB is MAME's coco3 default — confirmed, not
assumed:
```
mame coco3 -listxml  ->  <ramoption name="512K" default="yes">524288</ramoption>
```
Place buffers AWAY from the default-mapped top 64 KB (`$70000-$7FFFF`): the CoCo3 boots
with CPU `$0000-$FFFF` mapped there, so a buffer placed in it overlaps the running program
(a program at CPU `$0200` is physical `$70200`). Map the BACK buffer at CPU `$6000` via
`$FFA3-$FFA6`; basing the window at `$6000` rather than `$8000` avoids `$FFA7` (CPU
`$E000-$FFFF`) and so never remaps the block the stack and vectors live in.
*Established:* P2.6.

### 19h. §2A.3 needed no ruling — idioms files are REFERENCE, not §2D authored docs
§2D reserves Orchestrator authorship for "decision records, post-mortems, behavioral
models." An idioms file is none of those: §2A.3 rule 3 explicitly instructs Clyde to add to
it, and this file's own history is seven Clyde commits (P1.0 → P1.3-fix). The "authorship
ruling" tracked as open from P1.1 was a phantom — the rule was already unambiguous. What
was real was the P2.1–P2.5 filing lapse. The counter is retired here; discovered idioms go
in this file, in the dispatch that finds them.
*Established:* P2.6 §2A.3 reconciliation.

---

## 20. Interrupt discipline for VBL-synced animation (P2.6)

### 20a. `HAL_sys_init` is step 0, and skipping it is an INTERRUPT STORM
The PIAs assert IRQ **independently of the GIME's `IRQENR`**. PIA0 `$FF01`/`$FF03` and PIA1
`$FF21`/`$FF23` bits 0-1 enable CA1/CA2/CB1/CB2 interrupts, and PIA0 fires on **horizontal
sync at ~15.7 kHz**. A handler that acknowledges only by reading `$FF92` never clears them,
so the CPU re-enters the handler immediately after every `rti` and the main program makes
essentially no progress.

**What it looks like, and why it costs hours:** the VBL path appears *healthy*. The frame
counter advances 1:1 with real frames. What fails is everything else. Measured — a graphics
clear loop that should take ~6 frames never finished, with **42% of sampled PCs in the ROM →
`$010C` dispatch path**. It reads as a hung graphics routine.

`HAL_sys_init` clears those bits (mask `$FC`) while IRQ is still masked, which is why it is
step 0 of the documented init order. karateka root-caused the identical failure in its
R-boot work: *"infinite interrupt loop at `$0226`, 833,172 times per 30 seconds in MAME."*
*Established:* P2.6, by skipping it and reproducing karateka's R-boot bug exactly.

### 20b. `HAL_time_vbl_wait` does NOT wait when `CC.I` is set
It takes a documented fallback (Q001 N3=β), synthesises a frame-counter increment and
returns immediately. A caller that leaves interrupts masked gets a swap loop running flat
out, flipping VOFFSET at arbitrary raster positions. **It compiles, it runs, the counters
advance, and it tears.** `HAL_time_init` deliberately does not clear `CC.I` (the E1.c
invariant: HAL init never changes the caller's mask state), so the caller must:
```asm
        jsr   HAL_sys_init      ; step 0 -- silence the PIAs (20a)
        jsr   HAL_time_init     ; install $010C handler, enable VBORD only
        andcc #$EF              ; CLEAR CC.I -- nothing else will do this
```
*Established:* P2.6.

### 20c. Polling `$FF92` requires ARMING VBORD first
`$FF92` latches VBORD only when the source is enabled (`$FF92 = $08`) and `IEN` is set in
`$FF90`. Polling without arming spins forever. This is the mirror image of 20a: one is a
source that fires and is never acknowledged, the other a source that never fires at all.
*Established:* P2.5 (the mode probe hung after stage 1), fixed by arming per checkpoint.

### 20d. MAME `natkeyboard` mis-delivers the SHIFTED double quote — INTERMITTENTLY
`nk:post('LOADM"ANIM"')` arrived at the DECB prompt as:
```
LOADMBANIMB
?SN ERROR
```
Each `"` came through as the letter **B**. Confirmed by dumping the text screen at `$0400`,
so it is keystroke DELIVERY — not the disk and not the filename (`ANIM.BIN` was present, and
the identical string loaded successfully in other runs **in the same session**).
Intermittent is worse than broken: it passes the automated run and fails the one with a
human waiting.

**For a LIVE visual gate, direct-load instead** — poke the DECB segments in and set PC. The
disk path proves nothing a human is judging, and removing the keyboard removes an
intermittent failure from the run that costs someone's attention. Keep `LOADM` in the
automated test, where a retry is free.
*Established:* P2.6, after two dead live runs Jay sat through before reporting the error.

### 20e. 6809 accumulator-offset indexing is SIGNED (not MAME, but it bites here)
In `leax a,x` the offset is two's-complement **−128..+127**. A 16-colour stride of 160 is
therefore **−96**, and the draw pointer walks BACKWARD out of the framebuffer and through
whatever precedes it. Measured: a probe completed one swap, then executed at `$6001` — it
had overwritten itself. Use `clra / ldb <value> / leax d,x` for a genuine 0..255
displacement, since `D` is 16-bit and the high byte is zero.
*Established:* P2.6.


---

## 21. The canonical BOOT CONTRACT — machine-config first, always (P2.8)

Three consecutive dispatches lost time to the same shape: **a probe hand-rolled its machine
bring-up and got the ordering wrong.** P2.5 hung (polled `$FF92` without arming VBORD), P2.6
stormed (skipped `HAL_sys_init`, so the PIAs interrupted at 15.7 kHz unacknowledged), P2.7
froze. They are one family, and the family has a cure.

### 21a. Every program runs the HAL's canonical boot, verbatim, FIRST
`hal.inc`'s INIT ORDER is the authoritative list, and it is seven steps:
```
0. HAL_sys_init         bare-metal: mask, $FF90, MMU, PIA IRQ disable
1. HAL_mem_size_detect  memory probe (stub today)
2. HAL_time_init        frame counter + $010C VBL handler + VBORD enable
3. HAL_gfx_init  /  HAL_gfx_set_mode(mode)
4. HAL_input_init       (stub)
5. HAL_sound_init       (stub)
6. HAL_file_init        (stub)
```
Do not hand-roll bring-up and do not reorder. `src/engine/boot.s` in karateka is the
reference implementation.

### 21b. Boot is LAYERED, which is why "boot differs per resolution" is a non-problem
- **Steps 0-2 are machine-establishment and RESOLUTION-INDEPENDENT.** Identical for every
  program that will ever run on this machine. Mandatory, first, before ANY memory, graphics
  or data access.
- **Step 3 is the only resolution-DEPENDENT step**, and it is already parameterised —
  `HAL_gfx_set_mode(mode)` takes the mode as an argument.
- **Steps 4-6 are peripherals**, invariant, after graphics.

So there is no ambiguity about "which boot": the part that must be identical everywhere is
identical everywhere, and the part that varies is one parameterised call that happens later.

### 21c. This is the proto-KERNEL BOOT CONTRACT
Read it as an OS boundary and it stops being a probe convention: **the kernel establishes
machine configuration — guaranteed, in a fixed order — before any program runs; programs
then REQUEST modes rather than configuring hardware.** Steps 0-2 are what a kernel does
before handing control to userland; step 3 is a syscall. That framing is worth carrying into
the single-source extraction, because it says which side of the boundary each step lives on.

### 21d. `sys.s`'s `$FF90=$4C` "unmaps ROM" comment — FLAGGED, NOT TRUSTED
`sys.s` states the postcondition *"$FF90=$4C ... ROM unmapped from $8000-$FEFF"*. Both
references disagree that `$FF90` does this:

| MC1 | MC0 | ROM mapping |
|-----|-----|-------------|
| 0 | x | 16K internal, 16K external |
| 1 | 0 | 32K internal |
| 1 | 1 | 32K external (except vectors) |

[ref: GIME_Reference_Manual.pdf §3 INIT0; SockmasterGime.md:24-38 — identical tables]

`$4C` = `0100_1100` → MC1=0, MC0=0 → *"16K internal, 16K external"*. There is **no all-RAM
setting in MC1:MC0 at all**; the CoCo3's upper-memory RAM/ROM choice is the SAM's
`$FFDE`/`$FFDF` pair, which `HAL_sys_init` does not write (`HAL_gfx_init` and
`HAL_gfx_set_mode` write `$FFDF` as their last step).

**Measured, and it complicates the picture rather than settling it:** a write/read-back
survey found `$0200`, `$3000`, `$6000`, `$7F00`, `$8000`, `$9000`, `$A000`, `$C000`, `$D000`
and `$D7FF` ALL writable RAM at the DECB prompt, *before* `LOADM`, *before* `HAL_sys_init`
ran at all. So on this target the `$8000-$FEFF` window is RAM-backed regardless, and nothing
observed depends on the comment being true.

The comment is **not corrected here**: it is a factual claim in the shared kernel about
machine behaviour, and the correct disposition is Jay's. Flagged with the evidence.

### 21e. A speed change is a schedule change — treat it as one
P2.7's freeze was bisected to an unrolled draw loop. P2.8 bisected further: replacing the
unroll's 16-bit stores with unrolled BYTE stores **still fails**, while the original rolled
byte loop **passes**.

| variant | speed | result |
|---|---|---|
| rolled byte loop | slow | PASS |
| unrolled `sta ,x+` x16 | fast | FAIL |
| unrolled `std ,x++` x8 | fast | FAIL |

The instruction form is irrelevant; the SPEED is the variable. An optimisation that changes
no observable output can still change *when* things happen relative to interrupts, the
raster, and any hardware with its own clock — and a latent race that was previously masked
by slowness becomes reachable. When a provably output-equivalent speedup breaks something,
stop looking for a coding error and start looking for the race it uncovered.
*Established:* P2.8. **RESOLVED P2.9** — the race was the MMU remap; see §22.


---

## 22. A multi-register hardware update is a CRITICAL SECTION (P2.9)

**The MMU remap must be atomic with respect to interrupts.** Writing the four MMU
registers that cover the draw window is a multi-step change to the CPU's memory map.
Between the first write and the last, the window is half one buffer and half the other —
a map that never legitimately exists. An interrupt taken in that gap runs against it.

```asm
gfx_map_blocks:
        pshs    cc                      ; save caller's mask state
        orcc    #$50                    ; mask IRQ+FIRQ -- remap is atomic now
        ldx     #GFX_DB_MMU
        ldb     #GFX_DB_BLOCKS
gfx_map_lp:
        sta     ,x+
        inca
        decb
        bne     gfx_map_lp
        puls    cc                      ; restore caller's CC exactly
        rts
```

**How it was found, because the path matters.** Three theories died before this one:
stack-clobber (P2.7, disproven — the stack was intact and already relocated),
ROM-residency (P2.8, disproven — every address measured writable RAM before the probe
ran), and then the bisection that reframed everything: unrolled BYTE stores failed as
badly as unrolled word stores while the rolled loop passed, so **the variable was SPEED,
not the instruction** (§21e). Speed-dependence means an asynchronous interaction, and the
only asynchronous thing present was the VBL interrupt. One decisive test — mask IRQ across
the draw — turned 22/23 into 27/27; a second, narrower test — mask ONLY the four MMU
writes — did the same, localising it exactly.

**THE DISCIPLINE ALREADY EXISTED IN THE CODEBASE.** `HAL_time_frame_count` masks IRQ
around its two-byte read of the interrupt-updated frame counter and is labelled a race
fix. Same rule, different resource: **the 6809 gives no atomicity across multiple
accesses, so anything the interrupt context can observe part-way through must be made
atomic by masking.** The counter needed it for a 16-bit READ; the MMU needs it for a
four-register WRITE.

**Always `pshs cc` / `puls cc`, never `orcc` / `andcc`.** Restoring the caller's condition
codes exactly preserves their mask state — a caller that had interrupts masked stays
masked. Hard-coding `andcc` to unmask silently enables interrupts in callers that
deliberately disabled them.

**Generalises beyond the MMU.** Any hardware state written across several instructions and
observable from interrupt context is the same shape: VOFFSET pairs, palette runs, MMU task
switches. If an interrupt can see it half-written, mask it.
*Established:* P2.9, after three disproven theories. Fixed in `gfx.s gfx_map_blocks`;
karateka unaffected (binary byte-identical, service gated off).

### 22a. The MMU registers `$FFA0-$FFA7` are **READABLE** — so a borrow can save/restore (P4.25)

**A routine that needs the window for a moment does not have to know what was there.** The
Task-0 bank registers read back the block they hold, so the shape is the ordinary one:

```
                lda     $FFA6
                anda    #$3F            ; the top two bits are NOT part of the answer
                sta     save
                ...borrow the window...
                lda     save
                sta     $FFA6
```

**Ground truth, not inference:** *"These registers can also be read to determine what
palettes are set but **like the MMU registers, the upper 2 bits must be masked out**"*
[`docs/ground-truth/SockmasterGime.md:243`; the same file lists `$FFA0-$FFA7` as the Task-0
bank registers at line 188]. A block number is six bits, so masking is what turns the read
into a value; the GIME ignores bits 6-7 on the write back either way.

**WHY IT MATTERS HERE.** `$FFA6/$FFA7` are HAL-private while anything is drawing — `gfx.s`
says a caller must never learn a buffer address — but `intro_seq.s cel_preload` has to point
them at the cutscene's cel bank for eight track reads and then hand them back. Reading them
is what lets it do that **without importing a HAL-private constant.** Verified end to end by
`harness/tools/preload_fb_diff.lua`, which diffs the whole 32,256-byte draw window across the
borrow: **0 bytes differ.**

**★ THE OTHER HALF OF THE RULE, WHICH IS NOT SYMMETRIC:** `$FF90-$FF9F` are a different
story — §20c already records that `$FF92` needs VBORD *armed* before a poll means anything,
and `SockmasterGime.md:78` says the timer registers are write-only outright. **"GIME
register" is not one readability class.** Check the register, not the chip.

**★★ AND A SAVE/RESTORE IS NOT ALWAYS THE ANSWER:** `HAL_gfx_swap` ends in
`gfx_map_blocks`, which rewrites **all four** window registers unconditionally, so anything
holding a borrowed mapping across a flip loses it — that is P3.68, and it is why
`cutscene_room.s` wraps the swap in `room_present` rather than re-mapping at each call site.
Save/restore covers a borrow **between** frames; it does not survive one.

*Established:* P4.25. Tool: `harness/tools/preload_fb_diff.lua`.

---

## 23. `LOADM` at `$0200` dies as soon as it needs a SECOND granule (P3.3)

**DECB's own storage lives at `$0600`, and a program loading at `$0200` runs straight
through it.** Disk BASIC zeroes `$0600-$0989` at init and keeps `DBUF0=$0600`,
`DBUF1=$0700`, the **FAT RAM at `$0800`** and the **FCBs at `$094A`** there.
[`karateka_coco3 docs/project/decb-loadm-boot-gates.md`, from *Disk Basic Unravelled II*]
A granule is 2,304 bytes, so a load at `$0200` fills `$0200-$0AFF` on its FIRST granule —
taking out all four while `LOADM` is still using them. DECB then cannot follow the chain
to granule 2 and raises **`?FS ERROR`**, having loaded nothing usable.

**Measured, not inferred** (three cases, one conclusion):

| file | load address | granules | result |
|---|---|---|---|
| `PROBE`/`MODE`/`ANIM` (798–980 B) | `$0200` | 1 | **loads** |
| 6,912 B synthetic | `$0200` | 3 | `?FS ERROR` |
| the SAME 6,912 B file | `$4000` | 3 | **loads** |

So it is **not a size limit and not a `.dsk` capacity problem** — same file, same disk,
same granule count, different destination. The single-granule programs work only because
they stop below `$0600`.

**The consequence for POP:** every engine screen is far past one granule (`INTRO.BIN`
27,674 B, `INTROSEQ.BIN` 29,495 B), so **no engine program can be `LOADM`ed today.** Both
were run by parsing the DECB segment table in Lua, poking the bytes in and setting PC —
`build/introrun.lua` (P3.2) and `harness/smoke/introseq_test.lua` (P3.3). **A capability
gated by Jay's eye on a poked image says nothing about the disk path.**

**The fix is Karateka's and is already written.** `karateka_coco3 src/boot/bootloader.s`
runs from framebuffer space (`$8000+`, boot-dead), masks IRQ+FIRQ first, takes its own
stack at `$7F00`, replicates the MMU setup, raw-reads whole tracks into low RAM through
`disk_read.s`, and `jmp`s the game entry — never returning to BASIC, which is what makes
the clobbered `$01xx` vectors inert. Entered by **`LOADM"BOOT":EXEC`**: `LOADM` does
`STD EXECJP`, and bare `EXEC` jumps through it, so a single-granule stub is all DECB has
to survive. **Porting it is a POP task in its own right** (§2G copy-and-adapt), and is the
gate on any disk-resident engine screen.

*Established:* P3.3, after bisecting sizes/granules/addresses — the answer was in
Karateka's already-written gate doc, and Jay named it.

---

## 24. MAME writes `.dsk` images back — mount a COPY, never the built artifact (P3.3)

**MAME opens a floppy READ-WRITE and JVC saves back** (§3 already says the format is
writable; this is what that costs). A guest that touches the disk, or an exit taken
mid-FDC-operation, **rewrites the file the build produced.** In P3.3 a run of diagnostic
sessions against `build/probe.dsk` left it reporting **`Corrupt image`** to `imgtool`, and
`run_probe_test.sh`, `run_mode_test.sh` and `run_anim_test.sh` all failed at once — with
nothing wrong in any of them, and nothing wrong in the code they test. A rebuild "fixed"
it, which is exactly the shape that reads as flakiness.

**The rule was already standing** — §3: *".dsk fixtures are gitignored / throwaway —
generate per-task, don't share."* The fix is to enforce it in the runner instead of
remembering it: every `run_*_test.sh` now does

```bash
SRC_DSK="build/probe.dsk"          # the built artifact — never mounted
DSK="build/run_<test>.dsk"         # the scratch copy MAME may do as it likes with
cp -f "$SRC_DSK" "$DSK" || exit 1
```

and `/build/` is gitignored, so the scratch images cost nothing. **Verified:** the suite's
`md5` of `build/probe.dsk` is now identical before and after a full run.

**The tell to recognise next time:** several unrelated disk-loading tests failing
*together*, and a rebuild clearing it. That is the fixture, not the code.

*Established:* P3.3.

---

## 25. `lwasm -D` takes a C literal — `-DSYM=$1F00` silently defines SYM as ZERO (P3.4)

**No warning, no error, exit 0.** lwasm's `--define` parses a C-style literal, so a
`$`-prefixed hex value is accepted and evaluates to **0**. Measured three ways on the
same source:

```
-DDR_VARBASE=$1F00   ->  dr_status equ 0004     WRONG (base = 0)
-DDR_VARBASE=0x1F00  ->  dr_status equ 1F04     right
-DDR_VARBASE=7936    ->  dr_status equ 1F04     right
```

`$` is correct **inside** the source and wrong **on the command line** — which is
exactly the kind of inconsistency that survives review, because every other hex
number in the project is written `$`.

**What it cost:** POP passes one `-DDR_VARBASE` to both the kernel and the engine so
caller and primitive agree on where the disk primitive's parameter block lives. With
the value silently 0, *both* agreed on `$0000` — inside the HAL's DP scratch band
(`$00-$07`). The first disk read after any HAL call therefore read a track number
some other routine had overwritten, and failed with **RNF** — a completely plausible
disk error pointing nowhere near the actual fault.

**Check it, do not trust it:** `lwasm --list=x.lst` and read the `equ` back. A
symbol that should be `$1F00` and lists as `0000` is this bug.

*Established:* P3.4.

---

## 26. RELEASE THE DRIVE after every transfer — the primitive does not (P3.4)

`disk_read.s` disarms HALT at the end of each track but leaves the **drive selected
and the motor running**. That is harmless for the caller it was written for —
karateka's `bootloader.s` loads the game and `jmp`s into it, so nothing of the
loader's ever executes again — and **fatal for a caller that returns**. POP's intro
returns to a normal VBL loop with interrupts enabled; several seconds later the CPU
derailed with `S=$0000` and a free-running PC, in rendering code that never touches
the disk.

**The fix is one instruction at the I/O-CALLER layer**, where the speed bracket
already lives (§8):

```asm
lt_ok   clr     DSKREG          ; motor off, no drive selected, HALT disarmed
        sta     SAM_FAST        ; ... then restore speed
```

**The oracle does exactly this, explicitly, and always.** Every load in `MASTER.S`
is bracketed `jsr driveon` … `jmp driveoff` — `LoadStage1A`, `LoadStage1B`,
`LoadStage2A/B`, `LoadStage3`, `ReloadStuff`, `loadch7`. That housekeeping reads as
boilerplate when you are reading the original for structure, and it is the answer to
a bug you have not hit yet.

**The general shape:** a resource-acquiring routine written for a fire-and-forget
caller carries an implicit "and then the process exits" in its contract. Ask of any
inherited primitive not "is it correct" but **"what did its previous caller do next,
and am I doing that?"**

*Established:* P3.4. *Candidate:*
`a-primitive-proven-where-nothing-returns-leaks-state`.

---

## 27. Recording the port's output: `-aviwrite` is UNCOMPRESSED — transcode it (SQ-1)

**MAME's `-aviwrite` works and its AVI is valid, but it is uncompressed 24-bpp DIB:
about 27 MB per emulated second** (715 MB for a 26-second intro). It also lands in
the **`snapshot_directory`** (default `snap/`), not the path you passed — `ls` in the
working directory says "no file produced" when the file exists.

**`-nothrottle` does NOT distort the recording.** MAME writes one AVI frame per
EMULATED frame at the emulated refresh rate, so an unthrottled capture produces a
correctly-timed video and finishes ~8× sooner. (Distinct from the §6 caveat, which
is about *sampling* a moving image at arbitrary points; capturing every frame has
no such problem.)

**ffmpeg is installed** (`winget install Gyan.FFmpeg`, 8.1.2; binary under
`%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg_*\ffmpeg-*\bin\`). The recipe:

```bash
mame coco3 ... -nothrottle -aviwrite raw.avi -autoboot_script <live>.lua
ffmpeg -i snap/raw.avi \
  -vf "select='between(n,FIRST,LAST)',setpts=N/FRAME_RATE/TB,scale=1280:944:flags=neighbor" \
  -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -profile:v high \
  -aspect 4:3 -movflags +faststart -an out.mp4
```
578 MB → **827 KB**, PSNR 59 dB (luma 72 dB — essentially exact).

**THE RAW FRAME IS NOT SQUARE-PIXEL.** `-aviwrite` emits the screen bitmap, 640x236,
which is **2.71:1** — but a CoCo3's full NTSC raster, borders included, is **4:3**.
Encode the raw dimensions and it plays back badly squashed: a defect no amount of
codec or container checking will surface, because the file itself is perfect.

The fix is integer scaling PLUS aspect metadata, so it survives a player that
honours either one:
- **x2 horizontal, x4 vertical -> 1280x944.** Integer factors keep the pixels hard
  (`flags=neighbor`), and 1280x944 is **1.356:1** — only **1.7% off 4:3**, so a
  player that ignores the aspect flag is imperceptibly wrong rather than broken.
- **`-aspect 4:3`** sets SAR 59:60 / DAR 4:3 for a player that honours it.

Vertical x3 (1.81:1) and x5 (1.09:1) are 36% and 19% out. **x4 is the only usable
integer factor.**

**Two more settings that are not arbitrary:**
- **`scale=…:flags=neighbor` to 2× BEFORE encoding.** The coco3's 320-pixel mode is
  emitted at 640 wide, so 4:2:0's *horizontal* chroma halving is free — but its
  *vertical* halving is not, and it smears exactly the NTSC fringe colour the
  display-faithful conversion exists to reproduce. Doubling both axes first puts
  the subsampled chroma back at the source's own resolution. `neighbor` keeps the
  pixel art hard.
- **`yuv420p` + `high`, not 4:4:4.** Compatibility is the whole point (see below).

**THE TRAP THIS COST A ROUND-TRIP: Windows ships no MJPEG decoder.** Before ffmpeg
was installed, the AVI was re-encoded as MJPEG — structurally valid, every frame
decodable, verified by re-parsing — and Media Player/Photos **opened it, found no
decoder, and closed with no video.** *Validating the container proves nothing about
whether the target can play the codec.* On a stock Windows box: **H.264/mp4 and
uncompressed DIB AVI play; MJPEG AVI does not.**

**GIF is a serious option for this content, not a fallback.** A CoCo3 16-colour
screen has ~16-19 distinct colours in the whole recording, so GIF is **lossless**
(verified byte-identical, all frames), and an intro that holds still between page
flips has ~13 distinct images in 15 s — 915 frames became **39 GIF frames, 73 KB**,
against 103 MB of MJPEG. GIF's 10 ms delay granularity costs 20 ms of drift across
15 s, because the holds are seconds long. Use it when the target might not have a
video codec, or when the artifact needs to be small.

### 27a. Recording the WHOLE run: segment it from Lua, and the keyframe interval is the lever

**Three findings from capturing the port end to end (10,357 frames, 2:52).**
Tools: `harness/tools/capture_run.lua` + `harness/tools/encode_run.sh`.

**(1) `video:begin_recording()` / `end_recording()` exist in Lua — so segment from one boot.**
At 27 MB/emulated-second the full sequence is **4.5 GB**, past what one RIFF file should be
asked to hold. `manager.machine.video` exposes `begin_recording(name, "avi")`,
`end_recording()` and `is_recording` (enumerate its metatable if in doubt), so the run is cut
into fixed-frame files from **one** boot — which also means one deterministic timeline, so the
segments join exactly and ffmpeg's `concat` demuxer stitches them into a single encode.
Starting the recording *after* `LOADM`+`EXEC` also never writes the ~20 s of black BASIC
prompt at all — cheaper than trimming 550 MB of it afterwards.
**End where the PROGRAM ends**, not at a guessed frame: watch `probe_status` (`$2003`, from
`build/obj/introseq.map`) reach `BEAT_COUNT+2` and stop a tail later.

**(2) ★★★ THE PERIODIC KEYFRAMES WERE 56% OF THE FILE.** One 2,700-frame segment, crf 23 fixed:

```
 -g 250 (x264 default)   960 KB   11 keyframes
 -g 600                  570 KB    6
 -g 1200                 422 KB    4
 -g 3000                 284 KB    1
```

The artwork is converted Apple II DHR, so **every still frame is full of dither detail and an
I-frame of it is expensive** while the P-frames between are nearly free. Scene-cut detection
still inserts an I-frame where the picture actually changes, so raising `-g` costs **0 dB** —
only seek granularity. By contrast the CRF sweep on the busiest segment ran 1,048 KB (crf 18,
50.9 dB) to 723 KB (crf 28, 42.2 dB): a third of the size for 8.7 dB. **Reach for `-g` first.**

`-tune animation` also earns its 4%: 850 KB at 46.4 dB against 816 KB at 44.0 dB untuned.
`stillimage`, `film` and `deblock=-3,-3` were all worse on both axes.

**(3) 640x472 IS CHROMA-EXACT — §27's 1280x944 is one doubling more than this source needs.**
MAME emits 640x236 for a 320-pixel mode, so a source pixel is already **2 luma px wide and 1
luma row tall**. Output 640x472 (x1 horizontal, x2 vertical) has a yuv420p chroma plane of
320x236 — **exactly one chroma sample per source pixel on both axes.** 1280x944 gives two,
which is redundant rather than safer. Same 1.356:1, same `-aspect 4:3`, and the luma is 1:1
horizontally so the pixels cannot get softer than the source.

**Result:** 4.5 GB raw → **2.72 MB** (video 57 kbps + mono AAC 64k), **mean PSNR 48.2 dB luma,
worst single frame 43.0 dB** over all 10,361 frames. Silent: **1.25 MB**.
★ **On near-static content the SOUNDTRACK is the file** — 1.39 MB of the 2.72.

### 27b. ★★★ MAME's coco3 AUDIO: 3 channels of which ONE is live, and it carries a DC offset

**A capture that shipped with an inaudible soundtrack, and every check it passed was a check
of the wrong thing** — `ffprobe` showed an AAC stream, the stream was full-length, it measured
−15 dB RMS. Three faults, compounding:

1. **MAME records the coco3 as 3 channels and only `c0` carries signal.** `c1`/`c2` are
   digital silence (RMS −inf). **`-ac 1` AVERAGES them**, so the audio was silently divided
   by three — **−9.5 dB**. Use `pan=mono|c0=c0`, never `-ac 1`.
2. **`c0` carries a large DC offset** — measured **−0.2487** of full scale, i.e. −12 dB of
   pure 0 Hz, against music at about −30 dB. **18 dB of inaudible DC sitting on top of the
   thing you want**, which is exactly why the RMS looked healthy. `highpass=f=20` clears it
   (measured DC after: 0.000023).
3. **AAC then spends its budget coding the DC.** The 32k mono encode came out with a noise
   floor of −35 dB against music at −30 dB — **a 5 dB SNR where the source has 20 dB.**

**THE SIGNATURE, so it is recognised in one glance: a level that does not MOVE.** RMS was
flat at −15 dB for all 173 seconds. Real audio has silence in it — the fixed capture reads
−91 dB over the loading screen, −21 to −33 dB through the music, −91 dB again over the final
hold. *Measure the level in windows across the run and look for variation; a constant level
is the DC-only tell.*

**Also:** measure the peak over the **whole run**, not a sample — a gain taken from a 30 s
window decoded at **+1.4 dBFS** (clipped), because AAC overshoots transients here by ~2.4 dB.
And `-nothrottle` does **not** corrupt the audio: a throttled and an unthrottled capture of
the same window were **byte-identical**, which extends §27's claim from video to sound.

★ **The lesson is §27's own MJPEG trap one level down: validating the CONTAINER proves
nothing about the CONTENT.** "There is an audio stream, it is the right length, and it has a
healthy RMS" is three container facts and zero audible ones. `encode_run.sh` now prints the
DC offset and a windowed level trace after every encode, so the check travels with the tool.

*Established:* SQ-1 (§27), extended at the P5.1 capture.

---

## 28. Typing `EXEC` overwrites the program you just `LOADM`ed — $02DC is the line buffer (P3.5)

**Color BASIC's line-input buffer is at `$02DC`.** `LOADM` places the program; the
operator then types `EXEC` to start it; **DECB stores those keystrokes in the
buffer, on top of the program that was just loaded there.** Caught on the bus, with
the writing PC inside the BASIC ROM:

```
f708  $02DD <- $45   'E'    from DECB, PC=$A3E7
f717  $02DE <- $58   'X'
f726  $02DF <- $45   'E'
f735  $02E0 <- $43   'C'
```

`$02DD` was `sta probe_phase`; `$02E0` was `ldx seq_beat`. **The command that starts
the program corrupts the program.**

**THREE REGIONS A `LOADM`+`EXEC` PROGRAM MUST CLEAR** — this one completes the set:

| range | owner | when it bites |
|---|---|---|
| `$02DC-$03D5` | line-input buffer | typing `EXEC`, i.e. AFTER the load |
| `$0400-$05FF` | text screen | DECB prints `OK` |
| `$0600-$09FF` | DBUF0/DBUF1/FAT/FCBs | during `LOADM` itself (§23) |

POP's engine now links at **`$2000`** (`link/pop_engine.link`) — above all three and
below the graphics pages' end at `$25FF`. The P1.x probes keep `$0200`: they are
pinned there by the harness contract and are small enough to stop below `$02DC`.

**WHY IT IS VICIOUS.** Whether it matters depends on which instructions happen to
sit under `$02DC`, so it is **layout-sensitive**: adding four bytes of diagnostic
changes the symptom or hides it, and successive builds produce mutually
contradictory measurements that read as flakiness. Across P3.4/P3.5 the same
program showed correct timing with nonsense status bytes, sane status bytes with
collapsed timing, a hang, and a clean run.

**AND IT IS INVISIBLE ON THE POKED PATH.** P3.2/P3.3 and `introseq_live.lua` wrote
the image in from Lua and set PC — nothing types `EXEC`, so nothing is corrupted.
That is exactly why Jay watched the sequence run correctly while the automated test
reported it broken: **the two used different launch paths, and the fault was in the
path, not the program.** When a human's observation and a test disagree, compare
what each one LAUNCHED before theorising about the code.

**The tell, which was visible early and explained away:** an instruction that
provably executed followed by one that provably did not, in straight-line code with
no branch between them. That is never a logic bug — it means the bytes are not what
the source says. Read the memory, not the control flow.

*Established:* P3.5. *Candidates:*
`when-human-and-test-disagree-ask-what-each-one-launched`,
`a-layout-sensitive-fault-makes-the-diagnostic-part-of-the-experiment`.

---

## 29. Ship DMK with SEQUENTIAL interleave — JVC costs 2.5× (P3.6)

**MAME's `coco_jvc` container has no physical sector order to preserve**, so MAME
synthesises one — and the one it picks is near-pessimal for a whole-track read.
Measured on POP: **3.31 s/track**; karateka independently: **3.33 s/track**. Both
≈ **0.89 revolutions per SECTOR**, where a whole track should cost about one.

**DMK preserves the authored order, and imgtool authors it:**

```
imgtool create coco_dmk_rsdos <img> --tracks=35 --sectors=18 \
        --sectorlength=256 --interleave=0
imgtool writesector coco_dmk_rsdos <img> <track> 0 <sector> <file>
```

**INTERLEAVE 0 = SEQUENTIAL = FASTEST, which inverts the RS-DOS convention.** The
usual reason to spread sectors is to give a sector-at-a-time reader time to breathe.
A HALT-paced `m=1` Read-Multiple reads the whole track under ONE command and keeps
pace inside it, so it wants the next sector to be the *next* sector; any spread
costs a revolution. karateka swept it and the time rises monotonically — il=0:
10.66 s, il=1: 12.27, il=9: 25.07, il=13: 31.46 (worse than JVC).
[`karateka_coco3 docs/project/interleave-realization-mame.md`]

**POP's measured result** (three reads: 1-track bundle + 7-track screen ×2):

| read | JVC | DMK il=0 | |
|---|---:|---:|---:|
| bundle (1 track) | 5.2 s | 3.1 s | 1.68× |
| screen (7 tracks) | 23.2 s | 9.2 s | 2.52× |
| screen (7 tracks) | 23.0 s | 9.0 s | 2.56× |
| **to first frame** | **51.4 s** | **21.3 s** | **2.41×** |

Per-track **3.31 s → 1.31 s**, against karateka's 3.33 → 1.33. Byte-for-byte
identical throughout (5/5 screens). A **~6 rev/track wd_fdc floor remains** that
interleave cannot touch, so shippable perceived time still wants load-masking.

**Two free consequences:**
- **`raw_tracks.py` can no longer compute byte offsets.** JVC is linear
  (`(T*18+S-1)*256`); DMK is raw tracks with IDAM/DAM/gaps/CRCs. Place payload with
  `imgtool writesector` by logical id — the read side is unchanged, the primitive
  still asks for ids 1..18.
- **DMK is READ-ONLY in MAME's floppy layer** (§3), so §24's write-back hazard
  disappears: verified, the built image's md5 is unchanged across a full suite run
  and MAME never rewrites the scratch copy either. The scratch-copy rule stays as
  belt-and-braces.

**AND THE SPEEDUP EXPOSED A LATENT HARNESS RACE.** Posting `EXEC` the instant the
image verifies is not safe: the segment check only says the BYTES are in memory,
while DECB may still be finishing the LOADM and getting back to its prompt, and a
keystroke posted into that window is **dropped** — Jay watched the first `E` of
`EXEC` get eaten. The slow JVC load had been hiding it by leaving DECB idle before
the check passed. `anim_test.lua` now settles 90 frames after the image lands and
requires `nk.empty` before posting. **A load-time change is a harness-timing change.**

*Established:* P3.6.

---

## 30. Keypress-to-start is live from the FIRST intro screen — it lives in the HOLD primitives (P3.7)

**`StartGame?` has exactly two call sites, and both are hold primitives:**
`PlaySongI` (`MASTER.S:1400`) and `tpause` (`MASTER.S:1417`). Every intro beat holds
with one or both, so the keypress check runs during **every** beat — starting with
`PubCredit`'s first `tpause 44`, while the Brøderbund splash is on screen and before
any caption appears.

**Confirmed on the running oracle, not left at the source** (CLAUDE.md §2 ranks the
trace higher). Keypress posted at f350, during that first hold:

| | no key (P3.3/P3.4 baseline) | key at f350 |
|---|---|---|
| first disk activity after f196 | f2581 | **f356** |
| next screen change | f405 ("Presents" in) | **f357** (blackout) |

The intro aborts and `DOSTARTGAME` runs — `blackout`, `LoadStage3`, `set1stlevel`.

**The reading to avoid:** `MASTER.S:993` is where `StartGame?` is *defined*, which
sits after `TitleScreen` in the file and makes it look like a late-attract check.
Where a routine is defined says nothing about when it runs. **Grep for the callers,
not the label.**

**Scope for future input work:** polling belongs at the SEQUENCER's hold, not
per-beat — one check inside `hold_frames` covers every beat exactly as the oracle's
does, because the oracle put it in the equivalent place. No input is built yet.

*Established:* P3.7 (source + running-oracle confirmation).

---

## 31. The title screen is a CAPTION, not a picture — read the call, not the comment (P3.7)

`MASTER.S:823` reads `* Unpack title onto page 1` and the next two lines are:

```
 lda #delTitle
 jsr DeltaExpPop
```

**`delTitle` is a `del*` blob** — the same family as `delPresents` and `delByline` —
expanded by `DeltaExpPop`. It is NOT `pacSplash`/`DblExpand`, which is what
`unpacksplash` actually uses for a whole picture. The two identifier families are
the structural evidence:

```
pac*  whole images   pacSplash $40  pacProlog $7c  pacSumup $60  pacProom $84
del*  patches        delPresents $70  delByline $72  delTitle $74
```

**`SilentTitle` settles it beyond argument:** it calls `unpacksplash` + `copy1to2`
FIRST and only then `DeltaExpPop delTitle`. Loading a base picture before applying
the title would be pointless if the title *were* a picture.

**So the intro is one screen with THREE captions**, not three screens. The title's
descriptor is `track 0` (inherit) exactly like Mechner's; it is simply much bigger —
5,909 B against 885 and 687, 229 runs, rows 102-188, and ~6 frames to draw against
well under one.

**Two consequences that bit:**
- **A big patch has to pay its draw out of the hold.** The captions draw in under a
  frame so their `BEAT_PRE` *is* the measured interval; the title needed
  `118 - 6 = 112` to land on the oracle's frame. Same +1 drift as the others after.
- **The save buffer must hold the LARGEST patch, not the last one** — 5,361 pixel
  bytes, not 747.

**The general rule:** a comment names the author's INTENT, the call names the
MECHANISM, and a port needs the mechanism. Greps surface comments preferentially,
because comments contain the words humans search for — so the evidence most easily
found is the evidence least likely to be authoritative.

*Established:* P3.7. *Candidate:*
`a-comment-names-the-intent-the-call-names-the-mechanism`.

---

## 32. The intro's beats escalate in KIND — captions, own-picture screens, then a cutscene (P3.8)

The oracle's intro looks like one list of screens. It is three different mechanisms,
and the identifier families give it away before any tracing does:

| beat | mechanism | blob | what it is |
|---|---|---|---|
| Brøderbund / Mechner / Title | `DeltaExpPop` | `del*` | **captions** over one shared picture |
| Prolog1 / Prolog2 | `DblExpand` | `pac*` | **own full pictures** (double hi-res) |
| PrincessScene | `SngExpand` + `xplaycut` | `pacProom` | **a cutscene** — a subsystem |

`PrincessScene` is where a beat dispatch has to stop, and not marginally:
`cutprincess1` calls `LoadStage2` (the game's `bgtab1-2`/`chtab4`), unpacks with
**`SngExpand` — SINGLE hi-res, a different video mode** — and hands off to
`xplaycut`, the scripted player that also drives the game's cuts #1/#6/#7.
**Different unpacker, different mode, game tables, animation subsystem.**

**Two mechanism details that change what the port must do:**

- **`Prolog1` WIPES IN over ~100 frames; `Prolog2` appears INSTANTLY.** Neither is a
  flip. `Prolog1` calls `DblExpand` while its page is displayed, so the unpack is
  visible; `Prolog2` unpacks FIRST and calls `setdhires` after, so the switch reveals
  a finished picture. A port that flips matches `Prolog2` exactly and cuts where the
  oracle wipes.
- **`ReloadStuff` is NOT the title's problem.** `MASTER.S:862` is inside
  `PrincessScene`: the Apple's dhires *pages* (`$2000-$5FFF`) sit on the crunch
  store, so the titles eat their own source data. POP's framebuffers are banked
  physical RAM outside the 64 KB map — nothing to reload.

**A capability the mechanism "supports" but has never run is not yet a capability.**
The beat descriptor had carried an own-base field since P3.3 and it was correct —
but no beat had set it, and the first that did found the caption path running
unconditionally, ready to walk memory from `$0000` on a null patch pointer. First
real use is where untested support gets tested.

**And a base-only beat must read its picture ONCE.** The second read exists only so
the caption repair has a clean hidden copy; with no caption there is nothing to
repair. Reading twice cost **18 s** of stall per prologue screen instead of 9 s.

*Established:* P3.8. *Candidate:* `a-sequence-escalates-in-kind-not-just-in-content`.

---

## 33. The static intro closes at `SilentTitle`; `jmp Demo` is the intro→engine boundary (P3.9)

The attract flow ends
`… → Prolog2 → SilentTitle → jmp Demo`, and **`SilentTitle` is the last beat the
caption/picture mechanism can express.** Past it lies the engine.

**The reprise is beat 1's shape, and for the oracle's own reason.** `SilentTitle`
(`MASTER.S:808`) is `unpacksplash` + `copy1to2` **first**, *then* `DeltaExpPop
delTitle` — where `TitleScreen` (beat 3) just applied the caption to the splash
already resident. The prologue pictures have overwritten it by then, so the reprise
re-establishes its own base. Same visual as beat 3, different route; **verified
byte-identical framebuffers** despite that.

**The oracle batch-loads; POP does NOT — do not carry the oracle's cadence across.**
P3.4 traced the oracle holding its whole compressed stage resident (§P3.4). POP
deliberately inverted that: the screen picture lives **on disk and nowhere else**,
read straight into the framebuffer for **0 bytes resident**. Only the captions are
resident (the bundle). So "re-compose from resident data" is true of the oracle and
false of POP: the reprise **re-reads tracks 27–33**. Two different machines, two
different answers, and the oracle's is not automatically the port's.

**WHERE `Demo` STOPS BEING A BEAT:** it is attract *gameplay* — the animation
player and level tables, the same subsystem `PrincessScene` needs (§32). Nothing
past `jmp Demo` is expressible as a descriptor row.

**The stall this leaves:** beat 6 re-reads the splash **twice** (caption beats need
both buffers) — ~18 s, the largest single stall in the intro, immediately before the
final title. Prefetching during the preceding hold is the fix and needs a
non-blocking read.

*Established:* P3.9.

---

## 34. An invariant in a comment decays silently when an optimisation narrows it (P3.9)

`intro_seq.s` stated: *"on entry to every beat and on exit from every beat, BOTH
buffers hold the clean base image."* True when written, and the reason later beats
could inherit instead of re-establishing.

**P3.8 made it false and nothing broke.** Base-only beats began reading their
picture once instead of twice (halving a 9 s stall, correct and deliberate), so they
leave the *previous* screen on the hidden buffer. No beat had yet tried to inherit
from one, so there was no failure — and the comment went on asserting the
unqualified rule.

**P3.9's plan was written from that comment** and reasoned the new beat could
re-compose from state already in place. It could not: the prologue owns both
buffers. The prescribed mechanism happened to be right for a different reason, so
the error was invisible without checking the plan against the code.

The statement now reads: **both buffers are clean after every CAPTION beat**, and a
beat may only inherit from a caption beat.

**The rules:**
- **Narrow the statement in the same change that narrows the invariant.** One line,
  and nearly unrecoverable afterwards.
- **An invariant with no current violation is still weakened** — its value is
  entirely in what gets built on it later.
- **Prose invariants have no failing test.** Everything else in the file is checked
  by something; the header is checked by nobody. Treat a plan derived from a comment
  as a hypothesis.

*Established:* P3.9. *Candidate:*
`an-invariant-in-a-comment-decays-silently-when-an-optimisation-narrows-it`.

---

## 35. The GIME masks block numbers to installed RAM — 128 KB aliases mod 16 (P3.10)

**A block number is not an address; it is an index the GIME masks to the RAM that
is actually fitted.** On a 128 KB CoCo3 only blocks `$00-$0F` exist, so every number
aliases **mod 16** — and a layout that is correct on 512 KB can put two things on top
of each other on 128 KB with no warning:

| | assigned | 512 KB physical | 128 KB alias | |
|---|---|---|---|---|
| CPU map (`sys.s` sets `$FFA0-$FFA7`) | `$38-$3F` | `$70000` | `$08-$0F` | |
| buffer A | `$10-$13` | `$20000` | `$00-$03` | ok |
| buffer B **(was)** | `$18-$1B` | `$30000` | `$08-$0B` | **on the program + kernel** |
| buffer B **(now)** | `$14-$17` | `$28000` | `$04-$07` | ok |

**The symptom was silent:** on 128 KB the port `LOADM`ed fine, started, reported
`status=0`, and then never advanced — dead at the first framebuffer access, with no
error anywhere. `-ramsize 128K` is a one-flag test and worth running on any layout
change.

**VOFFSET follows the same masking.** `GFX_DB_B_VOFF` is `physical / 8`
(`$28000/8 = $5000`); on 128 KB the GIME masks the video address exactly as it masks
the block number, so the displayed buffer stays consistent with the mapped one.
Verified by the screens being byte-identical at both sizes, not by argument.

**What 128 KB leaves free.** 16 blocks: 4 for the low 32 KB (program, kernel, stack,
runtime data), 4 for buffer A, 4 for buffer B — **12 used, 4 free = 32 KB**, which
is exactly one 30,720-byte screen. Enough to bank the splash (read four times today)
and remove three of the intro's seven disk reads.

**`MAME_RAM=128K` now runs any `run_*_test.sh` at 128 KB.** Verified at both sizes:
probe, mode, anim, and the full six-beat intro (16/16 checks, 11/11 screens
byte-identical).

*Established:* P3.10.

---

## 36. `cp` is the WRONG way to mirror a sync-bridged HAL file (P3.10)

The bridge reports *"HAL source aligned … EOL/guard/export-placement normalised"*.
**Normalised is not identical.** POP's `gfx.s` and karateka's differ by six `export`
lines — karateka exports the blit-sprite entry points, POP keeps them dormant behind
a guard — and the bridge is written to look past exactly that.

So copying POP's file over karateka's to propagate a two-constant change **deleted
those exports** and karateka's build died with six
`Undefined symbol HAL_gfx_blit_sprite`. The bridge still said OK, because the copy
had made the files *more* identical than they are supposed to be.

**Mirror by applying the same EDIT to both files, never by copying one over the
other.** `git checkout` the clobbered file, re-apply the change, rebuild the sibling,
and check its prod SHA — `88eba89b15cdf17c8d25e082d2d3e1f3cce57d38` here, byte-identical,
which is what proves the change is inert on that side.

(P3.4's `disk_read.s` mirror was a `cp` and was *safe* only because that file had no
divergence yet. The technique was wrong both times; the first one got away with it.)

*Established:* P3.10.

---

## 37. A harness gate keyed to a disk-read COUNT is a proxy, and optimisations move it (P3.11)

`introseq_test.lua` captures the framebuffer at chosen moments. The moment it wanted
was *"the base picture is on the visible page"*. What it actually said was:

```lua
{ st = 2, ph = 0, tag = "1_base", loads = 2 },   -- bundle + the one splash read
```

The read count was a stand-in. It worked because beat 0 read the splash, and the
capture landed after the read that preceded the page flip.

P3.11 put the splash in a RAM bank, so the beat reads it once instead of twice. The
count still reached its threshold — one read earlier, **before `HAL_gfx_swap`**. The
harness dumped the visible page, which was still the cleared buffer, and reported

```
FAIL base screen == converted splash, centred: 22209 bytes differ; first at row 0 col 10
```

with all 16 in-emulator checks green. The engine was correct; the picture was
correct; **the failure named an asset, and the defect was in the clock the test read.**

**Gate on the state you mean.** The HAL already exports a swap counter, so the
condition *"a page flip has happened"* is directly observable:

```lua
{ st = 2, ph = 0, tag = "1_base", swaps = 1 },
```

The tell that this was the diagnosis and not a guess: the capture logs
`cur_back`, and it read `0` — the value it holds *before* the first flip. A dump of
the buffer showed **zero non-zero bytes**, i.e. a cleared page, not a wrong picture.
Neither number is visible from the FAIL line, which is why the log line now carries
`cur_back`, `swaps` and `loads` at every capture.

This gate had already broken once this way (P3.9 → P3.11 moved it 3 → 2). A count
that has to be re-tuned every time the loading strategy changes is not a gate, it is
a coincidence with a threshold.

*Established:* P3.11.

---

## 38. A 16-bit count cannot live in D across a copy loop (P3.12)

The LZ decoder's copy loops were written as the obvious thing:

```asm
lz_lit_loop     lda     ,u+
                sta     ,x+
                subd    #1              ; D is the count
                bne     lz_lit_loop
```

`lda` loads into **A, which is D's high half**. The first byte copied overwrites the
top of the counter, so `subd #1` decrements the *data*, and the loop runs until the
byte just fetched happens to be zero at the same moment B wraps. It cannot work, for
any input, ever.

The fix is to count in B with the high byte parked in memory — B reaching 0 with the
page byte still set means another 256 to go, and B wrapping to 255 on the next `decb`
is exactly right:

```asm
lz_lits         sta     lz_cnt          ; high byte
                bne     lz_lit_loop
                tstb
                beq     lz_lits_done
lz_lit_loop     lda     ,u+
                sta     ,x+
                decb
                bne     lz_lit_loop
                tst     lz_cnt
                beq     lz_lits_done
                dec     lz_cnt
                bra     lz_lit_loop
```

**Any 6809 loop that loads through A or B cannot also count in D.** The registers
that survive a `lda`/`ldb` are X, Y, U and memory — nothing else.

What made it expensive was not the bug but where it pointed. The failure appeared as
a runaway that scribbled through `$FF00` I/O (remapping memory underneath the routine
doing the remapping), so it presented as "the second screen crashes the machine" —
data-dependent, load-address-dependent, anything but "the copy loop is impossible".
Two hypotheses were tested and eliminated against a decoder that had never worked at
all. A guard that stops the reader leaving the window (`cmpu #$FE00 / bhs`) is worth
having permanently: it converts a machine that destroys itself into a picture that is
merely wrong, which can be looked at.

*Established:* P3.12.

## 39. `-wavwrite` records the session's audio; `-sound none` yields a valid, silent file (P4.6)

**`mame ... -wavwrite out.wav` works on `coco3` and on `apple2e`** and writes a 16-bit WAV
of the whole session at 48 kHz — **from frame 0, not from when the program starts**, so the
oracle's music sits 44 s inside a 32 MB file. It coexists with `-video none` and
`-nothrottle`, which is what makes a headless capture cheap.

**Do NOT pass `-sound none` with it.** Every other runner in this project passes it because
they measure pixels or cycles; here it produces a file that opens, has the right length, and
contains nothing. *An artifact that looks produced and is empty is the failure mode this
project keeps meeting.*

Two gotchas found in one dispatch:
- **The channel count is not 1 or 2.** `coco3` wrote 3 channels and `apple2e` wrote 5. Any
  parsing must read `getnchannels()`, not assume.
- **The idle level is not zero.** `apple2e` sits at 0 but `coco3` sits at −8192, so activity
  detection has to be relative to the file's own baseline. `harness/tools/wav_trim.py` takes
  the median of the first second as the baseline and cuts to the active span.

## 40. The GIME timer at TINS=0 runs `nnn+2`, and MAME reproduces it — measured (P4.6)

`SockmasterGime.md:83` records that the GIME cannot run a count of 1: the 1986 part
processes `nnn+2` and the 1987 part `nnn+1`. **MAME's `coco3` implements the +2 behaviour,
and it is measurable directly:** with the timer free-running (auto-reload, no per-interrupt
rewrite), the emitted period minus `ticks × 63.695 µs` is **+127.80 µs = 2.01 ticks**, with
no handler code in the path.

**This is not a rounding detail — for short periods it dominates.** At the 1.27 ms segments
this port's music mostly uses, two ticks is **10%**, and an unmodelled `nnn+2` left a slice
playing 7.2% long, about 1.2 semitones flat. **A timer period is `(ticks + 2) × tick`, and
the tick itself is nominal** — measured at 63.759 µs from adjacent tick values, +0.10%.

**If the handler REWRITES `$FF94` each interrupt** (needed to vary the period per segment,
e.g. to dither), add its own latency on top, and note it is not one number:

| path | offset | what it is |
|---|---|---|
| free-running | +127.8 µs | the chip's `nnn+2`, nothing else |
| rewrite, steady | +170.2 µs | the above + FIRQ entry and the prologue (~76 cyc) |
| rewrite, run advance | +225.2 µs | the above + the table walk (~98 cyc) |

**Measure it, do not derive it:** `harness/smoke/song_live.lua` `P_PULSE=1` times the
`$FF20` writes on the bus and splits the offset by whether `sp_ptr` moved — *by mechanism,
not by the tick value, which merely correlates with it in one particular song.*

---

## 41. Booting Sierra's OS-9 AGI titles under MAME — the five things that make it work (P0.4)

★ **AGI-VERIFIED for coco_agi.** Established P0.4 by booting `King's Quest III` from the pinned
CoCo3 corpus. Everything here was found by failing at it first; each item cost a run.

**The working command line:**

```
mame coco3 -ext fdc \
    -flop1 <a disk that carries BOTH the boot AND resource volumes> \
    -flop2 <the next disk in the set> \
    -autoboot_script <lua> -autoboot_delay 0 \
    -nothrottle -sound none -seconds_to_run <N> -snapshot_directory <dir>
```

- **41a. OS-9 boots with `DOS`, not `LOADM`/`EXEC`.** §2 and §14's recipe is for DECB binaries.
  A Sierra AGI disk is an OS-9 RBF volume with `OS9Boot` on it, and DECB's `DOS` command reads
  the OS-9 kernel off the boot track. Everything else in §14 still applies — `-ext fdc` is
  mandatory (14a), `natkeyboard.in_use` must be armed frames early (14b), and posts must be
  gated on `nk.empty` (14c).
- **41b. ★★ PICK A DISK THAT ACTUALLY CARRIES THE RESOURCE VOLUMES.** This cost the first run
  and it is invisible from the filename. `KQ3/Original/KQ3-1-1.DSK` has `OS9Boot` **and**
  `CMDS/Sierra` and **ZERO `vol.*` files** — a pure boot side. OS-9 comes up, the interpreter
  starts, and there is nothing to load. **The manifest answers this without booting anything:**
  `games/manifests/coco3-files.tsv`, filtered to `vol.*` per image. For KQ3 the single-drive
  choices are `Coco SDC/kq3.dsk` (all 12 volumes) or `Floppy 360K/kq3-1.dsk` (boot + `vol.0,1,2,3,12`).
- **41c. ★★ SIERRA'S INTERPRETER PROMPTS FOR MONITOR TYPE, AND THE ANSWER IS `R` + ENTER.**
  A single `R` is NOT enough — the prompt echoes it and waits. Posting `R` alone leaves the
  machine in a tight poll at `PC=$FD5F` and the frame goes static, which looks exactly like a
  hang. With `R\r` (or `R` then `\r` as separate posts) `PC` immediately starts varying
  (`$BF3A → $9EC9 → $F339 → $FC43`) and the game renders.
  ★ **`PC` stuck at one address across several seconds is the tell for "waiting on a key",
  and `PC` varying is the tell for "running".** That distinction is free and does not require
  looking at a pixel — which matters because CLAUDE.md §3 forbids interpreting one.
- **41d. Past the title it wants CTRL+BREAK.** Reported by Jay at the P0.4 gate. Not needed for
  a first-screen capture; needed to reach gameplay.
- **41e. `-flop3` does not exist on this driver.** `mame coco3 -ext fdc` exposes **`-flop1` and
  `-flop2` only**; a third mount is `Error: unknown option: -flop3`, exit 6. A set of three or
  more disks cannot all be mounted at once, so prefer a single-image variant when one exists.

★★ **AND THE §2P HAZARD, WHICH IS THE ONE THAT MATTERS: MAME OPENS A FLOPPY READ-WRITE AND JVC
SAVES BACK** (§3, §24). A raw `.dsk` from the corpus mounted directly is a game file opened for
writing. **Always mount a COPY**, and re-hash the original afterwards. P0.4 did both; the
original was unchanged. *Candidates:*
`os9-boots-with-DOS-not-LOADM`, `pick-a-disk-that-carries-the-volumes-not-just-the-boot`,
`sierra-agi-monitor-prompt-needs-R-plus-ENTER`,
`pc-stuck-vs-pc-varying-is-a-free-liveness-test-without-reading-pixels`,
`never-mount-a-corpus-image-in-mame-mount-a-copy`.
