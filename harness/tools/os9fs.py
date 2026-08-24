#!/usr/bin/env python3
"""os9fs.py -- a READ-ONLY OS-9 RBF filesystem reader for CoCo3 disk images (P0.4).

★★ GAME IMAGES ARE THE USER'S AND ARE READ-ONLY, ABSOLUTELY (CLAUDE.md §2P). Every open in this
file is 'rb'. There is no write path, no repair path and no "fix the image" convenience. A tool
that opens a game image for writing is a bug.

★★ THIS IS A FILESYSTEM READER, NOT AN AGI RESOURCE DECODER (dispatch §12).
It reports what files exist and how big they are. It does NOT parse LOGIC, PICTURE, VIEW or
SOUND, and it must not grow to -- writing our own resource decoder is P1/P2 work and doing it
here would build the self-referential baseline §2O.1 forbids.

────────────────────────────────────────────────────────────────────────────────────────────
THE FORMAT, AND WHY EACH FIELD IS TRUSTED OR NOT
────────────────────────────────────────────────────────────────────────────────────────────
OS-9 Level 2 RBF. Sector ("logical sector number", LSN) = 256 bytes, always, on this media.

LSN 0 -- identification sector:
    0x00 DD.TOT  3  total sectors        ★ NOT TRUSTED -- see below
    0x03 DD.TKS  1  sectors per track
    0x06 DD.BIT  2  sectors per cluster
    0x08 DD.DIR  3  LSN of the ROOT DIRECTORY's file descriptor
    0x10 DD.FMT  1  format byte
    0x15 DD.BT   3  bootstrap LSN
    0x18 DD.BSZ  2  bootstrap size
    0x1F DD.NAM 32  volume name, terminated by a byte with bit 7 set

File descriptor (one sector):
    0x00 FD.ATT  1  attributes; bit 7 (0x80) = DIRECTORY
    0x09 FD.SIZ  4  file size in BYTES
    0x10 FD.SEG     segment list: 48 entries x 5 bytes = (3-byte LSN, 2-byte sector count),
                    terminated by a zero LSN

Directory data is an array of 32-byte entries:
    0x00 29 bytes  name, terminated by a byte with bit 7 set
    0x1D  3 bytes  LSN of that entry's file descriptor
A first name byte of 0x00 marks a DELETED entry and is skipped.

★★★ DD.TOT IS NOT TRUSTED, AND THAT IS A MEASURED DECISION, NOT CAUTION.
Across the 80 images in this corpus DD.TOT disagrees with the file's actual length in three
whole classes of media:
  - DrivePak `.par`   : file is 2x the sectors DD.TOT declares (a partition container)
  - DriveWire becker/dw: DD.TOT declares 18432 sectors on files as small as 1394 sectors
  - LARRY1.DSK        : 720 sectors on disk, DD.TOT says 630
So every read is CLAMPED TO THE ACTUAL FILE LENGTH. Trusting DD.TOT would read past the end of
the file on more than a third of this corpus, and on a sparse DriveWire image it would silently
invent zero-filled content that the disk does not contain.
"""
import hashlib
import pathlib

SECTOR = 256
FD_ATTR_DIR = 0x80
DIRENT_SIZE = 32
MAX_SEGMENTS = 48
MAX_DEPTH = 16              # RBF has no depth limit; this bounds a malformed/looping image


class Os9Error(Exception):
    pass


def _u16(b, o):
    return (b[o] << 8) | b[o + 1]


def _u24(b, o):
    return (b[o] << 16) | (b[o + 1] << 8) | b[o + 2]


def _u32(b, o):
    return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


def _hi_terminated(b, o, maxlen):
    """OS-9 strings end at the byte whose bit 7 is set; that byte is part of the name."""
    out = []
    for i in range(maxlen):
        if o + i >= len(b):
            break
        c = b[o + i]
        ch = c & 0x7F
        if ch == 0:
            break
        out.append(chr(ch))
        if c & 0x80:
            break
    return "".join(out).strip()


