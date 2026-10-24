// --------------------------------------------------------------------------
// OBJ demo: the text lines (mode and object, V/F and the clock, key help),
// outside the rows the object can reach (24..175). A line is redrawn only when
// its text changes ("only modify what needs to be modified"); each is padded
// to a fixed width so the glyphs' paper wipes the old text.
//
// The clock is env.hostMicros (a benchmark aid, decisions.md 2026-10-10): the
// browser and the board answer it, the harnesses answer 0 and the line then
// shows V/F only, so their frames stay deterministic. FPS is frames over
// 32-frame windows; CPU is the cart's own update+render time, averaged.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

extern fn hostMicros() u32;

const LEVELS = @import("sphere.zig").LEVELS.len;

pub const INK: u8 = 200;
const COLS = 38;
const Line = [COLS]u8;
const ROWS = [3]i16{ 8, 16, 184 };
pub const HELP = "1-3 OBJECT  S SHADE  +/- RES  C SPLIT";

pub const Hud = struct {
    shown: [3]Line = .{ [_]u8{0} ** COLS, [_]u8{0} ** COLS, [_]u8{0} ** COLS },
    t_window: u32 = 0, // hostMicros() at the window's first frame
    frames: u32 = 0,
    busy_us: u32 = 0, // update+render time summed over the window
    t_work: u32 = 0,
    fps10: u32 = 0, // last window's fps x 10, 0 = no clock yet
    cpu_us: u32 = 0,

    pub fn workStart(self: *Hud) void {
        self.t_work = hostMicros();
    }

    /// End of a frame's work: accumulate, and close a window every 32 frames.
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

    pub const Info = struct { mode: []const u8, object: []const u8, level: ?u8, split: []const u8, v: u16, f: u16 };

    pub fn draw(self: *Hud, os: *zg.ZigOS, fb: *zg.LogicalFB, i: Info) void {
        var l: [3]Line = undefined;
        var obuf: [COLS]u8 = undefined;
        const obj = if (i.level) |lv| std.fmt.bufPrint(&obuf, "{s:<8} {s} {}/{} {s}", .{ i.mode, i.object, lv + 1, LEVELS, i.split }) catch "" else std.fmt.bufPrint(&obuf, "{s:<8} {s} {s}", .{ i.mode, i.object, i.split }) catch "";
        pad(&l[0], obj);
        var cbuf: [28]u8 = undefined;
        const clock = if (self.fps10 == 0) "" else std.fmt.bufPrint(&cbuf, "  FPS {}.{} CPU {}US", .{ self.fps10 / 10, self.fps10 % 10, self.cpu_us }) catch "";
        var vf: [COLS]u8 = undefined;
        pad(&l[1], std.fmt.bufPrint(&vf, "V {} F {}{s}", .{ i.v, i.f, clock }) catch "");
        pad(&l[2], HELP);
        for (0..3) |k| {
            if (std.mem.eql(u8, &l[k], &self.shown[k])) continue;
            self.shown[k] = l[k];
            os.printText(fb, &l[k], if (k == 2) 8 else 10, ROWS[k], INK, 0);
        }
    }
};

fn pad(dst: *Line, text: []const u8) void {
    var tmp: Line = undefined;
    const n = @min(text.len, COLS);
    @memcpy(tmp[0..n], text[0..n]);
    @memset(tmp[n..], ' ');
    dst.* = tmp;
}
