"""tools/picrender -- offline AGI PICTURE renderer (design §6).

★★ Validated against the PINNED ORACLE's rendered buffers, never against itself and never
against a golden file of our own (§2O.1, L-06, AC-9). The CoCo3 renderer at P3 diffs against
the SAME oracle -- never against this one (dispatch §12).

★ Read-only over game data throughout (§2P). Nothing here writes a game byte or a rendering.
"""
from . import screens, draw, fill, commands, render   # noqa: F401

__all__ = ["screens", "draw", "fill", "commands", "render"]
