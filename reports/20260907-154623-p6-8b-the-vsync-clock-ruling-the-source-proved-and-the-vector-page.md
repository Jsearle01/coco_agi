## Form B Report — P6.8b — Jay's VSYNC clock ruling (AD-138): the source proved, the vector page fixed, the arm gated
**Class:** build.  wip.

★★★★★ **This is the continuation of T-P0-064, not a new task.** Jay's ruling note says *"This lands
in T-P0-064's remaining six ACs; it is not a separate task."* **P6.8 was written before the ruling
arrived and reports AC-1/3/5/6/7/8 as NOT DONE with follow-up 1 = "decide the clock model".** The
ruling answered that follow-up, and the work below is what implementing it produced. ★★★
**P6.8's six ACs are STILL NOT DONE and this report does not claim them** — it exists so the
Orchestrator does not read P6.8's open question as still open, and does not read commit `0366844`
as unexplained.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-07 15:46:23 (HEAD `5e7580e`, wip; the work reported here is commit **`0366844`**).
`git status` clean apart from untracked `coco_agi.code-workspace`, an editor file, not staged.

---

### 1 — Summary

★★★★★ **The clock SOURCE is proved and Jay's ruling is implementable: 300 of 300 VBLs at 59.9227
Hz, handler entered 300 times, CC.I 0.0%.** The GIME setup, `HAL_time_init`, the `$010C` vector and
`hal_vbl_handler` are all correct exactly as they stand in the shared HAL — **nothing shared
changed, so §2M does not bite.** The +0.13% drift Jay accepted is measured rather than assumed: a
60-tick second reads 5.0000 s against 5.0064 s true.

★★★★★ **A latent defect was found and fixed for everyone.** `VP_VOCAB_END` was `$FF00` — right
about the I/O page, wrong about the 256 bytes below it. `HAL_sys_init` sets INIT0 bit 3 (MC3), so
`$FE00-$FEFF` is the interrupt vector page, and **the vocabulary self-test has been writing a
walking pattern across the vectors on every VM run since T-P0-060.** Silent for exactly as long as
nothing enabled an interrupt. Now ends at `$FE00`. **Nine-title gate 9/9 PASS.**

★★★ **The ruling is NOT fully implemented and the clock is behind `-DVM_VBLCLOCK`.** With the clock
on, the probe still runs away into `$0400-$05FF` before its first park, both self-tests reporting
clean. Cause not found. **The default build is HEAD's behaviour and the gate is green.**

★★★★ **Five measurements were spent attributing the symptom to the wrong thing**, and the
correction is §3.2. The instruments that eventually answered it are now in the tree.

---

### 2 — Files modified (commit `0366844`)

- `src/harness/vbl_probe.s` — **new, 71 lines.** vm_probe's prologue plus a bare spin loop: the
  positive control for the clock source.
- `src/harness/vm_probe.s` — `VP_VOCAB_END` `$FF00` → `$FE00`; `HAL_time_init` + `andcc #$EF` added
  behind `ifdef VM_VBLCLOCK`, placed after the destructive self-tests.
- `harness/tools/vbl_rate.lua` — **new.** Measures the VBL rate rather than assuming 60 Hz.
- `harness/tools/mask_where.lua` — **new.** Samples the PC and histograms it; prints the trajectory.
- `harness/tools/vm_sweep.lua` — stall detectors in **both** the boot and run states.
- `harness/tools/vm_run.ps1` — the `VM_VBLCLOCK` arm.

**No shared HAL file changed. No `src/engine/` file changed.**

---

### 3 — Reasoning

#### 3.1 The ruling's four requirements, against what was delivered

| ruling | status |
|---|---|
| `VAR_SECONDS` et al. advance from vertical sync | ★★★ **source proved; not yet driving the vars** |
| count VSYNCs, every 60 a second | ★★ **not reached** — the arm crashes before the first park |
| the interrupt stays enabled through the message loop | ★★ **not reached** |
| both legs change, or neither | ★★★★★ **NEITHER changed. The Python reference is untouched, and that is correct** — changing our 6809 leg while the arm cannot run would have left two legs disagreeing for a reason that is a bug rather than the modelling difference §3 of the note is about. |

