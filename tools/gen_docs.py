#!/usr/bin/env python3
"""ZigMachine documentation generator.

Parses the sealed HW ABI headers (hw/sdk/*.zig) and the open ZigOS library
(zigos/*.zig) for their public surface + doc comments, and emits a single
self-contained programmer's guide (docs/ZIGMACHINE_GUIDE.html) with a register
map, an ABI/library reference, and hand-written examples.

The reference is generated from source so signatures never drift; the prose and
examples live in EXAMPLES below. Run: `python3 tools/gen_docs.py` (from repo root
or anywhere — paths are resolved relative to this file).
"""
from __future__ import annotations

import html
import re
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


# --------------------------------------------------------------------------
# Parsing (lightweight, line-oriented — not a full Zig parser)
# --------------------------------------------------------------------------
@dataclass
class Item:
    name: str
    sig: str
    doc: str = ""


@dataclass
class Group:
    title: str
    blurb: str
    items: list[Item] = field(default_factory=list)


def _leading_doc(lines: list[str], idx: int) -> str:
    """Contiguous `//` comment lines immediately above line `idx`."""
    out: list[str] = []
    j = idx - 1
    while j >= 0:
        s = lines[j].strip()
        if s.startswith("//"):
            out.append(s.lstrip("/").strip())
            j -= 1
        else:
            break
    return " ".join(reversed(out))


def _trailing_doc(line: str) -> str:
    m = re.search(r"//\s*(.*)$", line)
    return m.group(1).strip() if m else ""


def parse_consts(path: Path, name_re: str) -> list[Item]:
    """`pub const <name> : type = value; // doc` lines whose name matches name_re."""
    items: list[Item] = []
    for line in path.read_text().splitlines():
        m = re.match(rf"\s*pub const ({name_re})\s*:[^=]+=\s*([^;]+);", line)
        if m:
            items.append(Item(m.group(1), m.group(2).strip(), _trailing_doc(line)))
    return items


def parse_externs(path: Path) -> list[Item]:
    """`pub extern fn name(args) ret; // doc` — the HW ABI exports."""
    items: list[Item] = []
    for line in path.read_text().splitlines():
        m = re.match(r"\s*pub extern fn\s+(\w+)\s*(\([^)]*\)[^;]*);", line)
        if m:
            items.append(Item(m.group(1), f"{m.group(1)}{m.group(2).strip()}", _trailing_doc(line)))
    return items


def parse_struct_methods(path: Path, struct: str) -> list[Item]:
    """`pub fn name(...) ret {` methods inside `pub const <struct> = struct`."""
    lines = path.read_text().splitlines()
    items: list[Item] = []
    cur = None
    for i, line in enumerate(lines):
        sm = re.match(r"\s*pub const (\w+)\s*=\s*(?:extern\s+)?struct", line)
        if sm:
            cur = sm.group(1)
            continue
        if cur != struct:
            continue
        fm = re.match(r"\s*pub fn\s+(\w+)\s*(\(.*)$", line)
        if fm:
            sig = fm.group(2).rstrip()
            sig = re.sub(r"\s*\{?\s*$", "", sig)  # drop trailing brace
            items.append(Item(fm.group(1), f"{fm.group(1)}{sig}", _leading_doc(lines, i)))
    return items


# --------------------------------------------------------------------------
# Hand-written prose + examples (the "learn it" half; reference is generated)
# --------------------------------------------------------------------------
INTRO = """
ZigMachine is a fantasy console: a <b>sealed hardware</b> core (compiled to two
<code>machine-*.wasm</code> binaries you never edit) plus an <b>open library</b>
(ZigOS) and your <b>scene</b> code, all sharing one <code>WebAssembly.Memory</code>
through a memory-mapped ABI. You write a scene; ZigOS gives you planes, palettes,
a <b>2D blitter</b>, HBL rasters, <b>hardware scrolling</b>, <b>low & medium
resolution</b> (with per-scanline resolution switching), a <b>GEM-style GUI
toolkit</b>, and a <b>Wavefront OBJ loader</b> on top of the sealed machine.
A scene is a struct with <code>init/update/render</code> (see the first example);
select it in <code>apps/floppy.zig</code>.
"""

