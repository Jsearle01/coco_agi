## Form B Report — P3.9 — Sierra's fill: the bounded disassembly
**Class:** recon.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-28 (dispatch T-P0-018 receipt; HEAD at receipt `590a704`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi         wip  590a7047155f227859d6aad2fa6ca8f2bb0ce8af  tracked-dirty 0
POP3_port        wip  430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip  78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
                      (harness/smoke/last-run.log -- pre-existing since T-P0-011)
lwasm from lwtools 4.24        MAME 0.281 (mame0281)

[hal-sync] coco_agi       OK -- aligned with POP3_port, karateka_coco3 (11 files compared)
[hal-sync] POP3_port      OK -- aligned with karateka_coco3, coco_agi (11 files compared)
[hal-sync] karateka_coco3 OK -- aligned with POP3_port, coco_agi (11 files compared)

[reg-discipline] scope: src/engine  0 register access(es).

$ python harness/tools/sierra_order.py build/sierra_shadow1/frames.csv
transitions: 6
★★★ LONGEST SEQUENTIAL RUN IN ANY TRANSITION'S DRAW PHASE: 277 bytes
    ★★★ NO COPY SIGNATURE. The repaint is NOT a linear blit.
   exactly 160 bytes = 1 row                      152 frames
  ★ T-P0-017's harness replays, including the 152-frame row signature.

6809 DISASSEMBLER (M-16 -- vendored, not just PATH):
  PATH:      lwasm / lwlink / lwar / lwobjdump  (assembler + linker; NO disassembler)
  VENDORED:  C:\Projects\ghidra\ghidra_11.4.2_PUBLIC
             support/analyzeHeadless  present
             Ghidra/Processors/MC6800/data/languages/6809.slaspec  present
             6800.ldefs declares id="6809:BE:16:default"
  ★★ TRIGGER 5 DOES NOT FIRE -- a 6809 disassembler is available and nothing was installed.
```

★ **§2T — POP `430a91c` and Karateka `78c8c27` unchanged from T-P0-017 §0.** No `src/**` file
touched; `reg_discipline` stays structurally at 0.

---

### 1 — Summary

★★★ **AC-4 IS ANSWERED. CONSULTATION TRIGGER 1 HAS FIRED.**

> | | cycles per screen pixel written |
> |---|---|
> | **Sierra** | **28.4 / 32.0 / 32.4 / 67.5 / 123.3** — median **32.4**, and this is a **CEILING** |
> | **Ours** | **506** (7.473 s ÷ 26,409 px, no disk at all) |
> | ★★★ **our boundary test ALONE** | **3.09 × 86 = 266** — ★★★ **8.2× Sierra's entire per-pixel budget** |

★★★ **AND THE SHARPEST FRAMING, because it removes the obvious alternative explanation:**

```
OURS   : 1,188,430 put_pixel writes / 45 pictures = 26,410 px = 0.98 screenfuls
THEIRS : 25,848 / 26,130 / 26,330 on-screen writes         = 0.97 screenfuls
```

> ★★★ **BOTH RENDERERS WRITE EACH SCREEN PIXEL ABOUT ONCE. THE GAP IS NOT OVERDRAW.**
> **It is entirely the cost of the work done per pixel — and our boundary test on its own
> costs eight times everything Sierra spends.**

★★ **The measurement is a ceiling on their fill, not a measurement of it**: the draw phase
contains everything between the last disk access and the screen settling — LOGIC, view setup,
whatever else. **Their fill is cheaper than 32 cycles per pixel, not more.**

★★ **AC-2 — the fill is LOCATED**: a single PC, **`$E1B1`**, sampled **165–184 times per
transition**, with three independent numbers agreeing (§3.3). ★★★ **AC-3 — the algorithm's
INSTRUCTION-LEVEL shape is "could not determine", and §3.5 explains why the attempt failed and
why I did not report the disassembly I had.** ★ Its **observable** shape is established with
high confidence: **~168 full 160-byte rows, each screen pixel written once.**

### 2 — Files modified
- **`harness/tools/sierra_pc.lua` — NEW.** Resolves every write to a **physical** address
  through the tracked MMU, and samples PC inside long sequential runs. ★ **No input path.**
- **`harness/tools/sierra_cost.py` — NEW.** AC-4's derivation, with the draw-phase bound swept.

**No `src/**` change.** ★★ **Sierra's binary, 520 memory dumps and every listing stay in the
SCRATCHPAD** (§2P). **The report describes the algorithm; it carries none of their code.**

### 3 — Reasoning

**3.1 ★★★ The instrument T-P0-017 was missing: physical addresses.**
T-P0-017 counted writes by **CPU** address and so could not say which landed on the screen —
which is why its shadow-buffer search covered only ~11% of RAM. The MMU registers are
write-only, but **every write to them is visible to a tap**, so the mapping can be tracked and
each write resolved:

```
physical = block[slot] * 8192 + (cpu_addr & 0x1FFF),   slot = cpu_addr >> 13
$FF91 bit 0 (TR) selects which half of $FFA0-$FFAF is live -- both sets tracked, TR chooses
   [ref: GIME-RM §2 register map; SockmasterGime.md INIT1 bit 0 TR]
```

★★★ **Result: `0 of 8,825,752 writes unresolved after graphics mode — 0.00%.`** ★ **The
coverage problem that limited T-P0-017's AC-2 is gone.** The screen start was read live from
VOFFSET rather than assumed: **physical `$76000`**, 30,720 bytes
`[ref: GIME-RM §6 VRES — $1E → HRES=111 = 160 B/row, LPF=00 = 192 lines]`.

**3.2 ★★ How the fill was located — the dispatch's own hint, and it worked.**
PC sampling on every write would be ruinous, so PC is sampled **only when a sequential run
reaches 64 bytes** (`PC_AT_RUN`, stated per L-44) — i.e. only inside the inner loop of whatever
emits the long runs. T-P0-017 established those runs are exactly one picture row.

```
ROOM CHANGE 1   PC $E1B1  x173
ROOM CHANGE 2   PC $E1B1  x168
ROOM CHANGE 3   PC $E1B1  x169
ROOM CHANGE 4   PC $E1B1  x165
ROOM CHANGE 5   PC $E1B1  x184        PC $E877  x7
```

★★ **One address, five transitions, no competition.**

**3.3 ★★★ L-47 — is this THE fill? Three independent numbers say yes.**

```
an AGI picture               168 rows x 160 bytes           = 26,880 bytes
PC $E1B1 samples             165, 168, 169, 173, 184        ~ one per ROW
on-screen writes measured    25,848 / 26,130 / 26,330       = 0.96-0.98 screenfuls
   170 runs x 160 bytes = 27,200  vs  a full picture of 26,880
```

★★★ **The long runs account for essentially all of the on-screen writes, and their count is the
row count.** ★ **That is the confirmation L-47 asks for, and it is three measurements that did
not have to agree.**

**3.4 ★★★ AC-4's derivation, and what it is a bound on.**

```
 #  draw_s  ALL writes  ON SCREEN  screenfuls     cycles   cyc/px  PC hits
 1   1.535      148764      40738        1.52    2747857     67.5      173
 2   0.467       37907      26130        0.97     836304     32.0      168
 3   0.417       32675      26330        0.98     746700     28.4      169
 4   0.467       37724      25848        0.96     836304     32.4      165
 5   2.854      280240      41408        1.54    5107429    123.3      184
```

★ Transitions 1 and 5 have long draw phases and >1.5 screenfuls — **the settle detector kept
running through subsequent animation**, which inflates both their time and their write count.
**2, 3 and 4 are the clean ones and they agree closely: 28.4–32.4 cycles per pixel at
0.96–0.98 screenfuls.**

★★ **L-46 — swept, because the draw-phase boundary is a free parameter and the last three tasks
were bitten by exactly that:**

```
  pad_s   n   median cyc/px   ratio vs ours
   0.00   5            32.4           15.7x
   0.25   5            45.4           11.1x
   0.50   5            57.4            8.8x
   1.00   5            79.5            6.4x
```

★★★ **The ratio moves from 15.7× to 6.4× depending on how generously the draw phase is bounded,
and EVERY setting leaves their per-pixel cost below our boundary test alone.** **That is the
robust part and it is what the conclusion rests on.**

**3.5 ★★★ AC-3 — WHY I AM NOT REPORTING A DISASSEMBLY I HAD IN FRONT OF ME.**
Having located `$E1B1`, I pulled the bytes around it from T-P0-017's memory dumps and
disassembled them by hand. **The result was a loop of `lda`/`cmpa`/`abx`/`dec`/`bne` with NO
STORE INSTRUCTION IN IT.** Code that writes nothing cannot be the code emitting 26,000 writes.

★★ **The cause: those dumps are from a DIFFERENT SESSION.** `$E1B1` is in CPU slot 7, and slot 7
maps whatever block the MMU held **in that session, in whatever OS-9 task was current**. The
bytes I disassembled are simply different memory that happened to be at the same CPU address.
**Confirmed: 0 of 120 sixty-four-byte windows in `$E000-$FDFF` of those dumps appear anywhere in
the extracted `mnln` module.**

★★★ **The PC is not wrong; my source for the code at that PC was.** Reporting an algorithm from
it would have been the seventh over-read on this thread, and it would have been a confident,
detailed, entirely fictional one. **What is needed is a dump taken in the SAME run, at the
moment the fill is executing, with the MMU state recorded alongside** — §8.1.

★ **So AC-3's instruction-level answer is "could not determine", per L-26.** Its **observable**
shape is not in doubt (§3.3): **full 160-byte rows, ~168 of them, each screen pixel written
once, with per-row setup between them** — which is what T-P0-017's row-boundary result already
showed and what this task's row-count correspondence confirms.

**3.6 ★★ AC-6 — does anything here depend on converted resources?**
★ **The measured quantity is a property of their RENDERER, not of their data**: cycles per
screen pixel, and pixels written per picture. **A repacked resource changes what is drawn, not
the cost of drawing a pixel.** ★★ **But the honest qualification (L-24): the timing ran on
`KQ3/Floppy 360K`, which IS a repack** — it is the only single-drive-bootable KQ3 build
[T-P0-015 §3.1]. **`KQ3/Original` was used only for the static extraction** (§3.5's `mnln`).
★★★ **What would settle it is re-measuring cycles/pixel on `Original` under two drives. Until
then AC-6 is "no dependency identified", not "no dependency".**

**3.7 §2 — the governing constraint.** ★★ **Nothing here is adopted and nothing here is a
specification.** The finding is a **cost**, not a mechanism, and §2's test — *does it hold on the
full PC corpus, gated against the pinned oracle, and can we say WHY* — **is not yet answerable
because AC-3 is undetermined.** ★ **We know their fill is ~16× cheaper per pixel. We do not yet
know how, and "how" is exactly what the generalisation clause requires before anything moves.**

**3.8 §2.2 disclosure.** `coco_agi`'s `docs/ground-truth/` is EMPTY; the GIME manual and
`SockmasterGime.md` were read from POP3_port's copy (read-only sibling use, §2G).
**Executor-verifiable, orchestrator-unverifiable.**

**3.9 §2S.** POP `430a91c`, Karateka `78c8c27`, both `wip`, measured this task at those refs.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] PASS.** `reg_discipline` 0; `hal_sync_check` OK ×3; `src/**`
  untouched; §2T baselines cited.
- **AC-2 [class: state-comparable] ★★★ PASS — LOCATED.** **PC `$E1B1`**, 165–184 samples per
  transition across 5 transitions, no competing address. Evidence in §3.3: **the sample count
  matches the picture's row count and the runs account for all on-screen writes.**
  ★★ **Caveat: `$E1B1` is a CPU address in a paged machine. The physical address, and therefore
  which module owns it, is NOT established** (§3.5).
- **AC-3 [class: state-comparable] ★★ PARTIAL — observable shape yes, instruction-level NO.**
  **Confidence graded per L-26:** *high* — emits full 160-byte rows, ~168 per picture, one write
  per screen pixel, with a break at every row boundary. *Could not determine* — span-emitting vs
  seed-stack vs scanline at the instruction level. ★★★ **No guess is recorded, and §3.5 says
  plainly why the disassembly I produced was discarded.**
- **AC-4 [class: state-comparable] ★★★ PASS — THIS IS THE TASK.** **28.4–32.4 cycles per screen
  pixel** on the three clean transitions (ceiling), against **ours at 506**, and **our boundary
  test alone at 266 = 8.2× their entire budget.** Swept across the draw-phase bound (§3.4).
  ★ **A static per-instruction cycle count was not derivable** — that needs AC-3 — **so what is
  given is the aggregate, its bound direction, and its sweep**, as the AC permits.
- **AC-5 [class: state-comparable] COULD NOT DETERMINE.** One pass or two over the planes needs
  the instruction-level read. ★ **One relevant measurement: on-screen writes are 0.96–0.98 of a
  single screenful, so if a priority plane is maintained it is NOT in the displayed 30,720
  bytes** — but where it is, and whether it is written in the same pass, is undetermined.
- **AC-6 [class: state-comparable] ★★ NO DEPENDENCY IDENTIFIED — and that is weaker than "no
  dependency".** §3.6.
- **AC-7 [class: suite] PASS — §6.**
- **AC-8 [class: suite] PASS — §7 and §3.5.**
- **AC-9 [class: suite] PASS.** Three candidates; §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim): §0's grep above, plus —

```
$ python harness/tools/sierra_cost.py build/sierra_pc1/frames.csv --sweep
build/sierra_pc1/frames.csv: 9832 frames, 0.02..164.08 s
transitions: 5

★ MMU resolver: 0 of 8825752 writes unresolved after graphics mode (0.00%)

 #  draw_s  frames  ALL writes  ON SCREEN  screenfuls     cycles   cyc/px  PC hits
 1   1.535      92      148764      40738        1.52    2747857     67.5      173
 2   0.467      28       37907      26130        0.97     836304     32.0      168
 3   0.417      25       32675      26330        0.98     746700     28.4      169
 4   0.467      28       37724      25848        0.96     836304     32.4      165
 5   2.854     171      280240      41408        1.54    5107429    123.3      184

★★★ CYCLES PER SCREEN PIXEL WRITTEN
    SIERRA  min 28.4  median 32.4  max 123.3   <- a CEILING
    OURS    506.5   (7.473 s / 26409 px, no disk at all)
    ★ ratio 15.7x   -- and the true ratio is LARGER, because theirs is a ceiling
    ★ our boundary test alone: 3.09 tests/px x 86 cy = 266 cy/px  -- MORE than Sierra's
      ENTIRE per-pixel budget

★ L-46 -- is the ratio robust to how the draw phase is bounded?
  pad_s   n   median cyc/px   ratio vs ours
   0.00   5            32.4           15.7x
   0.25   5            45.4           11.1x
   0.50   5            57.4            8.8x
   1.00   5            79.5            6.4x
```

```
=== AC-2: the fill located, from the live PC histogram ===
[f04654] * ROOM CHANGE 1: disk 3.121 s + draw 1.519 s  lat=66/160     PC $E1B1  x173
[f05835] * ROOM CHANGE 2: disk 1.969 s + draw 0.451 s  lat=47/160     PC $E1B1  x168
[f06393] * ROOM CHANGE 3: disk 1.519 s + draw 0.400 s  lat=47/160     PC $E1B1  x169
[f07199] * ROOM CHANGE 4: disk 2.954 s + draw 0.451 s  lat=49/160     PC $E1B1  x165
[f09789] * ROOM CHANGE 5: disk 1.502 s + draw 2.837 s  lat=67/160     PC $E1B1  x184
                                                                      PC $E877  x7
```

```
=== §3.3: three independent numbers that did not have to agree ===
AGI picture geometry       168 rows x 160 bytes = 26,880 bytes
PC $E1B1 samples           165, 168, 169, 173, 184        ~ one per row
on-screen writes           25,848 / 26,130 / 26,330       = 0.96-0.98 screenfuls
   170 runs x 160 bytes = 27,200  vs  a full picture of 26,880

=== and the framing that removes the obvious alternative ===
OURS   1,188,430 put_pixel writes / 45 pictures = 26,410 px = 0.98 screenfuls
THEIRS 25,848-26,330 on-screen writes                       = 0.97 screenfuls
   ★★★ BOTH write each pixel about ONCE. The gap is not overdraw.
```

```
=== §3.5: why AC-3's disassembly was DISCARDED ===
bytes at $E1B1 taken from T-P0-017's dumps decode to lda/cmpa/abx/dec/bne -- NO STORE.
0 of 120 sixty-four-byte windows in $E000-$FDFF of those dumps appear in mnln.bin.
  -> a different session's MMU mapping; the wrong memory at the right CPU address.
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` ships no bundle and this task built nothing.

25.3 operator-runtime-smoke: **N/A — no visual surface this task.** ★ The measured run was
operator-driven, launch path `live-disk`, off a mounted copy.

### 6 — Reactive deviations, route accounting, and AC-7 (what I think it means)

★★★ **AC-7 — MY READING.**

> **There is something to adopt, we do not yet know what it is, and we now know exactly where
> the gap is not.**

**Six external explanations are dead** across five tasks — blanking, VOFFSET, palette, MMU
remap, shadow buffer, and now **overdraw**. ★★★ **That last one is this task's real
contribution besides the number: both renderers write each screen pixel about once, so nobody
is doing redundant work. The entire 16× is the cost of a single pixel write and the decision
that precedes it.**

★★★ **And our own instrumentation has already named the suspect: 3.09 boundary tests per pixel
at 86 cycles = 266 cycles, which is 8.2× Sierra's whole per-pixel budget of 32.** **Whatever
they do, they cannot be performing three 86-cycle boundary tests per pixel. They cannot afford
one.**

★★ **Would it survive §2's oracle test?** **Unanswerable today, and I want to be exact about
why.** §2 requires that we can say **WHY** a technique works before adopting it — *a mechanism
we understand generalises; a sequence we copied does not.* **AC-3 is undetermined, so there is
no mechanism to understand yet, only a cost to envy.** ★ **What can be said: the cost is a
property of their renderer rather than their data (§3.6), so there is no reason yet to expect
it to be a conversion artifact.**

★ **My recommendation, and it is about our code rather than theirs:** the 266-cycle figure is
measured on our renderer, needs no assumption about Sierra, and is now known to exceed their
entire budget. ★★ **That is actionable before the disassembly, and it is a smaller step than
adopting anything.**

**Triggers.**
- ★★★ **TRIGGER 1 FIRED.** Their whole per-pixel budget is **32 cycles**; our boundary test
  alone is **266**. **Reported immediately; the task stopped here rather than pushing into
  AC-3's re-run.**
- **Trigger 2 did NOT fire** — their cost is not comparable to ours.
- **Trigger 3 did not fire** — no conversion dependency identified (§3.6, qualified).
- **Trigger 4 did not fire** — no §4 stop condition was reached; ★ **but §4's third condition
  was approached**: attributing `$E1B1` to a module starts to require understanding OS-9's
  task mapping, and §8.1's follow-up is scoped to avoid that.
- **Trigger 5 did NOT fire** — Ghidra 11.4.2 with a 6809 SLEIGH module is vendored; **nothing
  was installed.**

**ROUTE ACCOUNTING.** ★ **What I did NOT do:** run Ghidra at all — locating the routine was
achieved, but the bytes at that address could not be trusted (§3.5), and disassembling
`mnln.bin` blind was outside the bound. ★★ **What I proposed and did NOT deliver:** in the
launch message I said the PC histogram would turn the disassembly into "read the hundred bytes
around this address". **It did locate the address; the hundred bytes were not readable from the
data I had, and I am flagging that gap rather than leaving the earlier claim standing.**
★ **What I did that was not asked:** the physical-address resolver, which was T-P0-017's
follow-up #2 and is what made AC-4 derivable at all.

### 7 — Uncertainty flags
- ★★★ **AC-4 is a CEILING on their fill, not a measurement of it** — the draw phase includes
  non-fill work. **Their fill is cheaper than 32 cy/px.**
- ★★★ **The ratio depends on the draw-phase bound: 6.4× to 15.7×** (§3.4). **The robust claim is
  the one that survives all of it — their per-pixel cost is below our boundary test alone.**
- ★★★ **`$E1B1` is a CPU address, not a physical one.** Which module owns it is **not
  established**, and the disassembly attempted from it was discarded (§3.5).
- ★★ **Transitions 1 and 5 are contaminated** by animation continuing past the repaint (1.52 and
  1.54 screenfuls). **The clean figures come from 3 of 5 transitions** — ★ **and L-33 says three
  is thin.**
- ★★ **AC-6 is "no dependency identified", not "no dependency"** — the timing ran on a repack.
- ★ **One operator session, one game, KQ3 Floppy 360K.** **I-19: OS-9 overhead is inside every
  figure**, which makes their number a floor and the gap a lower bound.
- ★ **`docs/ground-truth/` is empty here**; GIME citations come from POP's copy (§2.2).

### 8 — Follow-up candidates
1. ★★★ **A SAME-SESSION DUMP AT THE FILL.** One short operator run that snapshots memory **while
   `$E1B1` is executing**, recording the MMU alongside — then Ghidra on those bytes. **That is
   the whole of AC-3 and AC-5, and §3.5 is the reason it is needed.**
2. ★★★ **ATTACK OUR 266.** 3.09 boundary tests per pixel at 86 cycles, measured on our own code,
   now known to exceed Sierra's entire per-pixel budget. **Needs nothing from Sierra.**
3. ★★ **Re-measure cycles/pixel on `KQ3/Original` under two drives**, to discharge AC-6
   properly.
4. ★ **More transitions** — three clean ones is thin for a headline ratio [L-33].

### 9 — User interaction during task
1. *"run it"* — **Jay drove the measured session**, which is the entire evidence base for AC-2
   and AC-4.

### 10 — Candidate(s) captured this task
Three, to `seeds/AGI/live/` (§2C — new rows; nothing existing read or edited):
1. ★★★ **`an-address-is-not-a-location-in-a-paged-machine`** — a PC captured in one session,
   resolved against memory captured in another, produced a clean disassembly of the wrong code:
   loads and compares with no store, for a routine that writes 26,000 bytes. **The address was
   right and the memory behind it was not.**
2. ★★★ **`rule-out-the-cheap-explanation-before-crediting-the-clever-one`** — the 16× gap could
   have been overdraw, which would have meant a bug in ours rather than a technique in theirs.
   **Measuring writes-per-pixel on both sides — 0.98 and 0.97 — cost one line and eliminated it,
   turning a vague "they are faster" into "the gap is entirely per-pixel cost".**
3. ★★ **`a-ceiling-is-more-useful-than-a-missing-number`** — a static cycle count was not
   derivable, and an aggregate that includes unrelated work still answered the question, because
   **its bound direction was known**: it can only overstate their cost, and it was already 8×
   below ours.

### 11 — Commit
<COMMIT>
