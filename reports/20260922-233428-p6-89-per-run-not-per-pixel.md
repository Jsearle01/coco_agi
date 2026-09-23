## Form B Report — P6.89 — Per run, not per pixel: the census says no, and P6.88's guards are now proven
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-22 (HEAD `ff0d2c5`, wip). `git status` clean apart from an untracked
`coco_agi.code-workspace` that predates this task.

### 1 — Summary
★★★★★ **§6's first trigger fires: the win is not there, and the census says so in two independent
ways.** Opaque runs average **1.84 pixels** in the castle's cels and **2.17** across 8,682 corpus
cels; **53–57% of opaque runs are a single pixel.** ★★★★★ **And the runs are not available to the
compositor at all** — `cp_composite` walks a per-pixel row buffer, so detecting a run costs the
very per-pixel look a run-skip exists to avoid. Carrying them across is **option 3, deferred and
out of scope.** ★★★ Priced from the stage-9 labels: the recoverable share is **~3–5% of a cycle**,
against changes to code that `cel` (9,193) and `comp` (124) own. **Census reported, implementation
not taken.**

★★★★★ **§1.1's premise is refuted where it pointed and confirmed where it did not.** The key runs
are the LONG ones (mean 3.47 castle / 4.21 corpus, 58–59% of pixels) — but key pixels are the
**cheap** ones: `co_pix`, the loop that tests them, is **9.2%** of the drawing stage against the
opaque path's **~28%**. ★★★ **The expensive pixels are in the short runs.**

★★★★★ **§4E succeeded and is the task's positive result: P6.88's two guards are now PROVEN
NECESSARY.** A constructed scene (`-DP3B_FORCE_OVERLAP`) puts two sprites on top of each other at
equal priority; `isolated` falls from 99 to 0 — the guards refuse every skip — and **with both
guards off the planes go wrong**: visual `76285D37BC19` against `891CA3CF2525`, priority
`E28B08FACA14` against `F5A30A58756A`. ★★★ **Neither could be shown red alone because in that scene
each independently refuses**, which is a fact about belt-and-braces guards worth keeping.

★★★★ **No shipped byte moved**: all nine arms and five probes byte-identical; the only source
change is a guarded test arm and two comment blocks.

