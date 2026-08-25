## Form B Report — T-P0-006 — P2 begins: the picture renderer, offline
**Class:** build. wip.

---

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-08-25T23:34:15Z. HEAD at receipt `ac9d24c` (wip) → **at report `35ced9d`**, pushed.
`git status --porcelain` at report → clean apart from this report.

---

## ★ §3 PRE-DISPATCH GREP FINDINGS (C-13) — VERBATIM, BEFORE THE SUMMARY

```
coco_agi        branch wip   HEAD ac9d24c10291a1dd1895fdd5511f416455564dfb  (at receipt)
POP3_port       branch wip   HEAD 282a65cf9c79739326e101b3d7cccffc8cff2daa
karateka_coco3  branch wip   HEAD 072ddcfc27ccb2c0a9b820913cd57b341a6e6fbc
```

Sibling refs **unchanged since T-P0-001** (§2S.3).

| check | measured |
|---|---|
| `agi-coco3-design-v0.6.md` in repo root | ★ **YES**, 50,869 B, sha1 `5262d1c9…`. §8.1 did not fire. |
| `oracle/scummvm.pin` | still **`9d9b9e93`**; WSL clone at that commit, binary present, runnable |
| `tools/volread/` | PICTURE extraction working; **oracle-verified at 2,410/2,410** (P1.1), on v2-directory **and v2-volume** games only |

**ScummVM's picture code, as found:**

| thing | file:line at `9d9b9e93` |
|---|---|
| command dispatch | `picture.cpp:378-446` `drawPicture()` |
| the flood fill | `picture.cpp` `draw_Fill(int16,int16)` — scanline, `Common::Stack<Common::Point>` |
| the boundary test | `picture.cpp` `draw_FillCheck()` |
| priority/control screens | `graphics.cpp:200-202` — two `calloc(SCRIPT_WIDTH*SCRIPT_HEIGHT)` planes |
| banding | `graphics.cpp:1295-1303` default, `:1305-1315` override |

★ **Dimensions and buffer count as FOUND, not as design §6 states them:** `_DEFAULT_WIDTH 160`
(`picture.h:27`), `_DEFAULT_HEIGHT 168` (`:28`), **two** planes, **one byte per pixel** (not
packed 4bpp), cleared to visual **15** / priority **4** (`picture.cpp:770-772`, `picture.h:56`).
**This matches v0.6 §2.1.**

### ★★ A CONTRADICTION WITH §2 — I DO NOT HOLD v0.4

§2 says to run the superset check against *"v0.4, the last version you hold."* **I hold no design
document and never have.**

```
$ git log --all --diff-filter=A --name-only | sort -u | grep -iE 'design|v0\.[0-9]'
(empty — no design doc has EVER been added to this repo)
$ find . -iname '*design*'
./agi-coco3-design-v0.6.md        (the one Jay just placed)
$ grep -i design README.md
- **Design authority:** `agi-coco3-design-v0.3.md` (held by the Orchestrator).
```

**v0.6 is the first design document ever to exist in this repo.** See §3A — the check is
**vacuous, not skipped**, and the distinction matters.

---

### 1 — Summary

★★★ **AC-3 — THE GATE — PASSES: 597 pictures, 597 with BOTH buffers byte-identical to the
pinned oracle**, across **six games and all three corpus populations**. Zero visual differences,
zero priority differences, zero render errors, **zero unknown opcodes**.

★★ **AC-5 answers the number design §6.2 needed: the peak seed-stack depth is 102 entries** over
498 pictures — **204 bytes on a 6809** at two bytes per seed. Median 7. ★ **No picture comes
close to §8.4's 2 KB trigger**, so the flood fill's memory cost is not the risk it was feared to
be. Its *time* cost is 12.5 M pixels filled across 35,048 invocations, which is the figure M-02
must weigh against a room-change budget.

★★ **AC-6 was proven by BREAKING it, not by passing.** With both screens on, the fill is bounded
by the **visual** screen (`draw_FillCheck` case 3). Rebinding that to the priority screen
**breaks 107 of 390 pictures** — so the rule is load-bearing, not incidentally satisfied. A
green aggregate could not have shown that.

