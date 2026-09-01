#!/bin/sh
# harness/tools/pic_variants.sh -- run the renderer sweep across the configurations that matter.
#
# ★★★★ WHY THIS EXISTS. The renderer gate has more than one configuration and gates.manifest
# records exactly one. The shipped artifact is UNPACKED and COUNTED (2,642 B); P3b.3's published
# 2.832 s median is PACKED and -DPIC_NOCOUNT (2,971 B). **Those are four different programs and
# the project quotes figures from at least three of them.** Comparing a windowed median against
# 2.832 s without matching the configuration is the T-P0-039 error wearing new clothes.
#
# ★★★ So each variant is built AND run here, by name, and the counters/medians come out of
# pic_counters.py rather than a scrollback. -DPIC_NOCOUNT is the "separate builds" rule from
# P3.3: counting costs real time, so timing figures come from a build with the counters out.
#
# usage:  sh harness/tools/pic_variants.sh [variant ...]
#         variants: counted packed nocount nocount_packed windowed windowed_nocount
set -e
LWASM=${LWASM:-/c/WIN_LWTools/lwasm.exe}
MAME=${MAME:-/c/mame/mame.exe}
M=-DHAL_GFX_MODE_SERVICE

flags_for() {
    case "$1" in
        counted)          echo "" ;;
        packed)           echo "-DPRI_PACKED" ;;
        nocount)          echo "-DPIC_NOCOUNT" ;;
        nocount_packed)   echo "-DPIC_NOCOUNT -DPRI_PACKED" ;;
        windowed)         echo "-DPLANE_WINDOWED" ;;
        windowed_nocount) echo "-DPLANE_WINDOWED -DPIC_NOCOUNT" ;;
        *) echo "UNKNOWN" ;;
    esac
}

for v in "$@"; do
    f=$(flags_for "$v")
    [ "$f" = "UNKNOWN" ] && { echo "★★★ unknown variant $v"; exit 2; }
    bin="build/pic_v_$v.bin"
    out="build/sweep_v_$v"
    echo "═══ $v  [$M $f] ═══"
    $LWASM --raw -I. $M $f -o "$bin" src/harness/pic_probe.s
    echo "  $bin  $(stat -c %s "$bin") bytes  [source-tree $(python harness/tools/gate_audit.py --hash src/harness/pic_probe.s)]"
    rm -rf "$out"; mkdir -p "$out"
    # ★ PIC_PACKED tells the LUA the priority plane is 13,440 B rather than 26,880 -- it must
    # match the BUILD or the readback reads the wrong length and the gate reports on nothing.
    case "$v" in *packed*) export PIC_PACKED=1 ;; *) unset PIC_PACKED ;; esac
    PIC_PROG="$bin" PIC_OUT="$out" \
    "$MAME" coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize \
        -seconds_to_run "${SECS:-1800}" -autoboot_script harness/tools/pic_sweep.lua 2>&1 | tail -2
    echo "  pictures written: $(ls "$out"/*.fb.bin 2>/dev/null | wc -l)"
    python harness/tools/pic_counters.py --csv "$out/timing.csv" 2>&1 | sed 's/^/  /'
    echo
done
