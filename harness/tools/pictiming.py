#!/usr/bin/env python3
"""T-P0-012 AC-5/AC-6/AC-7: what a PICTURE costs on a real 6809, and where the time goes.

★★ MEASUREMENT MECHANISM AND RESOLUTION, stated because a figure without its method is not a
measurement. A MAME write tap on the probe's PHASE byte fires at the instant of the store and
reads `manager.machine.time` -- exact emulated time, one-instruction resolution. Not a frame
counter (16.688 ms granular), not host wall-clock (measures the host), not -seconds_to_run
(bounds a session, does not time a region).

★★★ THE CLOCK IS MEASURED, NOT ASSUMED. Every run times 20,000 iterations of an 8-cycle loop
between phases 3 and 4; cycles/seconds gives the effective CPU rate, which must land on the
CoCo3's fast 1.7898 MHz. If it lands near 0.8949 the machine is in slow mode and every figure
would be 2x out -- so the calibration is a guard, and it is reported.

★ FILL COST BY DIFFERENCE. There is no cycle counter on a 6809 and per-call instrumentation
would perturb what it measures, so the fill is timed by running the identical binary with the
flood-fill call suppressed (-DPIC_NOFILL) and subtracting. Both builds walk the same resource
and take the same branches; the delta is the fill and nothing else.
"""
import argparse
import csv
import io
import json
import pathlib
import statistics
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

CAL_CYCLES = 20000 * 8 + 9      # 20,000 x (leax -1,x = 5, bne = 3), plus setup


