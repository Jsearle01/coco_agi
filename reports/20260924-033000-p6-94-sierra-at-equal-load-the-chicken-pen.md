## Form B Report — T-P0-148 / P6.94 — Sierra at equal load: the chicken pen
**Class:** measurement. wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-24 (HEAD `d130aa7`, wip). git status clean at t0.

### 1 — Summary

**The pen was reached, measured, and it answers the question — but not with the number the dispatch
asked for.**

★★★★★ **The direct comparison the dispatch wanted cannot be made, and the reason is structural:**
their figure is a **coalesced screen-update rate** and ours is a **cycle rate**. P6.91 already
flagged the ≥5.87 as a lower bound that *"must never be quoted as an equality"*; dividing by load
makes that worse, because **two chickens updating in the same frame register as one event.**

★★★★★ **So the comparison was made a different way: each interpreter against ITSELF under load, and
then the two ratios against each other. That cancels the instrument.**

| | no/low animation | with animation | **cost of the load** |
|---|---|---|---|
| **Sierra**, walking (lattice events/s) | ≥5.87 near-empty [P6.91] | **5.23** pen, +2 chickens | **−10.9%** |
| **Ours**, standing (cycles/s) | 15.0 room 83, 0 sprites | **4.99** castle, 4 sprites | **−66.7%** |
| **Ours**, walking | 15.0 | 4.28 | −71.5% |

> ★★★★★ **Adding two animating objects costs Sierra ~11% of its rate. Adding four sprites costs us
> ~67%. Our sensitivity to animation load is ~6× theirs.**

★★★★ **VERDICT (AC-4): BEHIND AT EQUAL LOAD** — §1.2's second branch. ★★★ **The speed arc
continues, and the dispatch names where: the blit.** `cp_composite` is ~29% of the drawing stage and
is now the largest single item.

★★★ **§4D answered, by Jay: the chickens pass behind each other.** ★★ **So their interpreter runs a
depth test over several simultaneously-cycling objects and still loses only 11%.** Fidelity
(`320×192×16`) and the depth test were already excluded [P6.91]; **this excludes "they do not
occlude" as well.**

★★ **No `src/` change** (AC-6: `git diff --stat -- src/` empty).

### 2 — Files modified
- `harness/tools/sierra_events.py` — **NEW.** The events/second measurement, written down at last
  (§3(3)), with a `--selftest` that re-derives P6.91's own published figures from P6.91's own data.
- `harness/tools/gates.manifest` — §9 delta 1: this task's equal-load figures beside P6.91's, with
  the object count, the 7× per-room range, and the ratio comparison — **so ≥5.87 cannot be quoted
  as an engine-speed ratio by the next reader.**

### 3 — Reasoning

**§3(1)** — nine arms at P6.93's figures; this task changed no `src/`.

**§3(2)/(3) — how P6.91 obtained ≥5.87, and it is the reason this task nearly could not run.**
★★★★★ **`sierra_rooms.py` measures room TRANSITIONS and nothing else. No tool in the tree computed
the events figure.** P6.91's ≥5.87, 0.00 and 0.40 all came from **an unsaved scratchpad script** —
★★★★ **L-45 exactly**, and T-P0-015's withdrawn 88%-disk figure is the precedent this project
already paid for.

★★★★★ **§6's second trigger was therefore live**: *"the event definition cannot be made identical to
P6.91's — then the two figures are not comparable."* ★★★ **It was closed by writing the definition
down and proving it**, not by asserting it:

> **the 16×10 lattice; a frame counts when `changed > 0`; CONSECUTIVE counting frames coalesce into
> ONE event; the disk must be quiet; rate = events / (frames/60).**

★★★★ **`sierra_events.py --selftest` reproduces 5.87/s, 0.00/s and 0.40/s from
`build/sierra_bench_live/frames.csv` — all three of P6.91's published numbers, to the digit.** The
definitions are identical **by construction** [§2W].

**§3(4)** — the cfg hazard P6.91 recorded was honoured: `sierra_live.ps1` was used as-is, which
copies both the disk (§2P) and the cfg seed. **No tracked file was mutated this run.**

**Authority tier.** The rates are **tier 2** (the running original). ★★★★ **The scene — the route,
the object count, the occlusion — is Jay, tier 1**, and was decisive twice: see §6(1).

**§2H's three checks.** (1) *A second mechanism for a different object class?* ★★★★★ **Yes, and it
is the finding**: the ego and the chickens load the instrument differently — walking is stable
across sub-windows (4.72–5.74) and standing is not (1.32–4.17), because a small chicken trips a
sample point only when it overlaps one. (2) *The calling routine.* The event rate is a property of
**the room**, not of the interpreter: across Sierra's own rooms in one run it ranges **0.86 → 5.87**,
a 7× spread. **A metric that varies 7× across rooms of the same interpreter cannot measure
interpreter speed** — which is why §4C is built on ratios. (3) *Grep the reports.* P6.91 (the rates
and their lower-bound caveat), P6.92 (room 83 at 15.0), P6.93 (castle at 4.99/4.28) agree and none
contradicts.

