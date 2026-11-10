"""Stage the SyncTERM spike for the board's SD card (the lead installs it; nothing here touches the board).

    uv run --project fpga python prototypes/syncterm/stage_card.py

Reads the data disk docs/demo-syncterm.zmd and the lean board image
fpga/build/hcycles/split/carts_fpu/syncterm/cart.bin (make split-cart CART=syncterm ZM_ZMX=1, system table
1.17 as on the card), and writes prototypes/syncterm/card/up/ as prototypes/notepad_card/up/ is laid out:

    CARTS/tools/demo-syncterm.zmd                  the data disk, as is (KOS's desktop boots over it)
    KESTREL/progs/demo-syncterm/BOOT.WSM.zmd        the same disk + the program's lean image (ZX0), glass_shelf.programs
    KESTREL/progs/by-hash/<sha256 of the wasm>.rv32 the lean image for GEM run from a real floppy (stage_by_hash)
    shelf_line.txt, up_list.txt, MD5SUMS_up, install.sh
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FPGA = ROOT / "fpga"
sys.path.insert(0, str(FPGA / "tools"))
import shelf_meta  # noqa: E402
import split_image  # noqa: E402
import zmd_fat  # noqa: E402
from glass_zx0 import zx0pack  # noqa: E402

TAG = "syncterm"
SYSTEM_TABLE = 0x00010011  # 1.17, the card's system.rv32 (prototypes/notepad_card)
CART_BIN = FPGA / "build/hcycles/split/carts_fpu" / TAG / "cart.bin"
OUT = Path(__file__).resolve().parent / "card" / "up"


def pack(src: Path, dst: Path) -> bytes:
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([zx0pack(), src, dst], check=True, capture_output=True)
    return dst.read_bytes()


def main() -> None:
    disk = (ROOT / f"docs/demo-{TAG}.zmd").read_bytes()
    wasm = (ROOT / f"docs/demo-{TAG}.wasm").read_bytes()
    cart = CART_BIN.read_bytes()
    split_image.check_pair(SYSTEM_TABLE, cart)  # refuses an image the card's system cannot run
    files: dict[str, bytes] = {f"CARTS/tools/demo-{TAG}.zmd": disk}
    packed = pack(CART_BIN, OUT / "work" / "cart.zx0")
    files[f"KESTREL/progs/demo-{TAG}/BOOT.WSM.zmd"] = zmd_fat.fatten(disk, packed)
    files[f"KESTREL/progs/by-hash/{hashlib.sha256(wasm).hexdigest()}.rv32"] = packed
    (OUT / "work" / "cart.zx0").unlink()
    (OUT / "work").rmdir()
    for name, data in files.items():
        (OUT / name).parent.mkdir(parents=True, exist_ok=True)
        (OUT / name).write_bytes(data)
    row = list(next(r for r in shelf_meta.records([TAG]) if r[0].endswith(f"demo-{TAG}.zmd")))
    # shelf_meta finds no group or description for a C port (no scene header): say what the OSD should show.
    row[2] = row[2] or "Stephen Hurd / Synchronet"
    row[5] = row[5] or ("SyncTERM 1.9, the BBS terminal (GPLv2), as a spike: the desk mode (640x480), the network MOCKED by "
                        "a BBS inside the cart (telnet://fakebbs.zig). Alt+X then No quits")
    (OUT / "shelf_line.txt").write_text("\t".join(row) + "\n")
    (OUT / "up_list.txt").write_text("".join(f"{n}\n" for n in files))
    (OUT / "MD5SUMS_up").write_text("".join(f"{hashlib.md5(d).hexdigest()}  ./{n}\n" for n, d in files.items()))
    for n, d in files.items():
        print(f"{len(d):>9}  {hashlib.md5(d).hexdigest()}  {n}")
    print(f"cart.bin {len(cart)} B (lean, table {split_image.vtext(SYSTEM_TABLE)}); shelf: {row[0]} {row[1]}")


if __name__ == "__main__":
    main()