★★★★ **§4 of the note asks whether the oracle's millisecond granularity is observable in
`VAR_SECONDS` against VSYNC's 60ths. That check is NOT done** — it needs a working arm to be worth
anything.

#### 3.2 ★★★★★ The correction: five measurements attributed the symptom to the wrong thing

`vbl_rate.lua` first reported **7.79 Hz against an expected 59.92 — 13% of interrupts delivered —
and a CC sample saying the CPU had interrupts masked 86.7% of the time.** Those two numbers agree
arithmetically (100 − 86.7 ≈ 13), which made the reading feel confirmed. **The reading was "the
interpreter's hot path masks interrupts", and it was wrong.**

Four candidate maskers were chased through the source and **all four were innocent**:

| candidate | why not |
|---|---|
| every `orcc #$50` in the HAL | all `pshs cc` / `puls cc` bracketed, a few dozen cycles |
| `HAL_time_frame_count` (`time.s:170`) | masks for two loads, restores the caller's CC exactly |
| a DP collision at `$0010/$0011` | `setdp 0` everywhere; the `$0010` map hits are `equ` constants |
| S used as a data pointer | every `leas`/`subd ,s++` is stack discipline; `lds` only at init |

`build/vm_probe.bin` was also checked and was **41 s newer than its source**, so AD-90 did not apply.

★★★★★ **What settled it was adding ONE field to the instrument — the program counter.**

```
PC       hits   share  nearest preceding symbol
$8957     260  100.0%  KCOCO3_FB_A_BASE+2391      distinct masked PCs: 1
```

**One address with a 100% share is a park, not a workload. The guest had crashed** — and a crashed
guest and a masked guest produce the same rate. `$8957` sits inside `RES_ARENA` (`$6B00` + 21 KB),
which the arena self-test writes a walking pattern across.

★★★★ **The control is what located the bug.** Building HEAD's own probe and running it through the
same instrument: it takes the **identical** path to frame 46, then goes `vm_st_c → vm_st_ozero →
vp_wait` and parks, **71% of samples at the gate.** One run overturned four wrong attributions.

#### 3.3 The vector page

`HAL_sys_init` writes `$FF90 = $4C` and `HAL_time_init` writes `$6C` — **MC3 (bit 3) set in both,
so it has been set the whole time** [`time.s:61-62,98`]. With MC3 set, `$FE00-$FEFF` is the vector
page. `VP_VOCAB_END` was `$FF00`, so `vp_vt_wr` swept the vectors.

★★★★ **This is §2M.1's shape in the harness**: a defect latent in a tree that never exercises the
path, surfacing the moment a second client does. **The clock change did not cause it; it was the
first thing to READ what the self-test had been writing.** ★★ 7,680 bytes still clears the 6,828
the vocabulary window must hold, so nothing is lost by stopping lower.

#### 3.4 ★★★ Two corrections to statements made mid-task

1. **"86.7% masked" was reported to Jay as the blocker.** It was not a masking problem at all.
2. **"the harness didn't stage, so the crash is expected" was wrong.** Staging happens *after* the
   guest reaches its first park, so `mask_where.lua` was measuring that phase faithfully; the log
   line `guest reached its gate` never printed, which is the evidence.

#### 3.5 Authority tier

All of the above is **measurement of our own port** — dynamic observation, no oracle claim, so
§2.1's original-vs-normalisation distinction does not arise. The one hardware claim (MC3 maps the
vector page) is **cited from the shared HAL's own header comments**, `time.s:61-62`, which are
tier-5 (comments) — ★★ **`[no-ref: MC3 maps $FE00-$FEFF as the vector page — discharge against
docs/ground-truth/SockmasterGime.md]`**. **The FIX does not depend on it**: the fix is validated by
the 9/9 gate and by the crash disappearing, not by the mechanism story.

---

### 4 — Verification (AC-by-AC)

**T-P0-064's remaining six ACs — unchanged from P6.8:**

- **AC-1 [eye-gated] — NOT DONE.** Nothing reaches the screen.
- **AC-3 [byte-comparable] — NOT DONE.** No text renders. ★ The dispatch note says "AC-3's build now
  has a clock to honour"; there is no AC-3 build.
- **AC-5 [byte-comparable] — NOT DONE.**
- **AC-6 [state-comparable] — NOT DONE.**
- **AC-7 [byte-comparable] — NOT DONE.**
- **AC-8 [state-comparable] — NOT DONE.**

