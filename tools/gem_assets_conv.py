"""Turn a LOCAL GEM asset directory into a Zig module for the ROM (-Dgem_assets=<dir>).

    uv run --with pillow python tools/gem_assets_conv.py <assets dir> <out dir> [--trees <dir>]

The directory is the layout of Matt's reconstruction (manifest.json + PNGs: desktop
icons, mouse forms, the 6x6 / 8x8 / 8x16 system fonts, fill patterns, the 16-colour
palette, MultiTOS colour icons); --trees adds object trees from a zig_extract
directory (index.json + one Zig file a tree). It writes <out dir>/gem_assets.zig with
the declarations of rom/gem/engine/assets_none.zig, filled.

LICENCE RULE: the inputs are not ours to publish. The output goes to the build cache
(build.zig hands an output directory in .zig-cache), never into the source tree, and
nothing it produces is ever committed. This tool itself is ours and is committed;
tools/gem_assets_conv_test.py proves it on a synthetic directory it makes up.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from PIL import Image

# Manifest file stems -> the semantic ids the desktop asks for.
ICON_IDS = {
    "floppy_disk": "FLOPPY", "hard_disk": "HARD", "trash": "TRASH",
    "folder": "FOLDER", "prg": "PROGRAM", "text": "DOCUMENT",
}
CICON_IDS = {"cicons_diskcc": "FLOPPY", "cicons_notecc": "NOTE", "cicons_quescc": "QUES", "cicons_stopcc": "STOP"}
FONTS = {"6x6": (6, 6), "8x8": (8, 8), "8x16": (8, 16)}
CICON_BASE = 48  # plane palette index of VDI pen 0 (rom/gem/desktop/eng/palette)


def rgba(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def opaque(p) -> bool:
    return p[3] >= 128


def dark(p) -> bool:
    return opaque(p) and (p[0] + p[1] + p[2]) < 384


def bitrows(im: Image.Image, test, x0=0, y0=0, w=None, h=None) -> list[int]:
    """Rows of MSB-first bytes: a set bit where test(pixel)."""
    w = w or im.width
    h = h or im.height
    out = []
    for y in range(h):
        row = [0] * ((w + 7) // 8)
        for x in range(w):
            if test(im.getpixel((x0 + x, y0 + y))):
                row[x // 8] |= 0x80 >> (x % 8)
        out += row
    return out


def font(path: Path, cw: int, ch: int) -> list[int]:
    """A 16x16 charset sheet, one blank pixel around a cell and between cells."""
    im = rgba(path)
    px, py = (im.width - 1) // 16, (im.height - 1) // 16
    if px < cw or py < ch:
        raise SystemExit(f"gem_assets_conv: {path.name}: cells {px}x{py} smaller than {cw}x{ch}")
    data = []
    for c in range(256):
        x0, y0 = 1 + (c % 16) * px, 1 + (c // 16) * py
        data += bitrows(im, dark, x0, y0, cw, ch)
    return data


def mouse(path: Path, hot) -> dict:
    im = rgba(path)
    words = lambda test: [int.from_bytes(bytes(bitrows(im, test, 0, y, 16, 1)), "big") for y in range(16)]
    return {"mask": words(opaque), "data": words(dark), "hx": hot[0], "hy": hot[1]}


def nearest(p, pens) -> int:
    return min(range(len(pens)), key=lambda i: sum((a - b) ** 2 for a, b in zip(p[:3], pens[i])))


def chunky(path: Path, pens) -> list[int]:
    im = rgba(path)
    return [CICON_BASE + nearest(im.getpixel((x, y)), pens) if opaque(im.getpixel((x, y))) else 0
            for y in range(im.height) for x in range(im.width)]


def hexrgb(s: str):
    return [int(s[i:i + 2], 16) for i in (1, 3, 5)]


def read_manifest(root: Path) -> list[dict]:
    m = root / "manifest.json"
    if not m.is_file():
        raise SystemExit(f"gem_assets_conv: no manifest.json in {root}")
    return json.loads(m.read_text())


def collect(root: Path) -> dict:
    out = {"fonts": {}, "icons": [], "cicons": [], "patterns": [], "palette": None, "arrow": None, "busy": None}
    entries = read_manifest(root)
    pal = next((e["colors"] for e in entries if e["kind"] == "palette" and len(e.get("colors", [])) == 16), None)
    out["palette"] = [hexrgb(c) for c in pal] if pal else None
    pens = out["palette"] or [[255, 255, 255], [0, 0, 0]]
    for e in entries:
        add_entry(root, e, out, pens)
    out["icons"].sort(key=lambda i: i["id"])
    out["cicons"].sort(key=lambda i: i["id"])
    return out


def add_entry(root: Path, e: dict, out: dict, pens) -> None:
    f = root / e["file"]
    stem, kind = f.stem, e["kind"]
    if not f.is_file():
        return
    if kind == "font" and "charset" in stem:
        for key, (cw, ch) in FONTS.items():
            if stem.startswith(key + "_"):
                out["fonts"][key] = {"w": cw, "h": ch, "data": font(f, cw, ch)}
    elif kind == "mouse_form" and "aes340" in e["file"]:
        if stem.endswith("_arrow"):
            out["arrow"] = mouse(f, e.get("hotspot", [0, 0]))
        elif "busy" in stem:
            out["busy"] = mouse(f, e.get("hotspot", [0, 0]))
    elif kind == "icon" and "aes340" in e["file"] and stem in ICON_IDS:
        im = rgba(f)
        out["icons"].append({"id": ICON_IDS[stem], "w": im.width, "h": im.height,
                             "mask": bitrows(im, opaque), "data": bitrows(im, dark), "col": None})
    elif kind == "color_icon" and stem.endswith("_4planes") and stem[:-8] in CICON_IDS:
        mono = rgba(f)
        out["cicons"].append({"id": CICON_IDS[stem[:-8]], "w": mono.width, "h": mono.height,
                              "mask": bitrows(mono, opaque), "data": bitrows(mono, dark), "col": chunky(f, pens)})
    elif kind == "fill_pattern" and e.get("table") == "DITHER":
        im = rgba(f)
        out["patterns"].append([int.from_bytes(bytes(bitrows(im, dark, 0, y, 16, 1)), "big") for y in range(16)])


# --- trees (zig_extract) ---------------------------------------------------------------
OBJ_RE = re.compile(r"\.\{ \.next = (-?\d+), \.head = (-?\d+), \.tail = (-?\d+), \.ty = (\w+), \.flags = ([\w |]+), "
                    r"\.state = ([\w |]+),\s*\.spec = (.*?), \.x = (-?\d+), \.y = (-?\d+), \.w = (-?\d+), \.h = (-?\d+) \},", re.S)
CONST_RE = re.compile(r"pub const (\w+): u16 = (0x[0-9A-Fa-f]+|\d+);")


def bits(expr: str, consts: dict) -> int:
    return sum(int(t, 0) if t[0].isdigit() else consts[t] for t in (s.strip() for s in expr.split("|")) if t)


def spec_of(src: str) -> dict:
    if m := re.match(r"\.\{ \.box = (0x[0-9A-Fa-f]+|\d+) \}", src):
        return {"kind": 1, "box": int(m.group(1), 0)}
    if m := re.match(r'\.\{ \.str = (".*") \}', src):
        return {"kind": 2, "str": m.group(1)}
    if m := re.match(r'\.\{ \.ted = \.\{ \.text = (".*?"), .*?\.font = (\d+), \.just = (\d+), \.color = (0x[0-9A-Fa-f]+), \.thickness = (-?\d+) \} \}', src):
        return {"kind": 3, "str": m.group(1), "font": int(m.group(2)), "just": int(m.group(3)),
                "color": int(m.group(4), 16), "thick": int(m.group(5))}
    if m := re.match(r'\.\{ \.icon = (".*") \}', src):
        return {"kind": 4, "str": m.group(1)}
    return {"kind": 5 if ".image" in src else 0}


def tree_file(path: Path) -> list[dict]:
    text = path.read_text()
    consts = {k: int(v, 0) for k, v in CONST_RE.findall(text)}
    objs = []
    for m in OBJ_RE.finditer(text):
        nx, hd, tl, ty, fl, st, spec, x, y, w, h = m.groups()
        objs.append({"next": int(nx), "head": int(hd), "tail": int(tl), "ty": consts[ty], "flags": bits(fl, consts),
                     "state": bits(st, consts), "x": int(x), "y": int(y), "w": int(w), "h": int(h), **spec_of(spec)})
    return objs


def collect_trees(root: Path, group: str = "aes340_tos4") -> list[dict]:
    idx = json.loads((root / "index.json").read_text())
    out = []
    for e in idx.get(group, []):
        objs = tree_file(root / e["file"])
        if len(objs) != e.get("objects", len(objs)):
            raise SystemExit(f"gem_assets_conv: {e['file']}: read {len(objs)} objects, index says {e['objects']}")
        out.append({"group": e["group"], "name": e["tree"], "objs": objs})
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("assets", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--trees", type=Path)
    a = ap.parse_args(argv)
    data = collect(a.assets)
    data["trees"] = collect_trees(a.trees) if a.trees else []
    from gem_assets_emit import emit  # beside this file
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "gem_assets.zig").write_text(emit(data, a.assets.name))
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
