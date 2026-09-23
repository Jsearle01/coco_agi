## Form B Report — P6.83 — The VIEW stops being copied
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-22 (HEAD `d210bf6`, wip). `git status` clean apart from an untracked
`coco_agi.code-workspace` that predates this task.

### 1 — Summary
`p3_composite_all` no longer copies a sprite's VIEW into the arena. It calls `res_locate` and the
decoder reads the cel through the volume window — header fields by `res_peek`, the compressed
stream by a new cursor that maps once and re-maps on crossing. **The arena allocation for a sprite
is now zero**, so the LOGIC cache stops starving: **hits/misses/evictions 3/1/1 → 4/0/0, bytes
re-fetched 3,817 → 0, s/cycle 0.761 → 0.679** (median 0.400 → 0.334), and the cache holds all five
castle LOGICs instead of four. **Pixels are identical** — `co_WRITTEN 11360` and `CP_BLITS 128` on
both paths. P6.81's trim stopped firing, which was the dispatch's prediction.

★★★★ **§1.1's premise held and AC-5 is what tested it**: the compositor now reads through slot 6 by
design, and nothing writes into the staged volume. ★★★ **Jay: "definitely notice it is faster, but
still not enough."**

★★★★★ **Two things this task could not close and both are reported rather than worked around**: the
`-IfRec` diagnostic arm no longer assembles (region A is full, and the assertion's own remedy is a
map ruling), and **the resource checksum now covers nothing for a VIEW**, which is a real widening
of P6.48's blind spot 1.

### 2 — Files modified
- `src/harness/res_core.s` — `res_cseek`/`res_cnext` (the stream cursor, under `RES_CURSOR`);
  `rl_len` publishes `res_len` from `res_locate`; `-DRES_FAULT_NOCROSS`.
- `src/harness/view_cel.s` — windowed source under `VC_SRC_WINDOWED`: `vc_rd8`, a windowed
  `vc_le16`, the header reads, and `vc_decode_row`'s fetch plus a count-based truncation bound.
- `src/harness/p3b_probe.s` — `res_locate` instead of `res_open`; the invalidation and the
  `res_close` retired; `-DP3B_VIEW_COPY` (the before arm) and `-DP3B_CELTEST` (AC-4).
- `harness/tools/p3b_show.ps1` — `-ViewCopy`, `-CelTest`, `-NoCross`, and their symbols.
- `harness/tools/p3b_run.lua` — `P3B_CELTEST` staging and readout.
- `harness/tools/cel_bytes.py` — NEW: cel spans and the corpus maximum (§4A).
- `harness/tools/p3b_arms_check.ps1` — nine arms re-baselined.

Explicit-path staging only.

### 3 — Reasoning

#### §4A — the straddle question, answered before the code ★★★★★

**1. Can a cel's data cross a block boundary? YES, and it does in the shipped corpus.**
`view_straddle.py --construct` reports **seven KQ1 VIEWs** whose payload crosses an 8 KB boundary
(67, 79, 81, 85, 116, 117, 138). ★★★★ **None of them is the castle's**: views 0, 97 and 107 each
sit inside one block, so 40 cycles of compositing exercise the boundary path **zero times**. That
is L-85's shape and it is why AC-4 is a constructed case rather than a castle run.

**2. Does P6.77's answer transfer? NO, and the reason is arithmetic.**
`res_peek` maps the block holding the **one** byte asked for — straddle-proof by construction, at
`res_ptr`'s **~90 CPU cycles a byte**. Eight header bytes is ~720 cycles against a multi-KB copy,
which is why T-P0-130 took that trade and was right. ★★★★ **A cel's compressed stream is up to
1,552 bytes** (`cel_bytes.py`, corpus maximum: larry1 view 41), and 1,552 × 90 ≈ **140,000 cycles**
against the copy's ~12 a byte. **So the stream needed the other shape** — map once, walk inside the
window, re-map on crossing — which is what `res_fetch`'s own copy already does internally.

★★★ **The split is the design**: `vc_decode_begin`'s ten header reads use `res_peek`;
`vc_decode_row`'s walk uses the cursor.

