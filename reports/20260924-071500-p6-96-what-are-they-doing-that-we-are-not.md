## Form B Report — T-P0-150 / P6.96 — What are they doing that we are not?
**Class:** measurement. wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-24 (HEAD `5f7861b`, wip). git status clean at t0.

### 1 — Summary

**The 61-task-old question is answered, and the answer is split in two.**

★★★★★ **THEY DO NOT CACHE RENDERED ROOMS.** A **re-entry** to the starting room cost **359,361
writes and 7,967 FDC accesses** over 5 s against a **first visit's 347,924 and 12,299** — **no
saving, and it still read the disk.** All five transitions in the recording read the disk. **The room
is re-rendered on entry.**

★★★★★ **BUT T-P0-015'S CAPTURE WAS REAL, AND IT IS NOT A ROOM CHANGE.** Two zero-disk bursts of
**~28,500 writes, 98% into ONE 4 KB bucket, in 0.17 s**, occur **mid-room** — t=135.2 s inside one
room and t=224.5 s inside another, at no transition. Their profiles are near-identical (28,529 /
28,545 writes; b7 21,800 / 21,813), so it is **one operation happening twice**. ★★★★ **The rate
corroborates it independently: 10.5 cycles per write at 1.789 MHz, and a 16-bit 6809 copy loop
(`ldd ,x++` / `std ,u++`) is ~10.5 cycles per byte.** It is a block copy — most plausibly a message
window's save/restore, which copies a screen region and needs no disk.

★★★★★ **AND THE TOOL BUILT TO TEST THE HYPOTHESIS COULD NOT HAVE FOUND IT.** `sierra_rooms.py`'s
detector requires **`min_fdc >= 2000`**, so a **zero-disk** event is invisible to it by construction.
★★★★ **The instrument excluded the exact case the hypothesis predicted** — which is why the question
stayed open for 61 tasks while a tool "for it" ran repeatedly and reported nothing.

★★★ **The useful half is what it prices for US, not what it copies from them**: at their demonstrated
**10.5 cycles/byte**, a 40,320 B room copy (26,880 visual + 13,440 priority) is **0.237 s against our
6.16 s room change.** **Caching rooms is worth it for us whether or not Sierra does it.**

**No `src/` change** (AC-5: 0 files). ★★ **Observation only** (AC-6).

### 2 — Files modified
- `harness/tools/sierra_writes.py` — **NEW.** T-P0-015's whole-map write census analysis, with the
  copy-versus-render discriminator stated before any number is quoted.
- `harness/tools/sierra_live.lua` — §9 delta 1: its 61-task-old banner now records that the census
  was run and what it found (comment only; the file stays observe-only).
- `harness/tools/gates.manifest` — §9 delta 2: the transition table beside P6.91's and P6.94's.

### 3 — Reasoning

**§3(1)** — nine arms at P6.95's figures; this task changed no `src/`.

**§3(2) — was T-P0-015's census ever run? THE CENSUS WAS BUILT AND NEVER ANALYSED.** ★★★★★
`sierra_live.lua`'s `frames.csv` header carries `total` plus **sixteen 4 KB buckets `b0..bF`** — the
whole-map census the banner asked for. ★★★★ **Two recordings already contained it**
(`build/sierra_bench_live/frames.csv` from P6.91, 36 M writes; `build/sierra_pen/frames.csv` from
P6.94, 23,908 frames). ★★★ **So §4A needed no new operator run at all** — the data had been sitting
in the tree since P6.91, and this task is the analysis half.

★★ **That is the answer to §3(2)'s question and it changed the task's shape**: the dispatch expected
a driving session, and the measurement was already on disk.

**§3(3) — what `sierra_live.lua` can sample.** FDC port accesses at `$FF40-$FF4F`, **write**
addresses across `$0000-$FEFF` bucketed to 4 KB, GIME register writes at `$FF90-$FFBF`, the VOFFSET
pair, and a 16×10 screen lattice. ★★★★ **No PC sampling exists there**, and it has **no input path by
design** — its own banner says three trigger designs failed before that was understood. **It stayed
observe-only; nothing was added to it but a comment.**

**§3(4) — `pc_profile.py` needs a symbol map** we do not have for their binary, so §4B's output would
have been an **address histogram, not routines.** ★★ **§4B was not reached** — §4A consumed the task,
which AC-3 explicitly permits.

**Authority tier.** Every figure is **tier 2, the running original**, observed from outside. ★★★★
**No instruction of theirs was read or interpreted** (AC-6).

