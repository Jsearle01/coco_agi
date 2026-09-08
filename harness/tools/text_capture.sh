#!/bin/sh
# harness/tools/text_capture.sh -- capture the text decision log for several titles. [P6.18 AC-7]
#
# ★★★★★ "596 MESSAGES" WAS A CLAIM ABOUT ONE TITLE. P6.17 gated Kingquest1 and nothing else, and
# L-85 is explicit that a gate's corpus is part of its claim. This captures the rest of the v2 set
# so the text gate's scope is stated in titles rather than implied by a single number.
#
# ★★★★ EACH TITLE GETS ITS OWN OUT-DIR, so one capture cannot be read as another's [L-92]. The
# oracle writes into its working directory, and oracle_dump.sh cd's there.
#
# ★★★ The v2 nine are the VM gate's corpus (vm_run.ps1's $VM_GATE_TITLES). Kingquest4, GoldRush and
# ManhunterNewYork are v3 and are NOT gate titles -- staging rejects them, so they are not here.
#
# usage:  sh harness/tools/text_capture.sh [title ...]
set -e
cd /c/Users/jayse/DEV/coco_agi
GAMES=/c/Projects/agi-games/pc

TITLES="$*"
[ -n "$TITLES" ] || TITLES="Kingquest1 Kingquest2 Kingquest3 SpaceQuest-1 SpaceQuest-2 PoliceQuest1 larry1 BlackCauldron MixedUpMotherGoose"

for t in $TITLES; do
    [ -d "$GAMES/$t" ] || { echo "  $t : no such game dir -- skipped"; continue; }
    out="oracle/dumps/text-$t"
    TEXT_DUMP=1 sh harness/tools/oracle_dump.sh "$GAMES/$t" "$out" > "/tmp/text-$t.log" 2>&1 || true
    swept=$(grep -o 'swept [0-9]* messages across [0-9]* logics' "/tmp/text-$t.log" | head -1)
    if [ -f "$out/text_events.txt" ]; then
        g=$(grep -c '^G ' "$out/text_events.txt" || true)
        r=$(grep -c '^R ' "$out/text_events.txt" || true)
        printf '  %-20s %s   glyphs %-7s restores %s\n' "$t" "${swept:-NO SWEEP LINE}" "$g" "$r"
    else
        printf '  %-20s ★★★ no text_events.txt\n' "$t"
    fi
done
