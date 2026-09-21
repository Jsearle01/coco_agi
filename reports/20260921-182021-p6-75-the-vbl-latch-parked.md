## Form B Report — P6.75 — Input at 60 Hz: built, measured, FAILED its eye gate, parked
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-21 (HEAD 16dd852, wip). git status clean at t0.

### 1 — Summary

★★★★★ **The VBL key latch was built, measured against its own fault arm, and FAILED its eye gate.**
Jay, playing it: *"after a few cycles of animation the game goes into a loop with everything
animating, but nothing moving just flashing including graham."* ★★★★ **It is now OPT-IN
(`-DP3B_VBLKEYS_OPT`, `-VblKeys`) and the shipped combined arm is back to its P6.74 bytes.** All the
code, instruments and measurements stay in the tree.

**What it did achieve, measured:**

| | keys made | reached the game |
|---|---|---|
| ★★★★★ **VBL latch** | 20 | **20** — captured 20, dropped 0, drained 20 |
| per-cycle scan (`-NoVblKeys`) | 20 | **10** |

★★★★ **Why it was parked:** a coded arrow post produced **~5 captured edges per press (40 from 8)**.
Each extra edge of the same arrow is *"the same direction again"*, which **stops** the ego
[keyboard.cpp:537-611] — go, stop, go, stop. **A walk cycle animating in place is very close to
what Jay describes.** The old 2.6 Hz scan sampled too slowly to see bounce; a 60 Hz edge detector
sees all of it. ★★★ **Leading suspect, not proven** — see §7.1.

### 2 — Files modified
- `src/harness/p3b_probe.s` — `p3_irq`, `p3_vbl_latch`, `p3_kq_get`; the slot-0 queue; the three
  scanners converted to drainers; the opt-in flag.
- `src/harness/vm_text_ops.s` — the FOURTH scanner (`tx_wait_dismiss`) converted.
- `harness/tools/p3b_show.ps1` — `-VblKeys`, `-NoVblKeys`, want-line, allowlist.
- `harness/tools/p3b_run.lua` — `P3B_BURST` (incl. coded keys), `P3B_ENTER_EVERY`, the made-vs-
  delivered readout taken when the burst ends.
- `harness/tools/p3b_arms_check.ps1` — `p3b_comb` restored to 18703 / 5F96E2BD, with the latch's
  18782 / B9F06823 recorded for whoever re-enables it.

### 3 — Reasoning

**§4A — the oracle** [tier: ScummVM, pin 9d9b9e93].

1. **`KEY_QUEUE_SIZE 16`** [agi.h:571], circular, and **`keyEnqueue` has no full check**
   [keyboard.h:27-31]: a 17th key advances `END` onto `START` and the queue reads as **empty**.
2. ★★★★★ **Press versus held — the design-deciding answer.** Keys are enqueued on `EVENT_KEYDOWN`
   only [keyboard.cpp:333-334], and **OS auto-repeat is discarded for direction keys**:
   `if (_allowSynthetic || !event.kbdRepeat) key = AGI_KEY_LEFT;` [keyboard.cpp:226-242]. **A held
   arrow is exactly ONE event. The latch must record EDGES, not levels.**
3. `_keyHoldMode` (KEYUP → `AGI_KEY_STATIONARY`) exists but is off by default.

★★★★★ **§4A(2) exposes a defect in the SHIPPED code, independent of the latch.** `p3_poll_dir`
samples the matrix **LEVEL** once per cycle. Hold RIGHT across three cycles and it reads RIGHT three
times: **set → "same direction again, stop" → set**. **And I told Jay to hold the key** in P6.74's
eye gate, which made it worse. That defect is still in the shipped combined arm.

**§3(2) — the chain, without touching `src/hal/`.** The probe already writes `$FEF7 ← JMP` because
its MMU remap destroyed the ROM's stub [AD-200]. Pointing that JMP at `p3_irq` — latch, then
`JMP hal_vbl_handler` — adds a stage in front of the shared handler without editing it. A 6809 IRQ
stacks the full machine state and `hal_vbl_handler` ends in `RTI`, so the latch saves nothing.

**★★★★★ §3(3) — every caller of `HAL_key_scan`, and there were FOUR, not three.**

