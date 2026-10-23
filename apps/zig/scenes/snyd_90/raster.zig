// --------------------------------------------------------------------------
// The shifter (shifter.zig) for the parts that change colour registers
// between lines from Timer B and open borders: a frame is captured line by
// line, each physical row with the registers the part's interrupt chain
// leaves for it, and the rows whose border the part opens are flickered open
// by the plane's HBL, as the ST's 50/60 Hz or resolution switch opens them.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("../swedish_newyear/st.zig");
const sh = @import("shifter.zig");

/// A low-res screen at `screen` under per-line registers: ST line y (the
/// window's row y; past 199 the bottom border) shows under pals[y], for
/// y < pals.len. From line `open_from` on, the bottom border is open, so
/// the screen runs on below the window; the side borders stay closed
/// (colour 0). Rows above the window and past pals.len are border.
pub fn capture(r: *const st.Ram, screen: u32, pals: []const [16]u16, open_from: usize) void {
    var last: [16]u16 = undefined; // the registers rarely change line to line: convert on change
    var regs: [16]u32 = undefined;
    var have = false;
    for (0..sh.PH) |py| {
        const y = py -% sh.OY;
        const k = if (py < sh.OY) 0 else @min(y, pals.len - 1);
        if (!have or !std.mem.eql(u16, &last, &pals[k])) {
            last = pals[k];
            regs = sh.rgba(last);
            have = true;
        }
        sh.setRegs(py, &regs);
        sh.setOpen(py, py >= sh.OY and y < pals.len and y >= open_from);
        if (py < sh.OY or y >= pals.len) {
            sh.blankRow(py);
            continue;
        }
        sh.window(r, py, screen + @as(u32, @intCast(y)) * st.LINE);
    }
}

/// Bytes of a line with the left and right borders open.
pub const FULL_LINE = 230;
/// A full-overscan picture: `lines` lines of 230 bytes from `start`, its
/// line 0 on ST line `first` (negative: in the opened top border), every
/// border open there (flickered), under one palette; the rest is border.
pub fn captureFull(r: *const st.Ram, start: u32, lines: usize, comptime first: i32, pal: [16]u16, border: u16) void {
    const top: usize = comptime @intCast(@as(i32, @intCast(sh.OY)) + first); // a line above the frame fails to build
    const regs = sh.rgba(pal);
    const edge = sh.rgba([_]u16{border} ** 16);
    for (0..sh.PH) |py| {
        const inside = py >= top and py < top + lines;
        sh.setRegs(py, if (inside) &regs else &edge);
        sh.setOpen(py, inside);
        if (inside) sh.full(r, py, start + @as(u32, @intCast(py - top)) * FULL_LINE) else sh.blankRow(py);
    }
}
