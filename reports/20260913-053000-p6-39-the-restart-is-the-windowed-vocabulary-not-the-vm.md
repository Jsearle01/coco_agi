## Form B Report — T-P0-094 / P6.39 — The restart reproduces on demand; the VM is exonerated
**Class:** measurement.  wip.  **No `src/` change.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-13 05:30 (HEAD 7f45daf, wip). Three harness tools modified, one added. Nothing under
`src/`.

### 1 — Summary
★★★★★ **The restart reproduces deterministically and its trajectory is now a sequence, not two
endpoints:** `c0→0  c1→83  c9→1  **c100→0**  c101→83`. **Cycle 100 is exactly the cycle the first
command is fed.**

★★★★★ **The VM is exonerated.** Pointed at the same scenario — same jump, same 400 cycles, the eye
gate's own input script — the per-cycle diff reports **0 divergent cycles of 400, byte-identical on
all 288 bytes**, and guest and reference agree about the room on every cycle. **The reference does
not restart and neither does the VM probe.**

★★★★ **Six arms narrow it to one configuration difference.** It survives the text engine being
modelled, interrupts being off, and `var21` being unset; it vanishes without input, without the
jump, and — decisively — **in the build whose vocabulary is FLAT instead of windowed.**

★★★ **`err 1` is named and closed: it is a CONSEQUENCE.** `PICTURE 0` is an empty DIR slot in
Kingquest1, so when var 0 becomes 0 the room check correctly fails. **Not a defect. Six tasks.**

### 2 — Files modified
- `harness/tools/room_trace.py` — **new.** Room trajectory from the gate's own 288-byte dump.
- `harness/tools/vm_run.ps1` — `VM_ROOM`/`VM_ROOM_AT` and `VM_INPUT_FILE` passthrough.
- `harness/tools/p3b_run.lua` — the room trajectory, the `res_err` watch, one-shot guards.
- `harness/tools/p3b_show.ps1` — `vm_curlogic` in the symbol list.

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| the six artifacts | P6.38's hashes | ✔ all six |
| region A headroom | 1,622 | **1,622** |
| `reg_discipline.py` | 17, one file, four registers | ✔ |
| `p3b_probe.s`'s `$FFA5` | the cel branch only | ✔ unchanged |

★★★★★ **§3(3) and §1.1 CONFIRMED, and the gap is worse than stated.** `vm_run.ps1` never passed a
room to either leg — **yet `vm_stage.py` has had `--room` since P6.36 and `vm_sweep.lua` has read
`VM_ROOM` since P5.3.** Both halves existed and this runner connected neither. **The nine-title gate
has never once covered a forced room jump.**

### 4A — Can the reference run the scenario? ★★★★★ YES

The reference runs the jump, the input and 400 cycles without complaint. §2's warning about the
broken print path did not bite: `vm_stage.py` does not drive `print`, and the six `said()` patterns
that raise are reported and skipped by the scheduler rather than stopping the run.

★★★ **So §4B is a bisection, and it returns nothing to bisect.**

### 4B — The first divergent cycle: ★★★★★ THERE ISN'T ONE

| scenario | cycles | divergent | rooms, both sides |
|---|---|---|---|
| jump, no input | 400 | **0** | `c0→0  c1→83  c8→1` |
| jump + generated input | 212 | **0** | `c0→0  c1→83  c8→1` |
| jump + **the eye gate's own script** | 400 | **0** | `c0→0  c1→83  c8→1` |

★★★★ **Byte-identical on all 288 bytes on every cycle, exclusion set empty, and the room agrees on
all 400.** The VM probe stays in room 1 from cycle 8 to cycle 400.

★★★ **The third row is the one that matters.** The eye script is `--eye --max-lines 3` and is not
what `vm_run.ps1` generates, so "the gate ran with input" and "the gate ran THIS input" are
different statements — `VM_INPUT_FILE` exists now so the distinction is recorded rather than
assumed [§2O.1: one producer].

### 4C — Guest-side attribution: six arms

