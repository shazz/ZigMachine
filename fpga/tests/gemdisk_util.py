"""Synthetic .zmd disks and the browser's own listing, for tests/test_board_gemdisk.py: GEM's FAT
listing over a data disk, as docs/zmdisk.js parses a disk and docs/sealed-loader.js writes it."""

from __future__ import annotations

import struct
import subprocess
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent

# The browser: parseDisk (docs/zmdisk.js) and sealed-loader.js's listing block, cut out of the
# loader and run over a mock GEM whose diskDirPtr is PTR in a memory of MEM bytes.
NODE_LIST = r"""
import { readFileSync } from "node:fs";
const [zmdisk, loader, diskPath, ent, maxf, ptr, mem] = process.argv.slice(1);
const { parseDisk } = await import(zmdisk);
const block = readFileSync(loader, "utf8").match(/^        if \(!diskDirSet && diskApp[\s\S]*?^            diskDirSet = true;\n        \}\n/m)[0];
let mountedDisk;
try { mountedDisk = parseDisk(new Uint8Array(readFileSync(diskPath)), diskPath).mounted; }
catch (e) { console.log("err"); process.exit(0); }
const memory = new WebAssembly.Memory({ initial: Number(mem) / 65536 });
let count = -1;
const demo = { diskDirPtr: () => Number(ptr), isBooted: () => 1, setDiskFileCount: (n) => { count = n; } };
const rom = { deskDirEntryBytes: () => Number(ent), deskDirMaxFiles: () => Number(maxf) };
const run = new Function("demo", "rom", "memory", "mountedDisk", "text_encoder", "diskApp",
    `let diskDirSet = false;\n${block}`);
try { run(demo, rom, memory, mountedDisk, new TextEncoder(), true); }
catch (e) { if (!(e instanceof RangeError)) throw e; console.log("err"); process.exit(0); }
const bytes = new Uint8Array(memory.buffer, Number(ptr), count * Number(ent));
console.log(`${count} ${Buffer.from(bytes).toString("hex")}`);
"""

NODE_FIND = r"""
const [zmdisk, diskPath, hex] = process.argv.slice(1);
const { readFileSync } = await import("node:fs");
const { parseDisk } = await import(zmdisk);
const files = parseDisk(new Uint8Array(readFileSync(diskPath)), diskPath).mounted.files;
console.log(Object.hasOwn(files, new TextDecoder().decode(Buffer.from(hex, "hex"))) ? "1" : "0");
"""


def browser_list(disk: Path, ent: int = 25, maxf: int = 12, ptr: int = 0x100, mem: int = 65536) -> str:
    args = [
        str(ROOT / "docs/zmdisk.js"),
        str(ROOT / "docs/sealed-loader.js"),
        str(disk),
        *map(str, (ent, maxf, ptr, mem)),
    ]
    out = subprocess.run(
        ["node", "--input-type=module", "-e", NODE_LIST, *args], capture_output=True, text=True, check=True
    )
    return out.stdout.strip()


def browser_find(disk: Path, name: bytes) -> str:
    args = [str(ROOT / "docs/zmdisk.js"), str(disk), name.hex()]
    out = subprocess.run(
        ["node", "--input-type=module", "-e", NODE_FIND, *args], capture_output=True, text=True, check=True
    )
    return out.stdout.strip()


def _be_sum(b: bytes | bytearray, words: int) -> int:
    return sum((b[2 * i] << 8) | b[2 * i + 1] for i in range(words)) & 0xFFFF


def fat(entries: list[tuple[bytes, int, int, int]]) -> bytes:
    """32-byte entries: name[16] start[4] len[4] type[1] + 7 zero bytes."""
    return b"".join(
        n[:16].ljust(16, b"\0") + struct.pack("<II", s, ln) + bytes([t]) + bytes(7) for n, s, ln, t in entries
    )


def v1(entries: list[tuple[bytes, int, int, int]], count: int | None = None, size: int | None = None,
       sum_: int = 0) -> bytes:  # fmt: skip
    """A v1 disk: "ZMDISK" at 0, the FAT at 0x300, the boot sector's sum `sum_` (0 = data disk);
    `size` cuts (or pads) the image, `count` overrides the file count."""
    img = bytearray(max(0x600, 0x300 + 32 * len(entries)))
    img[0:6] = b"ZMDISK"
    img[0x200:0x209] = b"TEST DISK"
    struct.pack_into("<H", img, 0x2E4, len(entries) if count is None else count)
    img[0x300 : 0x300 + 32 * len(entries)] = fat(entries)
    img[0x1FE:0x200] = ((sum_ - _be_sum(img, 256)) & 0xFFFF).to_bytes(2, "big")
    return bytes(img) if size is None else bytes(img[:size]).ljust(size, b"\0")


def v2(entries: list[tuple[bytes, int, int, int]], date: int, bootable: bool = False, cart_len: int = 1) -> bytes:
    """A v2 disk: a wasm boot sector, "ZMDISK" at 0x400, the date at 0x4f0, the FAT at 0x800;
    `cart_len` 0 = the descriptor names no cart (a data disk even with an executable sector)."""
    img = bytearray(0x800 + 32 * max(len(entries), 32))
    img[0:4] = b"\0asm"
    img[0x400:0x406] = b"ZMDISK"
    struct.pack_into("<I", img, 0x40C, cart_len)
    struct.pack_into("<IH", img, 0x4F0, date, len(entries))
    img[0x800 : 0x800 + 32 * len(entries)] = fat(entries)
    img[0x3FE:0x400] = (((0x1234 if bootable else 0x4321) - _be_sum(img, 512)) & 0xFFFF).to_bytes(2, "big")
    return bytes(img)
