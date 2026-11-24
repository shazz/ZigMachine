"""card.py's command line."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .errors import CardError


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="card.py", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("stage", help="stage a card's files into <out>/<name>/up")
    s.add_argument("--board", required=True, help="kestrel | peregrine")
    s.add_argument("--name", required=True, help="the card's name (KESTREL/rollback/<name>/)")
    s.add_argument("--cart", action="append", default=[], metavar="TAG", help="a cart (bootable or data disk), repeatable")
    s.add_argument("--fw-dir", type=Path, help="the board images (<tag>/cart.bin or fw.bin)")
    s.add_argument("--system", type=Path, help="the system image (sys.bin): staged as KESTREL/system.rv32, carts are lean")
    s.add_argument("--system-version", help="MAJOR.MINOR of a system already on the card (lean carts, no system staged)")
    s.add_argument("--bit", type=Path, help="a bitstream, checked against the board's part")
    s.add_argument("--rootfs-overlay", type=Path, metavar="DIR", help="appended to --rootfs-base as one more newc archive")
    s.add_argument("--rootfs-base", type=Path, help="the board's own rootfs.cpio.uboot")
    s.add_argument("--shelf-from", type=Path, help="the board's CARTS/shelf.txt: staged with the new carts' lines added")
    s.add_argument("--boot-dir", type=Path, help="a card from blank: BOOT.BIN (checked for the board), boot.scr, zImage, dtb, rootfs")
    s.add_argument("--out", required=True, type=Path)
    i = sub.add_parser("install", help="tar a staged card to the board over ssh and run its install.sh")
    i.add_argument("--host", required=True, help="root@<ip>")
    i.add_argument("--ssh", default="ssh")
    i.add_argument("dir", type=Path)
    return p


def run_stage(a: argparse.Namespace) -> None:
    from . import stage as st  # imports the repo's tools: only when staging

    req = st.Request(a.board, a.name, a.out, a.cart, a.fw_dir or st.FW_DIR, a.system, a.system_version, a.bit,
                     a.rootfs_overlay, a.rootfs_base, a.shelf_from, a.boot_dir)  # fmt: skip
    up, rows = st.stage(req)
    for name, src in rows:
        print(f"   {name:40} {src}")
    print((up / "MD5SUMS_up").read_text() + f"staged: {up}")


def main(argv: list[str] | None = None) -> int:
    a = parser().parse_args(argv)
    try:
        if a.cmd == "stage":
            run_stage(a)
        else:
            from . import remote

            remote.install(a.host, a.dir, a.ssh)
    except CardError as e:
        print(f"card.py: REFUSED\n{e}", file=sys.stderr)
        return 1
    return 0
