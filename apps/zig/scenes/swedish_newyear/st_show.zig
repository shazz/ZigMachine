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

// ------------------------------------------------------------------ overscan
// A frame with open borders is not a 320x200 window: each physical line has its
// own start address, first pixel and extent (TCB #1's 230-byte lines start 12
// pixels left of the plane; its first two lines are the odd ones where the
// borders open). The shifter reads 16-pixel groups of four plane words from
// the line's first byte on, whatever the address mod 8 -- which is why 230-byte
// lines rotate the plane order from one line to the next.

/// One physical line of an overscan frame: pixels in [lo, hi) show the screen,
/// read from `addr` with its first pixel at physical x `x0`; the rest is colour 0.
pub const Row = struct { addr: u32, x0: i32, lo: u16, hi: u16 };
pub const Rows = [frame.PH]?Row;

/// Colour registers 0..15 of each physical line, as ST words.
pub const LinePalettes = [frame.PH][16]u16;

/// Like capture(), for a whole overscan plane under ONE palette.
pub fn captureOverscan(r: *const st.Ram, rows: *const Rows, pal: *const [16]u16) void {
    var pals: LinePalettes = undefined;
    for (&pals) |*line| line.* = pal.*;
    captureLines(r, rows, &pals);
}

/// Like capture(), for a whole plane of physical rows, each line under its
/// own registers (OMEGA: the bottom border's palette from line 200).
pub fn captureLines(r: *const st.Ram, rows: *const Rows, pals: *const LinePalettes) void {
    for (ram.buf.plane, rows, pals, 0..) |*out, row, pal, py| {
        @memset(out, 0);
        if (row) |ln| lineAt(r, ln, out);
        for (&ram.buf.pal_next[py], pal) |*c, w| c.* = st.color(w);
        frame.c0_next[py] = ram.buf.pal_next[py][0];
    }
}

fn lineAt(r: *const st.Ram, ln: Row, out: *[frame.PW]u8) void {
    var group: [16]u8 = undefined;
    var have: i32 = -1;
    for (ln.lo..ln.hi) |x| {
        const k = @as(i32, @intCast(x)) - ln.x0;
        if (k < 0) continue;
        const g = @divFloor(k, 16);
        if (g != have) {
            st.groupToChunky(r.bytes(ln.addr + 8 * @as(u32, @intCast(g)), 8)[0..8], &group);
            have = g;
        }
        out[x] = group[@intCast(@mod(k, 16))];
    }
}

/// The captured overscan frame into the plane.
pub fn presentOverscan(fb: []u8) void {
    for (ram.buf.plane, 0..) |*row, py| @memcpy(fb[py * frame.PW ..][0..frame.PW], row);
    ram.buf.pal.* = ram.buf.pal_next.*;
    frame.c0_now = frame.c0_next;
}

test "palettes cover the ST window only" {
    try std.testing.expect(frame.OY >= 0 and frame.OY + LINES <= frame.PH);
}