EXAMPLES = [
    ("A minimal scene", """// apps/scenes/my_scene.zig — select it in apps/floppy.zig:
//   pub const Demo = @import("scenes/my_scene.zig").Demo;
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

pub const Demo = struct {
    pub fn init(self: *Demo, os: *ZigOS) void {
        _ = self;
        const fb = &os.lfbs[0];
        fb.is_enabled = true;                     // show plane 0
        fb.setPaletteEntry(1, .{ .r = 255, .g = 80, .b = 0, .a = 255 });
    }
    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void { _ = self; _ = os; _ = dt; }
    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = self; _ = dt;
        const fb = &os.lfbs[0];
        fb.clearFrameBuffer(0);
        fb.setPixelValue(160, 100, 1);            // one orange pixel, screen centre
    }
};"""),

    ("Filled vectors with the blitter", """const zg = @import("zigos");
var blit: zg.Blitter = .{};

// in init: blit.init();
// in render (fb = &os.lfbs[0]):
blit.clear(fb, 0);                                // hardware FILL
blit.triangle(fb, .{ .x = 20, .y = 20 }, .{ .x = 300, .y = 40 }, .{ .x = 160, .y = 180 }, 1);
// glenz (see-through) vectors: OR each single-bit face colour into the buffer
blit.triangleEx(fb, a, b, c, 0x01, 0, .glenz);"""),

    ("Per-scanline rasters (HBL)", """// A palette/background split every scanline — set a global HBL handler.
fn raster(os: *zg.ZigOS, line: u16) void {
    os.setBackgroundColor(.{ .r = @intCast(line), .g = 0, .b = 128, .a = 255 });
}
// in init: os.setHBLHandler(raster);"""),

    ("Hardware scrolling", """// A window onto a bigger-than-screen buffer.
const fb = &os.lfbs[0];
fb.setScrollPlane(640, 400);        // back plane 0 with a 640x400 buffer
// ... draw into it at buffer coords ...
// each frame, pan the visible 320x200 window (pure hardware, zero per-pixel cost):
fb.setScroll(scroll_x, scroll_y);
// bonus: in SCROLL mode HSCROLL is re-read per scanline, so a per-plane HBL
// handler calling fb.setScrollFine(sin(line)) bends each line (wobble)."""),

    ("Medium resolution + per-HBL res switch", """// Medium = 640x200, crisp 1:1 (low-res is 320, pixel-doubled onto the same
// 800-wide raster). setMediumPlane defaults the screen to medium.
const fb = &os.lfbs[0];
fb.setMediumPlane();                 // 640x200 crisp; setMediumFullscreen() for overscan
fb.setFrameBufferHBLHandler(0, resHBL);

// An HBL handler flips RESOLUTION per scanline -> low & medium on one screen:
fn resHBL(fb: *zg.LogicalFB, os: *zg.ZigOS, line: u16, x: u16) void {
    _ = fb; _ = x;
    os.setResolution(if (line >= 80 and line < 130) .planes else .medium);
}"""),

    ("A GEM window (gui toolkit)", """const gui = zg.gui;
var g: gui.Gui = .{ .os = os, .fb = &os.lfbs[0], .blit = &blit };
var wm: gui.Wm = .{};
// in init: gui.installPalette(fb); _ = wm.add(.{ .r = .{ .x=16,.y=26,.w=200,.h=90 }, .title = "FILE" });
// in update: g.beginFrame(); wm.handle(&g);
// in render: draw desktop, then each window's chrome + your content:
const content = wm.drawChrome(&g, id, id == wm.topId());
if (g.button(.{ .x=content.x+4, .y=content.y+4, .w=48, .h=18 }, "OK", false)) { /* clicked */ }
// pointer state arrives via demo.pointer(x,y,buttons) (see sealed-loader.js)."""),
]


# --------------------------------------------------------------------------
# HTML rendering
# --------------------------------------------------------------------------
def esc(s: str) -> str:
    return html.escape(s)


def render_items(items: list[Item]) -> str:
    rows = []
    for it in items:
        doc = f'<div class="doc">{esc(it.doc)}</div>' if it.doc else ""
        rows.append(f'<div class="item"><code class="sig">{esc(it.sig)}</code>{doc}</div>')
    return "\n".join(rows)


def render_consts(items: list[Item]) -> str:
    rows = ["<table><thead><tr><th>Name</th><th>Value</th><th>Meaning</th></tr></thead><tbody>"]
    for it in items:
        rows.append(
            f"<tr><td><code>{esc(it.name)}</code></td>"
            f"<td><code>{esc(it.sig)}</code></td><td>{esc(it.doc)}</td></tr>"
        )
    rows.append("</tbody></table>")
    return "\n".join(rows)


def render_examples() -> str:
    out = []
    for title, code in EXAMPLES:
        out.append(f'<h3>{esc(title)}</h3><pre class="code">{esc(code)}</pre>')
    return "\n".join(out)


