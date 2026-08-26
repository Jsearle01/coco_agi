"""The runtime opcode dispatch table.

★★ A 256-ENTRY TABLE, NOT A SWITCH. Design intent, and it is also what the target needs: on
the 6809 this becomes a jump table indexed by the opcode byte, so the decode cost is constant
and independent of which opcode it is. A switch here would model a cost the target will not
pay and hide one it will.

★★ THE TABLE IS BUILT, NOT LOADED. optable.py holds the BASE tables transcribed from the
pinned oracle. ScummVM's setupOpCodes() (opcodes.cpp:372) then MUTATES that base according to
interpreter version, platform, gameID and feature flags. Reproducing only the base table is a
first-mechanism reading (CLAUDE.md §2H) and it is wrong for real games:

  MEASURED over the pinned corpus (194 classified rows, harness/tools/optable_flags-style
  cross-reference against detection_tables.h):
    - version-driven mutations : fire for ZERO rows. Every pinned version (0x2272, 0x2440,
      0x2917, 0x3149) sits above every version threshold in setupOpCodes().
    - feature-driven mutations : fire for 21 rows, ALL fanmade -- GF_AGIMOUSE (18) and
      GF_AGI256 (4, one row carrying both).
    - platform/gameID mutations: Apple IIgs and Amiga/AtariST GoldRush/MH1/MH2 only, and the
      corpus is CoCo3 / PC-DOS / fan.

  ★ So for the CoCo3 and Sierra DOS titles this project targets, the table is effectively
  static -- but that is a MEASURED RESULT about this corpus, not a property of AGI, and it is
  enforced below rather than assumed: an unhandled mutation raises.
"""

from . import optable

# ── how each opcode is treated by this VM. Explicit, because the alternative is a silent no-op.
#
# ★★ AN UNIMPLEMENTED OPCODE MUST FAIL LOUDLY. A VM that quietly ignores opcodes it does not
# know produces a state diff that drifts for reasons the diff cannot attribute, and the first
# divergent cycle then points at a symptom rather than a cause. Backlog L-23: a validator whose
# failure mode is unreachable validates nothing.
IMPLEMENTED = "implemented"   # affects VM state; must be exact
MODELLED = "modelled"         # presentation-only; executing it changes no diffable state
UNIMPLEMENTED = "unimplemented"


class OpcodeError(RuntimeError):
    pass


class Opcode:
    __slots__ = ("num", "name", "params", "size", "handler", "status", "handler_name")

    def __init__(self, num, name, params, handler_name):
        self.num = num
        self.name = name
        self.params = params
        # ScummVM: parameterSize = strlen(parameters). Every parameter is exactly one byte.
        self.size = len(params)
        self.handler_name = handler_name
        self.handler = None
        self.status = UNIMPLEMENTED

    def __repr__(self):
        return "<op %02X %s(%s) %s>" % (self.num, self.name, self.params, self.status)


def _mutations_for(version, platform, game_id, features):
    """Reproduce setupOpCodes()'s parameter-string mutations.

    Returns {opcode: new_parameter_string}. Handler swaps (AGI256/AGIMOUSE/Apple IIgs) are
    reported separately by `unsupported_mutations` because this VM does not implement them --
    silently applying the base handler for an AGI256 game would run the wrong opcode.
    """
    out = {}
    if 0x2000 <= version < 0x3000:
        if version == 0x2089:
            out[0x86] = ""            # quit takes 0 args for 2.089
        if version < 0x2089:
            out[0x97] = "vvv"         # print.at
            out[0x98] = "vvv"         # print.at.v
    if version >= 0x3000:
        if version == 0x3086:
            out[0xB0] = "n"           # hide.mouse
            out[0xAD] = "n"           # hold.key
        if platform == "amiga" or platform == "atarist":
            if game_id in ("goldrush", "mh1", "mh2"):
                out[0xB6] = "vv"      # adj.ego.move.to.x.y
    if platform == "apple2gs":
        out[0xB0] = "n"               # hide.mouse
        out[0xB2] = "n"               # show.mouse
    return out


def unsupported_mutations(version, platform, game_id, features):
    """Mutations that swap a HANDLER rather than an arity. This VM implements none of them, so
    they are reported as a refusal rather than silently ignored."""
    bad = []
    if "GF_AGI256" in features:
        bad.append("GF_AGI256 replaces opcode 0xAA (set.simple) with a 256-colour picture load")
    if "GF_AGIMOUSE" in features:
        bad.append("GF_AGIMOUSE replaces opcode 0xAB (push.script) with a mouse-state read")
    if platform == "apple2gs":
        bad.append("Apple IIgs remaps discard.sound and adds platform opcodes")
    if version < 0x2000:
        bad.append("AGI v1 uses an entirely different opcode table (opCodesV1)")
    return bad


class DispatchTable:
    """A 256-entry table. Entries with no opcode defined at that number are `None`."""

    def __init__(self, version, platform="dos", game_id="", features=()):
        self.version = version
        self.platform = platform
        self.game_id = game_id
        self.features = tuple(features)

        refusals = unsupported_mutations(version, platform, game_id, features)
        if refusals:
            raise OpcodeError(
                "this VM cannot run that configuration:\n  " + "\n  ".join(refusals) +
                "\n(refused rather than run with the base table -- the base table would be "
                "the WRONG interpreter for this game, and the state diff would report a "
                "divergence whose cause is the harness)")

        base_cmds = optable.V2_COMMANDS
        base_tests = optable.V2_TESTS

        mut = _mutations_for(version, platform, game_id, features)

        self.commands = [None] * 256
        for i, (name, params, handler) in enumerate(base_cmds):
            self.commands[i] = Opcode(i, name, mut.get(i, params), handler)

        self.tests = [None] * 256
        for i, (name, params, handler) in enumerate(base_tests):
            self.tests[i] = Opcode(i, name, params, handler)

        self.n_commands = len(base_cmds)
        self.n_tests = len(base_tests)

    def bind(self, command_impls, test_impls):
        """Attach implementations and mark status. Anything unbound stays UNIMPLEMENTED."""
        for op in self.commands:
            if op is None:
                continue
            impl = command_impls.get(op.handler_name)
            if impl is not None:
                op.handler, op.status = impl.fn, impl.status
        for op in self.tests:
            if op is None:
                continue
            impl = test_impls.get(op.handler_name)
            if impl is not None:
                op.handler, op.status = impl.fn, impl.status

    def coverage(self):
        def tally(tbl, n):
            c = {IMPLEMENTED: 0, MODELLED: 0, UNIMPLEMENTED: 0}
            for op in tbl[:n]:
                c[op.status] += 1
            return c
        return {"commands": tally(self.commands, self.n_commands),
                "tests": tally(self.tests, self.n_tests)}

    def unimplemented_names(self):
        out = []
        for op in self.commands[:self.n_commands]:
            if op.status == UNIMPLEMENTED and op.handler_name is not None:
                out.append(("cmd", op.num, op.name))
        for op in self.tests[:self.n_tests]:
            if op.status == UNIMPLEMENTED and op.handler_name is not None:
                out.append(("test", op.num, op.name))
        return out