★ **Two near-misses of my own are recorded** (§3F): a literal `grep` that nearly produced a false
C-34 contradiction against v0.6, and the standing temptation to "fix" `draw_Line` into Bresenham.

**Eight AC pass, one is vacuous-by-contradiction, one is bounded by a P1.1 finding.**

---

### 2 — Files modified

Explicit-path staging (§2E). Two commits plus this report.

**`8028bb8`**
- `docs/project/agi-coco3-design-v0.6.md` — **moved from the root, committed as given** (§2D).
  Byte-identical across the move: sha1 `5262d1c9…` before and after.

**`35ced9d`**
- `tools/picrender/{__init__,screens,draw,fill,commands,render}.py` — **new.**
- `oracle/patches/0004-oracle-raw-resource-dump.patch` — extended with a **picture-render
  sweep** so the oracle renders and dumps every PICTURE.

★ **No game data, resource bytes or renderings committed** (§2P). ★ **A rendered room is a
rendering of copyrighted content** — this report carries counts and hashes, no images.

---

### 3 — Reasoning

#### 3A — Why AC-1's check is vacuous rather than skipped

A superset check answers one question: **was anything LOST?** With **no prior design version in
the repository**, nothing can have been. So committing v0.6 is safe on that ground — **not on
the ground that a check passed**, and the report says which.

What I did instead was **confirm v0.6 carries the changes §2 declares** — §4.2's 5-byte/7-byte
headers, §8.4's *"THREE populations"*, §4.5's 51.4 / 20.3 / 14.8 by variant, §11.1 **REOPENED**.
★ **That is confirming a description, which is weaker than a superset check**, and it is
reported as such rather than dressed up as AC-1.

#### 3B — Everything came from the oracle, and three details would never have been guessed

CLAUDE.md §2 ranks ScummVM above the Specs; §7 and L-25 say read the constant, don't infer it.

★★ **`draw_Line` IS NOT BRESENHAM.** ScummVM carries its own error-accumulation loop that steps
**both** axes per iteration, each gated on its own error term. Substituting a standard Bresenham
differs by a pixel on some diagonals — **a failed byte-comparison that looks perfectly correct on
screen.** The same shape as P1.1's LOGIC `+1` message-offset trap: plausible output, wrong bytes.
It was transcribed, not improved.

★★ **PARAMETERS SELF-TERMINATE, AND THERE IS NO LENGTH FIELD ANYWHERE.**
`getNextParamByte` (`picture.cpp:104`) treats any byte `>= 0xF0` as an opcode, **rewinds one
byte**, and ends the current command. So a single off-by-one in the reader desynchronises the
**entire rest of the picture** rather than corrupting one shape — which is exactly why a
byte-comparison catches it and an eyeball would not.

★ **`horizontalCheck` is passed and never read.** The Specs describe a horizontal-only variant of
the fill check; the oracle ignores the distinction. §2.1: **that is a fact about ScummVM.**
Reproduced with the parameter kept and unused, so the divergence stays visible instead of being
tidied away.

#### 3C — ★★★ AC-6: proving the rule by breaking it

`draw_FillCheck` has three cases, and the third is the one §5 flags:

```c
if (!_priOn && _scrOn && _scrColor != 15)  return screenColor == 15;      // visual only
if (_priOn && !_scrOn && _priColor != 4)   return screenPriority == 4;    // priority only
return (_scrOn && screenColor == 15 && _scrColor != 15);                  // ★ BOTH ON
```

★★ **With both screens enabled the test reads the VISUAL screen alone** — so the priority fill
stops at boundaries that exist only on the visual screen, exactly as §5 predicts.

★★★ **That all 597 pictures matched does not, by itself, show this rule is what made them
match** [L-10 — my own T-P0-001 finding, where 59 matched while the per-file split did not]. So
the rule was deliberately **broken** — case 3 rebound to the priority screen — and the gate
re-run:

```
as the oracle has it (visual bound)         identical=390   differing=0
case 3 bounded on PRIORITY instead (broken) identical=283   differing=107
```

**107 pictures break.** The rule is load-bearing. ★ **Had the break changed nothing, AC-6 would
have been UNPROVEN on this sample** and I would have said so — the script prints exactly that
branch, because a check whose failure mode is unreachable validates nothing (L-23).