class Os9Image:
    """A read-only view of one OS-9 disk image.

    ★★ TWO PHYSICAL LAYOUTS, ONE LOGICAL FORMAT -- and the second was found by measurement,
    not by reading a spec. Floppy `.dsk` images store one 256-byte OS-9 sector per 256 bytes of
    file. DrivePak `.par` images store one 256-byte OS-9 sector per 512-BYTE PHYSICAL SECTOR,
    with the upper half of each block padded 0xFF.

    All seven `.par` files in this corpus parsed to ZERO FILES under the 256 assumption, with a
    root descriptor of 0xFF bytes -- which looks like a corrupt image and is not one. Mapping
    the container showed exactly 2880 data sectors ALTERNATING with 2880 all-0xFF sectors, and
    DD.TOT = 2880 = filesize / 512. The stride is detected, never assumed.
    """

    def __init__(self, path):
        self.path = pathlib.Path(path)
        self.data = self.path.read_bytes()          # 'rb' -- read only, always
        if len(self.data) < 2 * SECTOR:
            raise Os9Error("image shorter than two sectors")

        self.stride = SECTOR
        self.sectors = len(self.data) // self.stride
        lsn0 = self.sector(0)
        dd_tot = _u24(lsn0, 0x00)
        dd_dir = _u24(lsn0, 0x08)

        # ★ Stride detection, by EVIDENCE rather than by file extension: if the root descriptor
        # does not read as a directory at stride 256 but does at stride 512, it is a 512-byte
        # container. Extension would be the lazy test and would be wrong for any `.dsk` that
        # happens to be imaged the other way.
        if not self._root_is_dir(dd_dir):
            alt = len(self.data) // 512
            if alt >= 2 and dd_tot == alt:
                self.stride = 512
                self.sectors = alt
                lsn0 = self.sector(0)
                dd_dir = _u24(lsn0, 0x08)
        self.dd_tot = _u24(lsn0, 0x00)
        self.dd_tks = lsn0[0x03]
        self.dd_bit = _u16(lsn0, 0x06)
        self.dd_dir = _u24(lsn0, 0x08)
        self.dd_fmt = lsn0[0x10]
        self.dd_bt = _u24(lsn0, 0x15)
        self.dd_bsz = _u16(lsn0, 0x18)
        self.volume = _hi_terminated(lsn0, 0x1F, 32)

        # ★ The plausibility gate. A file that is not OS-9 will usually fail here rather than
        # produce confident nonsense -- which is the failure mode that matters for a tool whose
        # output feeds a manifest.
        if self.dd_dir == 0 or self.dd_dir >= self.sectors:
            raise Os9Error("DD.DIR %d outside image of %d sectors" % (self.dd_dir, self.sectors))
        if self.dd_tks == 0:
            raise Os9Error("DD.TKS is zero")

    # ---- raw access -----------------------------------------------------------------

    def _root_is_dir(self, dd_dir):
        """Does DD.DIR point at a PLAUSIBLE root directory descriptor?

        ★ The obvious test -- 'is the directory bit set' -- IS NOT ENOUGH, and getting this
        wrong is what made stride detection silently fail the first time: an ERASED sector is
        0xFF bytes, and 0xFF has bit 7 set, so an all-0xFF descriptor passes a bare bit test
        and looks like a directory. Three fields must agree instead:
            - the directory attribute bit
            - a size that fits inside the image (0xFFFFFFFF does not)
            - a first segment whose LSN is inside the image and non-zero
        Never raises; a failure here is a fact about the layout, not an error.
        """
        try:
            if dd_dir == 0 or dd_dir >= self.sectors:
                return False
            fd = self.sector(dd_dir)
            if not (fd[0x00] & FD_ATTR_DIR):
                return False
            if _u32(fd, 0x09) > len(self.data):
                return False
            seg_lsn = _u24(fd, 0x10)
            seg_cnt = _u16(fd, 0x13)
            return 0 < seg_lsn < self.sectors and 0 < seg_cnt < self.sectors
        except (Os9Error, IndexError):
            return False

    def sector(self, lsn):
        if lsn < 0 or lsn >= self.sectors:          # ★ clamp to the FILE, never to DD.TOT
            raise Os9Error("LSN %d outside image of %d sectors" % (lsn, self.sectors))
        off = lsn * self.stride
        return self.data[off:off + SECTOR]          # always 256 logical bytes, whatever the stride

    def sha256(self):
        return hashlib.sha256(self.data).hexdigest()

    # ---- file descriptors -----------------------------------------------------------

    def read_fd(self, lsn):
        """-> (is_dir, size_bytes, [(start_lsn, sector_count), ...])"""
        fd = self.sector(lsn)
        is_dir = bool(fd[0x00] & FD_ATTR_DIR)
        size = _u32(fd, 0x09)
        segs = []
        for i in range(MAX_SEGMENTS):
            o = 0x10 + i * 5
            if o + 5 > len(fd):
                break
            seg_lsn = _u24(fd, o)
            seg_cnt = _u16(fd, o + 3)
            if seg_lsn == 0 or seg_cnt == 0:
                break                                # zero LSN terminates the list
            segs.append((seg_lsn, seg_cnt))
        return is_dir, size, segs

    def read_file(self, lsn):
        """Return a file's bytes, truncated to FD.SIZ. Missing sectors END the file."""
        is_dir, size, segs = self.read_fd(lsn)
        out = bytearray()
        for seg_lsn, seg_cnt in segs:
            for s in range(seg_cnt):
                if len(out) >= size:
                    break
                try:
                    out += self.sector(seg_lsn + s)
                except Os9Error:
                    # ★ A segment pointing past the end of a SPARSE image (DriveWire) is not a
                    # parse failure -- it is the image genuinely not containing those bytes.
                    # Returning what exists, short, beats inventing zeros.
                    return bytes(out[:size]), True
            if len(out) >= size:
                break
        return bytes(out[:size]), len(out) < size

    # ---- directory walk -------------------------------------------------------------

    def walk(self):
        """Yield (path, size_bytes, fd_lsn, truncated) for every regular file on the image."""
        yield from self._walk(self.dd_dir, "", 0, set())

    def _walk(self, dir_lsn, prefix, depth, seen):
        if depth > MAX_DEPTH or dir_lsn in seen:
            return
        seen = seen | {dir_lsn}
        try:
            is_dir, size, segs = self.read_fd(dir_lsn)
        except Os9Error:
            return
        if not is_dir:
            return

        raw = bytearray()
        for seg_lsn, seg_cnt in segs:
            for s in range(seg_cnt):
                try:
                    raw += self.sector(seg_lsn + s)
                except Os9Error:
                    break
        raw = raw[:size] if size else raw

        for o in range(0, len(raw) - DIRENT_SIZE + 1, DIRENT_SIZE):
            ent = raw[o:o + DIRENT_SIZE]
            if ent[0] == 0x00:
                continue                              # deleted entry
            name = _hi_terminated(ent, 0, 29)
            if name in (".", "..", ""):
                continue
            child = _u24(ent, 0x1D)
            if child == 0 or child >= self.sectors:
                continue
            try:
                c_isdir, c_size, _ = self.read_fd(child)
            except Os9Error:
                continue
            full = prefix + "/" + name if prefix else name
            if c_isdir:
                yield from self._walk(child, full, depth + 1, seen)
            else:
                yield full, c_size, child, False


def try_open(path):
    """-> Os9Image or None. Never raises; a non-OS-9 file is a fact, not an error."""
    try:
        return Os9Image(path)
    except (Os9Error, OSError, IndexError):
        return None
