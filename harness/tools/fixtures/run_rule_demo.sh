#!/bin/sh
# run_rule_demo.sh -- re-run the four-part-rule demonstration from a clean checkout.
#
# ★ WHY THIS EXISTS (D-11, T-P0-001 §7.2): the demonstration that reg_discipline.py implements
# CLAUDE.md §2N's four-part rule was originally produced from a scratchpad fixture and pasted
# into a report. An instrument whose demonstration is not reproducible from a clone is an
# instrument that decays -- the report ages, the tool changes, and nothing re-checks the claim.
# This script is the standing re-check.
#
# ★ rule_fixture.s IS NOT A HARNESS PROBE and is deliberately NOT on reg_discipline.py's
# allowlist (§2N). It lives outside src/, so the default scan never reaches it; the allowlist
# stays frozenset() and adding a probe stays a visible act.
#
# Run from the repository root:   sh harness/tools/fixtures/run_rule_demo.sh
set -e

TOOL=harness/tools/reg_discipline.py
FIXTURE=harness/tools/fixtures/rule_fixture.s
EXPECTED=8

echo "=== the four-part rule, deciding line by line (CLAUDE.md 2N) ==="
python "$TOOL" --explain "$FIXTURE"

echo "=== the count, and the assertion that it is 8 ==="
python "$TOOL" --roots harness/tools/fixtures --by-register --expect "$EXPECTED"

echo
echo "=== negative control: the --expect gate must FAIL on a wrong figure ==="
# ★ A check nobody has seen fail is not a check (POP P5.19 3C). Assert the NON-zero exit.
if python "$TOOL" --roots harness/tools/fixtures --expect 7 >/dev/null 2>&1; then
    echo "FAIL: --expect 7 returned success; the assertion gate is not working."
    exit 1
fi
echo "OK: --expect 7 exited non-zero as required."
