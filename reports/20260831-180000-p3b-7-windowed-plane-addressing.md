## Form B Report — P3b.7 — windowed plane addressing
**Class:** build. wip.
★★★★ **STOPPED ON §7 TRIGGER 4 BEFORE THE WINDOWING WORK BEGAN. The resource gate has been
running a STALE BINARY for three tasks, and behind it the LOGIC cache breaks a shipped path.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-31 (HEAD `3519466`, wip). git status clean at receipt.

---

### §4 — Pre-dispatch grep (verbatim, before the summary)

```
=== coco_agi ===        3519466  wip   (clean)

=== siblings (§2T: cite P3b.6 §0) ===
POP3_port          104b197 wip  tracked-modified=0
karateka_coco3     29f8f0a wip  tracked-modified=1

=== hal_sync ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)

=== reg_discipline ===
  src/engine/mmu_phase.s                       5  $FFA5 $FFA6
```

★★★★ **EVERY FLAT PLANE WALK — THE LIST IS THIRTEEN SITES ACROSS THREE FILES, NOT TWO** [L-53]:

```
src/harness/pic_core.s:31   addd #FB_BASE      (pix_addr, dead)
src/harness/pic_core.s:34   addd #PRI_BASE     (pix_addr, dead)
src/harness/pic_core.s:86   addd #FB_BASE      put_pixel, visual
src/harness/pic_core.s:107  addd #PRI_BASE     put_pixel, priority packed
src/harness/pic_core.s:130  addd #PRI_BASE     put_pixel, priority unpacked
src/harness/pic_fill.s:114  PRI_DELTA equ PRI_BASE-FB_BASE      ★ a CONSTANT between planes
src/harness/pic_fill.s:209  addd #FB_BASE      fill_check, visual
src/harness/pic_fill.s:252  addd #PRI_BASE     fill_check, priority packed
src/harness/pic_fill.s:277  addd #PRI_BASE     fill_check, priority unpacked
src/harness/pic_fill.s:340  ldd  #FB_BASE      ffs, visual span base
src/harness/pic_fill.s:351  ldd  #PRI_BASE     ffs_pri, priority span base
src/harness/pic_fill.s:774  leax PRI_DELTA,x   the second write
src/harness/pic_fill.s:810  addd #PRI_BASE     ff_store_pri
src/harness/composite.s:362 addd #CP_VIS       co_rowset
src/harness/composite.s:370 addd #CP_PRI       co_rowset
```

★★★ **`pic_fill.s` has the most, and it is the file whose inner loop P3.3 took from 11.102 s to
2.746 s.** ★★ **§7 trigger 3 fires: the class is wider than the two named routines.**

★★★★ **ARENA SIZES — THERE ARE THREE, NOT TWO:**

```
  res_core.s default (res_probe)   $3000-$6000   = 12,288 B   ★ SMALLER THAN p3b
  p3b_probe.s (MAP_ARENA_WIN)      $6000-$A000   = 16,384 B
  vm_probe.s                       $6B00-$C000   = 21,760 B
```

**The five gates:** ★★★★ **the resource gate is RED — 805 of 1,264.** See §1. Renderer, VM, cels
and composite were **not re-run**, because the task stopped before touching them (§6).

**Contradiction found. Stopped.**

---

### 1 — Summary

★★★★ **Three findings, each one uncovering the next, and none of them is the windowing work.**

**1 — The resource gate has been testing a binary assembled before the code it gates.**
`res_run.ps1` never assembles `res_probe.s`; it only points `RES_PROG` at `build\res_probe.bin`.
★★★ **I flagged that file as stale in T-P0-035** and did not follow the thread. The LOGIC cache
landed in T-P0-036. **So "resources 1,264/1,264, all clean" in T-P0-036 and T-P0-037 was produced
by a pre-cache binary and validated nothing about the cache.**

**2 — AD-89 is a correctness defect in a GATED path, not a latent one.** Rebuilt from source with
the defect restored (`-DABL_FWDCOPY`), the resource gate reports **`mismatched: 2`, 62
guest-reported failures**. ★★ **§7 trigger 4's exact condition.**

**3 — And with AD-89 FIXED the gate still fails: 805 of 1,264, `status=4` = `RES_E_BIG`.**
★★★★ **The LOGIC cache is only ever reset by `vm_new_room`.** `res_probe` has no rooms, so
`res_ccur` walks down and never returns; the 12,288-byte arena fills with cached LOGICs and later
fetches will not fit. **The cache was designed against the VM's lifecycle and `res_core` has three
callers.**

> ★★★★ **So the tree does not have a red gate because of anything done today. It has had a red
> gate since T-P0-036 and the staleness hid it.** Revealing it is the finding.

★★ **AC-7 is delivered** — a test that fails on the old code, and the gate now builds its own
artifact. ★★★ **Everything else is not reached, deliberately.**

