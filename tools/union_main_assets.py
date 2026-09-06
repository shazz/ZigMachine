#!/usr/bin/env python3
"""Convert shazz's Codef "UnionDemoCracktro" main-screen assets for ZigMachine.

Mechanical, idempotent conversion. Re-run any time; every step overwrites its
own outputs deterministically from the checked-in source assets.

Usage:
    python3 tools/union_main_assets.py

Outputs:
    apps/assets/screens/union_main/   raw + merged per-plane palette + map data + union_maps.zig
    docs/music/union/                 depacked .ymraw YM chiptunes

All target art is half-scale (Codef canvas 768x540 -> ZigMachine 400x280
fullscreen plane). A ZigMachine plane has ONE 256-entry palette, so every
asset drawn on the same plane must share ONE merged palette with remapped
indices (index 0 = transparent, reserved). See PLANES below for the grouping.
"""

import re
import struct
import subprocess
import sys
from pathlib import Path
from typing import Optional

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC_GFX = ROOT / "assets/oldies/UnionDemoCracktro/intro/gfx/efmain"
SRC_JS = ROOT / "assets/oldies/UnionDemoCracktro/intro/efmain.js"
SRC_ZIK = ROOT / "assets/oldies/UnionDemoCracktro/intro/zik"

OUT_SCREEN = ROOT / "apps/assets/screens/union_main"
OUT_MUSIC = ROOT / "docs/music/union"

RGB = tuple[int, int, int]
Pixels = list[Optional[RGB]]

MAX_SLOT = 255  # last valid palette index


def report(name: str, path: Path) -> None:
    size = path.stat().st_size
    print(f"  -> {name}: {path.relative_to(ROOT)} ({size} bytes)")