def build() -> str:
    sdk = ROOT / "hw" / "sdk"
    mm = sdk / "memmap.zig"
    geometry = parse_consts(mm, r"(?:WIDTH|HEIGHT|NB_PLANES|PHYSICAL_\w+|RASTER_\w+|MEDIUM_\w+|HORIZONTAL_\w+|VERTICAL_\w+|STRIDE_\w+)")
    modes = parse_consts(mm, r"(?:RES_\w+|FB_MODE_\w+)")
    regs = parse_consts(mm, r"REG_\w+")
    blit_regs = parse_consts(mm, r"BLIT_[A-Z_]+")
    blit_ctl = parse_consts(mm, r"(?:CON_\w+|MT_\w+|BLIT_CMD_\w+|BLIT_STATUS_\w+)")
    abi = parse_externs(sdk / "hardware.zig")
    lfb = parse_struct_methods(ROOT / "zigos" / "zigos.zig", "LogicalFB")
    zos = parse_struct_methods(ROOT / "zigos" / "zigos.zig", "ZigOS")
    blitter = parse_struct_methods(ROOT / "zigos" / "blitter.zig", "Blitter")
    gui = parse_struct_methods(ROOT / "zigos" / "gui.zig", "Gui")
    wm = parse_struct_methods(ROOT / "zigos" / "gui.zig", "Wm")
    mesh = parse_struct_methods(ROOT / "zigos" / "utils" / "obj_loader.zig", "Mesh")

    groups = [
        ("Geometry & resolution", render_consts(geometry)),
        ("Resolution & plane modes", render_consts(modes)),
        ("Video registers", render_consts(regs)),
        ("Blitter registers", render_consts(blit_regs)),
        ("Blitter commands / control / minterms", render_consts(blit_ctl)),
        ("HW ABI — machine exports", render_items(abi)),
        ("ZigOS — LogicalFB (a plane)", render_items(lfb)),
        ("ZigOS — ZigOS (the OS)", render_items(zos)),
        ("ZigOS — Blitter (2D coprocessor)", render_items(blitter)),
        ("ZigOS — GUI toolkit (Gui)", render_items(gui)),
        ("ZigOS — Window manager (Wm)", render_items(wm)),
        ("ZigOS — OBJ loader (Mesh)", render_items(mesh)),
    ]
    nav = "\n".join(f'<a href="#{i}">{esc(t)}</a>' for i, (t, _) in enumerate(groups))
    sections = "\n".join(
        f'<section id="{i}"><h2>{esc(t)}</h2>{body}</section>' for i, (t, body) in enumerate(groups)
    )
    methods = len(lfb) + len(zos) + len(blitter) + len(gui) + len(wm) + len(mesh)
    consts = len(geometry) + len(modes) + len(regs) + len(blit_regs) + len(blit_ctl)
    counts = f"{len(abi)} ABI exports · {methods} library methods · {consts} constants/registers"

    return TEMPLATE.format(
        css=CSS,
        date=date.today().isoformat(),
        counts=counts,
        intro=INTRO,
        nav=nav,
        examples=render_examples(),
        sections=sections,
    )


CSS = """
:root { color-scheme: dark; }
* { box-sizing: border-box; }
body { margin: 0; background: #0e1016; color: #d7dbe6; font: 15px/1.6 system-ui, sans-serif; }
header { padding: 32px 40px; background: linear-gradient(135deg, #1a1f2e, #0e1016); border-bottom: 1px solid #2a3142; }
h1 { margin: 0 0 6px; font-size: 26px; letter-spacing: .5px; }
.sub { color: #8b93a7; font-size: 13px; }
.wrap { display: flex; gap: 28px; max-width: 1200px; margin: 0 auto; padding: 28px 40px; }
nav { position: sticky; top: 20px; align-self: flex-start; min-width: 210px; display: flex; flex-direction: column; gap: 4px; }
nav a { color: #9aa4bd; text-decoration: none; padding: 5px 10px; border-radius: 6px; font-size: 13px; }
nav a:hover { background: #1a2030; color: #fff; }
main { flex: 1; min-width: 0; }
h2 { margin: 34px 0 14px; font-size: 19px; color: #7dd3fc; border-bottom: 1px solid #232a3a; padding-bottom: 6px; }
h3 { margin: 20px 0 8px; font-size: 15px; color: #fbbf72; }
.item { padding: 10px 0; border-bottom: 1px solid #191e2b; }
.sig { display: block; color: #a5f3c0; font: 13px/1.5 ui-monospace, monospace; white-space: pre-wrap; }
.doc { color: #9aa4bd; font-size: 13.5px; margin-top: 4px; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #1c2230; vertical-align: top; }
th { color: #7dd3fc; font-weight: 600; }
td code, .sig, code { color: #a5f3c0; }
pre.code { background: #12151f; border: 1px solid #232a3a; border-radius: 8px; padding: 14px 16px;
           overflow-x: auto; font: 12.5px/1.5 ui-monospace, monospace; color: #cdd6e6; }
.intro { background: #12151f; border: 1px solid #232a3a; border-radius: 8px; padding: 16px 18px; margin-bottom: 8px; }
code { background: #1a2030; padding: 1px 5px; border-radius: 4px; }
"""

TEMPLATE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ZigMachine — Programmer's Guide</title>
<style>{css}</style></head>
<body>
<header>
  <h1>ZigMachine — Programmer's Guide</h1>
  <div class="sub">Generated {date} by tools/gen_docs.py · {counts}</div>
</header>
<div class="wrap">
  <nav><a href="#top">Overview</a><a href="#examples">Examples</a>{nav}</nav>
  <main>
    <section id="top"><h2>Overview</h2><div class="intro">{intro}</div></section>
    <section id="examples"><h2>Examples</h2>{examples}</section>
    {sections}
  </main>
</div>
</body></html>
"""


def main() -> None:
    out = ROOT / "docs" / "ZIGMACHINE_GUIDE.html"
    out.write_text(build())
    print(f"wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
