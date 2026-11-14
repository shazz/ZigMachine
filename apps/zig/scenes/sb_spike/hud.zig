// --------------------------------------------------------------------------
// SB SPIKE: two text lines in the letterbox bands, what the board reading needs.
//
//   top     LOD, triangles in the LOD, drawn this frame, AFFINE ops, the toggles
//   bottom  FPS and the cart's own time a frame (env.hostMicros: the browser and
//           the board answer it; the harnesses answer 0, so their frames stay
//           deterministic and the line shows the key help instead)
// Each plane of the flip keeps what it shows; a line is redrawn only when its
// text changed for that plane (padded, so the paper wipes the old glyphs).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

extern fn hostMicros() u32;

const COLS = 40; // a multiple of 4: the lines stay word-aligned (std.mem.eql reads words)
const Line = [COLS]u8;
pub const HELP = "1-4 LOD  E ENV  A ASYNC  C CLEAR  P PAUSE";

pub const Info = struct { lod: usize, tris: u32, drawn: u32, ops: u32, env: bool, async_: bool, clear: bool };

pub const Hud = struct {
    shown: [2][2]Line align(4) = .{ .{ [_]u8{0} ** COLS, [_]u8{0} ** COLS }, .{ [_]u8{0} ** COLS, [_]u8{0} ** COLS } },
    ink: u8 = 255,
    t_window: u32 = 0,
    t_work: u32 = 0,
    frames: u32 = 0,
    busy_us: u32 = 0,
    fps10: u32 = 0,
    cpu_us: u32 = 0,

    pub fn workStart(self: *Hud) void {
        self.t_work = hostMicros();
    }

    /// End of a frame's work: FPS and CPU over 32-frame windows.
    pub fn workEnd(self: *Hud) void {
        const now = hostMicros();
        if (now == 0) return;
        self.busy_us +%= now -% self.t_work;
        self.frames += 1;
        if (self.t_window == 0) self.t_window = now;
        if (self.frames < 32) return;
        const span = now -% self.t_window;
        if (span > 0) self.fps10 = @intCast(@min(@as(u64, 32) * 10_000_000 / span, 9999));
        self.cpu_us = self.busy_us / 32;
        self.frames = 0;
        self.busy_us = 0;
        self.t_window = now;
    }

    pub fn draw(self: *Hud, os: *zg.ZigOS, fb: *zg.LogicalFB, plane: usize, i: Info) void {
        var l: [2]Line align(4) = undefined;
        var b0: [64]u8 = undefined;
        pad(&l[0], std.fmt.bufPrint(&b0, "MIX3 {}X T{} D{} OPS{} {s}{s}{s}", .{
            i.lod + 1,                       i.tris,                         i.drawn, i.ops,
            if (i.env) "ENV " else "",        if (i.async_) "ASY " else "",   if (i.clear) "CLR" else "",
        }) catch "");
        var b1: [64]u8 = undefined;
        pad(&l[1], if (self.fps10 == 0) HELP else std.fmt.bufPrint(&b1, "FPS {}.{}  CPU {}US", .{ self.fps10 / 10, self.fps10 % 10, self.cpu_us }) catch "");
        const ys = [2]i16{ 1, 191 };
        for (0..2) |k| {
            if (std.mem.eql(u8, &l[k], &self.shown[plane][k])) continue;
            self.shown[plane][k] = l[k];
            os.printText(fb, &l[k], 0, ys[k], self.ink, 0);
        }
    }
};

fn pad(dst: *Line, text: []const u8) void {
    const n = @min(text.len, COLS);
    @memcpy(dst[0..n], text[0..n]);
    @memset(dst[n..], ' ');
}
