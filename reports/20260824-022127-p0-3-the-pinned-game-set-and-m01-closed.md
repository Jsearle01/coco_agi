## Form B Report — T-P0-003 — unblocking the oracle: the pinned game set
**Class:** build + recon. wip.

---

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-08-24T02:21:27Z. HEAD at receipt `e5d7c88` (wip) → **at report `078f334`**, pushed.
`git status --porcelain` at report → **clean**.

---

## ★ §4 PRE-DISPATCH GREP FINDINGS (C-13) — VERBATIM, BEFORE THE SUMMARY

### 4.1 Locations

```
coco_agi        branch wip   HEAD e5d7c883ba25cbb51dbdbbcfb96c0a5d806c9631  (at receipt)
POP3_port       branch wip   HEAD 282a65cf9c79739326e101b3d7cccffc8cff2daa
karateka_coco3  branch wip   HEAD 072ddcfc27ccb2c0a9b820913cd57b341a6e6fbc
```

Both sibling refs **unchanged since T-P0-001**, so AC-2's figures stand at the refs they were
first measured at (§2S.3).

**ScummVM build clone:** at the pin `9d9b9e93108a276c551aeffa390169ccc5148e15`, patches 0001 and
0002 still applied (4 tracked modifications), binary present, 4 `oracleDump*` symbols linked.
**Buildable and instrumented, as left at P0.2.**

### 4.2 The corpus at `81c42ba` — the dispatch's classification CONFIRMED

`git ls-remote` resolves `81c42ba63b3b7f5fb260d282592681c097d46da9`, which is the repository's
current default-branch HEAD (*"Merge pull request #11 from russdanner/main"*). Sparse-checked-out
`html/webapp/games`:

| | dispatch | **measured** |
|---|---|---|
| game zips | 150 | **150** ✅ |
| on-disk size | 19 MB | **19 MB** ✅ |
| v2 (separate `LOGDIR`/`PICDIR`/`VIEWDIR`/`SNDDIR`) | 147 | **147** ✅ |
| v3-shaped (combined `*DIR` + `*VOL.n`) | 3 — `demo3`, `kq4dem`, `vtgadv` | **3 — exactly those** ✅ |

**No contradiction; §8.3 did not fire.**

The corpus's complete member vocabulary, enumerated rather than assumed:

```
vol.N 177 · words.tok 150 · object 150 · picdir 147 · viewdir 147 · logdir 147 · snddir 147
agidata.ovl 88 · pal.N 32 · dmvol.N 4 · dmdir 2 · vvol.N 2 · vdir 1
```

### 4.3 ★★ `kq4dem` IS v3, and it is v3 by DECODE and not merely by shape

The dispatch flags that the Orchestrator classified it **by filename shape alone** and asks for
confirmation. Three independent confirmations, in ascending strength:

1. **Shape** — `dmdir` (combined) + `dmvol.0` + `dmvol.1`, no separate `*dir` files.
2. **Detection** — the pinned ScummVM identifies it as
   `agi:kq4  King's Quest IV: The Perils of Rosella (Demo 1988-12-20/DOS/English)`.
   **Real Sierra v3 data**, as the dispatch expects.
3. ★★ **DECODE — `lzwExpand` actually ran.** Patch 0003 traces `loader_v3.cpp:175`, and the run
   log carries `oracle: lzwExpand ran -- v3 COMPRESSED resource`. **This is the claim that
   matters**: design §9 ranks v3 LZW second and AD-12 puts it on the target's critical path, so
   "kq4dem is v3" has to mean "its resources were LZW-expanded", not "its filenames look v3".

★ **And one thing the shape classification would have got wrong.** Of the three v3-shaped
titles, **only `demo3` and `kq4dem` actually LZW-expand; `vtgadv` does not.** Its resources take
`loader_v3.cpp:170`'s `agid->len == agid->clen` branch — *"do not decompress"*. **v3-shaped is
not the same set as v3-compressed**, and a report that said "3 v3 titles exercise LZW" would
have been wrong about a third of them.

