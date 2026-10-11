"""Disk streaming on the board: ZWINDOW places the cart's shelf disk in the cart window
and ZIGGY's firmware serves env.diskReadBlock from it (docs/FPGA_GLASS.md, "The disk in
DDR"), exactly as docs/sealed-loader.js serves it in the browser.

- The drive (host/disk.h, the code the firmware and the native host link) against the
  browser's OWN diskReadBlock, taken out of sealed-loader.js and run in node: every
  result and the whole memory after every call, full, partial, past-the-end and
  "negative" blocks, a dst outside memory (the JS's RangeError), no disk.
- scene_hash.mjs's --disk drive is the browser's function, text for text.
- The firmware's descriptor check (cycles/bdisk.c) on what the glass writes.
- The glass gives back every shelf disk in docs/ byte for byte from its fat disk, and puts
  it where tools/ddr_init.py (the board SoC sim's DDR image) puts it.
- The native host with --disk equals scene_hash.mjs --disk frame for frame on stniccc,
  which streams SCENE1.BIN, and differs from the run without a disk.
"""

import json
import random
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
WORK = FPGA / "build" / "board_disk"
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(FPGA / "gen"))
import ddr_init
import glass_map
import glass_sd
import zmd_fat

ZIG = Path.home() / ".local/zig/0.16.0/zig"
MEM = 65536
NODE_DRIVE = r"""
import { readFileSync } from "node:fs";
const [loader, diskPath] = process.argv.slice(2);
const fn = readFileSync(loader, "utf8").match(/^function diskReadBlock\(block, dstOff\) \{[\s\S]*?^\}/m)[0];
const memory = new WebAssembly.Memory({ initial: 1, maximum: 1 });
const mem = new Uint8Array(memory.buffer);
for (let i = 0; i < mem.length; i++) mem[i] = (i * 7) & 255;
const mountedDisk = diskPath === "-" ? null : { buf: new Uint8Array(readFileSync(diskPath)) };
const diskReadBlock = new Function("memory", "mountedDisk", `${fn}\nreturn diskReadBlock;`)(memory, mountedDisk);
const fnv = () => { let h = 2166136261; for (const b of mem) h = Math.imul(h ^ b, 16777619) >>> 0; return h; };
const out = [];
for (const line of readFileSync(0, "utf8").trim().split("\n")) {
    const [block, dst] = line.split(" ").map((x) => parseInt(x, 16) | 0); // a wasm i32 reaches JS signed
    let n;
    try { n = diskReadBlock(block, dst); } catch (e) { if (!(e instanceof RangeError)) throw e; n = -1; }
    out.push(`${n} ${fnv().toString(16).padStart(8, "0")}`);
}
console.log(out.join("\n"));
"""

BLOCKS = [0, 1, 2, 3, 0x40, 0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFD, 0xFFFF_FFFE, 0xFFFF_FFFF]
DSTS = [0, 0x1234, MEM - 512, MEM - 276, MEM - 100, 0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFF]


@pytest.fixture(scope="module")
def disk_test() -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    exe = WORK / "disk_test"
    src = [FPGA / "cycles/bdisk.c", FPGA / "tests/tb/disk_test.c"]
    inc = [f"-I{FPGA / d}" for d in ("host", "cycles", "gen")]
    subprocess.run(["clang", "-std=c11", "-Wall", "-Werror", *inc, *map(str, src), "-o", str(exe)], check=True)
    return exe


def _odd_disk() -> Path:
    """A disk whose last block is partial (1300 = 2 * 512 + 276 bytes)."""
    WORK.mkdir(parents=True, exist_ok=True)
    rng = random.Random(3)
    path = WORK / "odd.bin"
    path.write_bytes(bytes(rng.randrange(256) for _ in range(1300)))
    return path


def _both(disk_test: Path, disk: str, cases: list[tuple[int, int]]) -> tuple[list[str], list[str]]:
    """(browser, firmware code): one "n fnv" line per (block, dst), the memory carried along."""
    if shutil.which("node") is None:
        pytest.skip("no node")
    script = WORK / "drive.mjs"
    script.write_text(NODE_DRIVE)
    stdin = "\n".join(f"{b:x} {d:x}" for b, d in cases) + "\n"
    js = _out(["node", str(script), str(ROOT / "docs/sealed-loader.js"), disk], stdin).split("\n")
    c = _out([str(disk_test), "drive", disk], stdin).split("\n")
    return js[: len(cases)], c[: len(cases)]