**§2S.** No sibling claim is made.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: measurement]** ★★★★★ **PASS — the pen was reached, and the object count is stated
  before any rate.** ★★★★ **Jay: *"there 2 chickens in the pen plus me moving"*** — so **2 animating
  objects standing, 3 moving**. ★★ Against our castle's **4 staged, 3 animating standing** [P6.90].
  **Their load is lighter than ours**, which §4C's verdict is careful to allow for.

  ★★★ **The route, from Jay:** starting room → an unintended room (RC1 76.2 s) → back to the
  starting room (RC2 157.8) → outside (RC3 267.2) → **the pen (RC4 288.9)** → the room where he died
  (RC5 391.7). **The pen is a 99.1 s visit**, 292.6–391.7 s.

- **AC-2 [class: measurement]** ★★★★★ **PASS, n = 4 per figure, with spread.** Sub-windows of the
  pen visit:

  | | window | events/s | sub-windows (n=4) | spread |
  |---|---|---|---|---|
  | **standing** (no keys, 2 chickens) | 63.3 s | **2.12** | 1.39 · 4.17 · 1.58 · 1.32 | **3.2×** |
  | **walking** (2 chickens + ego) | 27.1 s | **5.23** | 4.72 · 5.45 · 5.01 · 5.74 | **1.2×** |

  ★★★★★ **The spread is itself the finding.** Walking is tight because the ego changes the screen
  constantly and the lattice samples it reliably. **Standing is 3.2× loose because whether a small
  chicken overlaps one of 160 sample points dominates the count** — mean lattice **1.0 of 160**,
  max 2. ★★★ **That is why the standing figure cannot carry the verdict**, and why §4C uses ratios.

- **AC-3 [class: measurement]** **PASS — §4C's table, with the incomparable cells marked rather than
  silently filled.**

  | | objects animating | ego | rate | instrument |
  |---|---|---|---|---|
  | Sierra, idle room [P6.91] | ~0 | still | 0.00–0.40 | lattice events/s |
  | Sierra, walking [P6.91] | ~0 | walking | ≥5.87 | lattice events/s |
  | **Sierra, chicken pen** | **2** | still | **2.12** (1.32–4.17) | lattice events/s |
  | **Sierra, chicken pen** | **2** | walking | **5.23** (4.72–5.74) | lattice events/s |
  | Ours, room 83 [P6.92] | 0 | still | 15.0 | cycles/s |
  | Ours, castle [P6.93] | 3 of 4 | still | 4.99 | cycles/s |
  | Ours, castle [P6.93] | 3 of 4 | walking | 4.28 | cycles/s |

  ★★★★★ **The two halves are NOT the same quantity and must not be read down the column.** The
  comparison that is valid is the **ratio within each side**, §1's table.

- **AC-4 [class: attribution]** ★★★★★ **BEHIND AT EQUAL LOAD.**

  > **Sierra loses ~11% of its rate to two animating objects. We lose ~67% to four sprites. Our
  > per-object cost is roughly 6× theirs.**

  ★★★★ **And the comparison is conservative in their favour on both sides**: their load is 2 objects
  against our 3 animating, and **a coalescing metric under-reports their cost**, so their true
  sensitivity may be higher than 11%. ★★★ **Neither correction plausibly closes a 6× gap.**

  ★★ **What it implies for the arc** [§1.2]: not branch one (we are not level), and not branch three
  (the loads were matchable enough to bound the answer). **Branch two: there is a technique we have
  not found, and the blit is where to hunt it.**

- **AC-5 [class: measurement]** **PASS.** ★★★★ **Jay: *"the chickens do pass behind each other"*.**
  So Sierra depth-tests several simultaneously-cycling objects at different priorities. ★★★
  **Combined with P6.91 (same `320×192×16` mode, ego occluded by a doorway), the three cheap
  explanations for their speed are now all excluded: not lower fidelity, not a missing depth test,
  and not "their objects never overlap".**

- **AC-6 [class: byte-comparable]** **PASS.** `git diff --stat -- src/` produced no output; 0 files.

- **AC-7 [class: suite]** **PASS by §2T citation.** `src/` untouched, so no artifact changed. Cited
  from **P6.93's report §5, run 2026-09-24 at HEAD `72678d4`**: `pic` 45/45, `res` 1,264/1,264,
  `cel` 9,193/9,193, `comp` 124/124, five p3b probes, *"all green"*, exit 0. ★ No sibling touched.

- **AC-8 [class: ruling requested]** **PASS** — §7.

