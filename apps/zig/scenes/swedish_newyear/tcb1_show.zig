// --------------------------------------------------------------------------
// What TCB #1's frame shows, line by line. MEASURED on Hatari's bordered
// capture (416x276: the normal window at x 48..367, rows 29..228) by fitting
// every capture row to the noise in memory (prototypes/snyd_re/tcb/
// fit_rows.py, render_tcb1.py):
//   row 0       the line the top border opens on: from base-46, first pixel
//               at capture x -48, showing x 34..367 (314 of its 334 pixels
//               fit; its two ends come from the switch itself)
//   row 1       from base+136, first pixel at x -52, showing x 0..362 (352 of
//               363 fit: the last 14 pixels, where the right border stays shut)
//   rows 2..228 230 bytes each from base+344, first pixel at x -4, open to
//               x 411: exact
//   row 229 on  the bottom border, colour 0
// A capture row r is physical line r+11 here and capture x is physical x+8.
// The intro phase is a plain 320x200 screen from the same base.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const show = @import("st_show.zig");
const frame = @import("frame.zig");
const T = @import("tcb1.zig");

const CAPTURE_TOP = 11; // physical line of capture row 0
const CAPTURE_X = 8; // capture x = physical x + 8
const FULL_LINES = 229; // capture rows 0..228

fn row(addr: u32, cap_x0: i32, cap_lo: i32, cap_hi: i32) ?show.Row {
    const lo = @max(cap_lo - CAPTURE_X, 0);
    const hi = @min(cap_hi - CAPTURE_X, frame.PW);
    return .{ .addr = addr, .x0 = cap_x0 - CAPTURE_X, .lo = @intCast(lo), .hi = @intCast(hi) };
}

/// The rows of a fullscreen frame shown from `base`.
fn fullRows(base: u32, rows: *show.Rows) void {
    rows[CAPTURE_TOP] = row(base - 46, -48, 34, 368);
    rows[CAPTURE_TOP + 1] = row(base + 136, -52, 0, 363);
    for (2..FULL_LINES) |r| {
        const addr = base + 344 + 230 * @as(u32, @intCast(r - 2));
        rows[CAPTURE_TOP + r] = row(addr, -4, 0, 412);
    }
}

fn normalRows(base: u32, rows: *show.Rows) void {
    for (0..200) |y| {
        const x: i32 = frame.OX;
        rows[@as(usize, @intCast(frame.OY)) + y] = .{ .addr = base + st.LINE * @as(u32, @intCast(y)), .x0 = x, .lo = @intCast(x), .hi = @intCast(x + 320) };
    }
}

/// Freeze the frame the last VBL set up (st_show: shown one host frame later).
pub fn capture(t: *const T.Tcb1, r: *const st.Ram) void {
    var rows: show.Rows = [_]?show.Row{null} ** frame.PH;
    if (t.fullscreen()) fullRows(t.shown, &rows) else normalRows(t.shown, &rows);
    var pal: [16]u16 = undefined;
    for (&pal, 0..) |*c, i| c.* = r.w(T.PALETTE + 2 * @as(u32, @intCast(i)));
    pal[0] = 0; // colour 0 is written 0 every VBL
    show.captureOverscan(r, &rows, &pal);
}
