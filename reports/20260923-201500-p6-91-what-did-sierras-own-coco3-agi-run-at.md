## Form B Report — T-P0-144 / P6.91 — What did Sierra's own CoCo3 AGI run at?
**Class:** measurement. wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-23 (HEAD `d01f4a7`, wip). git status clean at t0.

### 1 — Summary

**Sierra's own 1988 CoCo3 AGI interpreter, King's Quest III, booted fresh under our MAME
configuration and driven by Jay, does a room change in a median 4.10 s** — **disk 2.80 s + draw
1.58 s**, n=4. ★★★★★ **Ours is 6.16 s and is entirely draw**, because our p3b is RAM-staged and
never touches a floppy. **On the comparable half we are ~3.9× slower.** Walking, their ego produces
**≥5.87 screen-change events/second against our 3.33 cycles/second.**

★★★★★ **But the scenes are not like-for-like, and the difference is measurable rather than
asserted.** With the ego still, their KQ3 rooms produce **0.00–0.40 events/s — nothing animates.**
Our castle room 1 composites **3.11 cels every single cycle standing still** [P6.90]. **Their idle
scene does almost no work; ours does nearly as much idle as moving.**

★★★★★ **Two things that would have excused the gap are refuted, both by evidence rather than by
argument.** **They render at 320×192×16** — `VMODE=$80 BP=1 VRES=$1E`, our mode 1 exactly, settled
at t=33.98 s and never changed again — **so the fidelity is not reduced.** And ★★★★★ **their ego IS
occluded by scenery: Jay saw it pass behind a doorway during a room change in this run.** **Their
blit does a depth test, as ours does.**

> ★★★★ **So the bar is real: a CoCo3 AGI interpreter doing the same class of work at the same
> fidelity with the same depth test is ~1.8× faster walking and ~3.9× faster drawing a room.**
> ★★★ **The one honest discount is workload — their rooms animate less than our castle — and it is
> not quantified on their side because measuring it would need their resources** [§1.1, out of
> scope].

**No `src/` change** (AC-6: `git diff --stat -- src/` empty).

### 2 — Files modified
- `harness/tools/gates.manifest` — the Sierra benchmark recorded as a standing comparison: how to
  reproduce it, the figures, the media hash, the lower-bound caveat, and the cfg hazard (§9 delta 2).

(Explicit-path staging. `coco_agi.code-workspace` is untracked and left alone.)

### 3 — Reasoning

**§3(1) — what the project already knew, and the dispatch was right to ask.** Design §8 puts
Sierra's CoCo3 interpreter at **tier 2, "a runnable comparison target"**, and v0.4 records that the
interpreter itself was acquired and parsed [backlog **I-17**]. ★★★★ **More than that: the harness
already existed.** `sierra_live.ps1` / `sierra_live.lua` (observe-only, operator-driven),
`sierra_boot.lua` (automated boot), and **`sierra_rooms.py`, which the tree names as THE
measurement**, all date from P3.6–P3.9. **This task did not build an instrument; it ran one.**

★★ **§2H check 3 applied and it paid.** Grepping the reports for the subsystem found P3.6's
**"disk 3.121 s + draw 0.384 s"**. ★★★★ **That 0.384 s is scene-specific and the median over four
transitions is 1.58 s — 4.1× larger.** Had it been cited alone it would have set a target 4×
tighter than the truth, which is precisely the failure §7 names twice.

**§3(2)/(3) — what is in hand.** Seven CoCo3 releases: KQ1, KQ2, KQ3, KQ4, KQ6-AGI (fan), LSL1,
PQ1. ★★★★ **Four are titles we also run** — KQ1, KQ2, KQ3, PQ1 — so a shared title exists.
**KQ3 was chosen** because its image is the one P3.6 pinned; the hash matched
(`sha256[0:16]=20EA31A82087DA90`).

**§3(4)/§1.1a — the machine, and the Orchestrator's correction verified rather than accepted.**
`mame coco3 -listxml` returns `<ramoption name="512K" default="yes">524288</ramoption>`. ★★★★★
**Neither invocation passes `-ramsize`, so both sides run 512 KB.** ★★★ **The correction in §1.1a is
right and now it is measured** — and, as §1.1a says, nothing follows either way from "they needed
512 KB too".

