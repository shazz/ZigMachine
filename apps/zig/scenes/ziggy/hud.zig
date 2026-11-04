// --------------------------------------------------------------------------
// ZIGGY showcase: the two text lines under the picture (rows 184 and 192; the 8 px
// font's last row is 199, the plane's last),
// redrawn only when their text changes.
//   line 1   the mode, the texture size, ZM-X on/off, the keys
//   line 2   FPS, the cart's own time a frame in Mc (cycles at 100 MHz, the
//            board's ZIGGY) and cycles a pixel of the picture area
// The clock is env.hostMicros (decisions.md 2026-10-10): the browser and the
// board answer it, the harnesses answer 0 and line 2 then stays blank, so
// their frames are deterministic. In the browser the numbers are the host's
// wasm speed, not ZIGGY's: they mean something on the board.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const maps = @import("maps.zig");

extern fn hostMicros() u32;

const COLS = 40;
const Line = [COLS]u8;
const Y = [2]i16{ 184, 192 };
const PIXELS: u32 = 320 * 184;

pub const Hud = struct {
    shown: [2]Line = .{ [_]u8{0} ** COLS, [_]u8{0} ** COLS },
    t_window: u32 = 0,
    frames: u32 = 0,
    busy_us: u32 = 0,
    t_work: u32 = 0,
    fps10: u32 = 0, // 0 = no clock yet
    cpu_us: u32 = 0,

    pub fn workStart(self: *Hud) void {
        self.t_work = hostMicros();
    }

    /// End of a frame's work; a window closes every 32 frames.
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

    /// Forget the window (a mode switch: the old numbers are another loop's).
    pub fn reset(self: *Hud) void {
        self.* = .{ .shown = self.shown };
    }

    pub fn draw(self: *Hud, os: *zg.ZigOS, fb: *zg.LogicalFB, mode: []const u8, size: u32, zmx_on: bool) void {
        var l: [2]Line = undefined;
        var b0: [COLS]u8 = undefined;
        var tb: [8]u8 = undefined;
        const tex = if (size == 0) "    " else std.fmt.bufPrint(&tb, "{d:>3} ", .{size}) catch "";
        pad(&l[0], std.fmt.bufPrint(&b0, "{s} {s}ZM-X {s}  1/2 T Z F +-", .{ mode, tex, if (zmx_on) "ON " else "OFF" }) catch "");
        var b1: [COLS]u8 = undefined;
        if (self.fps10 == 0) {
            pad(&l[1], "");
        } else {
            const c100: u32 = self.cpu_us / 100; // Mc x 100 (100 cycles a microsecond)
            const cpx10: u32 = @intCast(@as(u64, self.cpu_us) * 1000 / PIXELS); // cycles a pixel x 10
            pad(&l[1], std.fmt.bufPrint(&b1, "FPS {}.{}  {}.{d:0>2} MC  {}.{} C/PX", .{ self.fps10 / 10, self.fps10 % 10, c100 / 100, c100 % 100, cpx10 / 10, cpx10 % 10 }) catch "");
        }
        for (0..2) |k| {
            if (std.mem.eql(u8, &l[k], &self.shown[k])) continue;
            self.shown[k] = l[k];
            os.printText(fb, &l[k], 0, Y[k], maps.INK, maps.PAPER);
        }
    }

    /// Repaint both lines next draw (the picture area under them was cleared).
    pub fn invalidate(self: *Hud) void {
        self.shown = .{ [_]u8{0} ** COLS, [_]u8{0} ** COLS };
    }
};

fn pad(dst: *Line, text: []const u8) void {
    var tmp: Line = undefined;
    const n = @min(text.len, COLS);
    @memcpy(tmp[0..n], text[0..n]);
    @memset(tmp[n..], ' ');
    dst.* = tmp;
}
