"""rootfs.cpio.uboot = the board's own image + ONE more newc archive of an overlay directory.

The kernel unpacks concatenated archives in order and the later file wins, so every file the overlay
does not name stays the board's (what prototypes/r80_watchdog_v2_card/stage.sh did with cpio + mkimage)."""

from __future__ import annotations

import stat
import struct
import sys
import zlib
from pathlib import Path

from .errors import CardError

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import rootfs_glass  # after the path insert

UBOOT_HEAD = 64
BLOCK = 512  # cpio -o pads the archive to a block; so do we


def newc_entry(name: str, mode: int, body: bytes, ino: int) -> bytes:
    f = (ino, mode, 0, 0, 1, 0, len(body), 0, 0, 0, 0, len(name) + 1, 0)
    head = b"070701" + b"".join(b"%08X" % v for v in f)
    raw = head + name.encode() + b"\0"
    raw += bytes(-len(raw) % 4) + body
    return raw + bytes(-len(raw) % 4)


def overlay_archive(root: Path) -> bytes:
    """A newc archive of `root`'s tree (owner 0:0, mtime 0: the same tree gives the same bytes)."""
    if not root.is_dir():
        raise CardError(f"--rootfs-overlay {root}: not a directory")
    out, ino = b"", 1
    for p in sorted(root.rglob("*")):
        rel, st = p.relative_to(root).as_posix(), p.lstat()
        body = p.read_bytes() if stat.S_ISREG(st.st_mode) else p.readlink().as_posix().encode() if p.is_symlink() else b""
        out += newc_entry(rel, st.st_mode, body, ino)
        ino += 1
    return out + newc_entry("TRAILER!!!", 0, b"", 0) if ino > 1 else b""


def base_cpio(image: bytes, name: str) -> bytes:
    """The board image's archive data, its U-Boot header checked (magic, data CRC)."""
    magic, _hcrc, _t, size, _la, _ep, dcrc = struct.unpack_from(">IIIIIII", image)
    data = image[UBOOT_HEAD:]
    if magic != rootfs_glass.IH_MAGIC or size != len(data) or dcrc != zlib.crc32(data):
        raise CardError(f"{name}: not a U-Boot ramdisk image (magic, size or data CRC wrong)")
    return data


def build(base: Path, overlay: Path, epoch: int) -> bytes:
    """The image: `base`'s archive, padded to a block, then the overlay's archive, under a fresh header."""
    extra = overlay_archive(overlay)
    if not extra:
        raise CardError(f"--rootfs-overlay {overlay}: empty")
    cpio = base_cpio(base.read_bytes(), str(base))
    cpio += bytes(-len(cpio) % BLOCK)
    return rootfs_glass.ramdisk_image(cpio + extra + bytes(-len(extra) % BLOCK), epoch)
