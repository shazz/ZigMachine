// --------------------------------------------------------------------------
// The shifter (shifter.zig) for the parts that change colour registers
// between lines from Timer B and open borders: a frame is captured line by
// line, each physical row with the registers the part's interrupt chain
// leaves for it, and the rows whose border the part opens are flickered open
// by the plane's HBL, as the ST's 50/60 Hz or resolution switch opens them.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const sh = @import("shifter.zig");

/// A low-res screen at `screen` under per-line registers: ST line y (the
/// window's row y; past 199 the bottom border) shows under pals[y], for
/// y < pals.len. From line `open_from` on, the bottom border is open, so
/// the screen runs on below the window; the side borders stay closed
/// (colour 0). Rows above the window and past pals.len are border.
pub fn capture(r: *const st.Ram, screen: u32, pals: []const [16]u16, open_from: usize) void {
    for (0..sh.PH) |py| {
        const out = sh.physRow(py);
        @memset(out, 0);
        const y = py -% sh.OY;
        const k = if (py < sh.OY) 0 else @min(y, pals.len - 1);
        sh.setRegs(py, &sh.rgba(pals[k]));
        sh.setOpen(py, py >= sh.OY and y < pals.len and y >= open_from);
        if (py < sh.OY or y >= pals.len) continue;
        const line = r.bytes(screen + @as(u32, @intCast(y)) * st.LINE, st.LINE);
        st.lineToChunky(line, out[sh.OX..][0..320]);
    }
}

/// Bytes of a line with the left and right borders open.
pub const FULL_LINE = 230;
/// A full-overscan line's pixel 0 sits this far left of the plane's x 0
/// (the open left border reaches 52 pixels past the window, the plane 40).
const FULL_SKIP = 12;

/// A full-overscan picture: `lines` lines of 230 bytes from `start`, its
/// line 0 on ST line `first` (negative: in the opened top border), every
/// border open there (flickered), under one palette; the rest is border.
pub fn captureFull(r: *const st.Ram, start: u32, lines: usize, first: i32, pal: [16]u16, border: u16) void {
    const top: usize = @intCast(@as(i32, @intCast(sh.OY)) + first);
    const regs = sh.rgba(pal);
    const edge = sh.rgba([_]u16{border} ** 16);
    for (0..sh.PH) |py| {
        const out = sh.physRow(py);
        @memset(out, 0);
        const inside = py >= top and py < top + lines;
        sh.setRegs(py, if (inside) &regs else &edge);
        sh.setOpen(py, inside);
        if (!inside) continue;
        var px: [416]u8 = undefined;
        const line = r.bytes(start + @as(u32, @intCast(py - top)) * FULL_LINE, 26 * 8);
        for (0..26) |g| st.groupToChunky(line[g * 8 ..][0..8], px[g * 16 ..][0..16]);
        @memcpy(out, px[FULL_SKIP..][0..sh.PW]);
    }
}