**§3(5) — what the host can count.** Frame counts, the 16×10 lattice, FDC access density and a
whole-map write census, all host-side. ★★ **Nothing was read out of their volumes** [§6 trigger 4].

**Authority tier.** §4B and §4D(2) are **measurements of the running original** — tier 2, the
highest evidence this project can obtain. ★★★★ **§4D(1) is Jay — tier 1** — and is recorded as his
observation, not as an inference from a change-rate. Our own figures are **cited, not re-measured**
[§2, §2T]: 0.3063/0.3004 moving and 3.11 decodes/cycle standing from P6.90, 6.16 s from P6.85.

★★★ **Nothing here rests on ScummVM**, so §2.1's original-vs-normalisation question does not arise.

**§2S.** No sibling claim is made.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: measurement]** A Sierra release running under our MAME configuration, every
  difference named — **PASS.**

  ```
  mame coco3 -ext fdc -flop1 <copy of kq3-1.dsk> -window -nomaximize -skip_gameinfo
             -rompath C:/mame/roms -cfg_directory <temp> -snapshot_directory <out>
             -snapview auto -snapsize 640x480 -keepaspect
             -autoboot_script harness\tools\sierra_live.lua -autoboot_delay 0
  ```

  **Differences from our p3b invocation, and what each costs:**

  | difference | why | does it weaken the comparison? |
  |---|---|---|
  | `-ext fdc -flop1 <disk>` | they boot OS-9 off a floppy; our p3b is loaded by its autoboot script | ★★★★ **Yes, and it is quantified rather than waved at**: their 4.10 s total contains 2.80 s of disk we do not pay. **The draw figures are the comparable ones.** |
  | no `-video none` | snapshots are needed for §4D | ★ No — our eye-gate arm also runs windowed. |
  | no `-nothrottle` on the operator run | §2U.2: a human is driving | ★★ No — every figure is in **emulated** time and frames. |
  | `-snapview/-snapsize/-keepaspect` | snapshot geometry only | No. |

  ★★★ **Same machine, same ROM set, same 512 KB, same `coco3` driver.** ★★ The headless boot
  (`sierra_boot.lua`, 150 emulated s, 1203% speed) reached gameplay at f05430 = 90.5 s unattended;
  the measured run was Jay-driven, because movement is CTRL+letter.

- **AC-2 [class: measurement]** §4B's three observables, theirs and ours, frame-counted — **PASS.**

  **(1) Room transition.** `sierra_rooms.py` over 8,486 frames, 0.02–141.61 s:

  | # | start | disk | draw | total | lat |
  |---|---|---|---|---|---|
  | 1 | 56.62 | 3.104 | 1.585 | 4.689 | 66/160 |
  | 2 | 83.17 | 2.603 | 1.569 | 4.172 | 115/160 |
  | 3 | 114.21 | 1.669 | 1.719 | 3.388 | 114/160 |
  | 4 | 133.52 | 3.004 | 1.018 | 4.022 | 51/160 |
  | | **median** | **2.80** | **1.58** | **4.10** | |

  **Ours: 6.16 s** [P6.85], all draw. ★★★★ **Their draw 1.58 s against our 6.16 s = 3.9×.**

  **(2) Ego steps/second while walking.** A 7.7 s window with `fdc = 0` (no disk) during Jay's
  movement burst: **45 events = 5.87/s.** **Ours: 3.33 cycles/s** (0.3004 s median, P6.90); an AGI
  ego advances one step per cycle, so the two are the same quantity.

  **(3) Sprite animation rate.** Their KQ3 rooms, ego still: **0.00/s** over 5.3 s and **0.40/s**
  over 10.0 s. ★★ Their *opening* room (headless run) gave **2.52/s**, so it varies by room.
  **Ours is the cycle rate, 3.33/s**, because every loop advances one cel per cycle [P6.90].

