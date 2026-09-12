## Form B Report — T-P0-095 / P6.40 — The vocabulary window is exonerated
**Class:** measurement.  wip.  **AC-9's negative result is the deliverable.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-13 09:00 (HEAD 895ab0a, wip). Two `src/` files, comment-and-flag only; two harness tools;
one doc filed.

### 1 — Summary
★★★★★ **The window is EXONERATED. A text build with a flat dictionary restarts identically.**
`c0→0 · c1→83 · c9→1 · c100→0 · c101→83` — the same five transitions as its control, with the same
parse (word 161 at cycle 100, word 160 at 200).

★★★★ **§1.1's lead does not hold.** `ph_blk_slot5` is $3D, which is exactly what slot 5 holds in the
VM phase, so `phase_vocab_out` restores correctly. **The Orchestrator's previous version of the lead
was wrong too**, and both were caught by the experiment rather than by reasoning.

★★★★ **Two more candidates eliminated as a by-product:** the relocated dispatch tables are
**byte-intact** (0 of 626 differ from what was poked), and **`RES_E_BIG` fires in the
non-restarting build too**.

★★★ **And a previously unreported error is named:** `res_err = 4`, `RES_E_BIG` — *"the payload will
not fit the arena at all"* — at **cycle 8, the jump cycle**, in both builds.

### 2 — Files modified
- `src/harness/p3b_probe.s` — `-DTEXT_VOCAB_FLAT` and the two declaration fixes it needed.
- `src/engine/mmu_phase.s` — **comment only**: §4D's nesting hazard.
- `harness/tools/p3b_show.ps1` — `-FlatVocab`.
- `harness/tools/p3b_run.lua` — the dispatch-table integrity check; two instrument fixes.
- `docs/project/agi-coco3-design-v1.3.md` — filed (§4C).

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| the six artifacts | P6.39's hashes | ✔ all six |
| region A headroom | 1,622 | **1,622** |

**§3(2) `ph_blk_slot5`, both halves, quoted:**
```
mmu_phase.s:81    ph_blk_slot5    fcb     0        ; what slot 5 holds outside that window
p3b_probe.s:1887  P3_BLK_SLOT5    equ     $3D
p3b_probe.s: 476  lda #P3_BLK_SLOT5 / sta ph_blk_slot5
```
**§3(3) what is at `$A000`:** `VM_OBJ equ MAP_PRI_SLICE` = $A000, in block **$3D** — the host
pre-sets every slot to `$38+i` at load. ★★★★ **So `ph_blk_slot5` = $3D IS what slot 5 should hold,
and §1.1's "a fixed byte that may be wrong" is not wrong here.**

**§3(4)** ★★★ **The spec was NOT at the repo root.** It was already at
`docs/project/agi-coco3-design-v1_3.md` — right directory, underscore naming — so there was nothing
to delete. Renamed to the dotted form; §4C's goal reached by one move rather than two.

### 4A — ★★★★★ THE ONE-FLAG EXPERIMENT: the window is exonerated

`-DTEXT_VOCAB_FLAT` stages the dictionary at a fixed address and never calls `phase_vocab_in`/`_out`.
**Everything else in the text configuration is kept** — the relocated `vm_tables.s`, the 128-entry
seed stack, the font at $E3BA, `input.s`, the four-slot text window.

| arm | build | rooms |
|---|---|---|
| B (control) | text, print modelled, **windowed** | `c0→0 c1→83 c9→1 **c100→0** c101→83` |
| **G (new)** | text, print modelled, **FLAT** | `c0→0 c1→83 c9→1 **c100→0** c101→83` |

★★★★ **15 bytes apart** — 15,382 against 15,367 — which is the two `jsr`s and the block setup.
**One variable, and the restart is on both sides of it.**

★★ The arm's dictionary sits at $EBBA-$FEF0 = **4,918 bytes**, which holds Kingquest1's 3,144 and
**not** the corpus maximum of 6,828. It is measurement-only, in no gate row, and carries its own
smaller assertion rather than inheriting one it would fail.

### 4B — Not applicable, and what was measured instead

§4B's three reads were conditional on the window being implicated. It is not. ★★★ **Two things were
measured anyway because they eliminate candidates:**

1. ★★★★★ **The relocated dispatch tables are intact.** `vm_tables at $0200..$0471: 0 of 626 bytes
   differ from what was poked.` **This was the strongest remaining candidate** — 626 bytes of
   `VMOP_TAB` living inside the region the engine's map calls the flood-fill seed stack — and a
   corrupted entry would have been latent until a fed command reached the damaged opcode, which is
   exactly the shape of the symptom. **It is not that.**
2. ★★★★ **`RES_E_BIG` at cycle 8 is common to both.** It fires in the restarting build once and in
   the **non-restarting** build three times (cycles 8, 9, 10). **Not the discriminator.**

### 4C — The spec, filed

```
docs/project/agi-coco3-design-v1.1.md   85,223
docs/project/agi-coco3-design-v1.2.md   95,132
docs/project/agi-coco3-design-v1.3.md  113,257   <- filed here
```
★★★ **The untracked list is now one file:** `coco_agi.code-workspace`. The body was not read, edited
or reconciled [§2D].

