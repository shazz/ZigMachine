// --------------------------------------------------------------------------
// What F6 shows: its Timer B chain, line by line.
//   line 3     ($1258C, Timer B after line 0, then a sync on the video
//              counter) a REAL raster line: 32 writes to colour 0, one every
//              16 pixels, from the table at $127FA (it steps one entry a
//              frame: the colours sweep), then colour 0 back to black
//   line 170   ($12690, 169 lines on) the logo's palette $12B96
//   line 200   ($126C4) the second raster line (the table 15 entries on,
//              32 pixels later) and the bottom border opened: the screen
//              runs on under it -- the logo and the balls' reflection
// The colour-0 writes happen while the beam crosses the line, borders
// included, so a raster line is opened (flickered) here and its colour-0
// pixels are given the register's value at their position: entries 16..47
// of that line's palette. Where in the line the writes start was measured on
// Hatari (x0 below); the rest of the beam race is not modelled.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const sh = @import("shifter.zig");

const RASTER: u32 = 0x127FA;
const LOGO_LINE = 170;
const OPEN_FROM = 200;
const LINES = 240;
/// The raster lines: ST line, table offset, first write's plane x.
const Rule = struct { y: usize, skip: u32, x0: i32 };
const RULES = [2]Rule{ .{ .y = 3, .skip = 0, .x0 = -40 }, .{ .y = 200, .skip = 0x1E, .x0 = -8 } };

pub fn capture(r: *const st.Ram, screen: u32) void {
    const balls = palette(r, 0x12B76);
    const logo = palette(r, 0x12B96);
    for (0..sh.PH) |py| {
        const out = sh.physRow(py);
        @memset(out, 0);
        if (py < sh.OY or py >= sh.OY + LINES) {
            sh.setRegs(py, balls[0..1]);
            sh.setOpen(py, false);
            continue;
        }
        const y = py - sh.OY;
        st.lineToChunky(r.bytes(screen + @as(u32, @intCast(y)) * st.LINE, st.LINE), out[sh.OX..][0..320]);
        var regs: [sh.MAXC]u32 = undefined;
        regs[0..16].* = if (y < LOGO_LINE) balls else logo;
        var n: usize = 16;
        var open = y >= OPEN_FROM;
        for (RULES) |rule| if (rule.y == y) {
            rasterLine(r, out, &regs, rule);
            n = sh.MAXC;
            open = true;
        };
        sh.setRegs(py, regs[0..n]);
        sh.setOpen(py, open);
    }
}

fn palette(r: *const st.Ram, at: u32) [16]u32 {
    var pal: [16]u16 = undefined;
    for (&pal, 0..) |*c, i| c.* = r.w(at + 2 * @as(u32, @intCast(i)));
    return sh.rgba(pal);
}

/// Colour 0's 32 values across the line: entries 16..47, and every pixel
/// of colour 0 pointed at the one the beam met it under.
fn rasterLine(r: *const st.Ram, out: *[sh.PW]u8, regs: *[sh.MAXC]u32, rule: Rule) void {
    const table = r.l(RASTER) + rule.skip;
    for (0..32) |k| regs[16 + k] = st.color(r.w(table + 2 * @as(u32, @intCast(k))));
    for (out, 0..) |*px, x| {
        if (px.* != 0) continue;
        const d = @as(i32, @intCast(x)) - rule.x0;
        if (d < 0 or d >= 32 * 16) continue; // before the writes, after the clr: black
        px.* = @intCast(16 + @divTrunc(d, 16));
    }
}
