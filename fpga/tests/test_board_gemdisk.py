"""GEM over a data disk on the board (docs/FPGA_GLASS.md, "GEM over a data disk"): the FAT
listing the firmware and the native host hand GEM (host/zmd_dir.h, host/disk_app.h) is the
browser's, byte for byte.

- The listing (zmd_dir.h) against the browser's OWN parseDisk (docs/zmdisk.js) and listing
  block (cut out of docs/sealed-loader.js, run in node): ST Replay's disk, v1 and v2 disks,
  repeated names, array-index names, bad UTF-8, a BOM, NUL cuts, more files than the ROM's
  cap, no files, a type byte past the end, a FAT past the end, a short disk, a bad magic, a
  corrupt checksum, records past the memory's end.
- scene_hash.mjs's --data-disk step is the browser's, text for text.
- The native host with --data-disk equals scene_hash.mjs --data-disk frame for frame on GEM
  opening the floppy (the listing drawn) and double-clicking BOOT.WSM (request 3, reported by
  both); a bootable disk is refused by both.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

import pytest
from gemdisk_util import ROOT, browser_find, browser_list, v1, v2

FPGA = Path(__file__).resolve().parent.parent
WORK = FPGA / "build" / "board_gemdisk"
HOST = FPGA / "build/host/gem/host"
ST_REPLAY = ROOT / "docs/demo-st_replay.zmd"

E = [(b"BOOT.WSM", 1536, 9636, 0), (b"SAMPLE.RAW", 11264, 773120, 1)]
ODD_NAMES = [b"\xff\xfeAB", b"\xe2\x82", b"\xef\xbb\xbfBOM", b"A\0B\nC", b"A\nB\0C", b"\xc3\xa9t\xc3\xa9",
             b"ABCDEFGHIJKLMNOP", b"__proto__", b"\xf0\x9f\x98\x80X", b"\xed\xa0\x80", b"\xc0\xaf"]  # fmt: skip
DISKS = {
    "st_replay": ST_REPLAY.read_bytes(),
    "v2": v2(E + [(b"README.TXT", 9, 77, 1)], date=20261011),
    "dupes": v1([(n, i, i * 10, i & 3) for i, n in enumerate([b"B", b"10", b"A", b"2", b"B", b"0", b"01", b"10"])]),
    "odd": v1([(n, i, i, 1) for i, n in enumerate(ODD_NAMES)]),
    "many": v1([(b"F%02d.RAW" % i, i, i, 1) for i in range(20)]),
    "empty": v1([]),
    "type_at_end": v1([(b"F%02d" % i, i, i, 7) for i in range(25)], size=0x618),
    "fat_past_end": v1([(b"F%02d" % i, i, i, 7) for i in range(26)], size=0x618),
    "short": v1(E)[:0x5FF],
    "magic": b"ZMDISX" + v1(E)[6:],
    "corrupt": v1(E, sum_=0x1111),
    "bootable": v1(E, sum_=0x1234),
}


@pytest.fixture(scope="module")
def disks() -> dict[str, Path]:
    WORK.mkdir(parents=True, exist_ok=True)
    out = {}
    for name, data in DISKS.items():
        out[name] = WORK / f"{name}.zmd"
        out[name].write_bytes(data)
    return out


@pytest.fixture(scope="module")
def zmd_dir_test() -> Path:
    exe = WORK / "zmd_dir_test"
    WORK.mkdir(parents=True, exist_ok=True)
    subprocess.run(["clang", "-std=c11", "-Wall", "-Werror", f"-I{FPGA / 'host'}", str(FPGA / "tests/tb/zmd_dir_test.c"),
                    "-o", str(exe)], check=True)  # fmt: skip
    return exe


def native(exe: Path, *args: str) -> str:
    return subprocess.run([str(exe), *args], capture_output=True, text=True, check=True).stdout.strip()


@pytest.mark.parametrize("name", list(DISKS))
def test_the_listing_is_the_browsers_byte_for_byte(name: str, disks: dict[str, Path], zmd_dir_test: Path) -> None:
    for ent, maxf in ((25, 12), (25, 3), (32, 40)):
        want = browser_list(disks[name], ent, maxf)
        assert native(zmd_dir_test, "list", str(disks[name]), str(ent), str(maxf), "0x100", "65536") == want


def test_st_replays_listing_is_its_two_files_in_fat_order(disks: dict[str, Path], zmd_dir_test: Path) -> None:
    n, records = native(zmd_dir_test, "list", str(disks["st_replay"]), "25", "12", "0x100", "65536").split()
    rec = bytes.fromhex(records)
    assert n == "2" and rec[:8] == b"BOOT.WSM" and rec[16] == 0 and int.from_bytes(rec[17:21], "little") == 9636
    assert rec[25:35] == b"SAMPLE.RAW" and rec[41] == 1 and rec[46:50] == bytes(4)  # a v1 disk: no date


def test_more_files_than_the_roms_cap_lists_only_the_cap(disks: dict[str, Path], zmd_dir_test: Path) -> None:
    n, records = native(zmd_dir_test, "list", str(disks["many"]), "25", "12", "0x100", "65536").split()
    assert n == "12" and len(records) == 2 * 12 * 25
    assert bytes.fromhex(records)[11 * 25 : 11 * 25 + 7] == b"F11.RAW"


def test_dupes_keep_their_first_place_and_index_names_come_first(disks: dict[str, Path], zmd_dir_test: Path) -> None:
    rec = bytes.fromhex(native(zmd_dir_test, "list", str(disks["dupes"]), "25", "12", "0x100", "65536").split()[1])
    names = [rec[i * 25 : i * 25 + 16].rstrip(b"\0") for i in range(len(rec) // 25)]
    assert names == [b"0", b"2", b"10", b"B", b"A", b"01"]
    assert rec[3 * 25 + 16] == 4 & 3  # "B": the second entry's values (index 4) in the first's place


def test_errors_where_the_browser_throws(disks: dict[str, Path], zmd_dir_test: Path) -> None:
    for name in ("fat_past_end", "short", "magic", "corrupt"):
        assert native(zmd_dir_test, "list", str(disks[name]), "25", "12", "0x100", "65536") == "err"
    assert browser_list(disks["st_replay"], 25, 12, ptr=65536 - 30) == "err"  # 2 records past the memory
    assert native(zmd_dir_test, "list", str(disks["st_replay"]), "25", "12", str(65536 - 30), "65536") == "err"
    assert native(zmd_dir_test, "list", str(disks["st_replay"]), "24", "12", "0x100", "65536") == "layout"


def test_a_fat_over_the_parsers_cap_is_refused(zmd_dir_test: Path) -> None:
    path = WORK / "huge.zmd"
    path.write_bytes(v1([(b"F%03d" % i, i, i, 1) for i in range(257)]))
    assert native(zmd_dir_test, "list", str(path), "25", "12", "0x100", "65536") == "toomany"


def test_a_cart_request_finds_the_file_the_browser_finds(disks: dict[str, Path], zmd_dir_test: Path) -> None:
    for name in (b"BOOT.WSM", b"SAMPLE.RAW", b"BOOT.WS", b"boot.wsm", b"", b"BOOT.WSM\0", b"\xef\xbb\xbfBOOT.WSM"):
        assert native(zmd_dir_test, "find", str(disks["st_replay"]), name.hex()) == browser_find(
            disks["st_replay"], name
        )
    assert native(zmd_dir_test, "find", str(disks["st_replay"]), "42" * 300) == "0"  # longer than any name
    assert native(zmd_dir_test, "boot", str(disks["bootable"])) == "bootable"
    assert native(zmd_dir_test, "boot", str(disks["st_replay"])) == "data"


def _step(text: str) -> list[str]:
    m = re.search(
        r"^\s*if \(!swapping && demo\.pollCartRequest\) \{\n[\s\S]*?^\s*diskDirSet = true;\n\s*\}\n", text, re.M
    )
    assert m, "no data-disk step"
    return [ln.strip() for ln in m.group(0).splitlines()]


def test_scene_hash_data_disk_step_is_the_browsers_text_for_text() -> None:
    js = (ROOT / "apps/scene_hash_disk.mjs").read_text()
    assert _step(js) == _step((ROOT / "docs/sealed-loader.js").read_text())


# GEM's floppy (40,30): a move, a click, the double-click pulse; then BOOT.WSM in the window
# (75,65, where the listing draws it) double-clicked: request 3.
SCRIPT = [(5, 40, 30, 0), (10, 40, 30, 1), (11, 40, 30, 0), (20, 40, 30, 2), (21, 40, 30, 0),
          (30, 75, 65, 0), (32, 75, 65, 2), (33, 75, 65, 0)]  # fmt: skip
ROUTED = ",".join(f"{f}:{x | y << 10 | b << 20:x}" for f, x, y, b in SCRIPT)
CALLS = [a for f, x, y, b in SCRIPT for a in ("--call", f"{f}:pointer:{x},{y},{b}")]


def _run(cmd: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, check=False)


@pytest.fixture(scope="module")
def gem_host() -> Path:
    subprocess.run(["make", "-s", "memmap", "build/host/gem/host"], cwd=FPGA, check=True, capture_output=True)
    return HOST


def test_native_host_opens_the_floppy_and_asks_for_boot_wsm_as_scene_hash_does(gem_host: Path) -> None:
    env = {**os.environ, "ZM_GLASS_POINTER": ROUTED}
    nat = _run([str(gem_host), "gem", "40", "5", "--data-disk", str(ST_REPLAY)], env)
    js = _run(["node", "apps/scene_hash.mjs", "docs/demo-gem.wasm", "40", "5", "--data-disk", str(ST_REPLAY), *CALLS])
    empty = _run([str(gem_host), "gem", "40", "5"], env)
    assert nat.returncode == js.returncode == empty.returncode == 0, nat.stderr + js.stderr
    hashes = [[s["hash"] for s in json.loads(r.stdout)["samples"]] for r in (nat, js, empty)]
    assert hashes[0] == hashes[1]
    assert hashes[0][:3] == hashes[2][:3] and hashes[0][4] != hashes[2][4]  # the listing, not "Drive A: is empty"
    assert 'cart request 3 "BOOT.WSM" (on the disk) at frame 32' in nat.stderr
    assert 'cart request 3 "BOOT.WSM" (on the disk)' in js.stderr


def test_a_bootable_disk_is_not_a_data_disk_for_either(gem_host: Path) -> None:
    gem_disk = str(ROOT / "docs/demo-gem.zmd")
    nat = _run([str(gem_host), "gem", "10", "5", "--data-disk", gem_disk])
    js = _run(["node", "apps/scene_hash.mjs", "docs/demo-gem.wasm", "10", "5", "--data-disk", gem_disk])
    assert nat.returncode == 2 and "bootable, not a data disk" in nat.stderr
    assert js.returncode != 0 and "bootable, not a data disk" in js.stderr