**3. Would a bounded scratch serve? NO** [§6's suggestion, priced and rejected]. The largest cel is
1,552 B against **~256 B of slack outside the arena** [T-P0-133 §4C]. A cel-sized scratch has the
same memory problem as the VIEW copy, smaller. **In-place is the only shape that needs no memory.**

#### §3(2) — every read of a VIEW's bytes ★★★★★

| reader | before | now |
|---|---|---|
| `vm_set_view` / `set_loop` / `set_cel` [`vm_run.s`] | **already in place** since T-P0-130, via `res_locate`/`res_peek` | unchanged |
| `vc_decode_begin` (loop table, cel table, cel header — ~10 bytes) | flat pointer into the arena copy | ★ `res_peek`, one mapping per byte |
| `vc_decode_row` (the compressed stream) | flat pointer into the arena copy | ★★★★ the cursor |
| `p3_composite_all` (`vc_view`, `vc_srcend`) | `res_base`, `res_base+res_len` | ★ payload offset 0, and `res_len` |
| `cel_probe` / `comp_probe` | host-staged flat memory | ★★★ **unchanged — neither sets the flag** |

#### §3(3) — what `res_open` returned and what `res_locate` offers ★★★★
`res_open` gave `res_base` (a CPU address in the arena) **and** `res_len`. `res_locate` gave
`res_lcoff`/`res_lcoffhi`/`res_lcvol` — **where the payload is, and not how long it is**, because
its only client read fixed header fields and needed no bound. ★★★ **A stream reader needs one**, so
`rl_len` reads the record's LE16 length at +3/+4, each byte through its own mapping. **That is the
only addition to `res_locate`'s contract**, and it is behind `RES_CURSOR` so `vm_probe` does not
carry it.

#### §3(4) — consumers of `res_base` after a VIEW open ★★★
`vc_view` and `vc_srcend` were the only two, both in `p3_composite_all`, both replaced. The
checksum hooks were the third and they are removed rather than left unreachable (§4C). **Nothing
else in the compositor holds a pointer into a VIEW**, which is why this was a contained change.

#### §1.2's four hazards, each answered ★★★★
1. **The compositor writes slot 6 between accesses.** ★★★★★ Answered by checking **per byte**, not
   per loop: `res_cnext` compares `res_cblk` against `res_curblk` — **which is `ph_cur6`, the single
   record P6.82 made structural.** Before that task this cursor could not have been written safely:
   it would have been a fourth cache of the same register.
2. **Straddling.** The cursor's boundary test; AC-4.
3. **`vc_decode_row` writes `CP_CEL` while reading.** ★★★ **Confirmed, not assumed**: `CP_CEL` is in
   `MAP_INPUT`, not slot 6 — and the measurement agrees, since `composite` moved only −2.5%.
4. **The checksum.** §4C below.

#### §4C — what `res_ck_note` covers for a VIEW now: NOTHING ★★★★★
**With no copy there is no resident object to baseline.** The bytes are the game's own, in the
staged volume, read once through an 8 KB window and never held. The baseline and release hooks are
**removed** rather than left in place, because a checksum call on a resource with no resident bytes
would baseline whatever the window happened to hold.

★★★★ **This is a real loss and it is P6.48's blind spot 1 getting wider.** The instrument's purpose
was catching a resource corrupted after it was loaded — **which is exactly what P6.78 was** — and a
VIEW is now outside its reach entirely. ★★★ What still covers the same failure, and is narrower:
the volume write-tap (AC-5), and `res_locate`'s signature check, which sees a window pointing at the
wrong block. **Neither is a per-byte guarantee.** ★★ LOGICs are unaffected — still copied, still
baselined at the bind, still verified on every later bind: `-ResCheck` reads 228 verified, 0
mismatches.

#### §1.3 — the silent drop, kept ★★★
`P3B_SPRSTATS` captures `res_err` at `pca_skip` and is **unchanged**: `res_locate` sets `res_err`
exactly as `res_open` did, on the same failure classes (missing DIR entry, bad signature).

#### §2S — sibling refs
POP3_port HEAD `104b197` (wip), karateka_coco3 HEAD `29f8f0a` (wip); both dirty with pre-existing
work not mine. **No `SHARED` file touched**; `hal_sync_check.py` run in all three repos (§5).
lwasm 4.24 unchanged.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement]** §4A above, before the implementation narrative.

- **AC-2 [state-comparable] All four sprites composite and the pixels are identical.**
  ★★★★★ Same binary family, counters on, same 40-cycle castle window:
  ```
  before (-ViewCopy -Count):  CP_BLITS 128  vc_err 0  last cel 13x4   co_WRITTEN 11360
  after  (windowed  -Count):  CP_BLITS 128  vc_err 0  last cel 13x4   co_WRITTEN 11360
  ```
  ★★★ `restore 28314 bytes` and `staged sprites 4` on both; `P3_PBUF` checksum `$C834` on both.

