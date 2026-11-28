// --------------------------------------------------------------------------
// RACER: the course select screen (M5 step 4; the board batch's layout, item 9: the mechanic of the 32X's course select
// in our own frame, fonts and colours). Top, the cursor's course as a turning 3D model (coursemesh.zig, baked at the
// library scan; coursedraw.zig). Under it, its name, lap length, laps (the options'), the race clock (clock.zig) and the
// session's best lap and best race on it. Bottom, a strip of the courses as outlines and file names, the cursor's
// highlighted, a file the loader refused in red, five a page; under it the files refused at the scan (not a track, too big, no RAM) by name
// and reason. All from the library scan's previews (preview.zig): nothing is loaded while the cursor moves.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const clock = @import("clock.zig");
const coursedraw = @import("coursedraw.zig");
const fd = @import("frontdraw.zig");
const menu = @import("menu.zig");
const palette = @import("palette.zig");
const racehud = @import("racehud.zig");
const rules = @import("rules.zig");

pub const INFO = [4]i32{ 8, 108, 304, 31 }; // x, y, w, h
pub const STRIP = [2]i32{ 8, 141 }; // the outlines' strip: x, y
pub const BOX = [2]i32{ 59, 27 }; // a strip box: w, h (61 apart)
pub const REFUSED_Y = 170;
pub const PER_PAGE = 5;
pub const ROW = 9;
pub var break_refuse = false; // racer_front.mjs --break refuse (key J)
pub const FOOT = "UP/DN COURSE FIRE CAR RIGHT OPTS BKSP";

pub fn draw(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB, p: menu.Px) void {
    const f = &d.front;
    if (!d.lib.list[f.cursor].bad) if (@import("courses.zig").get(f.cursor)) |m| coursedraw.draw(d, fb, m, f.frames);
    os.blitSync(); // WHY: the model's AFFINE spans land before the panels
    p.panel(8, 16, 304, 12);
    fd.text(os, fb, "SELECT A COURSE", 160 - 15 * 4, 18, menu.HILITE);
    p.panel(INFO[0], INFO[1], INFO[2], INFO[3]);
    info(d, os, fb);
    strip(d, os, fb, p);
    refusedLine(d, os, fb);
    p.panel(8, 178, 304, 10);
    fd.text(os, fb, FOOT, 160 - FOOT.len * 4, 179, palette.INK);
}

fn info(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB) void {
    const f = &d.front;
    const e = &d.lib.list[f.cursor];
    const pv = d.lib.preview(f.cursor);
    const x = INFO[0] + 4;
    const y = INFO[1] + 3;
    const r = INFO[0] + INFO[2] - 4;
    if (e.bad or !pv.ready) {
        fd.text(os, fb, e.label(), x, y, menu.ALERT);
        fd.text(os, fb, "REFUSED:", x, y + ROW, menu.ALERT);
        return fd.text(os, fb, e.why, x, y + 2 * ROW, menu.ALERT);
    }
    var nb: [24]u8 = undefined;
    fd.text(os, fb, std.ascii.upperString(&nb, pv.label())[0..@min(pv.label().len, 24)], x, y, menu.HILITE);
    if (pv.bench_only) {
        fd.text(os, fb, "BENCH ONLY:", x, y + ROW, menu.ALERT);
        return fd.text(os, fb, "NO RACE HERE", x, y + 2 * ROW, menu.ALERT);
    }
    var b: [4][24]u8 = undefined;
    const c = pv.clk();
    const rec = &d.recs[f.cursor];
    fd.text(os, fb, std.fmt.bufPrint(&b[0], "LAP {} M  {} LAPS", .{ pv.lap_m, rules.race_laps }) catch "", x, y + ROW, palette.INK);
    fd.text(os, fb, std.fmt.bufPrint(&b[1], "CLOCK {}S +{}S", .{ c.start / clock.HZ, c.extend / clock.HZ }) catch "", x, y + 2 * ROW, palette.INK);
    if (f.msg.len != 0) return right(os, fb, f.msg, r, y, menu.ALERT);
    right(os, fb, record(&b[2], "BEST LAP ", rec.best_lap), r, y + ROW, palette.INK);
    right(os, fb, record(&b[3], "BEST RACE ", rec.bestRace(rules.race_laps)), r, y + 2 * ROW, palette.INK);
}

fn right(os: *zg.ZigOS, fb: *zg.LogicalFB, s: []const u8, r: i32, y: i32, ink: u8) void {
    fd.text(os, fb, s, r - @as(i32, @intCast(s.len)) * 8, y, ink);
}

fn record(buf: []u8, head: []const u8, t: u32) []const u8 {
    var tb: [12]u8 = undefined;
    return std.fmt.bufPrint(buf, "{s}{s}", .{ head, if (t == 0) "-:--.-" else racehud.timeStr(&tb, t) }) catch "";
}

/// The files refused at the scan, by name and reason, on one line.
fn refusedLine(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB) void {
    if (break_refuse or d.lib.rej.n == 0) return;
    var b: [40]u8 = undefined;
    var n: usize = 0;
    for (d.lib.rej.list[0..d.lib.rej.n]) |*r| {
        const w = std.fmt.bufPrint(b[n..], "{s} {s}  ", .{ r.label(), r.why.short() }) catch break;
        n += w.len;
    }
    fd.text(os, fb, b[0..n], 8, REFUSED_Y, menu.ALERT);
}

/// The page of the strip the cursor is on: five courses.
fn strip(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB, p: menu.Px) void {
    const page = d.front.cursor / PER_PAGE * PER_PAGE;
    for (page..@min(page + PER_PAGE, d.lib.n)) |i| {
        const x = STRIP[0] + @as(i32, @intCast(i - page)) * (BOX[0] + 2);
        const y = STRIP[1];
        if (i == d.front.cursor) p.rect(x - 1, y - 1, BOX[0] + 2, BOX[1] + 2, menu.HILITE);
        p.panel(x, y, BOX[0], BOX[1]);
        const e = &d.lib.list[i];
        const pv = d.lib.preview(i);
        const ink = if (e.bad) menu.ALERT else if (i == d.front.cursor) menu.HILITE else palette.INK;
        fd.text(os, fb, e.label()[0..@min(e.label().len, 7)], x + 2, y + 18, ink);
        if (!e.bad and pv.ready) outline(p, &pv.map, x + 16, y + 2, ink);
    }
}

/// A course's racing line from above at a fifth of the preview's box (136 x 70 -> 27 x 14, over the name), the start marked.
fn outline(p: menu.Px, m: anytype, x: i32, y: i32, ink: u8) void {
    if (m.n < 2) return;
    for (0..m.n) |i| {
        const a = m.pts[i];
        const b = m.pts[(i + 1) % m.n];
        p.line(.{ x + @divTrunc(@as(i32, a[0]), 5), y + @divTrunc(@as(i32, a[1]), 5) }, .{ x + @divTrunc(@as(i32, b[0]), 5), y + @divTrunc(@as(i32, b[1]), 5) }, ink);
    }
    p.rect(x + @divTrunc(@as(i32, m.pts[0][0]), 5) - 1, y + @divTrunc(@as(i32, m.pts[0][1]), 5) - 1, 3, 3, menu.ALERT);
}
