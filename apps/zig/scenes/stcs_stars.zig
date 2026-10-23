// --------------------------------------------------------------------------
// STCS STARGOOSE — ZIG MODE's stars (key 3, stcs_zig.zig): 48 dots in three
// speeds scrolling right to left behind the logo and the letters.
//
// One byte store a star a frame, plus one to erase it where nothing else does:
//   - lines 69..199 are the band the cart restores every frame (stcs_logo
//     restoreBand) before the stars, so a star there is just drawn; the strip
//     copies after it are keyed on 0 (stcs_strip Opts.keyed), so the letters
//     cover it and the gaps between them do not;
//   - lines 0..68 are drawn once (the logo), so a star there is put back to the
//     logo's pixel (from cart RAM: no plane read) before it moves, and is drawn
//     only where the logo's pixel is 0: behind the logo.
// The field is the window (320 px) or, with the borders open, 400 px.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const logo = @import("stcs_logo.zig");

pub const N = 48;
/// Palette entries 32..34 (free: the font is 0..15, the logo 17..31), by speed:
/// cold blues no font, logo or raster colour uses (apps/stcs_zig_headless.mjs
/// tells the stars by them).
pub const BASE: u8 = 32;
pub const colours = [3]zg.Color{
    .{ .r = 80, .g = 96, .b = 144, .a = 255 },
    .{ .r = 144, .g = 160, .b = 208, .a = 255 },
    .{ .r = 208, .g = 224, .b = 255, .a = 255 },
};

/// Lines the cart restores itself every frame (stcs.zig BAND_TOP).
const BAND_TOP: i16 = 69;
const XO: i16 = zg.HORIZONTAL_BORDERS_WIDTH;
const STRIDE: usize = zg.PHYSICAL_WIDTH;

// Words, not halfwords: a 6-byte struct is copied with wide loads that
// straddle its 2-byte alignment, and a misaligned load TRAPS on the board.
const Star = struct { y: i32, x0: i32, speed: i32 };

// The field, at compile time from a fixed xorshift seed: line, start x (of
// 400), speed 1..3.
const field: [N]Star = blk: {
    var t: [N]Star = undefined;
    var r: u32 = 0x5717_c5a5;
    for (0..N) |i| {
        r ^= r << 13;
        r ^= r >> 17;
        r ^= r << 5;
        t[i] = .{ .y = @intCast(r % zg.HEIGHT), .x0 = @intCast((r >> 8) % zg.PHYSICAL_WIDTH), .speed = @intCast(1 + (r >> 20) % 3) };
    }
    break :blk t;
};

var pos: [N]i16 = undefined; // 0..span-1, screen x = pos + left
var drawn: [N]i16 = undefined; // the screen x a star was drawn at on lines 0..68, or NONE
const NONE: i16 = -32768; // (not a ?i16: its 4-byte copies are 2-aligned, see Star)

pub fn reset() void {
    for (&pos, field) |*p, s| p.* = @intCast(s.x0);
    for (&drawn) |*d| d.* = NONE;
}

/// Once a frame, after the band is restored and before the strips are copied.
/// `row0` is the plane from the window's first line, screen x -40.
pub fn draw(row0: [*]u8, wide: bool) void {
    const span: i16 = if (wide) zg.PHYSICAL_WIDTH else zg.WIDTH;
    const left: i16 = if (wide) -XO else 0;
    for (field, &pos, &drawn) |s, *p, *d| {
        const y: i16 = @intCast(s.y);
        erase(row0, y, d);
        p.* -= @intCast(s.speed);
        if (p.* < 0) p.* += span;
        if (p.* >= span) p.* -= span; // the field narrowed (borders closed)
        const x = p.* + left;
        if (logo.under(x, y) != 0) continue; // behind the logo
        put(row0, x, y, BASE + @as(u8, @intCast(s.speed - 1)));
        if (y < BAND_TOP) d.* = x;
    }
}

/// Stars off: lines 0..68 back to the logo (the band restores itself).
pub fn eraseAll(row0: [*]u8) void {
    for (field, &drawn) |s, *d| erase(row0, @intCast(s.y), d);
}

fn erase(row0: [*]u8, y: i16, d: *i16) void {
    const x = d.*;
    if (x == NONE) return;
    put(row0, x, y, logo.under(x, y));
    d.* = NONE;
}

fn put(row0: [*]u8, x: i16, y: i16, v: u8) void {
    row0[@as(usize, @intCast(y)) * STRIDE + @as(usize, @intCast(x + XO))] = v;
}
