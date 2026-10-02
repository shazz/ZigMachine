"""Stage the ZigMachine console's SD card in a DIRECTORY (docs/FPGA_GLASS.md).

    uv run python tools/glass_sd.py [--out build/glass/sd] [--buildroot BR_OUTPUT_DIR]

Nothing is written to a device: copy the directory's contents onto the card's
first (FAT32) partition yourself. MANIFEST.txt in it lists every file, where it
came from, and what is still missing.

On the card:
    BOOT.BIN                 zeST's (FSBL + U-Boot): DDR, clocks and MIO without Vivado
    boot.scr                 fpga/glass/boot/boot.cmd, compiled
    zigmachine.bit           the SoC with the glass (build/soc_z7/gateware/platform_z7.bit)
    zImage, zigmachine.dtb, rootfs.cpio.uboot    plan A: our Buildroot Linux (--buildroot)
    uImage, rootfs.ub, glass                     plan B: zeST's Linux + our ARM binary
    zigmachine/*.zmd         the shelf: fat disks (wasm cart + rv32 board image)
"""

from __future__ import annotations

import argparse
import shutil
import struct
import subprocess
import sys
import tarfile
import time
import zlib
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
import zmd_fat  # after the path insert

ZEST = FPGA / "boards/microphase_z7_7010/vendor/zest-bin"
ZEST_TAR = ZEST / "zeST-20260518.tar.xz"
ZEST_BOOT = ZEST / "zeST-20260518/boards/z7lite_7010/boot.bin"
BOOT_CMD = FPGA / "glass/boot/boot.cmd"
BITSTREAM = FPGA / "build/soc_z7/gateware/platform_z7.bit"
GLASS_ARM = FPGA / "glass/zig-out/arm/bin/glass"
IH_MAGIC, IH_OS_LINUX, IH_ARCH_ARM, IH_TYPE_SCRIPT = 0x27051956, 5, 2, 6


def script_image(text: bytes, name: str, epoch: int) -> bytes:
    """A U-Boot legacy script image, as `mkimage -A arm -O linux -T script -C none` makes."""
    data = struct.pack(">II", len(text), 0) + text
    head = struct.pack(">IIIIIIIBBBB32s", IH_MAGIC, 0, epoch, len(data), 0, 0, zlib.crc32(data), IH_OS_LINUX,
                       IH_ARCH_ARM, IH_TYPE_SCRIPT, 0, name.encode()[:32])  # fmt: skip
    head = head[:4] + struct.pack(">I", zlib.crc32(head)) + head[8:]
    return head + data


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


def build_shelf(dest: Path, variant: str) -> list[tuple[str, str]]:
    """A fat disk for every shelf disk whose cart has a board image of `variant`."""
    rows = []
    dest.mkdir(parents=True, exist_ok=True)
    for fw in sorted((FPGA / "build/cycles" / variant).glob("*/fw.bin")):
        tag = fw.parent.name
        disk = ROOT / "docs" / f"demo-{tag}.zmd"
        if not disk.exists():
            rows.append((f"zigmachine/demo-{tag}.zmd", f"MISSING: no {disk.name} on the shelf"))
            continue
        packed = dest / f"{tag}.rv32.zx0"
        subprocess.run([zx0pack(), fw, packed], check=True, capture_output=True)
        (dest / disk.name).write_bytes(zmd_fat.fatten(disk.read_bytes(), packed.read_bytes()))
        packed.unlink()
        rows.append((f"zigmachine/{disk.name}", f"{disk.relative_to(ROOT)} + {fw.relative_to(FPGA)}"))
    return rows


def _copy(src: Path | None, out: Path, name: str, why_missing: str) -> tuple[str, str]:
    if src is None or not src.exists():
        return name, f"MISSING: {why_missing}"
    shutil.copyfile(src, out / name)
    return name, str(src)


def _zest_linux(out: Path) -> list[tuple[str, str]]:
    if not ZEST_TAR.exists():
        return [("uImage, rootfs.ub", "MISSING: run fpga/tools/fetch_board.sh")]
    with tarfile.open(ZEST_TAR) as tar:
        for name in ("uImage", "rootfs.ub"):
            src = tar.extractfile(f"zeST-20260518/{name}")
            assert src is not None, name
            (out / name).write_bytes(src.read())
    return [("uImage", f"{ZEST_TAR.name} (plan B)"), ("rootfs.ub", f"{ZEST_TAR.name} (plan B)")]


def _newest_glass_source() -> float:
    """A bitstream older than the glass's RTL or LiteX wrapper does not have it."""
    srcs = [*(FPGA / "rtl/glass").glob("*.v"), FPGA / "soc/zm_glass.py", FPGA / "glass/src/map.zig"]
    return max(p.stat().st_mtime for p in srcs)


def stage(out: Path, buildroot: Path | None, variant: str) -> list[tuple[str, str]]:
    if str(out.resolve()).startswith("/dev") or out.is_block_device():
        raise SystemExit("glass_sd: refusing to write to a device; give a directory and copy it yourself")
    out.mkdir(parents=True, exist_ok=True)
    epoch = int(time.time())
    (out / "boot.scr").write_bytes(script_image(BOOT_CMD.read_bytes(), "zigmachine", epoch))
    rows = [("boot.scr", str(BOOT_CMD.relative_to(ROOT)))]
    rows.append(_copy(ZEST_BOOT, out, "BOOT.BIN", "run fpga/tools/fetch_board.sh (zeST's boot.bin)"))
    rows.append(_copy(BITSTREAM, out, "zigmachine.bit", "build the SoC: soc.zigmachine_soc --target z7 --build"))
    if BITSTREAM.exists() and BITSTREAM.stat().st_mtime < _newest_glass_source():
        rows[-1] = ("zigmachine.bit", f"STALE: {BITSTREAM.name} predates the glass RTL; rebuild the SoC")
    images = buildroot / "images" if buildroot else None
    for src, name in (("zImage", "zImage"), ("zigmachine-z7lite.dtb", "zigmachine.dtb"),
                      ("rootfs.cpio.uboot", "rootfs.cpio.uboot")):  # fmt: skip
        rows.append(_copy(images / src if images else None, out, name, "plan A needs --buildroot (Buildroot output)"))
    rows += _zest_linux(out)
    rows.append(_copy(GLASS_ARM, out, "glass", "cd fpga/glass && zig build -Dtarget=arm-linux-musleabihf ..."))
    return rows + build_shelf(out / "zigmachine", variant)


def manifest(out: Path, rows: list[tuple[str, str]]) -> str:
    lines = [f"{name:32} {src}" for name, src in rows]
    text = "\n".join(
        ["ZigMachine SD card: copy everything here onto the card's first (FAT32) partition.", "", *lines, ""]
    )
    (out / "MANIFEST.txt").write_text(text)
    return text


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=Path, default=FPGA / "build/glass/sd")
    p.add_argument("--buildroot", type=Path, help="Buildroot's output directory (has images/)")
    p.add_argument("--variant", default="aligned", help="which fpga/cycles board build goes on the shelf")
    a = p.parse_args()
    print(manifest(a.out, stage(a.out, a.buildroot, a.variant)), end="")


if __name__ == "__main__":
    main()
