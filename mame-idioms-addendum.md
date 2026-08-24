# MAME idioms — ADDENDUM (recovered from earlier sessions)

> **✅ INCORPORATED 2026-07-11 — folded into the two consolidated files.** A → `mame-idioms-coco3-port.md` §9 (GIME palette-after-video-mode, addresses verified in `src/`). B, C → `mame-idioms-apple2e-oracle.md` §4b/§4a (arm-`wpset`-before-boot; headless `-debug` hang) and §5 (boot-time-static bytes). D → **both** files' visual-authority section (§10 apple2e / §11 coco3, pixel-colour provenance; tool constant `(0,0,255)` confirmed in `harness/tools/palette_derive.py`). Retained for provenance only.

**Purpose:** four additional MAME-behaviour findings recovered from the **earlier (May)
content-conversion + display-init sessions** that were not in the first two files
(`mame-idioms-apple2e-oracle.md`, `mame-idioms-coco3-port.md`). Filed as an addendum so
Clyde can fold them into the final reconciled document. Each is sourced to the pass that
established it.

---

## A. COCO3 — **GIME register write ORDER matters; palette must be written AFTER video mode**

A real CoCo3 hardware/emulator behaviour, not a code-style preference: **palette register
writes (`$FFB0-$FFB3`) do not latch correctly until the GIME's video mode is already set.**
Writing palette **before** `$FF98`/`$FF99` (video mode + resolution) results in the
mid-range palette indices **not rendering** — only the extreme values ($00 black / $3F
white) survive; indices 1 and 2 (orange, blue/cyan) come out wrong or absent.

- **The constraint:** `$FF90` (CoCo3 mode) **first** (required — the `$8000+` framebuffer
  needs CoCo3 mode for CPU access), then clear buffers, then all GIME mode/offset/SAM setup
  (`$FF98`/`$FF99`, `$FF9D`/`$FF9E`, `$FF9C`, `$FF9F`, `$FFD9`, `$FFDF`), **then palette
  `$FFB0-$FFB3` LAST.**
- **Symptom of getting it wrong:** four-band palette test shows only 2 distinct bands
  (black + white); Brøderbund logos render without orange/blue.
- **This is empirical, not Sockmaster-documented** — the source is GFXMODE3.ASM (Jay's
  working reference) and Jay's own recollection: *"the GIME needs to be completely
  initialized before palette values are written."*
- **Cost of not knowing it:** the P2.3a display-init arc burned multiple followups
  (followup-2 was NOT CONFIRMED chasing palette *values* when the real cause was *ordering*)
  before the reorder fixed it.

**Candidate name:** `gime-palette-writes-must-follow-video-mode-set`.

*Established:* P2.3a.6 display-init followup arc (followup-3, the reorder).

---

## B. APPLE2E — **`-debug` launches PAUSED; set `wpset` BEFORE releasing boot**

To catch **boot-time** writes (a byte written once during disk load, before any runtime
code runs), the watchpoint must be armed **before the machine starts booting**.

- **Method:** `mame apple2e -debug -window -flop1 <disk>` launches **paused at the first
  instruction** (debugger window open, machine halted). Set watchpoints **there**, then
  `go`.
  ```
  wpset bffd,1,w        # addr, length(bytes), access(w=write)
  wpset bffe,1,w
  wpset bfff,1,w
  wplist                # verify armed
  go                    # release; breaks when a watchpoint fires
  ```
- **`wpset` syntax varies slightly across MAME versions** — if it errors, `help wpset`.
  (The `addr,length,access` form is stable across many versions but not guaranteed.)
- This is the **interactive-debugger** route (distinct from a scripted Lua tap), and it is
  the one that works where scripted taps false-0 on this target (see the opcode-fetch
  bypass in the main apple2e file).

**Candidate name:** `mame-debug-launches-paused-arm-watchpoints-before-go`.

*Established:* the `$BFFD-$BFFF` sync-byte watchpoint experiment (Q010).

---

## C. APPLE2E — **boot-time-static bytes: written once from disk load, never by runtime code**

A data-provenance quirk that changes *how* you instrument: some bytes are **set once from
the disk image at load time and never refreshed by runtime code**. A grep of `src/` for an
instruction that writes them finds **nothing** — because no runtime instruction does; the
value came in with the disk load.

