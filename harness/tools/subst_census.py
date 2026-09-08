"""harness/tools/subst_census.py -- the substitution buffer's REAL bound, at 100% coverage. [P6.21]

★★★★★ THE BUFFER HAS BEEN MEASURED ONCE AND THE MEASUREMENT DID NOT COVER THE CORPUS.
harness/tools/text_bufmax.py (P6.18) reported "printf max 490" and P6.19 sized TXT_PBUF_MAX at 768
from it -- but it walks `text_oob.swept_messages`, which is agi.cpp's sweep rule: the first EIGHT
non-empty texts of each logic. **That is 4,595 of the corpus's 14,944 messages, 31%.** The other
69% have never been substituted by anything.

★★★★ A BUFFER BOUND TAKEN OVER A THIRD OF THE INPUTS IS NOT A BOUND [L-85: the corpus is part of
the claim]. The engine must hold ANY message a game prints, not just the ones a sweep happened to
reach, so this walks every message in every logic.

★★★★★ AND IT USES THE STRICTER %m MODEL, WHICH IS ALSO THE REAL ONE. In the oracle's sweep
curLogicNr is 0, so %m reads logic 0 -- that is a property of the sweep [P6.18]. **In gameplay
curLogicNr is the RUNNING logic**, so a %m in logic 47 substitutes logic 47's own message. This
measures that: each logic's messages are printf'd with that logic as the current one, which is what
the port will actually face and is not what the gate's setting produces.

★★★ COVERAGE IS PRINTED, NOT ASSUMED. string_census.py's first two versions each produced a
plausible headline from a walk that was not working, and the coverage line is what exposed both.

★★ §2P: lengths and counts only. No message text, no substituted text, no hash of either.

usage:  python harness/tools/subst_census.py [title ...]
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
sys.path.insert(0, os.path.dirname(__file__))
from volread import resource, logic as logic_mod                   # noqa: E402
from agivm import text as textref                                  # noqa: E402
import text_oob                                                    # noqa: E402

GAMES = r"C:\Projects\agi-games\pc"


def main(argv):
    titles = argv[1:] or text_oob.V2_TITLES
    print("%-20s %7s %8s %8s %9s %9s %9s" %
          ("title", "logics", "msgs", "printf'd", "raw max", "subst max", "wrap max"))
    print("-" * 78)
    g_raw = g_sub = g_wrap = 0
    g_where = ("", 0, 0)
    t_msgs = t_done = 0
    hist = {}
    for title in titles:
        p = title if os.path.isdir(title) else os.path.join(GAMES, title)
        if not os.path.isdir(p):
            print("%-20s -- no such game dir" % title)
            continue
        game = resource.load_from_files(p)
        l0 = []
        try:
            raw0 = game.load("LOGIC", 0)
            if raw0:
                l0 = [m.decode("latin-1") for m in logic_mod.split(raw0, 0).messages]
        except Exception:                                          # noqa: BLE001
            pass

        n_log = n_msg = n_ok = 0
        raw_max = sub_max = wrap_max = 0
        for nr in range(256):
            try:
                blob = game.load("LOGIC", nr)
            except Exception:                                      # noqa: BLE001
                continue
            if not blob:
                continue
            lg = logic_mod.split(blob, nr)
            n_log += 1
            # ★★★★ THE CURRENT LOGIC IS THIS ONE. That is the whole difference from the gate's
            # setting, and it is the case the port meets in play.
            own = [m.decode("latin-1") for m in lg.messages]
            st = textref.PrintfState(logic0_texts=l0, cur_logic_texts=own)
            for m in lg.messages:
                if not m:
                    continue
                n_msg += 1
                s = m.decode("latin-1")
                try:
                    out = textref.string_printf(s, st)
                except RecursionError:
                    # ★★★ A message whose %m cycles. The port caps at TXT_SUBMAX and truncates;
                    # Python does not, so it is COUNTED and excluded rather than crashing the
                    # census -- and the count is printed, because a silent skip is how a maximum
                    # gets understated.
                    continue
                n_ok += 1
                raw_max = max(raw_max, len(s))
                if len(out) > sub_max:
                    sub_max = len(out)
                    if len(out) > g_sub:
                        g_where = (title, nr, len(out))
                wrapped, _, _ = textref.string_word_wrap(out, 30)
                wrap_max = max(wrap_max, len(wrapped))
                b = (len(out) // 128) * 128
                hist[b] = hist.get(b, 0) + 1
        print("%-20s %7d %8d %8d %9d %9d %9d"
              % (title, n_log, n_msg, n_ok, raw_max, sub_max, wrap_max))
        g_raw = max(g_raw, raw_max)
        g_sub = max(g_sub, sub_max)
        g_wrap = max(g_wrap, wrap_max)
        t_msgs += n_msg
        t_done += n_ok

    print("-" * 78)
    cov = 100.0 * t_done / t_msgs if t_msgs else 0.0
    print("coverage: %d of %d messages substituted (%.2f%%)" % (t_done, t_msgs, cov))
    if t_done == 0:
        print("★★★★★ NOTHING WAS SUBSTITUTED -- no bound is printed.")
        return 1
    if cov < 100.0:
        print("★★★ NOT EVERY MESSAGE SUBSTITUTED -- the maximum below is a LOWER BOUND.")
    print("CORPUS MAX  raw %d   substituted %d   wrapped %d" % (g_raw, g_sub, g_wrap))
    print("  longest substitution: %s logic %d, %d bytes" % g_where)
    print()
    print("distribution of substituted length (128-byte buckets):")
    for b in sorted(hist):
        print("  %5d-%5d : %6d" % (b, b + 127, hist[b]))
    print()
    print("★ prior measurement: text_bufmax.py, 490 over the SWEEP's 4,595 messages (31%)")
    print("★ current buffer   : TXT_PBUF_MAX = 768")
    for cand in (512, 576, 640, 768, 1024):
        head = cand - g_sub
        flag = "  ★★★ TOO SMALL" if head < 0 else ("  ★ %.2fx" % (cand / g_sub))
        print("  at %4d B: headroom %+5d%s" % (cand, head, flag))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
