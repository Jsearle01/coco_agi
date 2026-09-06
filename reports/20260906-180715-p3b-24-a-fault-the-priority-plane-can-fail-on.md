## Form B Report — P3b.24 — A fault the priority plane can fail on

**Class:** build. wip.

---

### §4 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi ===       wip  a143044 at start -> 5454d38 at report.  clean.
=== POP3_port ===      wip  104b197  unchanged
=== karateka_coco3 === wip  29f8f0a  unchanged

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s)   -- unchanged

gate   artifact                  shipped    fresh  verdict
pic 2654 | pic_nc 2524 | pic_nc_pk 2983 | pic_win 2667 | res 2055
cel 1472 | comp 967 | vm 8748 | p3b 13052          ALL NINE IDENTICAL

clock MEASURED 1.789772 MHz (160009 cycles calibrated)      [L-78]

p3b palette provenance line, every run:
  palette: 16 entries EXPECTED from content/agi_palette.s [P4.4 AC-11/AC-12]
           -- INSTALLED BY THE GUEST  idx2=$10 idx6=$22 idx15=$3F
```

★★ **§2T:** siblings cited from P3b.21 §4, both HEADs unchanged.

★★★★ **§4 asks for the renderer's "53/53 both planes" and the widened composite's "180 frames".**
★★★ **Correction, and it is the dispatch's own figures that are off:** 53/53 is **p3b's** corpus
sweep [P3b.20 AC-5], not a gate row — the renderer gate is **45/45**, which is what
`run_gates.sh pic` produces and what §4's table above reproduces. The widened composite's 180
frames is a corpus **built last task and not yet a manifest row**; it is run explicitly, nine
invocations of 20. **Both numbers are real and neither is a gate row**, so §4's table lists the
nine rows that are.

★★★ **Priority rejections per corpus [AD-126], carried forward and now shown to be the wrong
separator for this question — see §3.C.**

---

### 1 — Summary

★★★★★ **The composite gate's priority half can now fail, for the first time since the gate
existed.** `COMP_FAULT` moves the visual plane and **zero** priority bytes, because it flips the
depth test at the **equal-priority boundary** — and at such a pixel the value the sprite would
write is the value already there. **`COMP_PRI_FAULT` perturbs the VALUE instead of the DECISION:
the sprite stamps an adjacent priority band.**

★★★★★ **The two faults are exact mirrors on the same pixels.** SpaceQuest-1 frames 011/014/015:
`COMP_PRI_FAULT` gives **visual 0, priority 664/688/725**; `COMP_FAULT` gives **visual
664/688/725, priority 0**. ★★★ **Same byte counts, opposite planes** — they add rather than
replace [L-54].

★★★★ **AC-5 refutes the dispatch's §3 framing.** It expected only corpora exercising priority
*rejections* to carry a priority fault. **All nine carry it** — eight at 20/20, PoliceQuest1 at
11/20 — **including the five with zero rejections.** The fault fires where a sprite **stamps**
priority, not where the test **rejects** a pixel, and those are different events.

★★★★ **AC-7 closes the palette item, and AC-1 closed it by eye.** p3b writes its own palette,
verified by cold boot: **16 guest writes from PC `$5005`**, all matching `content/agi_palette.s`.
★★★ **And the first cold run found a regression I had introduced** — Jay: *"i saw a bunch of
garbage before the king's quest title screen"* — fixed, re-run, and **Jay: *"that looked good."***

---

### 2 — Files modified

- `src/harness/composite.s` — `COMP_PRI_FAULT`, both the packed and flat store paths.
- `src/harness/p3b_probe.s` — the palette load moved **after** `p3_black_visible` (§3.D).
- `harness/tools/p3b_show.lua` — VOFFSET asserted before staging (§3.D).

---

### 3 — Reasoning

#### 3.A ★★★★★ Why a second fault was needed, in one line

`COMP_FAULT` changes behaviour **only** where `screenPriority == viewPriority`. At an equal-priority
pixel the priority value the sprite would write **is the value already there**, so drawing and
not-drawing leave the priority plane byte-identical. ★★★ **A fault built on that boundary can only
ever move the visual plane** — which is why the measurement was zero everywhere and why no corpus
could have fixed it.

#### 3.B ★★★★ The fault, and what real bug it resembles [AC-6]

**The sprite stamps an ADJACENT priority band** — `eor #1` on the value written, at both store
sites (the packed read-modify-write and the flat store; **the comp gate builds flat**, since its
manifest row carries no `-DPRI_PACKED`).

