## Form B Report — P6.13 — Three placements, two already done and one in the wrong region
**Class:** build.  wip.

★★★★★ **The text work did not land again, and this time the reason is that the task's premise does
not hold.** Jay's ruling A is **already satisfied and executing it literally would make things
worse**; ruling C was **already done seven tasks ago on exactly the evidence it asks for**, and the
region it frees **cannot house a text engine**. Only ruling B offers space.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-07 22:29:29 (HEAD `f6f0450`, wip). `git status` clean apart from untracked
`coco_agi.code-workspace`, an editor file, not staged (§2E, explicit-path only).

---

### 4' — Pre-dispatch grep (C-13), verbatim, before the summary

```
=== coco_agi ===   f6f0450 P6.12 the clock in both legs, and a regression that broke p3b   wip
=== POP ===        104b197 HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)  wip
=== Karateka ===   29f8f0a HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)  wip

=== hal_sync x3 ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, ...)

=== reg_discipline ===
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   8   $FFA5 $FFA6
```

★ **§2T baseline cited, not rebuilt.** POP `104b197` / Karateka `29f8f0a` are P6.12 §0's refs,
unchanged; lwasm 4.24 unchanged. No sibling artifact built; no shared file touched.

★★★★★ **EVERY GATE RUN, NOT ASSERTED (§3):**

```
★ gates run: pic res cel comp p3b  -- all green
  renderer: per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
            games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
  comp:     composites byte-identical on both planes: 124 / 124 frames (100.00%)
  p3b:      160 cycles in 18.4571 emulated s, final room 83, err 0, no stall
=== VM gate (separate runner) ===
Kingquest1 PASS  Kingquest2 PASS  Kingquest3 PASS  SpaceQuest-1 PASS  SpaceQuest-2 PASS
PoliceQuest1 PASS  larry1 PASS  BlackCauldron PASS  MixedUpMotherGoose PASS
=== p3b ASSEMBLY, the one P6.11 broke ===
  p3b assemble exit=0   P3_CODE_END = 0x52FB   MAP_CODE_END = 0x5300   spare = 5 bytes
```

**Flag sets, enumerated and diffed** (L-77): one expected-on guard absent — p3b's `PIC_NOCOUNT`,
pre-existing, **fifth consecutive task**. **The clock, MEASURED** in every arm (L-78).

★★★★★ **The grep CONTRADICTED the dispatch in four places.** §1 and §3.

---

### 1 — Summary

★★★★★ **Ruling A is already satisfied, and the ruling would undo it.** `MAP_FONT` has been at
`$E0B8` since the map was written — **inside `MAP_TABLES`, slot 7, which memmap.inc's own phase
table marks "resident tables (unchanged)" in BOTH phases.** The font is not in `MAP_CODE`, has
never been, and costs **zero remaps per glyph and per string**. Moving it to a banked slice would
*introduce* a remap cost that does not currently exist — §7 trigger 2, reported, not done.

★★★★★ **Ruling C was already done in P3.13, on this exact evidence.** `pic_probe.s` cut the seed
stack from 1,024 B to **768 B / 384 entries** *"against a MEASURED peak of 37 (74 bytes)"*, left
10× headroom, and asserts the margin at assembly time. The dispatch's "1,024 B / 512 entries,
roughly 950 bytes idle" is **`memmap.inc`'s stale figure** — the map was never brought along.
★★★ **Re-measured this task on the corpus that actually runs: peak 74 bytes / 37 entries**,
identical. Not a corpus artifact; trigger 3 does not fire.

★★★★★ **And the region it frees cannot house a text engine.** The seed stack is at `$0100` in
**slot 0**; `MAP_CODE` is `$2000–$5300` in **slots 1–2**. Bytes freed there do not relieve the
pressure that motivated the task.

