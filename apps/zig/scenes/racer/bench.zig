// --------------------------------------------------------------------------
// RACER benchmark mode v0 (PORT_PLAN 2.5): per-stage timers on env.hostMicros (the only cart
// clock: ~100 cycles of resolution at 100 MHz; the headless harnesses answer 0), counted in
// 32-frame windows (avg of each stage, min / max of the frame), and printed as CSV on the console
// (zg.Console.log; on the board the serial path is the open point listed in the M1 note):
//
//   racer,csv,<frame>,<track>,<R>,<fill>,<mulsh>,<tiles>,<faces>,<verts>,<polys>,<spans>,<pixels>,
//         <vis>,<collect>,<sort>,<sky>,<fill>,<hud>,<avg_us>,<min_us>,<max_us>,<fps10>
//   racer,crc,<lap frame>,<crc32 of the shown view>          every 60 lap frames (the lap's CRC list)
//   racer,lap,<frames>,<knobs>,<avg_us>,<max_us>,<crc xor>   at the lap's end
// The lap is a script of frames (cam.lapPose), so the same CRC list comes out of the browser, a
// board and (later) PEREGRINE at equal knobs, whatever each frame cost.
// No ZigOS import: the logger is a parameter, bench_test.zig drives it with a fake clock.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Stage = enum(u3) { vis, collect, sort, sky, fill, hud };
pub const NSTAGE = 6;
pub const WINDOW = 32;
pub const CRC_EVERY = 60;

pub const Counts = struct { tiles: u32 = 0, faces: u32 = 0, verts: u32 = 0, polys: u32 = 0, spans: u32 = 0, pixels: u32 = 0 };
pub const Knobs = struct { track: []const u8, r: u32, cpu: bool, mul: []const u8 }; // mul: "mulsh", "plain" or "f32"

pub const Bench = struct {
    now: *const fn () u32,
    mark: u32 = 0,
    start: u32 = 0,
    cur: [NSTAGE]u32 = [_]u32{0} ** NSTAGE,
    sum: [NSTAGE]u64 = [_]u64{0} ** NSTAGE,
    total_sum: u64 = 0,
    min: u32 = 0xFFFF_FFFF,
    max: u32 = 0,
    n: u32 = 0,
    window_t0: u32 = 0,
    lap_sum: u64 = 0,
    lap_n: u32 = 0,
    lap_max: u32 = 0,
    avg_us: u32 = 0, // the last window, for the OSD
    fps10: u32 = 0,
    stage_us: [NSTAGE]u32 = [_]u32{0} ** NSTAGE,

    pub fn frameStart(self: *Bench) void {
        self.start = self.now();
        self.mark = self.start;
        self.cur = [_]u32{0} ** NSTAGE;
    }

    /// Bill the time since the last mark to `s`.
    pub fn lap(self: *Bench, s: Stage) void {
        const t = self.now();
        self.cur[@intFromEnum(s)] +%= t -% self.mark;
        self.mark = t;
    }

    /// End of a frame's work. Returns true when a 32-frame window just closed (the caller prints).
    pub fn frameEnd(self: *Bench) bool {
        const t = self.now();
        const total = t -% self.start;
        for (self.cur, 0..) |c, i| self.sum[i] += c;
        self.total_sum += total;
        self.lap_sum += total;
        self.lap_n += 1;
        self.lap_max = @max(self.lap_max, total);
        self.min = @min(self.min, total);
        self.max = @max(self.max, total);
        self.n += 1;
        if (self.window_t0 == 0) self.window_t0 = t;
        if (self.n < WINDOW) return false;
        const span = t -% self.window_t0;
        self.fps10 = if (span > 0) @intCast(@min(@as(u64, WINDOW) * 10_000_000 / span, 9999)) else 0;
        self.avg_us = @intCast(self.total_sum / WINDOW);
        for (&self.stage_us, self.sum) |*o, s| o.* = @intCast(s / WINDOW);
        self.window_t0 = t;
        return true;
    }

    pub fn resetWindow(self: *Bench) void {
        self.sum = [_]u64{0} ** NSTAGE;
        self.total_sum = 0;
        self.min = 0xFFFF_FFFF;
        self.max = 0;
        self.n = 0;
    }

    pub fn csv(self: *const Bench, buf: []u8, frame: u32, k: Knobs, c: Counts) []const u8 {
        const s = self.stage_us;
        return std.fmt.bufPrint(buf, "racer,csv,{},{s},{},{s},{s},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}", .{
            frame,                       k.track,                      k.r,                         if (k.cpu) "cpu" else "affine", k.mul,
            c.tiles,                     c.faces,                      c.verts,                     c.polys,                        c.spans,
            c.pixels,                    s[0],                         s[1],                        s[2],                           s[3],
            s[4],                        s[5],                         self.avg_us,                 self.min,                       self.max,
            self.fps10,
        }) catch "racer,csv,overflow";
    }

    pub fn summary(self: *const Bench, buf: []u8, k: Knobs, crc_xor: u32) []const u8 {
        const avg: u32 = if (self.lap_n == 0) 0 else @intCast(self.lap_sum / self.lap_n);
        return std.fmt.bufPrint(buf, "racer,lap,{},{s} R{} {s} {s},{},{},{x:0>8}", .{
            self.lap_n, k.track, k.r, if (k.cpu) "cpu" else "affine", k.mul, avg, self.lap_max, crc_xor,
        }) catch "racer,lap,overflow";
    }

    pub fn resetLap(self: *Bench) void {
        self.lap_sum = 0;
        self.lap_n = 0;
        self.lap_max = 0;
    }
};

pub fn crcLine(buf: []u8, lap_frame: u32, crc: u32) []const u8 {
    return std.fmt.bufPrint(buf, "racer,crc,{},{x:0>8}", .{ lap_frame, crc }) catch "racer,crc,overflow";
}