★★★★ **Design §3.5 makes priority banding a 168-byte LOOKUP TABLE rather than a computation**, and
an off-by-one in that table — or wrong rounding at a band edge — lands exactly here: every stamped
pixel carries a **plausible, in-range, wrong depth**. ★★★ `eor #1` keeps the value inside 0–15, so
nothing overflows a nibble and no plane changes size. **The defect is a wrong depth, not a
corruption** — the kind a byte gate exists to catch and an eye gate would miss, because a sprite
drawn at the wrong band still looks like a sprite.

★★ **Separable from `COMP_FAULT`** [L-54]: different symbol, different mechanism, different plane.
**The gate should be run under both**, and neither replaces the other.

#### 3.C ★★★★★ AC-5: all nine corpora carry it, and the separator was wrong again

| corpus | priority rejections [AD-126] | `COMP_FAULT` | **`COMP_PRI_FAULT`** |
|---|---|---|---|
| KQ1ego1 | 1,820 | 2/20 | **20/20** |
| KQ1room1 | **0** | — | **20/20** |
| KQ1room3 | 100 | — | **20/20** |
| KQ1room5 | **0** | — | **20/20** |
| Kingquest2 | **0** | — | **20/20** |
| Kingquest3 | **0** | — | **20/20** |
| larry1 | **0** | 20/20 | **20/20** |
| PoliceQuest1 | **15,525** | **0/20** | 11/20 |
| SpaceQuest-1 | 9,314 | 20/20 | **20/20** |

★★★★★ **The five corpora with ZERO priority rejections all carry the priority fault at 20/20.**
The dispatch's §3 reasoned that *"a fault on the priority plane is only detectable on frames where
priority does something"* — **true, and "does something" is not "rejects".** Every drawn sprite
pixel **stamps** a priority value; rejection is a separate, rarer event.

★★★ **That is the third separator in three tasks to be right about one thing and wrong about the
one being asked** — `rejected-by-priority` predicted nothing about `COMP_FAULT` (PoliceQuest1 has
the most rejections and caught it 0 times), `equal-priority` predicted `COMP_FAULT` exactly, and
neither predicts this one, which tracks **stamped pixels**. ★★ **L-89's lesson holds and its
application does not transfer: a separator is a prediction about ONE fault.**

★ **Trigger 2 does not fire.** The gate's default corpus is SpaceQuest-1 [`run_comp_sweep.sh`], and
it carries the fault at 20/20.

#### 3.D ★★★★ AC-1 found a regression I had introduced, on the first cold run

Jay: ***"i saw a bunch of garbage before the king's quest title screen."***

★★★★★ **The screen had been black for the wrong reason.** Two things must be true for the boot to
be black: **the palette must be black AND the display must be looking at a plane we control.**
Only the first was. The host asserted sixteen black entries before staging, which hid everything —
**including that VOFFSET was still scanning wherever DECB left it**, the text screen the stager
overwrites. P3b.22 then had p3b install the **real** palette at init, before clearing its visible
plane, and the hidden garbage became visible garbage.

★★★ **Both halves fixed.** The guest installs the palette **after** `p3_black_visible` has zeroed
the plane it colours — index 0 is `$00`, so a zeroed plane is black under the real palette too and
**the transition is invisible rather than merely brief**. The host points VOFFSET at block 40
before staging rather than at cycle 2.

★★ **This is what §4A is for.** No byte gate moved: pictures 22/1/3/83 were 0.0% on both planes
before and after, and the binary is the same size — the call moved, it did not grow. **A human
watching the boot is the only instrument that could have seen it.**

#### 3.E Authority tiers and §2H

AC-1 is **Jay's, tier 1**. Oracle frames are the reference per §2O.1. §2H: the **second mechanism**
is §3.C's stamp-versus-reject distinction — the first mechanism (rejection) was the one the
dispatch named and it is not the governing one; the **calling routine** is named at each store site;
the **prior-report grep** was run against the composite gate's history before claiming the priority
half had never failed, and P3b.21 §3.D is the source.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: eye-gated] — ★★★★★ PASSED. Jay, live, `poke`, RGB, COLD BOOT.** Castle and room
  22 in fresh MAME sessions with nothing else run: ***"that looked good."*** ★★★ **The first
  attempt failed and that is reported, not smoothed** (§3.D): Jay saw garbage before the title
  screen, from a regression this task's own AC-7 work introduced.