- **AC-3 [class: measurement]** §4C's scene descriptions — **PASS, and the mismatch is the point.**

  | | Sierra KQ3 (measured window) | ours (castle room 1) |
  |---|---|---|
  | staged sprites | not countable without their resources | **4** |
  | animating with ego still | ★★★★★ **~0** (0.00–0.40 events/s) | ★★★★★ **3 of 4, every cycle** (3.11 decodes/cycle) |
  | ego moving | yes, CTRL+arrow, 7.7 s | yes, `LEFT` held |
  | screen fill | full room, 320×192×16 | full room, 320×200×16 |
  | depth test exercised | ★★★★ **yes — ego occluded by a doorway** (Jay) | yes |

  ★★★★ **What could not be matched, stated rather than fudged:** their sprite *count* is not
  observable without reading their volumes [§6 trigger 4], and **their idle animation load is
  visibly lighter than our castle's.** ★★★ **So the walking comparison (5.87 vs 3.33) flatters
  them by an unquantified amount**, and the room-change comparison (1.58 vs 6.16) is the cleaner
  of the two because both are drawing a whole picture.

- **AC-4 [class: measurement]** §4D's comparison and what it shows about the work being done —
  **PASS.**

  1. ★★★★★ **Priority: THEY HAVE IT AND IT RAN.** Jay: *"ego didnt go behind in the run we just
     did but im pretty sure he does in parts of the gsme"*, then *"actauul he is occluded by the
     doorway in one room change"*. ★★★★★ **So their blit does a depth test, as ours does, and the
     3.9× cannot be attributed to them skipping it.** ★★★ **This is the finding I was one sentence
     away from getting backwards**: a 0.00/s idle change-rate makes "no priority" the tempting
     read, and it would have been wrong [§2W.3 — the most incriminating available reading].
  2. ★★★★★ **Fidelity: NOT reduced.** GIME settles at t=33.976 s to `VMODE=$80 BP=1`, `VRES=$1E`,
     `LPF=0`, `VSCROLL=$00` and **never changes again for the rest of the 141 s run**. `$1E` is our
     mode 1, **320×192×16, 160 bytes/row**. ★★ **Citation chain stated honestly**: this mapping is
     cited from our own `src/hal/coco3-dsk/hal_globals.s`, whose comment carries
     `[ref: GIME-RM §10]`. **`docs/ground-truth/` in this tree holds only `.gitkeep`**, so I could
     not check the GIME RM myself — `[no-ref: $1E ↔ 320×192×16 — second-hand through
     hal_globals.s; discharge by checking GIME-RM §10 when the document is present]`.
  3. **How many animate at once:** measured as ~0 idle in the rooms visited (AC-2(3)). Not
     separately confirmed by eye.
  4. **Text-area split:** ★ **not answered.** Jay was asked and answered (1); this and (3) were not
     pressed. **Recorded as open** — it is §4D's lowest-starred item and nothing here rests on it.

- **AC-5 [class: attribution]** ★★★★★ **The bar, as a number.**

  > **Sierra's own CoCo3 AGI draws a room in 1.58 s (median of 4) and walks the ego at ≥5.87
  > steps/second, at 320×192×16, with a working priority plane, on a 512 KB CoCo3 under MAME.**
  > **We are at 6.16 s and 3.33/s.**

  **With §1.2's caveats attached, every one of them:**
  1. ★★★★ **Their conversions drop content** — KQ1's CoCo3 release cuts 26 of 48 sounds;
     KQ3's `words.tok` is 4,463 against the PC's 5,657 [design §1.2a]. ★★★ **Neither costs a
     cycle**, but **their scene load is lighter in a way this task measured (idle ~0 vs our 3.11
     cels/cycle) and could not quantify on their side.**
  2. ★★★ **V3 LZW is a later AGI with a different decompression path** — not the interpreter we
     are porting.
  3. ★★★★★ **5.87/s is a LOWER BOUND.** The lattice is 16×10 over 640×239 and their ego trips
     ~1.1 points per event, so it can only undercount. ★★★★ **That is safe in one direction only,
     and it happens to be the direction that matters: they are faster, by at least 1.8×.**
     ★★ **It must never be quoted as an equality** [§2W.3].
  4. ★★ **Both figures are under MAME.** Neither side has run on hardware, which is what makes the
     comparison fair [§2].

