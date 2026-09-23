#!/usr/bin/env python3
"""cel_reuse.py -- price a decoded-cel cache against a real decode sequence [T-P0-143 SS4A(2)].

WHY THIS EXISTS, AND IT IS NOT THE SAME QUESTION -CelStats ANSWERS.
-CelStats counts, in the guest, how often a staged sprite's (view, loop, cel) is the same as LAST
cycle's.  That is distance-1 reuse, and it prices a ONE-SLOT-PER-OBJECT cache and nothing else.
SS4B contemplates four slots.  A walk loop that advances one cel per cycle scores ~0% adjacency and
~100% on a cache big enough to hold the loop -- so quoting the adjacency rate as a predicted hit
rate is SS2H's first-mechanism error: the number is real and it is not the governing one.

INPUT is build/<out>/celtrace.txt, written by p3b_run.lua's P3_PHASE-9 tap:

    # <guest cycle> <view.loop.cel:skipflag> ...
    41 0.0.2:0 4.0.1:1 4.0.1:1 22.0.0:0

One line per cycle; each token is a staged sprite at the instant the composite stage is entered.
`skipflag` is P6.88's decision: 1 means the sprite was skipped and NOT decoded this cycle.

WHAT IS SIMULATED.  Requests are taken in staging order within a cycle, cycles in order.  A request
is the (view, loop, cel) triple; identical triples staged twice in one cycle are TWO requests,
because the decoder is called twice today -- that intra-cycle duplication is itself cache-visible
and the report should not hide it.  Policy is LRU over N slots, N = 1, 2, 3, 4, 6, 8, 16.

SS2V: THE 6809 FORM OF EVERY STRUCTURE HERE.
  seq          list[tuple]  -> nothing; this is host-side analysis and is never ported.
  lru          list[key]    -> on the 6809 an N-entry array scanned linearly.  N <= 8, so the scan
                              is <= 8 three-byte compares, cheaper than any hash.
  key          3-byte tuple -> three bytes (view, loop, cel) in the slot header.  No allocation.
  per-slot data             -> w*h bytes in the arena; cel_bytes.py bounds it at 1,552 B corpus-max.
This file makes no claim about the 6809; it prices the POLICY, and the policy is the portable part.
"""
import argparse
import collections
import sys


def load(path):
    """-> [(cycle, [(view, loop, cel, skipped), ...]), ...]"""
    out = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            cyc, row = int(parts[0]), []
            for tok in parts[1:]:
                ident, _, skip = tok.partition(":")
                v, l, c = (int(x) for x in ident.split("."))
                row.append((v, l, c, skip == "1"))
            out.append((cyc, row))
    return out


def load_sizes(path):
    """-> {(view, loop, cel): decoded_bytes}, from cel_runs.py --dims --tsv."""
    out = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            p = line.split("\t")
            out[(int(p[0]), int(p[1]), int(p[2]))] = int(p[3])
    return out


def loop_sim(requests, nloops, sizes):
    """Cache WHOLE LOOPS, LRU over loops. -> (hits, misses, resident_bytes_high_water).

    ★★★★★ WHY A LOOP AND NOT N CELS [T-P0-146 §4B]. P6.90's curve is FLAT at 25.1% from 1 to 14
    slots and then 95.4% at 20 -- a cliff, because room 1's three animation loops are 6, 5 and 9
    cels and each ADVANCES ONE CEL PER CYCLE. A partial cache of a cyclic sweep holds exactly the
    cels that will be wanted last. ★★★★ Caching a whole LOOP inverts that: once a loop is resident,
    every cel of it hits forever, and the loops are independent. So the useful unit is the loop,
    and the useful axis is BYTES -- one loop is 6-9 cels, which is where the storage goes.

    ★★★ A loop is admitted only if its TOTAL size is known; a cel whose size is missing from the
    table makes its loop uncacheable rather than silently free [§2W: an unknown must not price as
    zero].
    """
    by_loop = {}
    for (v, l, c) in requests:
        by_loop.setdefault((v, l), set()).add(c)
    loop_bytes, unknown = {}, set()
    for key, cels in by_loop.items():
        tot = 0
        for c in cels:
            s = sizes.get((key[0], key[1], c))
            if s is None:
                unknown.add(key)
                break
            tot += s
        else:
            loop_bytes[key] = tot

    resident, hits, misses, hw = [], 0, 0, 0
    for (v, l, c) in requests:
        key = (v, l)
        if key in unknown:
            misses += 1
            continue
        if key in resident:
            hits += 1
            resident.remove(key)
            resident.append(key)
        else:
            misses += 1                 # ★ the first touch of a loop always decodes
            resident.append(key)
            if len(resident) > nloops:
                resident.pop(0)
        hw = max(hw, sum(loop_bytes[k] for k in resident))
    return hits, misses, hw, loop_bytes, unknown


