"""`card.py stage --boot-dir DIR`: the card root's boot files, for a card made from blank (a new board).

DIR holds what the board boots from: BOOT.BIN (checked against the board's chip, bootbin.py), boot.scr,
the kernel, its DTB and the rootfs (plan A, tools/glass_sd.py or build_planA.sh --stage write such a
directory), and u-boot.img when BOOT.BIN is plan A's SPL. Every file but BOOT.BIN is the same on both
boards: the same PS, the same DDR, the same device tree, and U-Boot's `fpga loadb` reads the part itself."""

from __future__ import annotations

import shutil
from pathlib import Path

from . import bootbin
from .errors import CardError

NEEDED = ("BOOT.BIN", "boot.scr", "zImage", "zigmachine.dtb", "rootfs.cpio.uboot")
OPTIONAL = ("u-boot.img",)  # plan A: the SPL loads it from the card
ROOTFS = "rootfs.cpio.uboot"


def check(boot_dir: Path, dbpart: str, board: str) -> str:
    """BOOT.BIN's verdict; CardError when a needed file is missing or BOOT.BIN is for the other chip."""
    if not boot_dir.is_dir():
        raise CardError(f"--boot-dir {boot_dir}: not a directory")
    if missing := [f for f in NEEDED if not (boot_dir / f).is_file()]:
        raise CardError(f"--boot-dir {boot_dir}: no {', '.join(missing)}")
    return bootbin.check_board((boot_dir / "BOOT.BIN").read_bytes(), dbpart, board, str(boot_dir / "BOOT.BIN"))


def stage(boot_dir: Path, up: Path, verdict: str, keep_rootfs: bool) -> list[tuple[str, str]]:
    """Copy the boot files to up/; keep_rootfs=False when --rootfs-overlay builds rootfs.cpio.uboot instead."""
    rows: list[tuple[str, str]] = []
    for name in NEEDED + OPTIONAL:
        src = boot_dir / name
        if not src.is_file() or (name == ROOTFS and not keep_rootfs):
            continue
        shutil.copyfile(src, up / name)
        rows.append((name, f"{src} ({verdict})" if name == "BOOT.BIN" else str(src)))
    return rows
