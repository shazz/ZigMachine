"""The SD card's shelf (tools/glass_sd.py stages it): a fat disk per cart, the shelf disk the
browser mounts plus the rv32 board image ZWINDOW loads (tools/zmd_fat.py), and shelf.txt.

A DATA disk (not bootable: ST Replay's) is what KOS boots its desktop over (docs/ZIGTOS_BOOT.md,
KOS = ZigTOS), as the browser does: the card carries the desktop ONCE, as zigmachine/kos/desktop.rv32
(OS_CART's board image, ZX0-packed), and a data disk is staged as it is, just files: the glass puts
the desktop and the disk in DDR (glass/src/app_drive.zig), and the desktop's firmware does the rest
from the disk itself (cycles/bdiskapp.c: docs/FPGA_GLASS.md, "GEM over a data disk"). Nothing else
marks it: the boot sector says, as in the browser.

A program on a data disk (a type-0 FAT file: ST Replay's BOOT.WSM) is wasm GEM asks the
browser to run (request 3); on the board it must be native code built beforehand. Each one
gets its own fat disk, the SAME data disk plus the program's board image, at
zigmachine/progs/demo-<tag>/<NAME>.zmd, where ZWINDOW looks for it (glass/src/app_request.zig)
and the shelf's scan does not. Which board image: the cart whose docs/demo-<cart>.wasm is the
program's bytes, depacked (tools/mkdisks.sh writes BOOT.WSM from a cart of the matrix).
"""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
import shelf_meta  # after the path insert
import split_image
from glass_zx0 import program_cart, zx0pack, zx0unpack  # re-exported: the shelf's tests use them
import zmd_fat

# The board firmwares (cycles/board.mk `board-fw`): linked for the bitstream's CSR map. NOT
# build/cycles/<variant>: those are the cycles SIMULATION's, another map, and trap on the board.
BOARD_FW = FPGA / "build/hcycles/board"
CSR_MAP = FPGA / "build/hcycles/gen/csr_addr.h"
# The carts the card carries: `make -C fpga board-shelf` builds a board firmware for each, and the
# staging names any of them without one (MISSING) instead of leaving it off the card unnoticed. A
# firmware in --fw-dir that is not listed is staged too (a cart being tried out). st_replay and
# sysinfo are data disks: staged as they are (KOS's desktop boots over them), and the cart's own
# firmware is the program GEM launches (progs/demo-<tag>/BOOT.WSM.zmd). GEM itself is no shelf disk:
# it is KOS's desktop (OS_CART, kos/desktop.rv32), which an empty drive boots.
SHELF = (
    "blitter", "fuji_hobbytronic", "music", "polkadots", "raytrace", "raytrace_f32", "replicants_emlyn",
    "sap_test", "skystrike", "st_replay", "stniccc", "sysinfo", "tsl_hybridglenz", "tutorial", "ulm_dsots",
    "union_beatdis",
    # The Union Demo's street and the carts its doors boot (apps/zig/scenes/union_demo/doors.zig): on the
    # board a door is a REQ_LOAD_CART for its shelf disk, and the screen's -1 comes back (app_request.zig).
    "union_demo", "union_deltaforce", "union_tnt3", "union_superscroller", "union_tnt1", "union_reps",
    "union_tnt2", "union_l16", "union_multifake", "union_texcopier", "union_textracker",
)  # fmt: skip
OS_CART = "gem"  # KOS's desktop: what the browser boots for a data disk or an empty drive
DESKTOP_FILE = "kos/desktop.rv32"  # glass/src/app_drive.zig DESKTOP
SYS_FILE = "system.rv32"  # glass/src/system.zig FILE


@dataclass(frozen=True)
class Images:
    """Where the board images come from: <fw_dir>/<cart>/fw.bin, monolithic; or, given the
    system's table version, the lean <fw_dir>/<cart>/cart.bin that system runs (decisions.md
    2026-10-15: the card then carries the system once, as system.rv32)."""

    fw_dir: Path
    system_version: int | None = None

    def path(self, cart: str) -> Path:
        return self.fw_dir / cart / ("fw.bin" if self.system_version is None else "cart.bin")

    def problem(self, cart: str) -> str | None:
        """Why the card cannot carry `cart`'s image (MISSING / REFUSED), or None."""
        fw = self.path(cart)
        if not fw.exists():
            how = "board-fw" if self.system_version is None else "split-cart"
            return f"MISSING: no {fw}; make -C fpga {how} CART={cart}"
        if self.system_version is not None:
            try:
                split_image.check_pair(self.system_version, fw.read_bytes())
            except split_image.SplitError as e:
                return f"REFUSED: {fw}: {e}"
        return None


def programs(tag: str, img: bytes, images: Images, dest: Path) -> list[tuple[str, str]]:
    """A fat disk per program on data disk `tag` (`img`): progs/demo-<tag>/<NAME>.zmd."""
    rows = []
    for name, start, length, kind in zmd_fat.files(img):
        if kind != 0:
            continue
        out = f"zigmachine/progs/demo-{tag}/{name}.zmd"
        cart = program_cart(img[start : start + length], dest)
        why = "MISSING: no docs/demo-*.wasm is this program" if cart is None else images.problem(cart)
        if why:
            rows.append((out, why))
            continue
        fw = images.path(str(cart))
        (dest / "progs" / f"demo-{tag}").mkdir(parents=True, exist_ok=True)
        packed = dest / f"{tag}.{name}.rv32.zx0"
        subprocess.run([zx0pack(), fw, packed], check=True, capture_output=True)
        (dest / "progs" / f"demo-{tag}" / f"{name}.zmd").write_bytes(zmd_fat.fatten(img, packed.read_bytes()))
        packed.unlink()
        rows.append((out, f"docs/demo-{tag}.zmd + {fw.relative_to(FPGA) if fw.is_relative_to(FPGA) else fw} ({name})"))
    return rows