**The ruling's own work:**

- **R-1 [state-comparable] — the clock source works. PASS.** `vbl_probe.s`, 300/300 VBLs, 59.9227
  Hz, handler entered 300×, CC.I 0.0%. Drift measured at +0.13% (5.0000 vs 5.0064 s). — 25.1.
- **R-2 [byte-comparable] — nothing shared changed. PASS.** `hal_sync_check.py` OK in all three
  repos; `irq_vbl.s`, `time.s`, `sys.s`, `gfx.s` untouched.
- **R-3 [byte-comparable] — the vector-page fix is safe. PASS.** Nine-title gate **9/9
  byte-identical** on the default build. — 25.1.
- **R-4 [state-comparable] — both legs on VSYNC. NOT DONE**, and deliberately: the Python leg was
  not moved while the 6809 arm cannot run (§3.1).
- **R-5 [state-comparable] — the arm runs. FAIL, and gated.** With `-DVM_VBLCLOCK` the probe runs
  away into `$0400-$05FF` before its first park; 109 addresses, `arena_bad=$0000`,
  `vocab_bad=$0000`. Cause not found. **Default build is HEAD's behaviour.**
- **R-6 [byte-comparable] — the instruments can fail. PASS both directions.** The boot-state stall
  detector fired with an address list on the hung build and stays silent on the green one (§2W).

★★★★ **Why the arm is gated rather than shipped red.** Jay's ruling accepts the nine-title gate
going red while T3 recovers — **but that is a state-diff divergence from a changed clock model,
which is a finding.** A guest that crashes is not that, and shipping it as the accepted redness
would spend the ruling's budget on a bug.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — the clock source, `vbl_probe.s` spin arm (verbatim):**
```
poked 798 bytes, PC set (frame 28)
counter at t0 : 2   (emulated t=0.4992, MAME frame 30)
counter at t1 : 302   (emulated t=5.5056)

elapsed emulated : 5.0064 s
VBL ticks        : 300
measured rate    : 59.9227 Hz
MAME frames      : 300 in the same window = 59.9227 Hz
handler ENTERED  : 300 times = 59.9227 Hz
★ handler entries vs counter increments: 300 vs 300
CC.I set when sampled : 0 of 300 samples = 0.0% of the time MASKED

★ seconds implied by a 60-tick second : 5.0000  (true elapsed 5.0064)
```

**25.1 — the same instrument on the VM probe, the reading that was wrong (verbatim):**
```
elapsed emulated : 5.0064 s
VBL ticks        : 39
measured rate    : 7.7900 Hz
handler ENTERED  : 39 times = 7.7900 Hz
CC.I set when sampled : 260 of 300 samples = 86.7% of the time MASKED
```

**25.1 — `mask_where.lua`, the field that settled it (verbatim):**
```
PC         hits   share  nearest preceding symbol
$8957       260  100.0%  KCOCO3_FB_A_BASE+2391

distinct masked PCs: 1
```

**25.1 — the control, HEAD's own probe through the same instrument (verbatim):**
```
PC         hits   share  nearest preceding symbol
$07EB       107   35.7%  vp_wait+2
$07ED        70   23.3%  vp_wait+4
$07EC        36   12.0%  vp_wait+3
   46  $0756 I vp_vt_rd+10
   47  $1FCA I vm_st_c+5
   48  $1FE0 I vm_st_ozero+2
   53  $07ED I vp_wait+4
```

**25.1 — after the `$FE00` fix, the clock live in the VM probe (verbatim):**
```
elapsed emulated : 5.0064 s   VBL ticks 254   MAME frames 300
CC.I set : 46 of 300 samples (15.3%)
   46  $074E I vp_vt_rd+2        <- self-tests, masked
   47  $1FE4 - vm_st_ozero+1     <- clock live, CC.I CLEAR
   52  $07EF - vp_wait+1         <- parked at the gate, taking VBLs
```
★ The 46 masked frames are exactly the self-test phase; 254 ticks over the remaining frames is
59.92 Hz.

