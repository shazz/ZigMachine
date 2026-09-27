// --------------------------------------------------------------------------
// Showing an ST part: its screen through the shifter, and its colour registers
// as they stand on every line -- the rasters are THOSE, per-line register
// values, never pixels. Borders the part leaves closed show colour 0, as an
// ST's do, and the machine paints a closed border (the global HBL, frame.zig)
// BEFORE the cart runs; so a frame is captured one host frame ahead: capture()
// at the end of a render, present() at the start of the next, and the border
// table c0_next is filled from the same capture. Plane and borders then show
// the same iteration.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("st.zig");
const frame = @import("frame.zig");
const ram = @import("ram.zig");

pub const LINES = 200;
/// Colour registers 0..15 of each ST line, as ST words.
pub const Palettes = [LINES][16]u16;

/// Freeze what the machine will show next: `screen` (a 32000-byte buffer at
/// that address of `r`), `pal` for display lines 0..199, and colour 0 for the
/// border above and below.
pub fn capture(r: *const st.Ram, screen: u32, pal: *const Palettes, top: u16, bottom: u16) void {
    const out = ram.buf.chunky;
    for (out, 0..) |*row, y| st.lineToChunky(r.bytes(screen + @as(u32, @intCast(y)) * st.LINE, st.LINE), row);
    for (ram.buf.pal_next, 0..) |*line, py| {
        const y = @as(i32, @intCast(py)) - frame.OY;
        if (y >= 0 and y < LINES) {
            for (line, pal[@intCast(y)]) |*c, w| c.* = st.color(w);
        } else {
            @memset(line, st.color(if (y < 0) top else bottom));
        }
        frame.c0_next[py] = line[0];
    }
}

/// The captured frame into the plane: the 320x200 window at the border
/// offsets, index 0 (colour 0) around it.
pub fn present(fb: []u8) void {
    const src = ram.buf.chunky;
    for (0..frame.PH) |py| {
        const row = fb[py * frame.PW ..][0..frame.PW];
        const y = @as(i32, @intCast(py)) - frame.OY;
        if (y < 0 or y >= LINES) {
            @memset(row, 0);
            continue;
        }
        const x0: usize = @intCast(frame.OX);
        @memset(row[0..x0], 0);
        @memcpy(row[x0..][0..320], &src[@intCast(y)]);
        @memset(row[x0 + 320 ..], 0);
    }
    ram.buf.pal.* = ram.buf.pal_next.*;
    frame.c0_now = frame.c0_next;
}

test "palettes cover the ST window only" {
    try std.testing.expect(frame.OY >= 0 and frame.OY + LINES <= frame.PH);
}