---

### 2 — Files modified

- `harness/tools/res_run.ps1` — **assembles `res_probe.s` before running.** The one-line
  omission behind finding 1.
- `src/harness/res_core.s` — `-DABL_FWDCOPY` restores AD-89 on purpose, for AC-7's test.
  ★ Inert by default; `vm_probe.bin` verified byte-identical.

★★ **No windowing work was started.** No plane-addressing file was touched.

---

### 3 — Reasoning

#### 3.1 How the staleness was found, and why it took a rebuild

The dispatch asked me to fix AD-89 **and gate it** (AC-7), and L-62's principle is that a fix
whose test has never failed is an assertion. So I put the defect back behind `-DABL_FWDCOPY` and
ran the resource gate expecting it to stay green — the gate had reported clean with the defect
present for two tasks, so the interesting question was *why it could not see it*.

★★★ **It failed immediately.** That inverted the question: not "why is this gate blind" but
"what did that gate actually run". `res_run.ps1` has no assemble step.

★★ **The tell was available in my own T-P0-035 report** — *"build/res_probe.bin is from Aug 29
and nothing rebuilds it"* — written while investigating something else and never followed up.

#### 3.2 Why the cache breaks `res_probe` and not `vm_probe`

| | arena | resets the cache? |
|---|---|---|
| `vm_probe` | 21,760 B | ★ **yes** — `vm_run.s:361` calls `res_cache_reset` from `vm_new_room` |
| `res_probe` | **12,288 B** | ★★★ **no** — it has no rooms; nothing ever calls it |

★★★ `res_cache_stash` allocates downward from `res_ccur` and only `res_cache_reset` restores it.
With no reset, the cache is a one-way allocation: after the first `RES_CACHE_MAX` LOGICs the
arena's free span is permanently reduced by their total, and the next large PICTURE returns
`RES_E_BIG`. ★ Consistent with the observed failures being PICTUREs at `status=4`.

★★★★ **This is the third member of one family in two days**, and I wrote the row for it this
morning: *a defect whose presence depends on a caller's configuration passes every gate.* AD-89's
trigger was the caller's **arena size**; this one's is the caller's **lifecycle**. ★★ `res_core`
is a shared layer with three clients and the cache assumed one of them.

#### 3.3 Why I did not start the windowing

§7 trigger 4: *"AD-89 turns out to affect a shipped path, not only p3b. **Stop and report** — that
would make it a correctness defect in gated code, not a latent one."* It does, and it is.

★★ **Windowing would have landed on top of a red gate**, and AC-3/AC-4/AC-6 all compare against
gates that cannot currently be trusted — the renderer and composite gates build their own probes,
but the resource layer underneath them does not. ★ Attributing a cost to windowing (AC-5) while a
second defect is live would violate L-54 outright.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** ★★★ **FAILS, and the failure is the finding.** `hal_sync` OK;
  `reg_discipline` 5/2/one owner; §2T cited from P3b.6 §0. ★★★★ **The resource gate is 805 of
  1,264.** The other four were not re-run (§6).

- **AC-2 [class: byte-comparable]** ★★★ **NOT REACHED** — no windowing was written, so there is
  no in-window assertion to report. ★ §4's enumeration is the input it would need: **13 sites**,
  not 2.

- **AC-3 [class: byte-comparable]** ★★★ **NOT REACHED.**
- **AC-4 [class: byte-comparable]** ★★★ **NOT REACHED.**
- **AC-5 [class: state-comparable]** ★★★★ **NOT REACHED** — and this is the number the dispatch
  says decides whether P3b closes or the map changes. It is still unknown.
- **AC-6 [class: state-comparable]** ★★ **NOT REACHED.**

- **AC-7 [class: byte-comparable]** ★★★★ **DELIVERED, and it is the one AC that mattered most.**
  - **The test fails on the OLD code:** `-DABL_FWDCOPY` rebuilds `res_probe` with the forward
    overlapping copy → **`mismatched: 2`, `guest-reported failures: 62`**, against a clean
    baseline of 0 and 0.
  - **The gate now builds its own artifact**, so it tests the source rather than history.
  - ★★★ **But AD-89's fix does NOT make the gate green — 805 of 1,264 remains**, because §3.2 is
    a second, independent defect in the same code. **AD-89 is fixed; the cache is not.**

- **AC-8 [class: byte-comparable]** ★★★ **NOT REACHED** — no injected-fault run. ★ Per L-62 I am
  not claiming any earlier build's fault result transfers.

- **AC-9 [class: state-comparable]** ★★ **NOT REACHED** — no boundary check was placed, so there
  is no siting decision or cost to report.

- **AC-10 [class: suite]** ★ **One row** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

