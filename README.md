# coco_agi — a Sierra AGI interpreter for the Tandy Color Computer 3

A native 6809 reimplementation of Sierra's AGI interpreter, targeting a **512 KB CoCo3** with
GIME 16-colour video, running **unmodified original game data** from floppy or SDC.

- **Design authority:** `agi-coco3-design-v0.3.md` (held by the Orchestrator).
- **Working agreement:** [CLAUDE.md](CLAUDE.md) — project invariants; these override task contracts.
- **Ground truth:** there is no Sierra source. ScummVM's `engines/agi` and the AGI Specifications are
  *evidence*, not source — see CLAUDE.md §2 for the authority stack before citing either.
- **Game data is the user's and is read-only, absolutely** (CLAUDE.md §2P). `games/` holds manifests only.

Branch `wip` is in-flight work; `main` is coherent and deliverable.
