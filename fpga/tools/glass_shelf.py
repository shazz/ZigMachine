"""The SD card's shelf (tools/glass_sd.py stages it): a fat disk per cart, the shelf disk the
browser mounts plus the rv32 board image ZWINDOW loads (tools/zmd_fat.py), and shelf.txt.

A DATA disk (not bootable: ST Replay's) is what the browser boots GEM for
(docs/sealed-loader.js), so its fat disk carries GEM's board image (OS_CART), and GEM's
firmware does the rest from the disk itself (cycles/bdiskapp.c: docs/FPGA_GLASS.md,
"GEM over a data disk"). Nothing else marks it: the boot sector says, as in the browser.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
import shelf_meta  # after the path insert
import zmd_fat

# The board firmwares (cycles/board.mk `board-fw`): linked for the bitstream's CSR map. NOT
# build/cycles/<variant>: those are the cycles SIMULATION's, another map, and trap on the board.
BOARD_FW = FPGA / "build/hcycles/board"
CSR_MAP = FPGA / "build/hcycles/gen/csr_addr.h"
# The carts the card carries: `make -C fpga board-shelf` builds a board firmware for each, and the
# staging names any of them without one (MISSING) instead of leaving it off the card unnoticed. A
# firmware in --fw-dir that is not listed is staged too (a cart being tried out). st_replay is a
# data disk: its fat disk carries GEM's image, and its own firmware is the program GEM launches.
SHELF = (
    "blitter", "fuji_hobbytronic", "gem", "polkadots", "raytrace", "raytrace_f32", "replicants_emlyn",
    "sap_test", "skystrike", "st_replay", "stniccc", "tsl_hybridglenz", "tutorial", "ulm_dsots", "union_beatdis",
)  # fmt: skip
OS_CART = "gem"  # what the browser boots for a data disk


def zx0pack() -> Path:
    """The repo's own packer, built once into build/glass/."""
    exe = FPGA / "build/glass/zx0pack"
    if not exe.exists():
        exe.parent.mkdir(parents=True, exist_ok=True)
        zig = Path.home() / ".local/zig/0.16.0/zig"
        subprocess.run([zig, "build-exe", "-OReleaseFast", "--dep", "zx0_pack", f"-Mroot={ROOT}/tools/zx0pack/main.zig",
                        f"-Mzx0_pack={ROOT}/libs/zig/depackers/zx0_pack.zig", f"-femit-bin={exe}"],
                       check=True, cwd=exe.parent)  # fmt: skip
    return exe


def boots(disk: bytes) -> str:
    """The cart whose board image a disk's fat disk carries: its own, or GEM for a data disk."""
    return "" if zmd_fat.bootable(disk) else OS_CART


def _fat_disk(tag: str, fw_dir: Path, csr_map: Path, dest: Path) -> tuple[str, str]:
    name = f"zigmachine/demo-{tag}.zmd"
    disk = ROOT / "docs" / f"demo-{tag}.zmd"
    if not disk.exists():
        return name, f"MISSING: no {disk.name} on the shelf"
    img = disk.read_bytes()
    cart = boots(img) or tag
    fw = fw_dir / cart / "fw.bin"
    if not fw.exists():
        return name, f"MISSING: no {fw}; make -C fpga board-fw CART={cart}"
    if csr_map.exists() and fw.stat().st_mtime < csr_map.stat().st_mtime:
        return name, f"STALE: {fw} predates the CSR map; make board-fw CART={cart}"
    packed = dest / f"{tag}.rv32.zx0"
    subprocess.run([zx0pack(), fw, packed], check=True, capture_output=True)
    (dest / disk.name).write_bytes(zmd_fat.fatten(img, packed.read_bytes()))
    packed.unlink()
    src = fw.relative_to(FPGA) if fw.is_relative_to(FPGA) else fw
    return name, f"{disk.relative_to(ROOT)} + {src}" + (" (a data disk: GEM boots)" if cart != tag else "")


def build_shelf(
    dest: Path, fw_dir: Path, csr_map: Path = CSR_MAP, shelf: tuple[str, ...] = SHELF
) -> list[tuple[str, str]]:
    """A fat disk for every shelf cart with a board image in `fw_dir` (one per cart)."""
    dest.mkdir(parents=True, exist_ok=True)
    every = sorted(set(shelf) | {fw.parent.name for fw in fw_dir.glob("*/fw.bin")})
    rows = [_fat_disk(tag, fw_dir, csr_map, dest) for tag in every]
    tags = [r[0].removeprefix("zigmachine/demo-").removesuffix(".zmd") for r in rows if not r[1].startswith("MISSING")]
    if not tags:
        return rows
    shelf_meta.write(dest, tags)
    rows.append((f"zigmachine/{shelf_meta.FILE}", f"tools/shelf_meta.py ({len(tags)} carts)"))
    return rows
