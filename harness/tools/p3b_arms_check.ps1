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

# name, extra flags beyond $BASE, expected size, expected SHA256 prefix -- P6.40's hashes, held since.
$ARMS = @(
  @{ n = "p3b";        f = @();                                          sz = 13918; sha = "58AD3C27" },
  @{ n = "p3b_text";   f = $TEXT;                                         sz = 16258; sha = "5B19334F" },
  @{ n = "p3b_win3";   f = $TEXT + @("-DTEXT_WIN3");                      sz = 16258; sha = "5400A30F" },
  @{ n = "p3b_notick"; f = $TEXT + @("-DTEXT_FAULT_NOTICK");              sz = 16255; sha = "F7AE0FCF" },
  @{ n = "p3b_nomap";  f = $TEXT + @("-DP3B_VOCAB_NOMAP");                sz = 16255; sha = "9604AAAA" },
  @{ n = "p3b_fault";  f = $TEXT + @("-DTEXT_MODELLED");                  sz = 15382; sha = "16DC35EF" },
  @{ n = "p3b_flat";   f = $TEXT + @("-DTEXT_MODELLED","-DTEXT_VOCAB_FLAT"); sz = 15367; sha = "E7882A33" }
)

# ★★★ -DVM_NOCOUNT removes the two opcode counters [vm_core.s:132]. It is a REAL byte change with no
# behavioural risk, and it shrinks `p3b`, so the row goes red on size AND on hash.
if ($SelfTest) { $ARMS[0].f += "-DVM_NOCOUNT"; "★ SELF-TEST: p3b built with -DVM_NOCOUNT -- that row MUST read MOVED" }

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
if ($bad -eq 0) { "★ all 7 shipped arms byte-identical to P6.40" } else { "★ $bad ARM(S) MOVED"; exit 1 }
