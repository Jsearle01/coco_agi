## Form B Report — P3.2 — the sync entry, and first pixels
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-26 (dispatch T-P0-011 receipt; HEAD at receipt `bae9e5e`, wip, clean).
HEAD at report: `dbfe82c`. git status clean apart from this report.
POP `430a91c`, Karateka `78c8c27` — both carry the shared half of Part A.

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi                     wip    bae9e5e229020e40065b320f2f266cf843416ea5
POP3_port                    wip    e19bbed47098e38c07440feb57205e53fe5703df
karateka_coco3               wip    1b5ad76bb2c815926042078fd5159987834764e7
tracked dirty: coco_agi 0, POP 0, karateka 1 (harness/smoke/last-run.log, pre-existing)

POP baseline build exit 0; karateka baseline build exit 0. 319 / 104 artifacts snapshotted.
  build/loop_probe.bin      1269   1885b4d01f9166b9a0fa7488
  build/mode_probe.bin      1332   11134e4e24eee4e37e40fc17
  build/anim_probe.bin      1451   2cfa655c5e819a2c43d39e42
  build/intro_splash.bin   28145   8295c4139a2ee0a311d17659
  build/loader.bin          1606   56bf6740440c4e0a13909f90
  build/tile_probe.bin      1500   69c48c62b528c029f250e195
  build/probe.dmk         224016   ec6daccb0b78a9d52e0bfb2a

hal_sync_check.py  SIBLINGS = {'POP3_port': 'karateka_coco3', 'karateka_coco3': 'POP3_port'}
                   SHARED = 11 entries; PROJECT_LOCAL = {'src/hal/coco3-dsk/hal_globals.s'}
  working-tree sha1: POP 56d5b42, karateka 016408c, coco_agi 56d5b42  -- NOT byte-identical
  ★ index blobs: ALL THREE e9514813ba7be77a6deb7089faa94d74844f971f -- IDENTICAL.
    The working-tree difference is EOL only: karateka has no .gitattributes.

coco_agi HAL vs POP's CURRENT head: 9 of 11 SHARED files normalise()-EQUAL.
  hal.inc DIFFERS, gfx.s DIFFERS.