★★★★ **Ruling B is implementable and is the only one that is.** `MAP_RESERVED` is 3,328 B and
`MAP_RESERVED_MIN` is a floor on the **region's SIZE**, not on how much of it may be used —
`ifgt MAP_RESERVED_MIN-(MAP_RESERVED_END-MAP_RESERVED)`. The engine's parser assembles to ~870 B,
leaving ~2,458 B for text and sound. **Trigger 1 does not fire.**

★★★ **What landed:** the map corrected to 768 B with its assertion updated and **proven to fire**;
`pic_fill.s`'s comment corrected (both its numbers were wrong and it called a prediction a
measurement); and **the renderer gate shown able to fail on a seed-stack overflow**, selectively.

---

### 2 — Files modified

- `src/engine/memmap.inc` — `MAP_SEEDSTACK_E` `$0500 → $0400` (1,024 → 768 B) with the sizing
  evidence; the size assertion updated to 768 and **tested in both directions**.
- `src/harness/pic_fill.s` — the stack-overflow comment corrected (448→384 entries; "measured peak
  of 102" was the offline *prediction*, the measurement is 37).
- `src/harness/pic_probe.s` — `-DPIC_SEEDFAULT`, AC-6's overflow fault.
- `harness/tools/pic_seedfault.sh` — **new.** The fault arm, mirroring the gate's own invocation.

**No `src/engine/` code changed. No shared HAL file touched. No text engine exists.**

---

### 3 — Reasoning

#### 3.1 ★★★★★ Four contradictions between the dispatch and the tree

| the dispatch says | the tree says |
|---|---|
| the glyph table must leave `MAP_CODE` for a banked slice | `MAP_FONT` is at `$E0B8` in **resident** tables — never in `MAP_CODE`, and banked would be **worse** |
| `MAP_SEEDSTACK` is 1,024 B / 512 entries, ~950 idle | the **probe** is 768 B / 384 entries since P3.13; only the **map** still said 1,024 |
| the renderer "now runs **53** pictures"; AC-6 asks 53/53 | the gate runs **45**, and its own label reads `renderer (45 pictures)` |
| the peak "74 B / 37 entries" may be a 45-picture artifact | re-measured on the same 45 — **74 B / 37 entries**, and the corpus never widened |

★★★★ **The 53 figure has been corrected before.** P3b-24 §4: *"Correction, and it is the dispatch's
own figures that are off: 53/53 is **p3b's** corpus... not a gate row."* **The same error recurred
into this dispatch** — which is §3's disease (a claim carried rather than run) in the Orchestrator's
half of the loop rather than mine.

#### 3.2 §2H's three checks, on the glyph-table placement

1. **A SECOND mechanism?** ★★★★ Yes, and it decides the question. `memmap.inc:21-32` tabulates the
   slots per phase: slot 7 `$E000-$FEFF` is **"resident tables (unchanged)"** in both the VM phase
   and the draw phase, and `mmu_phase.s` writes only `MMU_SLOT5`/`MMU_SLOT6`. **The font is in the
   one region the phase mechanism never touches.**
2. **Name the caller.** `phase_vm` and `phase_draw` (`mmu_phase.s:36,45`) are the only writers of
   the phase pair, and neither goes near slot 7.
3. **Grep the reports before citing.** P6.8's AC-9 already recorded `MAP_FONT` `$E0B8`/2,048 B as
   *"confirmed correct and already"* placed. ★★ **The placement question was answered a task before
   the ruling that re-opened it.**

#### 3.3 The seed stack, and why it is not cut further

Measured this task, `sp_peak_bytes` over every picture in `build/sweep/timing.csv`: **max 74 B (37
entries), mean 15.2 B**, deepest `Kingquest1-009`. The P2 fill study's **offline prediction of
worst-case demand is 102 entries / 204 bytes** — a model, higher than any picture reaches.

★★★ **384 entries is 3.8× the model and 10.4× the sample, and I did not cut it further**, for three
reasons stated in the source: a flood fill's demand is a property of pictures we have not rendered
[AD-113 found a 71.5% divergence on a picture outside the gate corpus]; the overflow path halts
rather than wrapping; and **the region cannot fund the thing the cut was meant to fund** (§1).

★★ **`pic_fill.s:16` said "448 entries against a measured peak of 102" and both numbers were
wrong** — the stack is 384, and 102 was the prediction, not a measurement. **A comment that calls a
model a measurement launders it into evidence**, which is worse than being merely stale [AD-95].

#### 3.4 §2S — ref and scope

Sibling claims are §0's citation at POP `104b197` / Karateka `29f8f0a`, both `wip`, scope = HEAD and
cleanliness. Every gate figure in this report is from a run made this task.

---

### 4 — Verification (AC-by-AC)

★★★★★ **AC-1 [eye-gated] — NOT DONE, and not "pending Jay".** No text renders, so there is nothing
to show. §4A puts the eye gate first; the honest report is that this task produced no visual
surface.

- **AC-2 [byte-comparable] — PASS, every gate RUN.** pic **45/45**, res, cel, comp **124/124**, p3b
  (160 cycles, no stall), **p3b assembly exit 0**, VM **9/9**. `hal_sync_check.py` OK ×3;
  `reg_discipline.py` 8, unchanged. §2T cited in §0. — 25.1.

- **AC-3 [byte-comparable] — REPORTED, NOT DONE, and deliberately.** The glyph table is
  **`MAP_FONT` `$E0B8`, 2,048 B, ending `$E8B8`**, inside `MAP_TABLES` (`$E000–$FF00`, 7,936 B,
  **5,704 B free** after it). **It is NOT in `MAP_CODE`** and never was.
  ★★★★★ **Remap cost: ZERO, per glyph and per string.** Slot 7 is resident in both phases
  [`memmap.inc:21-32`], and `mmu_phase.s` touches only slots 5 and 6.
  ★★★ **§7 trigger 2 fires in the inverse direction the dispatch expected**: moving the font to a
  banked slice would make the per-glyph remap cost non-zero where it is currently zero. **Reported
  and stopped rather than executed.**

- **AC-4 [byte-comparable] — ANALYSED, engine NOT BUILT.** `MAP_RESERVED` `$5300–$6000` = 3,328 B.
  ★★★★ **The tripwire is on the region's SIZE, not its usage**: `ifgt
  MAP_RESERVED_MIN-(MAP_RESERVED_END-MAP_RESERVED)` fires only if someone shrinks the region below
  3,072 B. **So a text engine may use the reservation freely and trigger 1 does not fire.**
  The engine's parser assembles to ~870 B, leaving **~2,458 B** for text + sound.
  ★★ In **p3b** the same region is occupied by `CP_CEL` (4,784 B), which is why that probe org's
  the parser to `$E000` — a documented probe/engine divergence, unchanged by this task.

- **AC-5 [state-comparable] — DONE.** Re-measured across the corpus the gate actually runs:
  **peak 74 bytes / 37 entries** (`Kingquest1-009`), mean 15.2 B, 45 pictures.
  ★★★★ **The size was already 768 B / 384 entries in the probe** (P3.13); the **map** said 1,024 and
  is now corrected. **Chosen headroom: 3.8× the offline worst-case model (102 entries), 10.4× the
  measured peak**, with the assembly-time assertion updated to match. **Not cut further** — §3.3.
  ★★★ **Trigger 3 does not fire**: the peak is not higher than 74 B and was not a corpus artifact.

- **AC-6 [byte-comparable] — PASS, both directions.** Renderer **45/45 byte-identical on both
  planes** with the 768 B stack (`0 FAIL, 0 with no output`).
  ★★★★★ **And the gate is shown able to fail on a seed-stack overflow.** `-DPIC_SEEDFAULT` drops the
  ceiling to 20 entries, below the corpus peak of 37: **29 pictures report "no output" and the
  sweep stops after 16**, while the **first 6 render normally** (`sp_peak` 8–30, all under the
  ceiling) and the rest cap at `sp_peak=38, pixels=5237, fills=1` — the fill hitting the ceiling and
  halting, exactly as `pic_fill.s` claims. ★★★ **The split is the evidence**: a fault that broke all
  45 would prove only that the binary changed.
  ★★★ **The map's own assertion was also tested in both directions** (§7.2): 640 B fires with the
  correct message, 1,024 B does not — it is a **minimum**, not an equality.
  ★ **AC-6 asked for "53/53"; the gate is 45.** §3.1.

- **AC-7 [byte-comparable] — NOT DONE.** No text renders; no restore exists to compare.
- **AC-8 [byte-comparable] — NOT DONE.** The input line is not implemented.
- **AC-9 [state-comparable] — NOT DONE.** `have.key` still spins; `get.string` still absent.
- **AC-10 [state-comparable] — NOT DONE.** Depends on AC-7.

- **AC-11 [byte-comparable] — PASS.** All gates pass (AC-2). **`P3_CODE_END = $52FB` against
  `MAP_CODE_END = $5300` — 5 bytes spare, unchanged before and after this task's changes.**

- **AC-12 [state-comparable] — see §7.**
- **AC-13 [suite] — §10.**

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 (verbatim).** Gates — in §4' above, all run this task.

AC-5, the re-measured peak (`build/sweep/timing.csv`, 45 rows):
```
peak  = 74 bytes = 37 entries (2 B each)      mean = 15.2 bytes
Kingquest1-009  74 B (37)   Kingquest2-114  52 B (26)   Kingquest1-056  40 B (20)
Kingquest3-065  40 B (20)   Kingquest2-050  32 B (16)   Kingquest1-080  30 B (15)
```
AC-6, the overflow fault (`pic_seedfault.sh`, 20-entry ceiling):
```
rows in the FAULT run's CSV: 16  (a full run is 45)      'no output': 29
  Kingquest1-080  pixels=25079  fills=8   sp_peak=30     <- under the ceiling, renders
  Kingquest1-053  pixels=25677  fills=64  sp_peak=8      <- renders
  Kingquest3-065  pixels=5237   fills=1   sp_peak=38     <- AT the ceiling, halts
  Kingquest1-004  pixels=5237   fills=1   sp_peak=38     <- halts
★ picgate reported FAILURES -- which is what this arm is for
```
and the gate restored:
```
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
rows: 45   sp_peak max: 74 bytes
```
AC-6, the map assertion tested both ways (`build/assert_test.sh`, scratch):
```
=== SMALL: $0380 = 640 B, under the 768 minimum ===
  exit=1
  src/engine/memmap.inc(243) : ERROR : User Specified: "seed stack is not 768 B -- see the sizing note at MAP_SEEDSTACK"
=== LARGE: $0500 = 1024 B, the old value ===
  exit=0  (a MINIMUM check should NOT fire on oversize)
=== restored ===  exit=0
```
AC-3, the placement:
```
MAP_TABLES  $E000..$FF00 = 7936 B     MAP_PRI_BANDS $E000 168 B
MAP_PALETTE $E0A8   16 B              MAP_FONT      $E0B8 2048 B -> ends $E8B8
FREE        $E8B8..$FF00 = 5704 B
memmap.inc:  slot 7  $E000-$FEFF   resident tables   (unchanged)   [both phases]
mmu_phase.s: MMU_SLOT5 $FFA5, MMU_SLOT6 $FFA6  -- the only slots the phases write
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; nothing shipped, no DECB image, no
`LOADER.BIN`.

**25.3 operator-runtime-smoke:** `N/A — no visual surface this task (AC-1 NOT DONE).`

---

### 6 — Reactive deviations and route accounting

1. ★★★★★ **Two of the three rulings were not executed, and that is the report.** A is already
   satisfied and executing it would add cost (trigger 2); C was already done and its region cannot
   fund the text engine. **Neither is a §22.5 judgement call about method — both are the dispatch's
   premise not holding**, which §4 says to stop and report.
2. ★★★★ **I broke the p3b build and caught it in the same session.** `MAP_SEEDSTACK_E` moved without
   its assertion; `p3b_probe.s` refused to assemble and named the constant. **Fixed, and the fixed
   assertion then tested in both directions.** ★★ This is exactly P6.11's failure — and the
   difference is that §3 made me run the build.
3. ★★ **`pic_fill.s`'s comment was corrected** though no dispatch asked; it was wrong in both
   numbers and load-bearing for anyone sizing the stack.

**Route accounting.** I proposed no route and this report claims no text work. ★★★★ **What I got
wrong twice in a row and had to redo:** my first test of the new assertion used `-I` overrides that
did not take effect (exit 0, proving nothing), and the second used PowerShell `Set-Content -Encoding
UTF8`, which added a BOM so lwasm failed on line 1 rather than on the assertion — **both "passes"
were artifacts of the test, not the code.** The third attempt, a script run by path, is the one
quoted. ★★ **I also reached for a PowerShell here-string feeding `bash -c` and it mangled**, which
is §2J's construct failing exactly as §2J says it does.

---

### 7 — Uncertainty flags  (and AC-12: what the dispatch did not anticipate)

1. ★★★★★ **Ruling A's goal was already met and the ruling would reverse it.** The font is resident
   with zero remap cost; banked would be worse.
2. ★★★★★ **Ruling C was already executed in P3.13**, on the same measured peak, with 10× headroom
   and an assertion — seven tasks before the dispatch proposed it.
3. ★★★★★ **Reclaiming the seed stack cannot fund the text engine.** Slot 0 versus slots 1–2. **The
   task's three placements do not, between them, make the room the task was for.**
4. ★★★★ **The "53 pictures" figure recurred after P3b-24 corrected it.** The renderer gate runs 45
   and says so in its own label. §3's disease, in the Orchestrator's half of the loop.
5. ★★★ **`pic_fill.s` called an offline prediction a "measured peak"** for an unknown number of
   tasks.
6. ★★★ **The memmap assertion is a MINIMUM, not an equality** — it catches shrinking below 768 B and
   would not catch growing back to 1,024. Stated because I tested it and found out, not assumed.
7. ★★ **p3b's `PIC_NOCOUNT` absence is now five tasks old.**
8. ★★ **The `-DVM_VBLCLOCK` runaway is untouched** and remains unexplained [AD-142]; the clock is
   still gated, as §11 asks me to say.

---

### 8 — Follow-up candidates

1. ★★★★★ **The text engine's real placement question**, now that A and C are closed: `MAP_RESERVED`
   has ~2,458 B after the parser, and **resident tables have 5,704 B free at `$E8B8`** — which is
   where a glyph-adjacent text renderer would sit at zero remap cost. **That is a map decision and
   it is Jay's.**
2. ★★★★ **p3b's missing `PIC_NOCOUNT`** — fifth task naming it.
3. ★★★ **A build-all check** — one command that assembles every probe. It would have caught P6.11's
   overrun and my seed-stack assertion break at the moment each was made.
4. ★★★ **Widen the renderer corpus past 45**, which AD-113 said is under pressure and which would
   also re-test the seed-stack peak on new pictures.
5. ★★ **T3 in a populated room** — still not re-taken (P6.12 follow-up 2).

---

### 9 — User interaction during task

`None.`

---

### 10 — Candidate(s) captured this task

`None.` ★ Two are pending from P6.12 and remain unfiled; this task adds a third worth considering —
*a ruling made from a stale figure re-opens a question the tree already answered* — but three
candidates from three consecutive tasks on the same theme is a sign they should be folded into one,
and that is the reconciler's read-time job, not a reason to file three thin rows.

---

### 11 — Commit

See the commit carrying this report; pushed to `origin/wip` before reporting.
