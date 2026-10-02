"""The glass's ARM program (fpga/glass) and its disks, without the board.

- `zig build test`: the program's own tests, against the simulated register
  block and a fake DDR (loader, menu, keymap, pad, OSD, shelf, the app).
- tools/zmd_fat.py: a fat disk keeps every byte of the shelf disk and its
  bootability, and carries the board image as a FAT file.
- The whole load path, end to end: a shelf disk + the board image that
  fpga/cycles links for that cart -> ZX0 -> fat disk -> `glass sim-load` ->
  the DDR window must hold exactly that image, then zeros. Runs on every cart
  whose image is built (`make cycles-fw`); a synthetic image always runs.
"""

import os
import random
import runpy
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
GLASS = FPGA / "glass"
WORK = FPGA / "build" / "glass" / "test"
ZIG = os.environ.get("ZIG", str(Path.home() / ".local/zig/0.16.0/zig"))
sys.path.insert(0, str(FPGA / "tools"))
import glass_sd
import zmd_fat

WINDOW = "0x400000"  # 4 MiB: every board image so far is under 0.6 MB


def _zig(*args: str) -> None:
    r = subprocess.run([ZIG, "build", *args], cwd=GLASS, capture_output=True, text=True, timeout=600, check=False)
    assert r.returncode == 0, r.stdout + r.stderr


@pytest.fixture(scope="module")
def tools() -> dict[str, Path]:
    """The host `glass` and a zx0pack built from the repo's own sources."""
    _zig()
    WORK.mkdir(parents=True, exist_ok=True)
    return {"glass": GLASS / "zig-out" / "bin" / "glass", "zx0pack": glass_sd.zx0pack()}


def test_zig_unit_tests() -> None:
    _zig("test")