def _out(cmd: list[str], stdin: str | None = None, cwd: Path | None = None) -> str:
    return subprocess.run(cmd, input=stdin, cwd=cwd, capture_output=True, text=True, check=True).stdout


@pytest.mark.parametrize("which", ["odd", "stniccc"])
def test_drive_answers_every_block_and_dst_as_the_browser_does(disk_test: Path, which: str) -> None:
    disk = _odd_disk() if which == "odd" else ROOT / "docs/demo-stniccc.zmd"
    cases = [(b, d) for b in BLOCKS for d in DSTS]
    js, c = _both(disk_test, str(disk), cases)
    assert c == js
    if which == "odd":  # the happy path and each error path, pinned
        result = dict(zip(cases, (int(line.split()[0]) for line in c), strict=True))
        assert result[(0, 0)] == 512 and result[(1, 0x1234)] == 512
        assert result[(2, MEM - 276)] == 276  # the partial last block, exactly at memory's end
        assert result[(3, 0)] == 0 and result[(0x40, 0)] == 0  # past the end: nothing, no error
        assert result[(3, 0xFFFF_FFFF)] == 0  # nothing to copy: dst is never looked at
        assert result[(0, MEM - 100)] == -1 and result[(0, 0x8000_0000)] == -1  # RangeError: a trap
        assert result[(0xFFFF_FFFE, 0)] == 512  # -2: subarray counts from the end, as the browser does
        assert result[(0xFFFF_FFFF, 0)] == 0 and result[(0x8000_0000, 0)] == 0


def test_drive_without_a_disk_answers_zero_and_writes_nothing(disk_test: Path) -> None:
    cases = [(b, d) for b in BLOCKS for d in DSTS]
    js, c = _both(disk_test, "-", cases)
    assert c == js
    assert {line.split()[0] for line in c} == {"0"} and len({line.split()[1] for line in c}) == 1


def test_scene_hash_drive_is_the_browsers_function_text_for_text() -> None:
    def body(path: Path) -> list[str]:
        m = re.search(
            r"^( *)function diskReadBlock\(block, dstOff\) \{\n([\s\S]*?)^\1\}", path.read_text(), re.MULTILINE
        )
        assert m, path
        return [line.strip() for line in m.group(2).splitlines()]

    assert body(ROOT / "apps/scene_hash.mjs") == body(ROOT / "docs/sealed-loader.js")


def _desc(disk_test: Path, rows: list[tuple[int, ...]]) -> list[str]:
    stdin = "\n".join(" ".join(f"{v & 0xFFFF_FFFF:x}" for v in r) for r in rows) + "\n"
    out = subprocess.run([str(disk_test), "desc"], input=stdin, capture_output=True, text=True, check=True)
    return out.stdout.split("\n")[: len(rows)]


def test_firmware_takes_the_descriptor_the_glass_writes_and_refuses_anything_else(disk_test: Path) -> None:
    magic, end = glass_map.DISK_MAGIC, glass_map.DISK_END
    good = struct.unpack("<4I", ddr_init.descriptor(0x30_0000, 650_240))
    rows = [
        (*good, 0x2F_0000),  # the image ends below the disk
        (*good, 0x30_1000),  # a disk over the image
        (0, *good[1:], 0x1000),  # no magic: U-Boot's flow, an old glass
        (*good[:3], good[3] ^ 1, 0x1000),  # a bad check: garbage that happens to say ZMDK
        (magic, end - 0x1000, 0x1001, ~(magic ^ (end - 0x1000) ^ 0x1001), 0),  # past the pictures
        (magic, end - 0x10, 0xFFFF_FFFF, ~(magic ^ (end - 0x10) ^ 0xFFFF_FFFF), 0),  # size wraps
        (magic, end, 0, ~(magic ^ end), 0),  # an empty disk at the very end: reads give 0
    ]
    assert _desc(disk_test, rows) == ["ok 300000 9ec00", "none", "none", "none", "none", "none", f"ok {end:x} 0"]


@pytest.fixture(scope="module")
def glass() -> dict[str, Path]:
    r = subprocess.run(
        [str(ZIG), "build"], cwd=FPGA / "glass", capture_output=True, text=True, timeout=600, check=False
    )
    assert r.returncode == 0, r.stdout + r.stderr
    return {"glass": FPGA / "glass/zig-out/bin/glass", "zx0pack": glass_sd.zx0pack()}


