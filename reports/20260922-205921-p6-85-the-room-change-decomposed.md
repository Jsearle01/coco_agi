## Form B Report — P6.85 — The room change decomposed: it was the render, and the render was counting
**Class:** measurement, with §1.3's bounded licence exercised.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-22 (HEAD `45188c5`, wip). `git status` clean apart from an untracked
`coco_agi.code-workspace` that predates this task.

### 1 — Summary
★★★★★ **§1.1's premise is refuted: there were never seven unaccounted seconds.** The decomposition
reconciles to **95.3%** of the 9.5456 s cycle, and **the render is 8.2797 s of it — 91.0%.** The
`~2.8 s` figure beside `p3_pic_draw` is `pic_variants.sh`'s **`nocount_packed` median** — *a
different probe, flat-mapped, with counters off* — quoted as if it described this build.

★★★★★ **Profiling that one cycle named the cause in one line: `fc_count`, 29.4%, the largest single
routine in the room change.** It is a pure counter in the flood fill's innermost loops, guarded by
`PIC_NOCOUNT`, and **p3b had never defined the flag** — while `pic_fill.s`'s own comment has said
since it was written that *"timings come from `-DPIC_NOCOUNT`, where this vanishes entirely."*

★★★★ **All five criteria held, so it was taken — one `equ`.** **Room change 9.5456 → 6.1579 s
(−3.39 s, −35.5%)**; the render inside it **8.2797 → 4.8957 s (−40.9%)**; **the steady cycle is
unchanged to the digit** (mean 0.2917, median 0.2837 both arms); **pixels identical.**

★★★ **Two things fell out.** All nine arms shrank **142 B**, which gave region A back enough
headroom that **`-IfRec` assembles and runs again** — the instrument P6.83 lost — and logic 1 reads
**0 of 256** on it. And §1.2's two named candidates are both small: the clear is 2.6%, the present
2.2%.

### 2 — Files modified
- `src/harness/p3b_probe.s` — `PIC_NOCOUNT` defined (the fix, one `equ`); `-DP3B_PICSTEPS`'s
  markers 13..22; `-DP3B_PIC_COUNT` (the before arm); §9's three doc corrections.
- `harness/tools/p3b_run.lua` — the sub-step accumulator, grouped per room change and reconciled
  against the measured cycle.
- `harness/tools/p3b_show.ps1` — `-PicSteps`, `-PicCount`.
- `harness/tools/p3b_arms_check.ps1` — nine arms re-baselined (−142 B each).

Explicit-path staging only.

### 3 — Reasoning

#### §3(2) — every step `draw.pic` and `show.pic` perform ★★★★★
`p3_pic_draw`: `res_open(PICTURE)` → `ph_blk_fb = SHADOW` → `phase_draw_enter` →
**`p3_clear_planes`** → **`pic_render_at`** → **`p3_pri_shadow`** (cel arm) → `res_close` →
`p3_enter_vm_phase`. `p3_pic_show`: **`p3_present`** → `p3_shown = 1` → `p3_enter_vm_phase`.
★★★ **Five steps worth timing, and markers 13..22 bracket exactly those five.**

#### §3(3) — timing WITHIN a cycle ★★★★
The stage timer already write-taps `P3_PHASE` and stamps exact emulated time at the store,
odd = enter / even = leave. ★★★★ **But it keeps ONE open slot, and these steps NEST inside
`roomcheck` (7/8)** — a nested pair would close the outer stage at the inner marker and report a
stage that never returned. ★★ So the sub-steps get their own accumulator and `return` before the
stage machinery sees them. Two tables rather than a stack, because the nesting is exactly one deep.

