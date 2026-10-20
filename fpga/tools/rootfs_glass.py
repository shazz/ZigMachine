"""Put a glass binary into Buildroot's rootfs without re-running Buildroot (decisions.md 2026-10-19).

    uv run python tools/rootfs_glass.py ROOTFS_CPIO GLASS OUT_UBOOT [--strip STRIP]

The board boots /usr/bin/glass from its initramfs (rootfs.cpio.uboot on the SD card), and S99glass runs
it at every boot. That copy must match the card's boot.scr: since boot.cmd sets HP1's AFI write channel
64-bit (0xF00), a glass that predates fpga/glass/src/afi.zig would run the firmware's 4-byte beats on a
64-bit channel (half the picture's words lost). Buildroot's post-build.sh installs the glass from the
main checkout's zig-out; this swaps ONE entry of the finished newc archive instead, so every other file,
device node and owner stays byte-identical to what Buildroot (under fakeroot) made, then wraps it the way
`mkimage -A arm -O linux -T ramdisk -C none` does (U-Boot's `bootz` takes it as the initrd).
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import subprocess
import tempfile
import time
import zlib
from pathlib import Path

ENTRY = "usr/bin/glass"
MAGIC = b"070701"
HEAD = 110  # "070701" + 13 eight-digit hex fields
IH_MAGIC, IH_OS_LINUX, IH_ARCH_ARM, IH_TYPE_RAMDISK = 0x27051956, 5, 2, 3


def _pad4(n: int) -> int:
    return (n + 3) & ~3


def entries(cpio: bytes) -> list[tuple[str, int, int, int]]:
    """(name, header offset, data offset, data size) per entry, up to and including TRAILER!!!."""
    out, at = [], 0
    while True:
        if cpio[at : at + 6] != MAGIC:
            raise ValueError(f"not a newc cpio entry at {at:#x}")
        fields = [int(cpio[at + 6 + 8 * i : at + 14 + 8 * i], 16) for i in range(13)]
        size, namesize = fields[6], fields[11]
        name = cpio[at + HEAD : at + HEAD + namesize - 1].decode()
        data = _pad4(at + HEAD + namesize)
        out.append((name, at, data, size))
        if name == "TRAILER!!!":
            return out
        at = _pad4(data + size)


def replace(cpio: bytes, name: str, body: bytes) -> bytes:
    """The archive with NAME's data swapped for BODY; its mode, owner and mtime kept, nothing else moved."""
    hits = [e for e in entries(cpio) if e[0] == name]
    if len(hits) != 1:
        raise ValueError(f"{name}: {len(hits)} entries in the archive, want exactly 1")
    _, at, data, size = hits[0]
    head = bytearray(cpio[at:data])
    head[6 + 8 * 6 : 6 + 8 * 7] = b"%08X" % len(body)  # c_filesize
    return cpio[:at] + bytes(head) + body + bytes(_pad4(len(body)) - len(body)) + cpio[_pad4(data + size) :]


def member(cpio: bytes, name: str) -> bytes:
    for n, _, data, size in entries(cpio):
        if n == name:
            return cpio[data : data + size]
    raise KeyError(name)


def ramdisk_image(data: bytes, epoch: int, name: str = "") -> bytes:
    """A U-Boot legacy ramdisk image, as `mkimage -A arm -O linux -T ramdisk -C none` makes."""
    head = struct.pack(">IIIIIIIBBBB32s", IH_MAGIC, 0, epoch, len(data), 0, 0, zlib.crc32(data), IH_OS_LINUX,
                       IH_ARCH_ARM, IH_TYPE_RAMDISK, 0, name.encode()[:32])  # fmt: skip
    return head[:4] + struct.pack(">I", zlib.crc32(head)) + head[8:] + data


def stripped(glass: Path, strip: Path | None) -> bytes:
    """GLASS as post-build.sh installs it (stripped: 3.4 -> 0.6 MB of RAM); unstripped without a strip."""
    if strip is None:
        return glass.read_bytes()
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "glass"
        subprocess.run([str(strip), "-o", str(out), str(glass)], check=True)
        return out.read_bytes()


def buildroot_strip(buildroot: Path) -> Path | None:
    """The Buildroot toolchain's own strip (post-build.sh's), or None."""
    found = sorted((buildroot / "host/bin").glob("*-buildroot-linux-*-strip"))
    return found[0] if found else None


def build(rootfs_cpio: Path, glass: Path, out: Path, strip: Path | None, epoch: int | None = None) -> bytes:
    """Write OUT (rootfs.cpio.uboot) with GLASS at /usr/bin/glass; return the glass bytes installed."""
    body = stripped(glass, strip)
    cpio = replace(rootfs_cpio.read_bytes(), ENTRY, body)
    out.write_bytes(ramdisk_image(cpio, int(time.time()) if epoch is None else epoch))
    return body


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("rootfs_cpio", type=Path, help="Buildroot's images/rootfs.cpio")
    p.add_argument("glass", type=Path, help="the ARM glass (fpga/glass/zig-out/arm/bin/glass)")
    p.add_argument("out", type=Path, help="the rootfs.cpio.uboot to write")
    p.add_argument("--strip", type=Path, help="an ARM strip (default: none, the glass goes in as built)")
    a = p.parse_args()
    body = build(a.rootfs_cpio, a.glass, a.out, a.strip)
    print(f"{a.out}: {ENTRY} {len(body)} bytes md5 {hashlib.md5(body).hexdigest()}")


if __name__ == "__main__":
    main()