- **AC-6 [class: byte-comparable]** **PASS.** `git diff --stat -- src/` produced no output;
  `git diff --name-only -- src/` counted **0** files.

- **AC-7 [class: suite]** **PASS by §2T citation.** Nothing was rebuilt because nothing changed:
  `src/` is untouched (AC-6) and the only edit is a comment block in `gates.manifest`, which no
  artifact depends on. Gates cited from **P6.90's report §5, run 2026-09-23 at HEAD `4452c98`**:
  `pic` 45/45, `res` 1,264/1,264, `cel` 9,193/9,193, `comp` 124/124, `vm` 9/9, nine arms and five
  probes byte-identical. ★ **POP and Karateka were not touched and no sibling claim is made**, so
  §2T's HEAD/clean check does not apply here.

- **AC-8 [class: ruling requested]** **PASS** — §7 below.

- **AC-9** **PASS.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
=== §1.1a, the machine (mame coco3 -listxml) ===
<ramoption name="128K">131072</ramoption>
<ramoption name="2M">2097152</ramoption>
<ramoption name="8M">8388608</ramoption>
<ramoption name="512K" default="yes">524288</ramoption>

=== §4A, media, §2P (copied, never mounted) ===
OK  368640 B  sha 20EA31A82087DA90  kq3-1.dsk      <- matches P3.6's pin
OK  368640 B  sha 2207F25E8860F324  lsl-1.dsk
media OK  KQ3  sha256[0:16]=20EA31A82087DA90
checking sierra_live.lua loads...  OK

=== §4A, the unattended boot (sierra_boot.lua, 150 emulated s) ===
[f00300] posting DOS
[f02400] monitor prompt should be up (PC=$FD5F)
[f02460] posting R (capital -- idiom 41c)
[f02580] posting ENTER (separate post)
[f05400] CTRL+BREAK past the title (41d)
[f05430] BREAK released -- GAMEPLAY
Average speed: 1203.47% (149 seconds)

=== §4B(1), THE INSTRUMENT (sierra_rooms.py, offline, Jay-driven run) ===
build\sierra_bench_live\frames.csv: 8486 frames, 0.02..141.61 s
params: gap=0.5s settle=1.0s min_lat=30/160 min_fdc=2000

 #  start_s   disk_s   draw_s  TOTAL_s     fdc   lat  pk/frm  voff
 1    56.62    3.104    1.585    4.689   11985    66      14     0
 2    83.17    2.603    1.569    4.172    7970   115      16     0
 3   114.21    1.669    1.719    3.388    6900   114      16     0
 4   133.52    3.004    1.018    4.022   10681    51      12     0

n = 4
  TOTAL  min 3.39  median 4.10  max 4.69 s
  DISK   min 1.67  median 2.80  max 3.10 s   <- 68% of the median total
  DRAW   min 1.02  median 1.58  max 1.72 s   <- 38%
  VOFFSET writes across all transitions: 0   <- a room change is NOT a page flip
  peak PER-FRAME lattice change: 16/160   <- why a per-frame detector is blind to this

=== §2W, the two instruments cross-checked ===
live candidates : RC3 3.371 s   RC4 4.005 s
offline tool    : RC3 3.388 s   RC4 4.022 s
delta            +0.017 s = EXACTLY ONE FRAME, the coalescing offset. Two independent
                 implementations of the same state machine, agreeing.

=== §4B(2)/(3), the lattice, windows chosen from the key log ===
MOVING (keys 120.6-127.4 s)     7.7 s  fdc      0  changed-frames 51  EVENTS 45 = 5.87/s  mean lat 1.1/160 max 2
idle after that burst           5.3 s  fdc  14829  changed-frames  0  EVENTS  0 = 0.00/s  mean lat 0.0/160 max 0
idle before room change 3      10.0 s  fdc  19202  changed-frames  5  EVENTS  4 = 0.40/s  mean lat 1.2/160 max 2