#### §3(4) — what `p3_clear_planes` writes ★★★
Both planes: the visual half writes `$FFFF` over 26,880 B, the priority half its own. ★★★★
**Whether it is required or defensive was NOT settled here** — `pic_render_at` is the only reader of
what it leaves, and answering it properly is an oracle question (§6's second trigger). ★★ It did not
need settling, because the measurement made it moot: **the clear is 2.6% of the room change.**

#### §4A — the decomposition ★★★★★

**Castle room change — host cycle 9, measured 9.5456 s** (`-DP3B_PICSTEPS`, 40-cycle run,
`P3B_ROOM=1`):

| step | seconds | % of steps |
|---|---|---|
| **pic render** | **8.2797** | **91.0%** |
| pic clear | 0.2322 | 2.6% |
| present | 0.1967 | 2.2% |
| pri shadow | 0.1749 | 1.9% |
| pic fetch | 0.0204 | 0.2% |
| **STEPS SUM** | **9.1005** | |
| *unattributed* | *0.4451* | *4.7% of the cycle* |

★★★★★ **95.3% accounted.** The 0.4451 s residue is the rest of the cycle — the logic that issued
`draw.pic`, the VM around it, `res_cache_stash` — and `interpret` claims 4.7% of the cycle in the
profile, which is the same number arriving twice.

★★★ **The title screen's render is the same shape**: host cycle 1, 7.6599 s, steps 6.9873 s
(91.2%), render 6.3723 s. **A 40-cycle run draws TWO pictures**, which is why the first version of
this instrument was wrong (§6).

#### §4B — is each step NEEDED ★★★★
★★★★★ **The question the dispatch expected to be decisive is not, and the measurement says so:**
1. **`p3_clear_planes` — 0.2322 s, 2.6%.** Not a large cost. **Left alone**; its requirement is
   unanswered and recorded beside it.
2. **The priority shadow — 0.1749 s, 1.9%.** Not a large cost.
3. **`p3_present` — 0.1967 s, 2.2%**, once per room, unavoidable while the shadow is the render
   target. ★★ **Now unavoidable with a number beside it**, which is what §4B(3) asked for.

★★★★★ **The large win was not a step that should not run; it was work inside the step that should
not have been assembled.**

#### AC-2 — the profile over cycle 9 alone ★★★★★
`# window cycles 9-10  hz 997  samples 9517  span 9.5446 s` — **9,517 samples in one cycle**, more
than the whole steady window gets in forty. `PCs in remapped slots 3-6: 0 samples`.

```
roomcheck 93.3%  |  interpret 4.7%  |  composite 1.9%
 1 fc_count      pic_fill.s   29.4%      6 plane_vis        3.1%
 2 flood_fill    pic_fill.s   25.2%      7 ff_win_row       3.0%
 3 put_pixel     pic_core.s    6.7%      8 plane_pri        2.7%
 4 draw_line     pic_draw.s    4.8%      9 p3_clear_planes  2.4%
 5 p3_present    p3b_probe.s   4.1%     10 p3_pri_shadow    1.8%
```
★★★★ **The fill is 59.4%** (`fc_count` + `flood_fill` + `ff_win_row` + `fill_check`), and **29.4%
of the whole cycle is a counter.**

#### §4C — the resource share of a room change ★★★
**`pic fetch` is 0.0204 s — 0.2%.** In the profile, `res_cache_stash` appears at 6% *of the
interpret stage*, itself 4.7% of the cycle. ★★★ **A room change is where the cache still misses,
and it is not where the time goes**: the fetch and the re-binds together are under 1% of it. ★★
P6.83's 4/0/0 steady state is not disturbed by this, and the room change never needed it to be.

#### §4D / §1.3 — the five criteria, one by one ★★★★★

The candidate: **`fc_count` is instrumentation, assembled into a timing build.**
`ldd CNT_CHK+2 / addd #1 / std CNT_CHK+2 / …`, called from `ff_left`, `ff_right` and both seed
tests — the fill's innermost loops. **Every `ifndef PIC_NOCOUNT` block in `pic_fill.s` is an
increment with no logic in it** (grepped, all twelve).

| | criterion | verdict |
|---|---|---|
| 1 | **One cause** | ★ **MET** — one routine, 29.4%, the largest in the cycle. |
| 2 | **Local, no new mechanism** | ★ **MET** — one `equ`. `PIC_NOCOUNT` already exists, is used by `pic_variants.sh`, and is the documented way. |
| 3 | **No observable behaviour moves** | ★ **MET** — the counters are write-only here: p3b declares the `CNT_*` addresses because `pic_draw.s`/`pic_core.s` increment two of them unguarded, and **never loads one**; **no `.lua`, `.ps1` or `.py` reads p3b's copies**. `co_WRITTEN 11360`, `CP_BLITS 128` identical; five byte gates unmoved. |
| 4 | **A fault arm that goes red** | ★ **MET IN THE FORM AVAILABLE, and stated honestly.** The change removes instrumentation, so **there is no logic to break and no correctness fault to inject.** What exists is the attribution pairing: `-DP3B_PIC_COUNT` restores exactly the removed work and differs in **nothing but time** (render 8.2797 vs 4.8957, same pixels, same steady cycle) — plus a §2W check that the flag took: **`fc_count` is absent from the profile and known routines fall 374 → 373.** |
| 5 | **No ruling** | ★ **MET** — not the map, not the arena, not a gate's meaning, not an oracle semantic. **The renderer gate is `pic_probe`, a different probe with its own flags, and is untouched.** |

★★★★ **Five of five, so the fix was taken**, measured before and after in the same binary.

#### §2S — sibling refs
POP3_port `104b197` (wip), karateka_coco3 `29f8f0a` (wip); both dirty with pre-existing work not
mine. **No `SHARED` file touched**; `hal_sync_check.py` OK. lwasm 4.24 unchanged.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement]** §4A's table. ★★★★★ **Reconciles to 95.3%; the gap is named and is the
  cycle's own VM work.**
