#!/usr/bin/env python3
"""A FAT12 floppy image for KOS's desktop proofs (docs/KOS_FAT.md): an Atari 720 KB layout (TOS's
BPB: 9 sectors, 2 per cluster, 112 root entries, a BRA.S at 0 and no 55 AA) made by mkfs.fat and
mtools, byte for byte the same on every run (--invariant, fixed file times). The root holds a
program (DEMO.WSM: any cart's wasm), two data files and two folders, one nested.

    python3 tools/kos_fat_fixture.py OUT.st [CART.wasm]
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAMP = 1_793_000_000  # 2026-10-26: every file's time, so the image never changes


def build(out: Path, cart: Path) -> None:
    out.unlink(missing_ok=True)
    subprocess.run(["mkfs.fat", "--invariant", "-i", "4b4f5331", "-n", "KOS DISK", "-S", "512", "-s", "2", "-f", "2",
                    "-r", "112", "-h", "0", "-C", str(out), "720"], check=True, capture_output=True)  # fmt: skip
    with tempfile.TemporaryDirectory() as t:
        files = {"DEMO.WSM": cart.read_bytes(), "README.TXT": b"KOS reads real floppies.\r\n" * 40,
                 "PIC.PI1": bytes(range(256)) * 125, "SAVE.DAT": b"\x01\x02" * 900, "LEVEL1.MAP": b"#" * 5000}  # fmt: skip
        for name, data in files.items():
            p = Path(t) / name
            p.write_bytes(data)
            os.utime(p, (STAMP, STAMP))
        env = {**os.environ, "MTOOLS_SKIP_CHECK": "1", "SOURCE_DATE_EPOCH": str(STAMP)}
        def m(*a: str) -> None:
            subprocess.run([a[0], "-i", str(out), *a[1:]], check=True, capture_output=True, env=env)
        for name in ("DEMO.WSM", "README.TXT", "PIC.PI1"):
            m("mcopy", "-m", str(Path(t) / name), f"::{name}")
        m("mmd", "::GAMES")
        m("mmd", "::GAMES/LEVELS")
        m("mcopy", "-m", str(Path(t) / "SAVE.DAT"), "::GAMES/SAVE.DAT")
        m("mcopy", "-m", str(Path(t) / "LEVEL1.MAP"), "::GAMES/LEVELS/LEVEL1.MAP")
    b = bytearray(out.read_bytes())
    b[0:2], b[510:512] = b"\x60\x38", b"\x00\x00"  # TOS: a BRA.S, no 55 AA
    out.write_bytes(b)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    build(Path(sys.argv[1]), Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "docs/demo-tutorial.wasm")
