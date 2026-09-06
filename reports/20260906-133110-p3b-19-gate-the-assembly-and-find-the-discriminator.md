## Form B Report — P3b.19 — Gate the assembly, and find the discriminator

**Class:** build. wip.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-06 (HEAD `60c331a`, wip). `git status` clean at start; at report time the diff is
`harness/tools/gates.manifest`, `src/harness/p3b_probe.s`, and two new tools.

---

### 1 — Summary

**The discriminator is found, and it is not a property of the picture.** Every p3b divergence figure
ever published — 71.5%, 28.8%, 23.9%, 20.7%, 20.6%, 14.8% — was produced by a scratch script that
read **one file: the visual plane**. The priority plane was dumped on every one of those runs and
compared on none of them. Comparing it splits the divergence by kind and the answer is flat:
**the priority plane is 100% UNDER-FILL** on pictures 22 and 53, 87.1% on picture 3 — the guest
leaves the cleared value 4 exactly where the oracle painted a band. **Fills are not writing the
priority plane.** Lines are: picture 80's priority plane is byte-perfect and carries 2.4% non-clear
pixels, all of them drawn.

**The picture-side separator follows from that, and it is `priSeed`** — whether a picture issues any
fill seed while the priority plane is enabled. Picture 80 is the only one of the seven sampled with
`priSeed == 0`, and the only clean one. ★★★★★ **Across all 82 KQ1 pictures only THREE have
`priSeed == 0`: 80, 83 and 84.** Picture **83 is the title screen** — the room p3b boots into, and
the one room Jay has ever reported looking right. **The two pictures p3b renders correctly are two
of the three pictures in the game that never ask a fill to write the priority plane.**

The dispatch's own candidate — a picture's **FC_PRIORITY share**, the fill's *test* plane — is
**REFUTED** and recorded as such. It is ~0 across the whole sample, including the 71.5% outlier.

`p3b_probe.s` now has a `gates.manifest` row, recovered by byte-match, and the gate is proven able to
fail: a known-bad build takes picture 80 from **0.0% to 64.5%**.

---

### 2 — Files modified

- `harness/tools/gates.manifest` — **ninth row, `p3b`** (AC-3), with the reason the row looks wrong.
- `src/harness/p3b_probe.s` — `-DP3B_FAULT_CLEAR`, the historical clear defect behind a flag (AC-4).
  Inert by default; the shipped artifact is byte-unchanged.
- `harness/tools/plane_pair_diff.py` — **new.** Diffs BOTH planes, encoding measured per plane.
- `harness/tools/fill_census.py` — **new.** Static fill census by plane-enable state; `--title`.

---

### 3 — Reasoning

#### 3.A ★★★★★ The dispatch's candidate is refuted, and cleanly

25.3's candidate was that divergence tracks a picture's **FC_PRIORITY** share — fills whose *test*
plane is priority, the nibble walk under `-DPRI_PACKED`. `fill_census.py` walks the picture opcodes
and attributes each fill seed to the plane state in force:

```
pic    fillOp   seeds  visSeed  priSeed  PRI-ONLY    patOp
1          22      86       84       68         2        0
3          17      74       74       37         0        0
5          21      70       70       31         0        0
17         26      73       72       48         1        0
22         23      40       40       20         0        0
53         26      64       64       18         0        0
80          2       8        8        0         0        0
```

★★★★ **`visSeed` equals `seeds` everywhere.** Every fill in the sample runs with the visual plane
enabled, so every fill takes the **FC_VISUAL** path. `PRI-ONLY` — the fills that would select the
priority test — is **0, 0, 0, 1, 0, 0, 2**. ★★★★★ **Picture 3, at 71.5% the worst divergence in the
record, has PRI-ONLY = 0.** A quantity that is zero on the worst case cannot be what orders the
cases. **The candidate is dead, and this is the first thing the census was able to say.**

★ It also refutes half of my own P3b.17 §3.D, which offered *"fills that never ran (FC_PRIORITY takes
the windowed path)"* as the mechanism. **That half is wrong.** The other half of §3.D — the fill's
*write* to a windowed, packed priority plane — is what survives, and §3.C below is what promoted it
from a source reading to a measurement.

