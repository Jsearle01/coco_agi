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
  # ★★★★★ RE-BASELINED T-P0-114 AND AGAIN T-P0-115: 14785 -> 15246 (+461), and THE FLAG SET MOVED
  # -- the cel arm now takes -DHAL_KEYBOARD, which pulls in input.s (~318 B) plus the key-to-
  # direction join. ★★★ Selecting existing HAL code is not a HAL change [T-P0-085c §6]; the six
  # text arms already took this flag and are byte-identical below, which is the proof.
  # ★★★★★ RE-BASELINED T-P0-116, AND THIS TIME ALL SEVEN MOVED, BY EXACTLY +20 B EACH. That
  # uniformity is the evidence it is one change and nothing else: p3_present now stops at the
  # GAME SCREEN (26,880 B) instead of copying all four apertures (32,768), so the picture clear's
  # white no longer lands on the text area at rows 168-199.
  # ★★★★★ p3_present IS SHARED BY EVERY CONFIGURATION -- it is not inside `ifndef P3B_NO_CEL` --
  # and the defect mattered MORE in the text arms, which are the only ones that link text.s and
  # therefore the only ones that draw in the text area at all. **Scoping the fix to the cel arm to
  # keep six hashes stable would have knowingly left it broken where it matters most.** The p3b
  # gate was run green against the moved arms before these were re-baselined [T-P0-116 §4].
  # ★★★★★ RE-BASELINED T-P0-118: SAME SIZE, DIFFERENT BYTES -- 15,266 either way, because CP_CEL
  # moved out of region A to MAP_INPUT and vm_tables relocated to the seed-stack slack. Neither
  # changes how many bytes the image holds; both change where they sit. ★★★ A size-only check
  # would have called this unchanged, which is why the baseline is a HASH.
  # ★★★★★ RE-BASELINED T-P0-121, AND ALL EIGHT MOVED BY EXACTLY +194 B. The uniformity is again
  # the evidence it is ONE change: load.pic/draw.pic/show.pic/configure.screen became the GAME's
  # to order, and vm_pic_ops.s plus p3_pic_draw/p3_pic_show/p3_pic_pending link in every arm.
  # ★★★★ PIC_WIRED IS NOT INSIDE ANY ARM'S CONDITIONAL -- every p3b configuration links the
  # renderer and owns both planes -- so scoping this to one arm was never available, and the
  # opcodes matter in the text arms too: they are what puts the copyright and the picture in the
  # game's own order. ★★★ Gates were run green against the moved arms before re-baselining.
  # ★★★★★ RE-BASELINED T-P0-122, AND THE EIGHT MOVED IN TWO DISTINCT WAYS -- which is the evidence
  # that it is two changes and exactly two. **+9 B in the five TEXT_WIRED arms**: show.pic now
  # calls txt_close, as cmdShowPic does [op_cmd.cpp:1216]. **SAME SIZE, DIFFERENT BYTES in p3b,
  # p3b_fault and p3b_flat**: show.pic was reordered into the oracle's sequence -- setFlag, then
  # closeWindow, then the reveal -- which is the same instructions in a different order.
  # ★★★★★ THAT SECOND GROUP IS THE CASE THE PARAGRAPH ABOVE PREDICTED: *"A size-only check would
  # have called this unchanged, which is why the baseline is a HASH."* Second instance, same file.
  # ★★★ The non-TEXT_WIRED arms take NO txt_close bytes, which is the guard being right: the call
  # is conditioned on the flag that DEFINES tx_window_enter, not on "text.s is linked".
  # ★★★★★ RE-BASELINED T-P0-124, AND ONLY THE TWO CEL-LINKED ARMS MOVED (+15 B each). p3_poll_dir
  # publishes VAR 19 on a non-direction key [cycle.cpp:347-349], and it lives inside
  # `ifdef P3B_CEL_LINK` AND `ifdef HAL_KEYBOARD` -- so the five P3B_NO_CEL arms are byte-identical
  # and their six gate rows are untouched. ★★★ That split is a FINDING as well as a convenience:
  # **a text-only arm cannot publish VAR 19, so have.key can never fire in one.**
  # ★★★★★ RE-BASELINED T-P0-127: the two CEL-LINKED arms moved +7 B. p3_composite_all now
  # invalidates res_curblk before every VIEW fetch, because cp_composite writes the framebuffer
  # through slot 6 and res_core skips the MMU write when its cached block matches [res_core.s:
  # 1005-1010]. **Two of four sprites were being fetched from the framebuffer and refused with
  # RES_E_SIG** -- the alligators. The five text arms link no compositor and are unchanged.
  # ★★★ +2 B more for the ytop clamp testing the BORROW instead of the SIGN: `bpl` clamped every
  # restore rectangle whose top row was >= 128 to zero, so a sprite low on the screen never had
  # its own trail erased. Jay: "they stretch as they move."
  # ★★★★★ RE-BASELINED T-P0-130, AND THE EIGHT MOVED IN TWO WAYS -- ONE PER REMOVAL.
  # **All eight +119 B**: set.view/set.loop/set.cel read the VIEW's header IN PLACE through
  # res_core.s's new read-through (res_locate / res_peek, guarded by RES_PEEK, which vm_run.s
  # defines) instead of copying the whole VIEW into the arena. Every arm links vm_run.s.
  # **p3b_comb a further -35 B**: the shipped combined arm sets COMP_NOCOUNT, so cp_composite's
  # six co_inc32 call sites are not assembled [P6.76: 11.9% of a castle cycle].
  # ★★★★ THE COUNTING ARM IS THE NINTH ROW, and before removal 2 landed it reproduced P6.76's
  # shipped bytes EXACTLY (18703 B 5F96E2BD) -- the check that the instruments moved unchanged.
  # RETIRED at T-P0-130:
  #   p3b 15,484 3F4BDC80 | p3b_text 16,715 2463C537 | p3b_win3 16,715 ED4243EC
  #   p3b_notick 16,712 02BFEBD5 | p3b_nomap 16,712 B37C6E92 | p3b_fault 15,747 AEBC7C44
  #   p3b_flat 15,732 DD0A2E91 | p3b_comb 18,703 5F96E2BD
  # ★★★★★ RE-BASELINED T-P0-131: one press, one event. p3_key_edge (the one scanner outside the
  # VBL arm), p3_key_event, the park latch recording edges, p3_poll_key draining, and the forward
  # to the editor in every arm. Deltas by composition: cel +26, text +22, fault/flat +27,
  # combined +28. **The VBL arm (-DP3B_VBLKEYS_OPT) is byte-identical** to 52567b9 (18866 B38C1357):
  # every change sits outside its branches.
  # RETIRED at T-P0-131: p3b 15,603 CF23AA0D | p3b_text 16,834 CC3B131C | p3b_win3 16,834 62F6E475
  #   p3b_notick 16,831 9E5DCF55 | p3b_nomap 16,831 4C41F35E | p3b_fault 15,866 5EBB64CF
  #   p3b_flat 15,851 4E5787F5 | p3b_comb 18,787 26895BF7 | p3b_comb_count 18,822 93D0A95F
  # ★★★★★ AND AGAIN IN T-P0-131, THE THREE CEL-LINKED ARMS ONLY, +3 B EACH: p3_composite_all now
  # calls plane_reset after the VIEW fetch, because res_open maps a VOLUME block into slot 6 and
  # plane_win's slice cache did not know -- co_put_visual wrote sprite pixels into the staged game
  # data, corrupting logic 1. **The six text arms link no compositor and are byte-identical.**
  # RETIRED within T-P0-131 (part 1, 156b7ae): p3b 15,629 F3C36B7E | p3b_comb 18,815 32F9D982 |
  #   p3b_comb_count 18,850 131A3EB6
  # ★★★★★ RE-BASELINED T-P0-132, THE TWO COMBINED ARMS ONLY, +51 B: THE 60 Hz KEY LATCH SHIPS.
  # It was parked at T-P0-128 on an eye gate it failed; P6.78 then found that what it was judged on
  # was the compositor corrupting the game's own data [p3b_probe.s's note]. Re-tested on that base:
  # 20 of 20 presses delivered (1 of 20 without), 420 castle cycles with everything moving exactly
  # as the reference does, logic 1 intact 0 of 256, and Jay: taps register, everything keeps moving.
  # ★★★ -DP3B_VBLKEYS_OPT is retired; the arm is the default and -DP3B_FAULT_NOVBLKEYS is the fault.
  # **p3b_comb is now byte-identical to the arm those measurements were taken on** (18,869 30AEF5F9).
  # RETIRED at T-P0-132: p3b_comb 18,818 BD28251C | p3b_comb_count 18,853 80A33A39
  # ★★★★★ RE-BASELINED T-P0-134, ALL NINE BY EXACTLY +72 B, AND THE UNIFORMITY IS THE EVIDENCE.
  # Every arm links res_core.s and nothing else changed: res_cache_trim (the LIFO partial
  # eviction), two counters (res_ctrim, res_cdrop), and ro_fetch's retry bounded by res_cn
  # instead of by the res_evicted latch. ★★★ The same +72 B lands on the vm probe
  # [probe_identity_check.ps1], which links res_core.s and no p3b file -- so the delta is
  # attributable to that one file rather than to anything arm-specific.
  # ★★★★ THE SHIPPED CHANGE IS THE POLICY, NOT A FLAG: -DRES_FAULT_WHOLEDROP (the old whole-region
  # drop) and -DRES_TEST_TRIMALL (§2W's reachability arm) are both absent from every row here, so
  # each is a deliberate extra build and the default is the trimmed policy.
  # RETIRED at T-P0-134: p3b 15,632 0B7B0D00 | p3b_text 16,856 A7F35693 | p3b_win3 16,856 78994468
  #   p3b_notick 16,853 4C3AC864 | p3b_nomap 16,853 DC6F6BB2 | p3b_fault 15,893 17689A91
  #   p3b_flat 15,878 681455A6 | p3b_comb 18,869 30AEF5F9 | p3b_comb_count 18,904 5A6B5DE1
  # ★★★★★ RE-BASELINED T-P0-135, AND THE NINE SHRINK -- WHICH IS THE POINT OF THE TASK.
  # $FFA6 had two owners, each keeping its own record of what slot 6 held, each correct only while
  # the other remembered to invalidate it [P6.74, P6.78]. mmu_phase.s now keeps ONE record and
  # owns the only instruction that writes the register, so every invalidation that existed to tell
  # the other owner disappears: plane_reset and its five call sites, pic_fill's two, vm_text_ops'
  # pair, and p3b's own.
  # ★★★★ THE DELTAS SPLIT BY WHAT EACH ARM LINKS, which is the check that the change is scoped:
  #   -34 p3b (cel arm) | -46 the four TEXT_WIRED | -37 fault/flat (TEXT_MODELLED) | -49 combined
  # ★★★ reg_discipline: 18 accesses in 2 files -> 6 in 1. res 1,264/1,264 and vm 9/9 run green on
  # the moved binaries before this re-baseline.
  # RETIRED at T-P0-135: p3b 15,704 5E2BD3CB | p3b_text 16,928 C8777E16 | p3b_win3 16,928 4BFEC4D7
  #   p3b_notick 16,925 7E41DCD5 | p3b_nomap 16,925 A7626E70 | p3b_fault 15,965 A889DB49
  #   p3b_flat 15,950 941B277E | p3b_comb 18,941 F201956F | p3b_comb_count 18,976 4E9BB6B5
  # ★★★★★ RE-BASELINED T-P0-136: the compositor reads the VIEW IN PLACE and the nine grow again.
  # res_core.s gains a stream cursor (RES_CURSOR) and view_cel.s a windowed source (VC_SRC_WINDOWED),
  # both declared in p3b_probe.s's source as PLANE_WIN_MMU is. **+205 B on the three cel-linked arms
  # and +151 on the six text arms**, the difference being the cel decoder itself.
  # ★★★★★ ALL FIVE GATE PROBES ARE BYTE-IDENTICAL, which is the scoping check that matters: pic,
  # cel, comp, res and vm each link one or more of the changed files and none of them sets either
  # flag, so **9,193/9,193 and 124/124 remain claims about the same program they always were.**
  # ★★★ res 1,264/1,264 and vm 9/9 run green on this source before the re-baseline.
  # RETIRED at T-P0-136: p3b 15,670 52AB9C76 | p3b_text 16,882 4D78128E | p3b_win3 16,882 F6FF8580
  #   p3b_notick 16,879 9BF4601F | p3b_nomap 16,879 217459FA | p3b_fault 15,928 C7E8CEF2
  #   p3b_flat 15,913 B393D1D0 | p3b_comb 18,892 687EFD0E | p3b_comb_count 18,927 1641F878
  @{ n = "p3b";        f = @("-DHAL_KEYBOARD");                          sz = 15875; sha = "FB06064E" },
  # ★★★★★ RE-BASELINED T-P0-125: the FIVE TEXT_WIRED arms moved +83 B (clear.lines is real), and
  # p3b, p3b_fault and p3b_flat did NOT -- the first links no text engine and the other two are
  # -DTEXT_MODELLED, which takes vm_text_ops.s's `equ` branch. ★★★ The split falls exactly along
  # TEXT_WIRED, which is the condition the implementation sits behind.
  @{ n = "p3b_text";   f = $TEXT;                                         sz = 17033; sha = "7E4AEBEC" },
  @{ n = "p3b_win3";   f = $TEXT + @("-DTEXT_WIN3");                      sz = 17033; sha = "858EC6CD" },
  @{ n = "p3b_notick"; f = $TEXT + @("-DTEXT_FAULT_NOTICK");              sz = 17030; sha = "B85CA94F" },
  @{ n = "p3b_nomap";  f = $TEXT + @("-DP3B_VOCAB_NOMAP");                sz = 17030; sha = "B02F48D2" },
  @{ n = "p3b_fault";  f = $TEXT + @("-DTEXT_MODELLED");                  sz = 16079; sha = "D3ED625F" },
  @{ n = "p3b_flat";   f = $TEXT + @("-DTEXT_MODELLED","-DTEXT_VOCAB_FLAT"); sz = 16064; sha = "A5FBBCDD" },
  # ★★★★★ THE EIGHTH ARM, NEW AT T-P0-120: text AND cels in one binary, which no build had before.
  # src/engine/text.s is `org`ed into slot 7's hole at $EBBA -- region A cannot hold both halves
  # (P6.64 measured 513 B over) and slot 7 is never remapped in either phase.
  # ★★★ It is NOT a variant of the text arms: P3B_NO_CEL keeps its own meaning and all seven arms
  # above are byte-identical. This adds a shape rather than changing one.
  # ★★ -DP3B_IRQ comes with it, as it does for every wired text build.
  # ★★★★ T-P0-128's VBL key latch is OPT-IN (-DP3B_VBLKEYS_OPT) after it failed its eye gate, so
  # the shipped combined arm is back to its P6.74 bytes. Built with the latch it was 18782 B /
  # B9F06823 (+79); that figure is recorded here so the next task re-enabling it has a reference.
  @{ n = "p3b_comb";   f = @("-DHAL_KEYBOARD","-DP3B_COMBINED","-DP3B_IRQ"); sz = 19097; sha = "793E831B" },
  # ★★★★ T-P0-130's COUNTING ARM (-Count in p3b_show.ps1): the combined arm with the pixel counters.
  @{ n = "p3b_comb_count"; f = @("-DHAL_KEYBOARD","-DP3B_COMBINED","-DP3B_IRQ","-DP3B_COUNT"); sz = 19132; sha = "AA7E8B29" }
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
# ★★★ THE COUNT IS COUNTED, NOT TYPED. It read "all 7 shipped arms" while listing EIGHT -- stale
# since p3b_comb was added at T-P0-120 -- so a passing run stated a falsehood about its own scope.
# ★★ The baseline reference is likewise the CURRENT one: it said P6.47 through three re-baselines.
# ★★★ NOT TASK-STAMPED. "P6.47" survived three re-baselines and "T-P0-121" would have gone stale
# on this one -- the fourth. The baseline is whatever is in the table above; saying so is accurate
# forever and naming a task is accurate until the next commit.
if ($bad -eq 0) { "★ all $($ARMS.Count) arms byte-identical to the recorded baseline (SHA256)" } else { "★ $bad ARM(S) MOVED"; exit 1 }
