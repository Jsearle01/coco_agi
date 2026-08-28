## Form B Report — P3.12 — locating the picture-buffer writer by difference
**Class:** recon.  wip.

★★ **No numbered dispatch.** This is operator-directed follow-on from T-P0-020 §8.1 — Jay:
*"do it"* — executing the follow-up that report proposed. **Scored against the three standing
questions from T-P0-018 §4, not against a dispatch's ACs**, and §4 says so explicitly.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-28 (HEAD at start `72a74c8`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim

```
coco_agi         wip  72a74c8de007492e1d6dd9569823a3998fd364cb  tracked-dirty 0
POP3_port        wip  430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip  78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
lwasm from lwtools 4.24        MAME 0.281 (mame0281)
[hal-sync] coco_agi OK / POP3_port OK / karateka_coco3 OK
[reg-discipline] scope: src/engine   0 register access(es).   ★ no src/** change this task
```

★ **§2T — POP `430a91c` and Karateka `78c8c27` unchanged from T-P0-020 §0.**

---

### 1 — Summary

★★★ **THE ROUTINE IS LOCATED, AND IT IS NOT THE WHOLE-PICTURE FILL. Both halves matter.**

**Located** — `$909A`, by difference rather than by threshold:

```
  PC       in-burst     idle    of 24 distinct picture-buffer writers
$E95F         6,506   54,200    background -- runs in both regimes
$909A         4,283        0    ★★★ THE ONLY BURST-ONLY WRITER, 28.9% of burst writes
```

**Read** — PC-gated so the trigger cannot catch a different routine, because it *is* the routine:

```
$9088  CMPX ,S     bound check                 7 cy   ★ boundary test 1
$908A  BCC         exit                        3
$908C  TST ,U      test the source byte        6 cy   ★ test 2
$908E  BNE         skip zeros                  3
$9094  LDA ,X      load destination            4
$9096  EORA ,U+    ★ XOR the source in, U++    6
$9098  STA ,X+     store back, X++             6
$909A  BRA                                     3
                              43 cycles per byte, TWO tests per byte
```

> **Ours: 3.09 boundary tests per pixel at 86 cycles = 266 of a 506-cycle pixel — 52.5% of the
> whole render.**

★★★ **AND THE LIMIT, STATED BEFORE ANYONE QUOTES THE NUMBER: this is not the region fill.** It
wrote **971 bytes** in the traced window against a **16,320-byte** picture region, and
`LEAU $9074,PCR` resets its source every ~11 bytes — **the shape of a pattern or brush
primitive, one AGI drawing opcode, not a region fill.** ★★ **Naming it "the fill" because it is
the routine I was hunting is exactly the P3.9 and P3.10 error**, and §3.4 is the check that
refused it.

★★ **What made this work after four failures is that it has no trigger.** The cel blitter runs
every frame; the room load runs on a disk burst. **The two differ in WHEN, not WHERE** — so two
PC histograms and a subtraction beat every threshold that was tried on WHERE.

### 2 — Files modified
- **`harness/tools/sierra_pcdiff.lua` — NEW.** The differential: two PC histograms over writes
  into the picture buffer, one during disk bursts and one otherwise. **No trigger, no capture
  budget.**
- **`harness/tools/sierra_readfill.lua` — NEW.** Traces gated on **PC reaching `$909A`**.

**No `src/**` change.** No game data, dumps, binaries, traces or states committed (§2P).

### 3 — Reasoning

**3.1 ★★★ Why every earlier attempt failed, in one sentence.**
Four attempts triggered on a **proxy** for the fill — the disk, ordering, timing, run length,
write region. ★★ **A trigger on a continuously-written region catches the continuous writer,
whatever the threshold**, and no threshold fixes that because the problem is the base rate, not
the cutoff.

**3.2 ★★ The buffer was wrong, and that came from Jay's steer.**
[Jay, T-P0-020] *"does it really matter what is in the buffer if you can determine the code that
puts it there?"* Deriving the buffer from the blit's own source pointer gave **`$2000`–`$5F60`**,
and that region is **nearly silent during play**:

```
$2000-$5F60 :      ~40 writes in 35 s of ordinary play
$0000-$5FFF : 12,000+ writes every TEN FRAMES        <- what I had been watching
```

★★★ **The cel blitter lives below `$2000`. Three attempts were spent watching a region that was
mostly not the picture at all** — and the address that fixed it came from reading the code, not
from filtering traffic.

**3.3 ★★★ The instrument: the background as the control.**
Two histograms of the PC at every write into the buffer, split by whether the FDC was active,
accumulated over the whole session and subtracted. ★ **`SAMPLE=1`** — every write, because the
region is quiet enough to afford it [L-44: stated]. ★★ **A dry run first confirmed the tap fires
and the region is quiet (5 samples in 35 s), which is what made 1-in-1 sampling affordable**
[L-47].

