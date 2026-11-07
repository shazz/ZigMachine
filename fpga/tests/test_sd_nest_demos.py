"""Moving a card's flat CARTS/demos/ into platform folders (tools/sd_nest_demos.py): the printed
lines move each of the 87 demos to where tools/shelf_category.py now stages it, and a name the
repo cannot place stops the script instead of guessing a folder."""

from __future__ import annotations

import shlex
import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import sd_nest_demos
import shelf_category


def test_every_demo_moves_to_the_path_staging_now_writes() -> None:
    pairs, bad = sd_nest_demos.moves(sd_nest_demos.demo_names())
    assert bad == []
    assert len(pairs) == 87  # the card's CARTS/demos/ on 7 Nov
    assert ("demos/demo-stniccc.zmd", "demos/atari_st/demo-stniccc.zmd") in pairs
    assert all(to == shelf_category.disk_path(to.rsplit("demo-", 1)[1][:-4]) for _, to in pairs)


def test_the_script_remounts_makes_each_folder_once_and_quotes_every_path() -> None:
    lines = sd_nest_demos.script([("demos/demo-a.zmd", "demos/amiga/demo-a.zmd"),
                                  ("demos/demo-b.zmd", "demos/amiga/demo-b.zmd")], "/mnt/my sd")  # fmt: skip
    assert lines[0] == "mount -o remount,rw '/mnt/my sd'" and lines[-1] == "mount -o remount,ro '/mnt/my sd'"
    assert [ln for ln in lines if ln.startswith("mkdir")] == ["mkdir -p '/mnt/my sd/CARTS/demos/amiga'"]
    assert shlex.split(lines[2]) == ["mv", "/mnt/my sd/CARTS/demos/demo-a.zmd", "/mnt/my sd/CARTS/demos/amiga/demo-a.zmd"]


def test_a_listing_with_a_disk_the_repo_cannot_place_stops_the_script(tmp_path: Path) -> None:
    listing = tmp_path / "ls.txt"
    listing.write_text("demo-stniccc.zmd\ndemo-joust.zmd\ndemo-no_such_cart.zmd\nnotes.txt\n\n")
    run = [sys.executable, str(FPGA / "tools/sd_nest_demos.py"), "--files", str(listing)]
    out = subprocess.run(run, capture_output=True, text=True, check=False)
    assert out.returncode == 1 and out.stdout == ""
    assert out.stderr.splitlines() == [
        "demo-joust.zmd: not a demo's disk",  # a game: it was never in demos/
        "no_such_cart: no category (it is not in the catalog): add it to fpga/tools/shelf_category.py TABLE",
        "notes.txt: not a demo's disk",
    ]
    listing.write_text("demo-stniccc.zmd\n")
    ok = subprocess.run(run, capture_output=True, text=True, check=True)
    assert "mv /mnt/sd/CARTS/demos/demo-stniccc.zmd /mnt/sd/CARTS/demos/atari_st/demo-stniccc.zmd" in ok.stdout
