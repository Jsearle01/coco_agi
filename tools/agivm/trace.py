"""The per-cycle state trace, in the oracle's exact format.

★★ THE FORMAT IS NOT OURS TO CHOOSE. oracle/patches/0002 emits

    cycle %06u flags <32 bytes as 64 hex chars> vars <256 bytes as 512 hex chars>\\n

and the diff is a LINE diff, so a formatting difference is indistinguishable from a state
difference: a stray width change would report every cycle as divergent, and a lucky one would
report none. The format string below mirrors the patch exactly and is checked by
harness/tools/vmdiff.py --self-test, which round-trips an oracle line through the parser.

★ Emission point: cycle ENTRY, before the cycle acts. Same as the patch.
"""


class Trace:
    def __init__(self, path):
        self.path = path
        self._fh = open(path, "w", encoding="ascii", newline="\n")
        self.count = 0

    def emit(self, cycle_nr, flags, vars_):
        self._fh.write("cycle %06u flags %s vars %s\n"
                       % (cycle_nr, flags.hex(), vars_.hex()))
        self.count += 1

    def close(self):
        self._fh.close()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()


def parse_line(line):
    """Parse one dump line into (cycle_nr, flags_bytes, vars_bytes).

    Used by both the differ and the self-test. Raises on anything malformed rather than
    returning a partial parse -- a silently-truncated vars field would make the tail of every
    comparison vacuously equal.
    """
    if not line.startswith("cycle "):
        raise ValueError("not a dump line: %r" % line[:40])
    head, _, rest = line.partition(" flags ")
    if not rest:
        raise ValueError("no flags field: %r" % line[:40])
    flags_hex, _, vars_hex = rest.partition(" vars ")
    if not vars_hex:
        raise ValueError("no vars field: %r" % line[:40])
    cycle_nr = int(head.split()[1])
    flags = bytes.fromhex(flags_hex.strip())
    vars_ = bytes.fromhex(vars_hex.strip())
    if len(flags) != 32:
        raise ValueError("flags field is %d bytes, expected 32" % len(flags))
    if len(vars_) != 256:
        raise ValueError("vars field is %d bytes, expected 256" % len(vars_))
    return cycle_nr, flags, vars_
