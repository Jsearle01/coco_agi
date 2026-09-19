# harness/tools/p3b_arms_check.ps1 -- REBUILD THE SEVEN p3b ARMS AND COMPARE BYTES. [T-P0-101 AC-5]
#
# ★★★★★ WHY THIS IS A FILE AND NOT SEVEN TYPED LINES. Every diagnostic task since T-P0-098 has had
# to answer "did any shipped artifact move", and every one of them answered it by re-typing the
# seven lwasm invocations. **A build line that exists only in a shell history is the L-45 defect
# applied to the assemble step** -- gates.manifest already says exactly this about the gate probes,
# and the p3b ARMS were still being rebuilt from memory.
#
# ★★★★ THE FLAGS COME FROM p3b_show.ps1's OWN SWITCH BLOCK, transcribed once, here. `p3b_flat` and
# `p3b_fault` are measurement arms with no gates.manifest row, which is why the manifest alone
# cannot answer the question.
#
# ★★★ OUTPUT IS DELETED BEFORE EVERY BUILD [AD-90]. lwasm writes nothing on an error, so hashing a
# file that a failed build did not touch returns the BASELINE and reports a pass. The pass would be
# the previous build's, and that has happened on this probe.
#
# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ THE ALGORITHM IS SHA256, AND THE FIRST VERSION OF THIS FILE USED MD5 AND REPORTED ALL
# SEVEN ARMS MOVED [T-P0-101, §2W]. Every hash this project has published for these arms is a
# Get-FileHash DEFAULT -- SHA256 -- truncated to 32 hex, and 32 hex is exactly the width of a full
# MD5. **A truncated SHA256 and an MD5 are indistinguishable by inspection**, so the comparison
# looked like a byte-identity check and was a comparison of two different functions.
# ★★★★ IT WAS NEARLY BELIEVED. Seven simultaneous reds after a src/ edit reads as "the guards leak",
# which is a plausible story with a plausible cause. What killed it was that the SIZES all matched
# to the byte -- a guarded block that emitted code could not leave seven binaries the same length --
# and then building `p3b` at 670fea4, the commit that PUBLISHED the baseline, reproduced the same
# supposedly-wrong bytes.
# ★★★ SO THE BASELINE'S ALGORITHM IS PART OF THE BASELINE, and it was recorded in no file. It is
# recorded here now, which is this script's other reason to exist.
#
# ★★★★★ -SelfTest IS THE §2W HALF: it builds `p3b` with ONE extra define and the row MUST read
# MOVED. A checker's green is evidence only once the same checker has been seen to go red **for the
# right reason** -- and this one has already gone red for the wrong one, which is why the
# demonstration is a switch in the file rather than a command somebody typed once.
#
# usage: powershell -File harness/tools/p3b_arms_check.ps1 [-SelfTest]
param([switch]$SelfTest)
$ErrorActionPreference = "Stop"
Set-Location C:\Projects\coco_agi
$LW   = "C:\WIN_LWTools\lwasm.exe"
$BASE = @("-DHAL_GFX_MODE_SERVICE","-DHAL_SYS_FAST_CLOCK","-DPLANE_WINDOWED","-DPRI_PACKED")
$TEXT = @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DP3B_IRQ")