def lru_sim(requests, nslots):
    """LRU over nslots. -> (hits, misses). requests is a flat list of keys."""
    slots, hits, misses = [], 0, 0
    for k in requests:
        if k in slots:
            hits += 1
            slots.remove(k)
            slots.append(k)
        else:
            misses += 1
            slots.append(k)
            if len(slots) > nslots:
                slots.pop(0)
    return hits, misses


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--label", default="")
    ap.add_argument("--from-cycle", type=int, default=0,
                    help="ignore cycles below this -- the steady window, excluding boot and the "
                         "room render [the windowing rule every figure in this project carries]")
    ap.add_argument("--sizes", default="1,2,3,4,6,8,16")
    # ★★★★★ THE SKIP FLAG RECORDS A DECISION, NOT AN ACTION, AND UNDER -NoSkip THEY DIVERGE.
    # ★★★★ p3_skip_decide always runs and always SETS p3_skip[i]; -DP3B_NOSKIP makes
    # p3_composite_all IGNORE it. The CELTRACE tap reads the flag at P3_PHASE 9, so under -NoSkip
    # a trace marks records "skipped" that were in fact DECODED. ★★★★★ Without this switch the
    # tool then reports "0 actually decoded" for a room that decoded every staged sprite -- a
    # plausible, precise, completely wrong number [T-P0-145; §2W: an instrument proven for one
    # question is not proven for another, L-82].
    ap.add_argument("--cel-sizes", default=None,
                    help="TSV from `cel_runs.py --dims --tsv` -- enables the per-loop BYTE curve")
    ap.add_argument("--noskip", action="store_true",
                    help="the trace came from a -NoSkip build: treat every staged record as "
                         "DECODED, because the skip flags are advisory there")
    a = ap.parse_args()

    data = [(c, r) for c, r in load(a.trace) if c >= a.from_cycle]
    if not data:
        print("no cycles in window -- nothing to price", file=sys.stderr)
        return 1

    # Two request streams, and the difference is a finding in its own right:
    #   ALL     -- every staged sprite, i.e. what a build with P6.88's skip DISABLED would decode.
    #   DECODED -- only sprites P6.88 did not skip, i.e. what today's build actually decodes.
    # The cache can only save work on the second; the first says how much P6.88 already took.
    all_req = [(v, l, c) for _, row in data for (v, l, c, _s) in row]
    if a.noskip:
        dec_req = list(all_req)
    else:
        dec_req = [(v, l, c) for _, row in data for (v, l, c, s) in row if not s]
    if a.noskip:
        print("  ★ --noskip: skip flags treated as advisory; every staged record counts as decoded")

    print("%s%d cycles (%d..%d), %d staged records, %d actually decoded (%d skipped by P6.88)"
          % (a.label and a.label + ": " or "", len(data), data[0][0], data[-1][0],
             len(all_req), len(dec_req), len(all_req) - len(dec_req)))
    print("  staged %.2f/cycle, decoded %.2f/cycle"
          % (len(all_req) / len(data), len(dec_req) / len(data)))

    distinct = collections.Counter(dec_req)
    print("  distinct (view,loop,cel) among decoded: %d over %d requests -- mean %.2f uses each"
          % (len(distinct), len(dec_req),
             len(dec_req) / len(distinct) if distinct else 0))
    for k, n in distinct.most_common(8):
        print("     view %3d loop %d cel %d  x%d" % (k[0], k[1], k[2], n))

    # Adjacency, computed HOST-SIDE from the same trace -- so it can be cross-checked against the
    # guest's -CelStats number.  Two instruments agreeing is worth more than either alone [SS2W];
    # two disagreeing is a finding.
    prev = {}
    adj_seen = adj_same = 0
    for _c, row in data:
        cur = {}
        for i, (v, l, c, _s) in enumerate(row):
            adj_seen += 1
            if prev.get(i) == (v, l, c):
                adj_same += 1
            cur[i] = (v, l, c)
        prev = cur
    print("  ADJACENCY (host-side, cross-checks -CelStats): %d/%d = %.1f%% unchanged from last cycle"
          % (adj_same, adj_seen, 100 * adj_same / adj_seen if adj_seen else 0))

    # ★★★★★ THE INTRA-CYCLE ADJACENT DUPLICATE, SEPARATED OUT, BECAUSE IT IS THE ONE CLASS OF REUSE
    # THAT NEEDS NO STORAGE AT ALL.  If two consecutively-staged sprites carry the SAME triple, the
    # compositor could decode each row once and blit it to both destinations -- CP_CEL is already a
    # row buffer, so that costs zero bytes and does not change a single decoded byte.
    # ★★★ Reported as its own number so the report can say which part of a 1-slot cache's hit rate
    # is free and which part needs the map ruling.
    dup_adj = dup_cyc = 0
    for _c, row in data:
        live = ([(v, l, c) for (v, l, c, _s) in row] if a.noskip
                else [(v, l, c) for (v, l, c, s) in row if not s])
        seen = set()
        for i, k in enumerate(live):
            if i and live[i - 1] == k:
                dup_adj += 1
            if k in seen:
                dup_cyc += 1
            seen.add(k)
    print("  INTRA-CYCLE duplicates among decoded: %d adjacent (%.2f/cycle), %d anywhere in the"
          " cycle -- adjacent ones need NO storage, only a two-destination row blit"
          % (dup_adj, dup_adj / len(data), dup_cyc))

    print("  ── LRU hit rate on the DECODED stream (what a cache could actually save) ──")
    for n in (int(x) for x in a.sizes.split(",")):
        h, m = lru_sim(dec_req, n)
        print("     %2d slot%s: %5d hit / %5d miss = %5.1f%% hit   (%.2f decodes/cycle avoided)"
              % (n, " " if n == 1 else "s", h, m, 100 * h / (h + m) if h + m else 0,
                 h / len(data)))
    print("  ── the same on ALL staged records, for reference (P6.88's skip disabled) ──")
    for n in (int(x) for x in a.sizes.split(",")):
        h, m = lru_sim(all_req, n)
        print("     %2d slot%s: %5.1f%% hit" % (n, " " if n == 1 else "s",
                                                100 * h / (h + m) if h + m else 0))

    # ★★★★★ §4B: THE PER-LOOP CURVE, AGAINST BYTES. This is the axis a map ruling can act on --
    # "8,192 B of borrowed aperture buys X%" -- where a slot count cannot be placed.
    if a.cel_sizes:
        sizes = load_sizes(a.cel_sizes)
        print("  ── PER-LOOP cache, LRU over whole loops, priced in BYTES [§4B] ──")
        loops = sorted({(v, l) for (v, l, _c) in dec_req})
        print("     %d distinct loop(s) in the decoded stream: %s"
              % (len(loops), ", ".join("v%d.l%d" % k for k in loops)))
        for n in range(1, len(loops) + 1):
            h, m, hw, lb, unk = loop_sim(dec_req, n, sizes)
            print("     %2d loop%s: %5.1f%% hit   high-water %5d B   (%.2f decodes/cycle avoided)%s"
                  % (n, " " if n == 1 else "s", 100 * h / (h + m) if h + m else 0, hw,
                     h / len(data), "   ★ %d loop(s) uncacheable: size unknown" % len(unk)
                     if unk else ""))
        h, m, hw, lb, unk = loop_sim(dec_req, len(loops), sizes)
        for k in sorted(lb):
            print("        v%d.l%d = %d B" % (k[0], k[1], lb[k]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
