// whichpart 4 -- TCB SCREEN #2 (screen.js do_tcb2), back to front:
//   the scroller layer: orgcanvas (tcb2_org.zig) at 1.8x, at (34, 254-Y) --
//     Y rises 0..30 by 3 and settles at -3 -- reaching into the bottom border,
//     which this part opens; or, once tcb2fx is 1, at 254-|sin(siny)*120|;
//   five raster bars (raster1_down at alpha 0.6 behind, raster1_up in front) on
//     200+200cos(angle), 0.25 apart, +0.05 a frame, halved vertically: ST-legal,
//     uniform rows -- REAL rasters, colour 0 per line (colour0());
//   the UNION WIZ CODERS logo at 1.5x in the frame's grey from clr[] (85 frames);
//   TCB_distlogo.png 1.5x through FX siny then sinx; ancool.png through FX sinx.
// tcb2fx becomes 1 when SYNC #1's scroller (myscrolltext -- the remake reads the
// wrong scroller, and it only moves in SYNC #1) stands on a ']': ported as is.
// Deviation, ST-ward: the bars are colour 0, so they pass BEHIND the scroller
// layer's pixels where, with tcb2fx 1, the remake would lay them over it.
const std = @import("std");
const frame = @import("frame.zig");
const gen = @import("assets_gen.zig");
const texts = @import("texts.zig");
const sc = @import("scroller.zig");
const fx = @import("fx.zig");
const org = @import("tcb2_org.zig");
const draw = @import("tcb2_draw.zig");

const NB_RASTERS = 5;

pub const Tcb2 = struct {
    colour: u8,
    cyl: org.Cylinder,
    y: i32, // Y
    y_inc: i32,
    loop: bool,
    tcb2fx: u8,
    siny: f64,
    angle: [NB_RASTERS]f64,
    text: sc.Scroller, // tcb2myscrolltext: 48x25 font, 329 canvas, speed 5
    cyl_text: sc.Scroller, // tcb2myscrolltext2: 32x25 font, 704 canvas, speed 2
    fx_tcb: fx.Fx(2), // tcb2myfx (siny)
    fx_tcb2: fx.Fx(2), // tcb2myfx2 (sinx)
    fx_ancool: fx.Fx(2), // tcb2myfx3 (sinx)

    pub fn init(self: *Tcb2) void {
        self.colour = 1;
        self.cyl = .{ .rota = 0, .counter = 0 };
        self.y = 0;
        self.y_inc = 3;
        self.loop = false;
        self.tcb2fx = 0;
        self.siny = 0;
        for (&self.angle, 0..) |*a, i| a.* = 0.25 * @as(f64, @floatFromInt(i));
        self.text.init(texts.tcb2, 48, 329, 5, null);
        self.cyl_text.init(texts.tcb2_cylinder, 32, 704, 2, null);
        self.fx_tcb = .{ .p = .{ .{ .value = 0, .amp = 10, .inc = 0.03, .offset = -0.06 }, .{ .value = 0, .amp = 10, .inc = 0.01, .offset = 0.05 } } };
        self.fx_tcb2 = .{ .p = .{ .{ .value = 0, .amp = 20, .inc = 0.02, .offset = -0.05 }, .{ .value = 0, .amp = 10, .inc = 0.04, .offset = 0.008 } } };
        self.fx_ancool = .{ .p = .{ .{ .value = 0, .amp = 60, .inc = 0.04, .offset = -0.05 }, .{ .value = 0, .amp = 25, .inc = 0.06, .offset = 0.05 } } };
    }

    /// One do_tcb2(). `sync1_char` is myscrolltext's current character.
    pub fn step(self: *Tcb2, sync1_char: u8) void {
        const grey = gen.clr_level[self.colour];
        if (self.colour >= 85) self.colour = 1;
        org.clear();
        self.cyl.scroller(&self.cyl_text, 0);
        org.otherScroller(&self.text);
        const cy: f64 = @floatFromInt(165 - self.y);
        org.edge(9, cy);
        org.edge(310, cy);
        self.cyl.scroller(&self.cyl_text, 1);
        org.quad();
        if (self.tcb2fx == 0) {
            draw.layer(@floatFromInt(254 - self.y));
            if (!self.loop) self.y += self.y_inc;
            if (self.y >= 30) self.y_inc = -3;
            if (self.y <= -1) self.loop = true;
        } else {
            self.siny += 0.05;
            draw.layer(254 - @abs(@sin(self.siny) * 120));
        }
        for (&self.angle) |*a| advance(a); // the bars were drawn by colour0()
        draw.wizcoder(gen.grey_gid[grey]);
        draw.tcbLogo(&self.fx_tcb, &self.fx_tcb2);
        draw.ancool(&self.fx_ancool);
        if (sync1_char == ']') self.tcb2fx = 1;
        self.colour += 1;
    }

    /// Colour 0 per line: rastercanvas (drawn at scale (1, 0.5)) row 4Y+1.
    pub fn colour0(self: *const Tcb2, table: *[frame.PH]u32) void {
        @memset(table, frame.BLACK);
        var y: i32 = 0;
        while (y < 100) : (y += 1) frame.setC0(table, y, self.barsAt(@as(f64, @floatFromInt(4 * y + 1)) + 0.5));
    }

    fn barsAt(self: *const Tcb2, rc: f64) u32 {
        var c = [3]f64{ 0, 0, 0 };
        for (self.angle) |a| if (a > std.math.pi and a < 2 * std.math.pi) {
            const s = @floor(rc - (200 + 200 * @cos(a)) + 26); // drawDOWN, alpha 0.6
            if (s >= 0 and s < 53) blend(&c, gen.raster_down_rows[@intFromFloat(s)], 0.6);
        };
        for (self.angle) |a| if (a >= 0 and a <= std.math.pi / 2.0) up(&c, rc, a); // drawUP1
        var i: usize = NB_RASTERS;
        while (i > 0) { // drawUP2, last bar first
            i -= 1;
            const a = self.angle[i];
            if (a > std.math.pi / 2.0 and a <= std.math.pi) up(&c, rc, a);
        }
        const r: u32 = @intFromFloat(@floor(c[0] + 0.5));
        const g: u32 = @intFromFloat(@floor(c[1] + 0.5));
        const b: u32 = @intFromFloat(@floor(c[2] + 0.5));
        return frame.BLACK | (b << 16) | (g << 8) | r;
    }
};

fn up(c: *[3]f64, rc: f64, a: f64) void {
    const s = @floor(rc - (200 + 200 * @cos(a)) + 16);
    if (s >= 0 and s < 32) blend(c, gen.raster_up_rows[@intFromFloat(s)], 1);
}

fn blend(c: *[3]f64, rgba: u32, alpha: f64) void {
    for (0..3) |k| {
        const v: f64 = @floatFromInt((rgba >> @intCast(8 * k)) & 0xFF);
        c[k] = c[k] * (1 - alpha) + v * alpha;
    }
}

/// myrastero.advance(0.05)
fn advance(a: *f64) void {
    a.* += 0.05;
    if (a.* >= 2 * std.math.pi) a.* -= 2 * std.math.pi;
}
