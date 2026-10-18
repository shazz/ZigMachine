"""Native KESTREL carts (cycles/native/native.mk, decisions.md 2026-10-17): lean cart images
written for ZIGGY directly (C or assembly), not compiled from wasm. Board only.

    uv run python tools/native_cart.py check build/hcycles/split/native_fpu/hello/cart.bin
    uv run python tools/native_cart.py disk build/.../hello/cart.bin build/.../hello/disk.zmd --title "HELLO (C)"

check: what glass (glass/src/system.zig) and the system (cycles/bsys.c) will hold the image
to, before a card carries it: the ZMCA header, a table version this tree's system serves,
its header size and page count, a .bss end past the image and before the pictures, a tag.

disk: the shelf disk glass_sd.py fattens with the cart (glass_shelf.py takes <fw-dir>/<tag>/
disk.zmd before docs/demo-<tag>.zmd): a v1 disk whose boot cart is cycles/native/
browser_stub.c, so a browser that mounts it says "KESTREL only" instead of failing.
"""

from __future__ import annotations

import argparse
import struct
import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(ROOT / "tools"))
import mkdisk  # after the path inserts: the shelf's own disk writer
import split_image
import sys_abi
from sys_abi_manifest import parse

HDR_BYTES, PAGES_AT, HDR_SIZE_AT, TAG_AT = 96, 20, 8, 80
STUB = FPGA / "cycles/native/browser_stub.c"
ZIG = Path.home() / ".local/zig/0.16.0/zig"
SHARED_PAGES = 112  # machine/sdk/memmap.zig, as apps/c/build.sh's MEM


def system_version() -> int:
    major, minor = parse(sys_abi.MANIFEST.read_text()).version
    return major << 16 | minor


def check(image: bytes, have: int | None = None) -> str:
    """The cart's tag if this tree's system runs it; split_image.SplitError naming why not."""
    split_image.check_pair(system_version() if have is None else have, image)
    if len(image) < HDR_BYTES:
        raise split_image.SplitError(f"{len(image)} B: shorter than the {HDR_BYTES} B header")
    size, pages = struct.unpack_from("<I", image, HDR_SIZE_AT)[0], struct.unpack_from("<I", image, PAGES_AT)[0]
    if size != HDR_BYTES or pages != SHARED_PAGES:
        raise split_image.SplitError(f"header says {size} B / {pages} pages, the system {HDR_BYTES} / {SHARED_PAGES}")
    tag = image[TAG_AT : TAG_AT + 16].split(b"\0")[0].decode("ascii", "replace")
    if not tag:
        raise split_image.SplitError("the header names no cart (empty tag)")
    return tag


def stub_wasm(out: Path) -> bytes:
    """browser_stub.c built as apps/c/build.sh builds a C cart (the machine's one memory)."""
    mem = SHARED_PAGES * 65536
    flags = ["-Wl,--no-entry", "-Wl,--import-memory", f"-Wl,--initial-memory={mem}", f"-Wl,--max-memory={mem}",
             "-Wl,--global-base=1048576", "-Wl,--strip-debug"]  # fmt: skip
    subprocess.run([str(ZIG), "cc", "-target", "wasm32-freestanding", "-O2", "-g0", "-ffreestanding", "-fno-builtin",
                    "-nostdlib", *flags, "-o", str(out), str(STUB)], check=True)  # fmt: skip
    return out.read_bytes()


def disk(cart: Path, out: Path, title: str) -> None:
    tag = check(cart.read_bytes())
    wasm = stub_wasm(out.with_suffix(".stub.wasm"))
    desc = f"Native ZIGGY cart '{tag}': runs on KESTREL (the FPGA console) only"
    out.write_bytes(mkdisk.build(wasm, title, "ZigMachine", desc, 0))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("kind", choices=["check", "disk"])
    ap.add_argument("cart", type=Path, help="the native cart.bin")
    ap.add_argument("out", type=Path, nargs="?", help="disk: the .zmd to write")
    ap.add_argument("--title", default="", help="disk: the title the menu shows")
    a = ap.parse_args()
    try:
        if a.kind == "check":
            print(f"{a.cart}: cart '{check(a.cart.read_bytes())}', {a.cart.stat().st_size} B, header ok")
        elif a.out is None or not a.title:
            ap.error("disk needs OUT and --title")
        else:
            disk(a.cart, a.out, a.title)
            print(f"{a.out}: {a.out.stat().st_size} B, board only")
    except split_image.SplitError as e:
        sys.exit(f"native_cart: {a.cart}: {e}")


if __name__ == "__main__":
    main()
