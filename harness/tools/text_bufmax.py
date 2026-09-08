"""harness/tools/text_bufmax.py -- how big must the port's two text buffers ACTUALLY be? [P6.19]

★★★★★ THE REFERENCE'S §2V TABLE PREDICTS 4,000 BYTES AND THERE ARE 2,374 AVAILABLE. text.py's
table inherits the oracle's two `[2000]` statics -- `resultPrintfBuffer` (text.cpp:1218) and
`resultWrappedBuffer` (1096) -- and says "2,000 B of MAP_RESERVED" for one and "2,000 B more" for
the other. MAP_RESERVED is 3,328 B and the parser already occupies 954, so **the predicted form
does not fit and the port cannot simply transcribe it.**

★★★★ §2V.2 SAYS "STATE THE MAXIMUM" AND THIS IS WHERE THAT IS CASHED. The oracle's 2,000 is a
bound chosen for a host with memory to spare, not a measurement. This measures the real one across
the whole gate corpus, at the same messages the gate runs, so the port's buffers are sized by
evidence rather than by inheritance.

★★★ IT REPORTS THE MAX, THE MESSAGE IT CAME FROM, AND THE DISTRIBUTION, because a maximum with no
margin is a maximum that a title outside the corpus will exceed [L-85]. §2P: lengths only.

usage:  python harness/tools/text_bufmax.py [title ...]
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
    g_raw = g_printf = g_wrap = 0
    g_where = ("", 0, 0)
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
        st = textref.PrintfState(logic0_texts=l0, cur_logic_texts=l0)

        t_raw = t_printf = t_wrap = 0
        for nr, t, m, lg in text_oob.swept_messages(game):
            if text_oob.FMT and False:
                pass
            s = m.decode("latin-1")
            out = textref.string_printf(s, st)
            wrapped, _, _ = textref.string_word_wrap(out, 30)
            t_raw = max(t_raw, len(s))
            if len(out) > t_printf:
                t_printf = len(out)
                if len(out) > g_printf:
                    g_where = (title, nr, t)
            t_wrap = max(t_wrap, len(wrapped))
            b = (len(out) // 128) * 128
            hist[b] = hist.get(b, 0) + 1
        print("%-20s  raw max %4d   printf max %4d   wrapped max %4d"
              % (title, t_raw, t_printf, t_wrap))
        g_raw = max(g_raw, t_raw)
        g_printf = max(g_printf, t_printf)
        g_wrap = max(g_wrap, t_wrap)

    print("-" * 72)
    print("CORPUS MAX   raw %d   printf %d   wrapped %d" % (g_raw, g_printf, g_wrap))
    print("  longest printf output: %s logic %d text %d" % g_where)
    print()
    print("distribution of printf-output length (128-byte buckets):")
    for b in sorted(hist):
        print("  %4d-%4d : %5d" % (b, b + 127, hist[b]))
    print()
    print("★ the oracle's own bound is 2000 for BOTH buffers (text.cpp:1096, :1218).")
    print("★★ measured headroom at 1024 B: printf %+d, wrapped %+d"
          % (1024 - g_printf, 1024 - g_wrap))


if __name__ == "__main__":
    main(sys.argv)