=== §2W, the lattice shown able to read BOTH ends, on this run ===
static title screen            0.15/s      <- it goes quiet when the screen does
idle KQ3 room                  0.00/s      <- and all the way to zero
opening room (headless run)    2.52/s
ego walking                    5.87/s

=== §4D(2), GIME, the Jay-driven run (last display change in 141 s) ===
[f02036] t=33.976  * GIME: VRES=$1E LPF=0  INIT0=$6C  VMODE=$80 BP=1  VSCROLL=$00

=== ours, for comparison (src/hal/coco3-dsk/hal_globals.s) ===
        fcb     $1E                     ; mode 1: 320x192x16 VRES  [GIME-RM §10]
        fcb     160                     ;   160 bytes/row

=== AC-6 ===
$ git diff --stat -- src/
(no output)
src/ files changed: 0  (AC-6 requires 0)
```

**25.2 bundled-artifact grep:** N/A — nothing was built or bundled.

**25.3 operator-runtime-smoke:** ★★★★★ **PASSED — Jay, live-disk, RGB.** Jay booted Sierra's KQ3
from a mounted floppy (`-ext fdc -flop1`), walked the ego with CTRL+arrow, and passed through four
room changes. ★★★★ **This is a `live-disk` gate on THEIR program, not ours** — our own p3b was not
run in this task and needs no gate, since no byte of it moved. **Jay's §4D(1) observation is the
gate's finding.**

### 6 — Reactive deviations and route accounting

1. ★★★ **`sierra_rooms.py` could not read the headless run's CSV** — `sierra_boot.lua` writes
   `frame,time_s,changed,fdc,fb_writes,note` and the tool expects `sierra_live.lua`'s schema with
   `voffset` (`KeyError: 'voffset'`). ★★ **I did not adapt the tool or write a second one.** The
   measured figures come from `sierra_live.lua`'s CSV via the tool the tree names as THE
   instrument; the headless run's role was reduced to proving the boot is unattended and giving the
   opening room's 2.52/s. ★ **Recorded because a reader may otherwise expect the two runs to be
   interchangeable. They are not.**
2. ★★★★ **I mutated a tracked file by running MAME, and restored it.** My ad-hoc headless
   invocation passed `-cfg_directory harness\mame-cfg\sierra-live` — the **tracked seed** — and
   MAME wrote a `<video><target .../></video>` block into `coco3.cfg` plus an untracked
   `default.cfg`. ★★★ **`sierra_live.ps1` copies the seed to a temp dir for exactly this reason and
   I bypassed it by hand-rolling the command.** Restored with `git checkout --`; the stray file
   deleted; **the hazard is now recorded in `gates.manifest` so the next reader does not repeat
   it.** ★★ **Same shape as §2P's rule** — a tool that opens a file the tree owns for writing.
3. ★★ **The automated movement probe was NOT retried.** `sierra_boot.lua`'s `SIERRA_WALK` drives
   `ioport_field:set_value()`, which steals CTRL for the session and never worked. **CLAUDE.md §6
   forbids retrying a failed approach without Jay's authorization**, so §4B(2) was obtained with
   Jay at the keyboard instead.

**ROUTE ACCOUNTING.** I proposed one route to Jay: run `sierra_live.ps1`, type the four-step boot,
walk for ~20 s, and pass through a door. ★★ **That is exactly what was run and exactly what the
figures come from.** I also told Jay to expect a draw near P3.6's 0.384 s *or* near 3 s, and said
which conclusion each would support; ★★★ **the answer was 1.58 s — between the two I named** — and
§3 records the 0.384 s as scene-specific rather than quietly dropping it. **Nothing was proposed
that was not done, and nothing was done that was not proposed.**

### 7 — Uncertainty flags, and AC-8's ruling request to Jay

★★★★★ **The question this task was created to settle, answered:**

> **Sierra's own CoCo3 AGI draws a room in 1.58 s where we take 6.16, and walks the ego at ≥5.87
> steps/second where we manage 3.33 — at the same 320×192×16, with a working priority plane.**
> ★★★★ **The gap is real and structural. It is not explained by them rendering less, and it is not
> explained by them skipping the depth test.**

★★★★ **The one honest discount is workload, and it is not small:** their rooms animate ~nothing
while the ego stands, and our castle composites 3 cels every cycle regardless. **Some unknown part
of the 1.8× walking gap is that, and none of the 3.9× room-change gap is** — a room draw is a whole
picture on both sides.

**What I am asking you to rule on:**

1. ★★★★★ **Is 1.58 s / 5.87 per second now the target, replacing AGI's PC 10/second?** ★★★ **The
   PC figure is on hardware several times faster and no CoCo3 has ever hit it.** **Sierra's number
   is the first target this project has had that a CoCo3 is known to achieve.**
2. ★★★★ **Does "playable" equal "AGI-rate"?** §7 of the dispatch raises it and this task cannot
   settle it: **you called 3.3/s unplayable**; ★★★ **Sierra shipped at ≥5.87 and presumably called
   it playable.** **The answer sets whether ~6/second ends the speed work or is a waypoint.**
3. ★★ **Is the castle the right benchmark scene for us?** It is our busiest and it may be
   flattering their numbers. A quieter room would compare more directly.

**Uncertainty flags:**
1. ★★★★ **5.87/s is a lower bound, not a measurement of their cycle rate.** §4D's caveat 3. **It
   must not be quoted as an equality**, and a future task wanting their true rate needs a different
   instrument than a 16×10 lattice.
2. ★★★ **n=4 room changes, one title, one session.** The draw range is 1.02–1.72 s, so the median
   is stable-ish, but **P3.6's 0.384 s from the same game shows how far a single transition can
   sit from it.**
3. ★★★ **Their sprite count is unknown** and cannot be obtained without reading their volumes
   [§6 trigger 4, §1.1]. **The workload discount is therefore directional, not numeric.**
4. ★★ **`$1E ↔ 320×192×16` is second-hand** through `hal_globals.s`; the GIME RM is not in this
   tree. Carried as a `[no-ref]` debt in AC-4(2).
5. ★ **§4D(3) and §4D(4) are unanswered** — you answered (1), which was the load-bearing one.

### 8 — Follow-up candidates

1. ★★★★★ **Whatever the ruling in §7(1) is, the design spec's speed target should be restated in
   CoCo3 terms** — §9's first delta, **PROPOSED TEXT ONLY** [§2D].
2. ★★★★ **The two-destination row blit** [P6.90 §8(1)] — still the highest value-per-risk item in
   hand, and now it has a bar to close against.
3. ★★★★ **The map ruling** — P6.90 priced its fifth symptom at ~15% of a cycle, which is a
   meaningful fraction of a 3.9× gap.
4. ★★★ **A quieter benchmark room on our side** — §7(3).
5. ★★ **Measure a Sierra room change on a title we also run at the same room**, for a true
   like-for-like. KQ1, KQ2, KQ3 and PQ1 all exist on both sides.
6. Carried, unchanged: the VIEW checksum gap; design spec §7.1's `0.039 s/cycle` (fourteen tasks
   flagged); the fill and the two core loops as rulings; option 3 and the sidecar variant; a scene
   separating P6.88's two guards; real-time pacing; typing cadence; the title page items;
   `checkPriority`/`checkCollision`; `MAP_PRI_BANDS`.

### 9 — User interaction during task

1. **Asked Jay** to drive the operator run (four boot/play steps), **with expectations stated**:
   that a draw near 0.384 s would mean the gap is in drawing, and near 3 s would mean P3.6's figure
   was scene-specific. Jay: **"run it"**, and drove it.
2. **Asked Jay** three §4D questions I am forbidden to answer from pixels [CLAUDE.md §3], with the
   stills surfaced first and uninterpreted. Jay: **"ego didnt go behind in the run we just did but
   im pretty sure he does in parts of the gsme"**, then, mid-turn: **"actauul he is occluded by the
   doorway in one room change"**. ★★★★ **The correction arrived before the report was written and
   changed AC-4(1) from "not observed" to "observed, and it runs".**

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-23-measure-the-bar-on-the-target-machine.md`

### 11 — Commit
(recorded below after push)
