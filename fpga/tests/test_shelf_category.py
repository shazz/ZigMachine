"""The SD card's folders (tools/shelf_category.py, docs/FPGA_GLASS.md "The menu"): every cart a card
can carry gets a category, from the catalog's machine type or the explicit table, and a cart
nothing places stops the staging instead of landing in a catch-all folder."""

from __future__ import annotations

import os
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
    assert shelf_category.disk_path(tag) == f"{category}/demo-{tag}.zmd"


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
    sd = tmp_path / "sd"
    assert sorted(str(p.relative_to(sd)) for p in sd.rglob("demo-*.zmd")) == [
        "demos/demo-stniccc.zmd", "tools/demo-st_replay.zmd", "tutorials/demo-tutorial.zmd"]  # fmt: skip
    assert "zigmachine/progs/demo-st_replay/BOOT.WSM.zmd" in rows  # programs stay in progs/, by the bare name
    lines = [ln.split("\t")[0] for ln in (sd / "shelf.txt").read_text().splitlines() if not ln.startswith("#")]
    assert sorted(lines) == ["demos/demo-stniccc.zmd", "tools/demo-st_replay.zmd", "tutorials/demo-tutorial.zmd"]


def test_path_prints_where_an_upload_script_finds_the_disk() -> None:
    tool = [sys.executable, str(FPGA / "tools/shelf_category.py"), "--path"]
    ok = subprocess.run([*tool, "joust"], capture_output=True, text=True, check=False)
    assert (ok.returncode, ok.stdout) == (0, "games/demo-joust.zmd\n")
    bad = subprocess.run([*tool, "no_such_cart"], capture_output=True, text=True, check=False)
    assert bad.returncode == 1 and "no_such_cart: no category" in bad.stderr