- **AC-2 [class: byte-comparable] — PASS.** `hal_sync_check` OK in all three; `reg_discipline`
  **8 / 1 file / 2 registers**, unchanged. **All nine gates identical** (§4). §2T: P3b.21 §4.
- **AC-3 [class: byte-comparable] — PASS. The fault moves PRIORITY bytes.**
  KQ1ego1 frames 476–485: **visual 0, priority 242 / 222 / 222 / 234 / 234 / 234**.
  SpaceQuest-1 frames 011/014/015/017: **visual 0, priority 664 / 688 / 725 / 684**.
  ★★★ **Against `COMP_FAULT`'s zero on every divergent frame of both corpora.**
- **AC-4 [class: byte-comparable] — PASS. The pair, same corpus, same session.**
  SpaceQuest-1 **clean: 20 identical, 0 divergent.** **`COMP_PRI_FAULT`: 0 identical, 20
  divergent.** ★★★★ **First time the composite gate's priority half has been shown able to fail.**
- **AC-5 [class: state-comparable] — ANSWERED, and it refutes §3's framing.** All nine corpora
  carry it (§3.C table); the default corpus does. **Trigger 2 does not fire.**
- **AC-6 [class: state-comparable] — an off-by-one in design §3.5's 168-byte priority band table**
  (§3.B). ★★ Stated as a resemblance, not as a discovered bug.
- **AC-7 [class: byte-comparable] — PASS, cold boot.** Fresh MAME session, nothing else run:
  **16 guest writes from PC `$5005`**, all 16 matching `content/agi_palette.s`, alongside 16 from
  Disk BASIC's ROM at `$C00F`. Provenance line in §4. ★★★ **And the earlier AC-1 pass WAS
  inherited** — reported in P3b.22 and restated here as the dispatch asks: that is the finding.
- **AC-8 [class: byte-comparable] — PASS.** `COMP_FAULT` still moves the visual plane, 664/688/725
  bytes on the same frames, priority 0. **The new fault adds; it does not replace** [L-54].
- **AC-9 [class: state-comparable] — four things the dispatch did not anticipate.**
  1. ★★★★★ **The two faults are exact mirrors** — identical byte counts on opposite planes (§1).
  2. ★★★★★ **All nine corpora carry the priority fault**, including the five with zero rejections
     (§3.C). The dispatch expected the opposite and said so.
  3. ★★★★ **AC-7's fix caused an AC-1 failure** — installing the real palette early exposed
     garbage a black palette had been hiding (§3.D). **Two of this session's fixes interacted.**
  4. ★★★ **§4's own figures needed correcting** — 53/53 is p3b's sweep, not a gate row (§4).
- **AC-10 [class: suite]** — see §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — AC-3, per-plane, the two faults on the same frames:**

```
=== COMP_PRI_FAULT (value) ===          === COMP_FAULT (decision) ===
frame 011  visual   0   PRIORITY 664    frame 011  visual 664   PRIORITY   0
frame 014  visual   0   PRIORITY 688    frame 014  visual 688   PRIORITY   0
frame 015  visual   0   PRIORITY 725    frame 015  visual 725   PRIORITY   0
frame 017  visual   0   PRIORITY 684    frame 017  visual 684   PRIORITY   0
```

**25.1 — AC-4, the pair:**

```
SpaceQuest-1  CLEAN       ★ 20 frames: 20 identical, 0 divergent
SpaceQuest-1  PRI_FAULT   ★ 20 frames:  0 identical, 20 divergent
SpaceQuest-1  COMP_FAULT  ★ 20 frames:  0 identical, 20 divergent
build/comp_probe.bin 967 unchanged;  build/comp_prifault.bin 969, its own name
```

**25.1 — AC-5, all nine under COMP_PRI_FAULT:**

```
KQ1ego1 20/20  KQ1room1 20/20  KQ1room3 20/20  KQ1room5 20/20  Kingquest2 20/20
Kingquest3 20/20  larry1 20/20  PoliceQuest1 11/20  SpaceQuest-1 20/20
```

**25.1 — AC-7, cold boot:**