All with Kingquest1, 400 cycles, and `vm_curlogic` sampled at every transition.

| arm | configuration | rooms | restart? |
|---|---|---|---|
| A | text opcodes **modelled**, jump, input, var21 | `…c9→1  c100→0  c101→83` | ★★★ **yes** |
| B | as A, **no var21** | `…c9→1  c100→0  c101→83` | ★★★ **yes** |
| C | as B, **no input** | `c0→0  c1→83  c9→1` | **no** |
| D | as B, **no jump** (§4E's control) | `c0→0  c1→83` | **no** |
| E | ★★★★★ **the CEL build — FLAT vocabulary** | `c0→0  c1→83  c9→1` | **no** |
| F | as B, **interrupts OFF** | `…c9→1  c100→0  c101→83` | ★★★ **yes** |

★★★★★ **Every transition is made by LOGIC 0** — the game's own dispatcher — with flag 5 clear. So
this is not a stray host write and not a rogue handler: **logic 0 itself decides to leave room 1**,
and it decides differently in the guest than in the reference given the same inputs.

★★★★ **Arms A, B and F rule out the three things that looked likeliest**: the blocking `print` and
its clock advance (modelled, still restarts), the host's per-park `var21` write (absent, still
restarts), and interrupts (off, still restarts).

★★★★★ **Arm E is the discriminator.** Same jump, same script, **the same parse result** — word 161
at cycle 100 and word 160 at cycle 200 in both builds — and **no restart.** The cel build's
vocabulary is flat at $E3BA; the text build's rides an MMU window at **$A000, which is VM_OBJ's
address in this probe.**

★★★ **AC-3, named honestly: the restart belongs to the WINDOWED-VOCABULARY configuration, not to
any of the dispatch's four candidates.** It is not a non-persisting flag (flag 5 is clear at every
transition), not a re-dispatch (logic 0 is the actor in the reference too), not `restart.game`
(`vm_quit` is 0 and `vm_badop` is 0 throughout), and not the harness's jump (arm C).

★★ **What arm E does NOT isolate**, stated rather than glossed: the cel and text builds differ in
more than the window — the relocated `vm_tables.s`, the shortened seed stack, the font's address,
`input.s`. **The next experiment is a text build with a flat dictionary**, which no flag currently
produces.

### 4D — ★★★★★ `err 1`, named and closed

```
PICTURE 0   entry: <PICTURE 0: empty>
PICTURE 0   load : ResourceError: Kingquest1: PICTURE 0 is an empty slot
PICTURE 1   entry: <PICTURE 1: vol 1 @ 0x00664>
```
`RES_E_EMPTY` is 1 and means "the DIR slot is FF FF FF" [`res_core.s:182`]. **Room 0 is not a room;
it is var 0's reset value.** When the restart drives var 0 to 0, `p3_room_check` fetches
`PICTURE 0`, the slot is genuinely empty, and `prc_fail` sets `P3_ERR = 1`.

★★★★ **The oracle would answer identically — it is the same DIR table, and `volread` reads the
game's own bytes.** So `err 1` is not a divergence and not a defect: **it is the probe correctly
reporting that a non-room has no picture.** It appears in every log where the restart appears and in
none where it does not, which is the correlation the six arms above make visible.

★★★ **`res_err` itself is 0 at the end of every run** — a later successful fetch clears it, while
`P3_ERR` is sticky. **Two bytes with similar names and different lifetimes**, and reports have been
quoting the sticky one as though it were live.

### 4E — The harness's contribution

**Arm D is the control: no jump, no restart.** ★★★ But arm C says the jump alone is not sufficient
either — **the restart needs the jump AND a fed command**, which is consistent with the jump simply
putting the game somewhere a command can matter. ★★ **The jump is not the defect**, and this cluster
has not been chasing a measurement artefact.

★★ One real asymmetry: **the reference jumps at cycle 8 and the guest at cycle 9.** Both land, both
dispatch, and the byte diff is clean — so it is the two hosts' arming seams differing by one park,
not a divergence. Recorded because it is visible in every trajectory above.