def boots(disk: bytes) -> str:
    """The cart whose board image a disk's fat disk carries: its own; "" for a data disk, which
    carries none (KOS's desktop boots over it)."""
    return "" if not zmd_fat.bootable(disk) else "own"


def stage_desktop(images: Images, dest: Path) -> tuple[str, str]:
    """KOS's desktop, once: OS_CART's board image, ZX0-packed, at kos/desktop.rv32."""
    name = f"zigmachine/{DESKTOP_FILE}"
    if why := images.problem(OS_CART):
        return (name, why)
    fw = images.path(OS_CART)
    (dest / "kos").mkdir(parents=True, exist_ok=True)
    subprocess.run([zx0pack(), fw, dest / DESKTOP_FILE], check=True, capture_output=True)
    return (name, f"{fw.relative_to(FPGA) if fw.is_relative_to(FPGA) else fw} (KOS's desktop)")


def _fat_disk(tag: str, images: Images, csr_map: Path, dest: Path) -> list[tuple[str, str]]:
    name = f"zigmachine/demo-{tag}.zmd"
    native = images.fw_dir / tag / "disk.zmd"  # a native cart's board-only disk (tools/native_cart.py)
    disk = native if native.exists() else ROOT / "docs" / f"demo-{tag}.zmd"
    if not disk.exists():
        return [(name, f"MISSING: no {disk.name} on the shelf")]
    img = disk.read_bytes()
    if not boots(img):  # a data disk: just files, the desktop boots over it
        (dest / f"demo-{tag}.zmd").write_bytes(img)
        rel = disk.relative_to(ROOT) if disk.is_relative_to(ROOT) else disk
        return [(name, f"{rel} (a data disk: KOS's desktop boots over it)"), *programs(tag, img, images, dest)]
    cart = tag
    fw = images.path(cart)
    if why := images.problem(cart):
        return [(name, why)]
    if images.system_version is None and csr_map.exists() and fw.stat().st_mtime < csr_map.stat().st_mtime:
        return [(name, f"STALE: {fw} predates the CSR map; make board-fw CART={cart}")]
    packed = dest / f"{tag}.rv32.zx0"
    subprocess.run([zx0pack(), fw, packed], check=True, capture_output=True)
    (dest / f"demo-{tag}.zmd").write_bytes(zmd_fat.fatten(img, packed.read_bytes()))
    packed.unlink()
    src = fw.relative_to(FPGA) if fw.is_relative_to(FPGA) else fw
    disk = disk.relative_to(ROOT) if disk.is_relative_to(ROOT) else disk
    return [(name, f"{disk} + {src}")]


def stage_system(dest: Path, system: Path, csr_map: Path) -> tuple[tuple[str, str], int]:
    """The card's system.rv32 (split_image.sys_file, ZX0-packed) and the table version it serves."""
    image = system.read_bytes()
    version = split_image.table_version(image)
    raw = dest / f"{SYS_FILE}.raw"
    raw.write_bytes(split_image.sys_file(image, version))
    subprocess.run([zx0pack(), raw, dest / SYS_FILE], check=True, capture_output=True)
    raw.unlink()
    src = system.relative_to(FPGA) if system.is_relative_to(FPGA) else system
    note = f"{src} (table {split_image.vtext(version)})"
    if csr_map.exists() and system.stat().st_mtime < csr_map.stat().st_mtime:
        note = f"STALE: {src} predates the CSR map; make board-split"
    return (f"zigmachine/{SYS_FILE}", note), version


def build_shelf(
    dest: Path, fw_dir: Path, csr_map: Path = CSR_MAP, shelf: tuple[str, ...] = SHELF, system: Path | None = None
) -> list[tuple[str, str]]:
    """A fat disk for every shelf cart with a board image in `fw_dir` (one per cart); with a
    `system` image, the card's system.rv32 and lean carts (Images)."""
    dest.mkdir(parents=True, exist_ok=True)
    rows, images = [], Images(fw_dir)
    if system is not None:
        row, version = stage_system(dest, system, csr_map)
        rows, images = [row], Images(fw_dir, version)
    every = sorted(set(shelf) | {fw.parent.name for fw in fw_dir.glob(f"*/{images.path('x').name}")} - {OS_CART})
    rows += [stage_desktop(images, dest)]
    rows += [row for tag in every for row in _fat_disk(tag, images, csr_map, dest)]
    shelf_rows = [r for r in rows if r[0].startswith("zigmachine/demo-") and not r[1].startswith("MISSING")]
    tags = [r[0].removeprefix("zigmachine/demo-").removesuffix(".zmd") for r in shelf_rows]
    if not tags:
        return rows
    shelf_meta.write(dest, tags)
    rows.append((f"zigmachine/{shelf_meta.FILE}", f"tools/shelf_meta.py ({len(tags)} carts)"))
    return rows