def half_scale_nearest(im: Image.Image) -> Image.Image:
    return im.resize((im.width // 2, im.height // 2), Image.NEAREST)


# ---------------------------------------------------------------------------
# generic per-asset pixel loading -> list[Optional[(r,g,b)]] (None = transparent)
# ---------------------------------------------------------------------------


def load_pixels_p_or_rgba(path: Path, expected_src_size: tuple[int, int]) -> tuple[tuple[int, int], Pixels]:
    with Image.open(path) as im:
        if im.size != expected_src_size:
            raise RuntimeError(f"{path.name}: expected size {expected_src_size}, got {im.size}")
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


def load_rasters_pixels(budget: int) -> tuple[tuple[int, int], Pixels, int]:
    """Crop rows 0-63, half-scale, quantize RGB to <=budget colors (no transparency)."""
    src = SRC_GFX / "rasters.png"
    with Image.open(src) as im:
        if im.size[0] != 768:
            raise RuntimeError(f"rasters.png: expected width 768, got {im.size[0]}")
        if im.height < 64:
            raise RuntimeError(f"rasters.png: expected height >= 64, got {im.height}")
        cropped = im.crop((0, 0, 768, 64)).convert("RGB")
        scaled = half_scale_nearest(cropped)
        if scaled.size != (384, 32):
            raise RuntimeError(f"rasters.png: expected scaled 384x32, got {scaled.size}")

        quantized = scaled.quantize(colors=budget, method=Image.MEDIANCUT, dither=Image.NONE)
        pal = quantized.getpalette()
        assert pal is not None
        data = list(quantized.getdata())
        pixels: Pixels = [(pal[v * 3], pal[v * 3 + 1], pal[v * 3 + 2]) for v in data]
        n_colors = len(set(pixels))
        return quantized.size, pixels, n_colors


# ---------------------------------------------------------------------------
# plane palette merging
# ---------------------------------------------------------------------------


class PlaneMerger:
    """Builds one shared 256-entry RGBA palette across several assets, remapping
    each asset's pixel stream from its own colors to the merged index space.
    Index 0 is always transparent/reserved. `reserved` pre-claims specific
    indices for out-of-band colors (e.g. the fontsIn ink color on plane2)."""

    def __init__(self, plane_name: str, reserved: Optional[dict[int, RGB]] = None):
        self.plane_name = plane_name
        self.reserved = dict(reserved or {})
        self.color_to_index: dict[RGB, int] = {}
        self.next_index = 1
        self.remapped: dict[str, tuple[tuple[int, int], bytes]] = {}

    def _reserved_indices(self) -> set[int]:
        return set(self.reserved.keys())

    def add(self, name: str, size: tuple[int, int], pixels: Pixels) -> None:
        reserved_indices = self._reserved_indices()
        out = bytearray(len(pixels))
        for i, px in enumerate(pixels):
            if px is None:
                out[i] = 0
                continue
            idx = self.color_to_index.get(px)
            if idx is None:
                while self.next_index in reserved_indices:
                    self.next_index += 1
                if self.next_index > MAX_SLOT:
                    raise RuntimeError(f"{self.plane_name}: palette overflow adding '{name}' (>{MAX_SLOT} colors)")
                idx = self.next_index
                self.color_to_index[px] = idx
                self.next_index += 1
            out[i] = idx
        self.remapped[name] = (size, bytes(out))

    def palette_bytes(self) -> bytes:
        pal = bytearray(256 * 4)  # index 0 stays (0,0,0,0) = transparent
        for color, idx in self.color_to_index.items():
            pal[idx * 4 : idx * 4 + 4] = bytes([color[0], color[1], color[2], 255])
        for idx, color in self.reserved.items():
            pal[idx * 4 : idx * 4 + 4] = bytes([color[0], color[1], color[2], 255])
        return bytes(pal)

    def n_colors_used(self) -> int:
        return len(self.color_to_index) + len(self.reserved)


# ---------------------------------------------------------------------------
# plane 0: world/background — layer_b1, layer_b2, clouds1, clouds2, clouds3,
#          tileset, gradtiles (gradTiles0.png only; RED_A/RED_B reported below)
# ---------------------------------------------------------------------------

PLANE0_SIMPLE = [
    ("layer_b1", "layer_b1.png", (768, 32), (384, 16)),
    ("layer_b2", "layer_b2.png", (768, 32), (384, 16)),
    ("clouds1", "clouds1.png", (640, 32), (320, 16)),
    ("clouds2", "clouds2.png", (640, 32), (320, 16)),
    ("clouds3", "clouds3.png", (640, 32), (320, 16)),
    ("tileset", "tileset.png", (544, 224), (272, 112)),
    ("gradtiles", "gradTiles0.png", (256, 416), (128, 208)),
]


def convert_plane0() -> None:
    print("\n=== plane 0 (world/background): layer_b1, layer_b2, clouds1, clouds2, clouds3, tileset, gradtiles ===")
    merger = PlaneMerger("plane0")

    gradtiles_colors_before = None
    for outbase, fname, exp_src, exp_out in PLANE0_SIMPLE:
        size, pixels = load_pixels_p_or_rgba(SRC_GFX / fname, exp_src)
        if size != exp_out:
            raise RuntimeError(f"{fname}: expected scaled size {exp_out}, got {size}")
        if outbase == "gradtiles":
            gradtiles_colors_before = set(merger.color_to_index.keys())
        merger.add(outbase, size, pixels)

    pal_out = OUT_SCREEN / "p0.pal"
    pal_out.write_bytes(merger.palette_bytes())

    for outbase, (size, data) in merger.remapped.items():
        raw_out = OUT_SCREEN / f"{outbase}.raw"
        raw_out.write_bytes(data)
        report(f"{outbase}.raw ({size[0]}x{size[1]})", raw_out)
    report("p0.pal (256x4)", pal_out)
    print(f"  plane0: {merger.n_colors_used()} colors used (of 254 available + transparent index 0)")

    red_a = merger.color_to_index.get((224, 0, 0))
    red_b = merger.color_to_index.get((255, 0, 0))
    print(f"  gradtiles RED_A (224,0,0) -> palette index {red_a}")
    print(f"  gradtiles RED_B (255,0,0) -> palette index {red_b}")


# ---------------------------------------------------------------------------
# plane 1: actors — sprites, credits
# ---------------------------------------------------------------------------

PLANE1_SIMPLE = [
    ("sprites", "sprites.png", (448, 56), (224, 28)),
]


def load_white_glyph_mask(path: Path, expected_src: tuple[int, int], exp_out: tuple[int, int]) -> tuple[tuple[int, int], Pixels]:
    """font_credits.png is a clean single-colour white glyph on a black field, but
    the source palette carries the field as BOTH idx 0 and an opaque idx 255 black.
    Keep ONLY the white glyph pixels as ink (everything else transparent) so the
    mask stays one ink index — otherwise the black field prints as a second ink and
    fattens every glyph (the "blurry, multiple white prints" artefact)."""
    with Image.open(path) as im:
        if im.size != expected_src:
            raise RuntimeError(f"{path.name}: expected size {expected_src}, got {im.size}")
        rgb = half_scale_nearest(im.convert("RGB"))
    if rgb.size != exp_out:
        raise RuntimeError(f"{path.name}: expected scaled {exp_out}, got {rgb.size}")
    pixels: Pixels = [(r, g, b) if (r > 160 and g > 160 and b > 160) else None for (r, g, b) in rgb.getdata()]
    return rgb.size, pixels


def convert_plane1() -> None:
    print("\n=== plane 1 (actors): sprites, credits ===")
    merger = PlaneMerger("plane1")

    for outbase, fname, exp_src, exp_out in PLANE1_SIMPLE:
        size, pixels = load_pixels_p_or_rgba(SRC_GFX / fname, exp_src)
        if size != exp_out:
            raise RuntimeError(f"{fname}: expected scaled size {exp_out}, got {size}")
        merger.add(outbase, size, pixels)

    # credits font: clean white-only 1-ink mask (see load_white_glyph_mask).
    size, pixels = load_white_glyph_mask(SRC_GFX / "font_credits.png", (576, 60), (288, 30))
    merger.add("credits", size, pixels)

    pal_out = OUT_SCREEN / "p1.pal"
    pal_out.write_bytes(merger.palette_bytes())

    for outbase, (size, data) in merger.remapped.items():
        raw_out = OUT_SCREEN / f"{outbase}.raw"
        raw_out.write_bytes(data)
        report(f"{outbase}.raw ({size[0]}x{size[1]})", raw_out)
    report("p1.pal (256x4)", pal_out)
    print(f"  plane1: {merger.n_colors_used()} colors used (of 254 available + transparent index 0)")


# ---------------------------------------------------------------------------
# plane 2: scroller — fontsout, rasters; index 255 reserved for the fontsIn
#          fill-mask ink color
# ---------------------------------------------------------------------------

FONTSIN_INK_RGB: RGB = (33, 32, 107)  # sampled from fontsIn.png's opaque glyph pixels


def convert_plane2() -> None:
    print("\n=== plane 2 (scroller): fontsout, rasters (index 255 reserved for fontsIn ink) ===")
    merger = PlaneMerger("plane2", reserved={255: FONTSIN_INK_RGB})

    size, pixels = load_pixels_p_or_rgba(SRC_GFX / "fontsOut.png", (640, 384))
    if size != (320, 192):
        raise RuntimeError(f"fontsOut.png: expected scaled 320x192, got {size}")
    merger.add("fontsout", size, pixels)

    fontsout_colors = merger.n_colors_used() - 1  # exclude the reserved index255
    budget = MAX_SLOT - 1 - fontsout_colors - 1  # -index0, -fontsout colors, -reserved 255
    budget = min(budget, 240)
    size, pixels, n_raster_colors = load_rasters_pixels(budget)
    merger.add("rasters", size, pixels)

    pal_out = OUT_SCREEN / "p2.pal"
    pal_out.write_bytes(merger.palette_bytes())

    for outbase, (sz, data) in merger.remapped.items():
        raw_out = OUT_SCREEN / f"{outbase}.raw"
        raw_out.write_bytes(data)
        report(f"{outbase}.raw ({sz[0]}x{sz[1]})", raw_out)
    report("p2.pal (256x4)", pal_out)
    print(f"  plane2: {merger.n_colors_used()} colors used (of 254 available + reserved index 255)")
    print(f"  plane2: fontsout contributed {fontsout_colors} colors, rasters quantized to {n_raster_colors} (budget was {budget})")
    print(f"  plane2: index 255 reserved for fontsIn ink color {FONTSIN_INK_RGB}")


# ---------------------------------------------------------------------------
# fontsIn.png -> 1-bit packed glyph mask (independent of plane palettes)
# ---------------------------------------------------------------------------


def convert_fontsin() -> None:
    print("\n=== fontsIn.png -> 1-bit packed glyph mask ===")
    src = SRC_GFX / "fontsIn.png"
    with Image.open(src) as im:
        if im.size != (640, 384):
            raise RuntimeError(f"fontsIn.png: expected 640x384, got {im.size}")
        rgba = im.convert("RGBA")
        scaled = half_scale_nearest(rgba)
        if scaled.size != (320, 192):
            raise RuntimeError(f"fontsIn.png: expected scaled 320x192, got {scaled.size}")

        colors = scaled.getcolors(maxcolors=100000)
        if colors is None or len(colors) > 2:
            raise RuntimeError(f"fontsIn.png: expected a 2-color (glyph/background) mask, got {colors}")

        w, h = scaled.size
        n_bits = w * h
        n_bytes = (n_bits + 7) // 8
        packed = bytearray(n_bytes)

        px = scaled.load()
        bit_index = 0
        for y in range(h):
            for x in range(w):
                _, _, _, a = px[x, y]
                if a >= 128:
                    byte_i = bit_index // 8
                    bit_i = 7 - (bit_index % 8)  # MSB-first
                    packed[byte_i] |= 1 << bit_i
                bit_index += 1

        out_path = OUT_SCREEN / "fontsin.bits"
        out_path.write_bytes(bytes(packed))
        report(f"fontsin.bits ({w}x{h} px, 1bpp, {n_bytes} bytes)", out_path)
        print("  packing: MSB-first, row-major over the whole 320x192 image; "
              "bit=1 means glyph ink (alpha>=128 in the half-scaled RGBA source), bit=0 background")
        print(f"  ink color for this mask on plane2 is reserved at palette index 255: {FONTSIN_INK_RGB}")


# ---------------------------------------------------------------------------
# map data scraped from efmain.js
# ---------------------------------------------------------------------------


def parse_int_rows(js_text: str, var_name: str) -> list[list[int]]:
    """Extract `this.<var_name> = [ [..], [..], ... ];` or `= [ ints ];` as rows of ints."""
    pattern = re.compile(r"this\." + re.escape(var_name) + r"\s*=\s*\[(.*?)\];", re.S)
    m = pattern.search(js_text)
    if not m:
        raise RuntimeError(f"could not find `this.{var_name} = [...]` in efmain.js")
    body = m.group(1)

    row_pattern = re.compile(r"\[([^\[\]]*)\]")
    row_matches = row_pattern.findall(body)
    if row_matches:
        rows = []
        for row_text in row_matches:
            rows.append([int(v) for v in row_text.split(",") if v.strip() != ""])
        return rows
    flat = [int(v) for v in body.split(",") if v.strip() != ""]
    return [flat]


def parse_pos_doors(js_text: str) -> list[int]:
    m = re.search(r"this\.posDoors\s*=\s*\[([^\]]*)\];", js_text)
    if not m:
        raise RuntimeError("could not find `this.posDoors = [...]` in efmain.js")
    return [int(v) for v in m.group(1).split(",") if v.strip() != ""]


def convert_maps() -> None:
    print("\n=== map data scraped from efmain.js ===")
    js_text = SRC_JS.read_text()

    world_rows = parse_int_rows(js_text, "world")
    anim_rows = parse_int_rows(js_text, "anim")
    clouds_rows = parse_int_rows(js_text, "worldClouds")
    pos_doors = parse_pos_doors(js_text)

    def verify(name: str, rows: list[list[int]], expected_rows: int, expected_cols: int) -> None:
        if len(rows) != expected_rows:
            raise RuntimeError(f"{name}: expected {expected_rows} rows, got {len(rows)}")
        for i, row in enumerate(rows):
            if len(row) != expected_cols:
                raise RuntimeError(
                    f"{name}: row {i} has {len(row)} values, expected {expected_cols} (STOPPING, not padding)"
                )
            for v in row:
                if not (0 <= v <= 199):
                    raise RuntimeError(f"{name}: row {i} has out-of-range value {v}")

    verify("world", world_rows, 9, 802)
    verify("anim", anim_rows, 5, 802)
    verify("worldClouds", clouds_rows, 1, 802)

    if len(pos_doors) != 18:
        raise RuntimeError(f"posDoors: expected 18 values, got {len(pos_doors)}")

    print(f"  world:  {len(world_rows)} rows x {len(world_rows[0])} cols (verified)")
    print(f"  anim:   {len(anim_rows)} rows x {len(anim_rows[0])} cols (verified)")
    print(f"  clouds: {len(clouds_rows)} row  x {len(clouds_rows[0])} cols (verified)")
    print(f"  posDoors ({len(pos_doors)}): {pos_doors}")

    world_bytes = bytes(v for row in world_rows for v in row)
    anim_bytes = bytes(v for row in anim_rows for v in row)
    clouds_bytes = bytes(clouds_rows[0])

    world_out = OUT_SCREEN / "world.dat"
    anim_out = OUT_SCREEN / "anim.dat"
    clouds_out = OUT_SCREEN / "clouds.dat"

    world_out.write_bytes(world_bytes)
    anim_out.write_bytes(anim_bytes)
    clouds_out.write_bytes(clouds_bytes)

    if len(world_bytes) != 9 * 802:
        raise RuntimeError(f"world.dat: expected {9*802} bytes, got {len(world_bytes)}")
    if len(anim_bytes) != 5 * 802:
        raise RuntimeError(f"anim.dat: expected {5*802} bytes, got {len(anim_bytes)}")
    if len(clouds_bytes) != 802:
        raise RuntimeError(f"clouds.dat: expected 802 bytes, got {len(clouds_bytes)}")

    report("world.dat (9x802)", world_out)
    report("anim.dat (5x802)", anim_out)
    report("clouds.dat (1x802)", clouds_out)

    zig_out = OUT_SCREEN / "union_maps.zig"
    pos_doors_lit = ", ".join(str(v) for v in pos_doors)
    zig_out.write_text(
        "// Generated by tools/union_main_assets.py from "
        "assets/oldies/UnionDemoCracktro/intro/efmain.js — do not hand-edit.\n\n"
        "pub const WORLD_W: usize = 802;\n"
        "pub const WORLD_ROWS: usize = 9;\n"
        "pub const ANIM_ROWS: usize = 5;\n"
        f"pub const POS_DOORS = [_]u16{{ {pos_doors_lit} }};\n"
    )
    report("union_maps.zig", zig_out)


# ---------------------------------------------------------------------------
# music (YM depack via 7z, LHA lh5)
# ---------------------------------------------------------------------------

YM_FILES = [
    "SharpnessBuzztone.ym",
    "150mph.ym",
    "Androids.ym",
    "Drooling.ym",
    "Lap33.ym",
    "Reality.ym",
]


def convert_music() -> None:
    print("\n=== YM music depack (LHA lh5 -> raw YM stream) ===")

    have_7z = subprocess.run(["which", "7z"], capture_output=True).returncode == 0
    if not have_7z:
        print("  7z not found on PATH — skipping all YM depacking (report only, no fabricated output)")
        return

    for fname in YM_FILES:
        src = SRC_ZIK / fname
        if not src.exists():
            print(f"  SKIP {fname}: source not found at {src.relative_to(ROOT)}")
            continue

        out_name = Path(fname).stem + ".ymraw"
        out_path = OUT_MUSIC / out_name

        proc = subprocess.run(["7z", "e", "-so", str(src)], capture_output=True, cwd=ROOT)
        if proc.returncode != 0:
            print(f"  FAIL {fname}: 7z exited {proc.returncode}: {proc.stderr.decode(errors='replace')[:200]}")
            continue

        data = proc.stdout
        magic = data[:4]
        if magic not in (b"YM5!", b"YM6!"):
            print(f"  FAIL {fname}: depacked but bad magic {magic!r} (not writing output)")
            continue

        out_path.write_bytes(data)
        report(f"{out_name} (magic {magic.decode()})", out_path)


# ---------------------------------------------------------------------------


def main() -> None:
    OUT_SCREEN.mkdir(parents=True, exist_ok=True)
    OUT_MUSIC.mkdir(parents=True, exist_ok=True)

    convert_plane0()
    convert_plane1()
    convert_plane2()
    convert_fontsin()
    convert_maps()
    convert_music()

    print("\n=== apps/assets/screens/union_main/ ===")
    for p in sorted(OUT_SCREEN.iterdir()):
        print(f"  {p.name}: {p.stat().st_size} bytes")

    print("\n=== docs/music/union/ ===")
    if OUT_MUSIC.exists():
        for p in sorted(OUT_MUSIC.iterdir()):
            print(f"  {p.name}: {p.stat().st_size} bytes")


if __name__ == "__main__":
    main()