★ Then the trace is gated on **PC == `$909A`**. **A PC is not a proxy**, so the capture cannot be
spent on a different routine — the failure mode of all four previous attempts is structurally
impossible here.

**3.4 ★★★ THE CHECK THAT REFUSED THE ANSWER I WANTED.**
`$909A` is burst-only, writes the picture buffer, and appeared after four failed attempts. ★★
**Every incentive was to call it the fill.** Three measurements say otherwise:

```
bytes written in the traced window            971      vs a 16,320-byte picture region
LEAU $9074,PCR executed                        88      -> the source resets every ~11 bytes
share of burst writes                       28.9%      -> ~15,000 bytes are written by something else
```

★ **A routine whose source is an 11-byte repeating pattern XORed into the destination is a
brush or texture primitive.** ★★★ **It is a real finding and it is not the one the thread has
been chasing, and those two facts have to be reported together.**

**3.5 ★★ What is left, and why it needs a different KIND of cut.**
The only candidate for the remaining ~15,000 bytes is **`$E95F`** — and it runs in both regimes
(6,506 burst against 54,200 idle), so **the burst/idle difference cannot isolate it by
construction.** ★★★ **What can: breakpoint it and log its REGISTERS, then compare the parameters
it is called with during a room load against those during idle play.** Same routine, different
arguments — a discrimination a PC histogram cannot make and a register log can. ★ **That is not
a better threshold; it is a different observable.**

**3.6 ★ A slip the harness caught, and why it printed it.**
`sierra_readfill.lua` prints its trigger back **in hex**, and printed `$907A` — I had converted
`0x909A` to 36986 instead of 37018. ★★ **Printing a derived constant back in the units it was
derived from is one line and it caught an arithmetic error before it cost an operator run.**

**3.7 §2.2 / §2S.** MC6809 cycle counts are read from POP3_port's `docs/ground-truth/`;
`coco_agi`'s is empty — **orchestrator-unverifiable**. POP `430a91c`, Karateka `78c8c27`, both
`wip`, at those refs.

### 4 — Verification (against T-P0-018 §4's three standing questions)

★ **No dispatch, so no dispatch ACs.** Scored against the questions the thread exists to answer.

- **Q1 — the fill's algorithm [class: state-comparable] ★★ PARTIAL.** One drawing primitive is
  read in full: an **XOR-merge of a repeating ~11-byte source into the destination, with a
  bound check per byte**. ★★★ **The region fill remains undetermined** (§3.4). **No guess is
  recorded** [L-26].
- **Q2 — boundary-test cost and frequency [class: state-comparable] ★★ ANSWERED FOR THIS
  PRIMITIVE ONLY.** **2 tests per byte, 43 cycles per byte total; the bound check alone is
  `CMPX ,S` + `BCC` = 10 cycles.** Against ours: **3.09 tests per pixel at 86 cycles.**
  ★ **It is not the region fill's number, and it must not be quoted as one.**
- **Q3 — one pass or two [class: state-comparable] COULD NOT DETERMINE.**
- **Location [class: state-comparable] ★★★ PASS.** `$909A`, isolated as the only burst-only
  writer among 24, **zero in 79,823 idle samples** — and confirmed by tracing on the PC itself.
- **Cross-check [class: state-comparable] ★★★ PASS, AND IT REFUSED THE HEADLINE.** 971 bytes
  against 16,320 (§3.4). ★★ **The AC that has done the most work in this thread is the one that
  rejects candidates.**

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
=== the differential, one operator run ===
=== FINAL: 14833 samples in bursts, 79823 idle, 4 disk bursts seen ===
      PC  in-burst      idle   verdict
  $E95F      6506     54200   background (the cel blitter and friends)
  $909A      4283         0   ★★★ BURST ONLY -- candidate for the fill
  $0730       270      1491   background
  $071B       270      1491   background
  ...
distinct PCs writing the picture buffer : 24
BURST-ONLY PCs (zero idle samples)      : 1
their share of burst samples            : 4283 of 14833  (28.9%)
```

```
=== the PC-gated trace: three captures, the trigger cannot miss ===
TRACE 1 ON at t=152.428  (PC $909A reached)
TRACE 1 OFF -- 67462 instructions, 1042 picture-buffer writes in the window
TRACE 2 OFF -- 39793 instructions,   63 picture-buffer writes
TRACE 3 OFF -- 18330 instructions,  283 picture-buffer writes
```

```
=== the loop, from the traced stream ===
     PC  instruction           executed  cyc  role
  $9088  CMPX ,S                    971    7  ★★ BOUNDARY TEST: X against a limit on the stack
  $908A  BCC $909C                  971    3    exit if past the end
  $908C  TST ,U                     970    6  test the SOURCE byte
  $908E  BNE $9094                  970    3    skip if zero
  $9090  LEAU $9074,PCR              88    5  ★ SOURCE RESETS -- an ~11-byte repeating pattern
  $9094  LDA ,X                     970    4  load the DESTINATION byte
  $9096  EORA ,U+                   970    6  ★★★ XOR the source in, U++
  $9098  STA ,X+                    971    6  store back, X++
  $909A  BRA $9088                  971    3  loop
