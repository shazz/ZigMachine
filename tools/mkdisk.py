#!/usr/bin/env python3
"""Pack a wasm cart into a ZigMachine .zmd disk image.

See docs/FLOPPY_DISK.md. Two formats:
  v1 (default):  512 B boot sector (magic + $1234 checksum + direct boot pointer)
                 · 1 KB descriptor + FAT · contiguous data from block 3.
  v2 (--boot-wasm): 1 KB boot sector = an EXECUTABLE wasm module whose 512 BE words
                 sum to $1234 (tuned via a `zmck` custom section) · 1 KB descriptor
                 (with the cart pointer) · 1 KB FAT · contiguous data from block 6.
All fields little-endian except the big-endian $1234 checksum.
"""
import argparse
import struct

BLOCK = 512
BOOT = 512          # v1 boot sector
DESC = 1024         # v1 descriptor + FAT
DATA_START = BOOT + DESC  # 1536 = block 3 (v1)
KB = 1024
V2_DATA_START = 3 * KB    # 3072 = block 6 (v2): boot(1K) + descriptor(1K) + FAT(1K)
WASM_MAGIC = b"\x00asm\x01\x00\x00\x00"


def _put_str(buf: bytearray, off: int, s: str, size: int) -> None:
    b = s.encode("utf-8")[:size]
    buf[off:off + len(b)] = b  # rest stays NUL


