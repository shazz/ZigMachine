"""tools/rootfs_glass.py: the board's initramfs gets the card's glass, and nothing else in it moves.

boot.cmd sets HP1 0xF00 (W64 by default, decisions.md 2026-10-19), so the /usr/bin/glass that S99glass
starts at boot must be one that knows afi.zig. These tests pin the archive surgery and the U-Boot wrap.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import glass_sd
import rootfs_glass


def _cpio(root: Path, names: list[str]) -> bytes:
    if shutil.which("cpio") is None:
        pytest.skip("no cpio")
    r = subprocess.run(["cpio", "-o", "-H", "newc", "--quiet"], cwd=root, input="\n".join(names).encode(),
                       capture_output=True, check=True)  # fmt: skip
    return r.stdout


def _tree(tmp: Path) -> tuple[Path, list[str]]:
    root = tmp / "root"
    (root / "usr/bin").mkdir(parents=True)
    (root / "etc").mkdir()
    (root / "etc/hostname").write_text("zigmachine\n")
    (root / "usr/bin/glass").write_bytes(b"old glass, 17 B")
    (root / "usr/bin/glass").chmod(0o755)
    (root / "usr/bin/zz").write_bytes(b"after the glass")
    return root, ["etc", "etc/hostname", "usr", "usr/bin", "usr/bin/glass", "usr/bin/zz"]


def test_the_glass_entry_is_swapped_and_every_other_entry_keeps_its_bytes(tmp_path: Path) -> None:
    root, names = _tree(tmp_path)
    cpio = _cpio(root, names)
    new = rootfs_glass.replace(cpio, rootfs_glass.ENTRY, b"new glass: a longer body, 37 bytes...")
    assert rootfs_glass.member(new, rootfs_glass.ENTRY) == b"new glass: a longer body, 37 bytes..."
    for name in ("etc/hostname", "usr/bin/zz"):
        assert rootfs_glass.member(new, name) == rootfs_glass.member(cpio, name)
    out = tmp_path / "x"
    out.mkdir()
    subprocess.run(["cpio", "-idm", "--quiet"], cwd=out, input=new, check=True)  # GNU cpio reads it back
    assert (out / "usr/bin/glass").read_bytes() == b"new glass: a longer body, 37 bytes..."
    assert os.stat(out / "usr/bin/glass").st_mode & 0o777 == 0o755
    assert (out / "usr/bin/zz").read_bytes() == b"after the glass"


def test_replacing_with_the_same_bytes_gives_the_same_archive(tmp_path: Path) -> None:
    root, names = _tree(tmp_path)
    cpio = _cpio(root, names)
    assert rootfs_glass.replace(cpio, "usr/bin/glass", rootfs_glass.member(cpio, "usr/bin/glass")) == cpio


def test_an_archive_without_exactly_one_glass_or_not_newc_is_refused(tmp_path: Path) -> None:
    root, names = _tree(tmp_path)
    cpio = _cpio(root, [n for n in names if n != "usr/bin/glass"])
    with pytest.raises(ValueError, match="0 entries"):
        rootfs_glass.replace(cpio, rootfs_glass.ENTRY, b"x")
    with pytest.raises(ValueError, match="not a newc"):
        rootfs_glass.entries(b"\x1f\x8b" + bytes(200))  # a gzipped cpio is not handled


def test_ramdisk_image_is_what_mkimage_makes(tmp_path: Path) -> None:
    if shutil.which("mkimage") is None:
        pytest.skip("no mkimage (u-boot-tools) to compare with")
    data = tmp_path / "rootfs.cpio"
    data.write_bytes(bytes(range(256)) * 9)
    ref = tmp_path / "ref.uboot"
    env = {**os.environ, "SOURCE_DATE_EPOCH": "1700000000"}
    cmd = ["mkimage", "-A", "arm", "-O", "linux", "-T", "ramdisk", "-C", "none", "-d", str(data), str(ref)]
    subprocess.run(cmd, check=True, capture_output=True, env=env)
    assert rootfs_glass.ramdisk_image(data.read_bytes(), 1700000000) == ref.read_bytes()


def test_sd_staging_puts_the_card_glass_into_the_rootfs(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    root, names = _tree(tmp_path)
    images = tmp_path / "br/images"
    images.mkdir(parents=True)
    (images / "rootfs.cpio").write_bytes(_cpio(root, names))
    (images / "rootfs.cpio.uboot").write_bytes(b"Buildroot's own, with its old glass")
    glass = tmp_path / "glass"
    glass.write_bytes(b"\x7fELF the card's glass")
    monkeypatch.setattr(glass_sd, "GLASS_ARM", glass)
    out = tmp_path / "sd"
    out.mkdir()
    name, src = glass_sd._rootfs(tmp_path / "br", out, 1700000000)
    image = (out / "rootfs.cpio.uboot").read_bytes()
    assert name == "rootfs.cpio.uboot" and "+ glass md5" in src
    assert rootfs_glass.member(image[64:], "usr/bin/glass") == b"\x7fELF the card's glass"  # no strip: as built
    assert image[:4] == bytes.fromhex("27051956") and image[30] == rootfs_glass.IH_TYPE_RAMDISK


def test_sd_staging_without_a_cpio_says_the_rootfs_glass_is_stale(tmp_path: Path) -> None:
    images = tmp_path / "br/images"
    images.mkdir(parents=True)
    (images / "rootfs.cpio.uboot").write_bytes(b"Buildroot's own, with its old glass")
    out = tmp_path / "sd"
    out.mkdir()
    name, src = glass_sd._rootfs(tmp_path / "br", out, 1700000000)
    assert name == "rootfs.cpio.uboot" and src.startswith("STALE: Buildroot's own glass")
    assert glass_sd._rootfs(None, out, 0)[1].startswith("MISSING")
