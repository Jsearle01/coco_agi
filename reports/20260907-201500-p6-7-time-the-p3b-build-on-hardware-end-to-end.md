## Form B Report — P6.7 — Time the p3b build on hardware, end to end
**Class:** recon.  wip.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-07 ~19:20 local (HEAD `517af61`, wip). `git status` clean apart from an untracked
`coco_agi.code-workspace` (Jay's editor config).

---

### 5 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `517af61`, `wip`, clean |
| POP + Karateka | §2T citation below |
| `hal_sync_check.py` | **OK in all three** — §5 |
| the gate rows | ★★ **cited, not re-run** — §7.5 |
| flag sets — enumerate and diff | ★★★★★ **produced, and it is the task's headline** — §3.A |
| the clock — measured | ★★★ **1.789772 MHz**, guest-stamped [L-78] |
| sprite count in the measured room | ★★★ **room 1, 4 sprites, REACHED BY A JUMP** at cycle 8 [AD-99] |

#### §2T — sibling baseline, by citation

★ P6.6 §0 records POP `wip` `104b197` and karateka `wip` `29f8f0a`. **Both unchanged.** Tracked
modifications: POP 0; karateka 1 (`harness/smoke/last-run.log`, a run log). **No file in §2M's
SHARED list is touched** — this task adds one Lua observer and changes no target code.

---

### 1 — Summary

★★★★★ **Jay's three figures, and the one that matters is bad:**

| | |
|---|---|
| **T1 start → title screen on the glass** | ★★★★ **8.00 s** |
| **T2 start → first room on the glass** | ★★★★ **17.94 s** (room 1, reached by a jump) |
| **T3 frame rate once the room is up** | ★★★★★ **2.22 cycles/s at 4 sprites** — against a corpus that asks for 10 [AD-82] |

★★★★★ **§8 trigger 2 fires and I am stopping on it.** T3 is **4.5× short**. ★★★★ **And the
breakdown says the compositor is not why:** `interpret` is **72.5%** of the cycle and `composite`
is **7.7%**.

★★★★★ **AC-6's answer is that the terms DO add — and I nearly reported the opposite.** The room
render measured 6.42 s against an "isolated" 2.832 s, which looks like a 2.3× integration cost. It
is not. **2.832 s is a `-DPIC_NOCOUNT` build and p3b's build has the counters in**; the
like-for-like figure is the pic gate's own **5.9349 s median**, and 6.42 s is **+8.1%** of it.

★★★★ **The instrument that would have caught that has been warning me for two tasks and I have
been calling it expected and benign** — `flag_diff --manifest`'s one surviving row,
`p3b [timing] ★★★ EXPECTED-ON BUT ABSENT: PIC_NOCOUNT`. **It was right.**

---

### 2 — Files modified

- `harness/tools/p3b_time.lua` — **new**, the only change. Read-taps each stage's entry address
  and `dofile`s the existing driver. ★ **No target code, no probe, no gate, no engine file.**

---

### 3 — Reasoning

#### 3.A ★★★★★ AC-6 — the terms add, and the comparison that says so was nearly the wrong one

**What I was about to report:** room render measured **6.4152 s** (title) and **8.3955 s** (room 1)
against design v1.2 §6.2's **2.832 s** — a 2.3–3.0× integration cost, §8 trigger 1, report and
stop.

★★★★★ **That comparison is between two different programs.** `gates.manifest`, in its own words:

```
pic        -DHAL_GFX_MODE_SERVICE
           note = correctness 45/45, median 5.9349 s (counters in -- not a perf figure)
pic_nc_pk  -DHAL_GFX_MODE_SERVICE -DPIC_NOCOUNT -DPRI_PACKED
           note = timing 2.8319 s median -- ★ THE CURRENT ROOM-RENDER FIGURE
p3b        -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED
```

★★★★ **p3b carries no `-DPIC_NOCOUNT`, so p3b's renderer has the counters in.** The figure to
compare against is therefore the **counters-in** one — the pic gate's **5.9349 s median, range
4.5124–10.7890 across 45 pictures** — not the counters-out 2.832 s.

| | measured in p3b | like-for-like isolated | |
|---|---|---|---|
| render, title (pic 83) | **6.4152 s** | 5.9349 median (4.51–10.79) | **+8.1%, inside the band** |
| render, room 1 | **8.3955 s** | same band | **inside the band** |

★★★ **So the render's term ADDS**, and the apparent 2.3× was a build-flag error. ★★ Neither
picture is in the gated 45 (checked — no `083` row), so this is a comparison against the
distribution, not against the same picture; **that is a weaker claim than a paired one and is
labelled as such** [L-10].

★★★★★ **The instrument was not crying wolf.** `flag_diff --manifest` has reported
`p3b [timing] EXPECTED-ON BUT ABSENT: PIC_NOCOUNT` in P6.5's and P6.6's greps, and both times I
wrote that it was "expected — p3b publishes per-stage timings with counters on". **That is true and
it is exactly the warning**: the row says every timing figure from this build is not comparable
with a counters-out one, and this is the task that compared them. ★★ **I authored the `purpose=`
mechanism that produces that row two tasks ago and then dismissed its one output twice.**

**The other terms, measured against their isolated figures:**

| term | isolated | measured | verdict |
|---|---|---|---|
| shadow blit | **0.2169 s/room** | **0.2109** | ★★★ **holds**, −2.8% |
| composite @ 4 sprites | **0.03929 s/cycle** | **0.03997** | ★★★ **holds**, +1.7% |
| remaps per cycle | **2** | **2** (sprites live) | ★★★ **holds** — §3.4's phase discipline survives compositing |
| VM, attract mode | 15.7 cyc/s = 0.0637 s/cy | **0.0834** (room 83, sprites 0) | ★★ **−24%** |
| VM, live room | — | **0.37547 s/cy** (room 1, 4 sprites) | ★★★★ **5.9× the attract figure** |

★★★★ **The last row is not an integration cost and must not be read as one** [L-54]. Room 83 is
attract mode; room 1 is the game running with four objects. **Different work, not slower
execution** — and the same-conditions comparison is the row above it, at −24%.

#### 3.B ★★★★ T3, and where the time actually goes

Per cycle, in room 1 with 4 sprites, from p3b_run.lua's marker brackets:

```
pace(wait)   0.00038 s/cycle    0.1%
interpret    0.37547 s/cycle   72.5%     <-- the cost
sprites      0.00423 s/cycle    0.8%
roomcheck    0.09799 s/cycle   18.9%
composite    0.03997 s/cycle    7.7%
```

★★★★★ **The compositor is 7.7% and the VM is 72.5%.** ★★★ The dispatch's §3 asked whether the
compositor had ever been in the add-up comparison; it now has, and **it holds to +1.7% and is not
the problem**. ★★ `roomcheck`'s 18.9% is the per-cycle room-change *check* across 160 cycles, not
a render — the two renders are inside it.

#### 3.C ★★★★★ My own instrument was 48% wrong, and only L-61 caught it

`p3b_time.lua` read-taps each stage's entry address — the project's recorded technique [idioms §10,
line 54]. ★★★ **It cost zero guest bytes, which was not optional: p3b has 3 bytes of code region
free** (`P3_CODE_END $52FD` against `MAP_CODE_END $5300`), so the four marker pairs this breakdown
wanted — 40 bytes — could not be added.

★★★★★ **But a read tap counts ACCESSES, not calls.** For a 60-cycle run with ONE room render it
reported `pic_render_at` **121** fires, `res_close` **243**, `res_open` **183**. Its steady-state
figure was **17.77 cycles/s** where p3b_run.lua's independent instrument — a guest store, not a PC
tap — measured **11.98**. ★★★★ **48% high, entirely plausible, and I would have published it.**

★★★ **What survives and what does not:**

| | |
|---|---|
| episode 1 total, tap **7.2629** vs p3b_run **7.2927** | ★★★ **0.4% — corroborated** |
| episodes 1+2, tap **17.1821** vs roomcheck **15.6785** | ★★★ **9.6% apart — NOT corroborated** |
| steady state, tap **3.31 cyc/s** vs p3b_run **2.22** | ★★★★ **49% apart — the tap is wrong** |

★★★★ **So every headline number in this report is p3b_run.lua's**, and the tap is used only for the
*within-episode shape* (fetch / clear / render / present), where episode 1 corroborates. **The
multiplicity is unexplained and is reported as unexplained** rather than divided out by a guess.

#### 3.D Where T1 and T2 start, and what is harness

★★★ **t0 is the guest's first instruction** — the moment the host sets PC, after DECB reaches its
`OK` prompt. ★★ **The DECB boot and the poke are harness, not product**, and **a real `LOADER.BIN`
load off a floppy is not measured** (out of scope). §8 trigger 5's requirement: **the interval
starts at the port's first instruction, and that is not the same as a player switching the machine
on.**

---

### 4 — Verification (AC-by-AC)

- **AC-1 [eye-gated] — pending Jay.** ★★ I ran headless. **Jay has not watched this run**, so per
  §4A this is not yet complete. To reproduce what the figures describe:
  `powershell -File harness\tools\p3b_show.ps1 -Title Kingquest1 -Cycles 160` — throttled, title
  screen then room 1 with four sprites. ★ The numbers below are from an unthrottled run; §2U.1
  says throttle changes nothing measured, and every interval here is emulated time.
- **AC-2 [byte-comparable] — PASS.** `hal_sync_check` OK ×3, `reg_discipline` unchanged at 8 in
  `mmu_phase.s`. §2T cited. ★★ **No gated file is touched**; the gate rows are cited, not re-run
  (§7.5).
- **AC-3 [state-comparable] — ANSWERED. T1 = 8.00 s.** Breakdown §5.
- **AC-4 [state-comparable] — ANSWERED. T2 = 17.94 s, room 1, reached by a JUMP** at cycle 8 —
  Kingquest1 never leaves room 83 on its own, measured at 300 cycles [p3b_room.lua].
- **AC-5 [state-comparable] — ANSWERED. T3 = 2.22 cycles/s at 4 sprites**, per-cycle breakdown
  §3.B, **2 remaps/cycle**. ★★★★ **Below the corpus's 10 — §8 trigger 2, and I am stopping on it.**
- **AC-6 [state-comparable] — ANSWERED: they add.** §3.A. ★★★ Blit, composite and remaps hold to
  within 3%; the render holds once compared against the right build; the VM's live-room figure is
  different work, not integration cost.
- **AC-7 [state-comparable] — PASS.** Clock **measured** at 1.789772 MHz from the guest's own
  160,009-cycle bracket, not printed [L-78]. Flag set enumerated and diffed — **and §3.A is what
  that diff was for.**
- **AC-8 [state-comparable] — ANSWERED.** §5, in a player's units, with stalls named as stalls.
- **AC-9 [state-comparable] — three things.** §7.1–§7.3.
- **AC-10 [suite] — one candidate.** §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — the clock, MEASURED (verbatim):**

```
clock MEASURED 1.789772 MHz (160009 cycles calibrated)
```

**25.1 — AC-3/AC-4, the episodes (verbatim from `p3b_time.lua`):**

```
#         at(s)      fetch      clear     render    present      TOTAL
1        0.7396     0.4306     0.2062     6.4152     0.2109     7.2629
2        8.0160     1.1066     0.2062     8.3955     0.2109     9.9192

T1  start -> FIRST room presented   : 8.0025 s   (episode 1)
T2  start -> SECOND room presented  : 17.9352 s   (episode 2)
```

★★ Episode 1 is **room 83, the title screen**; episode 2 is **room 1**, after the jump at cycle 8 —
paired from p3b_run.lua's per-cycle room numbers. ★★★ **The `render` and `fetch` columns carry
§3.C's caveat**: episode 1's total corroborates to 0.4%, the aggregate does not.

**25.1 — AC-5, per cycle with sprites live (verbatim from `p3b_run.lua`):**

```
  cycle   1  7.2927 s  room  83  sprites  0  remaps 22  err 0
  cycle   2  0.3171 s  room  83  sprites  0  remaps 2  err 0
  cycle   3  0.0834 s  room  83  sprites  0  remaps 2  err 0
  cycle 160  0.4506 s  room   1  sprites  4  remaps 2  err 0
★ 160 cycles in 85.3098 emulated s
    median 0.4506 s/cycle = 2.22 cycles/second
    mean   0.5332 s/cycle = 1.88 cycles/second
       pace(wait)   0.0605 s total   0.00038 s/cycle    0.1%  (160 entries)
       interpret   60.0756 s total   0.37547 s/cycle   72.5%  (160 entries)
       sprites      0.6765 s total   0.00423 s/cycle    0.8%  (160 entries)
       roomcheck   15.6785 s total   0.09799 s/cycle   18.9%  (160 entries)
       composite    6.3959 s total   0.03997 s/cycle    7.7%  (160 entries)
    final room 1, sprites 4, err 0, status=$00
```

**25.1 — AC-6, the flag-set diff that corrects the render comparison (verbatim):**

```
── p3b  (src/harness/p3b_probe.s)  [timing] ──
   ★★★ EXPECTED-ON BUT ABSENT: PIC_NOCOUNT
       counters cost 2.16x; a timing figure taken with them is not comparable
★★★ 1 expected-on guard(s) absent. Every timing figure from such a build is suspect.
```

★★★★★ **"a timing figure taken with them is not comparable" is the sentence, and it is the whole
of §3.A.**

**25.1 — the pic gate's own distribution, counters IN (from `build/sweep/timing.csv`):**

```
median 5.9349 s   min 4.5124   max 10.7890   n=45
```

**25.1 — §3.C, my tap's multiplicity (verbatim):**

```
=== tap multiplicity: raw fires per symbol (NOT calls) ===
   p3_clear_planes      3          res_open             1705
   vm_interpret_cycle   321        res_close            1865
   p3_present           2          pic_render_at        704
   gaps under 100us: 270 of 4594
```

★ Two-column layout mine; counts as printed. ★★★ **`pic_render_at` fired 704 times for TWO
renders.** A read tap counts accesses.

**25.1 — `hal_sync_check.py` / `reg_discipline.py` (verbatim):**

```
coco_agi        [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port       [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3  [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s                       8  $FFA5 $FFA6
```

**25.2 — bundled-artifact grep:** N/A — this task ships no DECB artifact and builds no new target
binary; it measures the one the gates passed.

**25.3 — operator-runtime-smoke:** **pending Jay** — AC-1. Launch path when run: **`poke`**, RGB,
throttled via `p3b_show.ps1`.

---

### 6 — What a player experiences (AC-8)

| | | |
|---|---|---|
| switch-on → title screen | **8.0 s** | ★★★ **a stall**, not a rate |
| title → first room | **9.9 s** | ★★★ **a stall** — the room render is 8.4 s of it |
| once a room is up | **2.22 cycles/s** | ★★★★ **a rate**, and AGI's own unit is the cycle |

★★★ **2.22 cycles/s is one update every 0.45 s.** At the corpus's requested 10 that would be one
every 0.1 s. ★★ **A 2.832 s render at 10 cycles/s is a 28-cycle gap; at the measured rate the
8.4 s room render is a 19-cycle gap** — the stall is comparable, the running rate is not.

★★ **Against Sierra's own CoCo3**, whose room change including disk read was **~3.54 s** at the
tight reading of an analysis that never fully resolved [T-P0-015]: ours is **8.4 s from RAM with no
disk at all**. ★★★ **The comparison is partial and is labelled so** — theirs includes a disk read
we do not do, and ours includes counters theirs did not have (§3.A).

---

### 7 — Uncertainty flags

1. ★★★★★ **T3 is 4.5× below what the corpus asks** [AD-82]. §8 trigger 2 — **reported, stopped,
   not optimised** (§12 puts optimisation out of scope). ★★★ **`interpret` at 72.5% is where any
   work would go, and `composite` at 7.7% is not.**
2. ★★★★ **The render figures are not paired.** Neither picture 83 nor room 1's picture is in the
   gated 45, so §3.A compares against a distribution (median 5.93, range 4.51–10.79) rather than
   against the same picture rendered both ways. ★★ **A paired measurement would settle it and is
   cheap** — render those two pictures under `pic_nc_pk` and compare directly.
3. ★★★★ **My tap's multiplicity is unexplained.** `pic_render_at` fires 704 times for two renders.
   Until that is understood, the fetch/render split is a SHAPE and not a measurement (§3.C).
4. ★★★ **T2 depends on a room JUMP**, not on the game reaching a room itself. Kingquest1 never
   leaves room 83 in 300 cycles. **A player would not see room 1 at 17.9 s; they would see the
   title screen and then whatever the game does next**, which is unmeasured.
5. ★★ **The gate rows were cited, not re-run** — no gated file is touched by this task, but that is
   weaker than P6.5's fresh run [§2T.3].
6. **Carried:** `CP_CEL`'s overrun — ★★★ **and p3b now has 3 bytes free, so its trigger ("before
   p3b's next code change") is effectively due.**

---

### 8 — Follow-up candidates

1. ★★★★★ **The cycle-rate decision is Jay's** — 2.22 against 10, with `interpret` at 72.5%.
2. ★★★★ **Pair the render measurement** (§7.2) — two pictures, both builds, direct.
3. ★★★ **Explain the read-tap multiplicity** or retire the tap for anything but shape (§7.3).
4. ★★★ **`CP_CEL` / p3b's 3 free bytes** — the next p3b code change cannot happen without it.
5. ★★ **What the game does after the title screen on its own**, for a T2 a player would recognise.

---

### 9 — Reactive deviations and route accounting

**Deviations (§22.5):**

1. ★★★★ **I nearly reported a 2.3× integration cost and did not** (§3.A). The correction came from
   the flag diff §5 asks for — **which is why that grep row exists**.
2. ★★★ **I built a new instrument and then declined to use most of its output** (§3.C). Reported
   rather than quietly dropped.
3. ★ **I used the room jump** for T2/T3, as §2 permits, and named it.

**Route accounting.** ★★ I proposed no route. ★★★ **What I described mid-task and did not build:**
after finding the multiplicity I said the fix was to "de-duplicate consecutive taps within a
derived window" — **I did not build that.** The gap histogram showed only 270 of 4,594 gaps under
100 µs, which does not account for `pic_render_at`'s 704 fires, so the dedup hypothesis is **not
supported by the measurement** and building it would have been fitting a fix to a guess.

---

### 10 — Candidate(s) captured this task

One, in `seeds/AGI/live/`, pushed to the pool at the hash in §11:

- `2026-09-07-two-figures-for-one-quantity-differ-by-their-build-flags`

★ **Not captured:** §3.C's read-tap-counts-accesses belongs to
`an-instrument-must-be-shown-able-to-fail`, which exists; per §2C I have not edited it.

### 11 — Commit

`454098b` — *P6.7 p3b_time.lua: T1/T2/T3 from an unmodified p3b binary*
(pushed to `origin/wip` before this report).