### 5 — Verdict-time evidence (v0.7 §11)
**25.1 fresh tool output:** §4B's three diffs, §4C's six arms, §4D's resource query, and:
```
p3b        13918 B  58AD3C27164BD63F      p3b_text  16258 B  5B19334FAD8E7AB0
git diff --stat:  harness/tools/p3b_run.lua | p3b_show.ps1 | vm_run.ps1   -- NO src/
```
**25.2 bundled-artifact grep:** N/A.
**25.3 operator-runtime-smoke:** **N/A — nothing was built.** ★★ The scenario under measurement is
the one Jay watched at P6.38 and his sequence is §1's opening quotation.

★★★ **AC-7 discharged by §2T citation, not re-run:** no file under `src/` was touched, `p3b` and
`p3b_text` reassemble to P6.38's hashes above, and the toolchain is unchanged. **The suite's inputs
are unchanged, so its outputs are** [P6.38 §5: pic 45/45, res 1,264/1,264, cel 9,193/9,193, comp
124/124, nine rows green, vm 9/9].

### 6 — Reactive deviations and route accounting
1. ★★★★ **A write tap on var 0 was installed and abandoned.** It would have named the storing PC —
   the strongest form of §4C's answer. **MAME's write tap covers the containing region, not the
   byte**, and $0800 is the VM state block, so a 40-second run had not finished 400 cycles in ten
   minutes. Replaced by `vm_curlogic` sampled at each transition, which is one level coarser and
   free. The dead end is recorded in the source.
2. ★★★ **Three harness tools gained passthroughs** (`VM_ROOM`, `VM_INPUT_FILE`, `vm_curlogic`).
   Each connects two halves that already existed; none changes a default, so the gate is unmoved.
3. ★★ **My first trajectory lines printed inside the hold's repeating block** — the log already
   carries 49,877 copies of "final room" — and were guarded to fire once.
4. **ROUTE ACCOUNTING.** §4A was answered before either branch, as asked. **No fix was attempted**
   and §6's first trigger was never approached.

### 7 — Uncertainty flags

**7.1 ★★★★ Arm E is a two-variable comparison and I have said so.** Flat-versus-windowed is the
most plausible difference on the feed path, but the cel and text builds also differ in the relocated
`vm_tables.s`, the 128-entry seed stack, the font's address and `input.s`. **A text build with a
flat dictionary would settle it in one run and no flag produces one.**

**7.2 ★★★ The mechanism is not established, only the configuration.** The window maps a block over
`$A000`, which is `VM_OBJ` in this probe. Nothing in `par_parse` writes there and the restore is
verified, so **how a correct parse leads logic 0 to a different decision is unexplained.**

**7.3 ★★ The parse results are identical in both builds** — word 161 and word 160, `notfound=0`. So
whatever differs is not what the parser produced, which removes the most obvious explanation and is
why §7.2 is open rather than closed.

**7.4 ★ `vm_quit` is 0 and `vm_badop` is 0** in every restarting arm, so `restart.game` did not
execute and no unimplemented opcode halted anything.

### 8 — Follow-up candidates
1. ★★★★★ **A text build with a flat vocabulary** (§7.1) — one flag, one run, and arm E becomes a
   one-variable result.
2. ★★★★ **Then the mechanism** (§7.2), with the fix dispatched against a named cause as §1.3 intends.
3. ★★★★ **`VM_ROOM` in the gate's own rows.** The nine-title gate has never covered a forced jump
   and the passthrough now exists; **a scenario nobody gates is where this hid for six tasks.**
4. ★★ **`P3_ERR` versus `res_err`** (§4D) — a sticky byte and a live one, quoted interchangeably.
5. ★ **The one-park arming asymmetry** between the two hosts (§4E).

### 9 — User interaction during task
None. ★★ The scenario measured is Jay's P6.38 observation, quoted in §1.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-13-both-halves-existed-and-nothing-connected-them.md`

### 11 — Commit
`0b03007` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `3b7fe1c`, one row under `seeds/AGI/live/`.