def _board(tools: dict[str, Path], size: int) -> bytes:
    """A synthetic board image of `size` bytes, ZX0-packed as zmd_fat expects it."""
    raw, packed = WORK / f"board{size}.rv32", WORK / f"board{size}.zx0"
    if not packed.exists():
        rng = random.Random(size)
        raw.write_bytes(bytes(rng.randrange(256) for _ in range(size // 4)) + bytes(size - size // 4))
        subprocess.run([tools["zx0pack"], raw, packed], check=True, capture_output=True)
    return packed.read_bytes()


def _sim_load(tools: dict[str, Path], disk: Path, board: bytes, window: str = "0x400000") -> tuple[str, Path]:
    fat = WORK / f"{disk.stem}.fat.zmd"
    fat.write_bytes(zmd_fat.fatten(disk.read_bytes(), board))
    out = WORK / f"{disk.stem}.ddr"
    r = subprocess.run([tools["glass"], "sim-load", fat, out, window], capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stdout + r.stderr
    return r.stderr, out


def test_glass_gives_back_every_shelf_disk_byte_for_byte(glass: dict[str, Path]) -> None:
    disks = sorted((ROOT / "docs").glob("demo-*.zmd"))
    if not disks:
        pytest.skip("no docs/demo-*.zmd shelf disk")
    board = _board(glass, 30_000)
    for disk in disks:
        _, out = _sim_load(glass, disk, board)
        assert Path(f"{out}.disk").read_bytes() == disk.read_bytes(), disk.name


def test_glass_and_the_sim_image_put_the_disk_and_descriptor_in_the_same_place(
    glass: dict[str, Path], disk_test: Path
) -> None:
    disk = ROOT / "docs/demo-stniccc.zmd"
    size = 2_123_456  # a board image's size: the disk goes at the next 4 KiB
    log, out = _sim_load(glass, disk, _board(glass, size), hex(glass_map.DDR_CART_BYTES))
    at = ddr_init.disk_at(size, disk.stat().st_size)
    assert at == 0x20_7000 and f"at +0x{at:X}," in log
    desc = Path(f"{out}.desc").read_bytes()
    assert desc == ddr_init.descriptor(at, disk.stat().st_size)
    assert _desc(disk_test, [(*struct.unpack("<4I", desc), size)]) == [f"ok {at:x} {disk.stat().st_size:x}"]


def test_sim_image_is_od_s_words_then_the_disk_and_the_descriptor_at_their_addresses() -> None:
    image = bytes(random.Random(5).randrange(256) for _ in range(5003))
    disk = b"ZMDISK" + bytes(range(256)) * 4
    lines = ddr_init.init_lines(image, disk)
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / "img.bin").write_bytes(image + bytes(-len(image) % 8))
    od = subprocess.run(
        ["od", "-An", "-v", "-tx8", "-w8", str(WORK / "img.bin")], capture_output=True, text=True, check=True
    )
    head = [w.strip() for w in od.stdout.splitlines()]
    assert lines[: len(head)] == head
    mem: dict[int, int] = {}
    addr = 0
    for line in lines:
        if line.startswith("@"):
            addr = int(line[1:], 16)
            continue
        mem[addr] = int(line, 16)
        addr += 1
    at, top = 0x2000, glass_map.DDR_CART_BYTES - glass_map.DISK_DESC_FROM_TOP
    placed = b"".join(mem[at // 8 + i].to_bytes(8, "little") for i in range(-(-len(disk) // 8)))
    assert placed[: len(disk)] == disk
    desc = mem[top // 8].to_bytes(8, "little") + mem[top // 8 + 1].to_bytes(8, "little")
    assert desc == ddr_init.descriptor(at, len(disk))
    with pytest.raises(SystemExit, match="pictures"):
        ddr_init.disk_at(glass_map.DISK_END - 0x1000, 0x1001)


def test_native_host_streams_stniccc_off_its_disk_as_scene_hash_does() -> None:
    host = FPGA / "build/host/stniccc/host"
    if not host.exists() or shutil.which("node") is None:
        pytest.skip("no native host for stniccc (make -C fpga build/host/stniccc/host) or no node")
    disk = ["--disk", "docs/demo-stniccc.zmd"]
    args = ["docs/demo-stniccc.wasm", "120", "20"]
    js = json.loads(_out(["node", "apps/scene_hash.mjs", *args, *disk], cwd=ROOT))
    native = json.loads(_out([str(host), *args, *disk], cwd=ROOT))
    blind = json.loads(_out([str(host), *args], cwd=ROOT))
    assert native["samples"] == js["samples"] and native["total"] == js["total"]
    assert len({s["hash"] for s in native["samples"]}) == 6  # the flight moves: the stream is read
    assert all(a["hash"] != b["hash"] for a, b in zip(native["samples"], blind["samples"], strict=True))
