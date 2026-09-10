## Form B Report — P6.28d (T-P0-084d) — the panel fills, with ciphertext
**Class:** integration (§4A) — **AC-1 FAILED; stopped with the cause named.**  wip.

★★★★★ **The scroll panel is no longer black. Jay: *"there was scrolling text. but the text was garbage
(unreadable) and it was too wide and overran the box"*.** The wiring works end to end — `display`
fires, the flat window blits, glyphs reach rows 6–18 — and **what it renders is wrong.**

★★★★★ **One cause explains both symptoms, and it is named rather than guessed:
`res_decode` is called by `res_probe.s` and by nothing else.** `vm_bind_logic` calls `res_open` and
never decodes, so on the LOGIC path **the message strings are still XOR-encrypted with "Avis
Durgan"**. `display` is faithfully rendering ciphertext: unreadable glyphs, and a ciphertext string
carries no spaces and no meaningful terminator position, so it overruns the box.

★★★★ **AC-2 passed first and Jay confirmed it: *"yes same as before. middle panel black"*.** The
fault arm is a build, not a reconstruction — its table entries resolve to the same address the
pre-wiring probe used — which is why "same as before" is the right thing to have heard.

---

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-084d dispatch receipt (HEAD `7bb2163`, wip; descends from `469921e` as expected).
At report time HEAD `c86a709`. `git status` clean but for `coco_agi.code-workspace` (untracked).

---

### §4 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi ===        7bb2163  wip   ?? coco_agi.code-workspace
=== POP3_port ===       104b197  wip   (no tracked modification)
=== karateka_coco3 ===  29f8f0a  wip    M harness/smoke/last-run.log

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, ...)

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s     8    $FFA5 $FFA6

=== p3b_probe.bin pre-strip ===
13925 B  F51FF8482D0B07E49F46B18612D20B06

=== gen_vm_tables.py --check ===
CHECK OK: src/harness/vm_tables.s matches optable.py.