#### 3.B ★★★★★ Every divergence figure in the record measured half the artifact

`planediff.py`, the scratch script behind all seven figures, takes two file paths and was only ever
handed `guest.visual.bin`. **`guest.priority.bin` was written by every one of those runs.** The
priority plane is what P3b.17 §3.D's hypothesis is *about*, and it had never been looked at.

`plane_pair_diff.py` compares both. ★★★ **It prints the value histogram of both sides of both planes
before it prints any percentage**, because three wrong comparisons of one file pair in P3b.15 all
came from asserting an encoding instead of measuring one. That guard fired immediately and on its
first run: **the guest's two planes do not share an encoding.** The visual dump is doubled ($FF for
white-15) and the priority dump comes back **bare** ($04 for priority 4). Read as doubled, the
priority plane scores **99.2% divergence on any picture whatsoever** — an instrument artifact that
looks exactly like a catastrophic finding, and one I would have reported.

#### 3.C ★★★★★ Split by kind, the priority plane gives a flat answer

| picture | visual | priority | priority: under-fill / wrong-colour / over-fill |
|---|---|---|---|
| **80** | **0.0%** | **0.0%** | — |
| 22 | 14.8% | **18.7%** | **100.0%** / 0.0% / 0.0% |
| 53 | 23.9% | **21.6%** | **100.0%** / 0.0% / 0.0% |
| 3 | 71.5% | **16.0%** | **87.1%** / 0.0% / 12.9% |

★★★★ **UNDER-FILL means the guest still holds the CLEAR value where the oracle holds a painted one:
the fill did not reach.** There is **no wrong-colour divergence at all** on the priority plane — the
guest never paints the wrong band, it simply fails to paint. The histograms say the same thing
directly, as an excess of the clear value $04:

```
          guest $04    oracle $04    excess     priority divergence
pic022      91.6%        72.9%       +18.7 pts        18.7%
pic053      87.9%        66.3%       +21.6 pts        21.6%
pic003      84.4%        72.5%       +11.9 pts        16.0%
```

★★★ **The excess of the clear value IS the divergence**, to the tenth of a point on 22 and 53. The
missing bands are whole values, not stray pixels: picture 53's oracle is 17.0% priority-14 and the
guest has 3.9%; picture 22's oracle has 5.9% priority-6, 5.5% priority-13 and 3.7% priority-5, and
the guest has 1.3%, 0.6% and none.

★★ **And picture 80 localises it to the fill rather than the plane.** Its priority plane is
byte-identical to the oracle *and* carries 2.4% non-clear pixels — **drawn by lines, with `priSeed`
= 0 fills.** So the windowed packed priority plane is addressed correctly by the line/pen path and
incorrectly by the fill path. That is a much narrower target than "the priority walk".

#### 3.D ★★★★★ The separator, and why no static metric could ever have ordered the magnitudes

`priSeed > 0` is a **necessary condition** for divergence across the sample: 0 for the one clean
picture, 18–68 for all six that diverge. It does **not** order the magnitudes, and it should not be
expected to — **the seed count says whether the defect is reachable; the AREA those fills should have
covered sets how big it is, and area is not derivable from a static opcode walk.** Fill count fails
for the same reason, and PRI-ONLY fails for a worse one (it is zero).

★★★★★ **This is why 25.3's framing could not have worked.** The discriminator is not a property of
the picture at all — it is a property of the *build*. **Picture 22 renders byte-identically in
`pic_probe`, on BOTH planes** (`picgate.py:72-73` compares `pic%03d.visual.bin` and
`pic%03d.priority.bin`; 22 and 53 are inside the passing 45) **and diverges in p3b with zero
sprites.** Same picture, same `pic_core`, same oracle reference. The one difference is the priority
plane's memory regime: `pic_probe` forces `PLANE_PRI_FLAT` whenever windowing is on
[`pic_probe.s:86-91`], p3b sets `PLANE_WIN_MMU equ 1` **in source** [`p3b_probe.s:65`] and windows
both planes. **The picture-side census was answering the wrong question, and answering it is what
showed the question was wrong.**