★ **Two guards that look like noise and are not:** `_scrColor != 15` and `_priColor != 4`.
Filling white into white would never terminate; the oracle makes it a no-op by returning false.
A renderer that "helpfully" permitted it would hang rather than mis-render.

#### 3D — §2H's three checks

1. **Is there a SECOND mechanism serving a different object class?** ★ **Yes — priority is
   written by two entirely separate mechanisms and only one is a picture's business.** A
   PICTURE's priority plane is written by its own drawing commands; the **banding table**
   (`graphics.cpp:1289-1315`) is a Y→priority lookup consulted when **sprites** are drawn.
   Conflating them would have applied banding to a buffer the oracle leaves alone. **The 597/597
   match confirms the oracle does not band a picture's priority screen**, and AC-7 verifies the
   table separately rather than through the renderer.
2. **Name the routine that CALLS it.** Decisive for the dump seam. `oracleDumpScreens()` fires at
   the end of `decodePicture()` — **above** the `drawPicture()` / `drawPicture_AGI256()` fork, so
   both decoders are covered (the P0.2 finding, reused). And the render sweep calls
   `decodePicture(nr, true)` with **clearScreen=true**, because that is what `draw.pic` does and
   what our `render()` reproduces; an overlay (`overlay.pic`) is a different operation and is not
   what AC-3 compares.
3. **Grep prior reports for the same subsystem.** P0.3 §3C found 156 of 193 priority dumps
   uniform-4 and established that a picture with no priority commands legitimately leaves the
   plane at its initial fill. **This task's `screens.clear(15, 4)` is the mechanism behind that
   observation**, and the two agree without either being adjusted.

#### 3E — AC-8: the populations, and which are out of scope

v0.6 §8.4 and P1.1 §3D: **the corpus is three populations.**

| population | in scope for byte-comparison? | gated here |
|---|---|---|
| **PC Sierra DOS** (KQ1/KQ2/KQ3) | ✅ v2 dirs, v2 volumes | **287 pictures** |
| **PC fan set** (`agile-gdx@81c42ba`) | ✅ v2 dirs, v2 volumes | **211 pictures** |
| **CoCo3** | ★ **1 of 38 variants only** | **99 pictures** (`KQ3/Original`) |

★★ **37 of 38 CoCo3 variants are V2-directory / V3-VOLUME hybrids** — 7-byte headers, LZW —
which P1.1 §3D established and which v0.6 §11.1 reopens. **They are out of scope by scope, not
by defect**, and no amount of renderer work reaches them until v3 is decided.

★ `KQ3/Original` was extracted from its ten OS-9 disk sides into a plain directory so the oracle
could read it (ScummVM cannot mount OS-9). It detects as **`agi:kq3 King's Quest III: To Heir Is
Human (CoCo3/English)`** — Sierra's official CoCo3 release — and renders 99/99 identical. ★ The
merge across ten images found **24 duplicate filenames and 0 with differing content**, which
independently validates `corpus.py`'s first-wins rule on this variant.

#### 3F — ★★ Two near-misses of mine, recorded because both nearly became report text

1. **A literal `grep` nearly produced a false C-34 contradiction.** Checking whether v0.6 carried
   §2's declared changes, three came back **zero**. The document was fine — **my grep was wrong**:
   I used BRE alternation `\|` under `-E`, so the patterns matched literal backslashes. Corrected
   syntax found all of them. ★ **This is the third time in this project a literal grep has misled
   me**, and it is precisely §2N's discredited-instrument lesson arriving in a new costume.
   **Verify the instrument before reporting what it found.**
2. **The standing pull to "fix" `draw_Line`.** Transcribing an error-accumulation loop that is
   *nearly* Bresenham invites correction. §3B says why not, and the byte-comparison is what would
   have caught it — but only after the fact, and only if I had not "corrected" the oracle's
   output to match my expectation instead.

#### 3G — Refs and scopes (§2S.3, L-24)

Oracle citations at **`9d9b9e93` (v2.9.1)**. Corpora at **`agile-gdx@81c42ba`**, the PC drop, and
the CoCo3 drop. Sibling figures at **POP `wip` `282a65c`** / **Karateka `wip` `072ddcf`**. ★ The
CoCo3 row names its **variant** (`KQ3/Original`), never just the title.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable]** — v0.6 committed **byte-identical**, sha1 `5262d1c9…` before and
  after the move to `docs/project/`. ⚠️ **Superset check NOT PERFORMED — I hold no v0.4** (§3
  grep, §3A). **Vacuous, not skipped**: v0.6 is the first design doc in the repo, so nothing can
  have been lost from it. Reported rather than claimed.