=== collision guard from 469921e, live ===
L927: ifgt    P3_CODE_END-MAP_RESERVED_END
L943: ifgt    P3_CODE_END-CP_CEL
```

★★ **§2T citation, P6.28c §3's caveat carried forward unchanged.** Both siblings are at **the same
refs P6.28c §3 recorded**, read at their **`wip` working trees**, not a public ref (§2S). Neither
has a tracked source modification.

**The nine entries, before:** all nine `vm_op_modelled` at lines 239–251, verbatim as in P6.28c §3.
★ **No contradiction; proceeded.**

---

### 1 — Summary

Three commits landed. The strip (`d45cc28`) re-baselined the gate; the wiring (`6dd5450`) moved both
legs together; the plumbing (`c86a709`) gave the gate a font and a runner. **AC-2 passed and Jay
confirmed it. AC-1 failed, and the failure is diagnosed to a single missing call.**

### 2 — Files modified

- `src/harness/p3b_probe.s` — `-DP3B_NO_CEL`; `P3_PBUF`, `P3_FONT`; text-engine pointer init; three
  new assertions.
- `src/harness/vm_text_ops.s` — **NEW.** Nine handlers, `TEXT_WIRED` / `TEXT_MODELLED` toggles.
- `src/harness/vm_tables.s` — regenerated; nine entries bound.
- `src/harness/vm_probe.s` — includes `vm_text_ops.s` (emits nothing; AD-176).
- `tools/agivm/cycle.py` — `TextRenderer` instantiated; `text_state()`, `text_render()`.
- `tools/agivm/commands.py` — nine `@_impl()` functions; nine names out of the MODELLED list.
- `harness/tools/p3b_run.lua` — font staging into `P3_FONT`.
- `harness/tools/p3b_show.ps1` — `-Text`, `-Fault`, `P3_FONT` in the symbol list.

### 3 — Reasoning

**3.1 ★★★★★ The diagnosis, and why it is one cause and not two.**

```
=== who calls res_decode? ===
res_probe.s:127: jsr     res_decode
=== does the VM bind path decode? ===
vm_run.s L57:  jsr     res_open        (vm_bind_logic)
vm_run.s L182: jsr     res_open
```

★★★★ **`res_decode` has exactly one caller in the tree and it is the resource gate's own probe.**
`res_core.s`'s header states the contract: *"the games run unmodified, so there is no conversion step
in which a host could pre-decrypt anything. The 6809 receives Sierra's bytes and must make text out
of them"* — and the strings region is XORed with an 11-byte key. **Nothing performs that XOR on the
path a LOGIC takes into the VM.**

★★★ **Both of Jay's symptoms follow from that one fact.** Ciphertext bytes are arbitrary, so they
index arbitrary glyphs — *"garbage (unreadable)"*. And ciphertext contains no spaces at the positions
a wrap needs and no early terminator, so `txt_wrap` cannot break lines where a reader would expect:
*"too wide and overran the box"*. **A wrapping defect and a decryption defect present identically
here**, which is why the second symptom is not evidence of a second bug.

**3.2 ★★★★ This is §4A.1's claim, produced again.**

`res_decode` is **gated** — `res_probe.s` exercises it and the `res` gate is green in this very run.
`text.s` is **gated** — AD-155, 9/9 titles, 293,648 glyphs. ★★★ **Both components are correct and
the glue between them does not exist**, which is exactly *"a byte gate cannot find a defect in the
glue BETWEEN the things it gates"*. ★★ **No byte gate in this project could have found this**, and
the eye gate found it on its first run — the third time §4A has paid for itself.

**3.3 ★★★★★ The fix has a hazard, which is why it is not in this commit.**

The apparent repair is `jsr res_decode` after `res_open` in `vm_bind_logic`. ★★★★ **`res_decode`
XORs IN PLACE, and `res_open` serves cached resources** (`res_cache_find` / `res_cache_stash`, and
L-66 measured a LOGIC being re-bound 3.01 times per cycle). **Decoding on every bind would
re-encrypt every cached hit** — the first bind correct, every later one garbage.

★★★ **That failure would be worse than the present one**: correct on the first room and wrong later,
i.e. a defect a room away from its cause, which is this project's signature shape and exactly what
`p3b_probe.s:980` already records happening once. ★★ **Decode belongs on the cache-MISS path inside
`res_open`, or behind a per-resource "decoded" flag** — an engine change with cache semantics, and a
ruling rather than a one-liner.

**3.4 ★★★★ Ruling 3's flat window was verified before the blit path was trusted, and it holds.**

`-Text -Headless`: **120 cycles, no stall, final room 83, err 0.** The two hazards it carries were
designed around rather than discovered:

- ★★★ **Slot 4 is the arena's high half and the message text is bytes of a LOGIC in the arena** — a
  10,964 B resource at the arena base reaches `$8AD4`. **So substitution runs first with the arena
  mapped, and the blit reads only `txt_pbuf` at `$1C00` in slot 0.** The buffer §2V sized for %-code
  substitution is also the isolation this needs; **recorded as luck, not as design.**
- ★★★ **The MMU registers are write-only**, so there is no save/restore. Restoration is by known
  value: `p3b_run.lua:345` pre-sets all eight slots to `$38+i` and `mmu_phase.s` never touches slot 4,
  so it is `$3C`.

★★ **`$FFA4` has no sanctioned owner.** `mmu_phase.s` manages slots 5 and 6 only, so
`vm_text_ops.s` is now the second writer of the MMU register file — a §2N ownership question,
**reported not settled**. It is in `src/harness/`, so the `src/engine` census stays at 8.

**3.5 ★★★★ AD-179's class recurred and cost a run.**

The font was first pointed at `MAP_FONT` (`$E0B8`). ★★★ **This probe orgs the parser at `$E000`**
(slot 5 is its priority slice, so the engine's vocabulary window is unavailable here), so `$E0B8` is
**184 bytes into parser code**. Staging 2,048 bytes there overwrote the parser: `★★★ STUCK in cycle
6`. Moved to `P3_FONT = MAP_RESERVED_END-2048 = $5800`, in slot 2, with its own collision assertion.

★★★ **Second instance in two tasks of an ENGINE address reused inside a probe whose own map already
claimed it** — `CP_CEL` was the first. `memmap.inc`'s header says the harness keeps its own
addresses, and **both times the thing that bit was taking an engine constant at face value.**

**3.6 ★★★ AD-176 bit immediately, and the fix emits nothing.**

The first wired build broke `p3b`'s default configuration *and* `vm_probe.s` with `Undefined symbol
vmop_print` — the generated table names the nine labels in every build. `vm_text_ops.s` is now
included **unconditionally** and takes a nine-`equ` branch unless `TEXT_WIRED`. ★★ `equ` emits no
bytes, so both keep their hashes: p3b default `F51FF848…`, `vm_probe` `EC8991A5…`.

**3.7 ★★ Idiom 19j, observed rather than cited.** The p3b gate runs the Python oracle trace, so
`cmdDisplay` now renders in the reference — **and the nine-title diff did not move.** ★★★ **That is
the predicted result and it is not evidence of anything about the wiring**; the eye gate is.

★ One corroborating instrument read, offered as corroboration only: the per-cycle SUM went
**0.12244 s (fault) → 0.17322 s (wired)**, consistent with `display` doing work.

**3.8 ★★ Authority tier.** No ScummVM or Specs claim. The XOR contract is quoted from `res_core.s`,
which cites `logic.cpp decodeLogic` and `global.cpp:311-316`.

### 4 — Verification (AC-by-AC)

★ **Per L-112, each AC names what observed it. AC-1 and AC-2 are eye-gated by Jay; nothing else is.**

- **AC-1 [eye gate — Jay]** ★★★★★ **FAILED.** Jay: *"there was scrolling text. but the text was
  garbage (unreadable) and it was too wide and overran the box"*. **The panel fills; the content is
  ciphertext** (§3.1). Launch path: `poke`, RGB, throttled, `P3B_ROOM=83`, 120 cycles ≈ 21 s plus a
  12 s hold — **more than one full redraw cycle** [AD-156].
- **AC-2 [eye gate — Jay — ran first]** ★★★★★ **PASSED.** `-DTEXT_MODELLED` at room 83; Jay: *"yes
  same as before. middle panel black"*. ★★ **Adjudicated and confirmed before the wired arm ran**
  [L-113].
- **AC-3 [byte-comparable · SHA-256]** ★★★ **PASSED.** Re-baseline from the post-strip, pre-wiring
  build: **12,744 B `1B7C900C063CA66126CDC8FF94B83643`**. `git diff --stat HEAD -- src/hal/
  src/engine/pic_*.s src/engine/res_*.s src/engine/composite.s` is **empty** — only harness files and
  the two reference files changed.
- **AC-4 [state-comparable · grep]** ★★★ **PASSED.** Before: all nine `vm_op_modelled`. After:
  `$65 vmop_print`, `$66 vmop_print_f`, `$67 vmop_display`, `$68 vmop_display_f`,
  `$69 vmop_clear_lines`, `$6C vmop_set_cursor_char`, `$6D vmop_set_text_attribute`,
  `$70 vmop_status_line_on`, `$71 vmop_status_line_off`. **Zero remain `vm_op_modelled`.**
  ★★ **Full implementations:** `display`, `display.v`, `print`, `print.v`. **Stubs (bare `rts`):**
  the other five — none is needed to reach the scroll panel, and the Python leg counts them rather
  than rendering so the two legs stay the same program.
- **AC-5 [byte-comparable · assembler]** ★★★ **PASSED.** Wired `P3_CODE_END = $5597` against
  `MAP_RESERVED_END = $6000` — **2,665 B spare**. Three assertions live: span, `CP_CEL` (conditional
  on the buffer existing), and `P3_FONT`. ★★ The `CP_CEL` guard was **seen to fire** in P6.28c and
  the `ifdef CP_CEL` reverse guard is new here.
- **AC-6 [byte-comparable · SHA-256]** ★★★ **PASSED.** Wired **14,589 B
  `14EBADB65C0DD2D0F0EE6EBE53A7720B`**; fault **14,348 B `3BC9966FE3811A8A1F52FB6157C3C0A7`**.
  Distinct.
- **AC-7 [suite · byte gates]** ★★ **PASSED.** `★ gates run: pic res cel comp p3b -- all green`;
  `hal_sync_check.py` OK ×3; `reg_discipline.py` 8 in `mmu_phase.s`; `gen_vm_tables.py --check`
  **CHECK OK** after wiring.
- **AC-8 [byte-comparable · runner]** ★★ **PASSED.** Every run from `p3b_show.ps1`
  (`-Text` / `-Fault` / `-Headless`); no hand-typed MAME line. ★ Vocabulary: `par_vocab $E000`,
  `P3_VOCAB $E3BA`, staged by `p3b_run.lua` from the stage directory as before.
- **AC-9** One candidate; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).** §4's grep is above.

```
=== AC-3 re-baseline (post-strip, pre-wiring) ===
12744 B  1B7C900C063CA66126CDC8FF94B83643
Symbol: P3_CODE_END = 4E62   MAP_RESERVED_END = 6000