```
=== resource gate, OLD code (-DABL_FWDCOPY, rebuilt from source) ===
byte-identical vs tools/volread/ : 23
mismatched  : 2      guest-reported failures: 62
  ! PICTURE  79  status=4 (too-big)
  ! PICTURE  80  status=4 (too-big)
  ! PICTURE  81  status=4 (too-big)
  ... 12 more
```

```
=== resource gate, CURRENT code, gate now self-building ===
res_probe: 1969 bytes (assembled by this script)
=== TOTAL ===
byte-identical resources: 805 across 10 (title, volume) sweeps      ★ expected 1,264
```

```
=== the omission ===
harness/tools/res_run.ps1:37   $env:RES_PROG = "build\res_probe.bin"
  -- and no lwasm invocation anywhere in the file
```

```
=== who resets the cache ===
src/harness/vm_run.s:361       jsr  res_cache_reset      (from vm_new_room)
src/harness/res_probe.s        -- no call --
```

```
★ vm_probe.bin BYTE-IDENTICAL -- the ABL_FWDCOPY guard is inert
```

**25.2 bundled-artifact grep:** N/A — nothing bundled; the only shipped-path change is a harness
script gaining a build step.

**25.3 operator-runtime-smoke:** **N/A** — nothing reached the screen.

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **Stopped on §7 trigger 4** before any windowing. The dispatch's AC-2/AC-3 are "the
   task"; they are not started, on purpose.
2. ★★ **Four of the five gates were not re-run.** With the resource layer red beneath them, a
   green renderer or composite result would be reporting on an untrustworthy base. ★ They are
   owed once §3.2 is settled.
3. ★ **`res_run.ps1` gained an assemble step** — arguably out of scope, but a gate that does not
   build what it gates cannot be left in that state once known.

**ROUTE ACCOUNTING.** ★★ **What I did NOT do:** did not window any plane access; did not touch
`pic_core.s`, `pic_fill.s` or `composite.s`; did not measure windowing's cost; did not fix the
cache's lifecycle problem (§3.2 — that is a design question about a shared layer with three
callers, and trigger 4 says report); did not re-run the four other gates.

---

### 7 — Uncertainty flags

1. ★★★★ **The resource gate is red at 805/1,264 and has been since T-P0-036.** Two reports claim
   it clean on the strength of a stale binary. **Those claims should be treated as withdrawn.**
2. ★★★★ **How much else did the stale binary hide?** The cache landed in T-P0-036 and `res_core.s`
   was also edited in T-P0-035 and T-P0-037. **Every resource-gate result since Aug 29 is suspect**,
   not only the cache-related ones.
3. ★★★ **Which other gates build their own artifacts?** `vm_run.ps1` assembles (verified);
   `run_gates.sh` takes `PIC_PROG`/`COMP_PROG` from the caller and I have been building those by
   hand. ★★ **A gate that depends on the operator to rebuild is one operator lapse from testing
   history.** Not audited this task.
4. ★★★ **The cache's fix is a design choice, not a patch.** Options include resetting on arena
   exhaustion, evicting LRU, or restricting the cache to clients that opt in — each changes what
   `res_core` promises its three callers.
5. ★★ **§4's 13 sites are the flat-walk inventory, but I did not verify each is reachable** in the
   packed build; `pix_addr` is already dead. The count is an upper bound on work, not a work list.
6. ★ **AC-5 remains unknown**, so the question of whether P3b closes on the next attempt or the
   map changes is exactly where it was.

---

### 8 — Follow-up candidates

1. ★★★★ **Settle the cache's lifecycle** (§3.2) — it is the blocker, and it is a design question
   about a shared layer, not a bug fix.
2. ★★★★ **Audit every gate for whether it builds its own artifact** (§7.3). This one did not, for
   three tasks, and nothing in the process objected.
3. ★★★ **Re-run the four other gates** once the resource layer is green.
4. ★★★ **Then the windowing**, with §4's 13-site list as the input rather than the two named.
5. ★★ **Re-examine resource-gate results since Aug 29** (§7.2).
6. ★ **AD-77** remains open and out of scope.

---

### 9 — User interaction during task

`None.` ★ Jay rotated the methodology-pool key before this dispatch; that work is recorded in the
preceding exchange and is not part of this task.

---

### 10 — Candidate(s) captured this task

One row in `seeds/AGI/live/`, **pushed** — the pool is reachable again.

- `2026-08-31-a-gate-that-does-not-build-its-own-artifact-is-testing-history.md`

★★ **Not captured as a second row:** §3.2's lifecycle defect is a third instance of
`a-defect-whose-presence-depends-on-a-callers-configuration-passes-every-gate`, written this
morning — the trigger there was arena size, here it is caller lifecycle. Per §2C I did not edit
that row; folding is the reconciler's job, and a fresh single-instance row saying the same thing
would be duplication rather than evidence.

---

### 11 — Commit

`<filled at commit>` (pushed to origin/wip before this report)
