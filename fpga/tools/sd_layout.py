"""The KESTREL SD card's layout (decisions.md 2026-11-06; docs/FPGA_GLASS.md "The SD card's layout"):
the names every staging tool writes, the same as glass reads them (fpga/glass/src/layout.zig).

    /            the boot files only (BootROM / U-Boot read them there)
    /KESTREL/    the system: system.rv32, kos/desktop.rv32, glass.cfg, an optional glass override,
                 progs/ (by-hash and per-disk program images), rollback/ (old card files)
    /CARTS/      the OSD's shelf: <category>/demo-<tag>.zmd + shelf.txt
    /HD/         KOS's C: (the desktop shell roots C:\\ there; nothing above it shows in GEM)
"""

from __future__ import annotations

from typing import Final

SYSTEM: Final = "KESTREL"
CARTS: Final = "CARTS"
HD: Final = "HD"
OLD: Final = "zigmachine"  # the layout before: one folder for all of it (sd_migrate_layout.sh moves it)
GLASS: Final = f"{SYSTEM}/glass"  # S99glass runs it instead of the rootfs's when it differs


def system(rel: str) -> str:
    """A system file's path on the card: KESTREL/<rel>."""
    return f"{SYSTEM}/{rel}"


def cart(rel: str) -> str:
    """A shelf file's path on the card: CARTS/<rel>."""
    return f"{CARTS}/{rel}"
