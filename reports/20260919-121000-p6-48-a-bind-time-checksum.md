## Form B Report — T-P0-103 / P6.48 — A bind-time checksum: resource bytes are gated after the bind
**Class:** integration (§4A).  wip.  Descends from `7b58a87`.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-19 12:10 (HEAD 7b58a87, wip). Two `src/harness/` files changed and one added, all behind
`-DRES_CHECKSUM`; three harness tools changed, three added.

### 1 — Summary

★★★★★ **The gap P6.46 named is closed: resource bytes are now checked after the bind, and the
instrument reproduces P6.46's answer from a fault arm without being told what to look for.**

```
clean   12 baselined, 1,586 verified, 0 mismatches, 1 sweep skip
fault    8 mismatches, LOGIC 102 at $63F0, checksum +$B40F per cycle, constant
        res_copy_diff.py: 8 of 2,315 offsets, gaps [1, 1, 9, 9, 1, 16, 31]
```
★★★★★ **That gap sequence is byte-for-byte P6.46's**, offsets shifted +2 because this dumps the
resource and P6.46 snapshotted the bytecode.

★★★★★ **AC-4 is answered and the answer is NOT the standing explanation.** The largest decoded cel
in **Kingquest3 is 4,784 bytes — exactly the corpus maximum, and 1,456 past the margin**, which is
precisely the CP_CEL/arena overlap. larry1 has three such cels. **"Real cels are far smaller than
the corpus maximum" is true for three of five titles and false for two.**

★★★★★ **And §1.2's decode trap is real but was the SECOND trap, not the first.** The instrument's
own reporting path was wrong three times and produced **eight confident, fully-populated mismatch
rows on a clean run** before it was right (§6.1).

### 2 — Files modified
- `src/harness/res_check.s` — **new**, entirely inside `ifdef RES_CHECKSUM`. Baseline/verify/
  release/sweep, Fletcher-16, tables in `MAP_COVERAGE`.
- `src/harness/vm_run.s` — the bind hooks, split across the carry's two arms.
- `src/harness/p3b_probe.s` — the include, the VIEW hooks, `res_ck_init`, MODE 4,
  `-DP3B_ACCEPT_COV_ARENA`.
- `harness/tools/p3b_show.ps1` — `-ResCheck`, `-CovFault`.
- `harness/tools/p3b_run.lua` — arming, the raw dump, detection-time byte capture, the sweep park.
- `harness/tools/gates.manifest` — the `p3b_rescheck` row **and its four blind spots**.
- `harness/tools/res_copy_diff.py` — **new.** Offsets, deltas and gaps from a dump.
- `harness/tools/cel_extent.py` — **new.** §4D's offline answer.

### 3 — Pre-dispatch grep (C-13)

**§3(1)** Seven arms and every non-`p3b` probe at P6.47's figures ✔ — **SHA-256**, as the checkers
now record.

**§3(2) — EVERY WRITE PATH INTO `RES_ARENA`. This is the task's real subject and it had never been
enumerated.** In `p3b` the window is `$6000`–`$A000`:

| writer | legitimate? |
|---|---|
| `res_fetch`'s copy | ✔ the load itself |
| `res_decode` (LOGIC message section, in place, once) | ✔ **and it is §1.2's trap** |
| `res_cache_stash`'s relocation into the cache region | ✔ |
| ★★★★ **`vc_decode_cel` → `CP_CEL` `$5300`–`$65B0`** | ✘ **1,456 bytes into the arena — §4D** |
| `VM_OPSEEN`/`VM_TESTSEEN` `$6300`/`$6400` | ✘ **fixed at P6.47** |
| ★★★ **`vmtr_buf equ $6500`** [`vm_core.s:784`] | ✘ **dormant: no `p3b` arm defines `VM_TRACE`** |
| ★★★★ **`TX_WIN equ $6000`** [`vm_text_ops.s:79`] | ✔ **BY PHASE ONLY** — see below |