- **AC-2 [byte-comparable]** — `coco_agi` **0**, POP **59** at `282a65c`, Karateka **8** at
  `072ddcf`; fixture demo rc=0; `seam_check.py` **0 violations**. ✅ **PASS.**
- **AC-3 [byte-comparable] ★★★ THE GATE** — **597 pictures compared, 597 with BOTH buffers
  identical**, 6 games, 3 populations. Per-game table in §5 (**not just a total** — L-10).
  ✅ **PASS.**
- **AC-4 [byte-comparable]** — **zero unknown opcodes** across all 597. Every opcode encountered
  (`0xF0`–`0xFA`, `0xFF`) is handled. ★ The renderer **records** unknown opcodes with the
  resource that used them rather than skipping silently; the list is empty, which is a
  measurement, not an absence of instrumentation. ✅ **PASS.**
- **AC-5 [state-comparable]** — full cost table in §5. **Peak stack depth 102 (204 B on a 6809),
  median 7; 35,048 fill invocations; 12,555,589 pixels filled; 756,478 seeds pushed. 0 pictures
  over §8.4's 2 KB.** ✅ **PASS.**
- **AC-6 [byte-comparable]** — the both-screens interaction **demonstrated by breaking it**:
  107 of 390 pictures fail when case 3 is rebound to the priority screen. File:line
  `picture.cpp` `draw_FillCheck`; resources listed in §5. ✅ **PASS.**
- **AC-7 [state-comparable]** — default table **168 entries, 14 bands × 12 rows**, values below 4
  clamped to 4 (bands 1–4 collapse to `4×48`, then `5×12` … `14×12`); `setPriorityTable(50)`
  override verified (rows before base = 4, capped at 15). ★ **Our renderer does not band a
  picture's priority screen and neither does the oracle** — confirmed by the 597/597 match
  (§3D.1). ✅ **PASS.**
- **AC-8 [suite]** — three populations, counts and scope in §3E. ⚠️ **CoCo3 coverage is 1 of 38
  variants**, bounded by P1.1's V3-volume finding, **not by this renderer**.
- **AC-9 [byte-comparable]** — ★ **the check, stated and executed**: a grep over
  `tools/picrender/*.py` for `open(`, `read_bytes`, `write_bytes`, `pathlib`, `json`, `pickle`,
  `golden`, `expected`, `baseline` returns **only docstring prose — no file I/O of any kind**.
  The renderer cannot read a stored expectation because it cannot read a file. The only
  comparison anywhere is against the oracle's dumps, performed by a scratch script outside
  `tools/picrender/`. ✅ **PASS.**
- **AC-10 [suite]** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1a — the superset diff:** **N/A — no v0.4 exists to diff against** (§3, §3A).

**25.1b — `reg_discipline.py` ×3 + the seam check (AC-2):**

```
coco_agi  src/engine/**                    [reg-discipline] OK -- measured 0   rc=0
POP       src/ less src/hal,src/harness    [reg-discipline] OK -- measured 59  rc=0
Karateka  src/ less src/hal                [reg-discipline] OK -- measured 8   rc=0
run_rule_demo.sh                           rc=0  (incl. the --expect 7 negative control)
seam_check.py                              version branches outside the seam: 0   rc=0
```

**25.1c — ★★★ AC-3, THE GATE, PER GAME (not just a total — L-10):**

```
population     game           pics    cmp BOTH ok vis bad pri bad
PC Sierra DOS  Kingquest1       82     82      82       0       0
PC Sierra DOS  Kingquest2      108    108     108       0       0
PC Sierra DOS  Kingquest3       97     97      97       0       0
PC fan set     abrah           117    117     117       0       0
PC fan set     starco           94     94      94       0       0
CoCo3          KQ3/Original     99     99      99       0       0

  pictures compared      : 597
  BOTH buffers identical : 597
  visual differed        : 0
  priority differed      : 0
  oracle had no dump     : 0
  our renderer errored   : 0

AC-4  unknown opcodes: none -- every opcode encountered is handled
```