# name, extra flags beyond $BASE, expected size, expected SHA256 prefix.
# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ RE-BASELINED AT T-P0-102, ALL SEVEN, AND EVERY ONE BY EXACTLY -48 BYTES.
# p3b_probe.s now defines VM_NOCOUNT, so the two AC-5 opcode counters are neither incremented nor
# cleared in any p3b arm: 2 x 14 B of dispatch-path `inc` block [vm_core.s:132,344] and 2 x 10 B
# of reset-time clear loop [vm_cycle.s:51-64]. **The same delta on all seven is the check that the
# change is the one intended** -- a flag that leaked into anything else would not land on 48.
#
# RETIRED at T-P0-102 (P6.47), superseded by the rows below:
#   p3b        13918 B  58AD3C27   ->  13870 B  F875F7F6
#   p3b_text   16258 B  5B19334F   ->  16210 B  83DD87A4
#   p3b_win3   16258 B  5400A30F   ->  16210 B  0437A07C
#   p3b_notick 16255 B  F7AE0FCF   ->  16207 B  C545C08F
#   p3b_nomap  16255 B  9604AAAA   ->  16207 B  2B552C14
#   p3b_fault  15382 B  16DC35EF   ->  15334 B  E0742D78
#   p3b_flat   15367 B  E7882A33   ->  15319 B  89818F5F
# ★★★★ THE RETIRED HASHES DESCRIBE BINARIES THAT CORRUPTED GAME DATA [P6.46]. Every timing figure
# published against `p3b` comes from one of them, and the producer has moved -- so those figures are
# retired with the binary, not carried forward [gates.manifest's vm_timed precedent, T-P0-084h].
# ★★ -DP3B_COVERAGE restores the counters at their new address and reassembles p3b_text to 16,258 B
# -- the retired size exactly, since only two immediate operands differ. **That is the check that
# the -48 is the counters and nothing else.**
# ═══════════════════════════════════════════════════════════════════════════════════════════
$ARMS = @(
  # ★★★★ THE CEL ARM CARRIES AN ACCEPTED KNOWN DEFECT [T-P0-104]. CP_CEL $5300 + 4,784 overlaps
  # RES_ARENA by 1,456 bytes, which is a static error since P6.49; -DP3B_ACCEPT_CEL_ARENA is the
  # named acceptance that keeps this arm buildable while the shape is Jay's ruling. **It changes no
  # bytes** -- an assertion emits nothing -- which is why this row's hash is unchanged.
  @{ n = "p3b";        f = @("-DP3B_ACCEPT_CEL_ARENA");                   sz = 13870; sha = "F875F7F6" },
  @{ n = "p3b_text";   f = $TEXT;                                         sz = 16210; sha = "83DD87A4" },
  @{ n = "p3b_win3";   f = $TEXT + @("-DTEXT_WIN3");                      sz = 16210; sha = "0437A07C" },
  @{ n = "p3b_notick"; f = $TEXT + @("-DTEXT_FAULT_NOTICK");              sz = 16207; sha = "C545C08F" },
  @{ n = "p3b_nomap";  f = $TEXT + @("-DP3B_VOCAB_NOMAP");                sz = 16207; sha = "2B552C14" },
  @{ n = "p3b_fault";  f = $TEXT + @("-DTEXT_MODELLED");                  sz = 15334; sha = "E0742D78" },
  @{ n = "p3b_flat";   f = $TEXT + @("-DTEXT_MODELLED","-DTEXT_VOCAB_FLAT"); sz = 15319; sha = "89818F5F" }
)

# ★★★ -DP3B_COVERAGE puts the two opcode counters back [p3b_probe.s]. It is a REAL byte change --
# +48 B, the exact delta this task's re-baseline removed -- so the row goes red on size AND on hash.
# ★★ It used to be -DVM_NOCOUNT, which p3b_probe.s now defines itself; passing it again is a
# multiply-defined symbol rather than a fault. **A self-test that stops assembling is not a red**,
# and the replacement is the better one anyway: it re-creates the configuration that was retired.
# ★★★★ IT TARGETS p3b_text, NOT p3b, AND THE REASON IS ITSELF A RESULT. `p3b` is the cel arm, whose
# flat vocabulary window runs $E3BA-$FF00 and needs 6,828 of its 7,238 bytes -- so -DP3B_COVERAGE
# there does not produce a different binary, it produces the assertion at p3b_probe.s refusing the
# build. **That is correct and it is not a self-test**: a checker whose fault arm fails to assemble
# proves the assembler works, not that the checker compares.
if ($SelfTest) { $ARMS[1].f += "-DP3B_COVERAGE"; "★ SELF-TEST: p3b_text built with -DP3B_COVERAGE -- that row MUST read MOVED" }

$bad = 0
foreach ($a in $ARMS) {
  $out = "build\arms_$($a.n).bin"
  Remove-Item -Force -ErrorAction SilentlyContinue $out
  & $LW --format=raw --output=$out -I. @($BASE + $a.f) src/harness/p3b_probe.s
  if ($LASTEXITCODE -ne 0) { "$($a.n): ASSEMBLE FAILED"; $bad++; continue }
  if (-not (Test-Path $out)) { "$($a.n): NO OUTPUT"; $bad++; continue }
  $sz = (Get-Item $out).Length
  $h  = (Get-FileHash $out).Hash          # ★ SHA256 -- see the header; MD5 here is a false red
  $ok = ($sz -eq $a.sz) -and ($h.StartsWith($a.sha))
  if (-not $ok) { $bad++ }
  "{0,-10} {1,6} B  {2}  {3}" -f $a.n, $sz, $h.Substring(0, 8), $(if ($ok) { "OK" } else { "MOVED -- expected $($a.sz) B $($a.sha)" })
}
if ($bad -eq 0) { "★ all 7 shipped arms byte-identical to the P6.47 baseline (SHA256)" } else { "★ $bad ARM(S) MOVED"; exit 1 }
