#!/usr/bin/env python3
"""harness/tools/copy_census.py -- AC-2 and AC-3: what the VM's resource copy copies, and whether it must.

★★★★ THE STRUCTURAL FACT THIS MEASURES. Our 6809 port binds a LOGIC on every invocation:
vm_call_body does `jsr vm_bind_logic / jsr vm_run_logic / jsr res_close`, and vm_bind_logic goes
to res_open -> res_fetch, whose rfe_copy loop moves the WHOLE resource from the VOL window into
the arena. **The reference does not**: cycle.py's load_logic populates `_logic_cache` once and
never invalidates it. So the port pays per INVOCATION what the reference pays per GAME.

★★★ AC-2 counts what that costs -- invocations per cycle, bytes per invocation, and how much of
it is the same resource fetched again.

★★★★ AC-3 IS THE EXPERIMENT AND IT RUNS ENTIRELY IN THE REFERENCE [L-58]. Making the reference
re-load on every call reproduces the PORT's behaviour inside the ORACLE, so a divergence cannot
be blamed on 6809 code -- there is none in the experiment. If cached and re-loading references
agree cycle for cycle, re-copying is behaviourally neutral and the port is free to cache.
★★ The inverse framing matters: the port cannot be the thing under test, because the port is
what we would be changing.

★ Game directories are opened READ-ONLY (CLAUDE.md §2P).
"""
import argparse
import collections
import hashlib
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from agivm.cycle import Vm                      # noqa: E402
from volread import resource                    # noqa: E402


def build(game_dir, version, platform, seed):
    game = resource.load_from_files(game_dir)
    return Vm(game, version, platform=platform, seed=seed), game


def instrument(vm, game, no_cache=False):
    """Hook load_logic/load_view to count invocations, and optionally defeat the cache.

    ★★ `no_cache=True` clears the memo before each call, which makes the reference re-read the
    resource exactly as the port re-copies it. **That is the whole of AC-3's manipulation** --
    nothing else about the run changes.
    """
    stats = {"logic_calls": 0, "logic_bytes": 0, "view_calls": 0, "view_bytes": 0,
             "logic_hist": collections.Counter(), "sizes": {}}
    real_logic, real_view = vm.load_logic, vm.load_view

    def size(kind, nr):
        k = (kind, nr)
        if k not in stats["sizes"]:
            try:
                stats["sizes"][k] = len(game.load(kind, nr))
            except Exception:                                # noqa: BLE001
                stats["sizes"][k] = 0
        return stats["sizes"][k]

    def hooked_logic(nr):
        if no_cache:
            vm._logic_cache.pop(nr, None)
        stats["logic_calls"] += 1
        stats["logic_bytes"] += size("LOGIC", nr)
        stats["logic_hist"][nr] += 1
        return real_logic(nr)

    def hooked_view(nr):
        if no_cache:
            vm._view_cache.pop(nr, None)
        stats["view_calls"] += 1
        stats["view_bytes"] += size("VIEW", nr)
        return real_view(nr)

    vm.load_logic, vm.load_view = hooked_logic, hooked_view
    return stats


def state_digest(vm):
    """The same 288 bytes the VM gate compares: 32 flag bytes then 256 var bytes."""
    # ★ st.flags is ALREADY the packed 32-byte form and st.vars the 256-byte array -- exactly
    # the oracle's dump layout, so no repacking. Repacking it as if flags were 256 booleans
    # indexed past the end and raised; the shapes are worth checking rather than assuming.
    st = vm.state
    return bytes(st.flags) + bytes(st.vars)


def run(game_dir, version, platform, seed, cycles, no_cache):
    vm, game = build(game_dir, version, platform, seed)
    stats = instrument(vm, game, no_cache=no_cache)
    vm.start()
    digests = []
    h = hashlib.sha256()
    for _ in range(cycles):
        try:
            vm.run(max_cycles=vm.cycle_nr + 1)
        except Exception:                                    # noqa: BLE001
            break
        d = state_digest(vm)
        h.update(d)
        digests.append(d)
    return stats, digests, h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("--version", default="0x2917")
    ap.add_argument("--platform", default="dos")
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--cycles", type=int, default=300)
    ap.add_argument("--label", default="")
    args = ap.parse_args()

    label = args.label or pathlib.Path(args.game_dir).name
    v = int(args.version, 0)

    print(f"=== {label}   {args.cycles} cycles, seed {args.seed}")

    # ── AC-2: what the copy copies, measured on the UNMODIFIED reference ──
    s, dig_a, hash_a = run(args.game_dir, v, args.platform, args.seed, args.cycles, False)
    n = max(len(dig_a), 1)
    print(f"cycles actually run : {len(dig_a)}")
    print(f"LOGIC invocations   : {s['logic_calls']:>8}   = {s['logic_calls']/n:6.2f} per cycle")
    print(f"  bytes the PORT copies (whole resource, every invocation)")
    print(f"                    : {s['logic_bytes']:>8} B = {s['logic_bytes']/n:8.0f} B per cycle")
    print(f"VIEW  invocations   : {s['view_calls']:>8}   = {s['view_calls']/n:6.2f} per cycle")
    print(f"                    : {s['view_bytes']:>8} B = {s['view_bytes']/n:8.0f} B per cycle")

    distinct = len(s["logic_hist"])
    uniq_bytes = sum(s["sizes"][("LOGIC", k)] for k in s["logic_hist"])
    print(f"distinct LOGICs     : {distinct:>8}   holding {uniq_bytes:,} B if cached once")
    if s["logic_bytes"]:
        print(f"★ REDUNDANT FRACTION: {100*(1-uniq_bytes/s['logic_bytes']):5.1f}% of copied bytes are"
              f" a resource fetched AGAIN")
    top = s["logic_hist"].most_common(4)
    print("  most-invoked        : " + "  ".join(
        f"logic{k}x{c} ({s['sizes'][('LOGIC',k)]:,}B)" for k, c in top))

    # ── AC-3: does re-loading change anything? Both arms are the REFERENCE ──
    s2, dig_b, hash_b = run(args.game_dir, v, args.platform, args.seed, args.cycles, True)
    print()
    print("★★ AC-3 -- reference CACHED vs reference RE-LOADING (no port in the experiment):")
    print(f"  cached      {len(dig_a)} cycles  sha256 {hash_a[:16]}")
    print(f"  re-loading  {len(dig_b)} cycles  sha256 {hash_b[:16]}")
    if len(dig_a) != len(dig_b):
        print(f"  ★★★ CYCLE COUNTS DIFFER ({len(dig_a)} vs {len(dig_b)}) -- divergent")
        return 1
    bad = [i for i, (x, y) in enumerate(zip(dig_a, dig_b)) if x != y]
    if not bad:
        print(f"  ★★★★ IDENTICAL on all {len(dig_a)} cycles, 288 bytes each."
              f"  Re-copying is behaviourally NEUTRAL.")
        return 0
    print(f"  ★★★ {len(bad)} divergent cycle(s); first at {bad[0]}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
