#!/usr/bin/env python3
"""resource.py -- THE SEAM (design §4.2a). Ask for "LOGIC 3", get bytes.

★★ THIS IS THE ONLY MODULE PERMITTED TO KNOW WHICH AGI VERSION IT IS LOOKING AT (AC-8).
Callers ask for a (type, index) and receive bytes. **No caller learns which volume, which
offset, or which version produced them.** That is the whole point of §4.2a, and it is why the
v3 deferral [design §11.1, AD-25] stays reversible: adding v3 means adding a decoder behind
this seam, not editing every call site.

★ The discipline is the P1 analogue of §2N's register discipline, and the same rule will bind
`src/engine/storage/`. It is checkable mechanically -- see harness/tools/seam_check.py -- for
the same reason §2N insists on a real instrument: "nobody branches on version" is a claim about
a whole tree, and a claim about a whole tree that nothing verifies decays.

★★ v2 ONLY THIS TASK [design §11.1, dispatch §4.1]. No LZW, no combined-DIR loader, no 4-bit
PICTURE packing. A v3-shaped game raises rather than guessing -- ★ silently mis-decoding a v3
resource as v2 would produce plausible bytes, and "plausible bytes" is the failure mode the
whole oracle diff exists to catch.
"""
import pathlib

from . import dirfile
from . import volume as volmod

LOGIC, PICTURE, VIEW, SOUND = "LOGIC", "PICTURE", "VIEW", "SOUND"
RES_TYPES = (LOGIC, PICTURE, VIEW, SOUND)

# ★ The four DIR filenames, per type, in the two casings the corpora actually use. AC-9
# requires both: the fan set ships `logdir`, the CoCo3 OS-9 media ships `logDir`. These are
# CANDIDATE names matched case-insensitively by the loader below -- the parser never assumes a
# casing, because assuming one is precisely what makes a tool work on one corpus and not the
# other (dispatch §4.3).
DIR_NAMES = {
    LOGIC:   "logdir",
    PICTURE: "picdir",
    VIEW:    "viewdir",
    SOUND:   "snddir",
}


class ResourceError(Exception):
    pass


class UnsupportedVersion(ResourceError):
    pass


class Game:
    """A v2 AGI game's resource layer: DIR tables plus its VOL set."""

    def __init__(self, label, dirs, volumes, version="v2", extras=None):
        self.label = label                 # ★ names the IMAGE/variant, not the title (L-24)
        self.dirs = dirs                   # {restype: [DirEntry]}
        self.volumes = volumes             # VolumeSet
        self.version = version
        self.extras = extras or {}         # words.tok / object raw bytes, if present

    # ---- the seam -------------------------------------------------------------------

    def _header_len(self):
        """★ THE ONLY VERSION BRANCH IN THE PROJECT'S PYTHON RESOURCE LAYER."""
        if self.version == "v2":
            return volmod.V2_HEADER_LEN
        raise UnsupportedVersion(
            "%s: version %r is not supported this phase (v2 only, design §11.1). "
            "A v3 decoder goes BEHIND this seam, not around it." % (self.label, self.version))

    def entry(self, restype, index):
        try:
            entries = self.dirs[restype]
        except KeyError:
            raise ResourceError("%s: no %s directory" % (self.label, restype))
        if index < 0 or index >= len(entries):
            raise ResourceError("%s: %s %d out of range (0..%d)"
                                % (self.label, restype, index, len(entries) - 1))
        return entries[index]

    def present(self, restype, index):
        return self.entry(restype, index).present

    def load(self, restype, index):
        """★ THE ENTRY POINT. -> raw resource bytes, exactly as the oracle would load them.

        'Raw' means post-record-header and pre-decode: the same bytes ScummVM's
        loadVolumeResource() hands to its per-type decoder. That is deliberate, because AC-5
        diffs against exactly that buffer -- comparing anything further downstream would be
        comparing our decode to theirs, which is a different and weaker claim.
        """
        e = self.entry(restype, index)
        if not e.present:
            raise ResourceError("%s: %s %d is an empty slot" % (self.label, restype, index))
        payload, declared, _vol_byte = self.volumes.read(e.volume, e.offset, self._header_len())
        return payload

    def iter_present(self, restype=None):
        for rt in (RES_TYPES if restype is None else (restype,)):
            for e in self.dirs.get(rt, ()):
                if e.present:
                    yield e

    def counts(self):
        out = {}
        for rt in RES_TYPES:
            entries = self.dirs.get(rt, ())
            out[rt] = (sum(1 for e in entries if e.present), len(entries))   # (present, slots)
        return out


# ---- loading a game from either corpus ----------------------------------------------------

def _find_ci(names, want):
    """Case-insensitive lookup. ★ AC-9: `logdir` vs `logDir` is a real corpus difference."""
    low = want.lower()
    for n in names:
        if n.lower().rsplit("/", 1)[-1] == low:
            return n
    return None