---

### 1 — Summary

**The oracle is unblocked, AC-3's gate passes, and M-01 is closed with a number that contradicts
the dispatch's premise.**

★★ **M-01, measured over all 150: the median title is 166,740 bytes, which EXCEEDS one floppy
(156,672 B), and 78 of 150 — 52% — do not fit on one.** The dispatch's §1 says *"most fan titles
are one floppy, not two to four."* **Measured, most are not.** 35 of 150 (23%) also exceed
AD-06's ≈376 KB RAM-disk ceiling. AD-04 and AD-06 both need re-deciding on these figures.

★★ **AC-7 is the other number that moves a decision: 136 of 150 titles (91%) address a text row
above 23 before the player does anything.** Row 24 is not an edge case — it is the norm — and
`resi44` (*Residence 44 Quest*), the title ScummVM's own source comment names, is second in the
corpus with 182 hits. **AD-01's two-text-row layout has a gap that 91% of the corpus walks into
at boot.**

★ **Three of my own measurements had to be corrected before they were reportable**, and each is
recorded in §3 rather than quietly fixed: the first byte totals counted Sierra's DOS interpreter
overlay as game data; three games sharing a priority hash looked like corroboration and was worth
a histogram; and the sweep's summary file was silently corrupt while its artifacts were fine.

**Nine AC pass; AC-4 is partial and AC-5 carries a material qualification (§7.1).**

---

### 2 — Files modified

Explicit-path staging (§2E). Two commits.

**`0284093`→`078f334`:**
- `CLAUDE.md` — **v1.1 → v1.2, committed as provided, not edited** (§2D).
- `oracle/scummvm.pin` — `[game-set]` filled in; patch list and the DumpFile `.tmp` trap recorded.
- `oracle/patches/0003-oracle-row24-probe-and-lzw-trace.patch` — **new.**
- `harness/tools/game_manifest.py` — **new**, the corpus measure.
- `games/manifests/agile-gdx-81c42ba.tsv` — **new**, 150 rows.
- `harness/tools/oracle_dump.sh` — corrected: `--no-console` does not exist on this build, and
  the `.tmp` rename is now handled.