★★★★★ **`TX_WIN` is the one this grep was worth doing for.** The text engine writes glyphs at
`$6000` and up, and it is safe **only because `phase_text_in` has remapped slots 3-6 to framebuffer
blocks first**. The arena and the text window are the same addresses in different phases. Nothing
asserts that ordering; §2R.1's "declare the mapped pair before entering a phase" is the whole
guarantee, and **a text write with the arena still mapped would scribble resource bytes.** The
instrument would now catch it.

**§3(3)** Binds: `res_open`'s hit path returns **C set**, the miss path **C clear** — the signal
§4A needed already existed. `vm_bind_logic` consumes it at `vm_run.s:83`.

**§3(4)** The cache is four parallel arrays (`res_ckey`/`res_caddr`/`res_clen`, `res_cn`) — the
natural shape, and `res_cache_find` is what the sweep uses to confirm an entry is still live.

### 4A — ★★★★★ The baseline point, and why it is right rather than convenient

**At `vm_run.s`'s `vbl_nodec`** — where a LOGIC's bytes are final on **both** paths.

★★★★ **It is the seam the resource gate is already aligned to**, chosen four phases earlier for the
same reason: the oracle's raw dump is taken "immediately after loadVolumeResource() returns and
BEFORE any decode" [agi.cpp:456, P1.1], and the decode is `if (~flags & RES_LOADED)` — **once per
load, by the oracle's own structure.** A resource decoded twice is a defect in either
implementation, so "after exactly one decode" is a well-defined instant and not a moving target.

★★★★ **The carry already separates the two cases**, so no new signal was needed: fresh → NOTE,
cached → VERIFY. **The hooks go on the two arms rather than at the join**, because `jsr res_decode`
destroys the carry before `vbl_nodec`.

**The blind spots, in the same breath** [L-121], and all four are in the source and the manifest:
1. **Between the fetch and the baseline is invisible** — it is baselined *as* the truth.
2. **PICTURE and SOUND are not watched** — no call site notes them.
3. ★★★★ **The cel arm cannot run it at all** (§6.2).
4. **A stale entry is skipped, not reported** — the sweep asks `res_cache_find` first, and **counts
   the skips** so a narrowing is visible [L-88].

### 4B — The implementation

Fletcher-16, not a sum: a plain sum cannot see two bytes swapping, nor a +1 and a −1 in the same
resource. **Whole resources, never sampled** — §1.1 says cost is not the constraint here.

**Tables in `MAP_COVERAGE`** — the 512-byte slot-7 region T-P0-102 declared and `p3b` then declined.
Slot 7 is required, not convenient: these are written from the VM phase *and* the draw phase.
`res_ck_init` zeroes it, because it is not part of the poked image.

★★★★ **The byte dump happens at DETECTION, in the park loop.** The first version dumped at readout
and `res_copy_diff.py` reported **3,549 of 3,817 bytes differing** — a confident answer about memory
the arena had since reused.

### 4C — ★★★★★ RED, against a known answer

`-ResCheck -CovFault` puts the counters back at `$6300`/`$6400`. **`-DP3B_ACCEPT_COV_ARENA` is a
named bypass for P6.47's assertion**: the two §2W obligations otherwise contradict — the assertion
may not be weakened, and the checksum may not be believed until it has been seen red on a real
corruption.

```
res-checksum: 18 baselined, 1280 verified, 8 mismatch(es), 2 sweep skip(s)
  type 0 index 102 at $63F0 len 3817  expected $007E got $B48D  (later bind, cycle 11)
  ... $689C, $1CAB, $D0BA, $84C9, $38D8, $ECE7 -- a constant +$B40F per cycle
```
★★★ **The constant per-cycle delta is the histogram signature**, and the offsets confirm it:
`$0012 $0013 $0014 $001D $0026 $0027 $0037 $0056`, gaps `[1,1,9,9,1,16,31]`.

### 4D — ★★★★★ §7.2 answered: does `CP_CEL`'s overlap corrupt anything?