**§2H's three checks.** (1) *A second mechanism for a different object class?* ★★★★★ **Yes, and it is
the whole finding**: there are **two** distinct fast-screen-change mechanisms — the disk-backed room
render and a zero-disk block copy — and T-P0-015 saw the second and reasoned about the first.
(2) *The calling routine.* The bursts occur **mid-room**, which is what identifies them as not a
transition; the *when* carried the meaning, not the byte count. (3) *Grep the reports.* P6.91 (the
rooms table), P6.94 (the pen), and T-P0-015's banner are the prior art; **the banner's hypothesis and
`sierra_rooms.py`'s `min_fdc` floor contradict each other and nobody had noticed.**

**§2S.** No sibling claim is made.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: measurement]** **PASS — five transitions, first visit versus re-entry.**

  | transition | writes / 5 s | FDC | note |
  |---|---|---|---|
  | RC1 76.2 s | 347,924 | 12,299 | first visit, unintended room |
  | **RC2 157.8 s** | **359,361** | **7,967** | ★★★★★ **RE-ENTRY to the starting room** |
  | RC3 267.2 s | 434,937 | 6,908 | outside |
  | RC4 288.9 s | 348,113 | 7,975 | into the chicken pen |
  | RC5 391.7 s | 398,319 | 3,059 | the death room |

  ★★★★ **The re-entry is not cheaper and is not disk-free.** ★★★ Jay's route makes RC2 a return to a
  room first drawn at boot [P6.94 §4A], so it is the pair the hypothesis needed, and it shows no
  saving.

- **AC-2 [class: attribution]** ★★★★★ **NO — they do not cache rendered rooms**, on the evidence in
  AC-1: a re-entry costs a first visit's writes and still reads the disk.

  ★★★★ **And the observation that prompted the hypothesis is separately explained**:

  | window | writes | top 2 buckets | FDC | seconds |
  |---|---|---|---|---|
  | t=135.2 s | **28,529** | **b7 21,800** + b0 6,151 = **98%** | **0** | 0.17 |
  | t=224.5 s | **28,545** | **b7 21,813** + b0 6,156 = **98%** | **0** | 0.17 |
  | RC2's draw phase | 6,656 | b7 3,547 + b8 1,354 = 74% | 1,068 | 0.17 |
  | RC4's draw phase | 3,642 | b7 2,087 + b0 430 = 69% | 283 | 0.17 |

  ★★★★★ **The two zero-disk bursts are a block copy**: bounded (~28.5 K), concentrated (98% in one
  4 KB aperture), fast (0.17 s), disk-free, and **twice with near-identical profiles**. ★★★★ **The
  rate is the independent corroboration — 10.5 cycles per write at 1.789 MHz against a 16-bit 6809
  copy loop's ~10.5 cycles per byte.** ★★★ **They occur mid-room**, so they are not room restores;
  a message window's save/restore is the obvious candidate and is a copy of a screen region.

  ★★ **A render looks different in the same instrument**: RC2's and RC4's draw phases show only
  3.6–6.7 K writes in their first 10 frames because a render is **spread over 1.0–1.7 s**, which is
  T-P0-015's own stated discriminator working as designed.

- **AC-3 [class: measurement]** ★★ **NOT REACHED — §4A consumed the task**, which AC-3 permits.
  ★★★ §3(4) records what it would have produced (an address histogram, not routines) and §7(3) carries
  it forward.

- **AC-4 [class: measurement]** ★★★ **§4A was NEGATIVE, so there is nothing to copy from them** — and
  the price for us is worth stating anyway:

  > **At the 10.5 cycles/byte they demonstrate, a 40,320 B room copy is 0.237 s. Our room change is
  > 6.16 s and 91% of it is the render** [P6.85]. **~5 blocks per room, ~46 free on 512 KB.**

  ★★ **Shape only, not built** [§4C]: keyed by room number; invalidated by anything that draws into
  the picture — **`add.to.pic` is the named invalidator** and T-P0-112 already recorded that it must
  write the shadow. ★★★ **A cached room that has been drawn into is stale**, and that is the hard
  part, not the copy.

- **AC-5 [class: byte-comparable]** **PASS.** `git diff --name-only -- src/` counted **0** files.

- **AC-6 [class: process]** ★★★★★ **PASS, stated explicitly.** **Nothing was written into their
  machine** — `sierra_live.lua` has no input path and only a comment was added to it; no new run was
  even performed, because the data already existed. **No instruction of theirs was read or
  interpreted.**

  **What was sampled, exhaustively:** FDC port accesses (`$FF40-$FF4F`), **write addresses** across
  `$0000-$FEFF` bucketed to 4 KB, GIME register writes (`$FF90-$FFBF`), the VOFFSET pair, and a 16×10
  lattice of screen pixels. ★★★★ **All of it is "what address, how often" — bus activity, never "what
  instruction"** [§6's line].