### 4D — The nesting hazard, recorded

★★★★ **`phase_vocab_out` and `phase_text_out` do not nest, and neither `_in` saves anything.** A
parse inside an open text window would put the object table's block back where the framebuffer
belongs. ★★★ **Unreachable today** — the oracle's order is parse-then-redraw [`text.cpp:782-793`]
and `txt_pkey` follows it — so it is a comment beside `phase_vocab_out`, not a guard.

### 5 — Verdict-time evidence (v0.7 §11)
```
p3b        13918 B  58AD3C27164BD63F    p3b_notick 16255 B  F7AE0FCFBF0BB3F0
p3b_text   16258 B  5B19334FAD8E7AB0    p3b_nomap  16255 B  9604AAAA121CA3D3
p3b_win3   16258 B  5400A30F609A52B5    p3b_fault  15382 B  16DC35EF28CF1193
                                        p3b_flat   15367 B  E7882A33A1950091  (new)
git diff --stat -- src/ :  mmu_phase.s +14 (comment only) | p3b_probe.s +55
[reg-discipline] 17 access(es) in 1 file(s) over 4 register(s)
```
★★★★ **All six shipped artifacts byte-identical**, so AC-5 and AC-6 hold and **the `src/` delta is
the flag plus one comment block**.
**25.2:** N/A. **25.3:** N/A — nothing shipped changed.
★★★ **AC-7 by §2T citation to P6.38/P6.39:** six artifacts unchanged, toolchain unchanged, so the
suite's inputs are unchanged [pic 45/45, res 1,264/1,264, cel 9,193/9,193, comp 124/124, nine rows,
vm 9/9].

### 6 — AC-4: what remains, ranked

Arm E (cel, no restart) versus arm B (text, restart). Interrupts, `var21`, the text engine, the
window, the tables and `RES_E_BIG` are all eliminated. **Four differences remain:**

| rank | difference | what would distinguish it |
|---|---|---|
| ★★★★ 1 | **`input.s` linked and `HAL_input_init` called** (`-DHAL_KEYBOARD`) — it writes PIA0's control registers | **The cel build WITH `-DHAL_KEYBOARD`.** One flag, one run, and it is the only remaining single-flag step |
| ★★★ 2 | **`text.s` linked at all** — even modelled it occupies the code region and moves every address above it | A text build with `text.s` excluded; no flag produces one |
| ★★ 3 | **The seed stack at 128 entries** rather than 384 | `SP_PEAK` against 128. ★ The run completes and `ff_push` HALTS on overflow, so no overflow occurred — **this is ranked low on evidence, not on taste** |
| ★ 4 | **The font staged at $E3BA** | Not staging it; it is 2,048 host-poked bytes into a region the cel build fills with its dictionary |

★★★★ **Rank 1 is the one to run next**, and it is genuinely one flag.

### 7 — Uncertainty flags

**7.1 ★★★★ Two instrument defects were found and fixed, and one of them was mine from P6.39.**
The `res_err` tap captured the cycle from `n` — but `stage()` is defined **above** `local n`, so the
closure read a **global** of that name, which is nil. `string.format` then threw, **the frame
callback died silently**, and the run completed with the log stopped mid-summary. ★★★ **The missing
lines read as "the check did not fire"** rather than as "the check killed the reporting". Now read
from the guest's own `P3_CYCLE`.
★★ **The `par_vocab` tap has the same latent bug** and only shows on the stall path.

**7.2 ★★★ `RES_E_BIG` at cycle 8 is unreported and unexplained.** *"The payload will not fit the
arena at all"* on the jump cycle, in every arm. It is not this task's cause, but a resource that
cannot be loaded at room entry is not nothing, and **six tasks of logs have not mentioned it** —
because `res_err` is overwritten by the next success and only `P3_ERR` survives.

**7.3 ★★ The flat arm is one title wide.** 4,918 bytes holds Kingquest1 and not SpaceQuest-2.
Reproducing the restart on a second title would need the windowed build.

**7.4 ★ `ph_blk_slot5` is correct here and the lead was still worth having** — checking it is what
produced §3(2)/§3(3), which is the evidence that `$A000` is block $3D.

### 8 — Follow-up candidates
1. ★★★★★ **The cel build with `-DHAL_KEYBOARD`** (§6 rank 1). One flag, one run.
2. ★★★★ **`RES_E_BIG` at the jump cycle** (§7.2) — which resource, and does the reference load it?
3. ★★★ **Fix the `par_vocab` tap's captured `n`** (§7.1) before it costs a stall investigation.
4. ★★★ **`VM_ROOM` in the gate's own rows** — still queued, still where this hid for six tasks.
5. ★★ **`res_err` versus `P3_ERR`** — the live byte is worth publishing, not only the sticky one.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-13-the-diagnostic-that-killed-the-report-it-belonged-to.md`

### 11 — Commit
`d2824fd` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `c95365d`, one row under `seeds/AGI/live/`.