- **Symptom:** "no instruction in `src/` writes `$XXXX`" is **not** proof the value is
  dynamic or protected — it can be **static from disk load**.
- **How to tell:** a **write-watchpoint armed before boot** (idiom B) fires **at boot**
  (during load), not during the attract/runtime loop. If it only fires at boot, the byte is
  static-from-disk.
- **Why it matters:** avoids chasing a "who writes this" runtime hunt for a value nothing
  writes at runtime (the `$BFFD-$BFFF` EOR-sync bytes were static-from-load: `$00/$3B/$49`,
  set at boot, never refreshed — which resolved whether they were copy-protection).

**Candidate name:** `boot-time-static-bytes-arent-written-by-runtime-code`.

*Established:* the `$BFFD-$BFFF` sync-byte investigation (Q010).

---

## D. BOTH — **a tool render is NOT a MAME capture; verify provenance by PIXEL COLOUR, not filename**

The single most expensive MAME-adjacent trap in the project's history: **files labelled
"TRUE" / "reference" / "ground truth" were tool renders, not MAME captures**, and were used
as ground truth across **multiple iterations** — meaning the "verification" was
**tool-output vs tool-output**, never tool-vs-MAME.

- **The tell is the pixel colour.** MAME's actual rendered palette colours differ from the
  conversion tool's colour constants:
  - **MAME blue ≈ `(25,144,255)`** vs the **tool constant `(0,0,255)`**.
  - A ground-truth file that contains `(0,0,255)` is a **tool render**, not a MAME capture.
- **Filename labels establish nothing.** "diagnostic TRUE", "reference image", "ground
  truth capture" are just strings. **Content + creation method + timestamp** establish
  provenance:
  - **Pixel-colour spot-check** (does it contain MAME's palette, e.g. `(25,144,255)`, or the
    tool's `(0,0,255)`?) — the fastest tell.
  - **Timestamp** (does the file's creation time match the claimed capture session? The
    contaminated files were created at 17:43, *after* the real snaps at 14:01).
  - **Creation method** (produced by the claimed MAME capture, or by
    `sprite_render_apple2.py`?).
- **The authoritative captures:** `C:\karateka-capture\snap\apple2e\` — snaps 0082-0085,
  560×192 px, **snap 0083 = record of record**. Derive rules against **those**, spot-checked
  by pixel colour before use.
- **Companion trap — automated-check tautology.** "109/109 pixels match the rule" is
  **tautological** if the rule generated the predictions being matched. Validate against
  **independently-grounded** raw pixel coordinates from the MAME snap, not against
  rule-derived expectations. (This is *why* Jay's eye repeatedly caught an off-by-one that
  Clyde's "109/109 pass" missed — the checks were self-consistent, not ground-truthed.)

**Candidate names:** `tool-render-is-not-a-mame-capture-verify-by-pixel-colour`,
`automated-check-tautology-validate-against-ground-truth-not-rule-predictions`.

*Established:* Content Wave 1 (the 8-iteration Brøderbund-logo conversion arc), iterations
5/6/8; promoted to formal patterns (`reference-provenance-verification`,
`automated-check-tautology-avoidance`, `visual-review-as-authority`) in commit `0b5825b`.

---

## Where these slot into the two main files

- **A** → `mame-idioms-coco3-port.md` (new section: GIME register ordering — a display-init
  hardware constraint).
- **B, C** → `mame-idioms-apple2e-oracle.md` (extend §4 debugger technique with the
  arm-before-boot pattern, and add boot-time-static-bytes as an instrumentation note).
- **D** → **both** files' "visual authority is Jay's live MAME" section (§7 apple2e / §9
  coco3) — the pixel-colour provenance tell is the concrete mechanism behind "never a Clyde
  snapshot," and it applies to any capture file either target produces.

*These four were in the May sessions (P2.2 / P2.3a display-init / Content Wave 1 / Q010),
before the scene-5/6 recon that the first two files drew from — which is why they weren't in
the initial compilation. Clyde's in-repo search should confirm the exact register addresses
(A), the current `wpset` syntax (B), and the live tool colour constants (D) against the
present tooling before these are treated as canonical.*