**25.1d — ★★ AC-5, THE FILL COST TABLE (the input to M-02, and through it M-13):**

```
                     min      median       max        total
fill invocations       0          47       531        35,048
pixels filled          0      24,752    52,795    12,555,589
seeds pushed           0       1,443     4,028       756,478
MAX STACK DEPTH        0           7       102         (peak)

★ deepest stack : starco pic241 -- depth 102, 83 fills, 25,799 pixels, 657 pushes
★ a seed is (x,y); at 2 bytes each that peak is 204 BYTES on a 6809
★ pictures whose seed stack would exceed 2 KB (§8.4 trigger): 0

CoCo3 KQ3/Original separately: 10,500 fill invocations, max depth 47, median 7
```

★ **The stack is not the problem; the pixel count might be.** 24,752 pixels is the *median*
picture — filling that many at, say, a few cycles per pixel is where a room-change budget goes,
not in holding 204 bytes of seeds.

**25.1e — ★★ AC-6, proven by breaking the rule:**

```
as the oracle has it (visual bound)          identical=390   differing=0
case 3 bounded on PRIORITY instead (broken)  identical=283   differing=107

★ AC-6 DEMONSTRATED: breaking case 3 breaks 107 picture(s) that otherwise match.
  The visual-screen bound is load-bearing, not incidentally satisfied.
```

**25.1f — AC-7, priority banding:**

```
default table: 168 entries;  14 bands x 12 rows = 168  -> matches SCRIPT_HEIGHT
bands: 4x48 5x12 6x12 7x12 8x12 9x12 10x12 11x12 12x12 13x12 14x12
values below 4 clamped to 4: True     rows 0..47 all == 4: True
setPriorityTable(50): rows before base are 4: True    capped at 15: True
```

**25.1g — AC-9, the self-reference check:**

```
$ grep -rE "golden|expected|baseline|open\(|read_bytes|write_bytes|pathlib|json|pickle" \
       tools/picrender/*.py
  -> matches only inside docstrings; NO file I/O in any module.
```

**25.2 — bundled-artifact grep:** **N/A.** No build artifact; the deliverables are Python and a
patch. The ScummVM binary is an oracle tool outside the repository (§2Q.1).

**25.3 — operator-runtime-smoke:** **N/A — no CoCo3 visual surface this task.** Offline only;
hardware rendering is P3.

---

### 6 — Reactive deviations and route accounting

1. **Patch 0004 was extended** rather than a new 0005 added — the render sweep sits directly
   beside the raw-resource sweep it shares a guard with.
2. **`KQ3/Original` was extracted to a scratch directory** so the oracle could read it; ScummVM
   cannot mount an OS-9 image. The extraction is `os9fs` (P0.4-validated); the **comparison is
   still ours-vs-oracle**, not ours-vs-ours.
3. **Six games, not four** (AC-3 asks ≥4) and **three populations, not one**.
4. **AC-6 was proven by deliberately breaking the renderer**, which is not what the AC asks for —
   it asks for verification against the oracle. **The break is strictly stronger** and the
   passing form is reported alongside it.
5. **Two games (`kq2bi`, `sq0`) did not render** in the oracle sweep and are absent from the
   sample. Not chased: 597 across 6 games already exceeds AC-3's floor, and **saying so is
   better than quietly reporting the smaller set as if it were the plan** (§7.3).

**ROUTE ACCOUNTING.** No route was proposed to Jay or the Orchestrator. What this change contains
is §2's file list plus the five items above. **What it does NOT contain, said here rather than
left to the diff:** no 6809 code, no CoCo3 rendering, no cycle counting, no span-optimised fill
(§7.5), no v3/LZW, no VIEW or sound decode, no golden files. **Explicitly not done per §12:** no
`src/hal/`, no `hal_sync_check.py`, no `build.bat`, no image builder, no game data or renderings
committed, no disassembly of Sierra's interpreter.

---

### 7 — Uncertainty flags

1. **★ AC-1's superset check was not performed** (§3A). If v0.4 or v0.5 content was dropped
   between versions, **nothing in this task would have detected it.**
