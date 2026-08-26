"""The V2 test (condition) opcodes, and the 0xFF conditional-expression evaluator.

Transcribed from the pinned oracle's op_test.cpp. Where a transcription is not literal it says
so and why.

★★ THE EXPRESSION EVALUATOR IS THE PART THAT MUST BE EXACT. Individual comparisons are easy
and their defects are visible. testIfCode's AND/OR/NOT handling is neither: an error there
changes which branch runs, and the wrong branch is a perfectly plausible-looking execution
that diverges cycles later somewhere else entirely. Its structure below follows ScummVM
statement for statement.
"""

from .dispatch import IMPLEMENTED, MODELLED, UNIMPLEMENTED, OpcodeError
from .optable import SAID_TEST_OPCODE, VM_VAR_KEY

EGO_OWNED = 0xFF
EGO_OWNED_V1 = 0xF9

# ViewFlags bit used by test 0x13; generated, not typed
from .optable import fAdjEgoXY  # noqa: E402


class Impl:
    __slots__ = ("fn", "status")

    def __init__(self, fn, status):
        self.fn = fn
        self.status = status


def _impl(status=IMPLEMENTED):
    def deco(fn):
        return Impl(fn, status)
    return deco


# ── comparisons ────────────────────────────────────────────────────────────────────────────
@_impl()
def condEqual(vm, p):
    vm.state.test_result = (vm.get_var(p[0]) == p[1])


@_impl()
def condEqualV(vm, p):
    vm.state.test_result = (vm.get_var(p[0]) == vm.get_var(p[1]))


@_impl()
def condLess(vm, p):
    vm.state.test_result = (vm.get_var(p[0]) < p[1])


@_impl()
def condLessV(vm, p):
    vm.state.test_result = (vm.get_var(p[0]) < vm.get_var(p[1]))


@_impl()
def condGreater(vm, p):
    vm.state.test_result = (vm.get_var(p[0]) > p[1])


@_impl()
def condGreaterV(vm, p):
    vm.state.test_result = (vm.get_var(p[0]) > vm.get_var(p[1]))


@_impl()
def condIsSet(vm, p):
    vm.state.test_result = vm.state.get_flag(p[0])


@_impl()
def condIsSetV(vm, p):
    # ★ NOT a typo for condIsSet: the parameter names a VARIABLE whose VALUE is the flag
    # number. Reading this as "flag p[0]" tests a different flag and still runs.
    vm.state.test_result = vm.state.get_flag(vm.get_var(p[0]))


# ── inventory ──────────────────────────────────────────────────────────────────────────────
@_impl()
def condHas(vm, p):
    vm.state.test_result = (vm.object_get_location(p[0]) == EGO_OWNED)


@_impl()
def condObjInRoom(vm, p):
    vm.state.test_result = (vm.object_get_location(p[0]) == vm.get_var(p[1]))


# ── positional ─────────────────────────────────────────────────────────────────────────────
@_impl()
def condPosn(vm, p):
    o = vm.state.screen_objs[p[0]]
    vm.state.test_result = (o.x >= p[1] and o.y >= p[2] and o.x <= p[3] and o.y <= p[4])


@_impl()
def condObjInBox(vm, p):
    o = vm.state.screen_objs[p[0]]
    vm.state.test_result = (o.x >= p[1] and o.y >= p[2]
                            and o.x + o.xSize - 1 <= p[3] and o.y <= p[4])


@_impl()
def condCenterPosn(vm, p):
    o = vm.state.screen_objs[p[0]]
    cx = o.x + o.xSize // 2
    vm.state.test_result = (cx >= p[1] and cx <= p[3] and o.y >= p[2] and o.y <= p[4])


@_impl()
def condRightPosn(vm, p):
    o = vm.state.screen_objs[p[0]]
    rx = o.x + o.xSize - 1
    vm.state.test_result = (rx >= p[1] and rx <= p[3] and o.y >= p[2] and o.y <= p[4])


# ── input ──────────────────────────────────────────────────────────────────────────────────
@_impl()
def condController(vm, p):
    vm.state.test_result = vm.state.controller_occurred[p[0]]


@_impl()
def condHaveKey(vm, p):
    # ★ §2.1 NOTE. ScummVM's condHaveKey pumps the event loop and can consume a real keypress.
    # This VM is headless and has no input source, so the branch below is the "no key waiting"
    # path. That is FAITHFUL FOR A RUN WITH NO INPUT -- which is what the state diff compares,
    # since the oracle is driven headless with no input either -- and WRONG the moment input is
    # introduced. Recorded here rather than left to be discovered.
    if vm.get_var(VM_VAR_KEY):
        vm.state.test_result = True
        return
    vm.state.test_result = False


@_impl()
def condSaid(vm, p):
    # `said` is variable-length and its operands are read by the evaluator, not from p[].
    vm.state.test_result = vm.test_said(p)


