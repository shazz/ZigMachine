"""The board's split images (decisions.md 2026-10-15): the system table's record and its
gate (tools/sys_abi.py), the images as files (tools/split_image.py), where the sim's DDR
image puts them (tools/ddr_init.py --cart), the card's shelf (tools/glass_shelf.py with a
system), and the one version rule the firmware (cycles/bsys_abi.h), the tools and glass
share. The board SoC sim run of the pair is tools/hp_sim_split.py's."""

from __future__ import annotations

import shutil
import struct
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(FPGA / "gen"))
import ddr_init
import glass_cart
import glass_map
import glass_shelf
import split_image
import sys_abi
import wasm_sig
from sys_abi_manifest import Manifest, bumped, check, digest, parse

V1 = 1 << 16
BASE = glass_map.CART_CPU_BASE + glass_cart.CART_IMG_AT


def lean_cart(version: int, size: int = 256, bss: int = 64) -> bytes:
    body = bytearray((i * 29 + 3) & 255 for i in range(size))
    struct.pack_into("<II", body, 0, glass_cart.CART_HDR_MAGIC, version)
    struct.pack_into("<I", body, glass_cart.CART_HDR_BSS_END_AT, BASE + size + bss)
    return bytes(body)


def system_image(version: int, count: int = 7) -> bytes:
    return b"crt0 and the rest" * 4 + struct.pack("<3I", glass_cart.SYS_MAGIC, version, count) + bytes(16)


def test_the_committed_table_is_todays_layout_under_its_version() -> None:
    m = parse(sys_abi.MANIFEST.read_text())
    assert check(m, sys_abi.current(m)) == []
    assert m.history[-1] == (m.version, digest(m.body))
    assert "env romReset rom void()" in m.body and "env hwVideoBase machine u32()" in m.body


def test_a_layout_changed_under_the_same_version_fails_and_the_bump_fixes_it() -> None:
    m = Manifest((1, 0), ["const X 0x1", "env a rom u32()"], [((1, 0), digest(["const X 0x1", "env a rom u32()"]))])
    grown = [*m.body, "env b rom void(u32)"]
    assert any("--update" in e for e in check(m, grown))
    assert bumped(m, grown).version == (1, 1) and check(bumped(m, grown), grown) == []
    retyped = ["const X 0x1", "env a rom f64()"]
    assert bumped(m, retyped).version == (2, 0)
    forged = Manifest((1, 0), retyped, m.history)
    assert any("bump the version" in e for e in check(forged, retyped))


def test_the_break_run_catches_every_unversioned_change() -> None:
    out = subprocess.run([sys.executable, str(FPGA / "tools/sys_abi.py"), "--break"], capture_output=True, text=True)
    assert out.returncode == 0, out.stdout
    assert out.stdout.count(" ok ") == 6 and "FAIL" not in out.stdout


def test_wasm_sig_reads_the_roms_exports_and_refuses_a_non_wasm_file() -> None:
    exports, imports = wasm_sig.signatures((ROOT / "docs/rom.wasm").read_bytes())
    assert exports["romReset"] == ("void", []) and imports["hwVideoBase"] == ("u32", [])
    with pytest.raises(ValueError, match="not a wasm module"):
        wasm_sig.signatures(b"\x7fELF" + bytes(8))


def test_the_system_file_round_trips_and_a_bad_head_is_refused() -> None:
    image = system_image(V1 | 2)
    assert split_image.table_version(image) == V1 | 2
    data = split_image.sys_file(image, V1 | 2)
    assert split_image.sys_unfile(data) == (V1 | 2, image)
    with pytest.raises(split_image.SplitError, match="does not check"):
        split_image.sys_unfile(data[:12] + bytes([data[12] ^ 1]) + data[13:])
    with pytest.raises(split_image.SplitError, match="runs into the cart"):
        split_image.sys_file(bytes(glass_cart.CART_IMG_AT + 8), V1)
    with pytest.raises(split_image.SplitError, match="2 tables"):
        split_image.table_version(image + image)


def test_a_cart_runs_on_its_major_and_any_later_minor_only() -> None:
    assert split_image.check_pair(V1 | 1, lean_cart(V1)).bss_end == glass_cart.CART_IMG_AT + 256 + 64
    for need in (V1 | 2, 2 << 16):
        with pytest.raises(split_image.SplitError, match="needs system table"):
            split_image.check_pair(V1 | 1, lean_cart(need))
    with pytest.raises(split_image.SplitError, match="no ZMCA header"):
        split_image.cart_header(b"\x13" * 64)