=== AC-6, the two arms ===
WIRED   14589 B  14EBADB65C0DD2D0F0EE6EBE53A7720B   P3_CODE_END = 5597
FAULT   14348 B  3BC9966FE3811A8A1F52FB6157C3C0A7

=== unchanged, byte-identical ===
p3b default (cel)  13925 B  F51FF8482D0B07E49F46B18612D20B06
vm_probe            9660 B  EC8991A52A09C27BD502E4A480DB75C1

=== AC-4, the nine after wiring ===
fdb vmop_print              ; 65 print(s)
fdb vmop_print_f            ; 66 print.v(v)
fdb vmop_display            ; 67 display(nns)
fdb vmop_display_f          ; 68 display.v(vvv)
fdb vmop_clear_lines        ; 69 clear.lines(nns)
fdb vmop_set_cursor_char    ; 6C set.cursor.char(s)
fdb vmop_set_text_attribute ; 6D set.text.attribute(nn)
fdb vmop_status_line_on     ; 70 status.line.on()
fdb vmop_status_line_off    ; 71 status.line.off()

=== ruling 3's flat window, verified headless before the blit path was trusted ===
   P3_FONT          $5800
   font 2048 bytes -> P3_FONT $5800
   program 14589 bytes: 13719 at $2000 + 870 at $E000 (the parser, org'd)
   ★ 120 cycles in 22.2787 emulated s
       final room 83, sprites 0, err 0, status=$00
   ★ p3b headless: 120 cycles, no stall

=== the first attempt, with the font at MAP_FONT ($E0B8, inside parser code) ===
   ★★★ STUCK in cycle 6 after 1800 frames (30.0 emulated s) -- most-visited PCs:
   ★★★ p3b FAILED -- no completion line; the run did not reach 120 cycles

=== the diagnosis ===
who calls res_decode?   res_probe.s:127: jsr res_decode        (and nothing else)
vm_bind_logic:          vm_run.s:57      jsr res_open          (no decode)

=== suite ===
★ gates run: pic res cel comp p3b  -- all green
CHECK OK: src/harness/vm_tables.s matches optable.py.
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; these are harness binaries.

**25.3 operator-runtime-smoke — THE EYE GATE.**

**Invocation** (both arms, `p3b_show.ps1`, RGB, **no `-nothrottle`** [§2U.2]):

```
$env:P3B_ROOM="83"
powershell -File harness\tools\p3b_show.ps1 -Fault -Hold 12      # AC-2
powershell -File harness\tools\p3b_show.ps1 -Text  -Hold 12      # AC-1
```
which assembles with `-DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED
-DP3B_NO_CEL [-DTEXT_MODELLED]` and launches
`mame coco3 -window -nomaximize -skip_gameinfo -rompath C:/mame/roms -cfg_directory harness\mame-cfg
-autoboot_script C:/Projects/coco_agi/harness/tools/p3b_show.lua -autoboot_delay 0`.
★ **Launch path: `poke`** — the image is poked into RAM and PC set from Lua after DECB's OK prompt.
**Not `live-disk`; this gate does not certify load or launch.**

**AC-2, fault arm, run first.** `var0=83 vm_cycle=120 res_err=0`, held 12 emulated s.
**Jay: *"yes same as before. middle panel black"*.**

**AC-1, wired arm.** `var0=83 vm_cycle=120 vm_badop=$00 res_err=0`, held 12 emulated s.
**Jay: *"there was scrolling text. but the text was garbage (unreadable) and it was too wide and
overran the box"*.**

★★★ **So: the panel filled, and it filled with the wrong thing.** §2P: no screenshot and no rendered
text is committed; Jay's description is the record.

### 6 — Reactive deviations and route accounting

**Deviation 1 — the strip is a build flag, not a deletion.** Ruling A calls it *"a probe
configuration, not an engine change"*, so `-DP3B_NO_CEL` keeps the default build byte-identical and
restores cel by dropping a flag rather than reverting a commit.

**Deviation 2 — `vm_text_ops.s` is included by `vm_probe.s` too.** Forced by AD-176 and not in the
dispatch's file list; without it that gate does not assemble.

**Deviation 3 — `P3_FONT` instead of `MAP_FONT`** (§3.5), after the first choice hung the run.

**Deviation 4 — a fourth commit.** §10's sequence has three; the plumbing (font staging, runner
switches) is its own commit (`c86a709`) because it is harness work, not wiring, and folding it into
the wiring commit would have made that commit's hashes unreproducible.