**25.1 — the gate, default build (verbatim):**
```
=== AC-2 SUMMARY ===
Kingquest1  PASS   Kingquest2  PASS   Kingquest3  PASS
SpaceQuest-1 PASS  SpaceQuest-2 PASS  PoliceQuest1 PASS
larry1 PASS        BlackCauldron PASS MixedUpMotherGoose PASS
```

**25.1 — `hal_sync_check.py`, all three repos (verbatim):**
```
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, EOL/guard/export-placement normalised)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, EOL/guard/export-placement normalised)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, EOL/guard/export-placement normalised)
```

**25.1 — the stall detector, shown able to fire (verbatim):**
```
★★★ GUEST NEVER REACHED ITS GATE -- VP_GO uncleared for 1201 frames.
    VP_GO=1 VP_STATUS=255 arena_bad=$0000 vocab_bad=$0000
    $0562     27   2.4%  ?
    distinct PCs: 109
```
★ And silent on the green build — both directions, §2W.

**25.2 bundled-artifact grep:** N/A — no bundled artifact; nothing shipped, no DECB image built.

**25.3 operator-runtime-smoke:** `N/A — no visual surface. The clock has no screen presence and
AC-1's eye gate is NOT DONE (§4).`

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **The clock was gated behind `-DVM_VBLCLOCK` rather than shipped.** §22.5 deviation from
   the ruling's plain reading. Reasoned in §4; the gate is green as a result.
2. ★★★ **The Python leg was deliberately not moved** (§3.1), against the note's "both legs change
   or neither" — **which is why: neither changed.** That satisfies the rule's letter and its
   purpose.
3. ★★ **Two instruments and one control build were written that no dispatch asked for.** They are
   the reason the vector-page defect was found.

**Route accounting.** I proposed no route. ★★★★ **What I DESCRIBED mid-task and did not deliver:
I told Jay "86.7% masked" was the blocker and that the harness's missing staging explained the
crash. Both were wrong and both are corrected in §3.4.** Neither claim reached an artifact, but
both reached Jay, which is exactly the case §7's route-accounting note exists for.

---

### 7 — Uncertainty flags

1. ★★★★★ **The `-DVM_VBLCLOCK` runaway is not understood.** `$0400-$05FF` is the DECB text buffer;
   109 addresses; both self-tests clean. **Everything I have eliminated is listed in §3.2, and the
   list is not the answer.**
2. ★★★ **`VP_VOCAB_END = $FE00` is validated by the 9/9 gate and by the crash disappearing, not by
   a ground-truth reading of the GIME.** The MC3 mechanism carries a `no-ref` (§3.5).
3. ★★ **The vector page may have been corrupted on every VM run since T-P0-060 without consequence,
   and I have not audited whether any OTHER probe sweeps `$FE00-$FEFF`.** `p3b_probe.s` places the
   parser at `$E000` and is the obvious one to check.
4. ★★ **`vbl_rate.lua`'s CC.I sampler is phase-locked to the frame boundary.** It read 0.0% on the
   spin arm, which is the evidence it is not structurally biased — but that is one negative
   control, not a characterisation.

---

### 8 — Follow-up candidates

1. ★★★★★ **Find the `-DVM_VBLCLOCK` runaway.** The instruments are in the tree; the next step is a
   PC histogram from the boot-state detector on the crashing arm with symbols resolved.
2. ★★★★ **Then finish the ruling**: move both legs, and answer §4's granularity question
   (milliseconds vs 60ths in `VAR_SECONDS`).
3. ★★★★ **T-P0-064's six ACs remain**, and AC-1 is an eye gate — §4A puts it first.
4. ★★ **Audit the other probes for `$FE00-$FEFF` sweeps** (§7.3).

---

### 9 — User interaction during task

1. Jay ruled **Option B and the simple 60-count**: *"do b. and use the vsync. one second in 12.5
   minutes won't be missed."* Implemented as far as §3.1 records.
2. Jay: **"check the gate"** and **"continue"** — the nine-title runs in 25.1.
3. Jay: **"orchestrator needs reports for t-064 and 065"** — the request this report answers.

---

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-08-a-rate-is-not-an-address.md`
- `seeds/AGI/live/2026-09-08-a-self-test-must-exclude-what-the-machine-needs-to-keep-running.md`

---

### 11 — Commit

Work: **`0366844`** (pushed to origin/wip). This report: see the commit carrying it.
