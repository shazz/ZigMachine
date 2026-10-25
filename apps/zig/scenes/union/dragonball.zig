// --------------------------------------------------------------------------
// Union main-screen DRAGONBALLS (efmain.js "dragonball" object + codef_3d.js).
// 6 bouncing balls along the bottom of the screen: each shows a flat-shaded
// spinning 5-point star (5 overlapping copies at 72deg phase offsets, per the
// JS) over a translucent squashing disc. Drawn on P0, the background, last:
// the disc only ever lies over the plain bottom band (dragonball_squash.zig's
// test pins it), so its translucency is one pre-blended colour and the balls
// need no plane of their own over the background (a FRESCO pass per line,
// ~1.1 Mc a frame on the board). Caller sets up P0 (overscan) first.
//
// Geometry/animation constants faithful to codef_dragonball.js + efmain.js
// (:207-210, :317-324) — see dragonball_math.zig for the vertex/triangle data.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const sq = @import("dragonball_squash.zig");

const TWO_PI: f32 = std.math.pi * 2.0;

const raster = @import("dragonball_raster.zig");
const PAL_DISC = raster.PAL_DISC;
const PAL_FRONT = raster.PAL_FRONT;
const PAL_BACK = raster.PAL_BACK;
const PAL_DISC_ON_BACK = raster.PAL_DISC_ON_BACK; // precomputed disc(a=0.5) over PAL_BACK, opaque

// The disc as it was on its own plane (a = 128) over an opaque colour, as the board's mixer
// (fpga/rtl/video/zm_video_mix.v) and the browser's canvases fold it: P = round(c * a / 255),
// D = P + (D * (256 - a) >> 8). Over the bottom band's (224,224,224): (224,192,192).
const DISC = Color{ .r = 224, .g = 160, .b = 160, .a = 128 };
fn over(c: Color, d: Color) Color {
    return .{ .r = mix(c.r, c.a, d.r), .g = mix(c.g, c.a, d.g), .b = mix(c.b, c.a, d.b), .a = 255 };
}
fn mix(c: u8, a: u8, d: u8) u8 {
    const r: u32 = @as(u32, c) * a + 128;
    return @intCast(((r + (r >> 8)) >> 8) + ((@as(u32, d) * (256 - @as(u32, a))) >> 8));
}

var ball_buf: raster.Buf = undefined; // module-level scratch (heap-free)
var sprite: sq.Sprite = undefined; // the squashed ball, stamped 6 times by CHISEL

pub const Dragonballs = struct {
    rotx: f32 = 0, // shared star rotation.x (all 5 phases share one accumulator)
    roty: f32 = 0, // shared star rotation.y
    u: f32 = 0, // disc squash phase
    angle: f32 = 0, // bounce phase
    blitter: zg.Blitter = .{},

    /// `under`: the opaque colour of the band the discs lie on (main.zig's bottom band).
    pub fn init(self: *Dragonballs, zigos: *ZigOS, under: Color) void {
        self.* = .{};
        self.blitter.init();
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.setPaletteEntry(PAL_DISC, over(DISC, under));
        p0.setPaletteEntry(PAL_FRONT, Color{ .r = 217, .g = 67, .b = 69, .a = 255 });
        p0.setPaletteEntry(PAL_BACK, Color{ .r = 160, .g = 50, .b = 52, .a = 255 });
        // disc(224,160,160,a=0.502) over PAL_BACK(160,50,52), pre-blended opaque.
        p0.setPaletteEntry(PAL_DISC_ON_BACK, Color{ .r = 192, .g = 105, .b = 106, .a = 255 });
    }

    pub fn update(self: *Dragonballs) void {
        self.rotx = @mod(self.rotx + 0.01, TWO_PI);
        self.roty = @mod(self.roty + 0.06, TWO_PI);
        self.u = @mod(self.u + 0.2, TWO_PI);
        self.angle = @mod(self.angle + 0.05, TWO_PI);
    }

    pub fn draw(self: *Dragonballs, zigos: *ZigOS) void {
        raster.renderBall(&ball_buf, self.rotx, self.roty); // stars + disc, dragonball_raster.zig
        // Squash the WHOLE ball (stars + disc together) at blit time — matches
        // the original (scale the composited sprite), so star tips never poke
        // outside the disc when it shrinks.
        const sx = 1.0 + @sin(self.u) / 6.0;
        const sy = 1.0 + @sin(self.u + 10.0) / 6.0;
        sprite.build(&ball_buf, sx, sy); // one resample for all six balls
        const p0: *LogicalFB = &zigos.lfbs[0];
        var i: usize = 0;
        while (i < 6) : (i += 1) {
            const fi: f32 = @floatFromInt(i);
            const cx: i16 = 40 + 64 * @as(i16, @intCast(i));
            // the bounce height lands on a whole pixel, so all six share the sprite
            const cy: i16 = sq.centreY(self.angle, fi);
            self.blitter.blitImage(p0, cx + sprite.ox, cy + sprite.oy, sprite.pixels(), sprite.stride, 0, 0, sprite.w, sprite.h, 0);
        }
    }
};