| caller | before | in the latch arm |
|---|---|---|
| `p3_key_latch` (park loop) | scanned | **no-op** |
| `p3_poll_key` (fallback) | scanned | **no fallback** — takes `p3_keybuf` only |
| `p3_poll_dir` | scanned | **drains the queue**; forwards non-directions to `p3_keybuf` iff the prompt is enabled |
| ★★★★ **`tx_wait_dismiss`** (`vm_text_ops.s:460`) | scanned | **drains the queue** |
| `p3_vbl_latch` | — | ★★★★★ **the ONLY scanner** |

★★★★ **The fourth was not in the dispatch's list.** It is the blocking message-box wait, and in the
latch arm it would have been a second owner of the PIA's column register for as long as a box is on
screen — §1.2's hazard, the kind that fails intermittently. Found by grepping every caller rather
than trusting the list [§2H check 3].

**§3(4) — the queue's home.** `CP_CEL` ends at `MAP_INPUT+928 = $1FA0`; `$1FA0-$1FFF` is 96 bytes
in slot 0, never remapped, so an interrupt may write it in any phase. ★★ **The `P3_RBTRACE`
collision message says `$1F60`; that figure is stale.**

**§4C — the measurements.**

1. ★★★★★ **Made vs delivered: 20/20 with the latch, 10/20 without** — same counter (`p3_nvarkey`),
   same meaning, two input paths, so the pair measures the latch alone.
2. **s/cycle**, title screen, no input, identical work: **0.2014 (latch) vs 0.2008** — unchanged,
   which is the check that this fixes input and not speed.