def _load(tools: dict[str, Path], disk: Path, board: bytes, tag: str) -> bytes:
    (WORK / f"{tag}.rv32").write_bytes(board)
    packed = WORK / f"{tag}.rv32.zx0"
    subprocess.run([tools["zx0pack"], WORK / f"{tag}.rv32", packed], check=True, capture_output=True)
    fat = WORK / f"{tag}.zmd"
    fat.write_bytes(zmd_fat.fatten(disk.read_bytes(), packed.read_bytes()))
    out = WORK / f"{tag}.ddr"
    r = subprocess.run([tools["glass"], "sim-load", fat, out, WINDOW], capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stdout + r.stderr
    return out.read_bytes()


def _a_disk() -> Path:
    for tag in ("tutorial", "stniccc", "union_beatdis"):
        if (ROOT / "docs" / f"demo-{tag}.zmd").exists():
            return ROOT / "docs" / f"demo-{tag}.zmd"
    pytest.skip("no docs/demo-*.zmd shelf disk")


def test_synthetic_image_lands_exactly(tools: dict[str, Path]) -> None:
    rng = random.Random(7)
    board = bytes(rng.randrange(256) for _ in range(30001)) + bytes(50000) + b"tail"
    assert _load(tools, _a_disk(), board, "synthetic") == board


def _board_images() -> list[tuple[str, Path]]:
    """The board build (`aligned`) of every cart that has one; ZM_GLASS_ALL=1
    adds the other variants' images too (the whole shelf, about 80 s)."""
    variants = ("aligned", "nobounds", "stock") if os.environ.get("ZM_GLASS_ALL") == "1" else ("aligned",)
    found: dict[str, Path] = {}
    for variant in variants:
        for fw in sorted((FPGA / "build" / "cycles" / variant).glob("*/fw.bin")):
            found.setdefault(fw.parent.name, fw)
    return sorted(found.items())


@pytest.mark.parametrize(("tag", "fw"), _board_images() or [("none", None)], ids=lambda v: str(v)[-24:])
def test_cart_board_image_lands_exactly(tools: dict[str, Path], tag: str, fw: Path | None) -> None:
    disk = ROOT / "docs" / f"demo-{tag}.zmd"
    if fw is None or not disk.exists():
        pytest.skip("no board image built (make cycles-fw CART=<tag> VARIANT=aligned) or no shelf disk")
    assert _load(tools, disk, fw.read_bytes(), tag) == fw.read_bytes()


def test_fat_disk_keeps_the_shelf_disk_and_its_bootability() -> None:
    disk = _a_disk().read_bytes()
    fat = zmd_fat.fatten(disk, b"BOARD")
    v1 = disk[:6] == b"ZMDISK"
    boot = 512 if v1 else 1024
    assert zmd_fat._be_sum(fat[:boot]) == zmd_fat._be_sum(disk[:boot])
    skip = {(0x0A, 0x0E), (0x1FE, 0x200)} if v1 else set()  # total blocks + checksum word
    count_at, fat_at = (0x2E4, 0x300) if v1 else (0x4F4, 0x800)
    skip |= {(count_at, count_at + 2), (fat_at, fat_at + 24 * 32)}
    changed = [i for i in range(len(disk)) if fat[i] != disk[i] and not any(a <= i < b for a, b in skip)]
    assert changed == [], f"bytes outside the header changed: {changed[:8]}"
    n = struct.unpack_from("<H", fat, count_at)[0]
    entry = fat[fat_at + (n - 1) * 32 :][:32]
    start, length = struct.unpack_from("<II", entry, 16)
    assert entry[:9] == b"CART.RV32" and fat[start : start + length] == b"BOARD" and start % 512 == 0
    if v1:
        assert struct.unpack_from("<I", fat, 0x0A)[0] * 512 == len(fat)


def test_fat_disk_refusals() -> None:
    disk = _a_disk().read_bytes()
    with pytest.raises(SystemExit, match="already"):
        zmd_fat.fatten(zmd_fat.fatten(disk, b"A"), b"B")
    with pytest.raises(SystemExit, match="not a .zmd"):
        zmd_fat.fatten(b"PK\3\4" + bytes(4096), b"A")


def test_cart_side_input_routing_matches_the_browser() -> None:
    """The cart CPU's half (glass/firmware/glass_input.c): events -> cart exports."""
    values = runpy.run_path(str(FPGA / "gen" / "glass_map.py"))
    defines = [f"-D{k}={v}u" for k, v in values.items() if k.isupper() and isinstance(v, int)]
    WORK.mkdir(parents=True, exist_ok=True)
    exe = WORK / "glass_input_test"
    fw = GLASS / "firmware"
    cmd = ["clang", "-std=c11", "-Wall", "-Werror", f"-I{fw}", *defines, str(fw / "glass_input.c")]
    subprocess.run([*cmd, str(FPGA / "tests/tb/glass_input_test.c"), "-o", str(exe)], check=True)
    r = subprocess.run([exe], capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stdout + r.stderr


def test_boot_script_image_is_what_mkimage_makes(tmp_path: Path) -> None:
    if shutil.which("mkimage") is None:
        pytest.skip("no mkimage (u-boot-tools) to compare with")
    ref = tmp_path / "ref.scr"
    env = {**os.environ, "SOURCE_DATE_EPOCH": "1700000000"}
    cmd = ["mkimage", "-A", "arm", "-O", "linux", "-T", "script", "-C", "none", "-n", "zigmachine"]
    subprocess.run([*cmd, "-d", glass_sd.BOOT_CMD, ref], check=True, capture_output=True, env=env)
    assert glass_sd.script_image(glass_sd.BOOT_CMD.read_bytes(), "zigmachine", 1700000000) == ref.read_bytes()


def test_sd_staging_lists_what_is_missing_and_refuses_devices(tmp_path: Path) -> None:
    images = tmp_path / "br" / "images"
    images.mkdir(parents=True)
    for name in ("zImage", "zigmachine-z7lite.dtb", "rootfs.cpio.uboot"):
        (images / name).write_bytes(name.encode())
    out = tmp_path / "sd"
    rows = dict(glass_sd.stage(out, tmp_path / "br", "no-such-variant"))
    assert (out / "zigmachine.dtb").read_bytes() == b"zigmachine-z7lite.dtb"
    assert (out / "boot.scr").read_bytes()[:4] == bytes.fromhex("27051956")
    assert rows["zImage"].endswith("zImage") and not any(k.startswith("zigmachine/") for k in rows)
    with pytest.raises(SystemExit, match="device"):
        glass_sd.stage(Path("/dev/null"), None, "aligned")
