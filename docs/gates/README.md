# docs/gates/ — artifacts a human has to look at

★★ **Everything here is for an eye gate (CLAUDE.md §4) and is tracked on purpose.** `build/` is
gitignored, so an artifact left there is invisible to anyone reading the repo — including the
Orchestrator, who fetches the tree rather than a description of it (§2E).

★★★ **Why images are allowed here at all, when T-P0-025 §11 puts "renderings or screenshots"
out of scope.** That ban exists because a rendering of a room *is* game data — Sierra's
copyrighted content in another wrapper. **These are not renderings of anything.** AC-12's
swatches are sixteen blocks of a known palette index, and the reference strip is synthesised
from EGA's published RGB values. Jay's note adds the ruling explicitly:

> ★ **AC-12 needs no game data** — sixteen blocks of a known index. ★★ **Which also means it is
> not copyrighted content and the capture can be handled normally.**

★ **So the test is not "is it a PNG", it is "does it contain game content".** A room capture
still does not belong in the repo and never will.

---

## AC-11 — the palette write path

`AC11-palette-readback.txt` — what `$FFB0`–`$FFBF` held after `pal_load`, read back **by the
guest** and masked to the low 6 bits.

★★ **The mask is documented, not discovered:** *"These registers can also be read to determine
what palettes are set but like the MMU registers, the upper 2 bits must be masked out."*
[ref: `docs/ground-truth/SockmasterGime.md` — "FFB0-FFBF Color palette registers"]. Without it
the comparison reports sixteen false mismatches.

★ **This proves the intended values LANDED. It does not prove they are the right colours.**

## AC-12 — the palette values

| file | what it is |
|---|---|
| `AC12-coco3-palette-swatches-rgb.png` | the **CoCo3**, RGB monitor (`screen_config=1`), captured from MAME |
| `AC12-reference-ega.png` | the **EGA reference**, synthesised from EGA's 16 RGB values |

**Both run index 0 at the left through index 15 at the right. Band 6 is brown** — the entry a
"double the CGA bit" conversion silently turns into dark yellow.

★★★ **THE BANDS DO NOT LINE UP HORIZONTALLY.** The CoCo3 capture is the whole MAME screen
*including the border*; the AGI picture is 320 px wide inside it. The two images share the
**order and the count, not the geometry** — count six bands in from the left in each. Finding
the border inset would mean reading pixels, which §3 forbids.

★ **A saturation difference is expected; a hue difference is not.** The GIME has four levels per
channel and EGA's values (`$00`/`$55`/`$AA`/`$FF`) land exactly on them, so the encoding is
lossless for these sixteen colours.

★★ **Neither image was interpreted by Clyde** (§3). The reference was synthesised; from the
capture only the IHDR width and height were read.

---

## AC-9 (T-P0-028) — `pq1-frame331.priority.png`

**The composite's eye gate: does a sprite go BEHIND scenery where the priority screen says it
should?** PoliceQuest1, frame 331. Produced by `harness/tools/comp_render.py` from the **6809's
own** priority plane after compositing.

### ★★★ Why this frame, and why the selection is the whole job

AC-4 found **two titles where the byte gate would pass with the priority test INVERTED** — their
sample frames contain no occlusion at all. So a frame had to be chosen on evidence, not looks.
`harness/tools/comp_pick.py` scored all **1,679** frames:

| | frames | |
|---|---|---|
| scored | 1,679 | five titles |
| **zero** priority rejections | **1,545** | **92%** — every sprite in front of everything |
| a sprite **partly** occluded | **99** | 5.9% — the only frames worth showing |

★★ **The score is per SPRITE, and the first version was per frame — which was wrong.**
SpaceQuest-1 frame 029 topped the per-frame ranking (575 rejected, 564 written) and contains **no
partly-occluded sprite at all**: one sprite is entirely hidden and a different one is entirely in
front. A per-frame total cannot tell that from "half a sprite is behind scenery", and only the
second shows a human anything.

Frame 331: one sprite, **297 pixels drawn and 620 refused by the priority test.**

### ★★ What the image shows, and how to read it

One colour per priority band — **not** the picture palette, deliberately, so it cannot be read as
a picture. Bands present:

| band | pixels | meaning |
|---|---|---|
| 4 | 3,383 | scenery **behind** the sprite → the sprite draws over it |
| **5** | **297** | ★ **the sprite's own stamp** — exactly the pixels it was allowed to draw |
| 8 | 23,200 | scenery **in front** → the sprite is refused here |

★ **Higher band = nearer.** The rule is `screenPriority <= viewPriority → draw`; the sprite is
priority 5, so band 4 accepts it and band 8 hides it. **The 297-pixel band-5 region IS the
sprite**, and its outline against band 8 is the occlusion boundary.
★★ Bands 0–2 would be **control lines, not depth** (shown in reds by the ramp). **None appear in
this frame — or in any of the 1,680** (report §7.4).

### ★★★ Launch path and what this does NOT discharge

**`static-png`** — and per §4 that is **endpoints only**. The composite ran under MAME with the
probe **poked** into RAM by Lua, so the launch path is `poke`, which §4 records as hiding
load/launch bugs.

> ★★★ §4: *"MOTION-BEARING gates require a LIVE run, not a still... For AGI this includes sprite
> compositing, priority interactions and the room-change transition."*

**Sprite compositing and priority interaction are named there explicitly.** This still verifies
one frame's occlusion and **cannot show motion** — a character *walking* behind scenery is not
demonstrated. **AC-9 is therefore reported as `static-png`, not as PASSED**, and a live run
remains outstanding.

### §2P — what is here and what is not

★★ The **composited frames are copyrighted game content and are NOT committed.** They are at
`build/gate-ac9/pq1-frame331.{coco3,oracle}.png` and were surfaced to Jay directly.
★ The **priority visualisation is ours** — sixteen flat bands of our own buffer — and is
committed, per Jay's ruling in the T-P0-028 note.
★★ **Clyde did not interpret any of the three images** (§3). Every number above comes from the
plane **buffers**, not from a rendered image.
