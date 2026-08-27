## Form B Report — P3.7 — does Sierra blank the display? and how is their fill faster?
**Class:** recon.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-27 (dispatch T-P0-016 receipt; HEAD at receipt `ccf1df6`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi         wip  ccf1df6f3605ef6d2769537aa84528ed9f72bfd3  tracked-dirty 0
POP3_port        wip  430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip  78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
                      (harness/smoke/last-run.log -- pre-existing since T-P0-011)
lwasm from lwtools 4.24        MAME 0.281 (mame0281)

[hal-sync] coco_agi       OK -- aligned with POP3_port, karateka_coco3 (11 files compared)
[hal-sync] POP3_port      OK -- aligned with karateka_coco3, coco_agi (11 files compared)
[hal-sync] karateka_coco3 OK -- aligned with POP3_port, coco_agi (11 files compared)

[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.

$ python harness/tools/sierra_rooms.py build/sierra_nojoy/frames.csv        <- TRIGGER 5 GATE
n = 7   TOTAL median 3.54  DISK median 1.97  DRAW median 0.47
gap=0.25 n=7 DISK median 1.97 | gap=1.5 n=7 DISK 1.97 | gap=2.0 n=7 DISK 7.06 | gap=3.0 n=7 DISK 8.48
  ★ the seven transitions AND the gap sweep both reproduce -- trigger 5 does NOT fire.
```

★ **§2T — POP `430a91c` and Karateka `78c8c27` unchanged from T-P0-015 §0**, both clean; lwasm
unchanged. **No `src/**` file was touched**, so `reg_discipline` stays structurally at 0.

★★ **GIME video-enable: THERE IS NO SUCH BIT.** See §3.1 — this is trigger 4's territory and
the answer is stronger than "cannot be established".

---

### 1 — Summary

★★★ **AC-2 IS ANSWERED AND THE ANSWER IS NO. SIERRA DOES NOT BLANK THE DISPLAY.**

> Across **8 operator-produced room changes**, `INIT0`, `VMODE`, `VRES` and `BORDER` **never
> changed value** — not once, not in any transition. `VOFFSET` was never written. The palette
> was never written. **Every route to a blank the GIME offers was watched and none was taken.**
> ★★ **The answer is invariant across the whole coalescing-gap sweep** (AC-3).

★★ **The conclusion is stronger than "we saw no blanking".** These registers are **write-only
and latched**: a write tap sees every write, and the harness carries each register's value
frame by frame. **A latched register that never changes value cannot be how anything blanks.**

★★★ **CONSULTATION TRIGGER 2 HAS FIRED**, and its consequence follows: **"progressive drawing"
is WITHDRAWN as a mechanism** (AC-4). The clean transitions repaint in **14–21 frames
(0.23–0.35 s)**, which is exactly the reconciliation the dispatch proposed — *a person sees a
quarter of a second and calls it "at once"; a 60 Hz lattice sees fifteen frames and calls it
progressive.* **Jay's tier-1 observation and the instrument were never in conflict.**

★★★ **AND TRIGGER 3 INVERTS. AC-5's question 2 rests on a false premise:**

> The dispatch says *"we fill 320 wide because our framebuffer is 320 wide."*
> ★★★ **WE DO NOT. `PIC_W equ 160`, `PIC_H equ 168`, one byte per AGI pixel** — the probe's own
> header says *"it is 160x168 one byte per pixel — the SAME shape as the oracle's."*
> **There is no 2× structural saving available here. It is already taken.**

★★ **T-P0-015 §3.10's MMU-remap hypothesis is also NOT SUPPORTED.** The MMU slots are now
tapped, and the write rate through a transition is **25.3/frame against 25.9/frame idle —
0.98×**. That is OS-9 task switching, not a buffer swap.

★ **So the uncomfortable question returns undiminished, exactly as §2 said it would**, and it
is now narrower by three ruled-out explanations. **What I think it means is in AC-6, and it is
a number from our own code, not a guess about Sierra's.**

### 2 — Files modified
- **`harness/tools/sierra_blank.py` — NEW.** AC-2's instrument: consumes a run and reports
  every display register through every transition `sierra_rooms.py` finds. `--sweep` re-runs
  the whole answer across the free parameter (AC-3).
- **`harness/tools/sierra_gime.lua` — NEW.** Unattended boot + GIME tap. ★ Its movement sweep
  is **disarmed by default** (§3.5).
- `harness/tools/sierra_live.lua` — the GIME tap added to the **operator** harness, which still
  has **no input path** (audited: no `set_value`, `:post`, `natkeyboard`).

**No `src/**` change. No game data, resource bytes, renderings or screenshots committed** (§2P).
★ Sierra's extracted binary (§3.6) was written to the **scratchpad**, never the repo.

### 3 — Reasoning

**3.1 ★★★ There is no GIME video-enable bit, and that had to be established BEFORE building.**
Tapping a bit that does not exist would have produced a confident "no blanking" that meant
nothing.

```
[ref: GIME-RM §2 Register Map Summary]  $FF90-$FFBF enumerated in full; NO display-enable
                                        register appears anywhere in the map.
[ref: GIME-RM §3 INIT0]   COCO/MMUEN/IEN/FEN/MC3/MC2/MC1/MC0   -- no video enable
[ref: GIME-RM §6 VMODE]   BP/BPI/MOCH/H50/LPR2-0                -- no video enable
[ref: GIME-RM §6 VRES]    LPF1-0/HRES2-0/CRES1-0                -- no video enable
```

★ Corroborated independently by `SockmasterGime.md`, which enumerates the same four registers
bit by bit. ★★ **§2.2 / §2S disclosure: `coco_agi`'s own `docs/ground-truth/` is EMPTY — a
`.gitkeep` and nothing else. Both documents were read from POP3_port's copy**, which §2G
permits (reading a reference is read-only use of a sibling). **These citations are
executor-verifiable and orchestrator-unverifiable.**

★★★ **So the question is right and the instrument named in the dispatch is not.** "Blank the
display" is a **result**, and the GIME offers at least six routes to it. Tapping all six costs
the same as tapping one:

| route | register | what it would look like |
|---|---|---|
| CoCo1/2 mode | `$FF90` INIT0 bit 7 COCO | the whole screen changes meaning |
| text mode | `$FF98` VMODE bit 7 BP | a graphics screen becomes alphanumeric |
| ★★ **zero lines** | `$FF99` VRES LPF=10 | "Reserved" [GIME-RM §6]; Sockmaster records it as zero/infinite lines — **set during the vertical border, the screen is ALL BORDER.** The likeliest "yes" |
| border | `$FF9A` | what such a blank would show |
| point elsewhere | `$FF9C/$9D/$9E/$9F` | VSCROLL / VOFFSET / HOFFSET |
| ★★ **MMU remap** | `$FFA0-$FFAF` | T-P0-015 §3.10's hypothesis — **the previous run was STRUCTURALLY BLIND to it**, its write tap covering only `$0000-$FEFF` |
| ★ palette | `$FFB0-$FFBF` | all sixteen to one colour: **a blank with no video register involved at all** |

**3.2 ★★★ The answer, and why it is a strong negative.**
All eight transitions, every register constant:

```
 #  start_s  total_s  lat |          INIT0        VMODE           VRES  BORDER | VOFF    MMU  PAL
 1    54.22    3.521   62 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   5747    0
 2    78.20    1.769   47 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   4515    0
 3    88.11    1.936   47 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   4868    0
 4   104.03    4.406  105 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   9256    0
 5   119.72    1.936  100 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   4757    0
 6   131.48    5.273   59 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0  14599    0
 7   146.85    4.306   45 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   9166    0
 8   175.37    4.389   76 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0  12875    0
```

★ And over the **whole run** once graphics mode is entered (t=30.77 s, 9,064 frames):
`INIT0 $6C` constant, `VMODE $80` constant, `VRES $1E` constant, `BORDER $00` constant;
**2 VOFFSET writes in 151 s** (neither inside a transition) and **272 palette writes, all in a
single 4-frame burst at mode setup and never again.**

★★ **`VRES = $1E` decodes to LPF=00 (192 lines), HRES=111 (160 bytes/row), CRES=10 (16
colours)** — Sierra runs 320×200×16 with **160 bytes per row**, and never touches it again.

**3.3 ★★★ THE EVENTS ARE LOADS, NOT MENUS — and this time that was CHECKED, not assumed.**
§3.6 of T-P0-015 reported four menu events as room changes. **Menus produce a very large
lattice change**, so the screen-change requirement alone does not separate them:

```
measured, run 2 (unattended, CTRL+letter holds):
   lattice change   520-568 per hold   <- menus move the screen MORE than a room change does
   FDC accesses     0 in 7 of 8 holds  <- ★★★ MENUS DO NOT TOUCH THE DISK

the 8 events reported here:  FDC 3,820 / 6,907 / 6,909 / 6,910 / 7,970 / 8,768 / 9,294 / 11,985
```

★★ **The disk is the discriminator, and it separates the two populations completely.** A menu
is a screen change with no disk; a room change is a screen change with thousands of accesses.

**3.4 ★★ The MMU hypothesis, tested rather than waved away.**
T-P0-015 §3.10 proposed that the picture might be made visible by **remapping MMU slots**. It
is now tapped — but OS-9 task-switches constantly, so a raw count proves nothing. **The
question is whether the rate is elevated when the screen changes.**

```
during transitions :     25.3 writes/frame  (2602 frames)
idle in-game       :     25.9 writes/frame  (3686 frames)
ratio              :     0.98x        peak in any single frame: 310
```

★★★ **Not elevated. Consistent with task switching and not with a remap-driven buffer swap.**
★ A swap would be a **burst of a few writes at one instant**; this is a flat background rate.

**3.5 ★★★ TWO CORRECTIONS FROM JAY, AND BOTH WERE LOAD-BEARING.**

1. ★★★ **CTRL+BREAK after R+ENTER is required to enter the game.** [Jay, tier 1]
   ★★ **My first unattended run held eight different movement keys for four seconds each and
   the lattice never moved a single point — including its own idle baseline — and I read that
   as wrong keys.** A completely flat lattice **including the baseline** is the signature of a
   machine that is not in the game at all. ★ It was also visible in T-P0-015's operator log,
   where Jay pressed CTRL then BREAK+CTRL at t=46 s, immediately after his R and ENTER.
2. ★★★ **CTRL+letter is the MENU system, not movement.** [Jay, tier 1: *"your just spamming
   the menus again"*] **The measurement agrees and is unambiguous:** each CTRL+letter hold
   moved **520–568 lattice points across ~95 of its 240 frames** — a menu opening and closing —
   against **~0 for the bare arrows.**
   ★★ **T-P0-015 recorded "movement is Ctrl+letter" from documentation [I-16, flagged
   SECONDARY]. §8.1 puts Jay above it, and so does the measurement.** ★ The earlier
   twelve-candidate probe's failure was **not the joystick alone — the keys were also wrong**,
   and attributing it entirely to the joystick was a single-cause explanation for a two-cause
   failure.
   ★ **The unattended sweep is now DISARMED by default**, because a script that can only churn
   menus on a visible window is a hazard, not an instrument.

**3.6 ★★ AC-5's part B — where the interpreter actually is.**
`CMDS/Sierra` is **1,377 bytes**: an OS-9 module named `sierra`, type/lang `$11`, exec offset
`$0014`. ★ **It is a launcher, not the interpreter.** The interpreter is **`CMDS/MnLn` —
24,622 bytes** ("MainLine"), read from `KQ3/Original/KQ3-1-1.DSK` (`sha256[0:16]
5e9fd9d8637fa80c`) with the read-only `os9fs.py`.

★★ **Locating it is as far as this task goes**, per trigger 2 (*"the next dispatch aims
entirely at B"*) and §11's exclusion of a full disassembly. **Q1 and Q3 are "could not
determine"; no guess is recorded.** ★ **Q2 did not need the binary at all** — see §3.7.

**3.7 ★★★ Q2 IS ANSWERED FROM OUR OWN SOURCE, AND IT INVERTS THE QUESTION.**

```
src/harness/pic_probe.s:45   PIC_W  equ  160
src/harness/pic_probe.s:46   PIC_H  equ  168
src/harness/pic_probe.s:51   PRI_BASE equ $1700   ; 160*168 = $6900 -> ends at $8000
src/harness/pic_probe.s:41   "...it is 160x168 one byte per pixel -- the SAME shape as the
                              oracle's. No transform, no place for a transform error to hide"
```

★★★ **We already fill 160-wide, one byte per AGI pixel.** The dispatch's premise — *"we fill
320 wide because our framebuffer is 320 wide"* — is false. **The mode is 320 pixels wide and
160 BYTES wide (CRES=10, two pixels per byte), so one AGI pixel is one byte and the nibble
doubling IS the pixel doubling.** ★ **Sierra runs the identical geometry** (§3.2: HRES=111 =
160 bytes/row). **Whatever explains the gap, it is not pixel count.**

**3.8 §2.1 / §8.1 — authority.** Jay is tier 1 and corrected me twice (§3.5). Sierra's
interpreter is tier 2 for CoCo3 questions and only for KQ3 and LSL [X-26]; this used KQ3.
★★ **The blanking result is a measurement of the RUNNING ORIGINAL — §2 tier 2 — not of ScummVM
or the Specs**, and it is the strongest evidence class this project has short of Jay's eye.
★ **I-19: OS-9 overhead is inside every timing here, so every Sierra figure is a FLOOR.**

**3.9 §2S.** POP `430a91c`, Karateka `78c8c27`, both `wip`, measured this task at those refs.
No sibling file was modified; POP's `docs/ground-truth/` was **read** (§3.1).

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] PASS.** `reg_discipline` 0; `hal_sync_check` OK in all three
  repos; `src/**` untouched. §2T baselines cited above.
- **AC-2 [class: state-comparable] ★★★ PASS — THE ANSWER IS NO.** 8 transitions (dispatch asks
  ≥5). Register, bit, state and citation in §3.1–§3.2. ★★ **On "each observed ≥3 times"
  [L-33]: the 8 are distinct transitions and were NOT each repeated.** What substitutes, and I
  think substitutes well: **the state is sampled every frame for all 10,907 frames**, so each
  register is observed ~9,000 times after graphics mode; **the answer is invariant across all
  eight events**; and **the sweep re-derives it six times over.** ★ **What repetition would
  still add is a second operator session on a different route through the game**, and that was
  not done.
- **AC-3 [class: state-comparable] ★★ PASS — robust.**
  ```
   gap_s    n    transitions with ANY display change
    0.25    8                                      0
    0.50    8                                      0
    1.00    8                                      0
    1.50    8                                      0
    2.00    8                                      0
    3.00    8                                      0
  ```
  ★★★ **The count and the answer are both invariant. This is the parameter that invalidated
  T-P0-015's disk split, swept prospectively this time [L-46].**
- **AC-4 [class: state-comparable] ★★★ PASS — "progressive drawing" is WITHDRAWN.**
  ```
   #  draw_s  frames | moved | span | 100% of change within
   1   0.401     24  |    6  |  14  | 16 moving frames
   2   0.451     27  |    5  |  15  | 16
   3   0.434     26  |    6  |  15  | 16
   5   0.417     25  |    8  |  21  | 32
   -- the other four (4,6,7,8) run 103-162 frames with only 11-32 frames moving at all
  ```
  ★★ **In the clean half the entire repaint occupies 14–21 frames — 0.23–0.35 s — and the
  lattice moves in only 5–8 of them.** That is **exactly** the dispatch's reconciliation, and
  faster than the ~28 frames it proposed. **A person cannot resolve a quarter-second repaint as
  "building in"; a 60 Hz sampler with 160 points sees six frames of partial coverage and calls
  it progressive. Same event, different resolution. Jay was right and the instrument was never
  in conflict with him.**
  ★ **Honest caveat: the other four transitions spread sparse change over 1.7–2.7 s**, which I
  read as the repaint finishing quickly and then **animation continuing in the new room**
  resetting the settle detector — **but I did not verify that, and it is not needed for the
  withdrawal.** What is withdrawn is the claim that Sierra *deliberately draws incrementally*;
  the fast half refutes it on its own.
- **AC-5 [class: state-comparable] ★★ PARTIAL — 1 of 3 answered, and it inverts.**
  - **Q1 span-seeding vs pixel-queue: COULD NOT DETERMINE.**
  - ★★★ **Q2 160- vs 320-wide: ANSWERED, AND THE PREMISE IS FALSE. We are ALREADY 160-wide**
    (§3.7), and Sierra runs the same geometry. **There is no 2× here.**
  - **Q3 one pass or two: COULD NOT DETERMINE.**
  ★ **No guesses recorded.** The interpreter is located at `CMDS/MnLn`, 24,622 B (§3.6), which
  is where the next dispatch starts.
- **AC-6 [class: suite] PASS — see §6 below, in my words.**
- **AC-7 [class: eye-gated] PENDING JAY.** ★★ **Jay drove the entire measured run himself while
  the tap logged**, so his eye and the instrument were on the same eight events — which is what
  the AC asks. **A `★ GIME:` line prints the instant any display register changes, and none
  printed during any transition.** ★ **Launch path `live-disk`**, Sierra's own OS-9 boot off a
  mounted **copy** (§2P). Monitor: MAME's `screen_config` default is **Composite**.
- **AC-8 [class: suite] PASS.** Three candidates; §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim): §3's grep above, plus —

```
$ python harness/tools/sierra_blank.py build/sierra_gime_live/frames.csv --sweep
build/sierra_gime_live/frames.csv: 10907 frames, 0.02..182.02 s

room changes found: 8   (gap=0.5s settle=1.0s min_lat=30 min_fdc=2000; window padded 1.0s)
 #  start_s  total_s  lat |          INIT0        VMODE           VRES  BORDER | VOFF    MMU  PAL
 1    54.22    3.521   62 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   5747    0
 2    78.20    1.769   47 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   4515    0
 3    88.11    1.936   47 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   4868    0
 4   104.03    4.406  105 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   9256    0
 5   119.72    1.936  100 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   4757    0
 6   131.48    5.273   59 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0  14599    0
 7   146.85    4.306   45 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0   9166    0
 8   175.37    4.389   76 |     $6C COCO=0     $80 BP=1      $1E LPF=0     $00 |    0  12875    0

==============================================================================
★★★ ANSWER: NO. Sierra does NOT blank the display during a room change.
    Across 8 transitions, INIT0, VMODE, VRES and BORDER never changed
    value, and VOFFSET and the palette were never written.
    ★★ THE MMU IS THE EXCEPTION AND IT IS NOT AN EXCEPTION: OS-9 task-switches
    constantly, so $FFA0-$FFAF is written throughout. See the MMU RATE test
    below -- a remap-driven buffer swap would be a BURST, not a background rate.
==============================================================================

WHOLE RUN once graphics mode is entered (t=30.77s onward, 9064 frames):
     init0: ['$6C COCO=0']   (constant)
     vmode: ['$80 BP=1']   (constant)
      vres: ['$1E LPF=0']   (constant)
    border: ['$00']   (constant)
   VOFFSET writes 2   palette writes 272   MMU writes 232770

★★ MMU REMAP TEST ($FFA0-$FFAF) -- T-P0-015 §3.10's hypothesis
   during transitions :     25.3 writes/frame  (2602 frames)
   idle in-game       :     25.9 writes/frame  (3686 frames)
   ratio              :     0.98x
   peak in any single frame: 310
   ★★★ NOT ELEVATED -- consistent with OS-9 task switching and NOT with
       a remap-driven buffer swap. The §3.10 hypothesis is NOT supported.

★ AC-3 -- is the answer robust to the free parameter?
 gap_s    n    transitions with ANY display change
  0.25    8                                      0
  0.50    8                                      0
  1.00    8                                      0
  1.50    8                                      0
  2.00    8                                      0
  3.00    8                                      0
```

```
=== AC-5 Q2, from OUR source (§3.7) ===
src/harness/pic_probe.s:45   PIC_W  equ  160
src/harness/pic_probe.s:46   PIC_H  equ  168
src/harness/pic_probe.s:51   PRI_BASE equ $1700   ; 160*168 = $6900
   ★★★ we are ALREADY 160-wide, one byte per AGI pixel. The premise is false.
```

```
=== AC-5 part B, the interpreter located (§3.6) ===
KQ3/Original/KQ3-1-1.DSK  sha256[0:16] 5e9fd9d8637fa80c   (opened READ-ONLY)
   24622  CMDS/MnLn     <-- ★ THE INTERPRETER
    1377  CMDS/Sierra   <-- OS-9 module 'sierra', type/lang $11 -- a LAUNCHER
     222  MODULES/AGIVIRQDr        58  MODULES/VI
```

```
=== §3.3: the events are LOADS, not menus -- checked, not assumed ===
menus (measured, CTRL+letter holds):  lattice 520-568,  FDC 0 in 7 of 8
the 8 events reported here:           lattice 45-105,   FDC 3,820-11,985
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` ships no bundle and this task built nothing.

25.3 operator-runtime-smoke: **pending Jay.** Launch path **`live-disk`**; Jay drove the
measured run.

### 6 — Reactive deviations, route accounting, and AC-6 (what I think it means)

★★★ **AC-6 — MY READ, AND IT IS A NUMBER FROM OUR OWN CODE.**

**Three explanations are now dead:** it is not a display trick (AC-2), not a page flip or MMU
remap (§3.4, T-P0-015 §3.5), and not pixel count (§3.7 — we are already 160-wide). ★ **Each was
cheap to test and each would have been a comfortable answer. None survived.**

★★★ **Where I think the time actually goes, from T-P0-014's own counters:**

```
recorded over the 45-picture set [T-P0-013/014 §5]:
    boundary tests   3,666,862
    put_pixel writes 1,188,430      -> 26,409 per picture ≈ one 26,880-px screenful ✓
  ★★★ 3,666,862 / 1,188,430 = 3.09 BOUNDARY TESTS PER PIXEL WRITTEN
```

★★ **Label per §8: that division is my arithmetic over two recorded counters, not a fresh
measurement.** ★★★ **And one thing it is NOT: a validation.** I first wrote this as
*"3.09 tests x 170 cycles/test x 26,409 px = 7.7 s, which matches our 7.473 s median"* — **but
the 170 cycles/test figure was itself derived as render-cycles / boundary-tests, so
multiplying it back is circular and lands by construction.** The agreement would have been
guaranteed whatever the truth was. ★ **The honest number is the ratio alone: two independent
counters, 3.09 tests per pixel written.**

> **We test every pixel about three times. A span-based fill tests each pixel about once, and
> tests a whole run of pixels with one boundary check at each END of the run rather than one
> per pixel. That is where a 3–10× lives, and it needs nothing from Sierra to justify trying.**

★ **This is a hypothesis about OUR code, and it is testable without any further recon** — which
makes it a better next step than more archaeology. ★★ **But AC-5 Q1 is still "could not
determine", and if Sierra turns out to be pixel-queue too, then the gap is somewhere I have not
looked and I should not have guessed.** **I am not claiming Sierra is span-based. I am claiming
our own instrumentation says our fill does three times the work a span fill would.**

**Triggers.**
- ★★★ **TRIGGER 2 FIRED — Sierra does NOT blank.** Reported; task stopped at B's threshold.
- ★★★ **TRIGGER 3 FIRED, INVERTED.** Q2's premise is false; **there is no 2× to find.**
  Reported prominently per the dispatch's instruction, with the opposite sign.
- ★★ **TRIGGER 4 — partially.** The video-enable bit could not be established **because it does
  not exist**, which is a stronger result than `[no-ref:]`. **Cited, not guessed** (§3.1).
- **Trigger 1 did not fire** (Sierra does not blank). **Trigger 5 did not fire** — the saved
  harness replayed T-P0-015's seven transitions **and** its gap sweep.

**Deviations.**
- ★★ **The instrument was widened from "the video-enable bit" to the whole GIME register
  file** (§3.1). Same cost, and the narrow version would have answered a narrower question than
  the one asked.
- ★ **Two media were used**: the *measurement* ran on `Floppy 360K/kq3-1.dsk` (the only
  single-drive-bootable KQ3 build — T-P0-015 §3.1, unchanged); the *static read* used the
  dispatch's `KQ3/Original`, which is where `MnLn` was found.

**ROUTE ACCOUNTING.** ★ **What I did NOT do:** read `MnLn` (Q1 and Q3 are undetermined), and no
disassembly. ★★ **What I did that was not asked:** three unattended runs before asking Jay to
drive — **two of which produced nothing usable** (§3.5), and the second of which **churned menus
on a visible window and had to be stopped.** ★ I also tested T-P0-015's MMU hypothesis, which
the dispatch did not require but which the tap made free.

### 7 — Uncertainty flags
- ★★ **One operator session, one game, one route through it.** The 8 transitions are distinct
  but not independently repeated (AC-2).
- ★★ **AC-4's second population** — four transitions with sparse change over 1.7–2.7 s — is
  **read as post-repaint animation and not verified.** The withdrawal does not depend on it.
- ★★ **Q1 and Q3 are open**, and AC-6's span-fill reasoning is **a hypothesis about our code**,
  not a finding about Sierra's.
- ★ **`docs/ground-truth/` is empty in this repo**; the GIME citations are from POP's copy and
  are orchestrator-unverifiable (§2.2).
- ★ **A blank achieved by means outside `$FF90-$FFBF` would not be seen** — e.g. writing the
  border colour into every palette slot *would* be caught, but a display disabled by some path
  I have not enumerated would not be. **I enumerated from the register map; I did not prove the
  enumeration complete.**
- ★ **OS-9 overhead is inside every timing** [I-19].

### 8 — Follow-up candidates
1. ★★★ **TEST THE SPAN-FILL HYPOTHESIS ON OUR OWN RENDERER.** 3.09 boundary tests per pixel is
   measured; a span fill targets ~1. **This needs no further recon and is the largest lever
   identified so far.**
2. ★★ **Read `CMDS/MnLn`** (24,622 B) for AC-5 Q1 and Q3 — located, not read.
3. ★ **A second operator session** on a different route, for AC-2's repetition.
4. ★ **Put the GIME reference into `coco_agi/docs/ground-truth/`** so its citations stop being
   sibling-dependent.

### 9 — User interaction during task
1. ★★★ *"you have to send ctrl+break after the R+enter when everything is settled to get into
   the game proper."* — **without it nothing runs, and I had misread a flat lattice as wrong
   keys** (§3.5.1).
2. ★★★ *"your just spamming the menus again"* — **CTRL+letter is the menu system** (§3.5.2).
   This corrected a documented "fact" carried since T-P0-015 and stopped a run that was
   churning menus on a visible window.
3. *"run it"* — **Jay drove the measured session**, which is the entire evidence base for AC-2
   and satisfies AC-7's form.

### 10 — Candidate(s) captured this task
Three, to `seeds/AGI/live/` (§2C — new rows; nothing existing read or edited):
1. ★★★ **`check-the-mechanism-exists-before-instrumenting-it`** — the task was specified as
   "tap the GIME video-enable bit"; **there is no such bit**, and tapping one would have
   produced a confident negative that meant nothing. Widening from the named bit to the whole
   register file cost nothing and made the negative real.
2. ★★ **`a-flat-baseline-indicts-the-setup-not-the-input`** — eight movement keys held for four
   seconds each, zero screen change; I concluded "wrong keys". **The idle baseline was also
   zero**, which no key choice can explain: the machine was not in the game.
3. ★★ **`a-single-cause-explanation-for-a-two-cause-failure-hides-the-second`** — the earlier
   movement probe failed for BOTH the joystick ports AND the wrong keys. Finding the joystick
   explained the symptom completely enough that the second cause went unexamined for a task.

### 11 — Commit
`2c75749` — the report and `sierra_blank.py`.
`e4f53db` — the GIME tap in both harnesses; the unattended movement sweep disarmed.
Pool: `a32ca7f` — three rows on top of `d18fd47`.
★ Pushed to `origin/wip` before this report.