#### 3.E ★★★★ The corpus fraction, and what it says about the clean sample

**3 of 82 KQ1 pictures have `priSeed == 0`: 80, 83 and 84.** ★★★★★ **96.3% of the game asks a fill
to write the priority plane.**

★★★★★ **Picture 83 is the title screen**, the room p3b boots into (`room 83` in every run log), and
Jay's first live observation was *"when it starts i see the king's quest title screen. then another
room overwrites it but it is wireframe only."* **The title screen is one of the three exempt
pictures.** Picture 80 is another, and it is the sample that has been forced in unconditionally
since T-P0-011. ★★★ **Both pictures p3b has ever rendered clean sit inside a 3.7% exemption**, and
Jay's eye gate said so before any of this was measured.

★ P3b.17 charged that picture 80 was unrepresentative on fill *count* (2 against a median of 19).
That charge was right and understated: on the axis that actually separates, it is 1 of 3 in 82.

#### 3.F The gate row, and the reading it invites [AC-3]

The flags were recovered by **byte-match against the shipped artifact**, not from memory: eight
candidate flag sets were built and exactly one reproduced `build/p3b_probe_pk_fresh.bin` at
**12,859 bytes identical** — `-DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED
-DPRI_PACKED`.

★★★★★ **`PLANE_WIN_MMU` is absent from that line and p3b IS windowed through the MMU.** Every build
that passes it fails with `Multiply defined symbol`, because `p3b_probe.s:65` sets it
unconditionally in the source. ★★★★ **I read the first result as "p3b never windowed either" and
started drafting the retraction of §3.D before reading the assembler error**, which took one command
and said the opposite. The row therefore carries the warning in the manifest: *do not "fix" this row
by adding the flag*, because the natural reading of its absence is the exact inverse of the truth.

★★ **Contrast the `pic_win` row two lines above, which passes `-DPLANE_WINDOWED` and NOT
`-DPLANE_WIN_MMU` and therefore genuinely does not window.** The same two symbols mean opposite
things in the two files. This closes the carried item *"`pic_win`'s row may not enable windowing"*:
**it does not.**

#### 3.G Authority tiers and §2H

Every figure is fresh tool output on this machine (25.1). Oracle planes are the reference per §2O.1;
no conclusion is drawn against our own renderer. §2H's three checks: the **second mechanism** was
looked for and is the finding — the fill has a *test* plane and a *write* plane, the candidate named
the first and the defect is in the second; the **calling routine** is named at each step (the fill's
priority write under `PLANE_WIN_MMU`, not `pic_core`'s dispatch); the **prior-report grep** is §3.A's
partial retraction of my own P3b.17 §3.D. §2S: no sibling claim is made beyond `hal_sync_check`.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: eye-gated] — PENDING JAY.** §4A commands in §5. ★ This task changed no rendering
  code, so the live behaviour is P3b.18's; the gate is offered rather than claimed.
- **AC-3 [class: byte-comparable] — PASS.** `gates.manifest` has a ninth row, `p3b`.
  `gate_audit.py --verify` builds it from source and reports **12,859 / 12,859 identical**.
- **AC-4 [class: byte-comparable] — PASS, two-sided.** `-DP3B_FAULT_CLEAR` restores the historical
  constant overflow. Known-good picture 80: **visual 0.0%, priority 0.0%.** Known-bad: **visual
  64.5%, priority 0.0%.** ★★ The fault stays confined to the plane it touches, which is the right
  blast radius — the visual clear was the truncated term and the priority clear was not.
  ★★★ **Honest scope: `gate_audit --verify` is a STALENESS gate, not a correctness gate.** It proves
  the artifact is what its source builds; it cannot catch a defect that was rebuilt into both. The
  fault-detectability above is the *behavioural* check against the oracle, not the audit.
- **AC-5 [class: state-comparable] — ANSWERED. The candidate is refuted; the discriminator is
  found.** §3.A refutes FC_PRIORITY share (0 on the 71.5% outlier). §3.C names it: **the priority
  plane is 100% under-fill; fills do not write it; lines do.** §3.D gives the separator (`priSeed`)
  and states plainly that it separates without ordering, and why.
