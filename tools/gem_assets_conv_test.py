"""Proves tools/gem_assets_conv.py on a SYNTHETIC asset directory this test makes up
(nothing of the TOS sources or Matt's reconstruction): its arrow, a glyph of each font,
an icon, a colour icon and an object tree land in the generated Zig where the directory
says, and the module compiles against the stub's declarations (a zig test over it).

    uv run --with pillow python tools/gem_assets_conv_test.py [--break arrow|glyph|tree]

--break: the converter is made to lose that item; the test must then fail (exit 1).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import gem_assets_conv as conv  # noqa: E402

BLACK, WHITE, CLEAR = (0, 0, 0, 255), (255, 255, 255, 255), (0, 0, 0, 0)
ARROW_DATA = [0x8001 if r % 2 else 0x4002 for r in range(16)]  # made up
ARROW_MASK = [0xC003 | d for d in ARROW_DATA]
TREE = """pub const G_BOX: u16 = 20;
pub const G_STRING: u16 = 28;
pub const LASTOB: u16 = 0x0020;
pub const made_up = [_]Object{
    .{ .next = -1, .head = 1, .tail = 1, .ty = G_BOX, .flags = 0, .state = 0,
       .spec = .{ .box = 0x00011100 }, .x = 0, .y = 0, .w = 40, .h = 20 },
    .{ .next = 0, .head = -1, .tail = -1, .ty = G_STRING, .flags = LASTOB, .state = 0,
       .spec = .{ .str = "ZIGGY" }, .x = 3, .y = 4, .w = 40, .h = 8 },
};
"""


def sheet(path: Path, cw: int, ch: int) -> None:
    """A charset: glyph 'A' a solid block, glyph 1 its top row only, the rest blank."""
    px, py = cw + 2, ch + 2
    im = Image.new("RGBA", (1 + 16 * px, 1 + 16 * py), WHITE)
    for c, rows in ((ord("A"), range(ch)), (1, range(1))):
        x0, y0 = 1 + (c % 16) * px, 1 + (c // 16) * py
        for y in rows:
            for x in range(cw):
                im.putpixel((x0 + x, y0 + y), BLACK)
    im.save(path)


def mouse(path: Path) -> None:
    im = Image.new("RGBA", (16, 16), CLEAR)
    for y in range(16):
        for x in range(16):
            bit = 0x8000 >> x
            if ARROW_DATA[y] & bit:
                im.putpixel((x, y), BLACK)
            elif ARROW_MASK[y] & bit:
                im.putpixel((x, y), WHITE)
    im.save(path)


def make(root: Path) -> None:
    (root / "a").mkdir(parents=True)
    sheet(root / "a/8x8_system_font_charset.png", 8, 8)
    sheet(root / "a/8x16_system_font_charset.png", 8, 16)
    mouse(root / "a/mice0_arrow.png")
    icon = Image.new("RGBA", (16, 4), CLEAR)
    icon.putpixel((0, 0), BLACK)
    icon.putpixel((1, 0), WHITE)
    icon.save(root / "a/floppy_disk.png")
    cicon = Image.new("RGBA", (8, 2), (255, 0, 0, 255))
    cicon.save(root / "a/cicons_diskcc_4planes.png")
    pal = ["#ffffff", "#ff0000"] + ["#00ff00"] * 13 + ["#000000"]
    man = [
        {"file": "a/8x8_system_font_charset.png", "kind": "font"},
        {"file": "a/8x16_system_font_charset.png", "kind": "font"},
        {"file": "a/mice0_arrow.png", "kind": "mouse_form", "hotspot": [3, 5], "x": "aes340"},
        {"file": "a/floppy_disk.png", "kind": "icon"},
        {"file": "a/cicons_diskcc_4planes.png", "kind": "color_icon"},
        {"file": "a/pal.png", "kind": "palette", "colors": pal},
    ]
    for e in man:  # the converter takes TOS 4's mouse forms and icons (aes340_*) only
        if e["kind"] in ("mouse_form", "icon"):
            e["file"] = e["file"].replace("a/", "aes340_tos4/")
    (root / "aes340_tos4").mkdir()
    for n in ("mice0_arrow.png", "floppy_disk.png"):
        shutil.move(root / "a" / n, root / "aes340_tos4" / n)
    (root / "manifest.json").write_text(json.dumps(man))
    trees = root / "trees"
    (trees / "g/dialogs").mkdir(parents=True)
    (trees / "g/dialogs/made_up.zig").write_text(TREE)
    idx = {"aes340_tos4": [{"group": "dialogs", "tree": "MADE_UP", "file": "g/dialogs/made_up.zig", "objects": 2}]}
    (trees / "index.json").write_text(json.dumps(idx))


CHECK = """const std = @import("std");
const ga = @import("gem_assets.zig");
const eq = std.testing.expectEqual;
test "the synthetic set lands where its directory says" {
    try eq(true, ga.present);
    const a = ga.arrow.?;
    try eq(@as(u16, ARROW_DATA0), a.data[0]);
    try eq(@as(u16, ARROW_MASK1), a.mask[1]);
    try eq(@as(i8, 3), a.hx);
    try eq(@as(i8, 5), a.hy);
    const f = ga.font_8x16.?;
    try eq(@as(u8, 16), f.h);
    try eq(@as(u8, 0xFF), f.data['A' * 16 + 15]); // 'A' solid to its last row
    try eq(@as(u8, 0xFF), f.data[1 * 16]); // glyph 1: its top row
    try eq(@as(u8, 0), f.data[1 * 16 + 1]);
    try eq(@as(u8, 0xFF), ga.font_8x8.?.data['A' * 8]);
    try eq(@as(usize, 1), ga.icons.len);
    try eq(@as(u8, 0x80), ga.icons[0].data[0]); // black: data
    try eq(@as(u8, 0xC0), ga.icons[0].mask[0]); // black + white: mask
    try eq(@as(u8, 48 + 1), ga.cicons[0].col.?[0]); // red: pen slot 48 + hardware 1
    try eq(@as(usize, 1), ga.trees.len);
    try std.testing.expectEqualStrings("MADE_UP", ga.trees[0].name);
    try std.testing.expectEqualStrings("ZIGGY", ga.trees[0].objs[1].str);
    try eq(@as(i16, 3), ga.trees[0].objs[1].x);
    try eq(@as(u32, 0x00011100), ga.trees[0].objs[0].box);
}
"""


def sabotage(brk: str) -> None:
    if brk == "arrow":
        conv.mouse = lambda path, hot: {"mask": [0] * 16, "data": [0] * 16, "hx": 0, "hy": 0}
    elif brk == "glyph":
        real = conv.font
        conv.font = lambda path, cw, ch: [b ^ 1 for b in real(path, cw, ch)]
    elif brk == "tree":
        conv.collect_trees = lambda root, group="aes340_tos4": []


def main() -> int:
    brk = sys.argv[sys.argv.index("--break") + 1] if "--break" in sys.argv else None
    tmp = Path(tempfile.mkdtemp(prefix="gem-assets-"))
    try:
        make(tmp / "set")
        if brk:
            sabotage(brk)
        conv.main([str(tmp / "set"), str(tmp / "out"), "--trees", str(tmp / "set/trees")])
        check = CHECK.replace("ARROW_DATA0", hex(ARROW_DATA[0])).replace("ARROW_MASK1", hex(ARROW_MASK[1]))
        (tmp / "out/check.zig").write_text(check)
        zig = os.environ.get("ZIG", "zig")
        r = subprocess.run([zig, "test", str(tmp / "out/check.zig")], capture_output=True, text=True, check=False)
        ok = r.returncode == 0
        print(("PASS" if ok else "FAIL") + ": the synthetic asset set " + ("lands where it says" if ok else r.stderr[-1500:]))
        return 0 if ok else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
