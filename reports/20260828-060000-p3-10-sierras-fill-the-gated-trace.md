## Form B Report — P3.10 — Sierra's fill: the gated trace
**Class:** recon.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-28 (dispatch T-P0-019 receipt; HEAD at receipt `335987c`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi         wip  335987c227fa939eaac509b773d5ab7b63b61a4a  tracked-dirty 0
POP3_port        wip  430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip  78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
lwasm from lwtools 4.24        MAME 0.281 (mame0281)

[hal-sync] coco_agi OK / POP3_port OK / karateka_coco3 OK  (11 files compared, all three)
[reg-discipline] scope: src/engine   0 register access(es).

$ python harness/tools/sierra_cost.py build/sierra_pc1/frames.csv
transitions: 5   MMU resolver: 0 of 8825752 unresolved (0.00%)
SIERRA min 28.4 median 32.4  |  OURS 506.5  |  ratio 15.7x
PC $E1B1 x167 / x173 / x171 / x172 / x175      ★ $E1B1 still resolves

MAME TRACE SYNTAX, confirmed from mame-idioms-coco3-port.md before building [L-47]:
  manager.machine.debugger is nil without -debug            (idiom line 2393)
  headless -debug HANGS without execution_state="run"       (idiom §10)
  debugger:command("trace file,cpu[,noloop]") runs from Lua (idiom line 298)
  bp-action tracelog is brace-FREE; trace-action is BRACED  (idiom line 301)
★ And verified empirically before the long capture: a 10-frame trace on a plain boot produced
  1,013 lines of real disassembly.
```

★ **§2T — POP `430a91c` and Karateka `78c8c27` unchanged from T-P0-018 §0.** `src/**` untouched.

---

### 1 — Summary

★★★ **THE FILL IS READ, AND IT IS NOT A FILL.**

The routine that writes the room to the screen — the one at **`$E1B1`**, exactly where T-P0-018
placed it — is a **table-driven format conversion copying a PRE-RENDERED buffer to the display**:

```
  $E1A9  LDA ,X+        load one source byte, X++              6 cy
  $E1AB  ANDA #$0F      keep the low nibble = an AGI colour    2 cy
  $E1AD  LDA A,U        ★★★ 16-ENTRY TABLE LOOKUP              5 cy
  $E1AF  STA ,Y+        ★★★ store to the screen, Y++           6 cy
  $E1B1  DECB           ★ the PC T-P0-018 identified           2 cy
  $E1B2  BNE $E1A9      inner loop                             3 cy
                                              ─────────────────────
                                              24 cycles per pixel
  per row: DEC <$A0 / BEQ / LDD <$A2 / LEAY D,Y / ABX / CMPX #$6000 / BCS   32 cy / 160 px
```

> ★★★ **THERE IS NOT ONE COMPARISON, TEST OR BRANCH ON PIXEL DATA IN THE INNER LOOP.
> ZERO BOUNDARY TESTS PER PIXEL. Ours is 3.09 tests at 86 cycles = 266 cycles per pixel.**
> **24.2 against 506 — and their 24 buys a whole pixel, while our 266 buys only the tests.**

★★★ **AND THAT FORCES TWO CORRECTIONS TO PREVIOUS REPORTS, BOTH MINE:**

**1. ★★★ T-P0-017's "there is no shadow buffer" IS WRONG.** This loop's source is a pointer `X`
bounded by `CMPX #$6000` — **a pre-rendered picture buffer in low memory.** The picture is
interpreted into it and *then* converted to the screen.
★★ **Why the earlier argument failed, precisely:** T-P0-017 reasoned that a copy between
*same-stride contiguous buffers* cannot break its sequential run at a row boundary, and
observed runs stopping dead at 160. **`LEAY D,Y` advances the destination by a SEPARATE STRIDE
loaded from `<$A2`.** Source and destination do **not** share a stride, so the run breaks at
every row exactly as observed. **The observation was right; the premise attached to it was
false, and it was my premise.**

**2. ★★★ T-P0-018's "Sierra's fill costs 32 cycles per pixel" was measuring THIS BLIT, not
their fill.** The draw phase I timed is the conversion pass. **Their actual picture
interpretation — the vector opcodes and whatever flood fill they use — happens earlier, into
the buffer below `$6000`, and its cost is STILL NOT MEASURED.** ★ The 24.2 cy/px derived
statically here and the 28.4–32.4 measured from wall-clock there are the same quantity, which
is why they agree — and neither is Sierra's fill.

★★ **AC-6 passes exactly, which is what makes the above trustworthy:** `STA ,Y+` executed
**10,851** times; the write harness independently counted **10,851** screen writes in the same
frames; **159.6 inner iterations per row** against a 160-byte screen row; and the static
**24.2 cy/px** against the independent **28.4–32.4**.

★★★ **THE GATE TOOK FIVE CUTS AND EVERY FAILURE WAS THE SAME MISTAKE** — triggering on a proxy
for the fill instead of the fill. §3.2 lists them; the working trigger is *a 128+ byte
sequential run landing on the display*.

### 2 — Files modified
- **`harness/tools/sierra_trace.lua` — NEW.** The gated live trace, plus an **auto save-state**
  at the first confirmed room change (§3.6) so future runs skip the 60-second boot.
- **`harness/tools/sierra_readtrace.py` — NEW.** Trace analysis: PC histogram, hot regions,
  store accounting, AC-6's cross-check.

**No `src/**` change.** ★★ **Sierra's binary, all dumps and all trace logs stay in the
SCRATCHPAD** (§2P). **This report describes the algorithm; the listing above is the six
instructions needed to state the finding, not their code.**

### 3 — Reasoning

**3.1 Why a trace and not a dump.** P3.9 resolved `$E1B1` against an earlier session's memory,
where CPU slot 7 held a different block, and got a loop with **no store instruction** — code
that cannot perform 26,000 writes. **MAME's tracer disassembles live, through the map as it
actually is** [Jay], so the failure cause is removed rather than mitigated. ★ The capture's own
metadata records `mmu = 00 3E 3E 09 01 02 03 3F` and `screen_phys = $76000` — the in-game map —
so the context is recorded *with* the artifact and cannot drift from it again.

**3.2 ★★★ FIVE CUTS OF THE GATE, AND THEY ARE ONE MISTAKE REPEATED.**

| cut | trigger | what it caught |
|---|---|---|
| 1 | first disk burst ≥2,000 acc | **the game load** (51,409 acc) — a `LEAX/BNE` disk-wait spin |
| 2 | skip the first room change | **skipped the only room change in the session**, then fired on a 4,548-acc load that was not a transition — a 4-byte-wide strip blitter, maxrun 11 |
| 3 | the instant the disk goes quiet | **all three captures inside 0.5 s of the game loading**, `screen writes: 0` |
| 4 | a 128+ byte sequential run | **sector copies run 256 bytes** — 256 ≥ 128, so it caught the load again |
| 5 | ★★★ **a 128+ byte run LANDING ON THE DISPLAY** | ★★★ **the fill: maxrun 159, 10,851 screen writes** |

★★★ **Every failed cut used a PROXY for the fill — the disk, the ordering, the run length.
The fill has a direct signature: it writes a full screen row into `[VOFFSET, VOFFSET+30720)`.
Nothing else in the draw phase does.** ★★ **Cut 4 is the sharpest lesson: run length alone
cannot separate a 256-byte sector copy from a 160-byte picture row by magnitude, but the
DESTINATION separates them exactly — and the harness already computed it for every write.**

★ **Cut 4 also produced a false confirmation:** the verdict line tested `maxrun >= 128` and
printed *"THIS WINDOW CONTAINS THE PICTURE FILL"* over three windows with `screen writes: 0`.
**The check was reading the wrong half of what I already had.** It now requires both.

**3.3 ★★★ What the loop actually does, and what it does not.**
Six instructions per pixel: load a source byte, mask its low nibble to an AGI colour index
0–15, **look it up in a 16-entry table at `U`**, store to the screen. ★ On this display one AGI
pixel is one byte whose nibbles are equal (160 logical pixels doubled to 320 at 2 px/byte), so
the table is almost certainly *colour index → doubled-nibble byte* — **the doubling is a table
lookup, not arithmetic.**

★★★ **What is NOT in the loop:** no comparison against a fill boundary, no priority-plane read,
no bounds test, no branch on pixel value. **The per-pixel decision-making that dominates our
renderer is absent because it has ALREADY HAPPENED, into the source buffer.**

**3.4 ★★ AC-4's derivation, and its confidence [L-26].**
*High confidence* — the instruction sequence and the execution counts are traced, not inferred.
Cycle counts are standard MC6809 timings `[ref: MC6809-MC6809E Programming Manual, Motorola
1981]`, read from POP3_port's `docs/ground-truth/` (§2.2: `coco_agi`'s is empty;
**orchestrator-unverifiable**).
★ *The one soft edge:* `LDA A,U` is taken at 5 cycles (indexed, accumulator-offset). If it is 4
or 6 the total moves to 23.2 or 25.2 — **which changes nothing about the comparison.**

**3.5 ★★ AC-7 — does this depend on converted resources?**
★★★ **The technique does not; the TABLE does.** *Render off-screen, then convert and blit* is
general, and the 24-cycle loop would work on any source. **But a 16-entry colour lookup exists
because their resources were converted to a CoCo3 palette** — on PC resources we would need our
own mapping. ★ **That is a substitution, not a dependency**, and §2's test is therefore not
obviously failed. ★★ **What is NOT established is whether their off-screen fill depends on the
conversion, because that fill was not traced** (§7).

**3.6 ★ The save state [Jay, mid-task].** Booting to gameplay costs ~60 s of operator time every
run and has been paid on every dispatch since T-P0-015 — **five times over in this task alone.**
The harness now writes a state at the **first confirmed room change**, which is evidence of
being in the game rather than a timer that could fire on a title screen. ★★ **Not yet verified:
that a restored state reaches a working room change.** Flagged, not assumed.

**3.7 §2 — the governing constraint.** ★★ **Nothing adopted.** ★★★ **And the honest position on
§2's "can we say WHY it works": we can now say why the BLIT is cheap — no per-pixel decisions,
because they were made earlier. We still cannot say what their fill costs or how it works.**

**3.8 §2S.** POP `430a91c`, Karateka `78c8c27`, both `wip`, at those refs. No sibling modified;
POP's `docs/ground-truth/` read.

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] PASS.** `reg_discipline` 0; `hal_sync_check` OK ×3; `src/**` untouched.
- **AC-2 [state-comparable] ★★★ PASS.** Gating mechanism, trigger and threshold in §3.2;
  **PC_AT_RUN = 128 bytes, required to land in `[VOFFSET, VOFFSET+30720)`**; **73,407
  instructions** captured in 10 frames; three captures, all with maxrun 159. ★ **The trace
  covers `$E1B1` and its callers** — the enclosing per-row loop `$E1B4-$E1C0` is in the same
  region, 68 iterations.
- **AC-3 [state-comparable] ★★★ PASS — and it inverts the question.** Table-driven format
  conversion, row-at-a-time, separate source and destination strides. **Not a flood fill, not
  span-emitting, not seed-stack.** §3.3. ★★ **The fill proper was not traced** — see AC-9.
- **AC-4 [state-comparable] ★★★ PASS — THIS IS THE TASK.**
  **24.2 cycles per pixel. ZERO boundary tests per pixel.** Against ours: **86 cycles per test,
  3.09 tests per pixel, 266 cycles of testing alone inside a 506-cycle pixel.**
  ★★ **But read §1's correction 2: this prices their BLIT, not their fill.**
- **AC-5 [state-comparable] ★★ ONE PASS, ONE PLANE — in this loop.** A single `STA ,Y+` per
  source byte, one destination pointer, no second plane written. ★ **Whether a priority plane
  is maintained in the off-screen buffer is undetermined**, and that is where it would be.
- **AC-6 [state-comparable] ★★★ PASS, EXACTLY.**
  ```
  STA ,Y+ at $E1AF executed        10,851
  screen writes counted by the tap 10,851      ★ independent instruments, identical
  inner per outer                   159.6      ★ vs a 160-byte screen row
  static cycles/pixel                24.2      ★ vs 28.4-32.4 measured in T-P0-018
  ```
  ★★ **This is what makes AC-3 and AC-4 trustworthy, and it is what failed on the first
  capture** — that routine wrote 4 bytes then skipped 156, so it could not account for the
  measured runs, and it was discarded rather than reported.
- **AC-7 [state-comparable] ★★ TECHNIQUE NO, TABLE YES.** §3.5.
- **AC-8 [suite] PASS — §6.**
- **AC-9 [suite] PASS — §7.**
- **AC-10 [suite] PASS.** Three candidates; §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim): §0's grep, plus —

```
=== AC-2: the gate, fifth cut ===
[f02832] t=47.259  ★★★ TRACE ON -> .../fill1.tr
           MMU at trace start: 00 3E 3E 09 01 02 03 3F   screen start physical $76000
[f02842] t=47.426  ★★★ TRACE 1 OFF after 10 frames   maxrun in window: 159  screen writes: 10851
           ★★★ THIS WINDOW CONTAINS THE PICTURE FILL (long run + screen writes).
           trace lines: 73407
[f02852]           TRACE 2 OFF   maxrun 159  screen writes 10853   trace lines 73409
[f02862]           TRACE 3 OFF   maxrun 159  screen writes  4915   trace lines 69548
```

```
=== AC-3 / AC-4: the loop, from the traced stream ===
     PC  instruction             executed  cyc  role
  $E1A7  LDB <$A1                      68       row length into B
  $E1A9  LDA ,X+                    10851    6  load one source byte, X++
  $E1AB  ANDA #$0F                  10851    2  keep the low nibble = an AGI colour index
  $E1AD  LDA A,U                    10851    5  ★★★ 16-ENTRY TABLE LOOKUP
  $E1AF  STA ,Y+                    10851    6  ★★★ store to the screen, Y++
  $E1B1  DECB                       10851    2  ★ the PC T-P0-018 identified
  $E1B2  BNE $E1A9                  10851    3  inner loop
  $E1B4  DEC <$A0                      68    6  row counter--
  $E1B6  BEQ $E1D1                     68    3  done?
  $E1B8  LDD <$A2                      68    5  destination stride
  $E1BA  LEAY D,Y                      68    8  ★★ advance destination by a SEPARATE STRIDE
  $E1BC  ABX                           68    3  advance source by B
  $E1BD  CMPX #$6000                   68    4  ★★ SOURCE BOUND -- a pre-rendered buffer
  $E1C0  BCS $E1A7                     68    3  outer loop

★★★ INNER LOOP COST: 24 cycles per pixel byte
★   outer 32 cycles per row / 160 px = 0.20
★★★ TOTAL 24.2 cycles per pixel
★★★ comparison/test instructions between $E1A9 and $E1B2: 0
    ZERO boundary tests. Ours: 3.09 per pixel at 86 cycles = 266.

hot regions:  $E1A7-$E1C0   26 B   65650 instr   89.5% of the stream   stores 10919
```

```
=== AC-6 cross-check ===
STA ,Y+ at $E1AF executed 10851 times
the write harness counted 10,851 screen writes in the same frames
159.6 inner iterations per outer, against a 160-byte screen row
24.2 static cy/px against 28.4-32.4 measured independently in T-P0-018
```

```
=== §3.2: the four failed gates, each caught by its own evidence ===
cut 1  burst 51,409 acc   -> LEAX/BNE disk-wait spin
cut 2  ordering           -> 4-byte strip blitter, maxrun 11, LEAY $009C,Y (+156)
cut 3  disk goes quiet    -> 3 captures in 0.5 s of loading, screen writes 0
cut 4  run >= 128 bytes   -> sector copies are 256 bytes; caught the load again
cut 5  run >= 128 ON SCREEN -> maxrun 159, 10,851 screen writes
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` ships no bundle and this task built nothing.

25.3 operator-runtime-smoke: **N/A — no visual surface this task.**

### 6 — Reactive deviations, route accounting, and AC-8 (what I think it means)

★★★ **AC-8 — MY READING.**

> **There is a technique, we can now say why it works, and it is not the one the thread was
> looking for. Sierra does not have a fast fill. Sierra has a fast PRESENTATION and their fill
> is somewhere we have not looked.**

★★ **What is genuinely adoptable, and I think it is real:** *render into an off-screen buffer in
whatever form is cheapest, then convert to display format in one linear pass with a lookup
table.* **24 cycles per pixel, no branches, no per-pixel decisions.** ★ **We can say WHY: the
conversion loop has no decisions because every decision was made earlier, and the format change
is a table index rather than arithmetic.** That satisfies §2's *"can we say why"* test for the
blit.

★★★ **But the honest headline is a correction, not a discovery.** Two of my previous reports
said things this trace contradicts — there IS a shadow buffer, and the 32 cy/px I attributed to
their fill was their blit. **Six tasks of elimination narrowed the question correctly and then
mislabelled the answer at the last step.**

★ **What I would do next, and it is not more archaeology:** our renderer draws directly into the
display format and pays 266 cycles per pixel in boundary tests. **The measured alternative is to
fill an off-screen 160×168 byte buffer — where a boundary test is a byte compare with no
addressing arithmetic — and convert once at 24 cycles per pixel.** ★★ **That is testable on our
own code against the pinned oracle, needs nothing further from Sierra, and its worst case is a
26 KB buffer we already have room for.**

**Triggers.**
- ★★★ **TRIGGER 1 FIRED — the algorithm is determined and its boundary cost is zero against our
  3.09 per pixel.** Reported immediately; the task stops here.
- **Trigger 2 did not fire** — not comparable. **Trigger 3 did not fire** — no §4 stop reached.
- ★★★ **TRIGGER 4 FIRED ONCE AND WAS OBEYED:** the first capture's routine could not account for
  the measured writes (4 bytes then +156, runs of 4 against the measured 160). **It was
  discarded, not reported**, and that is why the gate was re-cut four times.
- **Trigger 5 did not fire** — the trace gated to ~73,000 instructions, 1.2 MB.

**ROUTE ACCOUNTING.** ★★ **What I did NOT do:** trace the off-screen fill itself — it runs
earlier and needs a different trigger (writes below `$6000`, not to the display). ★ **What I did
that was not asked:** the auto save-state (§3.6), at Jay's request mid-task. ★★ **What cost the
most:** five gate cuts, four of them wrong, each costing an operator run — **§8.2 is the fix and
it is now built.**

### 7 — Uncertainty flags (AC-9 — what I did NOT trace)
- ★★★ **SIERRA'S ACTUAL FILL WAS NOT TRACED.** It runs before this loop, writing into the buffer
  below `$6000`. **Its algorithm, its cost per pixel and its boundary test are all unmeasured**,
  and the thread's headline number does not describe it.
- ★★★ **T-P0-017's "no shadow buffer" and T-P0-018's "their fill is 32 cy/px" are both
  corrected here.** The Orchestrator should treat those two lines as withdrawn.
- ★★ **The 16-entry table's CONTENTS were not read** — inferred as colour→doubled-nibble from
  the geometry, not observed. `LDA A,U` with `U` unknown.
- ★★ **The destination stride `<$A2` and row count `<$A0` were not read**, so the picture's
  placement on screen is not established.
- ★ **One capture window analysed in depth** (fill1); fill2 and fill3 agree on the headline
  numbers but were not read instruction by instruction. **L-33: three of anything is thin.**
- ★ **`LDA A,U` taken at 5 cycles** — §3.4's soft edge.
- ★ **The save state is unverified** (§3.6). **One game, KQ3 Floppy 360K** [L-24]; **I-19**.

### 8 — Follow-up candidates
1. ★★★ **TRACE THE OFF-SCREEN FILL.** Same harness, trigger inverted: a long run landing
   **below `$6000`** instead of on the display. **That is the number this thread has actually
   been chasing, and it is one run away.**
2. ★★★ **PROTOTYPE THE OFF-SCREEN + CONVERT SPLIT ON OUR RENDERER**, against the pinned oracle
   on PC resources. **The 266-cycle boundary test is ours and the 24-cycle conversion is
   measured.**
3. ★★ **Verify the save state restores to a working room change** (§3.6) — it removes ~60 s
   from every future operator run and five runs were spent this task.
4. ★ **Read the 16-entry table and the stride variables** to settle §7's two unknowns.

### 9 — User interaction during task
1. ★★★ **The method itself** [Jay]: *MAME's tracer disassembles live, through the memory map as
   it actually is.* **That removed P3.9's failure cause rather than mitigating it, and it is why
   this task has an answer.**
2. ★★ *"take mame state capture right now so we can just jump back in the game for testing"* —
   §3.6. **Prompted by five boot cycles in one task; now automatic.**
3. Four operator runs driven by Jay, which are the entire evidence base.

### 10 — Candidate(s) captured this task
Three, to `seeds/AGI/live/` (§2C — new rows):
1. ★★★ **`gate-on-the-thing-itself-not-a-proxy-for-it`** — five cuts of one trigger; the first
   four keyed on the disk, on ordering, on timing and on run length, and each caught something
   else. **The target had a direct signature the whole time — a full-row run landing on the
   display — and the harness was already computing it.**
2. ★★★ **`a-negative-inherits-the-premise-you-attached-to-it`** — "runs never cross a row
   boundary, therefore no blit" was sound reasoning over a false premise: it assumed source and
   destination share a stride, and the code advances the destination separately. **The
   measurement stood; the conclusion drawn from it did not.**
3. ★★ **`name-what-you-measured-not-what-you-were-looking-for`** — a cost was measured, labelled
   "their fill", and carried as the thread's headline for a task. **It was their blit. The
   number was right and the noun was wrong**, and no downstream check would have caught it
   because everything referred to it by the label.

### 11 — Commit
<COMMIT>