- **AC-7 [class: suite]** **PASS by §2T citation.** `src/` untouched, so no artifact changed. Cited
  from **P6.95's report §5, run 2026-09-24 at HEAD `7b284d1`**: `comp` 124/124, `cel` 9,193/9,193,
  `res` 1,264/1,264, `pic` 45/45, five p3b probes, *"all green"*, exit 0; nine arms byte-identical to
  the re-baselined figures. ★ No sibling touched.

- **AC-8 [class: ruling requested]** **PASS** — §7.

- **AC-9** **PASS.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
=== §3(2), the census WAS built (sierra_live.lua's frames.csv header) ===
frame,time_s,changed,fdc,voffset,total,b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,bA,bB,bC,bD,bE,bF,
n_mmu,n_pal,n_vid,init0,vmode,vres,border
   -- 23,908 frames, 36,026,290 writes already on disk from P6.94. No new run needed.

=== AC-1, five transitions (sierra_writes.py, 5 s windows) ===
RC1 76.2s  (into unintended rm)   5.00 s 300 fr  writes  347924  fdc  12299  top b0:129637 b7:93907
RC2 157.8s RE-ENTRY to start      5.00 s 300 fr  writes  359361  fdc   7967  top b0:139908 b7:65267
RC3 267.2s (outside)              5.00 s 300 fr  writes  434937  fdc   6908  top b0:144974 b1:115102
RC4 288.9s (INTO THE PEN)         5.00 s 300 fr  writes  348113  fdc   7975  top b0:116106 b7:69536
RC5 391.7s (death room)           5.00 s 300 fr  writes  398319  fdc   3059  top b0:130505 b1:118480

=== AC-2, the zero-disk bursts against real draw phases (10-frame windows) ===
t=135.2 peak33 ZERO DISK      0.17 s 10 fr  writes 28529  fdc    0  top b7:21800 b0:6151  top2 98%
t=224.5 peak29 ZERO DISK      0.17 s 10 fr  writes 28545  fdc    0  top b7:21813 b0:6156  top2 98%
RC2 draw phase (RE-ENTRY)     0.17 s 10 fr  writes  6656  fdc 1068  top b7:3547 b8:1354   top2 74%
RC4 draw phase (disk-backed)  0.17 s 10 fr  writes  3642  fdc  283  top b7:2087 b0:430    top2 69%

=== AC-2, the rate corroborates a copy loop ===
t=135.2  28529 writes in 0.1667 s -> 10.5 cycles per write at 1.789 MHz
t=224.5  28545 writes in 0.1667 s -> 10.4 cycles per write at 1.789 MHz
a 16-bit 6809 copy loop  ldd ,x++ / std ,u++ / ...  = ~10.5 cycles per byte
   ★ these two independent facts agree, which is what makes "block copy" a finding and not a guess

=== AC-2, why sierra_rooms.py could never have found it ===
sierra_rooms.py: params gap=0.5s settle=1.0s min_lat=30/160 min_fdc=2000
   -- a ZERO-DISK event cannot pass min_fdc >= 2000. The tool built to test the hypothesis
      excludes the case the hypothesis predicts.

=== AC-4, what it prices for us ===
a 40,320 B copy (26,880 visual + 13,440 priority) at 10.5 cyc/B at 1.789 MHz = 0.237 s
our room change 6.16 s, 91% render [P6.85]

=== AC-5 / AC-6 ===
$ git diff --name-only -- src/     ->  0 files
nothing written into their machine; no new run performed; no instruction read or interpreted
sampled: FDC $FF40-$FF4F, write addresses $0000-$FEFF bucketed to 4 KB, GIME $FF90-$FFBF,
         VOFFSET $FF9D-$FF9E, a 16x10 screen lattice
mojibake: sierra_writes.py clean, sierra_live.lua clean, gates.manifest clean, exit=0
```

**25.2 bundled-artifact grep:** N/A — nothing built or bundled.

**25.3 operator-runtime-smoke:** **N/A — no run was performed.** ★★★ The measurement came from
recordings Jay had already driven at P6.91 and P6.94; **no new operator time was spent**, which is
§3(2)'s dividend.

### 6 — Reactive deviations and route accounting

1. ★★★★★ **No operator run was made, and the dispatch assumed one** (§4A: *"Drive the pen and the
   adjacent rooms"*). §3(2) found the census already recorded in two existing `frames.csv` files, so
   **the task became analysis of data in hand.** ★★★ That is a deviation in method and it saved a
   session; the figures are P6.94's recording, which Jay drove.
2. ★★★★ **I nearly quoted the five transitions as the whole answer.** They all read the disk, which
   looked like a clean refutation — until `sierra_rooms.py`'s `min_fdc >= 2000` floor showed that
   **a zero-disk transition cannot appear in its output at all.** ★★★ **The search then had to be
   built from the raw lattice rather than taken from the tool**, and that is what found the bursts.
3. ★★ **§4B was not reached.** AC-3 permits it; §7(3) carries it.
4. ★ **The bursts' identity is inferred, not established.** "A message window's save/restore" is the
   most plausible candidate consistent with mid-room timing, a screen-region-sized copy and no disk —
   **but §6 forbids reading their code to confirm it, so it stays a candidate** [§7(2)].

**ROUTE ACCOUNTING.** I proposed no route to Jay and asked for nothing. What this change contains:
one new analysis tool and two comment blocks. What it does **not** contain: any room cache, any
change to `sierra_live.lua`'s behaviour, any new recording, and any `src/` byte.

### 7 — Uncertainty flags, and AC-8's ruling request to Jay

★★★★★ **The three answers:**

> **1. Do they cache rooms? NO.** A re-entry costs a first visit's writes and still reads the disk.
> **2. Was T-P0-015's capture real? YES, and it is not a room change** — a ~28.5 K-write block copy,
> 98% into one 4 KB aperture, 0.17 s, zero disk, twice, at a 6809 copy loop's exact rate.
> **3. Is the per-pixel gap explained? NO** — §4B was not reached, and P6.94's ~6× load sensitivity
> stands unexplained.

**What I am asking you to rule on:**

1. ★★★★★ **Do we cache rendered rooms anyway?** **It is worth 6.16 s → ~0.24 s on a re-entry**, and
   the memory exists (~5 blocks per room, ~46 free). ★★★★ **Sierra not doing it is not an argument
   against it** — they re-render and they pay for it; **we are 4.3× slower per render than they are**
   [P6.94], so the same saving is worth more to us. ★★★ **The hard part is invalidation, not the
   copy**: `add.to.pic` must mark a cached room stale.
2. ★★★★ **Should §4B still happen?** The per-pixel question is the one that would explain P6.94's
   ~6×, and it needs an address histogram from a new operator run. **It is the only route left to
   "what are they doing that we are not".**
3. ★★★ **Is `sierra_rooms.py`'s `min_fdc` floor worth fixing?** As it stands the tool cannot see a
   disk-free transition, and **it will hide the next one too.**

**Uncertainty flags:**
1. ★★★★★ **The bursts' identity is a candidate, not a finding.** Mid-room, screen-region-sized,
   disk-free and twice-identical is consistent with a message window; **confirming it would require
   reading their code, which §6 forbids.** ★★★ What is established is *block copy*, not *of what*.
2. ★★★★ **A bucket is an APERTURE, not a destination.** The CoCo3 pages 512 KB through eight 8 KB
   slots, so two physical blocks visible at different times land in the same 4 KB bucket. **"98% in
   b7" means 98% through one window, not into one place.**
3. ★★★★ **One recording, one operator session, five transitions, one title.** The re-entry evidence
   is **a single pair** (RC2 against RC1 and against the boot draw).
4. ★★★ **"They do not cache" is proven only for a disk-backed re-entry within one session.** A game
   that cached only some rooms, or only within a location, would look like this.
5. ★★ **The 10.5 cycles/write figure assumes 1.789 MHz.** At 0.894 MHz it is 5.2, which no copy loop
   achieves — so the figure also **implies they run in fast mode**, consistent with the port's own
   `HAL_SYS_FAST_CLOCK`. Not independently confirmed here.

### 8 — Follow-up candidates

1. ★★★★★ **A room cache on our side** — §7(1). **0.237 s against 6.16 s**, and the invalidation
   shape is named.
2. ★★★★★ **§4B, the per-pixel histogram** — §7(2). **The only remaining route to P6.94's ~6×.**
3. ★★★★ **`sierra_rooms.py`'s `min_fdc` floor** — §7(3). It cannot report what it was built to find.
4. ★★★★★ **Put the cel cache in the gated arms** — P6.93 §7(1), **open across four tasks now.**
5. ★★★★ **A gated scene with overlapping sprites** — P6.95 §8(1); our corpus cannot see draw order.
6. Carried: region A at 151 B; the VIEW checksum gap; design spec §7.1's `0.039 s/cycle`; the
   static/regular sprite split; option 3 and the sidecar; real-time pacing;
   `checkPriority`/`checkCollision`; `MAP_PRI_BANDS` (forty-first task — ★ `memmap.inc` is a §6 stop
   trigger, not bumped).

### 9 — User interaction during task
None. ★★ **The measurement used recordings Jay drove at P6.91 and P6.94; no new operator time was
required.**

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-24-the-detector-excluded-the-case-it-was-built-for.md`

### 11 — Commit
(recorded below after push)
