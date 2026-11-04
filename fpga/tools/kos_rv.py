"""A floppy program's own board image (KOS F3b, docs/KOS_FAT.md): NAME.RV beside NAME.WSM, so a real
floppy runs its programs on the board with no SD card behind it (Matt, 31 Oct). The container is
glass/src/app_floppy_rv.zig's: "ZMRV", u32 LE version 1, the SHA-256 of the program's wasm (unpacked),
then the cart's board image ZX0-packed, as progs/by-hash holds it. The image is checked against the
system it is for (split_image.check_pair, the ABI) before it is written; glass checks it again
against the system it runs, and the hash against the .WSM beside it.

    python3 fpga/tools/kos_rv.py --fw-dir DIR --system SYS.bin rv CART OUT.RV
    python3 fpga/tools/kos_rv.py --fw-dir DIR --system SYS.bin floppy OUT.st CART [CART...]

`floppy` writes an Atari 720 KB FAT12 image (tools/kos_fat_fixture.py's writer) holding NAME.WSM
(docs/demo-<cart>.wasm) and NAME.RV for each cart, NAME being the cart's tag in 8.3 upper case.
"""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.append(str(ROOT / "tools"))  # last: fpga/tools wins a name both have
import split_image  # after the path insert
from glass_shelf import Images
from glass_zx0 import zx0pack
from kos_fat_fixture import Image

MAGIC = b"ZMRV"
VERSION = 1


def container(wasm: bytes, packed_image: bytes) -> bytes:
    return MAGIC + VERSION.to_bytes(4, "little") + hashlib.sha256(wasm).digest() + packed_image


def rv_of(cart: str, images: Images) -> bytes:
    """NAME.RV for `cart`: its board image (refused when the system would refuse it) in the container."""
    if why := images.problem(cart):
        raise SystemExit(f"kos_rv: {cart}: {why}")
    wasm = (ROOT / "docs" / f"demo-{cart}.wasm").read_bytes()
    with tempfile.TemporaryDirectory() as t:
        subprocess.run([zx0pack(), images.path(cart), Path(t) / "img.zx0"], check=True, capture_output=True)
        return container(wasm, (Path(t) / "img.zx0").read_bytes())


def name83(cart: str) -> str:
    base = cart.upper().replace("-", "_")[:8]
    if not base.replace("_", "").isalnum():
        raise SystemExit(f"kos_rv: {cart}: no 8.3 name")
    return base


def floppy(out: Path, carts: list[str], images: Images) -> None:
    names = [name83(c) for c in carts]
    if len(set(names)) != len(names):
        raise SystemExit(f"kos_rv: two carts share an 8.3 name: {names}")
    img = Image("KOS PROGS")
    for cart, n in zip(carts, names, strict=True):
        img.write(f"{n}.WSM", (ROOT / "docs" / f"demo-{cart}.wasm").read_bytes())
        img.write(f"{n}.RV", rv_of(cart, images))
    out.write_bytes(img.bytes())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--fw-dir", type=Path, required=True, help="the board images (<dir>/<cart>/cart.bin)")
    ap.add_argument("--system", type=Path, required=True, help="the system image the carts are for")
    sub = ap.add_subparsers(dest="cmd", required=True)
    one = sub.add_parser("rv")
    one.add_argument("cart")
    one.add_argument("out", type=Path)
    many = sub.add_parser("floppy")
    many.add_argument("out", type=Path)
    many.add_argument("carts", nargs="+")
    a = ap.parse_args()
    images = Images(a.fw_dir, split_image.table_version(a.system.read_bytes()))
    if a.cmd == "rv":
        a.out.write_bytes(rv_of(a.cart, images))
    else:
        floppy(a.out, a.carts, images)
    return 0


if __name__ == "__main__":
    sys.exit(main())