2. **★★ AC-5 measures a PYTHON fill, and the stack depth is an ALGORITHM property, not a 6809
   measurement.** Depth 102 is what *this* scanline algorithm needs on *these* pictures. It says
   nothing about cycles, and the 6809 figure (204 B) assumes a 2-byte seed — **a real
   implementation may need a wider entry**. M-02 needs the *time* cost, which this does not give.
3. **★ The sample is 597 pictures from 6 games of ~160 available** [L-22]. All are v2-directory
   **and** v2-volume. **Not covered: every V3-volume title (37 of 38 CoCo3 variants), AGI256,
   v3 nibble parameters, Amiga and PreAGI media.** A clean gate here licenses none of them.
   ★ `kq2bi` and `sq0` were in the intended sample and are absent (§6.5).
4. **`_dataOffsetNibble` / v3 4-bit parameters are structurally present but never enabled.**
   Untested, and would silently mis-read v2 data if switched on.
5. **★ The span optimisation design §6.2 wants is NOT implemented.** This is the oracle's
   point-seed scanline fill, transcribed. §4.4 of the dispatch asks correctness first and the
   span step measured separately — **the second half is not done**, and the AC-5 figures are for
   the unoptimised form.
6. **`plotPattern` carries a literal `167`** where one might expect `height - 1`
   (`picture.cpp`). Transcribed as-is. On a 168-row screen they coincide; **on any other height
   they would not**, and the oracle would be the one that is right.
7. **AC-6's break-test covered 390 pictures, not all 597** — it ran over 4 of the 6 games. The
   conclusion holds on that sample; a picture outside it could in principle exercise the rule
   differently.

---

### 8 — Follow-up candidates

1. ★★ **M-02 still needs a TIME cost, not a memory cost.** AC-5 shows the stack is a non-issue
   (204 B) and points at the real quantity: **a median 24,752 pixels filled per picture**. The
   next measurement is cycles-per-pixel on a 6809 for the fill inner loop, against a
   room-change budget — that is a P3 measurement, and it is what M-13 inherits.
2. ★ **Implement and measure the span optimisation** (§7.5, design §6.2), now that a correct
   reference exists to diff it against. **Diff it against the ORACLE, not against this
   renderer** — a second renderer of ours validated against the first is the self-referential
   trap (§2O.1).
3. **Widen the sample** to the full fan corpus (§7.3); the harness already sweeps 150 games.
4. **Decide §11.1** — 37 of 38 CoCo3 variants and one of the two official Sierra CoCo3 releases
   are unreachable until v3 is settled.
5. **Report the `167` literal** (§7.6) to the Orchestrator as a design note for §6.3.

---

### 9 — User interaction during task

**One message: `continue`**, after the renderer modules were written and before the oracle sweep.
**No guidance about the work's content was given and none was requested.**

★ **No consultation trigger fired.** §8.1 did not (v0.6 was present). §8.2 did not — **AC-3 never
diverged**, so there was nothing to report-and-stop on. §8.3 did not (the oracle's fill and the
Specs agree on the algorithm; where they differ is `horizontalCheck`, which changes nothing —
§3B). §8.4 did not — **0 pictures exceed 2 KB of seed stack**, the trigger's own threshold.
§8.5 could not (no v0.4 to check).

---

### 10 — Candidate(s) captured this task

**None.**

★ Stated rather than manufactured, and the reasoning is the same as P1.1's. The candidate this
task would have produced — *prove a rule is load-bearing by breaking it, because a passing
aggregate does not attribute the pass* (§3C) — is **the L-23/L-10 pair already in the pool**, and
§3F's grep near-miss is another instance of the discredited-instrument pattern already captured
at P0.4. **§2C says capture at the FIRST instance**; adding rows for the fourth and fifth
instances of principles already recorded would inflate the counts the reconciler uses to weigh
them (`SCHEMA.md` §4). **The right act is an added instance at reconcile time, which is the
reconciler's read-time job, not mine.**

---

### 11 — Commit

`35ced9d` — two commits this task, plus this report:

```
8028bb8  P2.1a design v0.6 committed as given (§2D)
35ced9d  P2.1  picture renderer: offline, oracle-verified at 597/597
(this)   P2.1  report
```

Pushed to `origin/wip` before this report.