def _be_word_sum(buf: bytes) -> int:
    """Sum of all big-endian 16-bit words of buf, mod $10000 (ST-style checksum)."""
    return sum((buf[2 * i] << 8) | buf[2 * i + 1] for i in range(len(buf) // 2)) & 0xFFFF


def _uleb128(n: int) -> bytes:
    out = bytearray()
    while True:
        b, n = n & 0x7F, n >> 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def _place_files(main_name: str, main: bytes, files: list, data_start: int) -> tuple:
    """Data area: main blob, then each extra file, each block-aligned.
    A single-cart disk keeps an EMPTY FAT (boot pointer only); a multi-file disk
    lists the executable + its files. Returns (data, fat)."""
    data = bytearray()
    fat = []                                  # (name, abs_start, length, type)
    def place(name, blob, ftype, in_fat):
        start = data_start + len(data)
        data.extend(blob)
        data.extend(b"\x00" * ((-len(blob)) % BLOCK))
        if in_fat:
            fat.append((name, start, len(blob), ftype))
    place(main_name, main, 0, bool(files))    # the executable (type 0 = wasm cart)
    for name, blob, ftype in files:
        place(name, blob, ftype, True)
    if len(fat) > 24:
        raise SystemExit("FAT overflow: max 24 files in the 1 KB region")
    return data, fat


def _write_fat(buf: bytearray, off: int, fat: list) -> None:
    """32-byte entries: name[16] · start u32 · length u32 · type u8."""
    for i, (name, start, length, ftype) in enumerate(fat):
        e = off + i * 32
        _put_str(buf, e, name, 16)
        struct.pack_into("<I", buf, e + 0x10, start)
        struct.pack_into("<I", buf, e + 0x14, length)
        buf[e + 0x18] = ftype


def build(wasm: bytes, title: str, author: str, desc: str, date: int,
          files: list | None = None, boot_name: str = "BOOT.WSM",
          bootable: bool = True) -> bytes:
    boot_block = DATA_START // BLOCK          # 3
    data, fat = _place_files(boot_name, wasm, files or [], DATA_START)
    total_blocks = (DATA_START + len(data)) // BLOCK

    # --- boot sector (512 B) ---
    bs = bytearray(BOOT)
    bs[0:6] = b"ZMDISK"
    struct.pack_into("<H", bs, 0x06, 1)               # format version
    struct.pack_into("<H", bs, 0x08, BLOCK)           # block size
    struct.pack_into("<I", bs, 0x0A, total_blocks)
    struct.pack_into("<I", bs, 0x0E, boot_block)
    struct.pack_into("<I", bs, 0x12, len(wasm))
    # Executability (ST-style): a BOOTABLE disk sums its 256 big-endian words to
    # 0x1234; a DATA disk is deliberately non-executable (we tune to 0x0000), so
    # the machine falls through to the OS (GEM) instead of running it.
    target = 0x1234 if bootable else 0x0000
    chk = (target - _be_word_sum(bs[:0x1FE])) & 0xFFFF
    bs[0x1FE:0x200] = chk.to_bytes(2, "big")

    # --- descriptor + FAT (1 KB), offsets relative to $200 ---
    d = bytearray(DESC)
    _put_str(d, 0x00, title, 64)      # $200
    _put_str(d, 0x40, author, 32)     # $240
    _put_str(d, 0x60, desc, 128)      # $260
    struct.pack_into("<I", d, 0xE0, date)   # $2E0 YYYYMMDD
    struct.pack_into("<H", d, 0xE4, len(fat))   # $2E4 file count
    _write_fat(d, 0x100, fat)                   # $300
    return bytes(bs) + bytes(d) + bytes(data)


def boot_sector_v2(boot_wasm: bytes) -> bytes:
    """Pad an executable boot wasm to exactly 1 KB with a `zmck` custom section
    (id 0, ignored at runtime) whose LAST 2 bytes are tuned so the 512 BE words
    of the sector sum to $1234 — the wasm code itself is never touched."""
    if boot_wasm[:8] != WASM_MAGIC:
        raise SystemExit("boot wasm: bad magic (not a wasm module)")
    # section = id(1) + uleb(size)(ulen) + [uleb(4)(1) + "zmck"(4) + payload]; the
    # bracket is `size`. payload >= 2 (the adjustment word), so wasm <= 1015 B.
    rem = KB - len(boot_wasm)
    ulen = 1 if rem - 2 < 0x80 else 2         # bytes needed to encode `size`
    payload = rem - 1 - ulen - 5
    if payload < 2:
        raise SystemExit(f"boot wasm is {len(boot_wasm)} B; max {KB - 9} B "
                         f"(1 KB boot sector minus the 9-byte minimum zmck section)")
    size = _uleb128(5 + payload)
    if len(size) < ulen:   # rem == 130: size 127 needs a 2-byte (non-minimal, wasm-legal) LEB
        size = bytes([size[0] | 0x80, 0x00])
    sec = b"\x00" + size + _uleb128(4) + b"zmck" + bytes(payload)
    bs = bytearray(boot_wasm + sec)
    assert len(bs) == KB
    adj = (0x1234 - _be_word_sum(bs)) & 0xFFFF   # last word is 0 here, so it's excluded
    bs[KB - 2:KB] = adj.to_bytes(2, "big")
    assert _be_word_sum(bs) == 0x1234 and bs[:8] == WASM_MAGIC
    return bytes(bs)


def build_v2(boot_wasm: bytes, cart: bytes, title: str, author: str, desc: str,
             date: int, files: list | None = None, cart_name: str = "CART.WSM") -> bytes:
    data, fat = _place_files(cart_name, cart, files or [], V2_DATA_START)
    # --- descriptor (1 KB), offsets relative to $400 ---
    d = bytearray(KB)
    d[0:6] = b"ZMDISK"
    struct.pack_into("<H", d, 0x06, 2)                       # format version
    struct.pack_into("<I", d, 0x08, V2_DATA_START // BLOCK)  # cart block (6)
    struct.pack_into("<I", d, 0x0C, len(cart))               # cart length
    _put_str(d, 0x10, title, 64)      # $410
    _put_str(d, 0x50, author, 32)     # $450
    _put_str(d, 0x70, desc, 128)      # $470
    struct.pack_into("<I", d, 0xF0, date)      # $4F0 YYYYMMDD
    struct.pack_into("<H", d, 0xF4, len(fat))  # $4F4 file count
    # --- FAT (1 KB) at $800 ---
    f = bytearray(KB)
    _write_fat(f, 0, fat)
    return boot_sector_v2(boot_wasm) + bytes(d) + bytes(f) + bytes(data)


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
    ap.add_argument("--boot-wasm", metavar="FILE",
                    help="format v2: FILE is the executable boot-sector wasm (<= 1015 B); "
                         "the positional wasm becomes the chainloaded cart")
    a = ap.parse_args()

    with open(a.wasm, "rb") as f:
        wasm = f.read()
    files = []
    for spec in a.file:
        name, _, path = spec.partition("=")
        with open(path, "rb") as fh:
            files.append((name, fh.read(), 1))  # type 1 = raw asset
    if a.boot_wasm:
        with open(a.boot_wasm, "rb") as f:
            boot = f.read()
        img = build_v2(boot, wasm, a.title, a.author, a.desc, a.date, files=files)
        boot_len, cart_block = KB, V2_DATA_START // BLOCK
        extra = f", boot wasm {len(boot)} B (+{KB - 9 - len(boot)} B headroom)"
    else:
        img = build(wasm, a.title, a.author, a.desc, a.date, files=files, bootable=not a.no_boot)
        boot_len, cart_block, extra = BOOT, DATA_START // BLOCK, ""
    with open(a.out, "wb") as f:
        f.write(img)

    s = _be_word_sum(img[:boot_len])
    kind = "executable" if s == 0x1234 else ("data disk" if s == 0x0000 else "BAD")
    print(f"{a.out}: {len(img)} bytes, cart {len(wasm)} B at block {cart_block}, "
          f"checksum sum=0x{s:04X} ({kind}){extra}")


if __name__ == "__main__":
    main()
