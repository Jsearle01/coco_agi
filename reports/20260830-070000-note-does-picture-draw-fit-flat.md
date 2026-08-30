## Form B Report — Note to Clyde — does the picture-draw phase fit FLAT?
**Class:** recon. wip. ★★★★ **Answer: NO — and the premise the question rests on is false.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-30 (HEAD `26694ed`, wip). git status clean. No build; no file changed.

---

### 1 — Summary

★★★★ **The picture-draw phase does not fit with flat planes: 72,615 against 65,280, over by
7,335.**

★★★ **And it is not close, in a way that makes the arithmetic robust to every assumption
after it.** Two flat planes are **53,760 bytes — 82.4% of the 65,280 available.** That leaves
**11,520**, and the engine code alone is **11,768**. ★★ **The phase is over by 248 bytes before
one byte of stack, status, or picture data is counted.**

★★★★ **The premise is false: picture-draw is not lighter than compositing.** `put_pixel` writes
**both** planes — `lda scr_on / beq pp_pri` then `pp_pri: lda pri_on / beq pp_out` — so
picture-draw needs both planes flat exactly as the compositor does. ★ The only difference is the
source data, and it is a wash: largest PICTURE **5,205 B** against largest decoded cel **4,784**.

> ★★★★ **So Jay is right. The repack IS the blocker, the fill restructure is the next dispatch,
> and the VM decomposition waits.**

---

### 2 — Files modified

**None.** ★ Arithmetic and two reads against the existing tree, per §5's scope.

---

### 3 — Reasoning

#### 3.1 The figures

| phase, FLAT planes | bytes | vs 65,280 |
|---|---|---|
| **picture-draw** | **72,615** | ★★★ **over by 7,335** |
| sprite-composite | 72,194 | over by 6,914 *(P3b.1, unchanged)* |
| **picture-draw, PACKED** | **59,386** | ✓ fits, **5,894 spare** |

Picture-draw flat = 26,880 visual + 26,880 priority + 11,768 code + 5,205 picture + 1,024 seed
stack + 768 hardware stack + 90 status.

★★★ **The dominating check needs none of those line items.** Two flat planes leave 11,520 and
the code is 11,768 — **over by 248 with everything else at zero.** Every disagreement about what
else the phase holds moves the answer in the same direction.

#### 3.2 Why picture-draw is not the lighter phase

★★ **`put_pixel` writes both planes**, conditionally on the two pen flags, and AGI pictures
routinely set both — the fill's own case table has `FC_VISUAL` at 70.3% of calls and
`FC_PRIORITY` at 6.4%, which are *both* non-zero precisely because pictures draw into both.
★ There is therefore **no draw phase in which only one plane is live.**

**Largest PICTURE, measured across the nine v2 titles: 5,205 B (MixedUpMotherGoose-019)** —
against the compositor's 4,784-byte cel staging. ★ That 421-byte difference is the whole of the
gap between the two phases' totals, which is why they land within 1% of each other.

#### 3.3 §3's question — the map is PER-PHASE, and it cannot reach this

★★★ **`memmap.inc` is per-phase, but only for two slots**: slot 5 (priority slice) and slot 6
(framebuffer slice / volume window). Slots 0–4 and 7 are resident in every phase, and entering a
draw phase remaps exactly two.

★★★★ **That machinery cannot help here.** Flat addressing requires a whole plane contiguously
visible inside whatever phase touches it, and **both draw phases touch both planes** (§3.2). So
there is nothing to stagger: the phase discipline can move *which* blocks are visible, not *how
many bytes* a flat index needs at once.

★★ **The note's §3 alternative is effectively right, though not for the stated reason.** The map
is **not** singular — it genuinely is per-phase. **But flat addressing makes the PLANE
REQUIREMENT singular across every phase that draws**, which has the same consequence: packing is
global or it is nothing.

#### 3.4 ★★ The boundary conversion, unasked-for and now moot — but the estimate is wrong

§5 invites a challenge to the Orchestrator's "noise" characterisation, so: converting
26,880 → 13,440 is a 13,440-iteration merge — read two bytes, shift, or, store one. ★ At roughly
**31 cycles per output byte that is ≈416,600 cycles ≈ 233 ms** at 1.789390 MHz.

