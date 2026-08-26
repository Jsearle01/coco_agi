"""The motion system: movement modes and their completion flags.

Transcribed from the pinned oracle's motion.cpp.

★★ §2H CHECK 2 -- NAME THE ROUTINE THAT CALLS IT. The motion OPCODES (wander, follow.ego,
move.obj) only set state; they move nothing. checkAllMotions() -> checkMotion() is what acts on
that state, once per cycle, and ONLY for objects that are animated AND updating AND drawn AND
whose stepTimeCount has reached 1. The caller carries the scope: an object can be in
kMotionWander for many cycles and move on few of them. Reading the opcode alone gives the wrong
model of when anything happens.

★★ THE COMPLETION FLAGS. motionFollowEgo sets follow_flag on arrival (motion.cpp:173);
motionMoveObjStop sets move_flag (motion.cpp:272,285). Together with updateView's loop_flag in
objects.py these are the three sources of the flag divergence P4.1 measured and attributed.

★ RNG. motionWander and motionFollowEgo consume Common::RandomSource. agivm reproduces that
generator exactly (cycle.py RandomSource) so a diff against the oracle is meaningful -- see
§2.1 note there: it is ScummVM's generator, not Sierra's.

★ TWO SCUMMVM DEVIATIONS ARE REPRODUCED HERE DELIBERATELY, both flagged §2.1:
  motion_activated / cycler_activated. The oracle's own comments call them WORKAROUNDs for
  games relying on undefined behaviour when a cycler and a motion are active at once. The
  original AGI overwrote one field with another and could set an unintended flag; ScummVM
  reproduces the overwrite but SUPPRESSES the unintended flag (ignore_loop_flag). We diff
  against the oracle, so we do what the oracle does -- this is NOT a claim about the original.
"""

from .optable import (fAnimated, fUpdate, fDrawn, fCycling, fIgnoreBlocks, fMotion,
                      kCycleEndOfLoop, kCycleRevLoop,
                      kMotionNormal, kMotionWander, kMotionFollowEgo, kMotionMoveObj,
                      kMotionEgo,
                      VM_VAR_EGO_DIRECTION, DIR_TABLE, DIR_DX, DIR_DY)
from .state import SCREENOBJECTS_EGO_ENTRY

_ACTIVE = fAnimated | fUpdate | fDrawn


class MotionError(RuntimeError):
    pass


def is_ego(vm, obj):
    return obj is vm.state.screen_objs[SCREENOBJECTS_EGO_ENTRY]


# ── the per-cycle entry point ──────────────────────────────────────────────────────────────
def check_all_motions(vm):
    """motion.cpp checkAllMotions(). ★ Note the stepTimeCount == 1 gate -- exactly 1, not <= 1."""
    for obj in vm.state.screen_objs:
        if (obj.flags & _ACTIVE) == _ACTIVE and obj.stepTimeCount == 1:
            check_motion(vm, obj)


def check_motion(vm, obj):
    """motion.cpp checkMotion()."""
    mt = obj.motionType
    vm.motion_modes_seen[mt] = vm.motion_modes_seen.get(mt, 0) + 1
    if mt == kMotionNormal:
        pass
    elif mt == kMotionWander:
        motion_wander(vm, obj)
    elif mt == kMotionFollowEgo:
        motion_follow_ego(vm, obj)
    elif mt in (kMotionEgo, kMotionMoveObj):
        motion_move_obj(vm, obj)
    else:
        # ★★ AC-5: a silent no-op on an unhandled mode is forbidden. The oracle's `default:`
        # falls through silently; here it halts, naming the mode and the object, because a
        # mode we do not model produces a divergence whose cause the state diff cannot name.
        raise MotionError(
            "unhandled motion type %d on screen object %d (cycle %d) -- this VM models "
            "normal/wander/follow.ego/move.obj/ego only" % (mt, obj.objectNr, vm.cycle_nr))

    st = vm.state
    if st.block is not None and not (obj.flags & fIgnoreBlocks) and obj.direction:
        change_pos(vm, obj)


# ── the modes ──────────────────────────────────────────────────────────────────────────────
def motion_wander(vm, obj):
    """motion.cpp motionWander()."""
    original = obj.wander_count
    obj.wander_count = (obj.wander_count - 1) & 0xFF

    if original == 0 or (obj.flags & _DIDNT_MOVE):
        obj.direction = vm.rnd.get_random_number(8)
        if is_ego(vm, obj):
            vm.set_var(VM_VAR_EGO_DIRECTION, obj.direction)
        # ★ `while (wander_count < 6)` -- a RETRY loop, not a clamp. It re-rolls until the
        # value is >= 6, so the RNG is consumed a variable number of times. Replacing it with
        # max(6, roll) would give a different RNG stream and diverge later, elsewhere.
        while obj.wander_count < 6:
            obj.wander_count = vm.rnd.get_random_number(50)