- **AC-9** **PASS.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
=== §3(3), the debt paid: the tool reproduces P6.91's own published figures ===
$ python harness/tools/sierra_events.py --selftest
SELFTEST against build\sierra_bench_live\frames.csv -- P6.91's own recording
MOVING (keys 120.6-127.4 s)       7.7 s  events   45 =  5.87/s   (changed frames  51, mean lat 1.1/160, max 2)
idle after that burst             5.3 s  events    0 =  0.00/s   (changed frames   0, mean lat 0.0/160, max 0)
idle before room change 3        10.0 s  events    4 =  0.40/s   (changed frames   5, mean lat 1.2/160, max 2)

P6.91 published 5.87/s for the moving window; this tool computes 5.87/s -- MATCH, the
definitions are identical
exit=0

=== §4A, the route (sierra_rooms.py, THE instrument), 23,908 frames, 399.0 s ===
 #  start_s   disk_s   draw_s  TOTAL_s     fdc   lat  pk/frm  voff
 1    76.20    3.104    0.417    3.521   11985    62      14     0
 2   157.77    1.318    1.719    3.037    3822    58      13     0
 3   267.24    1.502    1.418    2.920    6908    57      11     0
 4   288.87    2.603    1.118    3.721    7975   105      16     0     <-- INTO THE PEN
 5   391.74    0.701    1.202    1.902    2768   100      16     0     <-- out, to the death room
n = 5   TOTAL median 3.04 s   DISK median 1.50   DRAW median 1.20

=== §4B, the pen (sierra_events.py) ===
PEN standing (no keys 292.6-355.9)   63.3 s  events  134 =  2.12/s  (mean lat 1.0/160, max 2)
PEN walking  (keys 355.9-383.5)      27.1 s  events  142 =  5.23/s  (mean lat 2.9/160, max 16)

standing q1  1.39/s   q2  4.17/s   q3  1.58/s   q4  1.32/s      <- spread 3.2x
walking  q1  4.72/s   q2  5.45/s   q3  5.01/s   q4  5.74/s      <- spread 1.2x

=== §4C, each side against ITSELF, which cancels the instrument ===
SIERRA, walking, lattice events/s both times:
   near-empty rooms [P6.91]  >= 5.87   ->  chicken pen, +2 chickens  5.23   =  -10.9%
OURS, standing, cycles/s both times:
   room 83, 0 sprites          15.0   ->  castle, 4 sprites          4.99   =  -66.7%
OURS, walking: castle 4.28 -> -71.5% against the 15.0 no-sprite figure
ratio of sensitivities: 6.1x

=== the metric's own range across Sierra's rooms, one run ===
starting room  0.86/s (mean lat 10.5)   pen standing 2.12   pen walking 5.23
   -- 7x across rooms of the SAME interpreter, which is why §4C uses ratios

=== the one load-independent comparable, now n=9 across two runs ===
draws: 0.417 1.018 1.118 1.202 1.418 1.569 1.585 1.719 1.719
   P6.91 n=4 median 1.577 · P6.94 n=5 median 1.202 · COMBINED n=9 median 1.418 s
   ours 6.16 s (all draw, RAM-staged) = 4.3x the combined median
   ★ my arithmetic on their published values, labelled unverified per §8

