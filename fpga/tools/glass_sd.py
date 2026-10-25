"""Stage the ZigMachine console's SD card in a DIRECTORY (docs/FPGA_GLASS.md).

    uv run python tools/glass_sd.py [--out build/glass/sd] [--buildroot BR_OUTPUT_DIR]
    uv run python tools/glass_sd.py --shelf      # the shelf's carts (SHELF), what `make board-shelf` builds
    uv run python tools/glass_sd.py --system build/hcycles/split/board_snd/sys.bin --fw-dir build/hcycles/split/carts
                                                 # the split card (decisions.md 2026-10-15): `make board-split`

Nothing is written to a device: copy the directory's contents onto the card's
first (FAT32) partition yourself. MANIFEST.txt in it lists every file, where it
came from, and what is still missing.

On the card:
    BOOT.BIN                 zeST's (FSBL + U-Boot): DDR, clocks and MIO without Vivado
    boot.scr                 fpga/glass/boot/boot.cmd, compiled
    zigmachine.bit           the board SoC (--bit; default the blitter one, build/board_hp/zm_blit_vivado_100.bit)
    zImage, zigmachine.dtb, rootfs.cpio.uboot    plan A: our Buildroot Linux (--buildroot); the rootfs gets
                             this glass at /usr/bin/glass (S99glass runs it; tools/rootfs_glass.py)
    uImage, rootfs.ub, glass                     plan B: zeST's Linux + our ARM binary
    zigmachine/*.zmd         the shelf: fat disks (wasm cart + rv32 BOARD image, build/hcycles/board/<cart>/fw.bin;
                             a data disk is staged as it is: tools/glass_shelf.py)
    zigmachine/kos/desktop.rv32  KOS's desktop (GEM's board image), booted for a data disk or an empty drive
    zigmachine/progs/demo-<tag>/<NAME>.zmd   a data disk's programs, prebuilt (glass/src/app_request.zig)
    zigmachine/system.rv32   --system: firmware + machine + ROM + BARD, once; the fat disks then carry lean
                             carts (<fw-dir>/<cart>/cart.bin) that it runs (tools/glass_shelf.py Images)
    zigmachine/shelf.txt     what the OSD says about each cart (tools/shelf_meta.py)
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import struct
import sys
import tarfile
import time
import zlib
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
import rootfs_glass  # after the path insert
from glass_shelf import BOARD_FW, OS_CART, SHELF, build_shelf, zx0pack  # after the path insert; re-exported

ZEST = FPGA / "boards/microphase_z7_7010/vendor/zest-bin"
ZEST_TAR = ZEST / "zeST-20260518.tar.xz"
ZEST_BOOT = ZEST / "zeST-20260518/boards/z7lite_7010/boot.bin"
BOOT_CMD = FPGA / "glass/boot/boot.cmd"
BITSTREAM = FPGA / "build/board_hp/zm_blit_vivado_100.bit"
GLASS_ARM = FPGA / "glass/zig-out/arm/bin/glass"
__all__ = ["BOARD_FW", "SHELF", "build_shelf", "zx0pack"]  # the shelf's half lives in glass_shelf.py
IH_MAGIC, IH_OS_LINUX, IH_ARCH_ARM, IH_TYPE_SCRIPT = 0x27051956, 5, 2, 6


def script_image(text: bytes, name: str, epoch: int) -> bytes:
    """A U-Boot legacy script image, as `mkimage -A arm -O linux -T script -C none` makes."""
    data = struct.pack(">II", len(text), 0) + text
    head = struct.pack(">IIIIIIIBBBB32s", IH_MAGIC, 0, epoch, len(data), 0, 0, zlib.crc32(data), IH_OS_LINUX,
                       IH_ARCH_ARM, IH_TYPE_SCRIPT, 0, name.encode()[:32])  # fmt: skip
    head = head[:4] + struct.pack(">I", zlib.crc32(head)) + head[8:]
    return head + data


def script_text(cmd: bytes) -> bytes:
    """boot.cmd without its comments or blank lines: zeST's U-Boot (old hush) read a comment's
    apostrophe as an open quote, a `syntax error` that skipped the whole script (2026-10-10)."""
    lines = [ln.strip() for ln in cmd.decode("ascii").splitlines()]
    return "".join(ln + "\n" for ln in lines if ln and not ln.startswith("#")).encode()


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


def _rootfs(buildroot: Path | None, out: Path, epoch: int) -> tuple[str, str]:
    """Buildroot's rootfs with THIS glass at /usr/bin/glass: S99glass runs that copy at every boot, and
    boot.cmd's HP1 0xF00 needs a glass that knows afi.zig (tools/rootfs_glass.py)."""
    if buildroot is None or not (buildroot / "images/rootfs.cpio").exists() or not GLASS_ARM.exists():
        src = buildroot / "images/rootfs.cpio.uboot" if buildroot else None
        name, how = _copy(src, out, "rootfs.cpio.uboot", "plan A needs --buildroot (Buildroot output)")
        stale = "STALE: Buildroot's own glass, but boot.cmd sets HP1 0xF00: build the ARM glass and images/rootfs.cpio"
        return name, how if how.startswith("MISSING") else f"{stale} ({how})"
    images = buildroot / "images"
    strip = rootfs_glass.buildroot_strip(buildroot)
    body = rootfs_glass.build(images / "rootfs.cpio", GLASS_ARM, out / "rootfs.cpio.uboot", strip, epoch)
    return "rootfs.cpio.uboot", f"{images / 'rootfs.cpio'} + glass md5 {hashlib.md5(body).hexdigest()}"


