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
/// border above and below. The window is rows OY.. of the same plane an overscan
/// frame uses (320 pixels from column OX, colour 0 around), so both paths share
/// one converter and one present.
pub fn capture(r: *const st.Ram, screen: u32, pal: *const Palettes, top: u16, bottom: u16) void {
    var rows: Rows = [_]?Row{null} ** frame.PH;
    for (0..LINES) |y| {
        const addr = screen + @as(u32, @intCast(y)) * st.LINE;
        rows[y + @as(usize, @intCast(frame.OY))] = .{ .addr = addr, .x0 = frame.OX, .lo = @intCast(frame.OX), .hi = @intCast(frame.OX + 320) };
    }
    convertRows(r, &rows);
    for (ram.buf.pal_next, 0..) |*line, py| {
        const y = @as(i32, @intCast(py)) - frame.OY;
        if (y >= 0 and y < LINES) {
            for (line, pal[@intCast(y)]) |*c, w| setColor(c, w);
        } else {
            const w = if (y < 0) top else bottom;
            for (line) |*c| setColor(c, w);
        }
        frame.c0_next[py] = line[0];
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
    convertRows(r, rows);
    for (ram.buf.pal_next, pals, 0..) |*line, pal, py| {
        for (line, pal) |*c, w| setColor(c, w);
        frame.c0_next[py] = line[0];
    }
}

/// A store to cart RAM costs ~27 cycles, a load almost nothing, and the colours of a
/// line are mostly what they were two frames ago (these buffers swap): store changes only.
inline fn setColor(c: *u32, w: u16) void {
    const v = st.color(w);
    if (c.* != v) c.* = v;
}

// What each plane row was last converted from. A row whose descriptor is unchanged
// only reconverts the 16-pixel groups whose 8 source bytes changed (an ST screen
// changes in a few places a frame: 98% of OMEGA's pixels are the same as the frame
// before), and only rows that changed are copied to the framebuffer.
var keys: [frame.PH]?Row = [_]?Row{null} ** frame.PH;
var dirty: [frame.PH]bool = [_]bool{true} ** frame.PH;
var blank: [frame.PH]bool = [_]bool{false} ** frame.PH;

fn sameRow(a: ?Row, b: ?Row) bool {
    const x = a orelse return b == null;
    const y = b orelse return false;
    // not addr: where the bytes are read from may flip every frame (double buffering); what the
    // cached bytes say is compared group by group in lineAt
    return x.x0 == y.x0 and x.lo == y.lo and x.hi == y.hi;
}

fn convertRows(r: *const st.Ram, rows: *const Rows) void {
    for (ram.buf.plane, rows, 0..) |*out, row, py| {
        if (row == null) {
            keys[py] = null;
            if (!blank[py]) {
                @memset(out, 0);
                blank[py] = true;
                dirty[py] = true;
            }
            continue;
        }
        const ln = row.?;
        if (!sameRow(keys[py], row)) {
            @memset(out, 0);
            blank[py] = false;
            keys[py] = row;
            dirty[py] = true;
            _ = lineAt(r, ln, out, &ram.buf.src[py], false);
        } else if (lineAt(r, ln, out, &ram.buf.src[py], true)) {
            dirty[py] = true;
        }
    }
}

/// Convert the groups of `ln` into `out`; with `only_changed`, just those whose source
/// bytes differ from `cache` (returns whether any did). Pixels outside [lo, hi) and
/// left of the row's first byte stay as they are (colour 0).
fn lineAt(r: *const st.Ram, ln: Row, out: *[frame.PW]u8, cache: *[ram.SRC_ROW]u8, only_changed: bool) bool {
    if (ln.hi <= ln.lo or @as(i32, ln.hi) <= ln.x0) return false;
    const k0: i32 = @max(0, @as(i32, ln.lo) - ln.x0);
    const g0: usize = @intCast(@divFloor(k0, 16));
    const g1: usize = @intCast(@divFloor(@as(i32, ln.hi) - 1 - ln.x0, 16));
    var changed = false;
    for (g0..g1 + 1) |g| {
        const src = r.bytes(ln.addr + 8 * @as(u32, @intCast(g)), 8)[0..8];
        const c = cache[(g - g0) * 8 ..][0..8];
        const a0 = std.mem.readInt(u32, src[0..4], .little);
        const a1 = std.mem.readInt(u32, src[4..8], .little);
        const c0 = std.mem.readInt(u32, c[0..4], .little);
        const c1 = std.mem.readInt(u32, c[4..8], .little);
        if (only_changed and a0 == c0 and a1 == c1) continue;
        std.mem.writeInt(u32, c[0..4], a0, .little);
        std.mem.writeInt(u32, c[4..8], a1, .little);
        changed = true;
        putGroup(ln, g, src, out);
    }
    return changed;
}

fn putGroup(ln: Row, g: usize, src: *const [8]u8, out: *[frame.PW]u8) void {
    const xb = ln.x0 + 16 * @as(i32, @intCast(g));
    if (xb >= ln.lo and xb + 16 <= ln.hi) {
        st.groupToChunky(src, out[@intCast(xb)..][0..16]);
        return;
    }
    var group: [16]u8 = undefined;
    st.groupToChunky(src, &group);
    for (0..16) |i| {
        const x = xb + @as(i32, @intCast(i));
        if (x >= ln.lo and x < ln.hi) out[@intCast(x)] = group[i];
    }
}

/// Word by word, storing only the words that differ: a load is cheap and a store to
/// the framebuffer is not, and most of a changed row is what it was.
fn copyRow(dst: []u8, src: *const [frame.PW]u8) void {
    const d: [*]u32 = @ptrCast(@alignCast(dst.ptr));
    const s: [*]const u32 = @ptrCast(@alignCast(src));
    for (0..frame.PW / 4) |i| {
        if (d[i] != s[i]) d[i] = s[i];
    }
}

/// The captured frame into the plane: only the rows that changed since the last one
/// (the whole plane after another screen drew into it), then the colours.
pub fn presentOverscan(fb: []u8) void {
    const all = frame.fb_owner != 2;
    for (ram.buf.plane, 0..) |*row, py| {
        if (all or dirty[py]) copyRow(fb[py * frame.PW ..][0..frame.PW], row);
        dirty[py] = false;
    }
    frame.fb_owner = 2;
    const t = ram.buf.pal;
    ram.buf.pal = ram.buf.pal_next;
    ram.buf.pal_next = t;
    frame.c0_now = frame.c0_next;
}

test "palettes cover the ST window only" {
    try std.testing.expect(frame.OY >= 0 and frame.OY + LINES <= frame.PH);
}
