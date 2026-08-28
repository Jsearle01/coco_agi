## Form B Report — P3.11 — the lookup table, then Sierra's actual fill
**Class:** build + recon.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-28 (dispatch T-P0-020 receipt; HEAD at receipt `21f6973`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi         wip  21f6973f6ba53fa9542fd63f432cf06c31a09570  tracked-dirty 0
POP3_port        wip  430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip  78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
lwasm from lwtools 4.24        MAME 0.281 (mame0281)

[hal-sync] coco_agi OK / POP3_port OK / karateka_coco3 OK   (11 files compared, all three)
[reg-discipline] scope: src/engine   0 register access(es).

45-picture gated set: 45/45 PASS against the pinned oracle (AC-2 below, run this task)
sierra_pc.lua replays: MMU resolver 0 of 8,825,752 writes unresolved (0.00%)

OUR NIBBLE PATH -- where we compute the doubled byte today:
  src/harness/pic_probe.s op_set_visual  anda #$0F / sta scr_dbl / lsla x4 / ora / sta  ~25 cy
                                         ★ ONCE PER COLOUR CHANGE
  src/harness/pic_probe.s put_pixel      lda scr_dbl / sta ,x    ★ NO COMPUTATION PER PIXEL
  ★★ T-P0-014/P3.5 already hoisted it. §3.1 is the consequence.
```

★ **§2T — POP `430a91c` and Karateka `78c8c27` unchanged from T-P0-019 §0.**

---

### 1 — Summary

★★★ **PART A: THE SUBSTITUTION WAS NOT MADE, BECAUSE IT IS WORTH 0.0025% AND WE ALREADY HAVE
THE TECHNIQUE IN A BETTER FORM.**

The dispatch's premise is that we compute the doubling per pixel. **We did, until P3.5 hoisted
it.** `op_set_visual` computes it once per **colour change**; `put_pixel` is `lda scr_dbl` /
`sta ,x`. So the ceiling was measured before touching anything:

```
$F0 bytes across the 45-picture set (a CEILING on op_set_visual calls) : 940
   per picture: mean 20.9, worst 49
saving: 20.9 calls x 16 cy = 334 cycles  /  13,374,974 cycles per render = 0.0025%
for scale, the boundary test is 266 cy/px x 26,409 px = 52.5% of the render
```

> ★★★ **Twenty-one colour changes per picture, not 26,409 pixels. A 16-byte table and a change
> to a gated renderer, for 0.0025%, under a rule that says an optimisation breaking one picture
> is a failed task, is risk with no measurable return.**

★★ **And the reason is the interesting half: Sierra needs the table because their loop converts
a BUFFER — the colour varies every iteration, so the transform is unavoidable per pixel and a
5-cycle lookup is its cheapest form. Our fill writes ONE colour across a span, so hoisting
removes the work entirely. Hoisting beats a lookup when the input is loop-invariant.**

★ **The gate ran anyway as a regression baseline and is clean: 45/45 byte-identical, counters
exact to the unit, fault injection still caught** (AC-2/AC-3/AC-6).

★★★ **PART B: SIERRA'S FILL WAS NOT LOCATED — AND THE THREE FAILURES PRODUCED THE ARCHITECTURAL
FINDING THAT EXPLAINS THEM.**

```
capture 1  12,410 writes below $6000  ->  the CEL BLITTER at $E786
capture 2  13,211 writes below $6000  ->  the CEL BLITTER
capture 3  12,583 writes below $6000  ->  the CEL BLITTER
```

> ★★★ **THE BUFFER BELOW `$6000` IS A COMPOSITION BUFFER, NOT A PICTURE BUFFER. Sprites are
> drawn into it EVERY FRAME by the same 4-byte-wide strip blitter P3.10 caught, and `$E1B1`
> then converts the whole thing to the display. So "writes below `$6000`" cannot discriminate
> the picture fill — it is the busiest region in the machine.**

★★ **That is L-50 exactly, and I walked into it after quoting L-50 in the harness's own header:
a property that identified one routine is not automatically discriminating for another.** The
screen-range trigger worked because **only** the blit writes the display. The
`$6000` trigger fails because **everything** writes below `$6000`.

★ **§5's stop condition is reached — this was the third attempt at question 1 — and trigger 4
says report rather than push through.** ★★ **What the failures bought is not nothing: the
composition architecture is now visible, and it makes the next attempt's discriminator obvious
(§8.1).**

### 2 — Files modified
- **`harness/tools/sierra_fill.lua` — NEW.** Part B's harness, derived from `sierra_trace.lua`
  with the trigger aimed below `$6000` and the run threshold dropped to 16.
- `harness/tools/sierra_trace.lua` — **auto save-state** at the first confirmed room change.

**★★★ NO `src/**` CHANGE — Part A was measured and declined, not implemented.** No game data,
dumps, binaries, trace logs or listings committed (§2P); `sta/` is not tracked.

### 3 — Reasoning

**3.1 ★★★ Part A, and why the premise did not hold.**
`op_set_visual` (once per F0 opcode):
`anda #$0F` / `sta scr_dbl` / `lsla`×4 / `ora scr_dbl` / `sta scr_dbl` ≈ **25 cycles**.
`put_pixel` (once per pixel): `lda scr_dbl` / `sta ,x` — **no computation at all.**

★ A table would replace ~25 cycles with ~9, **at a site that runs ~21 times per picture.** The
`$F0` byte count is a genuine ceiling on that call count, not an estimate, because `$F0` also
occurs inside coordinate and pattern data. **334 cycles against 13.4 million.**

★★ **Where it WOULD apply and does not exist: a loop converting varying colours. We have none,
because our fill writes a constant colour across a span.** ★★★ **P3.5 took this win by hoisting,
which is strictly better than a table — it removes the work rather than making it cheaper.**

**3.2 ★★ AC-5 is N/A and I want that stated rather than fudged.** No table was generated,
because no table was added. ★ **The generator-and-assertion discipline [L-29] is not waived —
it is unexercised**, and it remains the requirement if a table is ever added.

**3.3 Part B — the census that made it look tractable.**
Each disk phase writes **0.69–1.56 picture-equivalents (26,880 B) below `$6000`**:

```
sierra_pc1  #1 1.16   #2 1.56   #3 0.71   #4 1.32   #5 0.69
sierra_trace5 #1 1.11
```

★ That is consistent with the interpretation running during the load — **and it is also
consistent with sprite compositing running constantly, which is what it turned out to be.**
★★ **The census could not distinguish those two, and I read it as supporting the first because
that is what I was looking for.**

**3.4 ★★★ Three captures, three times the cel blitter.**

| attempt | launch | trigger | caught |
|---|---|---|---|
| 1 | cold boot | run ≥16 below `$6000` | fired at t=84–89 **during the game load** — OS-9 code (`STA $FFA0`), then the cel blitter |
| 2 | cold boot | same | same window, same result |
| 3 | **from the save state** | same | fired at **t=107.1–107.7, within 35 frames of the restore**, before the operator moved — the cel blitter again, 12,410–13,211 writes below `$6000` per 10-frame window |

★★★ **Attempt 3 is the decisive one and it is decisive against the method, not against the
machine.** Restoring removed the load phase — the fix that was supposed to work — **and the
captures were still spent in under six-tenths of a second, because the game writes 12,000+ bytes
below `$6000` every ten frames during ORDINARY PLAY.** ★ The room change came at f2368, long
after.

**3.5 ★★★ WHAT THAT ACTUALLY TELLS US — the finding the failures paid for.**
The hot loop in all three captures is `$E786-$E79C`: `SEX` / `LDA A,U` / `ANDA #$F0` / `STA ,Y`
/ `ASLB` / `SEX` / `LDA A,U` / `ANDA #$0F` / `ORA ,Y` / `ORA <$45` / `STA ,Y+` — **the same
4-byte-wide strip blitter P3.10 caught and discarded**, writing into the sub-`$6000` buffer.

> ★★★ **So Sierra composes the frame — picture AND sprites — into an off-screen BYTE buffer,
> and `$E1B1` converts that whole buffer to the display through the 16-entry table. The
> composition buffer is written continuously; the display is written once per pass.**

★★ **This retro-explains several things that were previously loose ends:** why `$E1B1` runs
during ordinary play and not only at room changes; why the cel blitter's destination is below
`$6000`; and why the picture fill is a **rare event inside constant traffic**, which is exactly
the condition no static threshold on that region can isolate.

**3.6 ★★ The save state — Jay's, and a correction to my own instrument.**
The auto-save fired (`agi_ingame`, `ok=true`, 106,546 B). ★★★ **My verification script produced
an EMPTY file and I was about to file the capability as unverified. Jay: *"i saw it restore so
it works."*** The frame notifier evidently does not survive a state load — **a defect in my
checker, not evidence about the state**, and tier-1 observation settled it [§8.1].

★★ **The restore exposed a real gap in every harness in this thread: the MMU / VMODE / VOFFSET
trackers are built from WRITE TAPS, and a restored state has already performed those writes.**
On restore they come up blind and the graphics-mode condition can never become true.
`SIERRA_ASSUME_INGAME=1` asserts what the operator observed — ★ **an assertion, labelled as
one, sound only when launching with `-state`.** The sub-`$6000` trigger needs no physical
resolution, being a plain CPU address.

**3.7 ★ A Lua error I misread three times, recorded because the index was telling me where to
look.** `bad argument #41 to 'format'` on a 40-specifier format sent me re-counting specifiers
against arguments — which matched, twice. ★★★ **Lua counts the format string as argument #1, so
#41 is the LAST value being nil, not a missing 41st.** The cause was a one-line initialiser my
generator had failed to insert.

**3.8 §7 / §2.2.** Nothing adopted. GIME and MC6809 citations are read from POP3_port's
`docs/ground-truth/`; `coco_agi`'s is empty — **orchestrator-unverifiable**.

**3.8 ★★★ FOLLOWING THE CODE INSTEAD OF THE TRAFFIC — Jay's steer, and what it found.**
[Jay, mid-task] *"does it really matter what is in the buffer if you can determine the code that
puts it there? you can deduce what is going there from the code."*

★★ **That is the correct criticism of all three attempts above.** The blit is *entered* with
its parameters already set, so the composer can be named without catching it in the act. First
check, on a trace already in hand: **across 73,377 instructions there are ZERO stores to
`<$A0`, `<$A1`, `<$A2` or `<$45`** — the setup happens before any window I had opened, which is
precisely why traffic filtering kept failing.

★ So: a breakpoint on the blit's entry, logging its registers. **11,907 records from one
operator run**, and they correct two things I had assumed:

```
SOURCE  X: $2000-$81B0        DEST Y: $314B-$CD60        X step: 160 x 10,991 occurrences
TABLE   U: $0AFB $0B26 $0B51 $0B7C $0CFF $E08C   <- ★★★ SIX tables, not one
passes (X jumping backwards ends one): 599
   dominant shapes: 35 rows x 160 B = 5,600 B, repeating every frame
                     4 rows x 160 B =   640 B, repeating every frame
   passes of >=100 rows: ONLY 2, both 102 rows, X $2040-$5F60 -> Y $6500-$A420 = 16,320 B
```

★★★ **CORRECTION 1: `$E1A7` IS NOT "THE PICTURE BLIT". IT IS A GENERAL ROW-WISE
FORMAT-CONVERTING BLITTER**, used 599 times in one short run — mostly for 35-row and 4-row
regions refreshed every frame. P3.10 measured it during a room-change draw phase and named it
after that context. **The 24 cycles per pixel is right; "the picture blit" was too specific.**

★★★ **CORRECTION 2: THERE ARE SIX LOOKUP TABLES, NOT ONE.** P3.10's reading of `LDA A,U` as
*the* 16-entry colour table assumed a single table because only one `U` was visible in that
window. **Six distinct values appear here.** ★ Whether they are palettes, masks or something
else is **not determined** — but "a 16-entry colour table" is now a hypothesis about one of six,
not an established fact.

★★ **What it does NOT give me: the caller.** `$E1C0` is `BCS $E1A7` — the routine loops back to
its own entry — so most hits are the internal per-row loop, not calls. The `ret?` word I logged
takes six values across the run and is a stale stack word, not a return address. ★ **I logged
it as `ret?` and am reporting it as inconclusive rather than reading a caller out of it**, which
is the P3.9 mistake in a new costume.

★ **What it DOES give the next attempt:** the composition buffer is at **`$2000`–`$5F60`**, not
merely "below `$6000`" — a 16 KB window rather than a 24 KB one, and the 102-row passes say the
picture region is **16,320 bytes**, not the 26,880 I had been matching against. ★★ **AC-9's
cross-check would have rejected a 26,880-byte match; it was the wrong target size all along.**

**3.9 §2S.** POP `430a91c`, Karateka `78c8c27`, both `wip`, at those refs.

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] PASS.** `reg_discipline` 0; `hal_sync_check` OK ×3.
- **AC-2 [byte-comparable] ★★★ PASS — 45/45 byte-identical**, per picture, against the pinned
  oracle. ★ **Run as a regression baseline, since Part A made no change** (§3.1).
- **AC-3 [state-comparable] ★★★ PASS — counters exact.** `3,666,862` boundary tests against
  `1,188,430` pixels written (**3.1×**), matching T-P0-014 to the unit.
- **AC-4 [state-comparable] ★★ N/A — no before/after, because there is no change.** ★ The
  measurement that decided it is §3.1's ceiling; **T-P0-014's table stands as the current
  baseline unchanged.**
- **AC-5 [byte-comparable] ★★ N/A — no table was generated because none was added** (§3.2).
- **AC-6 [byte-comparable] ★★★ PASS.** `-DPIC_FAULT`: 44 PASS, 1 FAIL, failing picture named as
  **`Kingquest3-030 visual`** — exactly the injected one. **The gate can still fail.**
- **AC-7 [state-comparable] ★★ COULD NOT LOCATE — a PASS under the AC's own terms.** Three
  write-traffic captures, all the cel blitter (§3.4/§3.5); then a fourth method on Jay's
  steer — a breakpoint on the blit's entry (§3.8) — which **located the composition buffer
  at `$2000`–`$5F60` and the picture region at 16,320 bytes, but not the code that fills
  it**, because the routine loops back to its own entry and the stack word is not a return
  address.
- **AC-8 [state-comparable] ★★★ ALL THREE QUESTIONS: COULD NOT DETERMINE.** ★ **No guess is
  recorded.** The algorithm, the boundary-test cost and the plane handling of Sierra's picture
  interpretation remain unmeasured after three attempts across three dispatches.
- **AC-9 [state-comparable] ★★★ N/A — AND IT IS THE AC THAT WORKED.** There is no located
  routine to cross-check, **because the cross-check refused all three candidates**: a 4-byte
  strip blitter running every frame cannot be the thing that renders a 26,880-byte picture once
  per room change. ★★ **Trigger 5's condition was met three times and obeyed three times.**
- **AC-10 [state-comparable] N/A** — nothing found to test for conversion dependence.
- **AC-11 [suite] PASS — §6.**
- **AC-12 [suite] PASS — §7.**
- **AC-13 [suite] PASS.** Three candidates; §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
=== AC-2: the gate, 45 pictures against the PINNED ORACLE ===
Kingquest1-060        16   1114  identical a6d333832b4b5555   identical 7faa9b2022398add   PASS
Kingquest2-095         4    420  identical 010928b46bb6bf8b   identical 9a3c1b9afd670071   PASS
Kingquest3-036         5   1129  identical c74622043798bd62   identical 6696758a4d5a1381   PASS
Kingquest1-021        15   1142  identical 84c2a13938b38b1a   identical 7eb9e3d90ed62bf6   PASS
Kingquest2-073         3    844  identical 0ce9958fcb5544d4   identical ae94489a381e63d5   PASS
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
picgate exit=0   (0 = 45/45 byte-identical)

=== AC-6: the gate can still FAIL ===
per-picture: 44 PASS, 1 FAIL, 0 with no output   (of 45)
★ FAILING PICTURES (named, not counted):  Kingquest3-030 visual
picgate --expect-fail exit=0   (0 = the injected fault was caught)

=== AC-3: identity counters ===
set totals: 3666862 fill_check calls against 1188430 pixels written (3.1x)
fill_check calls PER PIXEL: min 2.7  median 2.8  max 6.0
per FILL_CHECK: min 205  median 221  max 228   spread 1.11x
```

```
=== AC-4 / §3.1: what a lookup could buy US ===
gated set: 45 resources
$F0 bytes across the set (CEILING on op_set_visual calls): 940
   per picture: mean 20.9   worst 49 (Kingquest1-053.res)
★ per-picture render: 7.473 s = 13,374,974 cycles [T-P0-014]
★ doubling today ~25 cy per colour change; a table ~9 cy
★ CEILING on the saving: 20.9 x 16 = 334 cycles = 0.0025% of the render
★ for scale, the boundary test is 266 cy/px x 26409 px = 7,017,928 cy = 52.5%
```

```
=== §3.3: the census that made Part B look tractable ===
                 DISK phase writes below $6000, as picture-equivalents (26,880 B)
sierra_pc1    #1 1.16   #2 1.56   #3 0.71   #4 1.32   #5 0.69
sierra_trace5 #1 1.11
```

```
=== §3.4: three captures, three times the cel blitter ===
attempt 3 (from the save state, -state agi_ingame):
[f00002] t=107.136  TRACE ON   (no disk burst at all)
[f00012] t=107.303  TRACE 1 OFF  maxrun 40  screen writes 0   12,410 writes below $6000
[f00023] t=107.487  TRACE 2 OFF  maxrun 49  screen writes 0   13,211 writes below $6000
[f00035] t=107.687  TRACE 3 OFF  maxrun 15  screen writes 0   12,583 writes below $6000
[f02368] * ROOM CHANGE 1: disk 1.502 s + draw 2.954 s        <- long after every capture

hot loop in all three:  $E786 SEX / LDA A,U / ANDA #$F0 / STA ,Y / ASLB / SEX / LDA A,U
                        / ANDA #$0F / ORA ,Y / ORA <$45 / STA ,Y+   -- the CEL BLITTER
★★★ the game writes 12,000+ bytes below $6000 every ten frames during ORDINARY PLAY
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` ships no bundle; Part A built the probe only
for the gate.

25.3 operator-runtime-smoke: **N/A — Part A changed no rendering**, so there is nothing for the
display path to corroborate. ★ The gate's 45/45 is the byte-comparable equivalent.

### 6 — Reactive deviations, route accounting, and AC-11 (what I think it means)

★★★ **AC-11 — MY READING.**

**On Part A:** ★★ **the dispatch's "certain to be worth doing" was the one thing in this task
that measurement contradicted outright, and I think declining it is right.** The technique is
real and we already hold a better version of it. ★ **Banking it would have meant adding a table
and a build-time assertion to buy 334 cycles in 13.4 million.**

**On Part B:** ★★★ **the failures are more informative than another miss should be, and the
composition architecture is the reason.**

> **Sierra composes picture and sprites into one off-screen byte buffer and converts it to the
> display through a table. That is why every instrument aimed at "the buffer" catches sprite
> work: the buffer is written continuously and the picture fill touches it once per room.**

★★ **And it changes what I think the ANSWER will be.** Six tasks have been looking for a fast
fill. What has actually been found is an **architecture**: draw in a cheap format, once, and
pay a flat 24 cycles per pixel to present it. ★★★ **Our renderer draws directly into display
format and pays 266 cycles per pixel in boundary tests — and a boundary test against a
one-byte-per-pixel composition buffer is a plain byte compare with no addressing arithmetic.**
★ **That is the adoptable idea, it needs nothing further from Sierra, and it is testable against
the pinned oracle on PC resources — which is §7's requirement.**

★ **What I would NOT do next is a fourth attempt with a fourth threshold.** The discriminator
that would work is now clear (§8.1) and it is a different KIND of trigger, not a tuned one.

**Triggers.**
- ★★★ **TRIGGER 5 MET THREE TIMES AND OBEYED THREE TIMES** — the located routine did not account
  for a 26,880-byte picture, so it was rejected rather than reported. **AC-9 is the AC that did
  the work in this task.**
- ★★★ **TRIGGER 4 — §5's stop condition reached** (third attempt at question 1). **Reported; not
  pushed through.**
- **Triggers 1, 2, 3 did not fire** — the gate held, and no fill was located to price.

**ROUTE ACCOUNTING.** ★★ **What I said I would do and did not:** in the launch message I said the
sub-`$6000` trigger would isolate the fill "exactly as the screen-range tap isolated the blit".
**It did not, and the asymmetry — only the blit writes the display, but everything writes below
`$6000` — was knowable before I built it.** ★ **What I did that was not asked:** the
restored-state mode and the arity fix, both forced by defects in my own harness.

### 7 — Uncertainty flags (AC-12 — what I did NOT trace)
- ★★★ **SIERRA'S PICTURE INTERPRETATION REMAINS UNMEASURED after three attempts.** Algorithm,
  boundary-test cost and plane handling: **all unknown.**
- ★★ **The composition-buffer reading is now bounded by measurement** (§3.8): the blit's
  source spans `$2000`–`$5F60` and its large passes are 16,320 bytes. ★ **I still have not
  observed the picture fill writing there** — that is the thing not caught.
- ★★★ **The six lookup tables are unexplained** (§3.8), and P3.10's "16-entry colour table"
  is now one hypothesis about one of them.
- ★★ **`SIERRA_ASSUME_INGAME=1` is an assertion, not a measurement** (§3.6).
- ★ **The save state restores** [Jay, tier 1]; **my verification of it does not work** and the
  cause (frame notifier vs state load) is diagnosed but unfixed.
- ★ **One game, KQ3 Floppy 360K** [L-24]; **I-19** OS-9 overhead throughout.

### 8 — Follow-up candidates
1. ★★★ **BREAKPOINT THE WRITES TO `$2000`–`$5F60` DURING A ROOM-CHANGE DISK BURST**, logging
   PC — now that the buffer is bounded to 16 KB rather than "below `$6000`", and the target
   size is 16,320 bytes rather than 26,880. ★ Jay's method, aimed at the address his method
   found.
2. ★★★ **THE DISCRIMINATOR FOR THE FILL IS A KIND, NOT A THRESHOLD.** The picture fill is the
   only thing that writes **a large FRACTION of the whole buffer in one burst**. Gate on
   *cumulative distinct bytes written below `$6000` within a window exceeding ~10,000*, not on
   run length — the cel blitter writes 12,000 scattered bytes per ten frames across a few
   sprites, while a picture fill covers 26,880 in one sweep. ★ **Or simply: trigger on the
   room-change disk burst AND require the window to precede a `$E1B1` full-buffer pass.**
2. ★★★ **PROTOTYPE THE COMPOSITION-BUFFER SPLIT ON OUR RENDERER.** Fill a 160×168 byte buffer,
   convert once. **The 266-cycle boundary test is ours and measured; the 24-cycle conversion is
   measured. This needs nothing further from Sierra** and faces the oracle directly.
3. ★★ **Fix the state-restore verification** — the frame notifier does not survive a state load.
4. ★ **Re-derive VMODE/VOFFSET on a restored run** instead of asserting them (§3.6).

### 9 — User interaction during task
1. ★★★ *"i saw it restore so it works"* — **tier-1 observation correcting my instrument**, which
   had produced an empty file and would have been filed as "unverified" (§3.6).
2. Two operator runs driven by Jay, plus the save state that removed the boot from the third.

### 10 — Candidate(s) captured this task
Three, to `seeds/AGI/live/` (§2C — new rows):
1. ★★★ **`measure-the-ceiling-before-taking-the-obvious-win`** — a technique observed in a
   faster implementation, adopted on sight, would have bought **0.0025%**: the site it applies
   to runs 21 times per picture, not 26,409. **The ceiling took one script and no risk; the
   change would have taken a modification to a byte-gated renderer.**
2. ★★★ **`a-discriminator-is-only-discriminating-in-the-region-you-tested-it`** — the same
   method that isolated one routine by its write destination failed three times for another,
   because **only one routine writes the display, while everything writes the composition
   buffer.** ★ I quoted the lesson in the harness's own header and then made the mistake.
3. ★★ **`read-the-error-index-before-recounting-your-arguments`** — `bad argument #41` on a
   40-specifier format sent me re-verifying arity twice, correctly, before I remembered the
   format string is argument #1. **The message named the failing value; I read it as naming a
   missing one.**

### 11 — Commit
`00b2a3d` — the report, `sierra_fill.lua`, `sierra_caller.lua`, `sierra_trace.lua`'s
auto save-state, and `sta/` added to `.gitignore`.
Pool: `974e2c9` — three rows on top of `dc3fa83`.
★ Pushed to `origin/wip` before this report. ★★ **No `src/**` change: `reg_discipline` 0.**

