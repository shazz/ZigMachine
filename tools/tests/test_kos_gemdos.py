"""KOS GEMDOS (rom/kos/gemdos.zig, docs/KOS_GEMDOS.md) against mtools, the independent oracle, on cards
mkfs.fat makes: FAT16 and FAT32 (the board's SD card), laid out as the board's (boot files and KESTREL/ at
the root, C:\\ = HD/), with folders three deep, a fragmented file, a long name (GEMDOS shows its 8.3
alias), a folder of 150 files (many directory clusters) and a 300 KB file (merged requests). Every file
under HD/ read through Fsfirst / Fsnext / Fopen / Fread (rom/kos/gemdos_dump.zig), in one big read and
in stdio's 1 KB pieces, must match mtools' bytes; nothing above HD/ may show; a card with no HD/ has no
C:. Skipped where mkfs.fat or mtools are missing.
"""

from __future__ import annotations

import os
import random
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ZIG = shutil.which("zig") or str(Path.home() / ".local/zig/0.16.0/zig")
TOOLS = all(shutil.which(t) for t in ("mkfs.fat", "mcopy", "mdir", "mtype", "mshortname", "mdel", "mmd"))


def fnv(b: bytes) -> str:
    h = 0x811C9DC5
    for x in b:
        h = ((h ^ x) * 0x01000193) & 0xFFFFFFFF
    return f"{h:08x}"


def mt(img: Path, *args: str) -> bytes:
    return subprocess.run([args[0], "-i", str(img), *args[1:]], check=True, capture_output=True).stdout


@unittest.skipUnless(TOOLS, "mkfs.fat / mtools not installed")
class KosGemdos(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="kos_gemdos_"))
        cls.dump = cls.tmp / "gemdos_dump"
        subprocess.run([ZIG, "build-exe", "-ODebug", str(ROOT / "rom/kos/gemdos_dump.zig"), f"-femit-bin={cls.dump}"],
                       check=True, cwd=cls.tmp, capture_output=True)  # fmt: skip

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp)

    def put(self, img: Path, name: str, data: bytes, to: str) -> None:
        src = self.tmp / name
        src.write_bytes(data)
        mt(img, "mcopy", str(src), to)

    def card(self, name: str, kb: int, *mkfs: str, hd: bool = True) -> Path:
        img = self.tmp / name
        img.unlink(missing_ok=True)
        subprocess.run(["mkfs.fat", *mkfs, "-C", str(img), str(kb)], check=True, capture_output=True)
        rnd = random.Random(kb)
        self.put(img, "boot", rnd.randbytes(9000), "::BOOT.BIN")
        mt(img, "mmd", "::KESTREL")
        self.put(img, "sys", rnd.randbytes(4000), "::KESTREL/SYSTEM.RV3")
        if not hd:
            return img
        for d in ("HD", "HD/PICTURES", "HD/PICTURES/PLASMA", "HD/MANY"):
            mt(img, "mmd", f"::{d}")
        self.put(img, "a", rnd.randbytes(5000), "::HD/A.BIN")
        self.put(img, "pi1", rnd.randbytes(32034), "::HD/PICTURES/PLASMA/ZIGPLASM.PI1")
        mt(img, "mdel", "::HD/A.BIN")  # a hole: BIG.DAT fills it, then goes on after it (fragmented)
        self.put(img, "big", rnd.randbytes(300_000), "::HD/PICTURES/BIG.DAT")
        self.put(img, "lfn", rnd.randbytes(700), "::HD/A long name.txt")
        for k in range(150):
            self.put(img, f"m{k}", rnd.randbytes(k * 37), f"::HD/MANY/F{k:03d}.DAT")
        return img

    def oracle(self, img: Path) -> set[tuple[str, int, str]]:
        out = set()
        for path in mt(img, "mdir", "-/", "-b", "::/HD").decode().splitlines():
            if path.endswith("/"):
                continue
            short = mt(img, "mshortname", path).decode().strip()
            data = mt(img, "mtype", path)
            parent = path.removeprefix("::/HD/").rpartition("/")[0]
            full = (parent.upper().replace("/", "\\") + "\\" if parent else "") + short.rpartition("/")[2]
            out.add((full, len(data), fnv(data)))
        return out

    def gemdos(self, img: Path, chunk: int) -> tuple[set[tuple[str, int, str]], int]:
        p = subprocess.run([str(self.dump), str(img), str(chunk)], capture_output=True, text=True)
        lines = p.stdout.splitlines()
        self.assertEqual(0, p.returncode, lines[:1])
        files = {(f[0], int(f[1]), f[2]) for f in (ln.split("\t") for ln in lines[:-1]) if not f[0].endswith("\\")}
        return files, int(lines[-1].split()[1])

    def check(self, img: Path) -> None:
        want = self.oracle(img)
        self.assertEqual(150 + 3, len(want))
        whole, trips_whole = self.gemdos(img, 1 << 20)
        small, trips_small = self.gemdos(img, 1024)
        self.assertEqual(want, whole)
        self.assertEqual(want, small)
        self.assertIn("ALONGN~1.TXT", {f[0] for f in whole})
        self.assertFalse(any("SYSTEM" in f[0] or "BOOT" in f[0] for f in whole))  # nothing above HD/
        self.assertLess(trips_whole, trips_small)  # whole reads go straight to the buffer, merged

    def test_fat16_card(self) -> None:
        self.check(self.card("f16.img", 16384, "-F", "16"))

    def test_fat32_card(self) -> None:
        self.check(self.card("f32.img", 65536, "-F", "32", "-s", "1"))

    def test_fat32_card_with_big_clusters(self) -> None:
        self.check(self.card("f32b.img", 140000, "-F", "32", "-s", "4"))  # FAT32 needs >= 65525 clusters

    def test_a_card_with_no_hd_folder_has_no_c(self) -> None:
        img = self.card("bare.img", 65536, "-F", "32", "-s", "1", hd=False)
        p = subprocess.run([str(self.dump), str(img), "1024"], capture_output=True, text=True)
        self.assertEqual((1, "no C:"), (p.returncode, p.stdout.strip()))


if __name__ == "__main__":
    unittest.main()
