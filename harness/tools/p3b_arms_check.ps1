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
  # ★★★★ -DP3B_ACCEPT_CEL_ARENA IS RETIRED [T-P0-105]. The cel buffer is one row and the arena
  # assertion passes on its own terms, so this row builds clean with no acceptance flag at all.
  # RETIRED at T-P0-105: 13,870 B F875F7F6 -> 13,941 B D2C30D53 (+71). The cel decode goes a row
  # at a time, CP_CEL moves from $5300/4,784 B to $5F00/255 B, and the arena overlap is gone.
  # RETIRED at T-P0-106: 13,941 B D2C30D53 -> 13,950 B 36B1A1C3 (+9). p3_composite_all now sets
  # vc_srcend from res_base + res_len -- the bound VC_E_TRUNC tests, which this probe had NEVER
  # set, so every cel truncated on its first byte for the life of the probe.
  # RETIRED at T-P0-107: 13,950 B 36B1A1C3 -> 13,950 B 9F232F39. composite.s stops addressing a
  # windowed plane flat: co_rowvis/co_rowpri become OFFSETS and the four access sites go through
  # plane_vis/plane_pri. **Same size by coincidence** -- co_rowset loses two `addd #BASE` and the
  # access sites gain a byte each -- which is why this row is pinned by HASH and not by length.
  # RETIRED at T-P0-108: ALL SEVEN +199 bytes -- the 168-byte priority band table plus the
  # derivation in vm_update_objs. **The same delta on all seven** is the check that the change is
  # the one intended; anything else would not land on 199 everywhere.
  #   p3b 13,950 9F232F39 | p3b_text 16,210 83DD87A4 | p3b_win3 16,210 0437A07C
  #   p3b_notick 16,207 C545C08F | p3b_nomap 16,207 2B552C14 | p3b_fault 15,334 E0742D78
  #   p3b_flat 15,319 89818F5F
  # RETIRED at T-P0-109: 14,149 B 2C4DB737 -> 14,152 B 26763F91 (+3). co_put_visual doubles the
  # colour into both nibbles under -DVIS_DOUBLED (`ldb co_col / lda #17 / mul / stb ,x` replacing
  # `lda co_col / sta ,x`). **Only this arm moves**: the text arms define P3B_NO_CEL, so
  # composite.s is not linked there, and comp_probe does not define VIS_DOUBLED.
  # ★★★★★ RE-BASELINED T-P0-112, ONE ARM ONLY: 14152 -> 14666 (+514 B). The sprite restore, the
  # priority shadow and the rectangle recorder all sit inside `ifndef P3B_NO_CEL`, so the six
  # text arms below are byte-identical and were verified so rather than assumed -- that is the
  # evidence the guarding worked, and it is why only this line moves.
  # ★★★★ RE-BASELINED T-P0-114: 14666 -> 14785 (+119 B) for the changed/unchanged comparison and
  # the three identity bytes the rectangle record now carries. Six text arms unchanged again --
  # everything added sits inside `ifndef P3B_NO_CEL`, and that is verified below, not assumed.
  @{ n = "p3b";        f = @();                                          sz = 14785; sha = "B3E4AD4C" },
  @{ n = "p3b_text";   f = $TEXT;                                         sz = 16409; sha = "D09866C3" },
  @{ n = "p3b_win3";   f = $TEXT + @("-DTEXT_WIN3");                      sz = 16409; sha = "35AB01B0" },
  @{ n = "p3b_notick"; f = $TEXT + @("-DTEXT_FAULT_NOTICK");              sz = 16406; sha = "7A9A319C" },
  @{ n = "p3b_nomap";  f = $TEXT + @("-DP3B_VOCAB_NOMAP");                sz = 16406; sha = "379A9421" },
  @{ n = "p3b_fault";  f = $TEXT + @("-DTEXT_MODELLED");                  sz = 15533; sha = "FA9C8531" },
  @{ n = "p3b_flat";   f = $TEXT + @("-DTEXT_MODELLED","-DTEXT_VOCAB_FLAT"); sz = 15518; sha = "E3E95063" }
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
