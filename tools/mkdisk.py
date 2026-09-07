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


def build(wasm: bytes, title: str, author: str, desc: str, date: int) -> bytes:
    boot_block = DATA_START // BLOCK          # 3
    boot_len = len(wasm)
    data = wasm + b"\x00" * ((-len(wasm)) % BLOCK)   # pad to a block
    total_blocks = (DATA_START + len(data)) // BLOCK

    # --- boot sector (512 B) ---
    bs = bytearray(BOOT)
    bs[0:6] = b"ZMDISK"
    struct.pack_into("<H", bs, 0x06, 1)               # format version
    struct.pack_into("<H", bs, 0x08, BLOCK)           # block size
    struct.pack_into("<I", bs, 0x0A, total_blocks)
    struct.pack_into("<I", bs, 0x0E, boot_block)
    struct.pack_into("<I", bs, 0x12, boot_len)
    # executability: sum of 256 big-endian 16-bit words == 0x1234; word $1FE tunes it.
    s = 0
    for i in range(255):
        s = (s + ((bs[2 * i] << 8) | bs[2 * i + 1])) & 0xFFFF
    chk = (0x1234 - s) & 0xFFFF
    bs[0x1FE] = (chk >> 8) & 0xFF
    bs[0x1FF] = chk & 0xFF

    # --- descriptor + FAT (1 KB), offsets relative to $200 ---
    d = bytearray(DESC)
    _put_str(d, 0x00, title, 64)      # $200
    _put_str(d, 0x40, author, 32)     # $240
    _put_str(d, 0x60, desc, 128)      # $260
    struct.pack_into("<I", d, 0xE0, date)   # $2E0 YYYYMMDD
    struct.pack_into("<H", d, 0xE4, 0)      # $2E4 file count (0 = FAT empty)

    return bytes(bs) + bytes(d) + data


def main() -> None:
    ap = argparse.ArgumentParser(description="Pack a wasm cart into a .zmd disk image.")
    ap.add_argument("wasm", help="input cart wasm")
    ap.add_argument("-o", "--out", required=True, help="output .zmd")
    ap.add_argument("--title", default="ZigMachine Disk")
    ap.add_argument("--author", default="")
    ap.add_argument("--desc", default="")
    ap.add_argument("--date", type=int, default=0, help="YYYYMMDD")
    a = ap.parse_args()

    with open(a.wasm, "rb") as f:
        wasm = f.read()
    img = build(wasm, a.title, a.author, a.desc, a.date)
    with open(a.out, "wb") as f:
        f.write(img)

    # verify the checksum we just wrote
    bs = img[:BOOT]
    s = sum((bs[2 * i] << 8) | bs[2 * i + 1] for i in range(256)) & 0xFFFF
    print(f"{a.out}: {len(img)} bytes, cart {len(wasm)} B at block {DATA_START // BLOCK}, "
          f"checksum sum=0x{s:04X} ({'executable' if s == 0x1234 else 'BAD'})")


if __name__ == "__main__":
    main()
