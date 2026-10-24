// The budget page (Shift+F11, or > from the debug page): where the cart's frame goes, from the
// video probe (budget.zig), smoothed over a second, with the peak of the last three.
//
//   row 0   title bar
//   row 1   the frame as a bar, one cell = 1/16 of a 60 fps frame (104 Kc): C cart, F FRESCO,
//           H handlers + planner, o other, . the VBL wait; past the 16th cell the frame is late
//   row 2   the 60 fps and 30 fps marks under it
//   rows 3+ the numbers, then what the cart may still spend at 60 fps
const std = @import("std");
const osd = @import("osd.zig");
const budget = @import("budget.zig");

pub const View = struct {
    avg: ?budget.Sample = null, // null: no probe (an old firmware, or no cart)
    peak: budget.Sample = .{},
    fps_x10: ?u32 = null,
    frames: ?u32 = null, // the last second's
    missed: ?u32 = null,
};

pub const CELL: u32 = budget.FRAME_60 / 16;

pub fn draw(o: *osd.Osd, v: *const View) void {
    o.line(0, " FRAME BUDGET   live  Esc", true);
    const s = v.avg orelse {
        o.line(2, "no video probe: no cart running,", false);
        o.line(3, "or a firmware without ZM_VSTAT", false);
        return;
    };
    var bar: [osd.COLS]u8 = undefined;
    barText(&bar, s);
    o.put(0, 1, &bar, false);
    var marks = [_]u8{' '} ** osd.COLS;
    @memcpy(marks[10..16], "60fps^");
    @memcpy(marks[26..32], "30fps^");
    o.put(0, 2, &marks, false);
    var b: [12][osd.COLS]u8 = undefined;
    var t: [8][8]u8 = undefined;
    const lines = [_][]const u8{
        p(&b[0], "frame  {s} Mc {d:>3}%  peak {s}", .{ mcs(&t[0], s.busy()), budget.percent(s), mcs(&t[1], v.peak.busy()) }),
        p(&b[1], "cart   {s} Mc       peak {s}", .{ mcs(&t[2], s.cart), mcs(&t[3], v.peak.cart) }),
        p(&b[2], "FRESCO {s} Mc  {s} planes", .{ mcs(&t[4], s.fresco), budget.planesText(&t[5], s.passes) }),
        p(&b[3], "hbl+pl {s} Mc  passes {d}", .{ mcs(&t[6], s.hbl), s.passes }),
        p(&b[4], "other  {s} Mc  idle {s}", .{ mcs(&t[7], s.other), mcs(&t[0], s.idle) }),
        p(&b[5], "fps    {s}  missed {s}/{s}", .{ tenths(&t[1], v.fps_x10), num(&t[2], v.missed), num(&t[3], v.frames) }),
        "",
        headroomLine(&b[6], s),
        p(&b[7], "  at 60 fps with {s} planes", .{budget.planesText(&t[4], s.passes)}),
        "",
        "C cart F FRESCO H hbl o other",
        ". VBL wait   1 cell = 104 Kc",
    };
    for (lines, 0..) |l, i| o.line(@intCast(3 + i), l, false);
}

/// The frame as 32 cells of 1/16 frame each: cart, FRESCO, handlers, other, then the VBL wait.
pub fn barText(buf: *[osd.COLS]u8, s: budget.Sample) void {
    @memset(buf, ' ');
    var at: usize = 0;
    const parts = [_]struct { u8, u32 }{ .{ 'C', s.cart }, .{ 'F', s.fresco }, .{ 'H', s.hbl }, .{ 'o', s.other }, .{ '.', s.idle } };
    var used: u64 = 0;
    for (parts) |part| {
        used += part[1];
        const end: usize = @intCast(@min(osd.COLS, (used + CELL / 2) / CELL));
        while (at < end) : (at += 1) buf[at] = part[0];
    }
}

fn headroomLine(buf: *[osd.COLS]u8, s: budget.Sample) []const u8 {
    var t: [8]u8 = undefined;
    const h = s.headroom();
    if (h < 0) return p(buf, "60 fps: over by {s} Mc", .{mcs(&t, @intCast(-h))});
    return p(buf, "cart may spend ~{s} Mc", .{mcs(&t, @intCast(h))});
}

fn p(buf: *[osd.COLS]u8, comptime fmt: []const u8, args: anytype) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    w.print(fmt, args) catch {}; // a long line is clipped at 32 columns
    return w.buffered();
}

fn mcs(buf: *[8]u8, c: u64) []const u8 {
    return budget.mcText(buf, c);
}

fn tenths(buf: *[8]u8, v: ?u32) []const u8 {
    const x = v orelse return "-";
    return std.fmt.bufPrint(buf, "{d}.{d}", .{ x / 10, x % 10 }) catch "?";
}

fn num(buf: *[8]u8, v: ?u32) []const u8 {
    return std.fmt.bufPrint(buf, "{d}", .{v orelse return "-"}) catch "?";
}