@pytest.mark.skipif(shutil.which("cc") is None, reason="a C compiler runs the firmware's rule")
def test_the_firmwares_rule_is_the_tools_rule(tmp_path: Path) -> None:
    vs = [0, 1, 2, V1, V1 | 1, V1 | 2, 2 << 16, (2 << 16) | 1]
    src = tmp_path / "abi.c"
    src.write_text('#include <stdio.h>\n#include "bsys_abi.h"\nint main(void) { unsigned v[] = {'
                   + ",".join(map(str, vs)) + "}; for (int i = 0; i < 8; i++) for (int j = 0; j < 8; j++) "
                   'printf("%d", bsys_abi_ok(v[i], v[j])); return 0; }\n')  # fmt: skip
    exe = tmp_path / "abi"
    subprocess.run(["cc", "-I", str(FPGA / "cycles"), str(src), "-o", str(exe)], check=True)
    want = "".join(str(int(split_image.abi_ok(n, h))) for n in vs for h in vs)
    assert subprocess.run([str(exe)], capture_output=True, text=True, check=True).stdout == want


def test_the_sim_image_puts_the_cart_at_its_place_and_the_disk_after_its_bss() -> None:
    system, cart = system_image(V1), lean_cart(V1)
    lines = ddr_init.init_lines(system, b"disk", glass_map.DISK_MAGIC, cart)
    at = lines.index(f"@{glass_cart.CART_IMG_AT // 8:x}")
    assert int(lines[at + 1], 16).to_bytes(8, "little") == cart[:8]
    disk_at = -(-(glass_cart.CART_IMG_AT + 256 + 64) // glass_map.DISK_ALIGN) * glass_map.DISK_ALIGN
    assert f"@{disk_at // 8:x}" in lines
    with pytest.raises(split_image.SplitError, match="runs into the cart"):
        ddr_init.init_lines(bytes(glass_cart.CART_IMG_AT + 8), None, cart=cart)


def _carts(tmp: Path, version: int) -> Path:
    for tag in ("tutorial", "gem"):
        (tmp / "carts" / tag).mkdir(parents=True)
        (tmp / "carts" / tag / "cart.bin").write_bytes(lean_cart(version))
    return tmp / "carts"


def test_the_split_card_carries_the_system_once_and_lean_carts(tmp_path: Path) -> None:
    sysbin = tmp_path / "sys.bin"
    sysbin.write_bytes(system_image(V1))
    rows = dict(glass_shelf.build_shelf(tmp_path / "sd", _carts(tmp_path, V1), tmp_path / "none.h",
                                        ("tutorial",), system=sysbin))  # fmt: skip
    assert rows["zigmachine/system.rv32"].endswith("(table 1.0)")
    assert rows["zigmachine/demo-tutorial.zmd"].endswith("carts/tutorial/cart.bin")
    packed = tmp_path / "sd" / "system.rv32"
    subprocess.run([glass_shelf.zx0unpack(), packed, tmp_path / "sys.raw"], check=True, capture_output=True)
    assert split_image.sys_unfile((tmp_path / "sys.raw").read_bytes()) == (V1, system_image(V1))
    assert sorted(p.name for p in (tmp_path / "sd").iterdir()) == [
        "demo-tutorial.zmd", "kos", "shelf.txt", "system.rv32"]  # fmt: skip: GEM is KOS's desktop, kos/desktop.rv32


def test_a_card_never_carries_a_cart_its_system_refuses_or_lacks(tmp_path: Path) -> None:
    sysbin = tmp_path / "sys.bin"
    sysbin.write_bytes(system_image(V1))
    rows = dict(glass_shelf.build_shelf(tmp_path / "sd", _carts(tmp_path, V1 | 1), tmp_path / "none.h",
                                        ("tutorial", "stniccc"), system=sysbin))  # fmt: skip
    assert rows["zigmachine/demo-tutorial.zmd"].startswith("REFUSED:") and "needs system table 1.1" in rows[
        "zigmachine/demo-tutorial.zmd"]  # fmt: skip
    assert rows["zigmachine/demo-stniccc.zmd"].endswith("make -C fpga split-cart CART=stniccc")
    assert not (tmp_path / "sd" / "demo-tutorial.zmd").exists()
