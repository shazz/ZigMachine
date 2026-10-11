"""The tooling around GEM over a data disk (docs/FPGA_GLASS.md, "GEM over a data disk"):
the shelf stages a data disk with GEM's board image, the generated bridge finds the cart's
disk exports, and the board SoC sim's variant (scripted mouse + data disk) names its files
apart from the plain run's."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest
from gemdisk_util import v1, v2

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
import glass_shelf
import hp_sim_variant
import zmd_fat
from host_bridges import DISK_APP_BRIDGE, disk_app_bridge

E = [(b"BOOT.WSM", 1536, 9636, 0)]


def test_bootable_is_the_browsers_boot_sector_rule() -> None:
    assert not zmd_fat.bootable((ROOT / "docs/demo-st_replay.zmd").read_bytes())
    assert zmd_fat.bootable((ROOT / "docs/demo-gem.zmd").read_bytes())
    assert zmd_fat.bootable(v1(E, sum_=0x1234)) and not zmd_fat.bootable(v1(E))
    assert zmd_fat.bootable(v2(E, 0, bootable=True)) and not zmd_fat.bootable(v2(E, 0))
    with pytest.raises(SystemExit, match="not a .zmd"):
        zmd_fat.bootable(b"PK\3\4" + bytes(4096))


def test_a_data_disk_boots_gem_and_a_bootable_one_its_own_cart() -> None:
    assert glass_shelf.boots((ROOT / "docs/demo-st_replay.zmd").read_bytes()) == "gem"
    assert glass_shelf.boots((ROOT / "docs/demo-stniccc.zmd").read_bytes()) == ""


def _fw(fws: Path, tag: str) -> None:
    (fws / tag).mkdir(parents=True)
    (fws / tag / "fw.bin").write_bytes(tag.encode() * 16)


def test_the_shelf_stages_st_replay_with_gems_image(tmp_path: Path) -> None:
    fws = tmp_path / "board"
    _fw(fws, "gem")
    csr = tmp_path / "csr_addr.h"
    csr.write_text("x")
    os.utime(csr, (100, 100))
    rows = dict(glass_shelf.build_shelf(tmp_path / "sd", fws, csr, ("st_replay",)))
    assert rows["zigmachine/demo-st_replay.zmd"].endswith(f"{fws / 'gem' / 'fw.bin'} (a data disk: GEM boots)")
    fat = (tmp_path / "sd" / "demo-st_replay.zmd").read_bytes()
    shelf = (ROOT / "docs/demo-st_replay.zmd").read_bytes()
    assert fat[0x300:0x340] == shelf[0x300:0x340] and fat[0x340:0x349] == b"CART.RV32"  # its files, + the image
    assert fat[0x600 : len(shelf)] == shelf[0x600:] and not zmd_fat.bootable(fat)  # still a data disk


def test_a_data_disk_without_gems_firmware_is_missing_gems(tmp_path: Path) -> None:
    fws = tmp_path / "board"
    _fw(fws, "st_replay")  # the program's own image is not what boots
    rows = dict(glass_shelf.build_shelf(tmp_path / "sd", fws, tmp_path / "none.h", ("st_replay",)))
    want = f"MISSING: no {fws / 'gem' / 'fw.bin'}; make -C fpga board-fw CART=gem"
    assert rows["zigmachine/demo-st_replay.zmd"] == want


def test_the_disk_bridge_takes_each_export_of_the_right_type_else_null() -> None:
    cart = {"insertDisk": ("void", ["u32"]), "isBooted": ("u32", []), "pollCartRequest": ("void", [])}
    text = disk_app_bridge(cart)
    assert text == "const host_disk_app_bridge host_dapp = {w2c_cart_insertDisk, w2c_cart_isBooted, 0, 0, 0, 0, 0};\n"
    assert len(DISK_APP_BRIDGE) == 7  # host.h host_disk_app_bridge's fields
    assert disk_app_bridge({}).count("0") == 7


def test_the_sim_variant_names_its_files_apart_and_scripts_the_mouse() -> None:
    var = hp_sim_variant.Variant("st_replay", hp_sim_variant.parse_pointer("2:40:30:0,3:40:30:1"))
    assert var.suffix.startswith("+dd-st_replay+ptr-") and hp_sim_variant.Variant().suffix == ""
    assert var.sim_pointer() == "2:7828,3:107828"
    assert var.make_vars() == ["ZM_SIM_POINTER=2:7828,3:107828"]
    assert var.disk() == ROOT / "docs/demo-st_replay.zmd"


@pytest.mark.parametrize("bad", ["2:40:30", "2:40:x:0", "3:1:1:0,2:1:1:0"])
def test_a_bad_pointer_script_is_refused(bad: str) -> None:
    with pytest.raises(SystemExit):
        hp_sim_variant.parse_pointer(bad)


def test_a_data_disk_that_is_not_on_the_shelf_is_refused() -> None:
    with pytest.raises(SystemExit, match="no "):
        hp_sim_variant.Variant("no_such_disk").disk()
