"""Hand-written prose + examples for the guide (the reference half is generated)."""
from __future__ import annotations

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
<p><b>New here?</b> Do the <a href="TUTORIAL.html">tutorial</a> first: it builds one
screen step by step in Zig, C and Rust, and runs each step on the real machine.
This page is the reference you reach for afterwards.</p>
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
