// --------------------------------------------------------------------------
// RACER (R82, Kestrel Racing M1): the renderer spike. An original flat-shaded track (our own
// generator, tools/racer/gen_track.py) drawn by the engine of freds72's PICO-8 racer (MIT; the
// tile/PVS/painter pipeline), in Q16 integers + ZM-X mulsh: a camera flies the racing line
// (the benchmark's lap v0), the PVS and a ray DDA pick the tiles, faces are back-face culled,
// transformed, clipped, bucket-sorted far to near and filled flat. docs/ports/kestrel_racing/.
//
//   3-8 draw distance R (tiles)   f the fill path: CPU word stores / CHISEL AFFINE spans
//   m mulsh instruction / plain twin   g the vertex transform in f32   d decals on / off   t oval / stress city   p pause
//   o the benchmark OSD   u the cart-only rate   c the lap CRC on / off   l back to the lap   A-H a fixed pose
// One plane in two pages (the shown one is enabled), the sky a per-line palette entry on the
// copper, the backdrop one AFFINE op. No float: nothing here costs an FPU op.
// Benchmark lines go to the console: apps/zig/scenes/racer/bench.zig.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const draw = @import("racer/draw.zig");
const bench = @import("racer/bench.zig");
const cam = @import("racer/cam.zig");
const clip = @import("racer/clip.zig");
const frame = @import("racer/frame.zig");
const fx = @import("racer/fx.zig");
const Hud = @import("racer/hud.zig").Hud;
const data = @import("racer/data.zig");
const palette = @import("racer/palette.zig");
const poly = @import("racer/poly.zig");
const report = @import("racer/report.zig");
const sinks = @import("racer/sinks.zig");
const trk = @import("racer/trk.zig");
const xf = @import("racer/xform.zig");

extern fn hostMicros() u32;
const K_ESC: u32 = 0xE012;
const TRACKS = [_][]const u8{ "OVAL", "CITY" };
const BLOBS = [_][]align(4) const u8{ data.oval, data.city };
const GROUND_RAMP = [_]usize{ 1, 8 }; // the ramp the ground beyond R takes: grass, plaza

var sky_tbl: [2][1]zg.copper.Table = undefined;

fn micros() u32 {
    return hostMicros();
}