def load(path):
    rows = {}
    with open(path, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            rows[r["name"]] = r
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("full_csv")
    ap.add_argument("picset_json")
    ap.add_argument("--nofill-csv", default=None)
    ap.add_argument("--counts-csv", default=None,
                    help="counted build, for AC-7 structure counts; timings come from full_csv")
    args = ap.parse_args()

    full = load(args.full_csv)
    nofill = load(args.nofill_csv) if args.nofill_csv else {}
    counts = load(args.counts_csv) if args.counts_csv else full
    manifest = json.loads(pathlib.Path(args.picset_json).read_text(encoding="utf-8"))

    # --- the clock guard -----------------------------------------------------------------
    cals = [float(r["calib_s"]) for r in full.values() if float(r["calib_s"]) > 0]
    print("=" * 100)
    print("CLOCK CALIBRATION (the guard, not a decoration)")
    if cals:
        clk = CAL_CYCLES / statistics.median(cals)
        print("  %d runs; calibration interval median %.9f s over %d cycles"
              % (len(cals), statistics.median(cals), CAL_CYCLES))
        print("  -> effective CPU clock %.4f MHz" % (clk / 1e6))
        print("  -> CoCo3 fast is 1.7898 MHz, slow is 0.8949: %s"
              % ("★ FAST, as HAL_gfx_set_mode's $FFD9 write intends"
                 if abs(clk - 1789772) < 20000 else "★★ NOT FAST -- every figure below is suspect"))
        print("  spread across runs: min %.9f max %.9f (identical = emulated time is "
              "deterministic)" % (min(cals), max(cals)))
    else:
        clk = 1789772.0
        print("  ★★ NO CALIBRATION DATA -- falling back to the nominal 1.7898 MHz (UNVERIFIED)")

    # --- per picture ---------------------------------------------------------------------
    print()
    print("=" * 100)
    print("AC-5 / AC-7 -- PER-PICTURE COST ON HARDWARE")
    print("%-18s %8s %10s %8s %8s %7s %7s %8s %6s"
          % ("picture", "render_s", "Mcycles", "fill_s", "line_s", "fills", "spans", "pixels",
             "peak_B"))
    print("-" * 100)

    recs = []
    for m in manifest:
        n = m["name"]
        if n not in full:
            continue
        r = full[n]
        t = float(r["render_s"])
        if t < 0:
            continue
        nf = float(nofill[n]["render_s"]) if n in nofill else None
        fill_s = (t - nf) if nf is not None and nf > 0 else None
        rec = {
            "name": n, "t": t, "cycles": t * clk,
            "fill_s": fill_s, "line_s": nf,
            "fills": int(r["fills"]), "spans": int(r["spans"]),
            "pixels": int(r["pixels"]), "peak": int(r["sp_peak_bytes"]),
            "bytes": m["bytes"],
            # ★ structure counts come from the COUNTED build; timings from the NOCOUNT one.
            "checks": int(counts.get(n, {}).get("checks", 0) or 0),
        }
        if n in counts:
            for k in ("fills", "spans", "pixels", "peak"):
                src = {"peak": "sp_peak_bytes"}.get(k, k)
                if src in counts[n]:
                    rec[k] = int(counts[n][src])
        recs.append(rec)
        print("%-18s %8.3f %10.2f %8s %8s %7d %7d %8d %6d"
              % (n, t, rec["cycles"] / 1e6,
                 ("%.3f" % fill_s) if fill_s is not None else "-",
                 ("%.3f" % nf) if nf is not None else "-",
                 rec["fills"], rec["spans"], rec["pixels"], rec["peak"]))

    if not recs:
        print("no timing rows"); return 1

    ts = sorted(r["t"] for r in recs)
    worst = max(recs, key=lambda r: r["t"])
    print("-" * 100)
    print("AC-5 SUMMARY over %d pictures, 3 games:" % len(recs))
    print("  render time   min %.3f s   median %.3f s   max %.3f s"
          % (ts[0], statistics.median(ts), ts[-1]))
    print("  in cycles     min %.2f M   median %.2f M   max %.2f M"
          % (ts[0] * clk / 1e6, statistics.median(ts) * clk / 1e6, ts[-1] * clk / 1e6))
    print("  ★ WORST CASE: %s at %.3f s (%.2f M cycles), %d fills, %d spans, %d px"
          % (worst["name"], worst["t"], worst["cycles"] / 1e6,
             worst["fills"], worst["spans"], worst["pixels"]))

    fs = [r["fill_s"] for r in recs if r["fill_s"] is not None]
    if fs:
        tot_t = sum(r["t"] for r in recs if r["fill_s"] is not None)
        tot_f = sum(fs)
        print()
        print("  FILL vs LINE/PEN split (by difference, -DPIC_NOFILL):")
        print("    fill    min %.3f s  median %.3f s  max %.3f s" %
              (min(fs), statistics.median(fs), max(fs)))
        print("    ★ fill is %.1f%% of total render time across the set" % (100.0 * tot_f / tot_t))
        wf = [(r["fill_s"] / r["t"], r["name"]) for r in recs if r["fill_s"] and r["t"]]
        wf.sort()
        print("    most fill-dominated: %s at %.1f%%" % (wf[-1][1], 100.0 * wf[-1][0]))
        print("    least              : %s at %.1f%%" % (wf[0][1], 100.0 * wf[0][0]))

    # --- AC-6 ------------------------------------------------------------------------------
    peaks = sorted(r["peak"] for r in recs)
    pw = max(recs, key=lambda r: r["peak"])
    print()
    print("=" * 100)
    print("AC-6 -- SEED STACK PEAK, measured on hardware vs the offline prediction")
    print("  offline predicted: 102 entries = 204 bytes (over 498 pictures)")
    print("  measured here    : max %d bytes = %d entries, on %s"
          % (peaks[-1], peaks[-1] // 2, pw["name"]))
    print("  distribution     : min %d  median %d  max %d bytes"
          % (peaks[0], statistics.median(peaks), peaks[-1]))
    print("  stack provisioned: 1024 bytes = 512 entries ($0100-$04FF)")
    print("  headroom at the measured max: %.1fx" % (1024.0 / max(peaks[-1], 1)))
    if peaks[-1] > 204:
        print("  ★★ MEASURED PEAK EXCEEDS THE PREDICTION -- a finding about the offline model")
    else:
        print("  ★ measured peak is within the prediction; the sets differ, so this is "
              "consistent-with, not confirmation-of")

    # --- AC-7 ------------------------------------------------------------------------------
    print()
    print("=" * 100)
    print("AC-7 -- WHERE THE TIME GOES (worst case: %s)" % worst["name"])
    px, sp, fi = worst["pixels"], worst["spans"], worst["fills"]
    print("  pixels written to visual : %d" % px)
    print("  seed spans pushed        : %d" % sp)
    print("  fill invocations         : %d" % fi)
    print("  cycles                   : %.2f M" % (worst["cycles"] / 1e6))
    print("  cycles per visual pixel  : %.1f" % (worst["cycles"] / max(px, 1)))
    print("  cycles per span pushed   : %.1f" % (worst["cycles"] / max(sp, 1)))
    print()
    print("  ★★ §6.3 predicts RUN-STRUCTURE work beats PER-PIXEL work.")
    print("     Two candidate cost drivers, tested against the same 45 renders:")
    cpp = [(r["cycles"] / max(r["pixels"], 1), r["name"]) for r in recs]
    cpp.sort()
    vals = [c for c, _ in cpp]
    print("       per PIXEL WRITTEN : min %.0f (%s)  median %.0f  max %.0f (%s)  spread %.1fx"
          % (vals[0], cpp[0][1], statistics.median(vals), vals[-1], cpp[-1][1],
             vals[-1] / max(vals[0], 0.001)))
    chk = [r for r in recs if r.get("checks")]
    if chk:
        cpc = sorted((r["cycles"] / r["checks"], r["name"]) for r in chk)
        cv = [c for c, _ in cpc]
        print("       per FILL_CHECK    : min %.0f (%s)  median %.0f  max %.0f (%s)  spread %.2fx"
              % (cv[0], cpc[0][1], statistics.median(cv), cv[-1], cpc[-1][1],
                 cv[-1] / max(cv[0], 0.001)))
        ratio = sorted(r["checks"] / max(r["pixels"], 1) for r in chk)
        print("       fill_check calls PER PIXEL: min %.1f  median %.1f  max %.1f"
              % (ratio[0], statistics.median(ratio), ratio[-1]))
        tot_chk = sum(r["checks"] for r in chk)
        tot_px = sum(r["pixels"] for r in chk)
        print("       set totals: %d fill_check calls against %d pixels written (%.1fx)"
              % (tot_chk, tot_px, tot_chk / tot_px))
        print()
        print("     ★★★ VERDICT: the quantity with the FLATTER cost per unit is the real driver.")
        if cv[-1] / max(cv[0], 0.001) < vals[-1] / max(vals[0], 0.001):
            print("        fill_check cost is flatter (%.2fx) than per-pixel cost (%.1fx)."
                  % (cv[-1] / cv[0], vals[-1] / vals[0]))
            print("        -> Cost tracks BOUNDARY TESTS, not pixels written. A picture can")
            print("           write the same number of pixels and cost twice as much because")
            print("           its regions are shaped so the fill tests more candidates.")
            print("        ★ SUPPORTS §6.3: run structure, not pixel volume.")
        else:
            print("        per-pixel cost is flatter -- cost tracks pixel VOLUME.")
            print("        ★ DOES NOT support §6.3.")
    else:
        print("       (no fill_check counts in this CSV -- run the counted build for AC-7)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
