#!/usr/bin/env python3
"""corpus.py -- feed the resource layer from EITHER corpus (AC-9).

★★ THE TWO CORPORA DIFFER IN TWO WAYS, AND A PARSER THAT HANDLES ONLY ONE IS NOT DONE
(dispatch §4.3):
  - **medium**: the fan set is a directory of files; the CoCo3 set is inside OS-9 disk images,
    where a "file" never exists on the host at all.
  - **filename case**: `logdir` vs `logDir`. Measured at P0.4, not assumed.

Both are absorbed here, by reducing every source to the same `{name: bytes}` mapping. The
parser never learns which medium it came from -- the same reasoning as §4.2a's seam, applied
one layer out.

★ A CoCo3 title spans SEVERAL images (KQ3's Original is five disks x two sides), and its
resources are spread across them. `load_os9_title()` therefore merges the files from every
image of one variant. ★ Where two images carry the same filename -- `object` and `vol.0` appear
on nearly every disk (P0.4 AC-6 measured 51.4% duplication) -- the FIRST occurrence wins and
the collision is recorded, because silently taking the last would make the result depend on
directory iteration order.

Read-only throughout (§2P).
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "harness" / "tools"))

from . import resource


def load_dir_title(path, label=None):
    """The fan corpus: a plain directory of game files."""
    d = pathlib.Path(path)
    blobs = {p.name: p.read_bytes() for p in d.iterdir() if p.is_file()}
    return resource.load_from_blobs(blobs, label or d.name)


def collect_os9_variant(variant_dir):
    """Merge every OS-9 image in one variant directory into {name: bytes}.

    -> (blobs, collisions, images_read)
    """
    import os9fs

    blobs, collisions, images = {}, [], []
    for img_path in sorted(pathlib.Path(variant_dir).iterdir()):
        if not img_path.is_file() or img_path.suffix.lower() not in (".dsk", ".par"):
            continue
        img = os9fs.try_open(img_path)
        if img is None:
            continue
        images.append(img_path.name)
        for name, size, lsn, trunc in img.walk():
            base = name.rsplit("/", 1)[-1]
            data, short = img.read_file(lsn)
            if base in blobs:
                if blobs[base] != data:
                    collisions.append((base, img_path.name, "DIFFERENT CONTENT"))
                else:
                    collisions.append((base, img_path.name, "identical"))
                continue                    # ★ first wins, deterministically
            blobs[base] = data
    return blobs, collisions, images


def load_os9_title(variant_dir, label=None):
    """The CoCo3 corpus: one variant directory of OS-9 images."""
    d = pathlib.Path(variant_dir)
    blobs, collisions, images = collect_os9_variant(d)
    lbl = label or ("%s/%s" % (d.parent.name.split(" (")[0], d.name))
    game = resource.load_from_blobs(blobs, lbl)
    game.extras["_collisions"] = collisions
    game.extras["_images"] = images
    return game