pub const Demo = struct {
    os: *zg.ZigOS = undefined,
    tracks: [2]trk.Track = undefined,
    which: usize = 0,
    f: frame.Frame = undefined,
    p: draw.Painter = undefined,
    hud: Hud = .{},
    bench: bench.Bench = .{ .now = micros },
    r: u32 = 5,
    decals: bool = true,
    osd: bool = false,
    uncapped: bool = false,
    paused: bool = false,
    pose: ?u32 = null, // a fixed pose (A-H) instead of the lap script
    script: u32 = 0, // the lap script's frame: advanced by frames, never by the clock
    back: usize = 0,
    rep: report.Reporter = .{},
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *zg.ZigOS) void {
        self.* = .{};
        self.os = zigos;
        self.bench = .{ .now = micros };
        for (BLOBS, 0..) |b, i| self.tracks[i] = trk.parse(b) catch |e| @panic(@errorName(e));
        const nv = @max(self.tracks[0].verts.len, self.tracks[1].verts.len);
        const nf = @max(self.tracks[0].faces.len, self.tracks[1].faces.len);
        self.f = .{
            .cache = .{ .e = zg.mem.mustAlloc(xf.Entry, nv) },
            .kept = zg.mem.mustAlloc(frame.Rec, frame.MAXP),
            .key = zg.mem.mustAlloc(u16, frame.MAXP),
            .order = zg.mem.mustAlloc(u16, frame.MAXP),
            .count = &zg.mem.mustAlloc([frame.BUCKETS + 1]u32, 1)[0],
            .seen = zg.mem.mustAlloc(u32, nf),
        };
        @memset(self.f.cache.e, std.mem.zeroes(xf.Entry));
        @memset(self.f.seen, 0);
        self.p = .{ .os = zigos, .aff = .{ .buf = zg.mem.mustAlloc(sinks.Span, 2 * sinks.CHUNK) } };
        for (0..2) |p| {
            const fb = &zigos.lfbs[p];
            palette.install(fb, &self.tracks[0], GROUND_RAMP[0]);
            zg.copper.install(fb, &.{palette.SKY}, &sky_tbl[p], .{});
            palette.skyFill(zg.copper.visible(fb, 0));
            fb.is_enabled = p == 0;
        }
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        zigos.blitAsync(true);
        zg.Console.log("racer: oval {} faces, city {} faces, cart RAM free {} KB", .{ self.tracks[0].faces.len, self.tracks[1].faces.len, zg.mem.free() / 1024 });
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC => self.wants_quit = true,
            '3'...'8' => self.r = cp - '0',
            'f' => self.p.cpu_fill = !self.p.cpu_fill,
            'm' => fx.use_zmx = !fx.use_zmx,
            'g' => fx.use_f32 = !fx.use_f32,
            'd' => self.decals = !self.decals,
            'o' => self.osd = !self.osd,
            'u' => self.uncapped = !self.uncapped,
            'c' => self.rep.crc_on = !self.rep.crc_on,
            't' => self.setTrack(1 - self.which),
            'p', ' ' => self.paused = !self.paused,
            'l' => self.pose = null,
            'X' => poly.break_edge = !poly.break_edge, // the harness' --break switches (see racer_headless.mjs)
            'Y' => clip.break_drop = !clip.break_drop,
            'A'...'H' => self.pose = cp - 'A',
            else => {},
        }
    }

    fn setTrack(self: *Demo, w: usize) void {
        self.which = w;
        self.script = 0;
        self.f.seen_stamp = 0;
        @memset(self.f.seen, 0);
        for (self.f.cache.e) |*e| e.stamp = 0;
        for (0..2) |p| palette.install(&self.os.lfbs[p], &self.tracks[w], GROUND_RAMP[w]);
    }

    pub fn update(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (!self.paused and self.pose == null) self.script +%= 1;
    }

    pub fn render(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = dt;
        self.bench.frameStart();
        const done = self.back;
        zigos.lfbs[done].is_enabled = true;
        zigos.lfbs[done ^ 1].is_enabled = false;
        self.back = done ^ 1;
        const fb = &zigos.lfbs[self.back];
        const t = &self.tracks[self.which];
        const pose = if (self.pose) |k| cam.fixedPose(t, k) else cam.lapPose(t, self.script, cam.povAt(self.script));
        var v = cam.view(pose);
        if (fx.use_f32) cam.floatView(&v);
        self.p.sky(fb, &v, pose.yaw);
        self.bench.lap(.sky);
        self.f.visibility(t, &v, self.r);
        self.bench.lap(.vis);
        self.f.collect(t, &v, self.decals);
        self.bench.lap(.collect);
        self.f.sort();
        self.bench.lap(.sort);
        const counts = self.p.fill(fb, &self.f);
        self.bench.lap(.fill);
        self.finish(zigos, fb, counts);
    }

    fn knobs(self: *const Demo) bench.Knobs {
        return .{ .track = TRACKS[self.which], .r = self.r, .cpu = self.p.cpu_fill, .mul = self.mulName() };
    }

    fn mulName(self: *const Demo) []const u8 {
        _ = self;
        return if (fx.use_f32) "F32" else if (fx.use_zmx) "MULSH" else "PLAIN";
    }

    fn finish(self: *Demo, zigos: *zg.ZigOS, fb: *zg.LogicalFB, c: bench.Counts) void {
        self.hud.draw(zigos, fb, self.back, .{
            .track = TRACKS[self.which], .r = self.r, .cpu = self.p.cpu_fill, .mul = self.mulName(), .decals = self.decals,
            .pov = @tagName(if (self.pose) |k| @as(cam.Pov, @enumFromInt(k % 3)) else cam.povAt(self.script)), .polys = c.polys, .spans = c.spans, .osd = self.osd,
            .uncapped = self.uncapped, .avg_us = self.bench.avg_us, .fps10 = self.bench.fps10, .stage_us = self.bench.stage_us,
        });
        self.bench.lap(.hud);
        const closed = self.bench.frameEnd();
        self.rep.report(zigos, fb, &self.bench, self.knobs(), c, .{ .script = self.script, .scripted = self.pose == null and !self.paused });
        if (closed) self.bench.resetWindow();
    }
};

const std = @import("std");