★★★ **That is 8.5% of a 2,746 ms render, not noise — and on its own it exceeds a whole cycle
budget** (the corpus's dominant request is 100 ms, T-P0-033 AC-6). It would have appeared as a
stall on top of the render rather than disappearing into it.

★ **This is my own arithmetic and unverified** (§8) — a lead, not a finding. **It does not
change the answer**, which is settled by §3.1 without it, and it is recorded only because the
conversion may be proposed again for a different reason.

---

### 4 — Verification (AC-by-AC)

The note sets no ACs. Its two questions, answered:

- **Q1 [class: state-comparable]** *Does the picture-draw phase fit flat?* ★★★★ **NO —
  72,615 against 65,280, over by 7,335**, and over by 248 on the plane-plus-code term alone.
  §3.1.
- **Q2 [class: state-comparable]** *Is the map per-phase or singular?* ★★★ **Per-phase, for two
  slots — and it does not help.** Flat addressing makes the plane requirement singular across
  every drawing phase. §3.3.

★ **Evidence class:** both are arithmetic over previously measured quantities plus two source
reads (`put_pixel`'s two plane writes; the corpus PICTURE maximum). **No build, no gate, no new
measurement** — proportionate to §5's scope.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
=== does picture-draw need BOTH planes? put_pixel: ===
                lda     scr_on
                beq     pp_pri
pp_pri:         lda     pri_on
                beq     pp_out

=== largest PICTURE resource in the v2 corpus ===
  max PICTURE = 5205 B (MixedUpMotherGoose-019)
```

```
available below the I/O page       65280
two FLAT planes                    53760   (82.4%)
  -> left for everything else      11520
  engine code alone (flat build)   11768   OVER by 248

picture-draw, FLAT        72615  vs 65280  -> OVER by 7335
sprite-composite, FLAT    72194  vs 65280  -> OVER by 6914

picture-draw, PACKED      59386  vs 65280  -> FITS spare 5894
```

**25.2 bundled-artifact grep:** N/A — nothing was built.

**25.3 operator-runtime-smoke:** N/A — nothing reached the screen.

---

### 6 — Reactive deviations and route accounting

★ **None.** The note asked for arithmetic and a judgement and that is what this is. ★★ **What I
did NOT do:** did not build, did not restructure the fill, did not implement a boundary
conversion, did not re-run any gate — the unpacked tree is unchanged since `26694ed`.

---

### 7 — Uncertainty flags

1. ★★ **The 11,768-byte code figure is a stub build.** `p3_run_vm`, `p3_stage_sprites` and
   `p3_composite_all` are still `rts`. ★ **The real code is larger, so the flat overrun grows** —
   the direction is safe, the magnitude is not final.
2. ★ **5,205 B is the largest PICTURE in the nine pinned v2 titles**, not in AGI. A fan title or
   an unpinned release could exceed it.
3. ★★ **§3.4's 233 ms is my arithmetic, not a measurement**, and is not load-bearing for the
   answer.
4. ★ **This assumes the picture resource must be CPU-addressable during the render.** It is, in
   the current design — `PIC_DATA equ MAP_ARENA_WIN` and `pic_render` walks it with `pic_get`.
   A streaming renderer that consumed the picture through an 8 KB window would trade 5,205 for
   8,192 and still not fit.

---

### 8 — Follow-up candidates

1. ★★★★ **The fill restructure** — the span walk from byte-pointer to nibble walk (AD-81). It is
   now the sole blocker and the next dispatch's subject.
2. ★★ **Re-check the flat/packed arithmetic once the P3b glue is real**, since §7.1's code figure
   is a stub build.
3. ★ **The VM decomposition's 34.9% unattributed** (T-P0-033 AC-4) waits behind the fill, as the
   note's §4 table says.

---

### 9 — User interaction during task

★★★ **Jay asked, via a Note to Clyde: does the picture-draw phase fit FLAT under the reconciled
map, and is the map per-phase or singular?** The note framed a possible route —
**compositor packed, renderer flat, with a conversion at the phase boundary** — which would have
left the fill's byte-pointer span walk untouched and closed the space problem without the
restructure.

★★ **Answered: no, it does not fit, and the premise is false** — `put_pixel` writes both planes,
so picture-draw is not the lighter phase. **The map is per-phase for two slots and that cannot
reach a flat-addressing requirement.** ★ The note explicitly invited "if the premise is wrong,
say so in one line", and that is the substance of this report.

★ **I also volunteered, per the note's §5 invitation, that the boundary conversion would not have
been noise** (≈233 ms, 8.5% of a render) **had the route been available.** Moot, and flagged as
my own unverified arithmetic.

---

### 10 — Candidate(s) captured this task

`None.` ★ The methodological content here — a route foreclosed by checking a premise against the
code — is already covered by this task's own
`an-optimisations-premise-is-worth-checking-before-its-arithmetic`, captured under T-P0-033 and
still unpushed. ★★ Capturing a second row for the same principle in consecutive tasks would be
duplication rather than a second instance.

★ **Standing:** twelve pool rows remain committed locally and unpushed — `Authentication failed`
on the pool remote for four consecutive tasks (§2C: fire-and-forget, never gates).

---

### 11 — Commit

`ea9e9f5` (pushed to origin/wip)
