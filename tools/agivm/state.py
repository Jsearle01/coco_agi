"""AGI VM state.

Mirrors the fields of ScummVM's AgiGame (agi.h) that the interpreter's own behaviour depends
on. It is NOT a copy of that struct: presentation-only members (pictures, views, sounds, mouse
fence, save-game description) are absent because nothing in the state diff can observe them.

★★ THE TWO ARRAYS THAT MUST BE EXACT are `vars` and `flags`, because they ARE the diff (see
oracle/patches/0002). Everything else in this file exists only so that the opcodes writing
those two arrays are given correct inputs.

★ FLAG STORAGE IS PACKED, deliberately. ScummVM keeps 256 flags in 32 bytes and the oracle
dump emits those 32 bytes verbatim. Storing them as 256 Python bools and packing at dump time
would work, but it would put a conversion between our state and the compared bytes -- and a
conversion is a place a defect can hide on one side only. Packed here, packed there, no
transform (CLAUDE.md §2O.1 in spirit).

★★ NO CONSTANT IN THIS FILE IS TYPED BY HAND. Every VM_VAR_*, VM_FLAG_* and ViewFlag value
comes from optable.py, which is generated from the pinned oracle's headers. This was not a
stylistic choice: the first draft typed them from memory and got four VM_VAR/VM_FLAG names or
values wrong and the ENTIRE ViewFlags bit assignment wrong (fDrawn is 0x0001, fAnimated is
0x0040 -- the draft had them reversed). None of those errors raise; they silently address the
wrong variable or test the wrong bit. See harness/tools/gen_oracle_tables.py.
"""

from .optable import *  # noqa: F401,F403  -- VM_VAR_*, VM_FLAG_*, ViewFlag/Cycle/Motion enums

MAX_VARS = 256
MAX_FLAGS = 256 >> 3          # 32 bytes
MAX_STRINGS = 24              # +1 usable; MAX_STRINGS itself is used by get.num
MAX_STRINGLEN = 40
MAX_CONTROLLERS = 256
SCREENOBJECTS_MAX = 255       # KQ3 uses o255
SCREENOBJECTS_EGO_ENTRY = 0


class ScreenObj:
    """One entry of screenObjTable. Only the members the VM reads back are modelled."""

    __slots__ = ("num", "objectNr", "x", "y", "xSize", "ySize",
                 "view", "loop", "cel", "numLoops", "numCels",
                 "priority", "flags", "direction",
                 "stepSize", "stepTime", "stepTimeCount",
                 "cycleTime", "cycleTimeCount", "cycle", "motionType",
                 "loop_flag", "wander_count",
                 "follow_count", "follow_stepSize", "follow_flag",
                 "move_x", "move_y", "move_stepSize", "move_flag")

    def __init__(self, num=0):
        self.num = self.objectNr = num
        self.x = self.y = 0
        self.xSize = self.ySize = 0
        self.view = self.loop = self.cel = 0
        self.numLoops = self.numCels = 0
        self.priority = 0
        self.flags = 0
        self.direction = 0
        self.stepSize = 1
        self.stepTime = 1
        self.stepTimeCount = 1
        self.cycleTime = 1
        self.cycleTimeCount = 1
        self.cycle = 0                 # kCycleNormal
        self.motionType = 0            # kMotionNormal
        self.loop_flag = 0
        self.wander_count = 0
        self.follow_count = 0
        self.follow_stepSize = 0
        self.follow_flag = 0
        self.move_x = self.move_y = 0
        self.move_stepSize = 0
        self.move_flag = 0


class ScriptPos:
    __slots__ = ("script", "curIP")

    def __init__(self, script, curIP):
        self.script = script
        self.curIP = curIP


class VmState:
    def __init__(self):
        self.vars = bytearray(MAX_VARS)
        self.flags = bytearray(MAX_FLAGS)

        self.strings = ["" for _ in range(MAX_STRINGS + 1)]
        self.controller_occurred = [False] * MAX_CONTROLLERS

        self.horizon = 0
        self.cur_logic_nr = 0
        self.exec_stack = []
        self.player_control = False
        self.exit_all_logics = False
        self.picture_shown = False
        self.gfx_mode = False
        self.num_objects = 0
        self.test_result = False

        self.screen_objs = [ScreenObj(i) for i in range(SCREENOBJECTS_MAX)]

        # loaded resources
        self.logics = {}          # nr -> bytes of bytecode
        self.logic_messages = {}  # nr -> list[str]
        self.loaded_logics = set()
        self.loaded_views = set()
        self.loaded_pics = set()
        self.loaded_sounds = set()

        # inventory: object number -> room number (the OBJECT file's own table)
        self.object_rooms = []
        self.object_names = []

        self.cycle_inner_loop_active = False
        self.cycle_inner_loop_type = 0
        self.block = None                # (x1, y1, x2, y2) or None
        self.speed_level = 0

        # current logic execution
        self.code = b""
        self.ip = 0

    # ── flags: packed, LSB-first within each byte (ScummVM's own convention)
    def get_flag(self, n):
        return bool(self.flags[n >> 3] & (1 << (n & 7)))

    def set_flag(self, n, value):
        if value:
            self.flags[n >> 3] |= (1 << (n & 7))
        else:
            self.flags[n >> 3] &= ~(1 << (n & 7)) & 0xFF

    def ego(self):
        return self.screen_objs[SCREENOBJECTS_EGO_ENTRY]