### 2 — Files modified
- `src/harness/p3b_probe.s` — `-DP3B_FORCE_OVERLAP` (§4E's constructed scene), guarded.
- `src/harness/composite.s` — **comment only**: the run census beside `co_pix`, and why the runs
  are not reachable there.
- `harness/tools/cel_runs.py` — NEW: the run-length census, key and opaque separately.
- `harness/tools/p3b_show.ps1` — `-ForceOverlap`.
- `harness/tools/gates.manifest` — §4E's result; P6.88's guards recorded as **now exercised**.

### 3 — Reasoning

#### §3(2) — where a run is known, and where it is lost ★★★★★
`vc_decode_row` reads the RLE and **expands it into `CP_CEL`, one byte per pixel**
[`vc_dc_emit`/`vc_dc_fill`]. `cp_composite` then reads that buffer through `co_src`, one byte at a
time, at `co_pix`. ★★★★★ **The run boundaries exist only inside the decoder's loop and are gone
before the blit sees anything.**

★★★★ **So "skip a key run by advancing" is not available to `cp_composite`**: to know a run is
eight long it must look at eight bytes, and the look is what `co_pix` already does. ★★★ The only
ways to make runs visible are (a) re-detect them in the buffer — a compare per pixel, which is the
cost being removed — or (b) have the decoder hand them over, **which is option 3** [§10; T-P0-141
§1.4 records the objection: `cel` gates 9,193 cels by comparing DECODED CEL BYTES].

#### §3(3) — which per-pixel decisions are run-invariant ★★★★
| site | per pixel | run-invariant? |
|---|---|---|
| `co_pix` | loads the buffer byte, tests against `co_key` | ★ the TEST is, the LOAD is what finds the run |
| `co_opaque` | reads screen priority (`plane_pri`) | ★★★★ **no** — screen priority varies under the sprite |
| `co_depth` | compares it with `co_prio` | ★★★★ **no**, for the same reason |
| `co_put_visual` | writes the colour (`plane_vis`) | ★ value yes, ADDRESS advances per pixel |
| the priority write | read-modify-write, packed 2 px/byte | ★ value yes, address advances every 2 px |

★★★ **So a fill would still do N depth reads and N packed RMWs**; what it could save is the key
test and the two accessor CALLS for pixels 2..N. `plane_vis`+`pv_have`+`plane_pri`+`pp_have` are
**10.4% of the stage**, and with a mean opaque run of 1.84 only 46% of opaque pixels are "extra" —
**a ceiling of ~4.8% of the stage, ~3% of a moving cycle**, before the re-detection cost.

#### §3(4) — region A ★★★
`-IfRec` still does not assemble (`"P3b code overruns MAP_RESERVED_END"`), **unchanged from
T-P0-141** — this task adds no unconditional code. ★★ The map ruling remains overdue and this task
did not make it worse.

#### §4A — THE CENSUS ★★★★★

**The cels the castle actually composites** (views 0, 97, 107 — 3 cels, 46 rows, 664 pixels):
```
KEY    runs 111  pixels 385 (58.0%)  mean run 3.47
OPAQUE runs 152  pixels 279 (42.0%)  mean run 1.84      ★ 80 of 152 runs are ONE pixel
opaque pixels in runs >= 2: 71.3%   >= 4: 20.8%   >= 8: 2.9%
key    pixels in runs >= 2: 88.3%   >= 4: 69.1%   >= 8: 44.9%
runs per row: 5.72
```

**The corpus** (6 pinned titles, 8,682 cels, 238,321 rows, 3,232,163 pixels):
```
KEY    runs 451,500  pixels 1,902,780 (58.9%)  mean run 4.21
OPAQUE runs 613,176  pixels 1,329,383 (41.1%)  mean run 2.17
★ 349,915 of 613,176 opaque runs are ONE pixel
opaque pixels in runs >= 2: 73.7%   >= 4: 41.8%   >= 8: 18.1%
key    pixels in runs >= 2: 93.1%   >= 4: 72.0%   >= 8: 48.5%   >= 16: 24.3%
```
★★★ **The castle is representative and slightly conservative** (opaque 1.84 against the corpus's
2.17), so the figures are a floor in the direction that matters.

★★★★★ **The threshold conclusion §4A asks for: there is no threshold worth having.** A fast path
taken only on runs ≥ 4 would cover **20.8% of the castle's opaque pixels and 41.8% of the
corpus's**, and would still pay a per-run test on the 53–57% of runs that are one pixel long —
**while being unable to see the runs at all without the per-pixel comparison it replaces.**

#### §4B — not implemented, and why that is the answer ★★★★★
§6's first trigger: *"§4A says the win is not there — short runs, bookkeeping dominant — report the
census and stop. That is a complete answer and it costs one task."* ★★★ **Three independent reasons,
any one sufficient:**
1. **Short runs**: opaque mean 1.84/2.17, majority single-pixel.
2. **The runs are not reachable** from `cp_composite` without option 3 (§3(2)).
3. **The ceiling is ~3–5% of a cycle** against code two byte-comparable gates own.

★★ **What the census implies for option 3**, as §4B asks: the decoder's expansion into a per-pixel
buffer is what destroys the information, so **fusing would be the only way to exploit runs** — and
its price is `cel`'s 9,193-cel comparison losing its subject. **The census makes option 3's case
stronger and its cost unchanged**; it is still a ruling.

#### §4E — the constructed scene, and what it proves ★★★★★
`-DP3B_FORCE_OVERLAP` copies sprite 0's x, y and priority over sprite 1's **in the staged copy
only** — the game's object table is untouched (§2P) and `update_position` keeps working. That is
two overlapping sprites at **equal priority**: the case T-P0-141 §4A named as the one the narrow
rectangle test cannot cover.

| arm | planes (visual / priority) | skips | verdict |
|---|---|---|---|
| reference `-NoSkip` | `891CA3CF2525 / F5A30A58756A` | — | — |
| both guards on | `891CA3CF2525 / F5A30A58756A` | **0** (was 99) | ★ identical |
| `-SkipNoIso` only | `891CA3CF2525 / F5A30A58756A` | 0 | ★ identical |
| `-SkipNoPrio` only | `891CA3CF2525 / F5A30A58756A` | 0 | ★ identical |
| **both off** | **`76285D37BC19 / E28B08FACA14`** | **111** | ★★★★★ **RED** |

★★★★★ **The guards are necessary, measured.** ★★★★ **And the reason neither is red alone is
worth recording: in this scene EACH guard independently refuses**, so disabling one leaves the
other refusing. **A belt-and-braces pair needs both arms off to demonstrate either** — which is a
general trap for fault-arm design, not a fact about this pair.

#### §2S — sibling refs
POP3_port `104b197` (wip), karateka_coco3 `29f8f0a` (wip); both dirty with pre-existing work not
mine. **No `SHARED` file touched**; `hal_sync_check.py` OK. lwasm 4.24 unchanged.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement]** §4A, key and opaque separately, castle and corpus, with the threshold
  conclusion.