- **AC-3 [measurement] §4D's five figures, before and after.** Shipped arm (no counters), steady
  castle cycle; the before side is `-ViewCopy` on **this** binary, not a quoted figure:

  | | before | after |
  |---|---|---|
  | **(1)** hits / misses / evictions per cycle | 3 / 1 / 1 | ★★★★★ **4 / 0 / 0** |
  | **(2)** bytes re-fetched per cycle | 3,817 | ★★★★★ **0** |
  | **(3)** s/cycle (sum of stages) | 0.76142 | **0.67854** (**−10.9%**) |
  | | median / mean | 0.4005 / 0.7672 | **0.3338 / 0.7234** |
  | | the resource layer's home stage, `interpret` | 0.36154 (45.8%) | **0.29100 (40.8%)**, **−19.5%** |
  | **(4)** `res_ctrim` / `res_cdrop` per cycle | 1 / 0 | ★★★★ **0 / 0 — the trim stopped firing** |
  | **(5)** arena free | 3,972 B, 4 entries | **155 B, 5 entries (16,229 B)** |

  ★★★★ **`composite` moved only −2.5%** (0.20012 → 0.19514), which is the result worth keeping:
  **reading through the window costs essentially nothing against copying**, and the whole saving is
  L102 no longer being evicted and re-fetched. **The copy was never mainly a read cost; it was an
  arena cost.**
  ★★★ Totals over 40 cycles: misses **41 → 11**, starvation episodes **32 → 1**, trims **34 → 3**.
  ★★ `roomcheck` is unchanged at 0.223 and is now 31% of the cycle.

- **AC-4 [state-comparable · fault injection] A block-straddling cel, decoded by the real path.**
  ★★★★★ **Constructed, because the castle cannot do it.** `cel_bytes.py --view 67 --boundary 2310`
  puts **KQ1 view 67 loop 2 cel 2 at `+2085..+2329`, across the boundary at `+2310`**:
  ```
  windowed (must straddle):  view 67 loop 2 cel 2 -> 18x35, 35 rows, vc_err 0, pixel sum 1678
  -ViewCopy (cannot):        view 67 loop 2 cel 2 -> 18x35, 35 rows, vc_err 0, pixel sum 1678
  ```
  ★★★★★ **And the test is shown able to go RED** [§2W]. `-NoCross` drops the cursor's boundary
  test:
  ```
  -NoCross, straddling cel   (67,2,2):  pixel sum 1622   ★ RED
  -NoCross, NON-straddling   (67,2,0):  pixel sum 1702  = shipped 1702   ★ unchanged
  ```
  ★★★ **The fault fires only where the property it guards applies**, which is the pairing that
  makes the green meaningful rather than a fact about the sample [L-85].

- **AC-5 [state-comparable] logic 1 intact.** ★★★★★ **Delivered by a different instrument than the
  AC names, and the reason is a blocker: `logic_copy_diff.py` reads a snapshot that only the
  `-IfRec` arm produces, and that arm no longer assembles** (§6). The substitute is P6.82's own
  end-to-end instrument, and it is stronger for this question: a write tap on `$A000-$DFFF`
  filtered to KQ1 vol.1's block `$0E`, over a 40-cycle castle run with **128 cels composited
  through slot 6**:
  ```
  RANGETAP A000-DFFF values BB,33:        <empty -- ZERO writes into the staged volume>
  ```
  ★★★★ **P6.78 was sprite pixels landing in that block**; the same tap showed 24 of them on
  P6.82's fault arm. ★★★ Corroborating: logic 1 is now a cache **hit every cycle** (misses 11 over
  40 cycles, none of them logic 1), so even the propagation path P6.78 used is gone.

- **AC-6 [byte-comparable · gate] All five RUN, on the final source.**
  `cel` **9,193/9,193**, `comp` **124/124**, `res` **1,264/1,264**, `vm` **9/9 (0 divergent of 600
  each)**, `pic` **45 PASS / 0 FAIL (of 45)**.
  ★★★★★ **And all five gate probes are BYTE-IDENTICAL** — `pic 2654 E0DDA8F0`, `cel 1527 8B754B9C`,
  `comp 967 39F5D105`, `res 2212 3826E5C0`, `vm 10140 67987995`. **Each links at least one changed
  file and none sets either flag**, so those figures remain claims about the same program.

- **AC-7 [state-comparable] §4C's answer** — above, stated in the source at `pca_gotview`.