**ROUTE ACCOUNTING.** ★★★★ Scope **A** and **B** are complete and committed. **C ran and AC-1
failed.** §11's design-spec edit is **NOT** made — it is conditioned on the eye gate passing, and it
did not. ★★★ **The dispatch's commit 3 ("eye gate: KQ1 scroll panel fills — Jay confirmed") does not
exist**, because the panel fills with ciphertext and claiming otherwise would put a false statement
in the log.

★★★ **I did not attempt the fix.** No trigger names "renders, but wrong"; the nearest, trigger 2,
directs naming the responsible opcode and stopping, and §3.3 shows the obvious repair would corrupt
cached binds. **A speculative one-liner here produces a defect a room away from its cause.**

### 7 — Uncertainty flags

1. ★★★★ **The diagnosis is a call-graph fact plus an inference, not a byte-level observation.** That
   `res_decode` has one caller is verified; that the bytes reaching `txt_dispch` are ciphertext is
   **inferred** from it and from the symptoms. ★★ **A dump of the message region as the blitter sees
   it would settle it**, and was not taken.
2. ★★★ **The wrap symptom is attributed to the same cause and could be its own defect.** §3.1 argues
   ciphertext has no spaces to wrap at; **if the text decodes and still overruns, the wrap is a second
   finding** and this report will have been half right.