@_impl()
def condCompareStrings(vm, p):
    vm.state.test_result = (_normalise_string(vm.get_string(p[0]))
                            == _normalise_string(vm.get_string(p[1])))


_STRIP = set(" \t-.,:;!'")


def _normalise_string(s):
    """ScummVM testCompareStrings: strip a fixed punctuation set, lowercase the rest."""
    return "".join(c.lower() for c in s[:40] if c not in _STRIP)


@_impl()
def condUnknown13(vm, p):
    o = vm.state.ego()
    vm.state.test_result = ((o.flags & fAdjEgoXY) == fAdjEgoXY)


@_impl(MODELLED)
def condUnknown(vm, p):
    # ScummVM warns and returns false. Test opcode 0x00 is illegal; reaching it means the
    # instruction stream is desynchronised, so it is loud here rather than a silent false.
    raise OpcodeError(
        "illegal test opcode 0x00 reached -- the instruction stream is desynchronised. "
        "ScummVM warns and returns false here; this VM refuses, because a false test would "
        "hide the desync and surface it later as an unrelated state divergence.")


TEST_IMPLS = {
    "condEqual": condEqual, "condEqualV": condEqualV,
    "condLess": condLess, "condLessV": condLessV,
    "condGreater": condGreater, "condGreaterV": condGreaterV,
    "condIsSet": condIsSet, "condIsSetV": condIsSetV,
    "condHas": condHas, "condObjInRoom": condObjInRoom,
    "condPosn": condPosn, "condController": condController,
    "condHaveKey": condHaveKey, "condSaid": condSaid,
    "condCompareStrings": condCompareStrings, "condObjInBox": condObjInBox,
    "condCenterPosn": condCenterPosn, "condRightPosn": condRightPosn,
    "condUnknown13": condUnknown13, "condUnknown": condUnknown,
}


# ── the conditional-expression evaluator ───────────────────────────────────────────────────
def skip_instruction(vm, op):
    """op_test.cpp skipInstruction(). ★ `said` is the special case that matters."""
    st = vm.state
    if op >= 0xFC:
        return
    if op == SAID_TEST_OPCODE and vm.version >= 0x2000:
        # a count byte, then that many 16-bit words
        st.ip += st.code[st.ip] * 2 + 1
    else:
        st.ip += vm.table.tests[op].size


def skip_instructions_until(vm, target):
    st = vm.state
    original_ip = st.ip
    while True:
        op = st.code[st.ip]
        st.ip += 1
        if op == target:
            return
        if op < 0xFC:
            entry = vm.table.tests[op]
            if entry is None or entry.handler_name is None:
                raise OpcodeError(
                    "illegal test opcode %02X while skipping in logic %d at %d "
                    "(skip started at %d)" % (op, st.cur_logic_nr, st.ip, original_ip))
        skip_instruction(vm, op)


def test_if_code(vm):
    """op_test.cpp testIfCode(). Returns the expression's value and leaves ip positioned.

    Structure follows ScummVM statement for statement:
      0xFC  first occurrence enters OR mode; second ends a failed OR expression
      0xFD  NOT, applying to exactly one following test
      0xFF  end of expression
      else  evaluate a test opcode
    """
    st = vm.state
    not_mode = False
    or_mode = False
    end_test = False
    result = True

    while not end_test:
        op = st.code[st.ip]
        st.ip += 1

        if op == 0xFC:
            if or_mode:
                # end of an OR expression in which nothing was true -> whole expr is false
                skip_instructions_until(vm, 0xFF)
                result = False
                end_test = True
            else:
                or_mode = True
            continue
        if op == 0xFD:
            not_mode = True
            continue
        if op == 0x00 or op == 0xFF:
            end_test = True
            continue

        entry = vm.table.tests[op]
        if entry is None or entry.handler is None:
            raise OpcodeError(
                "test opcode %02X (%s) is not implemented by this VM (logic %d, ip %d)"
                % (op, entry.name if entry else "?", st.cur_logic_nr, st.ip - 1))

        # ScummVM copies 16 bytes unconditionally; `said` then reads its own operands from
        # the stream. Slicing 16 here reproduces that without reading past the buffer.
        p = st.code[st.ip:st.ip + 16]
        entry.handler(vm, p)
        if st.exit_all_logics:
            return True
        skip_instruction(vm, op)

        if not_mode:
            st.test_result = not st.test_result
        not_mode = False

        if or_mode:
            if st.test_result:
                skip_instructions_until(vm, 0xFC)
                or_mode = False
                continue
        else:
            result = result and st.test_result
            if not result:
                skip_instructions_until(vm, 0xFF)
                end_test = True
                continue

    # Skip the IF block when the expression is false
    if result:
        st.ip += 2
    else:
        st.ip += int.from_bytes(st.code[st.ip:st.ip + 2], "little") + 2
    return result