- **AC-8 [suite]** `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green (`all green`);
  `-ResCheck` **11 baselined, 228 verified, 0 mismatches, 0 sweep skips**; the mojibake gate clean.
  ★★ `P3B_SPRSTATS`'s drop capture is unchanged (§1.3).

- **AC-9 [eye gate — Jay] RUN FIRST, before the byte gates were reported.** Live, RGB, 300 cycles.
  Expectations stated in the ask. Jay:
  1. *"yes, definitely notice it is faster, but still not enough"* — ★★★★ **expectation met, and the
     qualifier is the finding.** The stated ceiling was given in the ask: 0.679 s/cycle against
     AGI's 100 ms.
  2. *"yes"* — ★★★★ **pixels identical**, as AC-2 measures.
  3. *"yes, still a bit laggy"* — ★★ **matches the stated expectation** (one key per cycle).
  4. *"same preexisting issues"* — ★★★ the title-page items, unchanged and already on §8.

- **AC-10 [manifest]** Nine arms re-baselined: **+205 B** on the three cel-linked arms, **+151 B**
  on the six text arms, the difference being the cel decoder. ★★★ **The five gate probes did not
  move at all**, which is the scoping check.

- **AC-11 [tooling]** `reg_discipline` ★★★★ **still ONE owner** — `6 register access(es) in 1
  file(s)`, so P6.82 held under the first work to lean on it. `hal_sync_check.py` OK ×3;
  `gen_vm_tables.py --check` OK; `probe_identity_check.ps1` every non-p3b probe byte-identical;
  `p3b_arms_check.ps1` all 9 OK, `-SelfTest` red on exactly one row.

- **AC-12** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
=== AC-2 SUMMARY ===  Kingquest1..MixedUpMotherGoose all PASS (vm, 600 cycles each, 0 divergent)

shipped arm, steady castle cycle and totals:
  c40 h4 m0 ev0 tr0 dr0 cn5 top$6000 ccur$609B free155
  RESSTATS totals: hits 143, misses 11, starvation episodes 1, entries trimmed 3,
                   cache emptied 0, cache entries 5, arena free 155 B
  RESSTATS cache holds 5 entr(ies), 16229 B: L0:8999B L83:853B L1:1631B L101:929B L102:3817B
  median 0.3338 s/cycle   SUM 0.67854 s/cycle

before arm (-ViewCopy), same binary, same window:
  RESSTATS totals: hits 113, misses 41, starvation episodes 32, entries trimmed 34,
                   cache entries 4, arena free 3972 B
  median 0.4339 s/cycle   SUM 0.78916 s/cycle        [with -Count on both sides]
  interpret 0.36154 45.8% -> 0.29100 40.8%   composite 0.20012 -> 0.19514

AC-2:  co_WRITTEN 11360 both arms;  CP_BLITS 128 both;  restore 28314 both
AC-4:  CELTEST view 67 loop 2 cel 2 -> 18x35, 35 rows, vc_err 0, pixel sum 1678  (both paths)
       -NoCross same cel: 1622   |   -NoCross cel (67,2,0): 1702 = shipped 1702
AC-5:  RANGETAP A000-DFFF values BB,33 blk$0E:    <empty>
AC-8:  res-checksum: 11 baselined, 228 verified, 0 mismatch(es), 0 sweep skip(s)

[reg-discipline] 6 register access(es) in 1 file(s) over 4 register(s).
  src/engine/mmu_phase.s   6  $FFA3 $FFA4 $FFA5 $FFA6
[hal-sync] OK x3 (coco_agi, POP3_port, karateka_coco3)
CHECK OK: vm_tables.s matches optable.py.
pic 2654 E0DDA8F0 | cel 1527 8B754B9C | comp 967 39F5D105 | res 2212 3826E5C0 | vm 10140 67987995
  ★ every non-p3b probe byte-identical
p3b 15875 FB06064E | p3b_text 17033 7E4AEBEC | p3b_win3 17033 858EC6CD | p3b_notick 17030 B85CA94F
p3b_nomap 17030 B02F48D2 | p3b_fault 16079 D3ED625F | p3b_flat 16064 A5FBBCDD
p3b_comb 19097 793E831B | p3b_comb_count 19132 AA7E8B29
  ★ all 9 arms byte-identical to the recorded baseline (SHA256)
```

**25.2 bundled-artifact grep:** N/A — nine arms and five probes pinned by hash above.

**25.3 operator-runtime-smoke:** **PASSED — Jay, live, RGB, `-Combined`, 300 cycles.** Answers in
AC-9. Run BEFORE the byte gates were reported, per §4A.

### 6 — Reactive deviations and route accounting

1. ★★★★★ **STOP-AND-REPORT: the `-IfRec` diagnostic arm no longer assembles, and the remedy is a
   map ruling.** This change grows p3b by 205 B and `-IfRec` adds its own; the build now fails
   with *"P3b code has grown past MAP_RESERVED_END ($6000) into MAP_ARENA_WIN — region A is full.
   CP_CEL already left for MAP_INPUT and vm_tables is already relocated, so the next move is a
   real one: shrink the code, or take a ruling on the map."* ★★★★ **Every shipped arm builds and
   runs**; it is the diagnostic that is blocked. `memmap.inc` is a §6 stop, so **nothing was
   moved** and AC-5 was delivered by the substitute instrument instead.
