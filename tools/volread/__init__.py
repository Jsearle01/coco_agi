"""tools/volread -- AGI v2 resource layer, offline (design §4.2a).

★★ THE SEAM: callers ask resource.py for a (type, index) and get bytes. Nothing outside
resource.py knows which volume, which offset, or which AGI version produced them. That is what
makes the v3 deferral [design §11.1, AD-25] reversible, and harness/tools/seam_check.py
enforces it mechanically for the same reason §2N insists on a real instrument.

★ Read-only over game data throughout (§2P). No module here opens a game file for writing.
"""
from . import dirfile, volume, resource, logic, inventory, words   # noqa: F401

__all__ = ["dirfile", "volume", "resource", "logic", "inventory", "words"]
