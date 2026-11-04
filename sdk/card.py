"""Stage an SDK cart for the KESTREL SD card (docs/SDK.md, "Put it on the board").

    python3 sdk/card.py --tag hello --cart zig-out/board/hello/cart.bin --disk zig-out/demo-hello.zmd \
        --zx0pack zig-out/bin/zx0pack --out zig-out/sd [--card <release>/card] [--release <release>/RELEASE.txt]

The board runs the card's system.rv32 (prebuilt in the SDK release) and, from each fat disk, a
lean cart image (`make -C fpga split-cart`). This writes ONE fat disk, the cart's .zmd with its
cart.bin ZX0-packed as one more FAT file (fpga/tools/zmd_fat.py, as glass_shelf.py does for the
shelf), at <out>/zigmachine/<category>/demo-<tag>.zmd, and its line in <out>/zigmachine/shelf.txt.
With --card, <out> starts as a copy of the release's card, so it is the whole card to copy over.
With --release, the cart's system-table version is checked against the release's system image
(split_image.check_pair): a cart the card's system would refuse is refused here, not on the board.

Needs `make -C fpga memmap` (fpga/gen/): `make board` runs it first.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "fpga/tools"))
sys.path.insert(0, str(ROOT / "fpga/gen"))
import shelf_category  # after the path insert
import split_image
import zmd_fat

SHELF = "shelf.txt"
SHELF_HEAD = "# shelf.txt: FILE TITLE GROUP YEAR TYPE DESCRIPTION, tab-separated.\n"


def ascii_text(s: str) -> str:
    """The OSD draws the ST's 8-bit font: fold to ASCII, no tabs (shelf_meta.ascii_text's rule)."""
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return " ".join(s.replace("\t", " ").split())


def release_version(release: Path) -> int:
    """The system-table version the release's system.rv32 serves (RELEASE.txt `sys_table`)."""
    for line in release.read_text().splitlines():
        key, _, value = line.partition("=")
        if key.strip() == "sys_table":
            return int(value.strip(), 0)
    raise SystemExit(f"card: {release} names no sys_table")


def shelf_line(rel: str, a: argparse.Namespace) -> str:
    fields = [rel, a.title or a.tag.upper(), a.group, a.year, "zigmachine", a.desc]
    return "\t".join(ascii_text(f) for f in fields) + "\n"


def write_shelf(zm: Path, rel: str, line: str) -> None:
    """Our line replaces any older one for the same disk; every other line is kept."""
    path = zm / SHELF
    old = path.read_text().splitlines(keepends=True) if path.exists() else [SHELF_HEAD]
    keep = [ln for ln in old if ln.split("\t", 1)[0] != rel]
    path.write_text("".join(keep) + line)


def stage(a: argparse.Namespace) -> list[str]:
    if a.category not in shelf_category.CATEGORIES:
        raise SystemExit(f"card: --category must be one of {', '.join(shelf_category.CATEGORIES)}")
    cart = a.cart.read_bytes()
    if a.release:
        try:
            split_image.check_pair(release_version(a.release), cart)
        except split_image.SplitError as e:
            raise SystemExit(f"card: {a.cart}: {e}; rebuild against this SDK release") from e
    if a.card:
        shutil.copytree(a.card, a.out, dirs_exist_ok=True)
    zm = a.out / "zigmachine"
    rel = f"{a.category}/demo-{a.tag}.zmd"
    packed = a.out / f"{a.tag}.rv32.zx0"
    a.out.mkdir(parents=True, exist_ok=True)
    subprocess.run([a.zx0pack, a.cart, packed], check=True, capture_output=True)
    disk = zm / rel
    disk.parent.mkdir(parents=True, exist_ok=True)
    disk.write_bytes(zmd_fat.fatten(a.disk.read_bytes(), packed.read_bytes()))
    packed.unlink()
    write_shelf(zm, rel, shelf_line(rel, a))
    return [f"zigmachine/{rel}", f"zigmachine/{SHELF}"]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--tag", required=True)
    p.add_argument("--cart", type=Path, required=True, help="the lean cart image (split-cart's cart.bin)")
    p.add_argument("--disk", type=Path, required=True, help="the cart's .zmd (make floppy)")
    p.add_argument("--zx0pack", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--card", type=Path, help="the release's card directory: copied into --out first")
    p.add_argument("--release", type=Path, help="the release's RELEASE.txt: check the cart's system table")
    p.add_argument("--category", default="demos")
    p.add_argument("--title", default="")
    p.add_argument("--group", default="")
    p.add_argument("--year", default="")
    p.add_argument("--desc", default="")
    a = p.parse_args()
    for rel in stage(a):
        f = a.out / rel
        print(f"{hashlib.md5(f.read_bytes()).hexdigest()}  {rel}")
    print(f"card: copy the contents of {a.out} onto the card's first (FAT32) partition")


if __name__ == "__main__":
    main()
