"""The OSD's words for GEM and its data disk (tools/shelf_meta.py OVERRIDES, docs/FPGA_GLASS.md
"Cart descriptions"): the catalog calls GEM by the browser menu's verb, "EXIT TO GEM", which
is no name for a shelf entry; an override names it, and an empty override field keeps what
the repo says."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import shelf_meta


def _row(tag: str) -> tuple[str, ...]:
    (row,) = shelf_meta.records([tag])
    return row


def test_gem_is_the_gem_desktop_of_digital_research_1985() -> None:
    assert _row("gem")[:5] == ("demo-gem.zmd", "GEM DESKTOP", "Digital Research", "1985", "system")
    assert "EXIT TO GEM" in {name for name, tag, _ in shelf_meta.channels.entries() if tag == "gem"}  # the menu's


def test_an_empty_override_field_keeps_the_catalogs() -> None:
    assert _row("st_replay")[1:4] == ("ST REPLAY", "Microdeal", "")  # the catalog's title; no year written down
    assert _row("stniccc")[1:4] == ("OXYGENE STNICCC 2000", "Oxygene", "2000")  # no override at all


def test_shelf_txt_carries_the_overridden_titles(tmp_path: Path) -> None:
    text = shelf_meta.write(tmp_path, ["gem", "st_replay"]).read_text()
    lines = [ln.split("\t") for ln in text.splitlines() if not ln.startswith("#")]
    assert [ln[:4] for ln in lines] == [["demo-gem.zmd", "GEM DESKTOP", "Digital Research", "1985"],
                                       ["demo-st_replay.zmd", "ST REPLAY", "Microdeal", ""]]  # fmt: skip


@pytest.mark.parametrize("tag", list(shelf_meta.OVERRIDES))
def test_every_override_is_a_catalog_cart_and_fits_the_osd(tag: str) -> None:
    assert tag in {t for _, t, _ in shelf_meta.channels.entries()}  # an override for no cart is a typo
    title, group, year = shelf_meta.OVERRIDES[tag]
    assert len(title) <= 22 and title == shelf_meta.ascii_text(title) and title.upper() == title  # the catalog's cap
    assert group == shelf_meta.ascii_text(group) and (year == "" or shelf_meta.YEAR.fullmatch(year))
