// --------------------------------------------------------------------------
// hello.zig: the KESTREL SDK's template cart (docs/SDK.md). Rename it, keep the shape.
//
// One plane, three raster bars, a sine scroller and an SNDH tune:
//   - the bars are REAL rasters: palette entry 0 is rewritten before every
//     scanline by the copper (zg.copper), no pixel drawn. As on an ST they run
//     the full width, borders included: the plane is an overscan plane (400x280,
//     the whole raster) and the copper opens every border on every line;
//   - the scroller is the 8x8 system font, one glyph at a time on a sine;
//   - the music is a request by name, for a file under the SDK's docs/music/.
// All per-frame maths is integer (zg.fixtrig: Q16.16 sine, u32 angles): the
// board's cart CPU has no FPU on every image, and float there is soft-float.
//
// A scene is a struct named Demo with init / update / render. Every field is
// set in init: a cart's Demo is never built from field defaults.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

// An overscan plane is the whole raster: 400x280, the 320x200 window at (40, 40).
const W: i32 = zg.PHYSICAL_WIDTH; // 400
const H: usize = zg.PHYSICAL_HEIGHT; // 280

const BACK: u8 = 0; // the entry the rasters rewrite each line
const INK: u8 = 1;

const MUSIC = "sos.sndh"; // a file under docs/music/ (yours can go there too)
const TEXT = "HELLO KESTREL * THIS CART WAS BUILT WITH THE SDK * EDIT src/hello.zig AND TYPE make * ";
const TEXT_W: i32 = TEXT.len * 8;
const SCROLL_Y: i32 = 136; // the sine's centre line (the window's middle)
const AMPLITUDE: i32 = 48; // pixels

const BAR_H: i32 = 14;
const BARS = [_][3]u8{ .{ 7, 1, 1 }, .{ 1, 6, 2 }, .{ 2, 3, 7 } }; // ST nibbles 0..7

// The copper's per-line colours for BACK: module scope, owned by the scene (an
// HBL handler gets no pointer to the Demo).
var copper_table: [1]zg.copper.Table = undefined;

/// An ST palette colour: each channel a 3-bit nibble, nibble * 32 (0..224).
fn st(r: u8, g: u8, b: u8) Color {
    return .{ .r = r * 32, .g = g * 32, .b = b * 32, .a = 255 };
}

pub const Demo = struct {
    scroll_x: i32,
    wave: trig.Angle,
    bars: trig.Angle,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.scroll_x = 0;
        self.wave = 0;
        self.bars = 0;

        zg.requestSong(MUSIC);
        zigos.setBackgroundColor(st(0, 0, 0));

        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanBuffer(); // 400x280: its HBL lines are physical, 0..279
        fb.setPaletteEntry(BACK, st(0, 0, 0));
        fb.setPaletteEntry(INK, st(7, 7, 7));
        fb.clearFrameBuffer(BACK);
        // .flicker: the copper also flickers the resolution on every line, which opens the
        // top, bottom and side borders (the ST trick, timed by the machine like the real one).
        zg.copper.install(fb, &.{BACK}, &copper_table, .{ .flicker = true });
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt; // frame-locked: one step a frame, never time-driven
        self.scroll_x = @mod(self.scroll_x + 2, TEXT_W);
        self.wave +%= trig.angle(0.06);
        self.bars +%= trig.angle(0.035);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[0];
        // Only the scroller's band changes: wipe that, not the whole plane.
        const top: usize = @intCast(SCROLL_Y - AMPLITUDE);
        const bottom: usize = @intCast(SCROLL_Y + AMPLITUDE + 8);
        @memset(fb.fb[top * @as(usize, W) .. bottom * @as(usize, W)], BACK);
        self.drawScroller(zigos, fb);
        self.buildRasters(zg.copper.table(fb, 0));
    }

    /// One glyph at a time, each on its own height of the sine.
    fn drawScroller(self: *const Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        var x: i32 = -@mod(self.scroll_x, 8);
        var c: usize = @intCast(@divTrunc(self.scroll_x, 8));
        while (x < W) : (x += 8) {
            const a = self.wave +% @as(u32, @bitCast(x)) *% (1 << 24);
            const y = SCROLL_Y + (trig.sin(a) * AMPLITUDE >> 16);
            zigos.printText(fb, TEXT[c .. c + 1], @intCast(x), @intCast(y), INK, BACK);
            c = (c + 1) % TEXT.len;
        }
    }

    /// One colour a line of the whole raster: black, with three bars swinging on sines.
    fn buildRasters(self: *const Demo, lines: *[H]u32) void {
        @memset(lines, st(0, 0, 0).toRGBA());
        for (BARS, 0..) |rgb, i| {
            const phase = self.bars +% @as(u32, @intCast(i)) *% trig.angle(2.1);
            const y0 = @as(i32, @intCast(H / 2)) - BAR_H / 2 + (trig.sin(phase) * 120 >> 16);
            var d: i32 = 0;
            while (d < BAR_H) : (d += 1) {
                const k: u8 = @intCast(if (d < BAR_H / 2) d + 1 else BAR_H - d); // 1..7..1
                const line: usize = @intCast(y0 + d);
                lines[line] = st(rgb[0] * k / 7, rgb[1] * k / 7, rgb[2] * k / 7).toRGBA();
            }
        }
    }
};
