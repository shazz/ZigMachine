#!/usr/bin/env python3
"""Convert shazz's Codef "UnionDemoCracktro" efmain_intro placement-animation
strips for ZigMachine.

Mechanical, idempotent conversion. Re-run any time; overwrites its own
outputs deterministically from the checked-in source assets.

Usage:
    python3 tools/union_intro_assets.py

Source:
    assets/oldies/UnionDemoCracktro/intro/gfx/efmain_intro/back_layer{0..16}.png

Output:
    apps/assets/screens/union_intro/placement/
        back_layer{0..16}.raw   half-scale indexed pixels, one shared palette
        placement.pal           256*4 RGBA merged palette, index 0 transparent

All 17 strips share ONE 256-entry palette (a ZigMachine plane has one
palette) so they can all draw on the same fullscreen plane 0. Index 0 is
reserved transparent. Target art is half-scale (Codef canvas 768x540 ->
ZigMachine 400x280 fullscreen plane, same convention as union_main_assets.py).
"""

from pathlib import Path
from typing import Optional

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC_GFX = ROOT / "assets/oldies/UnionDemoCracktro/intro/gfx/efmain_intro"
OUT_DIR = ROOT / "apps/assets/screens/union_intro/placement"

NBLAYERS = 17
MAX_SLOT = 255  # last valid palette index

RGB = tuple[int, int, int]
Pixels = list[Optional[RGB]]


def report(name: str, path: Path) -> None:
    size = path.stat().st_size
    print(f"  -> {name}: {path.relative_to(ROOT)} ({size} bytes)")


def half_scale_nearest(im: Image.Image) -> Image.Image:
    return im.resize((im.width // 2, im.height // 2), Image.NEAREST)


def load_pixels(path: Path) -> tuple[tuple[int, int], Pixels]:
    """Half-scale a source PNG and return (size, pixels) with None = transparent."""
    with Image.open(path) as im:
        im = half_scale_nearest(im)
        size = im.size

        if im.mode == "P":
            trans_idx = im.info.get("transparency")
            pal = im.getpalette()
            assert pal is not None
            data = list(im.getdata())
            pixels: Pixels = []
            for v in data:
                if trans_idx is not None and v == trans_idx:
                    pixels.append(None)
                else:
                    pixels.append((pal[v * 3], pal[v * 3 + 1], pal[v * 3 + 2]))
            return size, pixels

        if im.mode == "RGBA":
            data = list(im.getdata())
            pixels = [None if a < 128 else (r, g, b) for (r, g, b, a) in data]
            return size, pixels

        raise RuntimeError(f"{path.name}: unsupported mode {im.mode}")


class PaletteMerger:
    """One shared 256-entry RGBA palette across all 17 strips; index 0 is
    reserved transparent. Each strip gets its OWN dedicated, non-overlapping
    index range (colors are deduped only WITHIN a strip, never reused across
    strips) — this costs a few extra palette slots but means a FADE strip's
    palette range can be alpha-scaled without touching any other strip's
    colors (see placement.zig's applyFade)."""

    def __init__(self) -> None:
        self.next_index = 1
        self.remapped: dict[str, tuple[tuple[int, int], bytes]] = {}
        self.ranges: dict[str, tuple[int, int]] = {}  # name -> inclusive [min,max]
        self.palette: dict[int, RGB] = {}

    def add(self, name: str, size: tuple[int, int], pixels: Pixels) -> None:
        color_to_index: dict[RGB, int] = {}
        start = self.next_index
        out = bytearray(len(pixels))
        for i, px in enumerate(pixels):
            if px is None:
                out[i] = 0
                continue
            idx = color_to_index.get(px)
            if idx is None:
                if self.next_index > MAX_SLOT:
                    raise RuntimeError(f"palette overflow adding '{name}' (>{MAX_SLOT} colors)")
                idx = self.next_index
                color_to_index[px] = idx
                self.palette[idx] = px
                self.next_index += 1
            out[i] = idx
        self.remapped[name] = (size, bytes(out))
        self.ranges[name] = (start, self.next_index - 1)

    def palette_bytes(self) -> bytes:
        pal = bytearray(256 * 4)  # index 0 stays (0,0,0,0) = transparent
        for idx, color in self.palette.items():
            pal[idx * 4 : idx * 4 + 4] = bytes([color[0], color[1], color[2], 255])
        return bytes(pal)

    def n_colors_used(self) -> int:
        return len(self.palette)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("=== efmain_intro placement strips (17 back_layer*.png, half-scale, shared palette) ===")
    merger = PaletteMerger()
    for i in range(NBLAYERS):
        src = SRC_GFX / f"back_layer{i}.png"
        if not src.exists():
            raise RuntimeError(f"missing source asset: {src}")
        size, pixels = load_pixels(src)
        merger.add(f"back_layer{i}", size, pixels)

    dims: list[tuple[int, int]] = []
    ranges: list[tuple[int, int]] = []
    for i in range(NBLAYERS):
        size, data = merger.remapped[f"back_layer{i}"]
        raw_out = OUT_DIR / f"back_layer{i}.raw"
        raw_out.write_bytes(data)
        lo, hi = merger.ranges[f"back_layer{i}"]
        report(f"back_layer{i}.raw ({size[0]}x{size[1]}, palette [{lo}..{hi}])", raw_out)
        dims.append(size)
        ranges.append((lo, hi))

    pal_out = OUT_DIR / "placement.pal"
    pal_out.write_bytes(merger.palette_bytes())
    report("placement.pal (256x4)", pal_out)
    print(f"  placement: {merger.n_colors_used()} colors used (of {MAX_SLOT} available + transparent index 0)")

    zig_out = OUT_DIR / "placement_dims.zig"
    dims_lit = ", ".join(f".{{ {w}, {h} }}" for w, h in dims)
    ranges_lit = ", ".join(f".{{ {lo}, {hi} }}" for lo, hi in ranges)
    zig_out.write_text(
        "// Generated by tools/union_intro_assets.py from "
        "assets/oldies/UnionDemoCracktro/intro/gfx/efmain_intro/back_layer*.png — do not hand-edit.\n"
        "//\n"
        "// STRIP_DIMS[i]   = .{ width, height } of back_layer{i}.raw (half-scale).\n"
        "// STRIP_RANGE[i]  = .{ min, max } inclusive palette index owned exclusively\n"
        "//                   by strip i in placement.pal (no cross-strip color reuse,\n"
        "//                   so a FADE strip's range can be alpha-scaled in isolation).\n\n"
        f"pub const STRIP_DIMS = [{NBLAYERS}][2]u16{{ {dims_lit} }};\n"
        f"pub const STRIP_RANGE = [{NBLAYERS}][2]u8{{ {ranges_lit} }};\n"
    )
    report("placement_dims.zig", zig_out)


if __name__ == "__main__":
    main()
