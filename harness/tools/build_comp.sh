#!/bin/sh
# harness/tools/build_comp.sh -- assemble the three comp_probe variants.
#
# ★★★ THIS EXISTS BECAUSE THE COMMANDS EXISTED ONLY IN A SHELL HISTORY. T-P0-030 needed to
# rebuild the fault variant to re-run AC-8 and had to RECONSTRUCT the command line from the Lua
# loader's expectations -- which is L-45 exactly: **an unsaved command cannot be audited, and the
# act of saving it is itself a check.** The same rule already caught the withdrawn "88% disk"
# figure (T-P0-015) and it applies to a build line as much as to an analysis script.
#
# ★★ THE THREE VARIANTS ARE NOT INTERCHANGEABLE and the differences are load-bearing:
#   comp_probe.bin        counted    -- AC-4/AC-5 read the counters; the counting costs cycles
#   comp_probe_nc.bin     -DCOMP_NOCOUNT -- AC-2's SECONDS come from here, so the cost figure is
#                         not inflated by the instrument measuring it [the T-P0-029 separation
#                         that proved cp_do_free's inflation was not the counters]
#   comp_probe_fault.bin  -DCOMP_FAULT   -- `bhs` for `bhi` in the priority test; AC-8's proof
#                         that the gate can still FAIL, because a gate that cannot fail is not
#                         evidence that it passed
#
# ★ Raw images: the Lua loader writes them byte-for-byte at $0700 and sets PC there, so there is
# no DECB header. `-I.` because lwasm resolves `include` against the SOURCE file's directory,
# not the cwd [idioms 15a].
set -e
LWASM=${LWASM:-/c/WIN_LWTools/lwasm.exe}
mkdir -p build
$LWASM --raw -I. -o build/comp_probe.bin       src/harness/comp_probe.s
$LWASM --raw -I. -o build/comp_probe_nc.bin    -DCOMP_NOCOUNT src/harness/comp_probe.s
$LWASM --raw -I. -o build/comp_probe_fault.bin -DCOMP_FAULT   src/harness/comp_probe.s
ls -l build/comp_probe.bin build/comp_probe_nc.bin build/comp_probe_fault.bin
