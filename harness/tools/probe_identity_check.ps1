# harness/tools/probe_identity_check.ps1 -- REBUILD EVERY NON-p3b PROBE AND COMPARE BYTES.
#
# ★★★★★ THE PRECEDENT THIS ENFORCES IS vm_state.s's OWN. When the VM state block was first made
# relocatable its note said: *"THE DEFAULTS ARE UNCHANGED AND THAT IS THE POINT: every existing
# probe assembles to the same bytes, verified byte-for-byte against the pre-change binaries rather
# than assumed."* T-P0-102 moves two more symbols into that same guard, so it owes the same proof --
# and "verified rather than assumed" needs a file, not a memory of having typed five commands.
#
# ★★★★ THE ALGORITHM IS SHA256, truncated to 8 hex for display. Every hash this project publishes
# is a Get-FileHash default cut to 32 hex, which is exactly MD5's width; a checker that assumed MD5
# reported all seven p3b arms moved [P6.46 §7.1]. **The algorithm is part of the baseline.**
#
# ★★★ Flags come from gates.manifest, which is their one home. Output is deleted before each build
# [AD-90]: lwasm writes nothing on an error, so hashing an untouched file reports the baseline.
#
# usage: powershell -File harness/tools/probe_identity_check.ps1
$ErrorActionPreference = "Stop"
Set-Location C:\Projects\coco_agi
$LW = "C:\WIN_LWTools\lwasm.exe"

# name, source, flags, expected size, expected SHA256 prefix
$PROBES = @(
  # RETIRED at T-P0-108: 9,667 B 771F147D -> 9,866 B B51A6760 (+199). The priority band table and
  # its derivation live in vm_objects.s, so every probe that links the VM carries them.
  # ★★★ The vm gate is what says the behaviour is unchanged: 9/9, 0 divergent cycles of 600 each.
  @{ n = "vm";   s = "src/harness/vm_probe.s";   f = @("-DHAL_GFX_MODE_SERVICE","-DHAL_SYS_FAST_CLOCK"); sz = 9866; sha = "B51A6760" },
  @{ n = "pic";  s = "src/harness/pic_probe.s";  f = @("-DHAL_GFX_MODE_SERVICE");                        sz = 0;    sha = "" },
  @{ n = "res";  s = "src/harness/res_probe.s";  f = @("-DHAL_GFX_MODE_SERVICE");                        sz = 0;    sha = "" },
  # ★★★★ PINNED AT T-P0-105, because this one MOVED and an on-disk baseline cannot notice that.
  # RETIRED: 1,472 B -> 1,527 B 8B754B9C (+55). vc_decode_cel became a wrapper over
  # vc_decode_begin + vc_decode_row so there is ONE unpack rather than two [§2F]. **Its behaviour
  # is unchanged and the cel gate is what says so: 9,193/9,193 byte-identical, 1,525 mirrored.**
  @{ n = "cel";  s = "src/harness/cel_probe.s";  f = @("-DHAL_GFX_MODE_SERVICE","-DHAL_SYS_FAST_CLOCK"); sz = 1527; sha = "8B754B9C" },
  @{ n = "comp"; s = "src/harness/comp_probe.s"; f = @();                                                sz = 0;    sha = "" }
)

$bad = 0
foreach ($p in $PROBES) {
  $out = "build\ident_$($p.n).bin"
  $ref = "build\$($p.n)_probe.bin"
  if ($p.n -eq "comp") { $ref = "build\comp_probe.bin" }
  Remove-Item -Force -ErrorAction SilentlyContinue $out
  & $LW --format=raw --output=$out -I. @($p.f) $p.s
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { "$($p.n): ASSEMBLE FAILED"; $bad++; continue }
  $sz = (Get-Item $out).Length
  $h  = (Get-FileHash $out).Hash
  # ★★ Two sources of truth, and both are used: the pinned figures above where a task recorded
  #    them, and the on-disk artifact the gates actually run where it did not.
  $expSz = $p.sz; $expSha = $p.sha; $src = "pinned"
  if ($expSz -eq 0) {
    if (-not (Test-Path $ref)) { "$($p.n): $sz B $($h.Substring(0,8))  -- NO BASELINE (no pin, no $ref)"; $bad++; continue }
    $expSz = (Get-Item $ref).Length; $expSha = (Get-FileHash $ref).Hash.Substring(0,8); $src = "on-disk"
  }
  $ok = ($sz -eq $expSz) -and ($h.StartsWith($expSha))
  if (-not $ok) { $bad++ }
  "{0,-5} {1,6} B  {2}  [{3}]  {4}" -f $p.n, $sz, $h.Substring(0,8), $src,
    $(if ($ok) { "OK" } else { "MOVED -- expected $expSz B $expSha" })
}
if ($bad -eq 0) { "★ every non-p3b probe byte-identical" } else { "★ $bad PROBE(S) MOVED"; exit 1 }
