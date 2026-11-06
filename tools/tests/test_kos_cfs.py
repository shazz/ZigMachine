"""KFS, KOS GEMDOS's C: image writer (rom/kos/kfs*.zig, docs/KOS_GEMDOS.md §7), against mtools and
fsck.fat, the independent oracles, on FAT16 and FAT32 cards mkfs.fat makes, laid out as the board's (C:\\ =
HD/). Every case ends with `fsck.fat -n` clean. Cases: create, grow across clusters (several requests),
overwrite (the old clusters come back), delete, rename (in a folder, across folders, a folder moved: its
`..` follows), mkdir / rmdir, a full disk (the old file survives), folders with long names beside ours
(untouched; one deleted by its 8.3 alias takes its long name along), refused paths, and a crash: the
save cut after a sector write (every fifth, and each of the commit's) leaves the neighbours intact, the file old or new (or the
new one still under its temporary name), and a disk fsck.fat repairs to clean with nothing lost.
Skipped where mkfs.fat, mtools or fsck.fat are missing.
"""

from __future__ import annotations

import random
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ZIG = shutil.which("zig") or str(Path.home() / ".local/zig/0.16.0/zig")
TOOLS = all(shutil.which(t) for t in ("mkfs.fat", "fsck.fat", "mcopy", "mdir", "mtype", "mmd", "mattrib"))
EWRITF, EFILNF, EPTHNF, EACCDN = -10, -33, -34, -36
CARDS = {"fat16": (16384, ["-F", "16"]), "fat32": (65536, ["-F", "32", "-s", "1"])}


def mt(img: Path, *args: str, check: bool = True) -> bytes:
    return subprocess.run([args[0], "-i", str(img), *args[1:]], check=check, capture_output=True).stdout