**`CP_CEL` = `$5300`, `RES_ARENA` = `$6000` → 3,328 bytes of margin.** A decoded cel is width×height
bytes. `cel_extent.py`, over the game files:

| title | largest cel | cels over the margin |
|---|---|---|
| Kingquest1 | 1,242 | 0 |
| Kingquest2 | 1,650 | 0 |
| ★★★ **Kingquest3** | **4,784** | **1** |
| ★★★ **larry1** | **4,592** | **3** |
| PoliceQuest1 | 2,496 | 0 |

★★★★★ **The 4,784-byte "corpus maximum" is not a safety margin — it is Kingquest3 view 64, loop 0,
cel 0, and it overruns the arena by exactly 1,456 bytes**, which is the overlap P6.47 computed.

★★★★★ **AND THE VICTIM IS THE VIEW ITSELF.** `res_top` starts at `RES_ARENA`, so the first transient
lands at `$6000`; `p3_composite_all` fetches the VIEW there and then decodes **from** it **into**
`CP_CEL`. A cel past the margin overwrites the source it is still reading.

★★ **Dormant for Kingquest1**, which is why every `p3b` cel run to date has been clean — L-86's
fixed sample, again. **Named, not fixed** (§6, §10).

### 4E — The row
`p3b_rescheck`, with all four blind spots and the scenario it is red under [P6.47 §6.4's lesson].

### 5 — Verdict-time evidence (v0.7 §11)
```
AC-2  8 mismatches, LOGIC 102 @$63F0, +$B40F/cycle; offsets gaps [1,1,9,9,1,16,31] = P6.46's
AC-3  12 baselined, 1586 verified, 0 mismatches, ring empty
AC-4  KQ3 4,784 B cel, +1,456 over the margin; larry1 3 cels over; KQ1/KQ2/PQ1 none
AC-5  all 7 p3b arms + vm/pic/res/cel/comp byte-identical to P6.47 (SHA-256)
AC-6  vm 9/9 PASS; res 1264/1264 (100.00%); renderer 45/45
AC-7  pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22 -- all green; mojibake clean
      fault arms: CITED to P6.47, which ran all three today -- the binaries are verified
      byte-identical and their scenarios unchanged, so the inputs are unchanged [2T]
AC-9  hal_sync x3 OK   reg-discipline scope src/engine   gen_vm_tables --check OK
git diff --stat : gates.manifest 31 | p3b_run.lua 96 | p3b_show.ps1 22 | p3b_probe.s 58
                  vm_run.s 31   + res_check.s, res_copy_diff.py, cel_extent.py (new)
```
**25.2:** N/A. **25.3:** N/A — no shipped artifact changed, nothing new for the eye to gate.

### 6 — Reactive deviations and route accounting

1. ★★★★★ **THE INSTRUMENT WAS WRONG THREE TIMES AND ITS FIRST OUTPUT WAS EIGHT CONFIDENT FALSE
   ACCUSATIONS.** On a clean run it reported mismatches against five intact resources, with real
   logic numbers and plausible addresses. The defects:
   - `leax u,x` — **U is not an index register** on the 6809; the assembler says "Undefined symbol
     u", which reads as a typo.
   - `lda rck_bad` before `pshs d` — **destroyed the checksum's high byte**, so rows reported the
     row index in the high byte: `$0300, $0400, $0500…`, **the most incriminating wrong answer the
     situation could produce** [§2W.3].
   - ★★★★★ **`ldd rck_seen` before `lslb` — CLOBBERED THE SLOT.** Every array read used
     `2 × rck_seen`; the observed offsets were 32, 34, 36 = 2 × 16, 17, 18. **This one corrupted the
     COMPARISON, not just the report** — the eight mismatches were entirely artefacts.
   ★★★★★ **What caught it was printing the raw table beside the rows.** The table was correct and
   the rows were not, and that contradiction is invisible unless both are shown. It was not caught
   by the mismatch count, by the row contents, or by three readings of the routine.
   ★★★★ **The common shape of all three: a value held in a register across a call or a load that
   needs the same register** — `vm_core.s` records four prior instances of exactly this.
2. ★★★★★ **THE CEL ARM CANNOT HOST THE INSTRUMENT, which is §6's "cost forces sampling" trigger in
   its sharpest form.** Region A ends at `$52F8` with `CP_CEL` at `$5300`: **eight free bytes**
   against 518. The tables were already moved out of the image into `MAP_COVERAGE`; the code cannot
   be. **So the one arm where the overlap is live is the one arm the guest cannot measure it in**,
   and §4D is answered offline instead. Stated rather than approximated.
3. ★★★★ **`res_copy_diff.py` reproduced §1.2's trap one layer up, twice.** Comparing raw file bytes
   against the guest's decoded resource reported 1,399 spurious offsets; XORing from `stringsPos`
   with the key restarting at zero still reported 1,502, because **the message section has its own
   header and offset table and only the STRINGS are encrypted.** The span is now narrowed to
   `u16 length + bytecode` and **the narrowing is printed** [L-88]. The checksum still covers the
   whole resource — it is the byte-level explanation that is narrowed, not the detection.
4. ★★★ **I attempted a PowerShell read-modify-write of a tracked source file** to delete a dead
   symbol. The classifier refused it. **That is §2J.5 exactly**, and the rule held because it is in
   CLAUDE.md rather than in a memory file [§2J.6].
5. ★★ **`p3b_show.ps1` gained `-CovFault` as a separate switch** rather than folding three flags
   into `-ResCheck`: the fault arm must differ from the clean arm by one switch [L-73].
6. **ROUTE ACCOUNTING.** §4A–§4E are all answered. **No fix attempted** to `CP_CEL`, `vmtr_buf` or
   the phase dependency.

### 7 — Uncertainty flags

**7.1 ★★★★★ `CP_CEL`'s overlap is LIVE for Kingquest3 and larry1** (§4D) and untouched. The gate
corpus's cel runs use titles where it is dormant.

**7.2 ★★★★ The instrument has been red once, on one injected fault.** It reproduced P6.46's answer,
which is the strongest available check — but a fault arm is one corruption shape. **A cel-driven
overrun would be a different one, and the arm that could show it is the arm that cannot build it.**

**7.3 ★★★★ `TX_WIN` and the arena share `$6000`, separated only by phase** (§3(2)). Nothing asserts
the remap happened. It is not a defect today; it is an unasserted invariant in the same class as the
three this arc has found, and the instrument would catch a violation **only if a resource were
resident and re-bound afterwards**.

**7.4 ★★★ PICTURE and SOUND are unwatched**, and `rck_full` latches a table overflow but 16 slots
has never been reached (12 baselined at most).

**7.5 ★★ The sweep skipped 1 entry on the clean run and 2 on the fault run** — evicted or relocated
LOGICs, correctly declined rather than falsely reported. **Counted, not silent.**

### 8 — Follow-up candidates
1. ★★★★★ **`CP_CEL` against the arena** (§4D) — now a measured live defect with two named titles,
   not a hazard. **Assert it, then move it.**
2. ★★★★★ **The title-screen scroll** [P6.47 §7.6] — still the next thing a person sees.
3. ★★★★ **Run the cel corpus through the checksum** once `CP_CEL` moves and the arm can build it.
4. ★★★ **Assert the phase/window invariant** (§7.3) · `vmtr_buf` · PICTURE and SOUND call sites.
5. ★★ **Design spec §8B.9's blind-spot list**: *no gate looks at resource bytes after a bind* —
   **can now say it is covered, with the four exclusions.** PROPOSED TEXT ONLY [§2D].

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-19-the-new-checkers-first-output-was-eight-false-accusations.md`
- `seeds/AGI/live/2026-09-19-a-corpus-maximum-is-a-real-input-not-a-safety-margin.md`

### 11 — Commit
`0f5beb3` (pushed to origin/wip before this report).
