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
const ink = @import("inkmask.zig");

/// Most colours a line needs: 56 over 3000 frames of the Chrome-exact replay.
pub const Palette = zg.LinePalette(80);

const BACK_H: u16 = 400;
const SCROLL_Y: i32 = 14; // scrolltextcanvas.draw(maincanvas, 0, 14)
const SCROLL_H: i32 = 374;
const W_I: i32 = A.W; // for the signed letter positions

const Layers = struct { back: ?cd.Taps, overs: [2]?cd.Taps, raster: ?u32 };

/// What a pixel is made of: the back taps, the overlay taps, a letter or not.
const Sample = struct { back: [2]u8, over: [4]u8, ink: bool };

const ZERO_ROW: [A.W]u8 align(4) = @splat(0);

pub fn drawFrame(dst: zg.blit.Dst, img: *const A.Images, cache: *ink.KeyCache, m: *const M.Motion, pal: *Palette) void {
    const ys = m.backCopies();
    for (0..A.H) |y| drawRow(dst.buf[y * dst.stride ..][0..A.W], y, img, cache, m, &ys, pal);
}

/// Image row `tap` (a canvas row, so halved) of an image, or zeros where no copy is drawn.
fn srcRow(image: []const u8, row: ?u16) *const [A.W]u8 {
    const r = row orelse return &ZERO_ROW;
    return image[(r >> 1) * A.W ..][0..A.W];
}

/// A pixel's sources packed: back taps 2 bits each, ink 1 bit, each overlay tap 3 bits.
inline fn keyAt(src: *const [6]*const [A.W]u8, ink_bit: u32, x: usize) u32 {
    return @as(u32, src[0][x]) | (@as(u32, src[1][x]) << 2) | (ink_bit << 4) |
        (@as(u32, src[2][x]) << 5) | (@as(u32, src[3][x]) << 8) | (@as(u32, src[4][x]) << 11) | (@as(u32, src[5][x]) << 14);
}

fn sampleOf(key: u32) Sample {
    return .{
        .back = .{ @intCast(key & 3), @intCast((key >> 2) & 3) },
        .ink = (key >> 4) & 1 != 0,
        .over = .{ @intCast((key >> 5) & 7), @intCast((key >> 8) & 7), @intCast((key >> 11) & 7), @intCast((key >> 14) & 7) },
    };
}

fn drawRow(row: *[A.W]u8, y: usize, img: *const A.Images, cache: *ink.KeyCache, m: *const M.Motion, ys: *const [3]cd.Fy, pal: *Palette) void {
    const cy: u16 = @intCast(2 * y);
    const l = layersAt(img, m, ys, cy);
    var mask: ink.Mask = [_]u32{0} ** ink.WORDS;
    if (l.raster != null) markInk(&mask, img, m, @as(i32, cy) - SCROLL_Y);
    const src = [6]*const [A.W]u8{
        srcRow(img.back, if (l.back) |t| t.top else null),
        srcRow(img.back, if (l.back) |t| t.bottom else null),
        srcRow(img.overlay, if (l.overs[0]) |t| t.top else null),
        srcRow(img.overlay, if (l.overs[0]) |t| t.bottom else null),
        srcRow(img.overlay, if (l.overs[1]) |t| t.top else null),
        srcRow(img.overlay, if (l.overs[1]) |t| t.bottom else null),
    };
    pal.beginRow(y);
    cache.nextRow();
    const words: *[A.W / 4]u32 = @ptrCast(@alignCast(row));
    const w32: [6]*const [A.W / 4]u32 = .{
        @ptrCast(@alignCast(src[0])), @ptrCast(@alignCast(src[1])), @ptrCast(@alignCast(src[2])),
        @ptrCast(@alignCast(src[3])), @ptrCast(@alignCast(src[4])), @ptrCast(@alignCast(src[5])),
    };
    // Where no overlay and no letter is over four pixels, the colour is a function of the
    // two back taps alone: 16 of them a row, found once each and then looked up.
    var back_lut: [16]u8 = @splat(0);
    var last_key: u32 = std.math.maxInt(u32);
    var entry: u8 = 0;
    for (words, 0..) |*word, wi| {
        const nib = (mask[wi >> 3] >> @intCast((wi & 7) * 4)) & 15;
        if (nib == 0 and (w32[2][wi] | w32[3][wi] | w32[4][wi] | w32[5][wi]) == 0) {
            var packed_px: u32 = 0;
            inline for (0..4) |k| {
                const sh: u5 = 8 * k;
                const bk: u32 = ((w32[0][wi] >> sh) & 3) | (((w32[1][wi] >> sh) & 3) << 2);
                var e = back_lut[bk];
                if (e == 0) {
                    e = entryFor(bk, img, l, cache, pal);
                    back_lut[bk] = e;
                }
                packed_px |= @as(u32, e) << sh;
            }
            word.* = packed_px;
            continue;
        }
        var packed_px: u32 = 0;
        inline for (0..4) |k| {
            const x = wi * 4 + k;
            const key = keyAt(&src, ink.bit(&mask, x), x);
            if (key != last_key) {
                last_key = key;
                entry = entryFor(key, img, l, cache, pal);
            }
            packed_px |= @as(u32, entry) << (8 * k);
        }
        word.* = packed_px;
    }
}

/// The row's palette entry for a pixel key: remembered per row, else made from its colour.
fn entryFor(key: u32, img: *const A.Images, l: Layers, cache: *ink.KeyCache, pal: *Palette) u8 {
    if (cache.find(key)) |e| return e;
    const e = pal.entry(colour(img, l, sampleOf(key)));
    cache.put(key, e);
    return e;
}

fn layersAt(img: *const A.Images, m: *const M.Motion, ys: *const [3]cd.Fy, cy: u16) Layers {
    var back: ?cd.Taps = null;
    for (ys) |yc| {
        if (cd.tapsFy(yc, BACK_H, cy)) |t| back = t; // later copies are drawn over earlier ones
    }
    const s = @as(i32, cy) - SCROLL_Y;
    return .{
        .back = back,
        .overs = .{ cd.tapsFy(ys[0], BACK_H, cy), cd.tapsFy(ys[1], BACK_H, cy) },
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
fn markInk(m_ink: *ink.Mask, img: *const A.Images, m: *const M.Motion, s: i32) void {
    const glyph_row: usize = @intCast(@divExact(s, 2));
    for (m.ring.x, m.ring.c) |pos, ch| {
        if (pos >= 2 * W_I or pos + M.TILE_W <= 0) continue;
        var runs = img.font.runs(ch - A.FIRST_CHAR, glyph_row);
        while (runs.next()) |run| {
            const cols = zg.spanfont.halfColumns(pos, run);
            const x0: usize = @intCast(std.math.clamp(cols[0], 0, W_I));
            const x1: usize = @intCast(std.math.clamp(cols[1], 0, W_I));
            if (x1 > x0) ink.setRange(m_ink, x0, x1);
        }
    }
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