3. ★★★ **Where decode belongs is unresolved** (§3.3) — bind path, `res_open` miss path, or a
   per-resource flag. Each has different cache semantics.
4. ★★ **`$FFA4` has no sanctioned owner** (§3.4).
5. ★★ **`PRI_PACKED` was still not evaluated** — §2 asked whether the stripped configuration needs it.
   The framebuffer window changed but the priority plane is untouched by the text path, so it was
   left alone rather than tested.
6. ★★ **`print` does not block, on either leg** — stated in both files. A title screen that calls
   `print` gets a box drawn and no wait, which is not what the engine does.
7. ★ **I corrupted `harness/tools/p3b_run.lua` mid-task** by editing it through PowerShell (a BOM and
   129/105 line churn for a 3-line change), against my own standing rule. Reverted with `git
   checkout` and redone with the editor; the committed diff is 26 insertions. **No corrupted bytes
   reached a commit.**

### 8 — Follow-up candidates

- ★★★★★ **The ruling this report asks for: where `res_decode` is called from.** The cache-miss path
  inside `res_open` is the obvious home; a per-resource decoded flag is the alternative.
- ★★★ **Discharge §7.1** — dump the bytes at the resolved message pointer and confirm they XOR to
  printable ASCII. ★★ §2P: report the **property**, not the text.
- ★★★ **Re-run AC-1 after the decode lands**, and see whether §7.2's wrap symptom survives.
- ★★ **`$FFA4`'s owner** (§3.4) and **`PRI_PACKED`** (§7.5).
- ★★ **`print`'s missing key-wait** (§7.6) once an input path exists in this probe.

### 9 — User interaction during task

Jay adjudicated both eye-gate arms, in order:
- **AC-2:** *"yes same as before. middle panel black"*
- **AC-1:** *"there was scrolling text. bu the text was garbage (unreadable) snd it was too wide and
  overran the box"*

### 10 — Candidate(s) captured this task

One, to `seeds/AGI/live/`:

- `2026-09-09-two-gated-components-with-no-glue-between-them`
  — *initiator: executor*. Both `res_decode` and `text.s` are gated and green; the call that joins
  them was never written, so the integrated path rendered ciphertext while every byte gate passed.
  The eye gate found it on its first run.

### 11 — Commit

`d45cc28` (strip + re-baseline), `6dd5450` (nine opcodes, both legs), `c86a709` (font staging and
the runner) — pushed to origin/wip before this report. ★★ **No eye-gate commit**: AC-1 failed.
