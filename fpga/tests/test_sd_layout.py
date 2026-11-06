"""The SD card's layout (decisions.md 2026-11-06): KESTREL/ (system), CARTS/ (the shelf), HD/ (KOS's C:),
the boot files alone at the root. One set of names (tools/sd_layout.py) = glass's (glass/src/layout.zig)
= the desktop shell's C: root (apps/zig/scenes/gem_fat.zig); the staging tools write it; and
tools/sd_migrate_layout.sh, run under busybox sh as on the board, moves an old card there and back.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(ROOT / "sdk"))
import card  # after the path insert
import glass_sd
import sd_layout

MIGRATE = FPGA / "tools/sd_migrate_layout.sh"
SH = shutil.which("busybox")


def test_one_set_of_names_in_python_glass_and_the_desktop_shell() -> None:
    zig = (FPGA / "glass/src/layout.zig").read_text()
    names = dict(re.findall(r'pub const (\w+) = "([^"]*)";', zig))
    assert (names["SYSTEM"], names["CARTS"], names["HD"], names["OLD"], names["ROOT"]) == (
        sd_layout.SYSTEM, sd_layout.CARTS, sd_layout.HD, sd_layout.OLD, "/mnt/sd")
    shell = (ROOT / "apps/zig/scenes/gem_fat.zig").read_text()
    assert f'pub const C_ROOT = "{sd_layout.HD}";' in shell
    s99 = (FPGA / "glass/boot/buildroot/overlay/etc/init.d/S99glass").read_text()
    assert 'OVERRIDE=$CARD/KESTREL/glass' in s99 and '"$GLASS" run "$CARD"' in s99 and "CARD=/mnt/sd" in s99


def test_sd_staging_writes_kestrel_carts_and_hd_never_zigmachine(tmp_path: Path) -> None:
    out = tmp_path / "sd"
    rows = dict(glass_sd.stage(out, None, tmp_path / "no-firmwares"))
    assert (out / "HD").is_dir() and "HD/" in rows
    assert sd_layout.GLASS in rows and "glass" not in rows  # the override, never a root glass
    assert not (out / "zigmachine").exists()
    assert {k.split("/")[0] for k in rows if "/" in k} == {"KESTREL", "CARTS", "HD"}
    assert (out / "CARTS" / "shelf.txt").exists() and (out / "KESTREL").is_dir()


def test_sdk_card_stages_a_cart_on_the_shelf_in_carts(tmp_path: Path) -> None:
    cart = tmp_path / "cart.bin"
    cart.write_bytes(bytes(range(256)) * 4)
    a = argparse.Namespace(tag="hello", cart=cart, disk=ROOT / "docs/demo-tutorial.zmd", zx0pack=glass_sd.zx0pack(),
                           out=tmp_path / "sd", card=None, release=None, category="demos", title="Hello", group="",
                           year="", desc="")  # fmt: skip
    assert card.stage(a) == ["CARTS/demos/demo-hello.zmd", "CARTS/shelf.txt"]
    assert (tmp_path / "sd/CARTS/shelf.txt").read_text().splitlines()[-1].startswith("demos/demo-hello.zmd\tHello\t")
    with pytest.raises(SystemExit, match="category"):
        card.stage(argparse.Namespace(**{**vars(a), "category": "nope"}))


# An old card as the board's was on 6 Nov: boot files and their copies, rollback_* folders, a card glass.
OLD_CARD = {
    "BOOT.BIN": "zest", "BOOT.BIN.ours": "spl", "u-boot.img": "u", "boot.scr": "s", "boot.scr.bb67385d": "s0",
    "zImage": "k", "zImage.prev": "k0", "zigmachine.dtb": "d", "zigmachine.bit": "b", "rootfs.cpio.uboot": "r",
    "rootfs.cpio.uboot.31eeb461": "r0", "uImage": "zk", "rootfs.ub": "zr", "zest.dtb": "zd", "authorized_keys": "key",
    "glass": "old glass", "MANIFEST.txt": "m", "rollback_kos/zigmachine/system.rv32": "sys0",
    "zigmachine/system.rv32": "sys", "zigmachine/glass.cfg": "volume=3", "zigmachine/kos/desktop.rv32": "desk",
    "zigmachine/progs/by-hash/ab.rv32": "p", "zigmachine/progs/demo-st_replay/BOOT.WSM.zmd": "w",
    "zigmachine/shelf.txt": "t", "zigmachine/demos/demo-a.zmd": "a", "zigmachine/tools/demo-b.zmd": "b",
}  # fmt: skip
BOOT = [k for k in OLD_CARD if "/" not in k and k not in ("glass", "MANIFEST.txt")]
NEW_CARD = {
    **{k: OLD_CARD[k] for k in BOOT}, "KESTREL/rollback/glass": "old glass", "KESTREL/rollback/MANIFEST.txt": "m",
    "KESTREL/rollback/rollback_kos/zigmachine/system.rv32": "sys0", "KESTREL/system.rv32": "sys",
    "KESTREL/glass.cfg": "volume=3", "KESTREL/kos/desktop.rv32": "desk", "KESTREL/progs/by-hash/ab.rv32": "p",
    "KESTREL/progs/demo-st_replay/BOOT.WSM.zmd": "w", "CARTS/shelf.txt": "t", "CARTS/demos/demo-a.zmd": "a",
    "CARTS/tools/demo-b.zmd": "b",
}  # fmt: skip


def tree(root: Path) -> dict[str, str]:
    return {p.relative_to(root).as_posix(): p.read_text() for p in sorted(root.rglob("*")) if p.is_file()}


def migrate(card_dir: Path, *args: str) -> str:
    r = subprocess.run([SH, "sh", MIGRATE, *args, str(card_dir)], capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stdout + r.stderr
    return r.stdout


@pytest.mark.skipif(SH is None, reason="no busybox (the board's sh)")
def test_migration_moves_an_old_card_once_and_back(tmp_path: Path) -> None:
    sd = tmp_path / "sd"
    for rel, text in OLD_CARD.items():
        (sd / rel).parent.mkdir(parents=True, exist_ok=True)
        (sd / rel).write_text(text)
    dry = migrate(sd, "--dry-run")
    assert tree(sd) == OLD_CARD and "mv zigmachine/system.rv32 KESTREL/system.rv32" in dry
    out = migrate(sd)
    assert tree(sd) == NEW_CARD and (sd / "HD").is_dir() and (sd / "zigmachine").is_dir()  # emptied, kept
    assert "mv glass KESTREL/rollback/glass" in out and "10 moved, 0 skipped" in out and "--back" in out
    assert "0 moved, 0 skipped" in migrate(sd)  # again: nothing to do
    (sd / "KESTREL/glass").write_text("new glass")  # an override, put there after
    migrate(sd, "--back")
    assert tree(sd) == {**OLD_CARD, "glass.kestrel": "new glass"}
    assert not (sd / "KESTREL").exists() and not (sd / "CARTS").exists() and (sd / "HD").is_dir()


@pytest.mark.skipif(SH is None, reason="no busybox (the board's sh)")
def test_migration_never_overwrites(tmp_path: Path) -> None:
    sd = tmp_path / "sd"
    for rel, text in {"zigmachine/system.rv32": "old", "KESTREL/system.rv32": "new", "zigmachine/shelf.txt": "t"}.items():
        (sd / rel).parent.mkdir(parents=True, exist_ok=True)
        (sd / rel).write_text(text)
    out = migrate(sd)
    assert "skip zigmachine/system.rv32: KESTREL/system.rv32 is there already" in out and "1 moved, 1 skipped" in out
    assert tree(sd)["KESTREL/system.rv32"] == "new" and tree(sd)["zigmachine/system.rv32"] == "old"