★ **No game data is in the repository and none passed through it** (§2P). Corpus at
`C:\Projects\agi-games\`, unpacked working copies at `~/agi-work/` in WSL. Archives opened `'r'`.

★ **Room dumps are deliberately NOT committed.** A rendered room is a rendering of copyrighted
game content; §2P's reasoning applies to it as much as to the VOL it came from. Their sha256 are
in §5, which is what a diff needs.

---

### 3 — Reasoning

#### 3A — §2 CLAUDE.md v1.2: the superset check finds FIVE, and the dispatch declares FOUR

Run at normalised EOL. **Five substantive v1.1 lines are absent from v1.2:**

```
v1.1:2    ## Working Agreement v1.1 (forked from POP3_port CLAUDE.md v1.1)
v1.1:3    **Version:** 1.1
v1.1:273  reference is 6,369 lines of C implementing 319 opcodes** — `op_cmd.cpp` alone is 2,540 — and a
v1.1:274  first-mechanism read of it is very easy to make and hard to catch. **The three checks apply verbatim to
v1.1:275  reading ScummVM.**
```

★ **This is NOT a C-34 stop, and the arithmetic is the reason.** §2's prose says *"exactly four
lines"*, but its own table has three rows and labels the third **"3 lines"** — so the table
declares 1 + 1 + 3 = **5**. All five absent lines fall inside those three declared rows.
**No line is missing beyond the declared set**, which is what the hard stop actually guards.
Reported rather than silently reconciled.

Verified the supersessions carry the corrections rather than merely deleting: `2,483` and
`30,066` at `v1.2:7`, the *"319 opcodes"* scope note at `v1.2:282-283` enumerating all four
tables, and `TC_MMU` still present from v1.1. **Both corrections are mine from T-P0-002, folded
by the Orchestrator, committed unedited.**

#### 3B — ★★ The first byte total was wrong, and the corpus disproved it for me

The obvious M-01 measure is "sum every member of each archive". That yielded a median of
**172,362**. It is wrong: it counts **`AGIDATA.OVL`, Sierra's DOS interpreter overlay** — 6,656
to 8,192 bytes, present in 88 of 150 archives. **Our CoCo3 interpreter replaces it outright**, so
charging it against a floppy or a RAM-disk budget bills the port for code it will never carry.

★ **Two confirmations, because "it looks like interpreter code" is not evidence:**

1. **62 of the 150 titles do not ship it at all** and are complete, playable games. A file absent
   from 41% of the corpus cannot be required resource data. *The corpus refutes it directly.*
2. **The pinned ScummVM never opens it.** Its only appearance in `engines/agi` is a comment at
   `detection_tables.h:238` using the version string inside it to identify an interpreter build.

Excluding it moves the median to **166,740** and drops the over-RAM-disk count from 37 to 35.
**Both figures are reported in the manifest (`total_uncompressed` and `game_bytes`) so the
decision is visible and reversible rather than baked into one column.**

#### 3C — ★★ §2H's three checks: three matching hashes that were not corroboration

1. **Is there a SECOND mechanism serving a different object class?** ★ **Yes, and it nearly cost
   me the priority half of the oracle.** The first three games dumped **identical priority
   hashes** (`ecefcc9d…`) while their visuals differed. Three independent games agreeing looks
   like the strongest possible corroboration; it is the opposite. A histogram showed every
   priority buffer was **uniform value 4** — the initial fill from `clear(15, 4)` with nothing
   drawn over it, i.e. **zero information**. Chasing it: `putVirtPixel` sets a draw mask from
   `_priOn`/`_scrOn` and `GfxMgr::putPixel` writes `_priorityScreen[offset]` only when the
   priority bit is set, so a picture with no priority commands legitimately leaves the buffer at
   its fill. **Settled by scanning all 193 priority dumps in the sweep: 37 are non-uniform**, one
   with **eight** distinct priority values. **The mechanism is sound; the early sample was all
   title cards.** Had I stopped at three matching hashes I would have reported either a false
   alarm or a false pass.
2. **Name the routine that CALLS it.** Decisive for AC-7's numbers. The probe fires in four
   opcode handlers, and **the caller is the game's LOGIC script** — which is why the answer is
   136/150 and not a property of the engine. It is also why `clear.lines` dominates (940 of 953
   hits) while `configure.screen` and `get.string` produced **zero at boot**: the mechanisms are
   not equally used, and a design that handled only the prompt row would miss the actual traffic.
3. **Grep prior reports for the same subsystem.** T-P0-002 §4.3 established the four mechanisms
   and predicted the answer could only come from game data. **This task measures what that report
   could only bound**, and the two agree: it named `resi44` from a ScummVM comment, and `resi44`
   turns up second in the corpus by hit count. No contradiction.

#### 3D — ★★ The VM state is deterministic except for the wall clock, and the variable is named

AC-3's picture dumps are byte-identical everywhere. **kq4dem's VM-state logs diverged**, which is
§8.1 territory, so it was run down rather than reported as a wobble.

**It diverges at cycle 879, and exactly three variables ever differ across 1,123 compared
cycles:** `var 11` (A=21, B=22), and `var 72`/`var 73`. **`var 11` is `VM_VAR_SECONDS`**
(`agi.h:227`) — AGI's real-time seconds counter — and 72/73 are game variables the LOGIC derives
from it. `starco` was byte-identical over all 565 cycles because it reaches a stable wait before
a second boundary matters.

★★ **So the oracle is not non-deterministic; it is CLOCK-COUPLED, in a bounded and identifiable
way.** That distinction is the difference between "design §8's method is invalid" and "the
state-diff must exclude var 11 and anything derived from it". **§8.1's stop was not triggered
because AC-3 — the picture dumps — passed; this is an AC-5 qualification, and it is in §7.1 as a
constraint on P2's state-comparable gate.**

#### 3E — §2.1: which of these are ScummVM normalisations

Two declarations, both bearing on AC-7:

- ★ **The row-24 CLAMP is ScummVM's, believed NOT original.** `clearBlock` (`text.cpp:629`)
  states it: *"Sierra didn't do clipping of the coordinates, we do it for security."* So the
  bound of 24 is ScummVM's behaviour. **What is believed ORIGINAL is that games ISSUE these
  rows** — that is a fact about game data, and it is what AC-7 counts.
- ★ **`cmdClearLines` carries two game-specific workarounds** (`op_cmd.cpp:2150-2156`), for
  *Residence 44* and *Agent06*. Both fired in this corpus. The AC-7 probe is placed **after** the
  `textRowUpper > textRowLower` swap, so it measures rows as ScummVM finally uses them, not as
  the game wrote them. **For `resi44`, which calls `clear.lines(24,0,0)`, that distinction is
  live** — and it is why both bounds are probed rather than one.

#### 3F — Refs and scopes (§2S.3)

ScummVM citations at **`9d9b9e93` (v2.9.1)**. Corpus figures at **`agile-gdx@81c42ba`**. Sibling
figures at **POP `wip` `282a65c`** and **Karateka `wip` `072ddcf`**.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable]** — v1.2 committed byte-identical: provided SHA-1
  `7ed6eda4eca2ea90eaeb61306f4532d6d44440d8`; **committed blob content SHA-1 identical**.
  Superset output in §3A: **five absent lines, all inside the three declared rows, none beyond.**
  ✅ **PASS**, with the 4-vs-5 discrepancy reported.
- **AC-2 [byte-comparable]** — `coco_agi` **0**, POP **59** at `282a65c`, Karateka **8** at
  `072ddcf`; all three `--expect` assertions rc=0. Fixture demo rc=0. ✅ **PASS.**
- **AC-3 [byte-comparable] ★ THE GATE — RUN FIRST, AND RE-RUN LAST** — verified **twice**: on the
  patch-0002 binary (`abrah`) before any other work, and again on the **final patch-0003 binary**
  (`starco`, 5 rooms; `kq4dem`), because the binary changed underneath the first result. **All
  picture and priority dumps byte-identical across separate invocations**, 26,880 B each.
  Verbatim in §5. ✅ **PASS.**
- **AC-4 [byte-comparable]** — **PARTIAL.** ≥2 rooms achieved for **37 of 150** titles (6 with 3,
  1 with 5). Tabulated for `starco` (5), `goutsq` (3), `herbao` (3) in §5, all 26,880 B with
  sha256. ★ **`kq4dem` yields ONE room, not two** — it holds on its title screen and the null
  backend supplies no input, so it never advances. **I did not inject synthetic input to
  manufacture a second room**: driving a game artificially to satisfy a count risks baselining
  states the game does not reach on its own. ⚠️ **PARTIAL — 3+ games with ≥2 rooms, but not
  kq4dem.**
- **AC-5 [state-comparable]** — VM state captured for **all 150** titles; **136 reached ≥20
  cycles**. Entry-of-cycle convention (T-P0-002 §3D). First three cycles of `starco` in §5.
  Determinism: `starco` **identical over all 565 cycles**; `abrah` identical. ★ **`kq4dem`
  diverges at cycle 879 in `VM_VAR_SECONDS` alone** (§3D). ✅ **PASS with the §7.1 qualification.**
- **AC-6 [suite] ★ M-01 CLOSED** — all 150 measured; table in §5. **min 8,975 · median 166,740 ·
  max 5,715,903 · sum 57,835,758.** **Over one floppy: 78/150 (52%). Over the RAM-disk ceiling:
  35/150 (23%).** Manifest committed and regenerable. ✅ **PASS.**
- **AC-7 [suite]** — **136 of 150 (91%)** address a game-supplied row > 23 at boot; 4 more call
  `text.screen` (unconditional 0..24). Mechanism split: `clear.lines.lower` **550**,
  `clear.lines.upper` **390**, `text.screen` **13**; `configure.screen` and `get.string`
  **zero**. ★ **Coverage limit stated explicitly: boot-time only, therefore a LOWER BOUND.** A
  game addressing row 24 in a death message, an endgame or any post-input path is not counted.
  **Never quote 91% as a ceiling.** ✅ **PASS.**
- **AC-8 [byte-comparable]** — `kq4dem` produces a valid 26,880 B room dump, byte-identical
  across runs, from **combined-DIR v3 parsing with `lzwExpand` confirmed to execute** (§4.3).
  ★ **Finding: `vtgadv` is v3-shaped but NOT LZW-compressed.** ✅ **PASS.**
- **AC-9 [byte-comparable]** — `games/manifests/agile-gdx-81c42ba.tsv` (150 rows, per-title
  sha256, version shape, byte totals, derived slot counts); `oracle/scummvm.pin` `[game-set]`
  carries repository, commit, path, counts, the sparse clone recipe and the regenerate command.
  **A second party can reconstruct the exact corpus from the repo alone.** ✅ **PASS.**
- **AC-10 [suite]** — one candidate captured and pushed. §10. ✅ **PASS.**

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1a — `reg_discipline.py` ×3 (AC-2), verbatim:**

```
coco_agi  src/engine/**                        [reg-discipline] OK -- measured 0   rc=0
POP       src/ less src/hal,src/harness        [reg-discipline] OK -- measured 59  rc=0
Karateka  src/ less src/hal                    [reg-discipline] OK -- measured 8   rc=0
```

**25.1b — ★ AC-3, THE GATE, on the FINAL binary (patch 0003 applied), verbatim:**

```
--- starco ---
  A  ecefcc9dd87f24646ea82869658d4e1ed6ba2485c6c4404ff83c224c397ea43c  pic001.priority.bin
  A  fc5e9ef7295e06ee4b5e922830d77334d61cfe49160b822af6ef29af38736369  pic001.visual.bin
  A  ecefcc9dd87f24646ea82869658d4e1ed6ba2485c6c4404ff83c224c397ea43c  pic245.priority.bin
  A  16b5a2280806959f427e81b405ab2a6e57619a52e1f4f43baddd5c112b8ec922  pic245.visual.bin
  A  ecefcc9dd87f24646ea82869658d4e1ed6ba2485c6c4404ff83c224c397ea43c  pic246.priority.bin
  A  104eeeae1abf477afeba0f347e8503ace4b6a747979c023027d63d62ebcd69f2  pic246.visual.bin
  A  ecefcc9dd87f24646ea82869658d4e1ed6ba2485c6c4404ff83c224c397ea43c  pic247.priority.bin
  A  f09f8e16656f3ad9595625d9343b1daa6c1d5d4f3d4eae598c426525ef190306  pic247.visual.bin
  A  ecefcc9dd87f24646ea82869658d4e1ed6ba2485c6c4404ff83c224c397ea43c  pic248.priority.bin
  A  713256f458fd7d5d92009fa5a74be0e364401ccdd5643055e1210e9752780966  pic248.visual.bin
  B  <the same ten lines, byte for byte>
  PICTURES: BYTE-IDENTICAL
  VM STATE: identical (565 cycles)
--- kq4dem ---
  A  ecefcc9dd87f24646ea82869658d4e1ed6ba2485c6c4404ff83c224c397ea43c  pic001.priority.bin
  A  5f83f6bd5c17cd371ab232afa13e8d3bb7f662beb8c22e977ba36167a2f37d81  pic001.visual.bin
  B  <identical>
  PICTURES: BYTE-IDENTICAL
```

Earlier gate on the patch-0002 binary (`abrah`), before any other work:
`82ec960a…` visual / `ecefcc9d…` priority, identical across runs A and B, 26,880 B each.

**25.1c — ★ AC-6, M-01, the table (all 150, `agidata.ovl` excluded):**

```
[manifest] 150 game(s)
[manifest] by shape: v2=147, v3-shaped=3

  GAME bytes per game (uncompressed, agidata.ovl excluded)
    min          8975  (pktetr)
    median     166740
    max       5715903  (epicft)
    sum      57835758

  exceeding ONE FLOPPY   (156672 B, AD-04): 78 of 150  (52%)
  exceeding RAM-DISK     (385024 B, AD-06): 35 of 150  (23%)
    epicft 5715903 · hitler 3935321 · 0fb053 2966578 · gourdb 2793529 · vtgadv 1947592
    sqx 1639615 · starco 1625846 · maalea 1561336 · jeffsq 1506199 · lpirat 1375395
    cldest 1287884 · sq0 1056822 · enclos 1042587 · gtamp1 949507 · davesq 879375
    gowest 849951 · sorapp 817806 · philq 751104 · joulum 738740 · dashik 704097
    uriq 683766 · ltec 682955 · corbmm 672650 · ttscb 628097 · acidop 587278
    nickq 578067 · kq2bi 575690 · totiki 543907 · starpi 525657 · hankqe 519350
    natu2e 497767 · spbike 491271 · mdqust 449688 · napalm 437156 · presq 400170
```

Full per-title detail, with sha256: `games/manifests/agile-gdx-81c42ba.tsv`.

**25.1d — AC-7, the row-24 census:**

```
games with artifacts on disk: 150
detected by ScummVM    : 150 / 150
reached >=20 VM cycles : 136 / 150

  GAME-SUPPLIED row > 23        : 136 / 150  (91%)
  text.screen (uncond. 0..24)   :   4 / 150  (3%)
  by mechanism (total hits):  clear.lines.lower 550 · clear.lines.upper 390
                              text.screen.clear0-24 13
                              configure.screen 0 · get.string 0

  sarien  hits=286   Sarien (DOS/English)
  resi44  hits=182   Residence 44 Quest (v1.0a) (DOS/English)     <-- the title ScummVM names
  pharq   hits=136   Pharaoh Quest (v0.0) (DOS/English)
  vdgirl  hits=8 · natu3e 7 · tobywd 7 · alpndh 6 · jochef 6 · uriq 6 · epicft 5 ...
```

**25.1e — AC-4, room dumps (26,880 B each; sha256 truncated to 40 hex):**

```
--- starco (5 rooms) ---            --- goutsq (3 rooms) ---
  pic001.visual  fc5e9ef7295e06ee…    pic000.visual  010928b46bb6bf8b…
  pic245.visual  16b5a2280806959f…    pic001.visual  b718642599430abc…
  pic246.visual  104eeeae1abf477a…    pic003.visual  ccd4e03cc7216147…
  pic247.visual  f09f8e16656f3ad9…  --- herbao (3 rooms) ---
  pic248.visual  713256f458fd7d5d…    pic000.visual  010928b46bb6bf8b…
--- kq4dem (1 room) ---               pic001.visual  dd69853ef02f4b9b…
  pic001.visual  5f83f6bd5c17cd37…    pic003.visual  f83b0e5f3d1a9673…
```

**Priority-buffer content across the whole sweep (§3C):**

```
priority dumps examined : 193
NON-UNIFORM             : 37
  0fb053 pic000  values=[0,4,5,6,10,11,12,15]   <-- eight distinct priority levels
  czherm pic001  values=[4,5,8,10,12,14]
  hitler pic001  values=[1,4,11,12,15]
  ... uniform (4,) in 156 dumps -- pictures with no priority commands
```

**25.1f — AC-5, first three cycles (`starco`), entry-of-cycle:**

```
cycle 000000 flags 200a000000000000000000000000000000000000000000000000000000000000 vars 0000000…
cycle 000001 flags 000b000002000000001000000000000000000000000000000000000000000000 vars 0100000…
cycle 000002 flags 000b000002000000001000000000000000000000000000000000000000000000 vars 0100000…
```

**The clock coupling, isolated (§3D):**

```
common cycles compared : 1123      first differing cycle : 879
VARIABLES that ever differ:  var  11 (52 cycles) · var  72 (51) · var  73 (51)
FLAG BYTES that ever differ: none
at cycle 879:  var 11 :  A=0x15 (21)   B=0x16 (22)
agi.h:227      VM_VAR_SECONDS,   // 11
```

**25.2 — bundled-artifact grep:** **N/A.** No coco_agi build artifact exists; the ScummVM binary
is an oracle tool living outside the repository and is never shipped (§2Q.1). Room dumps are
deliberately not committed (§2).

**25.3 — operator-runtime-smoke:** **N/A — no CoCo3 visual surface this task.**

---

### 6 — Reactive deviations and route accounting

1. **`--no-console` removed** from `oracle_dump.sh` — it does not exist on this build and made
   the first run exit 1. A P0.2 defect, found the moment the script was first exercised.
2. **The `.tmp` rename** — ScummVM's `DumpFile` writes atomically (`stdiostream.cpp:65,184`) and
   renames on close; a `timeout`-killed process never closes, so the long-lived logs stay
   `.tmp`. The runner performs the rename `close()` would have. **A rename is not a
   transformation** — no byte is read or altered, so §2O.1 is untouched.
3. **Patch 0003 carries the LZW trace as well as the AC-7 probe.** 55 inserted lines total, of
   which ~18 are comment and 13 are the LZW trace; **executable AC-7 instrumentation is ~24
   lines, inside §8.4's ~40**. Reported rather than consulted because the seam is exactly the
   four mechanisms the dispatch named.
4. **The secondary Sierra DEMOPACK set was NOT fetched** — §3 makes it optional and says to skip
   and say so. Skipped: the primary corpus covers every AC including the v3 LZW path. **Recorded
   in the pin as still wanted** for KQ3/LSL1 fidelity work.
5. **AC-4's second room was not manufactured for `kq4dem`.** Injecting synthetic input would have
   satisfied the count; it would also baseline states the game does not reach unaided.
6. **The sweep summary was recomputed, not re-run** (§7.4).

**ROUTE ACCOUNTING.** No route was proposed to Jay or the Orchestrator this task. What this change
contains is §2's file list plus the six items above. **What it does NOT contain, said here rather
than left to the diff:** no second room for `kq4dem`; no post-boot AC-7 coverage; no DEMOPACK
set; no committed dumps. **Explicitly not done per §12:** no `src/hal/`, no `hal_sync_check.py`
edit, no `build.bat`, no CoCo3 code, no offline renderer, **no VOL/DIR parser of our own** — every
size in the manifest is the archive's own figure — no owner-row ratchet, no P5.17 table fix, no
`*.patch` back-port, no game data committed, and no full playthroughs.

---

### 7 — Uncertainty flags

1. **★★ THE ORACLE IS CLOCK-COUPLED, AND P2's STATE GATE MUST ACCOUNT FOR IT.** `VM_VAR_SECONDS`
   (var 11) advances with wall-clock time, and game variables derived from it inherit the
   nondeterminism (here vars 72, 73). **Room dumps are unaffected** — a picture is a pure
   function of its resource — **but a per-cycle state diff will diverge on any run long enough to
   cross a second boundary.** Either exclude var 11 and its derivatives, or drive both sides from
   a synchronised clock. **This is a constraint on design §8's method, not a defect in the pin.**
2. **AC-7's 91% is a floor, not a ceiling.** Boot-time only. The true figure is higher by an
   unknown amount, and closing it needs LOGIC decoding, which is P1.
3. **`configure.screen` and `get.string` scored zero at boot.** That is a real observation about
   *boot*, not evidence they are unused — both are strongly associated with mid-game interaction.
   Do not conclude they are safe to ignore.
4. **★ The sweep's summary file was corrupt and its artifacts were not.** `results.tsv` used
   `count=$(grep -c PATTERN file || echo 0)`; `grep -c` prints `0` **and exits 1** on no match, so
   the `||` appended a second `0`, embedding a newline. 150 games produced 258 lines of which
   **16** were well-formed. Caught by comparing the line count against the known input count. All
   AC-4/7/8 figures in this report are **recomputed directly from the per-game artifacts**, not
   from that file. The sweep was not re-run. **The harness script is in the scratchpad, not the
   repo, so nothing in-tree carries the bug** — but the idiom is worth never using again.
5. **Slot counts in the manifest are DERIVED** (`dirlen / 3`) and are an **upper bound** — an
   unused DIR slot is `0xFFFFFF` and still occupies three bytes. Labelled as `slots`, never as
   resources, in both the tool and the TSV header.
6. **The ≈376 KB ceiling was read as 376 × 1024 = 385,024 B.** If AD-06 means 376,000 the count
   changes slightly. Stated so the threshold is checkable rather than assumed.
7. **`vtgadv` is v3-shaped but uncompressed** (§4.3), so the corpus contains **two** LZW-exercising
   titles, not three. Both are Sierra demos; there is no fan-made LZW title here.
8. **14 of 150 reached fewer than 20 cycles** in the 15 s boot window. All were detected and all
   reached ≥1 cycle, so none is a load failure — but their AC-7 coverage is thinner than the rest.

---

### 8 — Follow-up candidates

1. ★★ **AD-01 needs re-deciding on 91%.** Row 24 is the norm, not an edge case. Accept truncation,
   scroll, or find 8 more lines — a decision, and it now has a number behind it.
2. ★★ **AD-04 and AD-06 need re-deciding on §5's table.** The median title does **not** fit one
   floppy and 23% exceed the RAM-disk ceiling. The dispatch's own premise ("most fan titles are
   one floppy") does not survive measurement.
3. ★ **Decide the state-diff's clock policy** (§7.1) before P2 builds anything on VM-state dumps.
4. **Get a second room out of `kq4dem`**, by scripted input or a savegame, so the v3 path is
   exercised on more than a title card.
5. **Fetch the Sierra DEMOPACK set** before any fidelity comparison — KQ3 and LSL1 are the two
   titles Sierra shipped for the CoCo3.
6. **Pick priority-rich rooms as P2's first byte-comparable targets** — `0fb053 pic000` has eight
   distinct priority levels and is a far better first test than a title card.

---

### 9 — User interaction during task

**Jay sent two messages.** The first was `report`, while the corpus sweep was still running; I
checked its state, found it 113/150 complete, and continued rather than reporting partial AC-7
figures. The second was `sorry didnt realize you were waiting` + `check`, after declining a
long blocking wait — I switched to polling the sweep's row count directly. **No guidance about
the work's content was given and none was requested.** No consultation trigger fired: §8.1
(AC-3 passed, twice), §8.2 (`kq4dem` confirmed v3 by decode), §8.3 (classification confirmed
exactly), §8.4 (~24 executable lines), §8.5 (all five absent lines declared).

---

### 10 — Candidate(s) captured this task

`seeds/AGI/live/2026-08-24-keep-the-artifacts-so-a-broken-summary-costs-a-recompute.md`

*Have a long batch write raw per-item artifacts and derive the summary from them afterwards — the
aggregation is the least-tested code in the job, and when it breaks the cost should be a
recompute of seconds, not a re-run of hours.* Captured at its first instance (§7.4);
`instance_count` verified equal to `len(instance_history)`; `initiator: executor`.

★ It links the two prior AGI rows and proposes they be reconciled as one heading: **what a green
check actually licenses you to say.** T-P0-001's was *the comparison was too coarse*; T-P0-002's
was *the comparison was of the wrong copy*; this one is *the comparison was of a derived summary
rather than the evidence.* In all three the check ran and was reported in good faith.

Pushed `1808196..c88daa5`, fire-and-forget. No existing pool entry read for content or edited (§2C).

---

### 11 — Commit

`078f334f9d676eba3c1a39216554145065647372` — two commits this task:

```
078f334  P0.3  game set pinned at agile-gdx@81c42ba; manifests; row24 + LZW probes
0284093  P0.3a CLAUDE.md v1.2
```

Pushed to `origin/wip` before this report. This report is a third commit on `wip`.
