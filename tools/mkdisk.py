#!/usr/bin/env python3
"""Pack a wasm cart into a ZigMachine .zmd disk image.

See docs/FLOPPY_DISK.md. Layout: 512 B executable boot sector (magic + $1234
checksum + direct boot pointer) · 1 KB descriptor + FAT (empty for a single cart)
· contiguous data. All fields little-endian except the big-endian $1234 checksum.
"""
import argparse
import struct

BLOCK = 512
BOOT = 512          # boot sector
DESC = 1024         # descriptor + FAT
DATA_START = BOOT + DESC  # 1536 = block 3


def _put_str(buf: bytearray, off: int, s: str, size: int) -> None:
    b = s.encode("utf-8")[:size]
    buf[off:off + len(b)] = b  # rest stays NUL


def build(wasm: bytes, title: str, author: str, desc: str, date: int,
          files: list | None = None, boot_name: str = "BOOT.WSM",
          bootable: bool = True) -> bytes:
    files = files or []                       # extra FAT files: (name, bytes, type)
    boot_block = DATA_START // BLOCK          # 3
    boot_len = len(wasm)

    # --- data area: boot cart, then each extra file, each block-aligned ---
    data = bytearray()
    fat = []                                  # (name, abs_start, length, type)
    def place(name, blob, ftype, in_fat):
        start = DATA_START + len(data)
        data.extend(blob)
        data.extend(b"\x00" * ((-len(blob)) % BLOCK))
        if in_fat:
            fat.append((name, start, len(blob), ftype))
    # A single-cart disk keeps an EMPTY FAT (boot pointer only); a multi-file disk
    # lists the executable + its files.
    multi = bool(files)
    place(boot_name, wasm, 0, multi)          # the executable (type 0 = wasm cart)
    for name, blob, ftype in files:
        place(name, blob, ftype, True)
    total_blocks = (DATA_START + len(data)) // BLOCK

    # --- boot sector (512 B) ---
    bs = bytearray(BOOT)
    bs[0:6] = b"ZMDISK"
    struct.pack_into("<H", bs, 0x06, 1)               # format version
    struct.pack_into("<H", bs, 0x08, BLOCK)           # block size
    struct.pack_into("<I", bs, 0x0A, total_blocks)
    struct.pack_into("<I", bs, 0x0E, boot_block)
    struct.pack_into("<I", bs, 0x12, boot_len)
    # Executability (ST-style): a BOOTABLE disk sums its 256 big-endian words to
    # 0x1234; a DATA disk is deliberately non-executable (we tune to 0x0000), so
    # the machine falls through to the OS (GEM) instead of running it.
    s = 0
    for i in range(255):
        s = (s + ((bs[2 * i] << 8) | bs[2 * i + 1])) & 0xFFFF
    target = 0x1234 if bootable else 0x0000
    chk = (target - s) & 0xFFFF
    bs[0x1FE] = (chk >> 8) & 0xFF
    bs[0x1FF] = chk & 0xFF

    # --- descriptor + FAT (1 KB), offsets relative to $200 ---
    d = bytearray(DESC)
    _put_str(d, 0x00, title, 64)      # $200
    _put_str(d, 0x40, author, 32)     # $240
    _put_str(d, 0x60, desc, 128)      # $260
    struct.pack_into("<I", d, 0xE0, date)   # $2E0 YYYYMMDD
    # FAT: file table at $300 (d offset 0x100), 32-byte entries. Empty for a plain
    # single-cart disk; here it always lists at least the boot cart.
    struct.pack_into("<H", d, 0xE4, len(fat))   # $2E4 file count
    if len(fat) > 24:
        raise SystemExit("FAT overflow: max 24 files in the 1 KB region")
    for i, (name, start, length, ftype) in enumerate(fat):
        e = 0x100 + i * 32
        _put_str(d, e, name, 16)
        struct.pack_into("<I", d, e + 0x10, start)
        struct.pack_into("<I", d, e + 0x14, length)
        d[e + 0x18] = ftype

    return bytes(bs) + bytes(d) + bytes(data)


def main() -> None:
    ap = argparse.ArgumentParser(description="Pack a wasm cart into a .zmd disk image.")
    ap.add_argument("wasm", help="input cart wasm")
    ap.add_argument("-o", "--out", required=True, help="output .zmd")
    ap.add_argument("--title", default="ZigMachine Disk")
    ap.add_argument("--author", default="")
    ap.add_argument("--desc", default="")
    ap.add_argument("--date", type=int, default=0, help="YYYYMMDD")
    ap.add_argument("--file", action="append", default=[], metavar="NAME=PATH",
                    help="add an extra file to the FAT (repeatable), e.g. SAMPLE.RAW=docs/music/smp1.raw")
    ap.add_argument("--no-boot", action="store_true",
                    help="make a non-executable DATA disk (the machine boots the OS/GEM, not this disk)")
    a = ap.parse_args()

    with open(a.wasm, "rb") as f:
        wasm = f.read()
    files = []
    for spec in a.file:
        name, _, path = spec.partition("=")
        with open(path, "rb") as fh:
            files.append((name, fh.read(), 1))  # type 1 = raw asset
    img = build(wasm, a.title, a.author, a.desc, a.date, files=files, bootable=not a.no_boot)
    with open(a.out, "wb") as f:
        f.write(img)

    bs = img[:BOOT]
    s = sum((bs[2 * i] << 8) | bs[2 * i + 1] for i in range(256)) & 0xFFFF
    kind = "executable" if s == 0x1234 else ("data disk" if s == 0x0000 else "BAD")
    print(f"{a.out}: {len(img)} bytes, cart {len(wasm)} B at block {DATA_START // BLOCK}, "
          f"checksum sum=0x{s:04X} ({kind})")


if __name__ == "__main__":
    main()