=== AC-6 ===
$ git diff --stat -- src/       (no output)   src/ files changed: 0
```

**25.2 bundled-artifact grep:** N/A — nothing built or bundled.

**25.3 operator-runtime-smoke:** ★★★★★ **PASSED — Jay, live-disk, RGB.** Jay booted Sierra's KQ3
from a mounted floppy, walked to the chicken pen through four room changes, stood still 63 s, walked
27 s, and left. **His observations are AC-1 and AC-5.**

### 6 — Reactive deviations and route accounting

1. ★★★★★ **I mapped the pen to the wrong room change and Jay corrected me.** I read the pen as
   RC3→RC4 (an 18.7 s visit, 12.3 s of it with 27,380 FDC accesses) and reported it as unusable.
   ★★★★ **Jay: *"go back before the disk loads, i stood still for at least 20 secs"*** — the pen is
   **RC4→RC5**, a 99.1 s visit with a 63.3 s disk-quiet standing window. ★★★ **I had the right data
   and the wrong label**; the window I had called "the death room" was the pen. **The correction
   came from the operator, and no measurement was re-run to get it** — only relabelled.
2. ★★★★★ **§6's second trigger was live and was closed by building the missing tool**, not by
   proceeding. **Without `sierra_events.py` and its self-test, every figure in this report would
   have been incomparable with P6.91's by assertion.**
3. ★★★ **The direct Sierra-vs-us comparison the dispatch specified was NOT made**, because the two
   quantities are not the same. ★★★★ **Replaced by a ratio-of-ratios**, which is a genuine
   deviation from §4C's table shape and is marked in the table itself.

**ROUTE ACCOUNTING.** I proposed to Jay: boot, reach the pen, stand ~30 s, walk ~30 s, and answer
two questions. **All of that happened** (he stood 63 s and walked 27 s), and both questions were
answered. I also told him what I expected — 4–5 would mean level, 9–10 would mean a missing
technique. ★★ **The answer was 5.23 walking, which is neither**, and §4C explains why the expectation
was the wrong shape: the rate barely moves because **the metric saturates on the ego**, and the load
signal is in the *ratio*, not the level. **Stated rather than quietly re-framed.**

### 7 — Uncertainty flags, and AC-8's ruling request to Jay

★★★★★ **Where we stand at equal load:**

> **Their interpreter loses ~11% to two animating, mutually-occluding objects. Ours loses ~67% to
> four sprites. That is a ~6× difference in cost per animated object, and it is not explained by
> fidelity, by a missing depth test, or by their objects not overlapping — all three are now
> excluded by measurement.**

**What I am asking you to rule on:**

1. ★★★★★ **Does the speed arc continue into the blit?** §1.2's second branch is the one that fired.
   `cp_composite` is ~29% of the drawing stage and the cel cache has already taken the decode's
   share. **This is the next largest item and the first one with a measured reason to expect a win.**
2. ★★★★ **Is ~4.3× on the room draw still worth a task?** It is the one genuinely load-independent
   comparable and it has not moved: **their median 1.418 s over n=9, ours 6.16 s.**
3. ★★★ **Do you want a better instrument before more comparisons?** Everything here rests on a 16×10
   lattice that cannot count objects. **A finer grid is cheap** and would tighten the standing
   figure's 3.2× spread — but it is host-side work with no direct payoff to the port.

**Uncertainty flags:**
1. ★★★★★ **The 11% is a lower bound on their cost.** A coalescing metric under-reports load, and
   their walking figure may be saturated by the ego. ★★★ **So their true sensitivity could be
   higher** — but 11% would have to be wrong by 6× to close the gap.
2. ★★★★ **Their load is lighter: 2 animating objects against our 3.** Normalising per object would
   make our figure worse, not better, so **the verdict's direction is safe and its magnitude is
   not.**
3. ★★★★ **The standing figure's spread is 3.2×** (1.32–4.17) and the instrument's own limit is why.
   **Only the walking figure is tight enough to quote as a level**; the verdict rests on ratios, not
   on either level.
4. ★★★ **`sierra_events.py`'s self-test validates against ONE recording.** It proves the definition
   matches P6.91's; it does not prove either is the right definition.
5. ★★ **n=1 room for the pen**, one visit, one operator session.

### 8 — Follow-up candidates

1. ★★★★★ **The blit** — §7(1). `cp_composite` ~29% of the drawing stage, and this task is the
   measured reason to go there.
2. ★★★★★ **Put the cel cache in the gated arms** — P6.93 §7(1), still open and still the largest
   correctness gap: **no gate currently compiles the cache.**
3. ★★★★ **The room draw at 4.3×** — §7(2).
4. ★★★ **A finer lattice** — §7(3).
5. ★ **§9's remaining deltas**: the speed target's home [delta 2] and the design spec [delta 4] are
   **PROPOSED TEXT ONLY** and belong to the Orchestrator [§2D]; `memmap.inc` is a §6 stop trigger so
   its counter was not bumped [delta 3]. ★★ **Delta 1 is DONE** — see §2.
6. Carried: region A at 223 bytes; the VIEW checksum gap; design spec §7.1's `0.039 s/cycle`;
   option 3 and the sidecar; real-time pacing; `checkPriority`/`checkCollision`;
   `p3_stage_sprites` has no sort; `MAP_PRI_BANDS` (thirty-ninth task — ★ `memmap.inc` is a §6 stop
   trigger, not bumped).

### 9 — User interaction during task

1. **Jay drove the operator run** — boot, four room changes to the pen, 63 s still, 27 s walking.
2. **Jay answered the two questions I cannot** [CLAUDE.md §3]: *"there 2 chickens in the pen plus me
   moving"* and *"the chickens do pass behind each other"*. **Both are load-bearing** — AC-1 and
   AC-5.
3. ★★★★ **Jay corrected my room mapping**: *"go back before the disk loads, i stood still for at
   least 20 secs, you should be able to find that in the log"*. **He was right and it changed the
   task's answer from "unmeasurable" to a verdict.**
4. Jay on the controls: *"the controls on the coco3 kq3 are terrible"* — recorded because it is why
   the route wandered through two unintended rooms.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-24-compare-each-side-against-itself.md`

### 11 — Commit
`4fcbf42` (pushed to origin/wip before this report)