def motion_follow_ego(vm, obj):
    """motion.cpp motionFollowEgo()."""
    ego = vm.state.ego()
    ego_x = ego.x + ego.xSize // 2
    ego_y = ego.y
    obj_x = obj.x + obj.xSize // 2
    obj_y = obj.y

    direction = get_direction(obj_x, obj_y, ego_x, ego_y, obj.follow_stepSize)

    if direction == 0:
        obj.direction = 0
        obj.motionType = kMotionNormal
        vm.state.set_flag(obj.follow_flag, True)          # ★ completion flag
        return

    if obj.follow_count == 0xFF:
        obj.follow_count = 0
    elif obj.flags & _DIDNT_MOVE:
        while True:
            obj.direction = vm.rnd.get_random_number(8)
            if obj.direction != 0:
                break
        d = (abs(ego_y - obj_y) + abs(ego_x - obj_x)) // 2
        if d < obj.stepSize:
            obj.follow_count = obj.stepSize
            return
        while True:
            obj.follow_count = vm.rnd.get_random_number(d)
            if obj.follow_count >= obj.stepSize:
                break
        return

    if obj.follow_count != 0:
        k = obj.follow_count - obj.stepSize
        # ★ the oracle stores into a uint8 then tests it AS SIGNED; a straight max(0, k) is
        # not the same expression for k in 128..255 after wrap.
        k &= 0xFF
        obj.follow_count = k
        if k > 127:
            obj.follow_count = 0
    else:
        obj.direction = direction


def motion_move_obj(vm, obj):
    """motion.cpp motionMoveObj()."""
    obj.direction = get_direction(obj.x, obj.y, obj.move_x, obj.move_y, obj.stepSize)
    if is_ego(vm, obj):
        vm.set_var(VM_VAR_EGO_DIRECTION, obj.direction)
    if obj.direction == 0:
        motion_move_obj_stop(vm, obj)


def motion_move_obj_stop(vm, obj):
    """motion.cpp motionMoveObjStop()."""
    obj.stepSize = obj.move_stepSize
    # ★ The oracle checks motionType != kMotionEgo before setting the flag, and comments that
    # the original only did this in AGI3 -- it applies the check in all versions because it
    # reuses kMotionEgo for mouse movement. Transcribed as the oracle has it.
    if obj.motionType != kMotionEgo:
        vm.state.set_flag(obj.move_flag, True)            # ★ completion flag
    obj.motionType = kMotionNormal
    if is_ego(vm, obj):
        vm.state.player_control = True
        vm.set_var(VM_VAR_EGO_DIRECTION, 0)


# ── helpers ────────────────────────────────────────────────────────────────────────────────
def check_step(delta, step):
    """motion.cpp checkStep()."""
    if -step >= delta:
        return 0
    if step <= delta:
        return 2
    return 1


def get_direction(obj_x, obj_y, dest_x, dest_y, step_size):
    """motion.cpp getDirection(). DIR_TABLE is generated from the oracle, not typed."""
    return DIR_TABLE[check_step(dest_x - obj_x, step_size)
                     + 3 * check_step(dest_y - obj_y, step_size)]


def check_block(vm, x, y):
    """motion.cpp checkBlock(). ★ STRICT inequalities on all four edges -- an object exactly
    on the block boundary is OUTSIDE it."""
    b = vm.state.block
    if b is None:
        return False
    x1, y1, x2, y2 = b
    if x <= x1 or x >= x2:
        return False
    if y <= y1 or y >= y2:
        return False
    return True


def change_pos(vm, obj):
    """motion.cpp changePos(). Blocks are a CROSSING test, not a containment test: motion is
    refused when the step would change which side of the block the object is on."""
    x, y = obj.x, obj.y
    inside = check_block(vm, x, y)

    x += obj.stepSize * DIR_DX[obj.direction]
    y += obj.stepSize * DIR_DY[obj.direction]

    if check_block(vm, x, y) == inside:
        obj.flags &= ~fMotion
    else:
        obj.flags |= fMotion
        obj.direction = 0
        if is_ego(vm, obj):
            vm.set_var(VM_VAR_EGO_DIRECTION, 0)


# ── the two cycler/motion interaction workarounds (§2.1 deviations, reproduced) ────────────
def motion_activated(vm, obj):
    """motion.cpp motionActivated(). Called by wander / follow.ego / move.obj[.v]."""
    if obj.flags & fCycling:
        if obj.cycle in (kCycleEndOfLoop, kCycleRevLoop):
            obj.ignore_loop_flag = True


def cycler_activated(vm, obj):
    """motion.cpp cyclerActivated(). Called by end.of.loop / reverse.loop.

    ★ The overwrite IS reproduced (the oracle does it "as original AGI did"); only the
    unintended flag is suppressed, via ignore_loop_flag above.
    """
    mt = obj.motionType
    if mt == kMotionWander:
        obj.wander_count = obj.loop_flag
    elif mt == kMotionFollowEgo:
        obj.follow_stepSize = obj.loop_flag
    elif mt == kMotionMoveObj:
        obj.move_x = obj.loop_flag


# fDidntMove is not in the generated ViewFlag set under that name in every version of the
# header; resolve it once here so a rename upstream fails loudly at import rather than
# silently testing bit 0.
from .optable import fDidntMove as _DIDNT_MOVE  # noqa: E402