def detect_v3_volume_format(volumes, logic0_volume):
    """Does this game use V3 VOLUMES despite having V2 DIRECTORY files?

    ★★ THIS IS A REAL AND DOCUMENTED CASE, NOT AN EDGE. The oracle's own comment
    (loader_v2.cpp:61-71) states it:

        "The CoCo3 version of Leisure Suit Larry uses a V3 volume, even though it is a V2 game
         with V2 directory files. Sierra's other CoCo3 release, King's Quest III, uses regular
         V2 volumes. Fan ports of DOS games to CoCo3 use V3 volumes; presumably they used the
         Leisure Suit Larry interpreter."

    So "v2" is TWO independent facts -- v2 directories and v2 volumes -- and a game can be v2 in
    one and v3 in the other. Detecting only the DIR shape, as `_detect_version` does, answers
    the wrong half.

    ★ THE ALGORITHM IS THE ORACLE'S, NOT A HEURISTIC OF MINE (loader_v2.cpp:72-115). My first
    attempt guessed from whether a plausible `clen` sat at +5 and classified EVERY CoCo3 title
    as v3 including ones where len == clen -- unfalsifiable, and L-23's exact warning. ScummVM
    instead walks TEN consecutive records under the 7-byte assumption and requires all of them
    to hold: signature 0x1234, (header[2] & 0x7f) == the volume number, and the next record
    landing where clen says it will. A wrong assumption desynchronises within a record or two,
    so ten in a row is a real test that CAN fail.
    """
    try:
        vol = volumes.get(logic0_volume)
    except volmod.VolumeError:
        return False
    data = vol.data
    pos = 0
    for _ in range(10):
        if pos + 7 > len(data):
            return False
        if ((data[pos] << 8) | data[pos + 1]) != volmod.SIGNATURE:
            return False
        if (data[pos + 2] & 0x7F) != logic0_volume:
            return False
        clen = data[pos + 5] | (data[pos + 6] << 8)
        pos += 7 + clen
        if pos > len(data):
            return False
        if pos == len(data):
            break          # ran out exactly at the end: consistent
    return True


def _detect_version(names):
    """v2 iff all four separate DIR files are present. Anything else is refused, not guessed.

    ★ L-23: a check whose failure mode is unreachable validates nothing. This one CAN fail and
    is meant to -- a v3 game has one combined `<prefix>dir` and no `logdir`, so it lands in the
    raise below rather than being silently parsed as v2.
    """
    if all(_find_ci(names, DIR_NAMES[rt]) for rt in RES_TYPES):
        return "v2"
    combined = [n for n in names if n.lower().rsplit("/", 1)[-1].endswith("dir")]
    return "v3-shaped" if combined else "unknown"


def load_from_files(directory, label=None):
    """Load a game from a plain directory of files (the pinned fan corpus)."""
    d = pathlib.Path(directory)
    names = [p.name for p in d.iterdir() if p.is_file()]
    blobs = {}
    for p in d.iterdir():
        if p.is_file():
            blobs[p.name] = p.read_bytes()                  # 'rb' -- read only (§2P)
    return load_from_blobs(blobs, label or d.name)


def load_from_blobs(blobs, label):
    """Load a game from name -> bytes. ★ This is the form that makes AC-9 possible: an OS-9
    image yields blobs with no host files involved, and the parser cannot tell the difference."""
    names = list(blobs)
    version = _detect_version(names)
    if version != "v2":
        raise UnsupportedVersion(
            "%s: detected %s; v2 only this phase (design §11.1)" % (label, version))

    dirs = {}
    for rt in RES_TYPES:
        key = _find_ci(names, DIR_NAMES[rt])
        dirs[rt] = dirfile.parse_dir_bytes(blobs[key], rt)

    vols = volmod.VolumeSet()
    for n in names:
        base = n.lower().rsplit("/", 1)[-1]
        if base.startswith("vol.") and base[4:].isdigit():
            vols.add_bytes(int(base[4:]), n, blobs[n])

    # ★★ The second half of "is this v2": the VOLUME format, which is independent of the DIR
    # format (see detect_v3_volume_format). A v3 volume means LZW, which design §11.1 defers,
    # so such a game is REFUSED here rather than mis-parsed with a 5-byte header -- the latter
    # yields plausible-looking bytes, which is the failure the oracle diff exists to catch.
    logic0 = dirs[LOGIC][0] if dirs.get(LOGIC) else None
    if logic0 is not None and logic0.present and vols.numbers():
        if detect_v3_volume_format(vols, logic0.volume):
            raise UnsupportedVersion(
                "%s: V2 directories but V3 VOLUMES (7-byte headers, LZW). "
                "Out of scope this phase (design §11.1, dispatch §4.1). "
                "See loader_v2.cpp:61-71 -- CoCo3 LSL and the CoCo3 fan ports do this." % label)

    extras = {}
    for extra in ("words.tok", "object"):
        key = _find_ci(names, extra)
        if key:
            extras[extra] = blobs[key]

    return Game(label, dirs, vols, version, extras)