- **AC-6 [class: byte-comparable] — PASS.** The eight pre-existing rows are **identical**, at the
  same byte counts as P3b.17 §5: 2642 / 2512 / 2971 / 2655 / 2019 / 1436 / 967 / 8712. The new guard
  did not move `p3b_probe_pk_fresh.bin`.
- **AC-7 [class: state-comparable] — measured.** **3 of 82 (3.7%)** KQ1 pictures have `priSeed == 0`
  (80, 83, 84); **96.3% do not.** Separately, corpus membership for the renderer gate is **purely
  resource size** against the 1,263-byte poke window — 022 is 1,188 B and 053 is 1,057 B and both are
  in; 003 is 1,366 B, 005 1,509 B, 017 1,829 B and 001 2,752 B and none are. **Nothing about content
  selected the 45.**
- **AC-8 / AC-9 [class: state-comparable] — see §6 and §7.** No renderer code was changed; the defect
  is localised and **not fixed** (shared renderer code, trigger 2).

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — `gate_audit.py --verify`, nine rows:**

```
gate   artifact                  shipped    fresh  verdict
pic    build/pic_probe.bin          2642     2642  identical
pic_nc build/pic_nc_unpacked.bin     2512     2512  identical
pic_nc_pk build/pic_nc_packed.bin      2971     2971  identical
pic_win build/pic_v_windowed_nocount.bin     2655     2655  identical
res    build/res_probe.bin          2019     2019  identical
cel    build/cel_probe.bin          1436     1436  identical
comp   build/comp_probe.bin          967      967  identical
vm     build/vm_probe.bin           8712     8712  identical
p3b    build/p3b_probe_pk_fresh.bin    12859    12859  identical
```

```
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
```

**AC-3 — the byte-match that recovered the row:**

```
A  FAILED     ... -DPLANE_WINDOWED -DPLANE_WIN_MMU -DPRI_PACKED
B  FAILED     ... -DPLANE_WINDOWED -DPLANE_WIN_MMU -DPRI_PACKED -DPIC_NOCOUNT
C  FAILED     ... -DPLANE_WINDOWED -DPLANE_WIN_MMU
D  12859  IDENTICAL -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED
E  FAILED     ... -DPRI_PACKED
F/G/H FAILED  ... with -DPIC_FAULT / -DVM_FAULT / -DCOMP_FAULT
target 12859  build/p3b_probe_pk_fresh.bin

src/harness/p3b_probe.s(65) : ERROR : Multiply defined symbol (PLANE_WIN_MMU)
```

**AC-4 — fault-detectability, picture 80:**

```
=== FAULT BUILD (-DP3B_FAULT_CLEAR), room 80 ===
  VISUAL   DIFFERING: 17345 of 26880 (64.5%) over 161 of 168 rows
           BY KIND: UNDER-FILL 6.9% | WRONG-COLOUR 84.0% | OVER-FILL 9.1%
  PRIORITY DIFFERING: 0 of 26880 (0.0%)
=== CLEAN BUILD, room 80 (control) ===
  VISUAL   DIFFERING: 0 of 26880 (0.0%)
  PRIORITY DIFFERING: 0 of 26880 (0.0%)
```

**AC-5 — both planes, by kind:**

```
=== pic003 ===  VISUAL 71.5%  under 7.7% / wrong 92.3% / over 0.0%
                PRIORITY 16.0%  under 87.1% / wrong 0.0% / over 12.9%
=== pic022 ===  VISUAL 14.8%  under 45.2% / wrong 54.8% / over 0.0%
                PRIORITY 18.7%  under 100.0% / wrong 0.0% / over 0.0%
=== pic053 ===  VISUAL 23.9%  under 66.4% / wrong 31.0% / over 2.5%
                PRIORITY 21.6%  under 100.0% / wrong 0.0% / over 0.0%
=== pic080 ===  VISUAL 0.0%   PRIORITY 0.0%
```

**AC-7 — the corpus fraction:**