3. **Stack low-water: 54 vs 55 bytes used of 768** — the scan inside the handler did not deepen it.
4. ★★★★ **Handler cost, no-key: 0.067 s over ~1,206 frames ≈ 55 µs ≈ 99 CPU cycles per frame,
   0.33 % of a 29,800-cycle frame.** Measured, not taken from arithmetic. ★★ **The key-down cost
   (the HAL's full ~896-cycle walk) was NOT measured** — `natkeyboard` cannot hold a key — so that
   figure remains the HAL's own [hal_globals.s:262-271], labelled as such.

**The queue depth.** A first build used 8 and a per-frame ENTER poster dropped 33 of 110; **16, the
oracle's size, dropped 25 of 143** — and **captured + dropped equalled posts exactly**, so nothing
vanished silently. The remaining drops are the test (ENTER twice a second for 71 s, through two
~8 s renders when nothing drains); any finite queue overflows under that, including the oracle's.

### 4 — Verification (AC-by-AC)

- **AC-1 [citation · oracle] PASS** — §4A's three answers, quoted.
- **AC-2 [design] PASS** — **one owner of the PIA** in the latch arm; four former callers listed,
  including the one the dispatch missed.
- **AC-3 [state-comparable] PASS** — **20/20 delivered, against 10/20 for the fault arm.**
- **AC-4 [measurement] PASS** — s/cycle unchanged; stack unchanged; handler cost 0.33 % no-key.
- **AC-5 [byte-comparable] PASS** — **`src/hal/` untouched**: `hal_sync_check.py` OK against both
  siblings, and `git status src/hal` empty.
- **AC-6 [byte-comparable] PASS** — **pic 45/45 · res 1,264/1,264 · cel 9,193/9,193 ·
  comp 124/124**, fresh; `vm` not re-run (`vm_probe.s` unchanged, the latch lives in `p3b_probe.s`).
- **AC-7 [suite] PASS** — all five p3b health gates green.
- **AC-8 [fault injection] PASS** — `-NoVblKeys` RED: **10 of 20.**
- **AC-9 [eye gate — Jay] ★★★★★ FAILED.** *"after a few cycles of animation the game goes into a
  loop with everything animating, but nothing moving just flashing including graham."* **The latch
  is parked as a result.**
- **AC-10 [manifest] PASS** — shipped arms byte-identical to P6.74; the latch's figures recorded
  beside `p3b_comb` for re-enabling.
- **AC-11 [tooling] PASS** — `hal_sync_check.py`, `gen_vm_tables --check`, `p3b_arms_check.ps1`
  8/8, `fix_mojibake --check` clean.
- **AC-12** Candidate captured (§10).

### 5 — Verdict-time evidence (v0.7 §11)

```
25.1  VBL latch:   VBL key queue at cycle 45: made 20, reached the game 20
                     [queue: captured 20, dropped 0, drained 20]   ★ every press delivered
      -NoVblKeys:  VBL key queue at cycle 44: made 20, reached the game 10
                     [no queue: per-cycle scan]   ★★★ PRESSES MISSED
      no input:    100 cycles in 20.1426 s (latch)   vs   20.0758 s (no latch)
                   stack low-water 54 B (latch)      vs   55 B
      coded arrows: made 8, captured 40, dropped 8   <- ~5 edges per press

      per-picture: 45 PASS, 0 FAIL (of 45)
      ★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
      ★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22 -- all green
      ★ all 8 arms byte-identical to the recorded baseline (SHA256)
      [hal-sync] OK -- aligned with POP3_port, karateka_coco3 (11 files compared)
      CHECK OK: src/harness/vm_tables.s matches optable.py
25.2  N/A -- probe and harness code only.
25.3  FAILED -- Jay, live-disk, RGB, combined arm with the latch, castle room.
      "after a few cycles of animation the game goes into a loop with everything animating,
       but nothing moving just flashing including graham"
```

### 6 — Reactive deviations and route accounting

1. ★★★★★ **The latch was made opt-in after the eye gate failed.** Not requested; I judged that a
   regression Jay experienced must not stay switched on in the arm he plays. Reversible: one flag.
2. ★★★ **The queue went from 8 to 16** after a measured 33-of-110 drop.
3. ★★ **Two harness posters were added** (`P3B_BURST`, `P3B_ENTER_EVERY`) and the made-vs-delivered
   readout is taken when the burst ENDS, because a later un-dismissed box stalls the run and a
   stalled run never reaches the summary.

**ROUTE ACCOUNTING.** Everything in §4 was built. **What was not delivered is the outcome §4C and
AC-9 were for**: control that works in Jay's hands. **The byte-level result (20/20) passed and the
eye gate failed** — §4A.3's pattern exactly: a finding about what the count cannot see.

### 7 — Uncertainty flags

1. ★★★★★ **Jay's symptom is NOT reproduced headless, and the bounce explanation is unproven.**
   - Coded arrows (`post_coded("{RIGHT}")`) register as **non-direction keys in BOTH arms** —
     `dir=0` throughout, counted by `p3_nvarkey`. Jay walked Graham with a real keyboard in P6.61,
     so this is most likely my injection not reaching the CoCo3's arrow keys the way a physical
     press does. **Test artifact until shown otherwise.**
   - The headless stall at cycle 57 is a **message box** (`box still up`, CPU in the dismiss wait)
     and it occurs in **both** arms — pre-existing. **A blocking box stops cycling, so it cannot be
     the flashing Jay saw.**
   - ★★★ So "~5 edges per press causes go-stop-go" fits the symptom and is **not demonstrated.**
2. ★★★★ **The shipped combined arm still has the level-scan toggle** [§3, §4A(2)]: a held arrow
   re-fires every cycle and the same-direction rule stops him. That predates this task.
3. ★★ **Only coded ENTER and letters were measured for delivery.** Real arrows were not.

### 8 — Follow-up candidates

1. ★★★★★ **Debounce the latch, then re-gate with Jay.** Require a key to be stable for two
   consecutive VBL frames before it counts as an edge; the cost is one byte and ~17 ms of latency.
2. ★★★★ **Make headless arrows faithful** — the ioport-field approach `key_coverage.lua` uses holds
   a real matrix key, where `post_coded` apparently does not. **Without it, no control defect can be
   reproduced or regression-tested without Jay.**
3. ★★★★ **The cycle rate: 2.6/s against AGI's 20** [P6.74] — still the root of the input problem.
4. ★★ The stale `$1F60` in the `P3_RBTRACE` collision message.

### 9 — Doc-edit deltas applied
- `p3b_probe.s` — beside the `$FEF7` stub, that the latch chains there and would own the PIA;
  beside each former scanner, that it drains and must not scan; at the flag, why it is opt-in.
- `vm_text_ops.s` — the fourth scanner, found by grep and not by the dispatch's list.
- **Design-spec text: none proposed** [§2D].

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-21-a-faster-sensor-sees-the-noise-the-slow-one-averaged-away.md`

### 11 — Commit
(recorded below; pushed to origin/wip before this report was surfaced)