★★★ CYCLES PER BYTE: 43        BOUNDARY / TEST INSTRUCTIONS PER BYTE: 2
    OURS: 3.09 boundary tests per pixel at 86 cycles = 266 cy/px inside a 506-cy pixel

hot regions:  $E769-$E7B5  71.5%  <- the cel blitter
              $9088-$909A  11.6%  <- ★★★ THIS LOOP
```

```
=== §3.2: the buffer, and why three attempts missed ===
$2000-$5F60 (from the blit's own source pointer):  ~40 writes in 35 s of play
$0000-$5FFF (what I had been watching):        12,000+ writes every ten frames
```

25.2 bundled-artifact grep: **N/A** — nothing built.

25.3 operator-runtime-smoke: **N/A — no visual surface.** ★ Launch path `live-disk` via
`-state agi_ingame`; the run was operator-driven.

### 6 — Reactive deviations and what I think it means

★★ **No dispatch to deviate from.** The scope executed is T-P0-020 §8.1 as written.

★★★ **WHAT I THINK, AND IT IS A RECOMMENDATION TO STOP DIGGING.**

> **Six tasks have established what the gap is NOT — not blanking, not a page flip, not an MMU
> swap, not overdraw, not pixel count, not a shadow-buffer trick. What survives is that we test
> each pixel 3.09 times at 86 cycles, and that is 52.5% of our render.**

★★ **Both Sierra numbers now point the same way and neither is their region fill:** their
presentation pass does **zero tests at 24 cycles per pixel**; their one read drawing primitive
does **two tests at 43 cycles per byte**. ★ **We do three at 86.**

★★★ **The next task should be a design task on OUR renderer, not a fifth attempt at theirs.**
T-P0-014 already measured what it needs: span median 9, p90 56, **74.5% of pixels in
fully-contained 8-pixel groups**. A fill that tests once at each end of a run instead of once
per pixel has a measurable target, gates against the 45-picture oracle, and needs nothing
further from Sierra. ★★ **And §7 of T-P0-020's constraint is satisfiable: we can say WHY it is
cheaper, which is what licenses adopting it.**

★ **`$E95F` remains available if the Orchestrator wants their region fill** (§3.5), but **it is
optional**, and it needs a register log rather than another threshold.

### 7 — Uncertainty flags
- ★★★ **`$909A` IS NOT THE REGION FILL** (§3.4) and its 43 cy/byte must not be quoted as
  Sierra's fill cost.
- ★★★ **The region fill is still unlocated** after four attempts across three dispatches.
- ★★ **`$E95F` is a candidate, not a finding** — it is the only remaining writer, which is an
  argument from elimination over a set of 24, not an identification.
- ★★ **The ~11-byte pattern reading is inferred from `LEAU $9074,PCR` firing 88 times over 970
  bytes.** ★ **The pattern's contents were not read.**
- ★ **One operator session, four disk bursts, KQ3 Floppy 360K** [L-24, L-33]. **I-19** applies.
- ★ **`SIERRA_ASSUME_INGAME=1` is still an assertion** carried from T-P0-020 §3.6.

### 8 — Follow-up candidates
1. ★★★ **A DESIGN TASK ON OUR FILL, against 3.09 tests × 86 cycles = 266 cy/px (52.5% of the
   render).** ★★ **Highest value, needs nothing from Sierra, gates against the oracle.**
2. ★★ **`$E95F` by register log** — same routine, different arguments in the two regimes (§3.5).
   ★ **Optional.**
3. ★ **Re-derive MMU/VMODE/VOFFSET on a state-restored run** instead of asserting them; it makes
   every future operator run cheaper and fully instrumented.
4. ★ **Read the 11-byte pattern at `$9074`** to confirm §3.4's brush reading.

### 9 — User interaction during task
1. ★★★ *"do it"* — authorised this follow-on directly.
2. ★★★ **The method is Jay's, from T-P0-020**: *"you can deduce what is going there from the
   code."* ★★ **It produced the buffer address that three traffic-filtering attempts could not,
   and that address is why the differential worked.**
3. One operator run.

### 10 — Candidate(s) captured this task
Two, to `seeds/AGI/live/` (§2C — new rows):
1. ★★★ **`when-where-cannot-separate-two-things-try-when`** — four attempts failed to isolate a
   routine by the region it writes, because a busier routine writes the same region. The two
   differ in **timing**, so two histograms split by an independent condition and subtracted found
   it with no trigger, no threshold and no capture budget. **The background became the control.**
2. ★★ **`print-a-derived-constant-back-in-the-units-it-came-from`** — a harness echoed its
   trigger address in hex and revealed `$907A` where `$909A` was meant; the decimal conversion
   was wrong by 32. **One line of output, one operator run saved.**

### 11 — Commit
<COMMIT>
