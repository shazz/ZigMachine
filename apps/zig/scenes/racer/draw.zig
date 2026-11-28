// --------------------------------------------------------------------------
// RACER: painting a frame into a plane through the chosen fill path. sky() first (sky and ground
// rows, then the backdrop op), fill() after the geometry. The AFFINE path fires its rows as ops that
// run while the CPU collects and sorts; the CPU path stores them itself and syncs CHISEL before
// its polygons (the browser's blitter is synchronous: only the board needs the sync).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const backdrop = @import("backdrop.zig");
const bench = @import("bench.zig");
const cam = @import("cam.zig");
const frame = @import("frame.zig");
const hide = @import("hide.zig");
const palette = @import("palette.zig");
const poly = @import("poly.zig");
const sinks = @import("sinks.zig");
const xf = @import("xform.zig");

var bd_spans: [xf.Y1 - xf.Y0]zg.chisel_v2.Span = undefined;
var bd_lower: [xf.Y1 - xf.Y0]zg.chisel_v2.Span = undefined;

pub const Painter = struct {
    os: *zg.ZigOS,
    cpu: sinks.CpuSink = .{},
    aff: sinks.AffineSink,
    cpu_fill: bool = false, // CHISEL AFFINE by default since the board optimisation (~1.3 ms a 32X race frame); key f the CPU's

    pub fn sky(self: *Painter, fb: *zg.LogicalFB, v: *const cam.View, yaw: u32) void {
        if (self.cpu_fill) {
            skyFills(fb, v.horizon); // CHISEL fills, async: the CPU path syncs before its first span
        } else {
            self.aff.begin(fb);
            skyRows(&self.aff, v.horizon);
            self.aff.flush();
        }
        if (!hide.on(hide.BACKDROP)) backdrop.draw(fb, backdrop.spans(&bd_spans, &bd_lower, yaw, v.horizon, xf.Y0, xf.Y1));
        self.aff.begin(fb);
    }

    pub fn fill(self: *Painter, fb: *zg.LogicalFB, f: *frame.Frame) bench.Counts {
        var c = bench.Counts{ .tiles = f.stats.tiles, .faces = f.stats.faces, .verts = f.stats.verts, .polys = f.stats.polys };
        if (self.cpu_fill) {
            self.os.blitSync(); // the backdrop op wrote this plane: the CPU may touch it after this
            self.cpu.begin(fb);
            var e = poly.Emitter(sinks.CpuSink){ .sink = &self.cpu, .y_min = xf.Y0, .y_max = xf.Y1, .w = 320 };
            f.emit(sinks.CpuSink, &e);
            c.spans = self.cpu.spans;
            c.pixels = self.cpu.pixels;
        } else {
            var e = poly.Emitter(sinks.AffineSink){ .sink = &self.aff, .y_min = xf.Y0, .y_max = xf.Y1, .w = 320 };
            f.emit(sinks.AffineSink, &e);
            self.aff.flush();
            self.os.blitSync(); // the last op's tail counts in this frame's time (a NOP in the browser: pins hold)
            c.spans = self.aff.spans;
            c.pixels = self.aff.pixels;
        }
        return c;
    }
};

/// skyRows' pixels as at most three CHISEL fills (sky, ground, around an opaque panorama's rows) instead of 176 CPU row
/// spans (board optimisation: ~0.6 ms of the K stage). LogicalFB.fillRect falls back to the CPU where CHISEL can't.
fn skyFills(fb: *zg.LogicalFB, hz: i32) void {
    const skip = if (hide.on(hide.BACKDROP)) [2]i32{ 0, 0 } else backdrop.covers(hz);
    var y: i32 = xf.Y0;
    while (y < xf.Y1) {
        if (y >= skip[0] and y < skip[1]) {
            y = skip[1];
            continue;
        }
        var e: i32 = xf.Y1;
        if (y < skip[0]) e = @min(e, skip[0]);
        if (y < hz) e = @min(e, hz);
        fb.fillRect(0, y, 320, @intCast(e - y), if (y < hz) palette.SKY else palette.GROUND);
        y = e;
    }
}

fn skyRows(sink: anytype, hz: i32) void {
    const skip = if (hide.on(hide.BACKDROP)) [2]i32{ 0, 0 } else backdrop.covers(hz); // an opaque panorama's rows: it paints them whole (R82 32X look)
    var y: i32 = xf.Y0;
    while (y < xf.Y1) : (y += 1) {
        if (y >= skip[0] and y < skip[1]) continue;
        sink.span(y, 0, 320, if (y < hz) palette.SKY else palette.GROUND);
    }
}
