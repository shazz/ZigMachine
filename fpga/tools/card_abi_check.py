"""Which lean carts of a staged SD card a system table runs (decisions.md 2026-10-15: the same major, the
cart's minor at most the system's): every board image on the card (CARTS/**/*.zmd's CART.RV32,
KESTREL/**/*.rv32 and *.zmd), ZX0-unpacked, its header read, held against the version given. A monolithic
image (no cart header) needs no system and is counted apart. Used to say a system bump keeps a card's
carts running (KOS GEMDOS phase 2: 1.9 -> 1.10).

    uv run python fpga/tools/card_abi_check.py CARD_DIR [--system 1.10]
"""

from __future__ import annotations

import argparse
import struct
import subprocess
import tempfile
from collections import Counter
from pathlib import Path

import split_image
import zmd_fat
from glass_zx0 import zx0unpack


def unpack(packed: bytes, work: Path) -> bytes:
    src, dst = work / "in.zx0", work / "out.bin"
    src.write_bytes(packed)
    subprocess.run([str(zx0unpack()), str(src), str(dst)], check=True, capture_output=True)
    return dst.read_bytes()


def board_images(card: Path):  # noqa: ANN201 -- a generator of (path, packed bytes)
    for p in sorted(card.rglob("*")):
        if p.suffix == ".rv32" and p.name != "system.rv32":
            yield p, p.read_bytes()
        elif p.suffix == ".zmd":
            img = p.read_bytes()
            try:
                found = zmd_fat.files(img)
            except (ValueError, IndexError, struct.error):
                continue  # not a ZigMachine disk
            for name, start, length, _ in found:
                if name.encode() == zmd_fat.NAME:
                    yield p, img[start : start + length]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("card", type=Path)
    ap.add_argument("--system", default="1.10")
    a = ap.parse_args()
    major, minor = (int(x) for x in a.system.split("."))
    have = major << 16 | minor
    seen: Counter[str] = Counter()
    refused = []
    with tempfile.TemporaryDirectory() as tmp:
        for path, packed in board_images(a.card):
            try:
                img = unpack(packed, Path(tmp))
            except subprocess.CalledProcessError:
                img = packed
            if not split_image.is_cart(img):
                seen["monolithic"] += 1
                continue
            need = split_image.cart_header(img).version
            seen[split_image.vtext(need)] += 1
            if not split_image.abi_ok(need, have):
                refused.append(f"{path.relative_to(a.card)} needs {split_image.vtext(need)}")
    print(f"{a.card}: board images by table version: {dict(sorted(seen.items()))}")
    print(f"system {a.system} refuses {len(refused)}" + "".join(f"\n  {r}" for r in refused))
    raise SystemExit(1 if refused else 0)


if __name__ == "__main__":
    main()