- **AC-2 [measurement]** The per-routine profile over cycle 9 alone, above.
- **AC-3 [measurement]** §4B's three answers. ★★★ **The clear's requirement is NOT settled and is
  recorded as open beside the routine** — it did not need settling, at 2.6%.
- **AC-4 [measurement]** §4C. **The fetch is 0.2% of the room change.**
- **AC-5 [judgement]** §4D's table — **five of five, fix taken.**
- **AC-6 [measurement] Room change before and after, and the steady cycle unchanged.**

  | window | before | after |
  |---|---|---|
  | **room change (host cycle 9)** | **9.5456 s** | **6.1579 s** (**−35.5%**) |
  | the render inside it | 8.2797 s | **4.8957 s** (**−40.9%**) |
  | title render (host cycle 1) | 7.6599 s | **4.6727 s** |
  | `roomcheck` total, 120 cycles | 8.9076 s | **5.5236 s** |
  | **steady cycle 11–120, mean** | 0.2917 | **0.2917** |
  | **steady cycle 11–120, median** | 0.2837 | **0.2837** |

  ★★★★★ **The steady cycle is unchanged to four decimals**, which is what §AC-6 requires — and is
  expected, because the fill runs once a room. ★★★ The same-binary `-PicCount` comparison (both
  arms with `-Count`, 40 cycles) gives the same steady sum **10.0468 s on both**.

- **AC-7 [state-comparable] Pixels identical.** `co_WRITTEN 11360`, `CP_BLITS 128`, `vc_err 0`,
  `last cel 13x4` on both arms. ★★★ **And the restored `-IfRec` arm reads logic 1 at 0 of 256.**

- **AC-8 [byte-comparable · gate] `src/` changed, all RUN.** `pic` **45 PASS / 0 FAIL (of 45)** —
  it owns the renderer and is the gate this change could most plausibly have moved; `cel`
  **9,193/9,193**, `comp` **124/124**, `res` **1,264/1,264**, `vm` **9/9 (0 divergent of 600
  each)**. ★★★ **All five gate probes byte-identical.**

- **AC-9 [state-comparable · fault injection]** §4D criterion 4, stated as the honest form:
  the attribution arm plus the §2W reachability check. **No correctness fault exists to inject.**