- **AC-2 [byte-comparable · gate] All RUN.** `cel` **9,193/9,193**, `comp` **124/124**, `pic`
  **45 PASS / 0 FAIL (of 45)**, `res` **1,264/1,264**, `vm` **9/9**. ★★★★ **`comp_probe`
  byte-identical** and every other probe too — nothing unconditional changed.
- **AC-3 [state-comparable]** ★★ **No pixels could move**: all nine arms byte-identical to
  T-P0-141's baseline. The plane comparison was run anyway as §4E's instrument, with `P3B_DUMP=1`.
- **AC-4 [measurement]** ★★ **N/A — nothing was implemented**, so there is no before/after. The
  standing/moving figures are unchanged from T-P0-141: **0.2350/0.2336 standing, 0.3063/0.3004
  moving**, and the arms prove it.
- **AC-5 [state-comparable · fault injection]** ★★ **N/A — no per-run change to fault.** §4E's
  arms are the fault injection this task did produce.
- **AC-6 [measurement]** ★★ Nothing opportunistic was taken (§4C): the census closed the task
  before implementation, and no separable defect surfaced.
- **AC-7 [state-comparable]** §4E's table — ★★★★★ **not dropped, and it succeeded.**
- **AC-8 [byte-comparable]** Region A unchanged; **`-IfRec` still does not assemble**, as at
  T-P0-141. ★★ This task added no unconditional code.
- **AC-9 [suite]** `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green (`all green`);
  `-SelfTest` red on one row; mojibake clean.
- **AC-10 [eye gate — Jay]** ★★★★ **NOT OFFERED, and the reason is the arms**: all nine are
  byte-identical to the build Jay watched at T-P0-141. **There is nothing to look at**, and asking
  "is it faster while moving?" about an unchanged program would spend his attention on a null
  [P6.86's precedent].
- **AC-11 [manifest]** ★★ **Not re-baselined: nothing moved.**
- **AC-12 [tooling]** `hal_sync_check.py` OK; `reg_discipline` **6 in 1 file — still one owner**;
  `gen_vm_tables.py --check` OK; `probe_identity_check.ps1` every non-p3b probe byte-identical;
  `p3b_arms_check.ps1 -SelfTest` red on one row.
- **AC-13** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
=== AC-2 SUMMARY === all nine titles PASS (vm, 600 cycles each, 0 divergent)

§4A castle cels 0/97/107:  KEY 111 runs 385 px (58.0%) mean 3.47
                           OPAQUE 152 runs 279 px (42.0%) mean 1.84; 80 runs of length 1
                           opaque >=2 71.3% | >=4 20.8% | >=8 2.9%
    corpus 8682 cels:      KEY 451,500 runs 1,902,780 px (58.9%) mean 4.21
                           OPAQUE 613,176 runs 1,329,383 px (41.1%) mean 2.17
                           349,915 opaque runs of length 1; >=4 41.8%
    stage-9 labels, moving: co_pix 9.2% | co_opaque 5.2 co_depth 4.7 co_reject_pri 4.0
                            co_put_visual 3.9 plane_pri 3.4 pp_have 2.8 plane_vis 2.3 pv_have 1.9

§4E overlap scene (P3B_DUMP=1, 120 cycles, room 1), visual / priority:
    reference -NoSkip     891CA3CF2525 / F5A30A58756A
    both guards on        891CA3CF2525 / F5A30A58756A   isolated 0 of 111 unchanged
    -SkipNoIso            891CA3CF2525 / F5A30A58756A   isolated 0   (the other guard refuses)
    -SkipNoPrio           891CA3CF2525 / F5A30A58756A   isolated 0   (the other guard refuses)
    BOTH OFF              76285D37BC19 / E28B08FACA14   isolated 111, CP_BLITS 337   ★ RED

★ all 9 arms byte-identical to the recorded baseline (SHA256)
★ every non-p3b probe byte-identical
-IfRec: still does NOT assemble -- "P3b code overruns MAP_RESERVED_END"
[reg-discipline] 6 register access(es) in 1 file(s) over 4 register(s).
[hal-sync] OK      CHECK OK: vm_tables.s matches optable.py.
```

