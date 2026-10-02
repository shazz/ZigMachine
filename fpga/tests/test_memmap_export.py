"""The exported memory map must agree with machine/sdk/memmap.zig, the file the
wasm machine and every cart were built against. Values are pinned here from
memmap.zig's own comments, so an export that drifts (or a bad reflection) fails.
"""

import re
from pathlib import Path

GEN = Path(__file__).resolve().parent.parent / "gen"

# name -> value, as memmap.zig documents them
PINNED = {
    "PHYSICAL_WIDTH": 400,
    "PHYSICAL_HEIGHT": 280,
    "RASTER_WIDTH": 800,
    "RASTER_HEIGHT": 280,
    "PAL_BYTES": 1024,
    "OFF_PAL": 0x100,
    "OFF_VRAM": 0x1100,
    "REG_FRAME": 0x30,
    "FULLSCREEN_FB_BYTES": 112000,
}


def _python_map() -> dict[str, int]:
    text = (GEN / "memmap.py").read_text()
    return {k: int(v, 16) for k, v in re.findall(r"^(\w+) = (0x[0-9A-F]+)$", text, re.MULTILINE)}


def _verilog_map() -> dict[str, int]:
    text = (GEN / "memmap.vh").read_text()
    pattern = r"^localparam integer ZM_(\w+) = 32'h([0-9A-F]+);$"
    return {k: int(v, 16) for k, v in re.findall(pattern, text, re.MULTILINE)}


def test_exported_python_map_matches_memmap_zig_values() -> None:
    exported = _python_map()
    assert {k: exported[k] for k in PINNED} == PINNED


def test_verilog_and_python_exports_carry_the_same_constants() -> None:
    assert _verilog_map() == _python_map()


def test_export_includes_derived_offsets_not_just_literals() -> None:
    m = _python_map()
    assert m["OFF_PFB"] == m["OFF_VRAM"] + m["VRAM_BYTES"]