def stage(
    out: Path, buildroot: Path | None, fw_dir: Path = BOARD_FW, bit: Path = BITSTREAM, system: Path | None = None
) -> list[tuple[str, str]]:
    if str(out.resolve()).startswith("/dev") or out.is_block_device():
        raise SystemExit("glass_sd: refusing to write to a device; give a directory and copy it yourself")
    out.mkdir(parents=True, exist_ok=True)
    epoch = int(time.time())
    (out / "boot.scr").write_bytes(script_image(script_text(BOOT_CMD.read_bytes()), "zigmachine", epoch))
    rows = [("boot.scr", str(BOOT_CMD.relative_to(ROOT)))]
    rows.append(_copy(ZEST_BOOT, out, "BOOT.BIN", "run fpga/tools/fetch_board.sh (zeST's boot.bin)"))
    rows.append(_copy(bit, out, "zigmachine.bit", "build the SoC: soc.zigmachine_soc --target z7 --build"))
    if bit.exists() and bit.stat().st_mtime < _newest_glass_source():
        rows[-1] = ("zigmachine.bit", f"STALE: {bit.name} predates the glass RTL; rebuild the SoC")
    images = buildroot / "images" if buildroot else None
    for src, name in (("zImage", "zImage"), ("zigmachine-z7lite.dtb", "zigmachine.dtb")):
        rows.append(_copy(images / src if images else None, out, name, "plan A needs --buildroot (Buildroot output)"))
    rows.append(_rootfs(buildroot, out, epoch))
    rows += _zest_linux(out)
    rows.append(_copy(GLASS_ARM, out, "glass", "cd fpga/glass && zig build -Dtarget=arm-linux-musleabihf ..."))
    return rows + build_shelf(out / "zigmachine", fw_dir, system=system)


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
    br = FPGA / "build/buildroot"  # without one the card gets boot.cmd's HP1 0xF00 and no rootfs: say MISSING
    p.add_argument("--buildroot", type=Path, default=br if br.is_dir() else None, help="Buildroot's output (images/)")
    p.add_argument("--fw-dir", type=Path, default=BOARD_FW, help="the board firmwares (<cart>/fw.bin)")
    p.add_argument("--bit", type=Path, default=BITSTREAM, help="the board bitstream the firmwares were built for")
    p.add_argument("--shelf", action="store_true", help="print the shelf's carts and stop")
    p.add_argument("--system", type=Path, help="the split system image (sys.bin): --fw-dir then holds lean carts")
    a = p.parse_args()
    if a.shelf:
        print(" ".join((*SHELF, OS_CART)))  # the shelf, and KOS's desktop
        return
    print(manifest(a.out, stage(a.out, a.buildroot, a.fw_dir, a.bit, a.system)), end="")


if __name__ == "__main__":
    main()
