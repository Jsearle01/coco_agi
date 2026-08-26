"""tools/agivm -- the offline AGI virtual machine.

Gated by a per-cycle state diff against the PINNED oracle (oracle/scummvm.pin), never against
its own previous output (CLAUDE.md §2O.1).

Modules:
  optable.py    GENERATED from the pinned oracle -- opcode tables and VM constants
  dispatch.py   the 256-entry runtime table, including setupOpCodes()'s mutations
  state.py      VM state (vars, flags, screen objects, inventory)
  tests.py      the 20 test opcodes and the 0xFF expression evaluator
  commands.py   the command opcodes, each classified implemented/modelled/unimplemented
  cycle.py      the interpreter loop, the cycle, the timer and the RNG
  trace.py      the per-cycle dump, in the oracle's exact format
"""