@unittest.skipUnless(TOOLS, "mkfs.fat / fsck.fat / mtools not installed")
class KosCfs(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="kos_cfs_"))
        cls.tool = cls.tmp / "kfs_tool"
        subprocess.run([ZIG, "build-exe", "-ODebug", str(ROOT / "rom/kos/kfs_tool.zig"), f"-femit-bin={cls.tool}"],
                       check=True, cwd=cls.tmp, capture_output=True)  # fmt: skip

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp)

    def kfs(self, img: Path, *args: str, cut: int | None = None) -> tuple[int, int]:
        pre = ["--cut", str(cut)] if cut is not None else []
        p = subprocess.run([str(self.tool), str(img), *pre, *args], capture_output=True, text=True, check=True)
        code, writes = p.stdout.split()
        return int(code), int(writes)

    def file(self, name: str, data: bytes) -> Path:
        f = self.tmp / name
        f.write_bytes(data)
        return f

    def card(self, kind: str, name: str = "c.img", kb: int | None = None) -> Path:
        size, mkfs = CARDS[kind]
        img = self.tmp / f"{kind}-{name}"
        img.unlink(missing_ok=True)
        subprocess.run(["mkfs.fat", *mkfs, "-C", str(img), str(kb or size)], check=True, capture_output=True)
        for d in ("KESTREL", "HD", "HD/PICTURES", "HD/LONG"):
            mt(img, "mmd", f"::{d}")
        mt(img, "mcopy", str(self.file("sys", b"S" * 4000)), "::KESTREL/SYSTEM.RV3")
        mt(img, "mcopy", str(self.file("n", b"neighbour" * 300)), "::HD/PICTURES/OLD.PI1")
        mt(img, "mcopy", str(self.file("l1", b"long one" * 500)), "::HD/LONG/A long picture name.pi1")
        mt(img, "mcopy", str(self.file("l2", b"long two" * 90)), "::HD/LONG/Another long name.txt")
        return img

    def clean(self, img: Path) -> None:
        p = subprocess.run(["fsck.fat", "-n", str(img)], check=False, capture_output=True, text=True)
        self.assertEqual(0, p.returncode, p.stdout + p.stderr)

    def free(self, img: Path) -> int:
        line = mt(img, "mdir", "::/").decode().strip().splitlines()[-1]
        return int(line.split("bytes free")[0].replace(" ", "").replace("\u202f", ""))

    def save(self, img: Path, path: str, data: bytes) -> int:
        return self.kfs(img, "save", path, str(self.file("data", data)))[0]

    def test_create_grow_overwrite_delete_match_mtools(self) -> None:
        rnd = random.Random(1)
        for kind in CARDS:
            with self.subTest(kind):
                img = self.card(kind)
                base = self.free(img)
                small, big = rnd.randbytes(3000), rnd.randbytes(150_000)  # big: 5 requests, many clusters
                self.assertEqual(0, self.save(img, "PICTURES\\NEW.PI1", small))
                self.assertEqual(small, mt(img, "mtype", "::HD/PICTURES/NEW.PI1"))
                self.clean(img)
                self.assertEqual(0, self.save(img, "PICTURES\\NEW.PI1", big))
                self.assertEqual(big, mt(img, "mtype", "::HD/PICTURES/NEW.PI1"))
                self.clean(img)
                self.assertEqual(0, self.save(img, "PICTURES\\NEW.PI1", small))  # the big one's clusters freed
                self.assertEqual(small, mt(img, "mtype", "::HD/PICTURES/NEW.PI1"))
                self.assertEqual(0, self.save(img, "EMPTY.DAT", b""))
                self.assertEqual(b"", mt(img, "mtype", "::HD/EMPTY.DAT"))
                self.clean(img)
                self.assertEqual(0, self.kfs(img, "delete", "PICTURES\\NEW.PI1")[0])
                self.assertEqual(0, self.kfs(img, "delete", "EMPTY.DAT")[0])
                self.assertEqual(EFILNF, self.kfs(img, "delete", "PICTURES\\NEW.PI1")[0])
                self.assertEqual(base, self.free(img))  # every cluster came back
                self.assertEqual(b"neighbour" * 300, mt(img, "mtype", "::HD/PICTURES/OLD.PI1"))
                self.clean(img)

    def test_rename_mkdir_rmdir_attributes(self) -> None:
        for kind in CARDS:
            with self.subTest(kind):
                img = self.card(kind)
                self.assertEqual(0, self.kfs(img, "mkdir", "NEW")[0])
                self.assertEqual(EACCDN, self.kfs(img, "mkdir", "NEW")[0])
                self.assertEqual(EPTHNF, self.kfs(img, "mkdir", "NOPE\\SUB")[0])
                self.assertEqual(0, self.kfs(img, "mkdir", "NEW\\SUB")[0])
                self.clean(img)
                self.assertEqual(0, self.kfs(img, "rename", "PICTURES\\OLD.PI1", "PICTURES\\RENAMED.PI1")[0])
                self.assertEqual(0, self.kfs(img, "rename", "PICTURES\\RENAMED.PI1", "NEW\\SUB\\MOVED.PI1")[0])
                self.assertEqual(b"neighbour" * 300, mt(img, "mtype", "::HD/NEW/SUB/MOVED.PI1"))
                self.assertEqual(EACCDN, self.kfs(img, "rename", "NEW", "NEW\\SUB\\INSIDE")[0])  # into itself
                self.assertEqual(0, self.kfs(img, "rename", "NEW\\SUB", "PICTURES\\SUB")[0])  # a folder moves
                self.assertEqual(b"neighbour" * 300, mt(img, "mtype", "::HD/PICTURES/SUB/MOVED.PI1"))
                self.clean(img)  # fsck checks the moved folder's ".."
                self.assertEqual(EACCDN, self.kfs(img, "rmdir", "PICTURES\\SUB")[0])  # not empty
                self.assertEqual(EPTHNF, self.kfs(img, "rmdir", "PICTURES\\SUB\\MOVED.PI1")[0])  # a file
                self.assertEqual(1 | 0x20, self.kfs(img, "setattr", "PICTURES\\SUB\\MOVED.PI1", "0x21")[0])
                self.assertIn(b"R", mt(img, "mattrib", "::HD/PICTURES/SUB/MOVED.PI1").split(b":")[0])
                self.assertEqual(EACCDN, self.kfs(img, "delete", "PICTURES\\SUB\\MOVED.PI1")[0])  # read-only
                self.assertEqual(EACCDN, self.save(img, "PICTURES\\SUB\\MOVED.PI1", b"x"))
                self.assertEqual(0x20, self.kfs(img, "setattr", "PICTURES\\SUB\\MOVED.PI1", "0x20")[0])
                self.assertEqual(0, self.kfs(img, "delete", "PICTURES\\SUB\\MOVED.PI1")[0])
                self.assertEqual(0, self.kfs(img, "rmdir", "PICTURES\\SUB")[0])
                self.assertEqual(0, self.kfs(img, "rmdir", "NEW")[0])
                self.clean(img)

    def test_long_name_neighbours_are_untouched_and_go_with_their_alias(self) -> None:
        for kind in CARDS:
            with self.subTest(kind):
                img = self.card(kind)
                for k in range(20):  # the LONG folder grows past a cluster
                    self.assertEqual(0, self.save(img, f"LONG\\F{k:02d}.DAT", bytes([k]) * 700))
                self.assertEqual(b"long one" * 500, mt(img, "mtype", "::HD/LONG/A long picture name.pi1"))
                self.assertEqual(0, self.kfs(img, "rename", "LONG\\F03.DAT", "LONG\\G03.DAT")[0])
                self.assertEqual(0, self.kfs(img, "delete", "LONG\\ALONGP~1.PI1")[0])  # the alias GEMDOS shows
                self.clean(img)  # no orphaned long-name slots
                names = mt(img, "mdir", "-b", "::/HD/LONG").decode()
                self.assertNotIn("A long picture", names)
                self.assertIn("Another long name.txt", names)
                self.assertEqual(b"long two" * 90, mt(img, "mtype", "::HD/LONG/Another long name.txt"))
                self.assertEqual(bytes([3]) * 700, mt(img, "mtype", "::HD/LONG/G03.DAT"))

    def test_a_full_disk_refuses_the_save_and_keeps_the_old_file(self) -> None:
        for kind in CARDS:
            with self.subTest(kind):
                img = self.card(kind, "full.img", kb={"fat16": 9000, "fat32": 34000}[kind])
                old = b"old" * 1000
                self.assertEqual(0, self.save(img, "PICTURES\\KEEP.PI1", old))
                filler = random.Random(2).randbytes(self.free(img) - 20_000)
                self.assertEqual(0, self.save(img, "FILL.DAT", filler))
                self.assertEqual(EWRITF, self.save(img, "PICTURES\\KEEP.PI1", random.Random(3).randbytes(64_000)))
                self.assertEqual(old, mt(img, "mtype", "::HD/PICTURES/KEEP.PI1"))
                self.assertEqual(filler, mt(img, "mtype", "::HD/FILL.DAT"))
                self.clean(img)  # the failed save's temp file is a whole file, if a short one

    def test_paths_that_escape_hd_or_are_no_8_3_names_are_refused(self) -> None:
        img = self.card("fat32")
        for bad in ("..\\KESTREL\\SYSTEM.RV3", "\\KESTREL", "C:\\X", "a.pi1", "PICTURES/../X", "A long.txt", ""):
            with self.subTest(bad):
                self.assertEqual(EPTHNF, self.kfs(img, "delete", bad or "\\")[0])
        self.assertEqual(b"S" * 4000, mt(img, "mtype", "::KESTREL/SYSTEM.RV3"))

    def test_a_save_cut_after_any_sector_write_leaves_a_repairable_disk_and_no_damage(self) -> None:
        rnd = random.Random(4)
        for kind in CARDS:
            with self.subTest(kind):
                base = self.card(kind, "cut.img")
                old, new = rnd.randbytes(9000), rnd.randbytes(34_000)  # two requests
                self.assertEqual(0, self.save(base, "PICTURES\\SAVE.PI1", old))
                trial = self.tmp / "trial.img"
                shutil.copy(base, trial)
                _, total = self.kfs(trial, "save", "PICTURES\\SAVE.PI1", str(self.file("new", new)))
                for n in sorted({*range(0, total, 5), *range(max(0, total - 40), total + 1)}):  # every commit step
                    shutil.copy(base, trial)
                    self.kfs(trial, "save", "PICTURES\\SAVE.PI1", str(self.file("new", new)), cut=n)
                    subprocess.run(["fsck.fat", "-a", str(trial)], check=False, capture_output=True)
                    self.clean(trial)
                    self.assertEqual(b"neighbour" * 300, mt(trial, "mtype", "::HD/PICTURES/OLD.PI1"), n)
                    self.assertEqual(b"long one" * 500, mt(trial, "mtype", "::HD/LONG/A long picture name.pi1"), n)
                    got = subprocess.run(["mtype", "-i", str(trial), "::HD/PICTURES/SAVE.PI1"], check=False, capture_output=True)
                    if got.returncode == 0:
                        self.assertIn(got.stdout, (old, new), n)
                    else:  # the old entry went, the new one not yet named: the bytes wait under the temp name
                        self.assertEqual(new, mt(trial, "mtype", "::HD/PICTURES/~KOS0.TMP"), n)


if __name__ == "__main__":
    unittest.main()
