// --------------------------------------------------------------------------
// RACER: the track select screen (M5 step 4). Left, every track the library listed (the built-in
// oval, the disk's *.KTR, C:\RACER\'s), the cursor's row highlighted, a file the loader refused in red
// with its reason, then the files refused at the scan (not a track, too big, no RAM) by name and
// reason. Right, the cursor's track: its racing line from above (front.zig keeps the outline), its
// name, lap length, laps, the race clock (clock.zig) and the session's records on it.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const clock = @import("clock.zig");
const fd = @import("frontdraw.zig");
const menu = @import("menu.zig");
const palette = @import("palette.zig");
const racehud = @import("racehud.zig");
const rules = @import("rules.zig");
const trk = @import("trk.zig");

pub const LIST = [4]i32{ 8, 30, 152, 146 }; // x, y, w, h
pub const INFO = [4]i32{ 164, 30, 148, 146 };
pub const MAP = [4]i32{ 170, 36, 136, 70 }; // the outline's box (front.zig fits the line into it)
pub const ROW = 9;
pub var break_refuse = false; // racer_front.mjs --break refuse (key J)
pub const FOOT = "UP/DOWN TRACK  FIRE RACE  BKSP TITLE";

pub fn draw(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB, p: menu.Px) void {
    p.panel(8, 16, 304, 12);
    fd.text(os, fb, "SELECT A TRACK", 160 - 7 * 8, 18, menu.HILITE);
    p.panel(LIST[0], LIST[1], LIST[2], LIST[3]);
    p.panel(INFO[0], INFO[1], INFO[2], INFO[3]);
    p.panel(8, 178, 304, 10);
    fd.text(os, fb, FOOT, 160 - FOOT.len * 4, 179, palette.INK);
    list(d, os, fb);
    info(d, os, fb, p);
}

fn list(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB) void {
    var y: i32 = LIST[1] + 4;
    var b: [24]u8 = undefined;
    for (d.lib.list[0..d.lib.n], 0..) |*e, i| {
        if (y > LIST[1] + LIST[3] - ROW - 2) return;
        const tag: []const u8 = if (e.bad) "BAD" else switch (e.src) {
            .builtin => "BUILT-IN",
            .disk => "DISK",
            .hd => "C:\\RACER",
        };
        const ink = if (e.bad) menu.ALERT else if (i == d.front.cursor) menu.HILITE else palette.INK;
        const line = std.fmt.bufPrint(&b, "{s}{s:<8} {s}", .{ if (i == d.front.cursor) ">" else " ", e.label(), tag }) catch "";
        fd.text(os, fb, line, LIST[0] + 4, y, ink);
        y += ROW;
    }
    if (break_refuse) return;
    for (d.lib.rej.list[0..d.lib.rej.n]) |*r| {
        if (y > LIST[1] + LIST[3] - ROW - 2) return;
        const line = std.fmt.bufPrint(&b, " {s:<8} {s}", .{ r.label(), r.why.short() }) catch "";
        fd.text(os, fb, line, LIST[0] + 4, y, menu.ALERT);
        y += ROW;
    }
}

fn info(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB, p: menu.Px) void {
    const f = &d.front;
    const e = &d.lib.list[f.cursor];
    var y: i32 = MAP[1] + MAP[3] + 6;
    const x = INFO[0] + 4;
    if (e.bad or f.cursor != d.which) return refused(os, fb, e, x, y);
    outline(d, p);
    const t = d.cur();
    var b: [4][24]u8 = undefined;
    var nb: [24]u8 = undefined;
    fd.text(os, fb, std.ascii.upperString(&nb, std.mem.sliceTo(&t.name, 0)), x, y, menu.HILITE);
    y += ROW + 2;
    if (t.mood.flags & trk.BENCH_ONLY != 0) return benchOnly(os, fb, x, y);
    const c = f.clk;
    const lines = [_][]const u8{
        std.fmt.bufPrint(&b[0], "LAP {} M  {} LAPS", .{ f.lap_m, rules.LAPS }) catch "",
        std.fmt.bufPrint(&b[1], "CLOCK {}S +{}S", .{ c.start / clock.HZ, c.extend / clock.HZ }) catch "",
        record(&b[2], "BEST LAP ", d.recs[d.which].best_lap),
        record(&b[3], "BEST RACE ", d.recs[d.which].best_race),
    };
    for (lines) |l| {
        fd.text(os, fb, l, x, y, palette.INK);
        y += ROW;
    }
    if (f.msg.len != 0) fd.text(os, fb, f.msg, x, y + 2, menu.ALERT);
}

fn refused(os: *zg.ZigOS, fb: *zg.LogicalFB, e: anytype, x: i32, y: i32) void {
    fd.text(os, fb, e.label(), x, y, menu.ALERT);
    fd.text(os, fb, "REFUSED:", x, y + ROW + 2, menu.ALERT);
    fd.text(os, fb, e.why, x, y + 2 * ROW + 2, menu.ALERT);
}

fn benchOnly(os: *zg.ZigOS, fb: *zg.LogicalFB, x: i32, y: i32) void {
    fd.text(os, fb, "BENCH ONLY:", x, y, menu.ALERT);
    fd.text(os, fb, "NO RACE HERE", x, y + ROW, menu.ALERT);
}

fn record(buf: []u8, head: []const u8, t: u32) []const u8 {
    var tb: [12]u8 = undefined;
    return std.fmt.bufPrint(buf, "{s}{s}", .{ head, if (t == 0) "-:--.-" else racehud.timeStr(&tb, t) }) catch "";
}

/// The racing line from above in its box, the start marked.
fn outline(d: anytype, p: menu.Px) void {
    const m = &d.front.map;
    if (m.n < 2) return;
    const at = [2]i32{ MAP[0], MAP[1] };
    for (0..m.n) |i| {
        const a = m.pts[i];
        const b = m.pts[(i + 1) % m.n];
        p.line(.{ at[0] + a[0], at[1] + a[1] }, .{ at[0] + b[0], at[1] + b[1] }, palette.INK);
    }
    p.rect(at[0] + m.pts[0][0] - 1, at[1] + m.pts[0][1] - 1, 3, 3, menu.HILITE);
}
