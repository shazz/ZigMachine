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
const rows_ = @import("st_rows.zig");
const conv = @import("st_convert.zig");

pub const LINES = 200;
/// Colour registers 0..15 of each ST line, as ST words.
pub const Palettes = [LINES][16]u16;

/// Freeze what the machine will show next: `screen` (a 32000-byte buffer at
/// that address of `r`), `pal` for display lines 0..199, and colour 0 for the
/// border above and below. The window is rows OY.. of the same plane an overscan
/// frame uses (320 pixels from column OX, colour 0 around), so both paths share
/// one converter and one present.
pub fn capture(r: *const st.Ram, screen: u32, pal: *const Palettes, top: u16, bottom: u16) void {
    var rows: Rows = [_]?Row{null} ** frame.PH;
    for (0..LINES) |y| {
        const addr = screen + @as(u32, @intCast(y)) * st.LINE;
        rows[y + @as(usize, @intCast(frame.OY))] = .{ .addr = addr, .x0 = frame.OX, .lo = @intCast(frame.OX), .hi = @intCast(frame.OX + 320) };
    }
    conv.convertRows(r, &rows);
    const above_w: [16]u16 = @splat(top);
    const below_w: [16]u16 = @splat(bottom);
    var prev: ?*const [16]u16 = null;
    for (0..frame.PH) |py| {
        const y = @as(i32, @intCast(py)) - frame.OY;
        const words = if (y < 0) &above_w else if (y < LINES) &pal[@intCast(y)] else &below_w;
        putLine(py, words, prev);
        prev = words;
    }
}

/// The captured frame into the plane.
pub fn present(fb: []u8) void {
    presentOverscan(fb);
}

// ------------------------------------------------------------------ overscan
// A frame with open borders is not a 320x200 window: each physical line has its
// own start address, first pixel and extent (TCB #1's 230-byte lines start 12
// pixels left of the plane; its first two lines are the odd ones where the
// borders open). The shifter reads 16-pixel groups of four plane words from
// the line's first byte on, whatever the address mod 8 -- which is why 230-byte
// lines rotate the plane order from one line to the next.

/// One physical line of an overscan frame (st_rows.zig).
pub const Row = rows_.Row;
pub const Rows = rows_.Rows;
comptime {
    if (rows_.PW != frame.PW or rows_.PH != frame.PH) @compileError("st_rows.zig: not the frame's size");
}

/// Colour registers 0..15 of each physical line, as ST words.
pub const LinePalettes = [frame.PH][16]u16;

/// Like capture(), for a whole plane of physical rows, each line under its
/// own registers (OMEGA: the bottom border's palette from line 200).
pub fn captureLines(r: *const st.Ram, rows: *const Rows, pals: *const LinePalettes) void {
    conv.convertRows(r, rows);
    capturePalettes(pals);
}

fn capturePalettes(pals: *const LinePalettes) void {
    for (pals, 0..) |*words, py| putLine(py, words, if (py == 0) null else &pals[py - 1]);
}

/// The colour half of captureLines() for a plane converted elsewhere (tcb1_mirror.zig),
/// under ONE palette: every line is line 0's.
pub fn capturePalette(pal: *const [16]u16) void {
    putLine(0, pal, null);
    @memset(ram.buf.same_next[1..], true);
    @memset(frame.c0_next[1..], frame.c0_next[0]);
}

/// Line py's colours from its 16 ST words. A line whose words are the line above's
/// is only marked `same` (its colours are NOT stored): the plane's HBL has nothing to
/// write there (frame.zig), and colour 0 is the line above's.
inline fn putLine(py: usize, words: *const [16]u16, above: ?*const [16]u16) void {
    const same = if (above) |a| std.mem.eql(u16, words, a) else false;
    ram.buf.same_next[py] = same;
    if (same) {
        frame.c0_next[py] = frame.c0_next[py - 1];
        return;
    }
    const line = &ram.buf.pal_next[py];
    for (line, words) |*c, w| c.* = st.color(w);
    frame.c0_next[py] = line[0];
}

/// Words [w0, w1) of a row. Stored whether they differ or not: on the posted-store
/// board a store (~2.3 cycles) is cheaper than reading the framebuffer back to compare.
fn copyRow(dst: []u8, src: *const [frame.PW]u8, w0: usize, w1: usize) void {
    const d: [*]u32 = @ptrCast(@alignCast(dst.ptr));
    const s: [*]const u32 = @ptrCast(@alignCast(src));
    for (w0..w1) |i| d[i] = s[i];
}

/// The captured frame into the plane: only the spans that changed since the last one
/// (the whole plane after another screen drew into it), then the colours.
pub fn presentOverscan(fb: []u8) void {
    const all = frame.fb_owner != 2;
    for (ram.buf.plane, 0..) |*row, py| {
        const dst = fb[py * frame.PW ..][0..frame.PW];
        if (all) {
            copyRow(dst, row, 0, frame.PW / 4);
        } else if (conv.span_lo[py] < conv.span_hi[py]) {
            copyRow(dst, row, conv.span_lo[py] / 4, (@as(usize, conv.span_hi[py]) + 3) / 4);
        }
        conv.span_lo[py] = frame.PW;
        conv.span_hi[py] = 0;
    }
    frame.fb_owner = 2;
    flip();
}

/// The captured colours become the shown ones.
pub fn flip() void {
    const t = ram.buf.pal;
    ram.buf.pal = ram.buf.pal_next;
    ram.buf.pal_next = t;
    const u = ram.buf.same;
    ram.buf.same = ram.buf.same_next;
    ram.buf.same_next = u;
    frame.c0_now = frame.c0_next;
}

test "palettes cover the ST window only" {
    try std.testing.expect(frame.OY >= 0 and frame.OY + LINES <= frame.PH);
}
