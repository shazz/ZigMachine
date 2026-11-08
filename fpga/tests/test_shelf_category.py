"""The SD card's folders (tools/shelf_category.py, docs/FPGA_GLASS.md "The menu"): every cart a card
can carry gets a category, from the catalog's machine type or the explicit table, and a cart
nothing places stops the staging instead of landing in a catch-all folder."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import glass_shelf
import shelf_category
import shelf_meta


def test_every_cart_a_card_can_carry_has_a_category() -> None:
    tags = shelf_category.every_tag()
    assert shelf_category.problems(tags) == []
    assert set(glass_shelf.SHELF) <= set(tags)  # the shelf's carts are among them
    assert {shelf_category.category(t) for t in tags} == set(shelf_category.CATEGORIES)  # no empty folder


@pytest.mark.parametrize(
    ("tag", "category"),
    [
        ("stniccc", "demos"),  # atari st: a demo by its catalog type
        ("tsl_hybridglenz", "demos"),  # amiga
        ("union_tnt3", "demos"),  # a Union Demo screen, in no catalog line
        ("pt2", "tools"),  # pc: a program port
        ("sysinfo", "tools"),  # the catalog says "system", the table says it is an app
        ("gem", "system"),
        ("joust", "games"),  # atari st, but the table knows it is a game
        ("tutorial", "tutorials"),
        ("xm_test", "tests"),
        ("bench", "tests"),  # a native cart: not in the catalog at all
    ],
)
def test_a_cart_goes_in_its_category(tag: str, category: str) -> None:
    assert shelf_category.category(tag) == category
    assert shelf_category.disk_path(tag).startswith(f"{category}/")


@pytest.mark.parametrize(
    ("tag", "path"),
    [
        ("stniccc", "demos/atari_st/demo-stniccc.zmd"),  # catalog type "atari st": no space on the card
        ("tsl_hybridglenz", "demos/amiga/demo-tsl_hybridglenz.zmd"),
        ("trsi_transarctica", "demos/atari_falcon/demo-trsi_transarctica.zmd"),
        ("c64_1988", "demos/c64/demo-c64_1988.zmd"),
        ("union_tnt3", "demos/atari_st/demo-union_tnt3.zmd"),  # in no catalog line: the Union Demo's machine
        ("fuji_hobbytronic", "demos/kestrel/demo-fuji_hobbytronic.zmd"),  # written for the machine, an XL tune
        ("anima", "demos/kestrel/demo-anima.zmd"),
        ("joust", "games/demo-joust.zmd"),  # only demos/ is split by platform
        ("pt2", "tools/demo-pt2.zmd"),
    ],
)
def test_a_demo_goes_in_its_platform_folder(tag: str, path: str) -> None:
    assert shelf_category.disk_path(tag) == path


def test_every_platform_folder_is_one_fat_name_glass_takes() -> None:
    names = set(shelf_category.PLATFORMS.values())
    assert {"atari_st", "amiga", "atari_falcon", "atari_xl", "c64", "kestrel"} == names
    assert all(re.fullmatch(r"[a-z0-9_]{1,24}", n) for n in names)  # no space (ctl load), shelf.zig MAX_FOLDER
    demos = [t for t in shelf_category.every_tag() if shelf_category.category(t) == "demos"]
    assert {shelf_category.platform(t) for t in demos} == names - {"atari_xl"}  # no XL production yet


def test_a_demo_with_no_platform_is_an_error_not_a_catch_all(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(shelf_category.TABLE, "stniccc", "demos")  # a demo by the table, of a machine
    monkeypatch.setitem(shelf_category.kinds(), "stniccc", "spectrum")  # no folder is for
    with pytest.raises(shelf_category.UnknownCategory, match="stniccc: a demo with no platform .*'spectrum'"):
        shelf_category.disk_path("stniccc")
    assert shelf_category.problems(["stniccc"]) != []
    monkeypatch.setitem(shelf_category.PLATFORM_TABLE, "stniccc", "atari st")  # the override wins
    assert shelf_category.disk_path("stniccc") == "demos/atari_st/demo-stniccc.zmd"


def test_a_cart_nothing_places_is_an_error_not_a_catch_all() -> None:
    with pytest.raises(shelf_category.UnknownCategory, match="no_such_cart: no category .*not in the catalog"):
        shelf_category.category("no_such_cart")
    assert shelf_category.problems(["stniccc", "no_such_cart"]) == [
        "no_such_cart: no category (it is not in the catalog): add it to fpga/tools/shelf_category.py TABLE"
    ]


def test_a_zigmachine_cart_missing_from_the_table_is_an_error(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delitem(shelf_category.TABLE, "polkadots")  # a "zigmachine" screen: no rule can tell
    with pytest.raises(shelf_category.UnknownCategory, match="'zigmachine'"):
        shelf_category.category("polkadots")


def test_every_table_entry_is_a_cart_and_a_known_category() -> None:
    carts = set(shelf_category.kinds()) | set(shelf_meta.cart_tags()) | set(shelf_category.native_carts())
    assert set(shelf_category.TABLE) <= carts  # a table line for no cart is a typo
    assert set(shelf_category.TABLE.values()) <= set(shelf_category.CATEGORIES)
    assert {"hello", "hello_asm", "bench"} <= set(shelf_category.native_carts())


def test_staging_refuses_a_cart_with_no_category(tmp_path: Path) -> None:
    fws = tmp_path / "board"
    (fws / "mystery").mkdir(parents=True)
    (fws / "mystery" / "fw.bin").write_bytes(bytes(64))  # a cart being tried out, never placed
    with pytest.raises(SystemExit, match="mystery: no category"):
        glass_shelf.build_shelf(tmp_path / "sd", fws, tmp_path / "none.h", ())
    assert not list((tmp_path / "sd").rglob("*.zmd"))  # refused before anything was staged


def test_staging_puts_each_disk_in_its_folder_and_shelf_txt_names_the_path(tmp_path: Path) -> None:
    fws = tmp_path / "board"
    for tag in ("tutorial", "stniccc"):
        (fws / tag).mkdir(parents=True)
        (fws / tag / "fw.bin").write_bytes(bytes(64))
    csr = tmp_path / "csr_addr.h"
    csr.write_text("x")
    os.utime(csr, (100, 100))
    rows = dict(glass_shelf.build_shelf(tmp_path / "sd", fws, csr, ("tutorial", "st_replay")))
    assert not list((tmp_path / "sd" / "KESTREL").rglob("demo-*.zmd")) and (tmp_path / "sd" / "CARTS" / "shelf.txt").exists()
    sd = tmp_path / "sd" / "CARTS"  # tools/sd_layout.py: the shelf and shelf.txt
    assert sorted(str(p.relative_to(sd)) for p in sd.rglob("demo-*.zmd")) == [
        "demos/atari_st/demo-stniccc.zmd", "tools/demo-st_replay.zmd", "tutorials/demo-tutorial.zmd"]  # fmt: skip
    assert "KESTREL/progs/demo-st_replay/BOOT.WSM.zmd" in rows  # programs stay in progs/, by the bare name
    lines = [ln.split("\t")[0] for ln in (sd / "shelf.txt").read_text().splitlines() if not ln.startswith("#")]
    assert sorted(lines) == ["demos/atari_st/demo-stniccc.zmd", "tools/demo-st_replay.zmd", "tutorials/demo-tutorial.zmd"]


def test_path_prints_where_an_upload_script_finds_the_disk() -> None:
    tool = [sys.executable, str(FPGA / "tools/shelf_category.py"), "--path"]
    ok = subprocess.run([*tool, "joust"], capture_output=True, text=True, check=False)
    assert (ok.returncode, ok.stdout) == (0, "games/demo-joust.zmd\n")
    bad = subprocess.run([*tool, "no_such_cart"], capture_output=True, text=True, check=False)
    assert bad.returncode == 1 and "no_such_cart: no category" in bad.stderr
