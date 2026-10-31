"""KOS's FAT reader (rom/kos/fat.zig, docs/KOS_FAT.md) against mtools, the independent oracle, on
images mkfs.fat makes: FAT12 1.44 MB, an Atari 720 KB floppy (TOS's BPB: no 55 AA, a BRA.S at 0),
FAT16 and FAT32, with folders, a fragmented file, a deleted file and a long name (its 8.3 alias
is what GEMDOS shows). Every file's path (8.3, as mshortname gives it), size and bytes must match;
a corrupt BPB must be refused. Skipped where mkfs.fat or mtools are missing.
"""

from __future__ import annotations

import os
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
class KosFat(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="kos_fat_"))
        cls.dump = cls.tmp / "fat_dump"
        subprocess.run([ZIG, "build-exe", "-ODebug", str(ROOT / "rom/kos/fat_dump.zig"), f"-femit-bin={cls.dump}"],
                       check=True, cwd=cls.tmp, capture_output=True)  # fmt: skip

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp)

    def image(self, name: str, kb: int, *mkfs: str) -> Path:
        img = self.tmp / name
        img.unlink(missing_ok=True)
        subprocess.run(["mkfs.fat", *mkfs, "-C", str(img), str(kb)], check=True, capture_output=True)
        files = {"A.BIN": os.urandom(3000), "B.BIN": os.urandom(700), "C.BIN": os.urandom(9000)}
        for n, data in files.items():
            (self.tmp / n).write_bytes(data)
        mt(img, "mmd", "::GAMES")
        mt(img, "mmd", "::GAMES/LEVELS")
        mt(img, "mcopy", str(self.tmp / "A.BIN"), "::A.BIN")
        mt(img, "mcopy", str(self.tmp / "B.BIN"), "::GAMES/B.BIN")
        mt(img, "mdel", "::A.BIN")  # a hole: C.BIN fills it, then goes on after B.BIN (fragmented)
        mt(img, "mcopy", str(self.tmp / "C.BIN"), "::GAMES/LEVELS/C.BIN")
        mt(img, "mcopy", str(self.tmp / "B.BIN"), "::A long name.txt")
        return img

    def oracle(self, img: Path) -> set[tuple[str, int, str]]:
        out = set()
        for path in mt(img, "mdir", "-/", "-b", "::").decode().splitlines():
            if path.endswith("/"):
                continue
            short = mt(img, "mshortname", path).decode().strip().removeprefix("::/")
            data = mt(img, "mtype", path)
            parent = path.removeprefix("::/").rpartition("/")[0]
            full = (parent.upper() + "/" if parent else "") + short.rpartition("/")[2]
            out.add((full, len(data), fnv(data)))
        return out

    def reader(self, img: Path) -> tuple[str, set[tuple[str, int, str]]]:
        p = subprocess.run([str(self.dump), str(img)], capture_output=True, text=True)
        lines = p.stdout.splitlines()
        files = {(f[0], int(f[1]), f[3]) for f in (ln.split("\t") for ln in lines[1:]) if not f[0].endswith("/")}
        return lines[0], files

    def check(self, img: Path, kind: str) -> None:
        got_kind, got = self.reader(img)
        self.assertEqual(kind, got_kind)
        self.assertEqual(self.oracle(img), got)
        self.assertIn(("ALONGN~1.TXT", 700, fnv((self.tmp / "B.BIN").read_bytes())), got)

    def test_fat12_floppy(self) -> None:
        self.check(self.image("f12.img", 1440), "fat12")

    def test_atari_720k_floppy(self) -> None:
        img = self.image("st.img", 720, "-S", "512", "-s", "2", "-f", "2", "-r", "112", "-h", "0")
        b = bytearray(img.read_bytes())
        b[0:2], b[510:512] = b"\x60\x38", b"\x00\x00"  # TOS: a BRA.S, and no 55 AA
        img.write_bytes(b)
        self.check(img, "fat12")

    def test_fat16(self) -> None:
        self.check(self.image("f16.img", 16384, "-F", "16"), "fat16")

    def test_fat32(self) -> None:
        self.check(self.image("f32.img", 65536, "-F", "32", "-s", "1"), "fat32")

    def test_a_corrupt_bpb_is_refused(self) -> None:
        img = self.image("bad.img", 1440)
        b = bytearray(img.read_bytes())
        b[13] = 3  # sectors a cluster: not a power of two
        img.write_bytes(b)
        self.assertEqual("error Corrupt", self.reader(img)[0])


if __name__ == "__main__":
    unittest.main()