- **AC-10 [suite]** `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green (`all green`);
  mojibake clean over every tracked text file.

- **AC-11 [eye gate — Jay]** Live, RGB, 300 cycles, run twice at Jay's request. Expectations stated
  in the ask, including how much to expect. Jay:
  1. *"seems shorter"* — ★★★ **consistent with 9.55 → 6.16 s.**
  2. *"yes"* — ★★★★ the room looks the same, as AC-7 measures.
  3. *"no"* — ★★★ nothing else slower, as AC-6's unchanged steady cycle predicts.
  ★★ The wall clock of the run itself fell 36 s → 27 s → 19 s across the session; host variance is
  in that, so it is offered as direction and not as a measurement.

- **AC-12 [manifest]** Nine arms re-baselined, **−142 B each**. ★★ The uniform delta is the check
  that the change is the one intended.

- **AC-13** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
=== AC-2 SUMMARY === all nine titles PASS (vm, 600 cycles each, 0 divergent)

§4A  room changes, decomposed (P3_CYCLE at the step's close)
     P3_CYCLE 0 -- steps total 6.9873 s        [the title screen's picture]
        pic render 6.3723 (91.2%)  clear 0.2322  present 0.1966  shadow 0.1750  fetch 0.0113
        ★★ host cycle 1 measured 7.6599 s -> steps are 91.2%, unattributed 0.6725 s
     P3_CYCLE 8 -- steps total 9.1005 s        [the castle]
        pic render 8.2797 (91.0%)  clear 0.2322  present 0.1967  shadow 0.1749  fetch 0.0204
        ★★ host cycle 9 measured 9.5456 s -> steps are 95.3%, unattributed 0.4451 s

AC-2 # window cycles 9-10  hz 997  samples 9517  span 9.5446 s
     roomcheck 93.3% | interpret 4.7% | composite 1.9%
     fc_count 29.4% | flood_fill 25.2% | put_pixel 6.7% | draw_line 4.8% | p3_present 4.1%
     PCs in remapped slots 3-6: 0 samples      routine entries known 374

AC-6 after the fix, same window:
     # window cycles 9-10  samples 6139  span 6.1565 s      routine entries known 373
     flood_fill 33.4% | put_pixel 8.8% | draw_line 7.3% | p3_present 6.3%
     ★ fc_count ABSENT from the profile
     [cyc] 1 4.6727   [cyc] 9 6.1579        (were 7.6599 and 9.5456)
     steady 11-120: mean 0.2917  median 0.2837            (unchanged)
     roomcheck 5.5236 s total over 120 cycles             (was 8.9076)

AC-7 co_WRITTEN 11360 | CP_BLITS 128 | vc_err 0   both arms
     -IfRec restored: logic 1 differing offsets: 0 of 256 compared
[reg-discipline] 6 register access(es) in 1 file(s) over 4 register(s).
[hal-sync] OK      CHECK OK: vm_tables.s matches optable.py.
★ every non-p3b probe byte-identical   ★ all 9 arms byte-identical   -SelfTest: 1 ARM(S) MOVED
```

**25.2 bundled-artifact grep:** N/A — nine arms and five probes pinned by hash.

**25.3 operator-runtime-smoke:** **PASSED — Jay, live, RGB, `-Combined`, 300 cycles (twice).**
AC-11.

### 6 — Reactive deviations and route accounting

1. ★★★★★ **The decomposition instrument was wrong on its first run and the arithmetic said so
   loudly.** It totalled each step across the whole run and kept one cycle number per step — but
   **a 40-cycle run draws TWO pictures**, so it mixed two room changes and reported
   `steps account for 16.0878 s -- unattributed -16.0211 s (-24000.6%)`. ★★★★ **A −24000% is the
   instrument failing usefully**; a quieter design would have reported a plausible wrong split.
   Rebuilt to record **per occurrence**, grouped by the cycle each ran in, and it then reconciled
   to 95.3%. [§2W.3: a diagnostic that cannot be wrong does not measure.]
2. ★★★ **Both candidate cycle numbers are printed at the reconciliation** (`c` and `c+1`), because
   `P3_CYCLE` is the guest's counter and the per-cycle array is keyed by the host's released-cycle
   count. **They differ by one**, and asserting either would have been a diagnostic naming a side
   it does not have [§2W.3 again].
3. ★★ **`-DP3B_PIC_COUNT` was added and the dispatch did not ask for it** — §1.3 requires before
   and after in the same task, and a same-binary before arm is the only way to do that without the
   measurement carrying a different build's bytes.