2. ★★★ **`res_locate` gained `res_len`**, guarded by `RES_CURSOR` so `vm_probe` is unmoved. A
   contract addition the dispatch's §3(3) asked about and the answer was "the length did not exist".
3. ★★ **`cel_bytes.py` is new** — §4A's size question had no producer, and the answer (1,552 B)
   is what ruled out the bounded scratch.

**A defect this task introduced and caught** [§2W]: the first cursor factored `res_peek` into a
`res_peek_ptr`, which cost **+3 bytes on `res_probe` and `vm_probe`** — two gate probes re-pinned
one task earlier, for a refactor neither can reach. `res_peek` already leaves X at the byte, so the
cursor calls it and both probes are byte-identical. ★★ A second instance of the same shape: the
length read inline pushed three `bne` out of reach and cost `vm_probe` 6 more bytes; a `jsr` costs
3 bytes in the build that wants it and nothing in the build that does not.

★★★★ **A stale artifact nearly became a reported figure.** When the `-IfRec` build failed,
`p3b_show.ps1` threw and left the **previous** run's `run.log` on disk; it read `CP_BLITS 0` at
0.369 s/cycle and I began diagnosing a compositing failure that had not happened. **The assemble
error was three lines above, in output I had filtered out.** [AD-90's shape: a gate reporting on a
binary that was never built.]

**ROUTE ACCOUNTING.** §4A's three-way answer (per-byte peek / bounded scratch / cursor) was
reported before implementing and **the commit contains the cursor and neither of the other two**.
**NOT implemented**: a scratch copy of the cel (priced at 1,552 B against ~256 B of slack), and
`res_peek` for the stream (priced at ~140,000 cycles for one cel).

### 7 — Uncertainty flags

1. ★★★★★ **Still not fast enough, and Jay says so.** 0.679 s/cycle against AGI's 100 ms. The
   resource layer is no longer the binding cost: **`interpret` 40.8%, `roomcheck` 31.2%,
   `composite` 27.3%**, and only the first has been touched.
2. ★★★★★ **A VIEW is no longer covered by the resource checksum at all** (§4C). The instrument that
   existed to catch P6.78's failure class cannot see the class of resource P6.78 corrupted.
3. ★★★★ **Region A is full** (§6(1)). The next task that adds code to p3b hits this, not just the
   diagnostic arms.
4. ★★★ **AC-4 is one constructed cel of one view.** The cursor's boundary path is exercised by
   **exactly one case**; the castle exercises it zero times. A room that drew a straddling view
   would be better evidence and none does.
5. ★★★ **The cursor's "block stolen" path is exercised by the compositor every cycle**, but its
   *slow re-seek after theft* and its *boundary crossing* are separate paths and only the second
   has a fault arm.
6. ★★ **`arena free 155 B`.** The cache now fills the arena to within 155 bytes. **Nothing measured
   here needs that space**, but the margin is gone, and a room needing a sixth LOGIC will trim.

### 8 — Follow-up candidates

1. ★★★★★ **Re-profile, then pick the next target.** `roomcheck` at 31% has never been profiled and
   `composite` at 27% was last measured on the corrupted base. **The ranking that justified the
   last four tasks is now stale.**
2. ★★★★ **Real-time pacing** — out of scope until under 100 ms, and this is the first task where
   that is worth restating as *not yet*.
3. ★★★★ **Region A** (§7(3)) and **the VIEW checksum gap** (§7(2)) are both rulings.
4. ★★★ **The arena shortfall and compaction** — T-P0-134's, now less pressing: with no VIEW copy
   the working set fits.
5. ★★★ **Typing cadence**: one key per cycle, named three tasks running.
6. ★★ **The title page** — the "press a key to continue" carry (P6.79) and the eye gate's room jump.
7. ★★ **`checkPriority`/`checkCollision` and the moat**; **`MAP_PRI_BANDS`** at `memmap.inc:310` —
   **the twenty-ninth task.**

### 9 — User interaction during task
The §4A eye gate, offered before the byte gates were reported, with expectations for each of the
four questions and an explicit note that the title screen is cut by the gate's own room jump. Jay's
answers are quoted in AC-9.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-22-the-cost-you-measured-is-not-always-the-cost-that-binds.md`

### 11 — Commit
`c933f30`  (pushed to origin/wip before this report)
Pool candidate `7d8c391` (methodology-candidate-pool, main).