```
guest writes observed: 32
values (bits 7-6 masked): $00 $08 $10 $18 $20 $28 $22 $38 $07 $0F $17 $1F $27 $2F $37 $3F
   PC $C00F  16 write(s)  rom/other        PC $5005  16 write(s)  ★ GUEST
★★★★★ p3b WRITES ITS OWN PALETTE, and all 16 match content/agi_palette.s
```

**25.1 — §3.D's fix did not move a byte:**

```
pic022 / pic001 / pic003 / pic083 : visual 0.0%  priority 0.0%   (before and after)
gate_audit 9/9 identical
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; the nine gate binaries are byte-identical
to their sources (§4).

**25.3 operator-runtime-smoke: ★★★★★ PASSED — Jay, live, `poke`, RGB, cold boot.**
Castle and room 22, fresh MAME sessions: ***"that looked good."*** First attempt failed with
garbage before the title screen (§3.D); fixed and re-run.

---

### 6 — Reactive deviations and route accounting

- **No trigger fired.** Trigger 1: a fault was built. Trigger 2: the default corpus carries it.
  Trigger 3: the cold boot passed **and** the earlier pass is confirmed to have been inherited —
  reported as the finding per the dispatch. Trigger 4: `COMP_FAULT` still works. Trigger 5: n/a.
- **ROUTE ACCOUNTING.** I proposed no route. ★★ **The fault mechanism was mine to choose** and the
  dispatch said so; I chose the value perturbation its §2 named and picked `eor #1` for the reasons
  in §3.B. ★ **What I did NOT do:** add `COMP_PRI_FAULT` to any manifest row (the comp gate has no
  fault row; both faults are built to their own artifact names on demand), or widen the composite
  corpus further.

---

### 7 — Uncertainty flags

1. ★★★ **PoliceQuest1 catches the priority fault on 11 of 20 frames, not 20.** Not diagnosed. It is
   also the corpus `COMP_FAULT` cannot reach at all, so it is the weakest of the nine on both
   faults and worth a look.
2. ★★★ **`COMP_PRI_FAULT` is not in `gates.manifest`.** Neither is `COMP_FAULT`. **No fault build
   is a manifest row**, so fault-detectability is re-established by hand each time rather than
   audited — which is how it went unnoticed that the priority half had never failed.
3. ★★ **The packed store path's fault is untested.** The comp gate builds flat; p3b builds packed
   but runs no composite gate. Written for symmetry and labelled as such, exactly as AD-122's
   unpacked twin was.
4. ★★ **p3b has four bytes of code region left** — unchanged from P3b.22, and the palette-load move
   did not grow it.
5. ★ **`eor #1` maps band 4↔5 and 14↔15.** A band table off-by-one would more likely be uniform
   (+1 everywhere); this is a cheaper stand-in that produces the same class of wrongness.

---

### 8 — Follow-up candidates

1. ★★★★ **Give the fault builds manifest rows** (§7.2) so fault-detectability is audited rather
   than re-derived.
2. ★★★ **Diagnose PoliceQuest1's 11/20** (§7.1).
3. ★★★ **Re-stage the composite corpus on stamped-pixel count**, now that it is the separator this
   fault tracks (§3.C).
4. ★★ **`flag_diff --manifest` over-reports** — open across five tasks.
5. ★ **5 of 9 corpora exercise zero priority rejections** [AD-126] — still true, and now known not
   to bound what a priority fault can detect.

---

### 9 — User interaction during task

★★★★ **Jay ran AC-1 twice.** The first cold run produced ***"run it again i saw a buch of garbage
before the king's quest tilte screen"*** — a real regression, diagnosed in §3.D and fixed in both
halves. The second: ***"that looked good."*** ★★ He also asked me to run the sessions rather than
hand him commands, which is how the first failure was seen immediately.

★ **Separately, and recorded because it changes standing behaviour:** ***"don't commit png's unless
i ask."*** No PNG is committed by this task; the scratch overlay left by P3b.21's verification was
deleted. **This overrides §2P's "commit the visualisation" default** — §2P still governs what may
leave the machine at all, but the decision to commit a permitted image is Jay's.

---

### 10 — Candidate(s) captured this task

`seeds/AGI/live/2026-09-06-a-separator-is-a-prediction-about-one-fault.md`

---

### 11 — Commit

`783378d` (the fault) · `5454d38` (§3.D's boot fix). Both pushed to origin/wip before this report.
This report lands in the follow-up commit.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