**25.2 bundled-artifact grep:** N/A — nine arms and five probes pinned by hash, all unmoved.

**25.3 operator-runtime-smoke:** ★★ **NOT RUN, deliberately.** No shipped byte changed; the last
observed gate remains T-P0-141's (Jay: *"nothing noticed" / "yes" / "no" / "no"*), and the arms are
byte-identical to the ones he watched.

### 6 — Reactive deviations and route accounting

1. ★★★ **`cel_runs.py` is new** — §4A's question had no producer. `pic_census.py` is the precedent
   the dispatch names.
2. ★★★ **`-DP3B_FORCE_OVERLAP` was added for §4E.** Guarded; no shipped arm assembles a byte of it.
   ★★ It edits the **staged copy**, not the game's object table (§2P).
3. ★★ **§4E needed FOUR arms, not two.** The dispatch expected "disable the isolation test or the
   priority test"; in the constructed scene each refuses independently, so both had to be disabled
   together to produce a difference. **Reported as the finding it is.**

★★★★ **No §2J.5 violation.** Every edit used `Edit`/`Write`; `fix_mojibake --check` clean.

**ROUTE ACCOUNTING.** ★★★★★ **The dispatch gave permission to implement and the census withdrew
it, which §6 names as a complete answer.** **NOT implemented**: the per-run blit (§4A's three
reasons); the depth precheck of §1.2 (it hangs off a per-run path that does not exist); option 3
(§10, and the census strengthens its case without changing its price); option 2 (declined
upstream).

### 7 — Uncertainty flags

1. ★★★★★ **The ~3–5% ceiling is derived from label shares, not from a built arm.** It is an
   estimate and is labelled one [§8 rule: my own arithmetic is a lead, not a finding]. ★★★ **What
   is measured is the run distribution and the label split**; the multiplication is mine.
2. ★★★★ **The census counts runs in the ENCODING, and `cp_composite` sees the EXPANSION.** Every
   figure about run lengths is therefore about what the decoder consumed, not about what the blit
   could exploit — **which is precisely §3(2)'s point and the reason the answer is no.**
3. ★★★★ **§4E proves the guards are jointly necessary, not individually.** Each refuses in the
   constructed scene, so the experiment cannot say whether either alone would suffice. ★★ A scene
   that overlaps at DIFFERENT priorities would separate them and was not built.
4. ★★★ **The forced overlap is synthetic.** It shows the guards fire on a configuration AGI can
   produce, not that AGI produces it in these rooms — **and the reachable rooms still do not**.
5. ★★ **The corpus census covers cels as stored**, including loops and cels no game ever draws.
   The castle subset is the drawn one and agrees with it.

### 8 — Follow-up candidates

1. ★★★★★ **The remaining speed work is rulings, not licences.** The fill (63.6% of a render,
   P6.86), the two core loops (55% of the drawing stage, P6.87), and option 3. ★★★★ **None is a
   task-sized fix and the budget says none reaches parity**: removing the drawing stage entirely
   still lands at 0.096 s against a 0.100 s target.
2. ★★★★★ **The map ruling** — `-IfRec` blocked since T-P0-141, region A full, third instrument
   squeezed out.
3. ★★★★ **Option 3, with the census in hand** — it is the only route that makes runs visible to the
   blit, and T-P0-141 §1.4's objection (the `cel` gate loses its subject) is still unanswered.
4. ★★★ **A scene that separates P6.88's two guards** [§7(3)] — overlapping at different priorities.
5. ★★★ **Design spec §7.1's `0.039 s/cycle`** is `comp_probe`'s and is **twelve tasks flagged**;
   the replacement is **0.2350/0.2336 standing, 0.3063/0.3004 moving** — PROPOSED TEXT ONLY [§2D].
6. ★★ **Real-time pacing**; **typing cadence**; **`checkPriority`/`checkCollision`**;
   **`MAP_PRI_BANDS`** at `memmap.inc:310` — **the thirty-fourth task.**

### 9 — User interaction during task
None. ★★ No eye gate was offered: no shipped byte changed, and the arms are byte-identical to the
build Jay watched at T-P0-141.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-22-both-arms-off-or-neither-guard-is-red.md`

### 11 — Commit
`1a0ff9d`  (pushed to origin/wip before this report)
Pool candidate `e2b6993` (methodology-candidate-pool, main).