★★★★ **No §2J.5 violation this task.** Last task's re-baseline used a PowerShell round-trip and put
a BOM and 71 double-encoded runs into `p3b_arms_check.ps1`; **this task's nine rows were edited with
`Edit`** and `fix_mojibake --check` is clean on every touched file.

**ROUTE ACCOUNTING.** §4D evaluated one candidate and took it. **NOT taken, each with the criterion
it fails**: removing or shrinking `p3_clear_planes` — fails (5), whether the renderer requires a
cleared plane is an oracle question and §6's second trigger; `p3_present` — fails (1), it is 2.2%
and unavoidable by the shadow design; the flood fill's algorithm (`flood_fill` now 33.4%) — fails
(2), that is the work and changing it is a mechanism.

### 7 — Uncertainty flags

1. ★★★★★ **The `~2.8 s` was a THIRD instance of one error class, not a stale number.** It is
   `pic_variants.sh`'s `nocount_packed` median: **pic_probe, flat-mapped, counters off** — three
   differences from the build it labelled. ★★★ With design spec §7.1's `0.039 s/cycle`
   (comp_probe's) and P6.84's means over an undeclared window, **that is three figures correct
   about the program they were measured on and carried forward as if they described another.**
2. ★★★★ **A room change is still 6.16 s**, and the render is still 4.90 s of it. **The fill is
   33.4% and `put_pixel` 8.8%** — that is real work and the next question, not a defect.
3. ★★★★ **Whether `p3_clear_planes` is required is unanswered.** Recorded beside the routine. At
   2.6% it is not worth a ruling on its own, but it is the kind of question that gets cheaper to
   answer once and expensive to keep re-asking.
4. ★★★ **The unattributed 0.4451 s (4.7%) is attributed by inference, not by a marker** — the
   profile's `interpret` share for that cycle is 4.7%, which agrees, but no marker brackets it.
5. ★★★ **Two renders, one title and one castle, in one room.** The 8.28 s is KQ1 room 1. **A picture
   with more fills costs more**, and the fill is now 33.4% of what remains.
6. ★★ **Criterion 4 has no correctness fault arm** and the report says so rather than inventing
   one. What backs the change is the attribution pairing plus five unmoved byte gates.
7. ★★ **The eye gate's wall-clock fall (36 → 27 → 19 s) is direction, not measurement** — host
   variance is in it.

### 8 — Follow-up candidates

1. ★★★★★ **The flood fill.** `flood_fill` 33.4% + `put_pixel` 8.8% + `draw_line` 7.3% of a 6.16 s
   room change. ★★★ **It is now the largest thing in the program**, and unlike the counter it is
   real work — so it wants the other kind of task: an algorithm question, with a ruling.
2. ★★★★ **Is `p3_clear_planes` required?** §7(3). One oracle question, 2.6%, and it closes an open
   note rather than leaving it for the third reader.
3. ★★★★ **Audit for the third-instance error class** [§7(1)]: **every performance figure in the
   source and the design spec, against the probe and the flags it was measured on.**
   `pic_variants.sh` builds seven variants; the figures quoted elsewhere name none of them.
   ★★★ Design spec §7.1's `0.039 s/cycle` is **eight tasks flagged**.
4. ★★★ **Region A recovered 142 B and `-IfRec` works again** — but the map ruling is still open
   [P6.84 §1.2(2)], and the next 142 B of code re-closes it.
5. ★★★ **The steady cycle's 59% drawing path** — the other speed task, untouched here.
6. ★★ **Real-time pacing** (needed under 100 ms); **typing cadence**; **the title page** items;
   **`checkPriority`/`checkCollision`**; **`MAP_PRI_BANDS`** at `memmap.inc:310` — **the
   thirty-first task.**

### 9 — User interaction during task
The AC-11 eye gate, offered after the fix was taken, with expectations for all three questions.
Jay asked to see it again and it was re-run unchanged; a back-to-back against the `-PicCount` before
arm was offered and not needed. Jay's three answers are quoted in AC-11.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-22-instrumentation-assembled-into-the-timing-build.md`

### 11 — Commit
`85ba03d`  (pushed to origin/wip before this report)
Pool candidate `0d6261a` (methodology-candidate-pool, main).