```
★★ pictures with priSeed == 0 (no fill writes the priority plane): 3 of 82 (3.7%)
   80, 83, 84
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact changed; the nine gate binaries are
byte-identical to their sources (25.1 above).

**25.3 operator-runtime-smoke: pending Jay.** §4A commands:

```powershell
$s = '<scratchpad>\p3bshow.cmd'
& $s 40 83 eye83 0 6      # the TITLE SCREEN -- priSeed 0, predicted CLEAN
& $s 40 22 eye22 0 6      # in-corpus, zero sprites, priSeed 20 -- predicted UNDER-FILLED
```

★★★ **This pair is a prediction, not an illustration.** 83 and 22 are both KQ1 rooms; the model
above says 83 renders right and 22 does not, on the priority plane's account. If 83 comes up wrong,
the model is wrong.

---

### 6 — Reactive deviations and route accounting

- **The dispatch named one candidate for AC-5 and I ran it first, as instructed.** It is refuted
  (§3.A). What followed — the two-plane comparison — was not in the dispatch; I went there because
  the refuted candidate was *about* the priority plane and nothing had ever measured it.
- **ROUTE ACCOUNTING.** I proposed, in P3b.17 §3.D, that the windowed priority walk was "the only
  path left", with a mechanism attached. **This task implements none of a fix.** The *conclusion*
  survives and is now measured rather than read from source; **the mechanism I gave for it is
  refuted** (§3.A) and is retracted here rather than quietly restated.
- **Not implemented, deliberately:** the fix. It is shared renderer code (trigger 2) and this task's
  mandate was to find the discriminator.

---

### 7 — Uncertainty flags

1. ★★★★ **The visual plane is not yet explained, and picture 3 is the reason.** Its visual
   divergence is **92.3% wrong-colour**, not under-fill — the guest paints large areas colour 8 and 7
   where the oracle paints colour 10 (oracle 59.7% `$0A`; the guest has effectively none). That is a
   fill that *escaped or carried the wrong value*, which is the opposite defect to the priority
   plane's under-fill. **One mechanism has not been shown to produce both**, and I have not shown it.
   Pictures 22 and 53 are mixed (45.2% and 66.4% under-fill), so picture 3 may be a second defect.
2. ★★★ **`priSeed > 0` is necessary on a sample of seven; it is not shown to be sufficient.** Only
   three KQ1 pictures could test the negative side and only one of them (80) has been rendered.
   **Rendering 83 and 84 is the cheap two-sided test** and is what §5's eye gate begins.
3. ★★ **`fill_census.py` is a static walk and does not model `set_pattern`/`pattern_fill` state**,
   which is safe only because pattern fills are 0 across all 287 pictures (P3b.17 AC-3).
4. ★ **Picture 3's guest render carried 2 sprites** (`r3.log`), so a small part of its visual
   divergence is compositing, not rendering. 22 and 53 ran with zero and are the clean samples.
5. ★ **`build/p3b_probe_pk_fresh.bin` is an awkward permanent name** for the artifact the manifest
   now pins. Renaming it touches every launch script and was out of scope.

---

### 8 — Follow-up candidates

1. ★★★★★ **Find the fill's priority write under `PLANE_WIN_MMU`** — the target is now one path, not
   a subsystem: lines write the windowed packed priority plane correctly, fills do not.
2. ★★★★ **Render 83 and 84** to close the negative side of the separator (§7.2).
3. ★★★ **Explain picture 3's 92.3% wrong-colour visual divergence** — possibly a second defect.
4. ★★★ **Widen the 1,263-byte poke window**, which is the *only* thing keeping 1/3/5/17 out of the
   gated corpus (AC-7). The corpus was never selected on content.
5. ★★ **Give `res`, `cel` and `comp` the same `_FAULT` treatment `p3b` now has** (carried, 5 tasks).

---

### 9 — User interaction during task

None during execution. The eye gate in §5 is outstanding and is addressed to Jay.

---

### 10 — Candidate(s) captured this task

`seeds/AGI/live/2026-09-06-a-divergence-figure-names-the-artifact-it-actually-read.md`

---

### 11 — Commit

See below. Pushed to origin/wip before this report.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
