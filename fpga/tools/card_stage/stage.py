"""`card.py stage`: carts + system + bitstream + rootfs overlay into up/, for ONE board."""

from __future__ import annotations

import hashlib
import re
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

from . import bitfile, boot, install_sh, rootfs, shelf
from .errors import CardError

FPGA = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(FPGA))
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(FPGA / "gen"))
import glass_shelf  # after the path insert
import sd_layout
import shelf_meta
import split_image
from soc import boards

NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}")
TAG = re.compile(r"[a-z0-9][a-z0-9_]*")
BAD = ("MISSING", "STALE", "REFUSED")
FW_DIR = FPGA / "build/hcycles/split/carts_fpu"


@dataclass
class Request:
    board: str
    name: str
    out: Path
    carts: list[str] = field(default_factory=list)
    fw_dir: Path = FW_DIR
    system: Path | None = None
    system_version: str | None = None  # "1.27": carts only, no system image staged
    bit: Path | None = None
    rootfs_overlay: Path | None = None
    rootfs_base: Path | None = None
    shelf_from: Path | None = None
    boot_dir: Path | None = None  # a card from blank: the root's boot files (boot.py)


def parse_version(text: str) -> int:
    m = re.fullmatch(r"(\d+)\.(\d+)", text)
    if not m:
        raise CardError(f"--system-version {text!r}: want MAJOR.MINOR, as 1.27")
    return int(m[1]) << 16 | int(m[2])


def check_request(r: Request) -> boards.Board:
    """Every refusal that needs no staging: board, names, files for the right board."""
    try:
        board = boards.get(r.board)
    except boards.UnknownBoardError as e:
        raise CardError(str(e)) from e
    if not NAME.fullmatch(r.name):
        raise CardError(f"card name {r.name!r}: letters, digits, _ . - only")
    if (r.out / r.name).exists():
        raise CardError(f"card {r.name!r} already exists: {r.out / r.name}")
    if bad := [t for t in r.carts if not TAG.fullmatch(t)]:
        raise CardError(f"not a cart tag: {', '.join(bad)}")
    if r.system and r.system_version:
        raise CardError("--system and --system-version are exclusive: the system image carries its version")
    if bool(r.rootfs_overlay) != bool(r.rootfs_base):
        raise CardError("--rootfs-overlay needs --rootfs-base (the board's image it is appended to), and the reverse")
    if r.shelf_from and not r.carts:
        raise CardError("--shelf-from without --cart: nothing to add to the shelf")
    if r.bit:
        bitfile.check_board(r.bit.read_bytes(), board.dbpart, board.name, str(r.bit))
    if r.boot_dir:
        boot.check(r.boot_dir, board.dbpart, board.name)
    return board


def _csr(r: Request) -> Path:
    return boards.get(r.board).build_dir / "soc_z7/csr.json"


def _images(r: Request, up: Path) -> tuple[glass_shelf.Images, list[tuple[str, str]]]:
    if r.system:
        row, version = glass_shelf.stage_system(up / sd_layout.SYSTEM, r.system, _csr(r))
        return glass_shelf.Images(r.fw_dir, version), [row]
    version = parse_version(r.system_version) if r.system_version else None
    return glass_shelf.Images(r.fw_dir, version), []


def _carts(r: Request, up: Path, images: glass_shelf.Images) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for tag in r.carts:
        rows += glass_shelf._fat_disk(tag, images, _csr(r), up)
    rows += glass_shelf.stage_by_hash(r.carts, images.path, images.problem, up / sd_layout.SYSTEM)
    return rows


def _record(tag: str) -> tuple[str, ...]:
    return shelf_meta.records([tag])[0]


def _shelf(r: Request, up: Path, shelf_from: Path) -> tuple[str, str]:
    text, added = shelf.merge(shelf_from.read_text(), r.carts, _record)
    (up / sd_layout.CARTS).mkdir(exist_ok=True)
    (up / sd_layout.CARTS / shelf_meta.FILE).write_text(text)
    return sd_layout.cart(shelf_meta.FILE), f"{shelf_from} + {len(added)} new line(s): {', '.join(added) or 'none'}"


def _extras(r: Request, up: Path) -> list[tuple[str, str]]:
    rows = []
    if r.bit:
        shutil.copyfile(r.bit, up / "zigmachine.bit")
        rows.append(("zigmachine.bit", f"{r.bit} (part {bitfile.part_of(r.bit.read_bytes())})"))
    if r.rootfs_overlay and r.rootfs_base:
        (up / "rootfs.cpio.uboot").write_bytes(rootfs.build(r.rootfs_base, r.rootfs_overlay, 0))
        rows.append(("rootfs.cpio.uboot", f"{r.rootfs_base} + {r.rootfs_overlay}"))
    if r.shelf_from:
        rows.append(_shelf(r, up, r.shelf_from))
    if r.boot_dir:
        b = boards.get(r.board)
        verdict = boot.check(r.boot_dir, b.dbpart, b.name)
        rows += boot.stage(r.boot_dir, up, verdict, keep_rootfs=r.rootfs_overlay is None)
    (up / sd_layout.SYSTEM / "BOARD").write_text(r.board + "\n")
    rows.append((sd_layout.system("BOARD"), r.board))
    return rows


def seal(up: Path, name: str, board: str) -> str:
    """up_list.txt, MD5SUMS_up and install.sh over what is staged; the md5 list."""
    files = sorted(p for p in up.rglob("*") if p.is_file())
    rel = [p.relative_to(up).as_posix() for p in files]
    (up / "up_list.txt").write_text("".join(f + "\n" for f in rel))
    sums = "".join(f"{hashlib.md5(p.read_bytes()).hexdigest()}  {r}\n" for p, r in zip(files, rel, strict=True))
    (up / "MD5SUMS_up").write_text(sums)
    (up / "install.sh").write_text(install_sh.render(name, board))
    return sums


def stage(r: Request) -> tuple[Path, list[tuple[str, str]]]:
    """Stage <out>/<name>/up; raise CardError (leaving nothing behind) on a refusal or a MISSING/STALE row."""
    check_request(r)
    root = r.out / r.name
    up = root / "up"
    try:
        (up / sd_layout.SYSTEM).mkdir(parents=True)
        images, rows = _images(r, up)
        rows += _carts(r, up, images)
        rows += _extras(r, up)
        if problems := [f"{a} | {b}" for a, b in rows if b.startswith(BAD)]:
            raise CardError("\n".join(problems))
        seal(up, r.name, r.board)
    except (CardError, split_image.SplitError, OSError, SystemExit) as e:
        shutil.rmtree(root, ignore_errors=True)
        raise CardError(str(e)) from e
    return up, rows
