// --------------------------------------------------------------------------
// COPRO: the three HUD lines under the effect, the A/B in numbers:
//   line 1   the page, the keys
//   line 2   where its jobs run (ZIGGY / BARD / HOST: the page's loader, no
//            coprocessor), then the page's job as last measured on each side, in Mc (cycles at
//            100 MHz): ZIGGY = the cart's own time serving it; BARD = BARD's
//            cycle counter over it, written back in the job's slot
//   line 3   ZIGGY's frame (update + draw, the mean and the peak of a 32-frame
//            window, Mc), fps, and BARD's sound load (zg.mp3Status(.load):
//            the music's renders, per mille; jobs are not in it)
// The clock is env.hostMicros: 0 in the harnesses, so the numbers stay blank
// there and the frames hash the same. Redrawn only when a line's text changes.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const C = @import("common.zig");

const COLS = 40;
const Line = [COLS]u8;
pub const PAGES = 4;

pub const Hud = struct {
    shown: [3]Line = .{[_]u8{0} ** COLS} ** 3,
    t_window: u32 = 0,
    frames: u32 = 0,
    busy_us: u32 = 0,
    peak_us: u32 = 0,
    t_work: u32 = 0,
    fps10: u32 = 0,
    frame_us: u32 = 0,
    frame_peak: u32 = 0,
    job_ziggy: [PAGES]u32 = .{0} ** PAGES, // cycles, last measured
    job_copro: [PAGES]u32 = .{0} ** PAGES,

    pub fn workStart(self: *Hud) void {
        self.t_work = C.micros();
    }

    pub fn workEnd(self: *Hud) void {
        const now = C.micros();
        if (now == 0) return;
        const spent = now -% self.t_work;
        self.busy_us +%= spent;
        self.peak_us = @max(self.peak_us, spent);
        self.frames += 1;
        if (self.t_window == 0) self.t_window = now;
        if (self.frames < 32) return;
        const span = now -% self.t_window;
        if (span > 0) self.fps10 = @intCast(@min(@as(u64, 32) * 10_000_000 / span, 9999));
        self.frame_us = self.busy_us / 32;
        self.frame_peak = self.peak_us;
        self.frames = 0;
        self.busy_us = 0;
        self.peak_us = 0;
        self.t_window = now;
    }

    /// What this frame's job cost, on the side it ran on.
    pub fn job(self: *Hud, page: u32, ctx: *const C.Ctx, ran_on_ziggy: bool) void {
        if (ran_on_ziggy) {
            if (ctx.post_us != 0) self.job_ziggy[page] = ctx.post_us *% 100;
        } else if (ctx.job_cycles != 0) {
            self.job_copro[page] = ctx.job_cycles;
        }
    }

    pub fn draw(self: *Hud, os: *zg.ZigOS, fb: *zg.LogicalFB, page: u32, name: []const u8, side: []const u8) void {
        var l: [3]Line = .{[_]u8{' '} ** COLS} ** 3;
        put(&l[0], 0, "{d} {s}", .{ page + 1, name });
        put(&l[0], 31, "1-4 SPACE", .{});
        var a: [8]u8 = undefined;
        var b: [8]u8 = undefined;
        put(&l[1], 0, "{s}", .{side});
        put(&l[1], 6, "JOB  ZIGGY {s}  BARD {s}", .{ mc(&a, self.job_ziggy[page]), mc(&b, self.job_copro[page]) });
        var c: [8]u8 = undefined;
        var d: [8]u8 = undefined;
        if (self.fps10 != 0) {
            const load = zg.mp3Status(.load);
            put(&l[2], 0, "CPU {s} PEAK {s} {d}FPS SND {d}%", .{ mc(&c, self.frame_us *% 100), mc(&d, self.frame_peak *% 100), self.fps10 / 10, load / 10 });
        }
        for (&l, 0..) |*line, i| {
            if (std.mem.eql(u8, line, &self.shown[i])) continue;
            self.shown[i] = line.*;
            os.printText(fb, line, 0, @intCast(C.ROWS + 8 * i), if (i == 0) C.HUD_HI else C.HUD_INK, C.HUD_BG);
        }
    }
};

fn put(line: *Line, at: usize, comptime f: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(line[at..], f, args) catch line[at..];
    _ = s;
}

/// Cycles as "1.23MC" (blank: never measured).
fn mc(buf: *[8]u8, cycles: u32) []const u8 {
    if (cycles == 0) return "--";
    const c10k = cycles / 10_000;
    return std.fmt.bufPrint(buf, "{d}.{d:0>2}MC", .{ c10k / 100, c10k % 100 }) catch "?";
}
