// --------------------------------------------------------------------------
// TCB2 SUPERSCROLLER, draw() (screen.js:106-138) as one ST row at a time.
//
// ST row y shows canvas row 2y, ST column x canvas column 2x. On that row:
//   back     the last of back.png's copies at Y1, Y2, Y3 that Chrome draws
//            there, its two taps mixed (chrome_draw); black if none
//   letters  the scroll canvas at y 14: a glyph run covering 2x makes the
//            pixel the raster colour of canvas row 2y-14 ('source-atop': the
//            last raster copy over that row, the glyph's own ink if none)
//   overlay  overlay.png's copies at Y1 and Y2, each blended over what is there
// Each pixel's exact colour takes an entry of this line's palette (linepal);
// a run of pixels with the same sources skips the lookup.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");
const M = @import("motion.zig");
const cd = zg.chrome_draw;

/// Most colours a line needs: 56 over 3000 frames of the Chrome-exact replay.
pub const Palette = zg.LinePalette(80);

const BACK_H: u16 = 400;
const SCROLL_Y: i32 = 14; // scrolltextcanvas.draw(maincanvas, 0, 14)
const SCROLL_H: i32 = 374;

const Layers = struct { back: ?cd.Taps, overs: [2]?cd.Taps, raster: ?u32 };

/// What a pixel is made of: the back taps, the overlay taps, a letter or not.
const Sample = struct { back: [2]u8, over: [4]u8, ink: bool };

pub fn drawFrame(dst: zg.blit.Dst, img: *const A.Images, m: *const M.Motion, pal: *Palette) void {
    for (0..A.H) |y| drawRow(dst.buf[y * dst.stride ..][0..A.W], y, img, m, pal);
}

fn drawRow(row: *[A.W]u8, y: usize, img: *const A.Images, m: *const M.Motion, pal: *Palette) void {
    const cy: u16 = @intCast(2 * y);
    const l = layersAt(img, m, cy);
    var ink = [_]bool{false} ** A.W;
    if (l.raster != null) markInk(&ink, img, m, @as(i32, cy) - SCROLL_Y);
    pal.beginRow(y);
    var last_key: u32 = std.math.maxInt(u32);
    var entry: u8 = 0;
    for (row, 0..) |*px, x| {
        const s = sample(img, l, ink[x], x);
        const key = keyOf(s);
        if (key != last_key) {
            entry = pal.entry(colour(img, l, s));
            last_key = key;
        }
        px.* = entry;
    }
}

fn layersAt(img: *const A.Images, m: *const M.Motion, cy: u16) Layers {
    const ys = m.backCopies();
    var back: ?cd.Taps = null;
    for (ys) |yc| {
        if (cd.taps(yc, BACK_H, cy)) |t| back = t; // later copies are drawn over earlier ones
    }
    const s = @as(i32, cy) - SCROLL_Y;
    return .{
        .back = back,
        .overs = .{ cd.taps(ys[0], BACK_H, cy), cd.taps(ys[1], BACK_H, cy) },
        .raster = if (s >= 0 and s < SCROLL_H) rasterAt(img, m, s) else null,
    };
}

/// rasters.draw(scrolltextcanvas, 0, posRastersY[i]) for i = 0..4, source-atop.
fn rasterAt(img: *const A.Images, m: *const M.Motion, s: i32) u32 {
    var c = img.ink;
    for (m.rasters) |p| {
        const r = s - p;
        if (r >= 0 and r < A.RASTER_ROWS) c = img.raster_rgb[img.rasters[@intCast(r)]];
    }
    return c;
}

/// The columns of scroll-canvas row `s` (even) that a letter's ink covers.
fn markInk(ink: *[A.W]bool, img: *const A.Images, m: *const M.Motion, s: i32) void {
    const glyph_row: usize = @intCast(@divExact(s, 2));
    for (m.ring.x, m.ring.c) |pos, ch| {
        if (pos >= 2 * A.W or pos + M.TILE_W <= 0) continue;
        var runs = img.font.runs(ch - A.FIRST_CHAR, glyph_row);
        while (runs.next()) |run| {
            const cols = zg.spanfont.halfColumns(pos, run);
            const x0: usize = @intCast(std.math.clamp(cols[0], 0, A.W));
            const x1: usize = @intCast(std.math.clamp(cols[1], 0, A.W));
            if (x1 > x0) @memset(ink[x0..x1], true);
        }
    }
}

fn sample(img: *const A.Images, l: Layers, ink: bool, x: usize) Sample {
    var s = Sample{ .back = .{ 0, 0 }, .over = .{ 0, 0, 0, 0 }, .ink = ink };
    if (l.back) |t| s.back = .{ img.back[(t.top >> 1) * A.W + x], img.back[(t.bottom >> 1) * A.W + x] };
    for (l.overs, 0..) |over, k| {
        const t = over orelse continue;
        s.over[2 * k] = img.overlay[(t.top >> 1) * A.W + x];
        s.over[2 * k + 1] = img.overlay[(t.bottom >> 1) * A.W + x];
    }
    return s;
}

fn keyOf(s: Sample) u32 {
    var k: u32 = @as(u32, s.back[0]) | (@as(u32, s.back[1]) << 2) | (@as(u32, @intFromBool(s.ink)) << 4);
    for (s.over, 0..) |o, i| k |= @as(u32, o) << @intCast(5 + 3 * i);
    return k;
}

fn colour(img: *const A.Images, l: Layers, s: Sample) u32 {
    var c = [3]u8{ 0, 0, 0 };
    if (l.back) |t| c = mix(img.back_rgb[s.back[0]], img.back_rgb[s.back[1]], t.w);
    if (s.ink) c = channels(l.raster.?);
    for (l.overs, 0..) |over, k| {
        const t = over orelse continue;
        const a = s.over[2 * k];
        const b = s.over[2 * k + 1];
        const sa = cd.mix(if (a != 0) @as(u8, 255) else 0, if (b != 0) @as(u8, 255) else 0, t.w);
        if (sa == 0) continue;
        const src = mix(img.over_rgb[a], img.over_rgb[b], t.w); // [0] is 0: premultiplied transparent
        for (&c, src) |*d, sc| d.* = cd.srcOver(sc, sa, d.*);
    }
    return zg.linepal.rgb(c[0], c[1], c[2]);
}

fn mix(a: u32, b: u32, w: u8) [3]u8 {
    const ca = channels(a);
    const cb = channels(b);
    return .{ cd.mix(ca[0], cb[0], w), cd.mix(ca[1], cb[1], w), cd.mix(ca[2], cb[2], w) };
}

fn channels(rgba: u32) [3]u8 {
    return .{ @truncate(rgba), @truncate(rgba >> 8), @truncate(rgba >> 16) };
}
