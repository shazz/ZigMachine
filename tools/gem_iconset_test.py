"""Proves rom/gem/iconset.zig: every screen mode draws the icon set the desk mode draws
(Matt, 9 Nov: "in low resolution, the same icons should be used as in desk mode").

    uv run --with pillow python tools/gem_iconset_test.py [--break select|oldpath]

1. iconset.zig compiled against a SYNTHETIC asset set (gem_assets_conv_test's made-up
   directory, nothing of the TOS sources): its FLOPPY is the set's colour icon (a colour
   icon wins, as desk mode chose before), shown in colour only on 4+ planes (TOS 4: ST
   low, not ST medium), and the ids the set lacks fall back to the TOS 1.0 bitmaps.
2. The old path (rom/gem/desktop: low and medium) and the engine's asset table take their
   icons from iconset.zig only: no file there imports gem_icons.zig.

--break select: iconset.zig ignores the set (the old TOS 1.0-only path); must fail.
--break oldpath: desktop.zig draws gem_icons.zig directly again; must fail.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import gem_assets_conv as conv  # noqa: E402
import gem_assets_conv_test as synth  # noqa: E402

CHECK = """const std = @import("std");
const is = @import("iconset");
const ga = @import("gem_assets");
const eq = std.testing.expectEqual;
test "every mode draws the build's set; what it lacks is TOS 1.0's" {
    try eq(ga.cicons[0].data.ptr, is.FLOPPY.ink.ptr); // the colour icon wins
    try eq(@as(u16, 8), is.FLOPPY.w);
    const e = is.entryOf(is.FLOPPY).?;
    try eq(ga.cicons[0].mask.ptr, e.mask.ptr); // the engine's mask is the set's own
    try eq(e.mask[1] & ~is.FLOPPY.ink[1], is.FLOPPY.body[1]); // body = mask & ~data
    try eq(ga.cicons[0].col.?.ptr, e.col.?.ptr);
    try eq(true, is.colourIn(is.FLOPPY, 4) != null); // ST low: 4 planes, the colour image
    try eq(true, is.colourIn(is.FLOPPY, 2) == null); // ST medium: 2 planes, the mono icon
    try eq(true, is.has_colour);
    try eq(is.tos1.HARD.ink.ptr, is.HARD.ink.ptr); // not in the set: the built-in
    try eq(is.tos1.TRASH.ink.ptr, is.TRASH.ink.ptr);
    try eq(true, is.colourIn(is.HARD, 4) == null);
}
"""
OWNER = "rom/gem/iconset.zig"  # the one file that may import gem_icons.zig for drawing


def old_path_offenders(brk: str | None) -> list[str]:
    bad = []
    for f in sorted((ROOT / "rom/gem/desktop").rglob("*.zig")):
        src = f.read_text()
        if brk == "oldpath" and f.name == "desktop.zig":
            src += '\nconst icons_old = @import("../gem_icons.zig");\n'
        if re.search(r'@import\("[./]*gem_icons\.zig"\)', src):
            bad.append(str(f.relative_to(ROOT)))
    return bad


def compile_check(tmp: Path, brk: str | None) -> tuple[bool, str]:
    synth.make(tmp / "set")
    conv.main([str(tmp / "set"), str(tmp / "out"), "--trees", str(tmp / "set/trees")])
    gem = tmp / "gem"
    gem.mkdir()
    shutil.copy(ROOT / "rom/gem/gem_icons.zig", gem)
    src = (ROOT / OWNER).read_text()
    if brk == "select":
        src = re.sub(r"    if \(find\(ga\.\w+, id\)\).*\n", "", src).replace(") Entry {\n", ") Entry {\n    _ = id;\n", 1)
    (gem / "iconset.zig").write_text(src)
    (tmp / "check.zig").write_text(CHECK)
    zig = os.environ.get("ZIG", "zig")
    cmd = [zig, "test", "--dep", "iconset", "--dep", "gem_assets", f"-Mroot={tmp / 'check.zig'}",
           "--dep", "gem_assets", f"-Miconset={gem / 'iconset.zig'}", f"-Mgem_assets={tmp / 'out/gem_assets.zig'}"]
    r = subprocess.run(cmd, capture_output=True, text=True, check=False, cwd=tmp)
    return r.returncode == 0, r.stderr[-1500:]


def main() -> int:
    brk = sys.argv[sys.argv.index("--break") + 1] if "--break" in sys.argv else None
    tmp = Path(tempfile.mkdtemp(prefix="gem-iconset-"))
    try:
        ok, err = compile_check(tmp, brk)
        bad = old_path_offenders(brk)
        if bad:
            err += "\nthe old path draws gem_icons.zig directly, not iconset.zig: " + ", ".join(bad)
        ok = ok and not bad
        print(("PASS" if ok else "FAIL") + ": every mode draws the build's icon set" + ("" if ok else "\n" + err))
        return 0 if ok else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