hal_globals.s in coco_agi: present; carries NO mode table (POP's pre-POP-HAL-01 copy).
MAME: dist/mame-cfg/rgb/coco3.cfg present, BREAK+CTRL on :row6 mask 0x0004/0x0010; coco3 rom ok.
```

★★ **The drift is entirely additive from our side and POP has ZERO lines we lack** — measured,
not assumed:

```
src/hal.inc   ONLY in coco_agi (1):  GFX_MODE_320x200x16 equ 2 ...      ONLY in POP: 0
src/hal/gfx.s ONLY in coco_agi (17): GFX_MODE_MAX equ 2 + the 3-row table   ONLY in POP: 0
```

So nothing of POP-HAL-01 was missed, and this is the **anticipated transition** (§2M.5), not
§8.2's ambiguous drift. **§8.2 not triggered** — stated with the evidence rather than asserted.

★ **§2T note (arrived mid-task):** the baseline was rebuilt rather than cited, correctly —
**both** of §2T's conditions 1 and 2 hold. POP moved `282a65cf`→`e19bbed` and Karateka
`072ddcf`→`1b5ad76` (POP-HAL-01), and Karateka's tree carries a dirty tracked file. Citation
applies from the next dispatch.

---

### 1 — Summary
**Part A is complete and verified.** `coco_agi` is the third participant in the HAL sync mesh;
all three repos report OK naming the other two; POP and Karateka rebuild byte-identical; mode 2
moved out of the shared `gfx.s` into `coco_agi`'s own `hal_globals.s`, so it now touches no
shared file — the property POP-HAL-01 bought.

★★★ **Part B does not pass, and the cause is localised rather than ambiguous.** One AGI PICTURE
is interpreted by 6809 code on a real CoCo3 in 320×200×16 and both planes are read back and
diffed against the pinned oracle — the pipeline works end to end — but the rendering diverges.
**The same algorithm transcribed back into Python matches the oracle exactly (0 differences,
both planes), so the algorithm is right and the ASSEMBLY is wrong**; bisecting with fills
disabled shows the **vertical lines are not being drawn**. Reported, not worked around (§8.3).

### 2 — Files modified
- `CLAUDE.md` — v1.3 committed as given (`499a793`), then **v1.4** (`48d6dd6`) when it arrived mid-task. Both superset-checked.
- `harness/tools/hal_sync_check.py` — three-participant edit, **landed in all three repos**.
- `src/hal/coco3-dsk/gfx.s` — re-synced to POP's current head (the table leaves).
- `src/hal/coco3-dsk/hal_globals.s` — gains `coco_agi`'s own 3-row mode table.
- `src/hal.inc` (POP + Karateka) — the shared mode-number registry gains `GFX_MODE_320x200x16 equ 2`.
- `src/harness/pic_probe.s`, `pic_draw.s`, `pic_fill.s` — NEW, the 6809 picture renderer.
- `harness/tools/pic_probe.lua`, `picdiff.py` — NEW, the MAME driver and the diff.

`src/engine/**` untouched — **0 `.s` files**. No game data, resource bytes or renderings committed.

### 3 — Reasoning

**3.1 CLAUDE.md — v1.3 then v1.4, both superset-checked (§2D).**
v1.2→v1.3: 8 substantive in-repo lines absent from the provided file, **all intentional
supersessions** — the version banner (2), §2G's stale "read-only/copy-and-adapt" wording (3),
and §2M items 5–7 renumbered to 6–8 to make room for the mode-table seam (3). Verified by
reading the new §2G and §2M rather than trusting the count.
★ **v1.4 arrived mid-task** (17:59, after v1.3 at 17:52) adding **§2T**. Superset v1.3→v1.4:
only the version banner superseded. Both are committed separately rather than one amended over
the other, because *which artifact was in force when* is what a reader of this task will need.

**3.2 Part A — the three edits, and why none may be per-repo.**
`PARTICIPANTS` is a list with `others = [p for p in PARTICIPANTS if p != mine]` **derived**; a
1:1 dict can only ever name ONE sibling, so with three repos a participant would be compared by
nobody while appearing to pass. `PROJECT_LOCAL` is a per-repo **mapping keyed by repo name**,
identical in every copy — ★ AC-5's real constraint is that *"a per-repo constant must not be
able to make the copies differ"*, and the script is in its own `SHARED` list and compares
itself, so the only per-repo input is the directory name discovered at runtime. Graceful skip is
**per pair**: with two participants an absent sibling meant nothing could be checked; with
three, one absent repo must not suppress the pair that IS present.

**3.3 Mode 2 moved to `hal_globals.s`, and rows 0–1 came with it.** The lookup is **positional**
(row index = mode id), so mode 2 cannot sit at index 2 unless 0 and 1 exist. They are not AGI's
modes and AGI does not select them. The registry entry stays in shared `hal.inc` so two projects
cannot assign the same id to different modes — POP-HAL-01 left that for *"coco_agi's change to
make when it lands its mode"*, and it landed here.

**3.4 ★★ Part B's transform, and the direction that can fail.**
Mode 2 is 4bpp, so a CoCo3 byte is two screen pixels; AGI's 160 columns double to 320, making
**one AGI pixel exactly one byte with the colour in both nibbles** — and 160 B/row is mode 2's
stride exactly. **The nibble duplication IS the pixel doubling.**
★ We **unpack** the CoCo3 buffer to 160×168 indices and compare those, rather than packing the
oracle's. Packing the oracle would apply OUR transform to BOTH sides, so a packing bug would
cancel itself. ★ And the unpack **verifies the two nibbles agree** before trusting either — a
byte whose halves differ is not a colour index, it is a half-pixel, and AC-8(c) proves the plain
byte comparison misses exactly that. Priority is 160×168 on both sides (design §3.3), so **no
transform and nowhere for a transform error to hide**.

**3.5 ★★★ Algorithm right, assembly wrong — established rather than inferred (L-32).**
The same control flow, transcribed back into Python from `pic_probe.s`/`pic_draw.s`/`pic_fill.s`,
renders picture 80 with **0 differences against the oracle on both planes**. So what was
transcribed is correct and the defect is in the 6809 code. Bisecting with fills disabled: the
CoCo3 differs from that algorithm by **699 pixels over 166 rows, first at (0,1)** — about four
columns per row, which is the **vertical** lines missing. `x_corner`'s left and right borders are
therefore absent, the colour-7 fills have no boundary, and they flood the interior; by the time
the final `set_visual(9)` + `fill(2,166)` runs there is no white left to claim. That single
mechanism explains the whole 96%.

**3.6 Two real defects found and fixed on the way, both against the oracle.**
- ★★ **The AGI canvas is visual=15 / priority=4, not black.** `HAL_gfx_set_mode` clears to index 0 — right for the HAL, wrong for a picture, because `draw_FillCheck` fills only where the visual is 15. With a black canvas **no fill could ever succeed**. ★ Row 0 agreed with the oracle throughout anyway, because row 0 is genuinely black: two buffers matching for different reasons, and a gate that checked only row 0 would have passed.
- ★★ **`rel_line` deltas are SIGN-MAGNITUDE** [`picture.cpp:640-643`: `if (dx & 0x08) dx = -(dx & 0x07)`]. Bit 3 is the sign and bits 0–2 the magnitude, so `$F` is **−7**; my two's-complement `ora #$F0` made it **−1**. Every negative delta landed wrong.
- ★ **The probe never set `S`.** `hal.inc:357-362` states it outright — the CALLER owns the stack and it must live below `$8000` — and its suggested `$7F00` is inside this probe's priority plane, so it cannot be taken literally. Leaving `S` where DECB put it aimed the hardware stack into the fill stack; the first deep fill ate a return address and the CPU ran off to `$0211`.

**3.7 §2O.1 — the baseline is the oracle.** `picdiff.py` does not import `tools/picrender/` and
must not. picrender was used **once, as a diagnostic**, to confirm the oracle dump is what we
think it is — it reproduces `pic080` exactly on both planes. That is checking the instrument,
not moving the baseline.

**3.8 §2S.** All refs in the grep block. Siblings written only in the two sanctioned files
(`hal_sync_check.py`, `hal.inc`); no sibling content touched.

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] PASS.** v1.3 committed byte-identical (47,944 B, sha256 `8b7528da…`), then v1.4 (51,067 B, sha256 `02681726…`). Superset output in §5.
- **AC-2 [byte-comparable] ★★★ PASS.** Karateka **104/104 byte-identical**. POP: **shipped set 7/7 identical, all 292 emitted binaries unchanged**; the sole tree delta is `build/obj/tile.map` +61 B — `Symbol: GFX_MODE_320x200x16 (tile_probe.o)`, a bare `equ` in a shared header adding one symbol line to the one map that lists `GFX_MODE_*` at all. **No emitted byte changed.** Reported rather than absorbed: v1.3 scopes byte-identity to the six DECB files plus `probe.dmk`.
- **AC-3 [byte-comparable] ★★ PASS.** All three report **OK**, each naming the other two — not "skip". Verbatim ×3 in §5.
- **AC-4 [byte-comparable] PASS.** Index blobs identical in all three: `ddedd41b5b6b34b7e5422c52901e66905d0ddf06`. ★ Working-tree sha1 differs for Karateka **only** because it has no `.gitattributes` — a pre-existing condition recorded at T-P0-010, not introduced here.
- **AC-5 [byte-comparable] PASS.** `PARTICIPANTS = ['POP3_port','karateka_coco3','coco_agi']` with `others = [p for p in PARTICIPANTS if p != mine]`; `PROJECT_LOCAL` a per-repo mapping. Lines in §5.
- **AC-6 [byte-comparable] ★★★ FAILS.** Picture **KQ1 #80**. Visual: 25,809 of 26,880 differ (96.016%); ours sha256 `44867687…`, oracle `ef1556f2…`; first differing pixel **(x=0, y=1)** — ours 7, oracle 0. Transform: unpack 4bpp→indices, nibble agreement verified (**all bytes' nibbles agree**).
- **AC-7 [byte-comparable] FAILS.** Priority: 166 of 26,880 differ (0.618%); ours `88b2a40d…`, oracle `98cdf968…`; first differing pixel **(x=0, y=1)** — ours 4, oracle 15. No transform applied, as design §3.3 requires.
- **AC-8 [state-comparable] ★★ PASSES, three ways.** (a) positive control — a correct render **PASSES**, exit 0; (b) one pixel corrupted → caught at **exactly (37,42)**, 1 of 26,880; (c) one **half-pixel** (nibbles disagreeing) → caught by the nibble check **even though the byte comparison reported IDENTICAL**. (c) is the transform error §5 warned could cancel a rendering error, and it is the one a naive `byte & 0x0F` would absorb.
- **AC-9 [byte-comparable] PASS.** `coco_agi` **0** (src/engine holds 0 `.s` files; the probe is in `src/harness/`), POP **59**, Karateka **8**.
- **AC-10 [eye-gated] NOT SUBMITTED.** ★ **Deliberate.** The render is known-wrong (AC-6), so asking Jay to gate it would spend his attention on a picture I already know is incorrect. There is no screenshot in the repo (§2P). **The gate should be requested once AC-6 passes**, on the `poke` launch path — `LOADER.BIN` and the DECB bootstrap are out of scope (§12), so `live-disk` is not available yet and that must be recorded when it is.
- **AC-11 [suite]** See §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
=== AC-1 §2D superset checks ===
v1.2 -> v1.3: in-repo 597 substantive, provided 581.
  8 line(s) absent, ALL intentional supersessions:
    ## Working Agreement v1.2 ... / **Version:** 1.2
    - **Read-only for content.** Never modify a sibling's scene logic, ...
    - ★★ **The HAL is the exception and it is NOT read-only — it is SYNCHRONISED.** ...
    5. ★★ **ENTRY IS AT P3, NOT AT REPO CREATION.** ...
    6. **Joining requires three edits to the script, ...**
    7. ★ **Graceful skip must survive.** ...
v1.3 -> v1.4: SUPERSET CHECK PASS -- only the v1.3 version banner superseded.
CLAUDE.md now: 51067 bytes  sha256 02681726fefd2e46576cdf59dff9c22b  Version: 1.4
```

```
=== AC-3 hal_sync_check.py, all three repos ===
coco_agi        [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files ...)
POP3_port       [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files ...)
karateka_coco3  [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files ...)

=== AC-4 index blobs ===
coco_agi / POP3_port / karateka_coco3 : ddedd41b5b6b34b7e5422c52901e66905d0ddf06  (all three)

=== AC-5 ===
PARTICIPANTS = ['POP3_port', 'karateka_coco3', 'coco_agi']
    others = [p for p in PARTICIPANTS if p != mine]
PROJECT_LOCAL = {
    'POP3_port':      {'src/hal/coco3-dsk/hal_globals.s'},
    'karateka_coco3': {'src/hal/coco3-dsk/hal_globals.s'},
    'coco_agi':       {'src/hal/coco3-dsk/hal_globals.s'},
}
```

```
=== AC-2 POP, baseline vs after Part A ===
  baseline artifacts: 319   current: 319
  ★ CHANGED (1):
      build/obj/tile.map   11684 B 3b00940f668942f0 -> 11745 B 5664452b5e7e8a82
  mechanism: Symbol: GFX_MODE_320x200x16 (build/obj/tile_probe.o) = 2002
             tile.map is the ONLY map listing GFX_MODE_* symbols; every other lists none.
  SHIPPED SET (v1.3 scope: six DECB files + probe.dmk): 7/7 byte-identical
  ALL emitted binaries (.bin/.dmk/.raw/.o/.lz): 292 compared, 0 changed

=== AC-2 karateka ===
  baseline artifacts: 104   current: 104
  ★ ALL 104 ARTIFACTS BYTE-IDENTICAL
```

```
=== AC-6 / AC-7 THE GATE — picture 80, KQ1 ===
probe completed at frame 929, bad_op=$00        (no unimplemented opcode, no stack overflow)
  CoCo3 framebuffer window : 26880 bytes (packed 4bpp)
  unpack: every byte's nibbles agree -- the doubling is intact
  VISUAL    ★ DIFFERS   25809 of 26880 bytes (96.016%)
      ours   sha256 44867687e4031456c368b90ba897c5ceaa2660b04c231fb14f859c4f93724c1f
      oracle sha256 ef1556f2ae78156e686a3c987d6817aa15fe38d9cddd0211423caae4d5c84468
      first differing pixel: offset 160 = (x=0, y=1)  ours 7, oracle 0
  PRIORITY  ★ DIFFERS   166 of 26880 bytes (0.618%)
      ours   sha256 88b2a40dbb4b32b8dc93a3d4e8473e843ca54540808474d5dedc37383ca1e9b0
      oracle sha256 98cdf968fe6321caf5b88d4831eb85bc76e6c1b3347770a8eaa93a48880f02a7
      first differing pixel: offset 160 = (x=0, y=1)  ours 4, oracle 15
AC-6/AC-7: FAIL

=== the localisation ===
TRANSCRIPTION of the 6809 code, run in Python, vs the ORACLE:
  VISUAL   0 of 26880 differ (0.000%)
  PRIORITY 0 of 26880 differ (0.000%)
  -> the ALGORITHM is right; the ASSEMBLY is wrong.

LINES ONLY (fills disabled on both sides), CoCo3 vs that same algorithm:
  differing pixels: 699 of 26880 (2.600%)
  first at (x=0, y=1): CoCo3 15, transcription 0
  differing rows: 166        -> ~4 columns/row = the VERTICAL lines are not drawn
```

```
=== AC-8 the gate can fail ===
(a) positive control (oracle visual re-packed 4bpp + oracle priority):
      VISUAL ★ BYTE-IDENTICAL   PRIORITY ★ BYTE-IDENTICAL   AC-6/AC-7: PASS   exit=0
(b) one pixel corrupted, (37,42) 9 -> 8, nibbles still agreeing:
      VISUAL ★ DIFFERS 1 of 26880 (0.004%)
      first differing pixel: offset 6757 = (x=37, y=42)  ours 8, oracle 9   -> CAUGHT
(c) one HALF-pixel, (80,100) hi=8 lo=9:
      ★ HALF-PIXEL BYTES: (x=80, y=100) hi=8 lo=9
      VISUAL ★ BYTE-IDENTICAL      <-- the byte compare alone would have PASSED
      AC-6/AC-7: FAIL              <-- the nibble-agreement check caught it
```

```
=== AC-9 register discipline ===
coco_agi   src/engine .s files: 0
[reg-discipline] 0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
POP3_port  [reg-discipline] OK -- measured 59, matching the independent figure.
karateka   [reg-discipline] OK -- measured 8, matching the independent figure.
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` still ships no bundle; there is no `build.bat`,
no `LOADER.BIN` and no disk image (§12 defers all three). The probe image is gitignored.
25.3 operator-runtime-smoke: **NOT SUBMITTED — see AC-10.** Not "pending Jay": no gate was
requested, because the render is known-wrong. **Launch path when it is requested: `poke`**
(image poked into RAM, PC set from Lua), because `live-disk` needs `LOADER.BIN`, which is out of
scope. ★ A `poke` gate hides load/launch bugs and must be recorded as `poke`, never unqualified.

### 6 — Reactive deviations and route accounting
- **§8.2 examined and NOT triggered** (§3, grep block): the HAL drift is entirely additive from our side and POP has zero lines we lack, so it is the anticipated transition, not ambiguous drift.
- **§8.3 triggered and honoured**: AC-6 diverges; the picture, the first differing pixel and both buffers' hashes are reported, and the renderer was **not** adjusted toward `tools/picrender/`. picrender was used once to validate the oracle dump and is not imported by the differ.
- **Deviation:** CLAUDE.md was committed **twice** — v1.3 as the dispatch specified, then v1.4 when it arrived mid-task. I did not silently swap the artifact the dispatch named.
- **Deviation:** AC-10 was **not** submitted. Reasoning in AC-10; this is a judgement I am flagging rather than a step I skipped.
- **ROUTE ACCOUNTING.** The dispatch's two parts were done in the stated order, Part A verified before Part B started. Within Part B I said I would render one picture and diff it against the oracle — done, and it fails. **What I did NOT do:** find the vertical-line defect. I localised it to the assembly and to vertical lines specifically, and stopped there rather than continuing to hunt, because §8.3's instruction is to report a divergence rather than iterate on it.

### 7 — Uncertainty flags
- ★★ **The vertical-line defect is localised but NOT identified.** I read the vertical branch of `draw_line` repeatedly against the transcription and could not see the discrepancy; the evidence for "vertical lines" is the 699-pixel/166-row signature and the missing left border, not a line of code. The next task should bisect further (render only the `x_corner` and dump) rather than re-read it.
- **AC-6/AC-7's sample is ONE picture.** Picture 80 was chosen because it uses 7 opcodes — `set_visual`, `set_priority`, `disable_priority`, `x_corner`, `rel_line`, `fill`, `end`, measured from the resource bytes. **`y_corner`, `abs_line`, `disable_visual` and both pattern opcodes are unimplemented and HALT.** ★ KQ1's whole corpus uses **no** pattern opcodes.
- **The fill-stack peak was not measured on the CoCo3.** 256 entries against an offline peak of 102; overflow halts with `$EE`, and it did not fire.
- **Mode 2's framebuffer is cleared for 26,880 bytes, not the full 32,000.** Rows 168–199 keep whatever `set_mode` left. Harmless for the diff; a real renderer must decide what lives there.
- **The probe writes the visual plane straight into the framebuffer window** and keeps priority in RAM at `$1700`. That fits one 64 KB map exactly and will not survive adding a second buffer — the design's slice-mapping (§2R.1) is still ahead.

### 8 — Follow-up candidates
1. ★★★ **Find the vertical-line defect.** Bisect by rendering only `x_corner` and dumping, comparing against the transcription at the same point. The transcription is the instrument that makes this cheap.
2. Once AC-6 passes, **request AC-10** and record the launch path as `poke` until `LOADER.BIN` exists.
3. Implement `y_corner`, `abs_line`, `disable_visual`; they halt today.
4. ★ **Karateka has no `.gitattributes`** — still the reason the three working-tree copies of the sync script are not byte-identical. Worth settling.
5. Widen the picture sample once the renderer passes one.

### 9 — User interaction during task
One standing note from Jay, mid-task: sibling baselines are established by **citing** the
previous report when HEAD, working tree and toolchain are unchanged, rather than by rebuilding.
Acknowledged and adopted; it also arrived as **CLAUDE.md v1.4 §2T**, which is committed. ★ It did
not change this task's baseline — §2T's conditions 1 and 2 both held (both siblings' HEADs moved,
Karateka's tree dirty), so the rebuild was required. It applies from the next dispatch.

### 10 — Candidate(s) captured this task
None. ★ The two candidate observations here — *"a buffer can agree for the wrong reason"* (row 0
matched throughout while the canvas colour was wrong) and *"transcribe the assembly back to the
high-level language to separate algorithm from implementation"* — are worth capturing, but the
second is only half-proven until the vertical-line defect is actually found by that route. **I
would rather capture it once with the outcome than now with the hypothesis.**

### 11 — Commit
`499a793` — P3.2 Part A: join the HAL sync mesh; mode 2 lands project-local
`48d6dd6` — CLAUDE.md v1.4 (§2D) — §2T, sibling baselines by citation
`dbfe82c` — P3.2 Part B: first pixels on a CoCo3 — gate FAILS, defect localised
POP `430a91c`, Karateka `78c8c27` — the shared half of Part A
(all pushed to origin/wip before this report)
