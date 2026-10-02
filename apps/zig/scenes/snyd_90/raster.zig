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
