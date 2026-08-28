#!/usr/bin/env python3
"""harness/tools/res_stage.py -- stage a title for res_sweep.lua and produce the expected bytes.

★★ WHAT THIS DOES AND DOES NOT DO. It selects resources, writes the volume slice and the four
DIR files for the Lua to poke, and writes what tools/volread/ says each resource's bytes are.
★★★ IT DOES NOT PARSE ANYTHING THE GUEST PARSES. The DIR tables go across as RAW BYTES and the
volume slice goes across as RAW BYTES; the 6809 does the entry decode, the header parse, the
20-bit offset arithmetic and the straddling copy. If this script did any of that, AC-2 would be
comparing the reference against itself.

★ §2P: the slice and the expected bytes are game data. They are written to build/ and build/ is
not tracked; nothing here goes into the repo.
"""
import argparse
import hashlib
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from volread import resource  # noqa: E402

TYPES = ["LOGIC", "PICTURE", "VIEW", "SOUND"]
DIRFILES = ["logdir", "picdir", "viewdir", "snddir"]
BLOCK = 0x2000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("--out", default=str(ROOT / "build" / "res_stage"))
    ap.add_argument("--volume", type=int, default=0,
                    help="which VOL to stage (one per run keeps the slice small)")
    ap.add_argument("--blocks", type=int, default=40,
                    help="8 KB blocks available for the slice (L-44: stated)")
    ap.add_argument("--volbase", type=int, default=8,
                    help="first physical block used for staging")
    ap.add_argument("--max", type=int, default=0, help="cap the request count (0 = all)")
    ap.add_argument("--corrupt", default="",
                    help="AC-3: 'dir:TYPE:INDEX' or 'off:TYPE:INDEX' -- break one entry")
    a = ap.parse_args()

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    game = resource.load_from_files(a.game_dir)

    # ── the raw DIR bytes, exactly as they sit on the medium ────────────────────────────
    raw_dirs = {}
    for rt, name in zip(TYPES, DIRFILES):
        # rebuild the 3-byte entries from the parsed table -- volread keeps every slot,
        # including empties, because the index IS the identity
        buf = bytearray()
        for e in game.dirs[rt]:
            if not e.present:
                buf += b"\xFF\xFF\xFF"
            else:
                v = (e.volume & 0x0F) << 4 | ((e.offset >> 16) & 0x0F)
                buf += bytes([v, (e.offset >> 8) & 0xFF, e.offset & 0xFF])
        raw_dirs[rt] = bytearray(buf)

    # ── pick the resources that fall inside the staged slice ────────────────────────────
    # ★★★ THE LIMIT IS THE SMALLER OF THE STAGING BUDGET AND THE VOLUME ITSELF. Using the budget
    # alone put KQ1 VIEW entries at 0x20E2F on the request list for a 90,891-byte vol.2 and the
    # oracle raised rather than the guest -- a staging bug wearing a data bug's clothes.
    # ★★ THE ENTRIES ARE REAL: four of KQ1's 316 present DIR entries point past the end of their
    # own volume. They are not requested here (there are no expected bytes to compare against);
    # they go to dangling.txt, where res_run drives them as an AC-3 case the corpus supplied.
    vol = game.volumes.get(a.volume)      # VolumeSet is keyed by NUMBER, not by filename
    data = vol.data
    limit = min(a.blocks * BLOCK, len(data))
    chosen, dangling = [], []
    for ti, rt in enumerate(TYPES):
        for e in game.dirs[rt]:
            if not (e.present and e.volume == a.volume):
                continue
            if e.offset + 5 > len(data):
                dangling.append((ti, e.index, e.offset))
            elif e.offset < limit:
                chosen.append((ti, e.index, e.offset))
    chosen.sort(key=lambda c: (c[0], c[1]))
    if a.max:
        # keep the type mix rather than truncating to LOGIC alone
        per = max(1, a.max // len(TYPES))
        kept, seen = [], {i: 0 for i in range(len(TYPES))}
        for c in chosen:
            if seen[c[0]] < per:
                kept.append(c); seen[c[0]] += 1
        chosen = kept

    # ── AC-3's injected fault ───────────────────────────────────────────────────────────
    corrupt_note = "none"
    if a.corrupt:
        kind, tname, idx = a.corrupt.split(":")
        ti = TYPES.index(tname)
        idx = int(idx)
        off = ti * 0 + idx * 3
        if kind == "dir":
            raw_dirs[TYPES[ti]][off] ^= 0x01        # flip a bit in the volume/high-offset byte
            corrupt_note = f"dir byte0 of {tname} {idx} XOR 0x01"
        else:
            raw_dirs[TYPES[ti]][off + 2] ^= 0x10    # nudge the low offset byte
            corrupt_note = f"dir offset-low of {tname} {idx} XOR 0x10"

    # ── the slice, and the expected bytes ───────────────────────────────────────────────
    volname = f"vol.{a.volume}"
    slice_bytes = data[:limit]
    (out / "slice.bin").write_bytes(slice_bytes)

    for rt, name in zip(TYPES, DIRFILES):
        (out / f"{name}.bin").write_bytes(bytes(raw_dirs[rt]))

    with (out / "requests.txt").open("w", encoding="ascii", newline="\n") as f:
        for ti, idx, _off in chosen:
            f.write(f"{ti} {idx}\n")

    exp = out / "expected.bin"
    with exp.open("wb") as f:
        for ti, idx, _off in chosen:
            f.write(game.load(TYPES[ti], idx))

    with (out / "dangling.txt").open("w", encoding="ascii", newline="\n") as f:
        for ti, idx, off in dangling:
            f.write(f"{ti} {idx} {off}\n")

    with (out / "manifest.txt").open("w", encoding="ascii", newline="\n") as f:
        f.write(f"volbase {a.volbase}\n")
        f.write("slicebase 0\n")
        f.write(f"count {len(chosen)}\n")

    per_type = {TYPES[t]: sum(1 for c in chosen if c[0] == t) for t in range(len(TYPES))}
    print(f"game        : {a.game_dir}")
    print(f"volume      : {volname}, {len(data)} bytes; staged {len(slice_bytes)} "
          f"({a.blocks} blocks from block {a.volbase})")
    print(f"requests    : {len(chosen)}   {per_type}")
    print(f"expected    : {exp} ({exp.stat().st_size} bytes, "
          f"sha256 {hashlib.sha256(exp.read_bytes()).hexdigest()[:16]})")
    print(f"corruption  : {corrupt_note}")
    if dangling:
        print(f"★ DANGLING  : {len(dangling)} present DIR entries point past the end of "
              f"{volname} -- excluded from the byte gate, listed in dangling.txt")
    if len(data) > a.blocks * BLOCK:
        print(f"★ NOT STAGED: {len(data) - limit} bytes of {volname} beyond the "
              f"{a.blocks}-block window -- resources there are excluded from this run, "
              f"not silently skipped")


if __name__ == "__main__":
    main()
