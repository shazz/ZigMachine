"""The native host's generated half (tools/host_gen.py, tools/wasm_info.py) must
make the same decisions apps/scene_hash.mjs makes. The high-water port is checked
against the JS itself on every module the host runs; the import resolution and the
LinkError refusal are checked on hand-built inputs, including the failing cases.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))

import host_gen
import wasm_info

MODULES = sorted(ROOT.glob("docs/demo-*.wasm")) + [ROOT / "docs/rom.wasm", ROOT / "docs/machine-video.wasm"]


def _js_high_waters(paths: list[Path]) -> dict[str, int | None]:
    script = (
        "const m = await import(process.argv[1]); const fs = await import('node:fs');"
        "const out = {}; for (const p of process.argv.slice(2)) out[p] = m.cartHighWater(fs.readFileSync(p));"
        "console.log(JSON.stringify(out));"
    )
    hiwater = (ROOT / "docs/wasm_hiwater.js").as_uri()
    cmd = ["node", "--input-type=module", "-e", script, hiwater, *map(str, paths)]
    return json.loads(subprocess.run(cmd, check=True, capture_output=True, text=True).stdout)


@pytest.mark.skipif(shutil.which("node") is None, reason="node runs the JS reference")
def test_high_water_matches_wasm_hiwater_js_on_every_module() -> None:
    expected = _js_high_waters(MODULES)
    got = {str(p): wasm_info.high_water(p.read_bytes()) for p in MODULES}
    assert got == expected


def test_high_water_of_a_module_without_globals_or_data_is_none() -> None:
    assert wasm_info.high_water(b"\0asm\1\0\0\0") is None


def test_high_water_rejects_a_non_wasm_file() -> None:
    with pytest.raises(ValueError, match="not a wasm module"):
        wasm_info.high_water(b"\x7fELF\1\0\0\0")


def test_memory_import_reads_the_shared_112_page_limits() -> None:
    assert wasm_info.memory_import((ROOT / "docs/rom.wasm").read_bytes()) == (112, 112)


def test_link_check_refuses_a_module_whose_max_is_below_the_shared_memory(tmp_path: Path) -> None:
    # (module "env" "memory" (memory 48 48)): the JS host's LinkError case (demo-audio.wasm)
    imp = b"\x01\x03env\x06memory\x02\x01\x30\x30"
    wasm = tmp_path / "small.wasm"
    wasm.write_bytes(b"\0asm\1\0\0\0\x02" + bytes([len(imp)]) + imp)
    with pytest.raises(SystemExit, match="LinkError"):
        host_gen.link_check({"cart": wasm}, 112)


EXPORTS = {"rom": {"guiText": ("void", ["u32"])}, "machine": {"hwBlit": ("void", [])}, "cart": {}}


def test_resolve_prefers_rom_then_the_machine_list_then_a_stub() -> None:
    assert host_gen.resolve("guiText", {"cart"}, EXPORTS) == "rom"
    assert host_gen.resolve("hwBlit", {"cart", "rom"}, EXPORTS) == "machine"
    assert host_gen.resolve("hwClear", {"cart"}, EXPORTS) is None  # not in scene_hash's list
    assert host_gen.resolve("hblDispatch", {"machine"}, EXPORTS) == "cart"


def test_resolve_refuses_a_cart_that_imports_hbldispatch() -> None:
    with pytest.raises(SystemExit, match="hblDispatch"):
        host_gen.resolve("hblDispatch", {"machine", "cart"}, EXPORTS)


def test_stub_returns_what_undefined_converts_to() -> None:
    assert "return 0;" in host_gen.forwarder("diskReadBlock", "u32", ["u32", "u32"], None, EXPORTS)
    assert "return NAN;" in host_gen.forwarder("f", "f32", [], None, EXPORTS)
    assert "wasm_rt_trap" in host_gen.forwarder("g", "u64", [], None, EXPORTS)


def test_forwarder_refuses_a_signature_mismatch() -> None:
    with pytest.raises(SystemExit, match="does not match"):
        host_gen.forwarder("guiText", "void", ["u32", "u32"], "rom", EXPORTS)


def test_forwarder_wraps_the_hbl_dispatch_and_the_blitter_in_span_hooks() -> None:
    exports = {"machine": {"hwBlit": ("void", [])}, "cart": {"hblDispatch": ("void", ["u32"])}, "rom": {}}
    blit = host_gen.forwarder("hwBlit", "void", [], "machine", exports)
    hbl = host_gen.forwarder("hblDispatch", "void", ["u32"], "cart", exports)
    assert "HOST_SPAN_ENTER(HOST_SPAN_BLIT); w2c_machine_hwBlit(&e->machine); HOST_SPAN_LEAVE();" in blit
    assert "HOST_SPAN_ENTER(HOST_SPAN_CART); w2c_cart_hblDispatch(&e->cart, a0); HOST_SPAN_LEAVE();" in hbl
    assert "HOST_SPAN" not in host_gen.forwarder("guiText", "void", ["u32"], "rom", EXPORTS)


def test_forwarder_refuses_a_span_that_returns_a_value() -> None:
    exports = {"machine": {"hwBlit": ("u32", [])}, "cart": {}, "rom": {}}
    with pytest.raises(SystemExit, match="span"):
        host_gen.forwarder("hwBlit", "u32", [], "machine", exports)
