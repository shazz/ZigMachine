// --------------------------------------------------------------------------
// TCB2 SUPERSCROLLER, draw() (screen.js:106-138) as ST rows.
//
// ST row y shows canvas row 2y, ST column x canvas column 2x. On that row:
//   back     the last of back.png's copies at Y1, Y2, Y3 that Chrome draws
//            there, its two taps mixed (chrome_draw); black if none
//   letters  the scroll canvas at y 14: a glyph run covering 2x makes the
//            pixel the raster colour of canvas row 2y-14 ('source-atop': the
//            last raster copy over that row, the glyph's own ink if none)
//   overlay  overlay.png's copies at Y1 and Y2, each blended over what is there
//
// What changes between frames is only the weight w of the taps (and which
// image rows they are), the raster under the letters, and the letters' x.
// So a frame is (layers.zig, rowpal.zig):
//   - PAIRED rows, where the back and the one overlay over it come from the
//     same copy (every row but the one or two where the copies overlap): one
//     CHISEL blit per band of the precomputed entry image, the letters copied
//     from its ink twin (inkcopy.zig), an HBL writing the entries that change;
//   - the other rows per pixel (slowrow.zig), as the whole screen once was,
//     their colours handed out by the LinePalette in first-appearance order.
// The per-pixel colour() here is the reference; pairedColour() and inkColour()
// are it in scalars for the paired rows' tables and HBL.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");
const M = @import("motion.zig");
const L = @import("layers.zig");
const cd = zg.chrome_draw;
const ink = @import("inkmask.zig");
const rowpal = @import("rowpal.zig");
const slowrow = @import("slowrow.zig");
const inkcopy = @import("inkcopy.zig");

/// Most colours a line needs: 56 over 3000 frames of the Chrome-exact replay.
pub const Palette = zg.LinePalette(80);

const BACK_H: u16 = 400;
pub const SCROLL_Y: i32 = 14; // scrolltextcanvas.draw(maincanvas, 0, 14)
const SCROLL_H: i32 = 374;

pub const Layers = struct { back: ?cd.Taps, overs: [2]?cd.Taps, raster: ?u32 };

/// What a pixel is made of: the back taps, the overlay taps, a letter or not.
pub const Sample = struct { back: [2]u8, over: [4]u8, ink: bool };

pub const Frame = struct {
    fb: *zg.LogicalFB,
    blitter: *zg.Blitter,
    img: *const A.Images,
    tables: *const L.Tables,
    desc: *[A.H]rowpal.Desc,
    cache: *ink.KeyCache,
    m: *const M.Motion,
    pal: *Palette,
};

/// Consecutive paired rows from consecutive image rows at one weight: one blit.
const Band = struct {
    y0: usize,
    r0: u8,
    n: u16,
    mode: L.Mode,
    w: u4,

    fn extends(self: Band, p: Paired) bool {
        return self.mode == p.mode and self.w == p.w and self.r0 + self.n == p.r;
    }
};

const Paired = struct { mode: L.Mode, r: u8, w: u4 };

pub fn drawFrame(fr: Frame) void {
    const ys = fr.m.backCopies();
    var band: ?Band = null;
    for (0..A.H) |y| {
        const cy: u16 = @intCast(2 * y);
        const l = layersAt(fr.img, fr.m, &ys, cy);
        const scroll_row: u8 = if (l.raster != null) @intCast(@divExact(@as(i32, cy) - SCROLL_Y, 2)) else 0;
        if (pairedRow(l)) |p| {
            const starts = band == null or !band.?.extends(p);
            if (starts) {
                flush(fr, band);
                band = .{ .y0 = y, .r0 = p.r, .n = 1, .mode = p.mode, .w = p.w };
            } else band.?.n += 1;
            fr.desc[y] = .{ .slow = false, .mode = p.mode, .full = starts, .ink = l.raster != null, .r = p.r, .w = p.w, .scroll_row = scroll_row };
        } else {
            flush(fr, band);
            band = null;
            slowrow.draw(rowOf(fr.fb, y), y, fr.img, fr.cache, fr.m, l, fr.pal);
            fr.desc[y] = .{};
        }
    }
    flush(fr, band);
    for (fr.desc, 0..) |d, y| {
        if (d.slow or !d.ink) continue;
        inkcopy.row(rowOf(fr.fb, y), &fr.tables.li[@intFromEnum(d.mode)][d.r], fr.img, fr.m, d.scroll_row);
    }
}

fn rowOf(fb: *zg.LogicalFB, y: usize) *[A.W]u8 {
    return fb.fb[y * fb.stride ..][0..A.W];
}

fn flush(fr: Frame, band: ?Band) void {
    const b = band orelse return;
    fr.blitter.blitImage(fr.fb, 0, @intCast(b.y0), fr.tables.image(&fr.tables.l, b.mode), A.W, 0, b.r0, A.W, b.n, null);
}

/// The row's layers when the back and exactly one overlay share their taps.
fn pairedRow(l: Layers) ?Paired {
    const b = l.back orelse return null;
    const o = if (l.overs[0]) |o0| (if (l.overs[1] != null) return null else o0) else (l.overs[1] orelse return null);
    if (o.top != b.top or o.bottom != b.bottom or o.w != b.w) return null;
    const r = b.top >> 1;
    return .{ .mode = if (b.bottom >> 1 == r) .same else .pair, .r = @intCast(r), .w = @intCast(b.w) };
}

pub fn sampleOf(key: u32) Sample {
    return .{
        .back = .{ @intCast(key & 3), @intCast((key >> 2) & 3) },
        .ink = (key >> 4) & 1 != 0,
        .over = .{ @intCast((key >> 5) & 7), @intCast((key >> 8) & 7), @intCast((key >> 11) & 7), @intCast((key >> 14) & 7) },
    };
}

pub fn layersAt(img: *const A.Images, m: *const M.Motion, ys: *const [3]cd.Fy, cy: u16) Layers {
    const t0 = cd.tapsFy(ys[0], BACK_H, cy);
    const t1 = cd.tapsFy(ys[1], BACK_H, cy);
    const t2 = cd.tapsFy(ys[2], BACK_H, cy);
    const s = @as(i32, cy) - SCROLL_Y;
    return .{
        .back = t2 orelse t1 orelse t0, // later copies are drawn over earlier ones
        .overs = .{ t0, t1 },
        .raster = if (s >= 0 and s < SCROLL_H) rasterAt(img, m, s) else null,
    };
}

/// rasters.draw(scrolltextcanvas, 0, posRastersY[i]) for i = 0..4, source-atop.
pub fn rasterAt(img: *const A.Images, m: *const M.Motion, s: i32) u32 {
    var c = img.ink;
    for (m.rasters) |p| {
        const r = s - p;
        if (r >= 0 and r < A.RASTER_ROWS) c = img.raster_rgb[img.rasters[@intCast(r)]];
    }
    return c;
}

/// colour() for a PAIRED row (layers.zig) in scalars: colour()'s arrays are
/// stack stores, bus writes on the board, and these run 16K times at load (F)
/// and a few times a line in the HBL. The two agree bit for bit: same mix(),
/// same srcOver(), same order; scene_hash over 1200 frames is the proof.
/// A letter's pixel at weight `w` over raster colour `raster`, under overlay
/// taps `over` (the 6-bit ink key).
pub fn inkColour(img: *const A.Images, w: u8, raster: u32, over: u8) u32 {
    return overlayOver(img, w, over, raster);
}

/// A pixel of the back at weight `w` under its overlay taps: 10-bit layer `key`.
pub fn pairedColour(img: *const A.Images, w: u8, key: u32) u32 {
    const t0 = img.back_rgb[key & 3];
    const t1 = img.back_rgb[(key >> 2) & 3];
    var base: u32 = 0;
    inline for (0..3) |i| base |= @as(u32, cd.mix(@truncate(t0 >> (8 * i)), @truncate(t1 >> (8 * i)), w)) << (8 * i);
    return overlayOver(img, w, @intCast(key >> 4), base);
}

fn overlayOver(img: *const A.Images, w: u8, over: u8, base: u32) u32 {
    const a: usize = over & 7;
    const b: usize = over >> 3;
    const sa = cd.mix(if (a != 0) @as(u8, 255) else 0, if (b != 0) @as(u8, 255) else 0, w);
    var out: u32 = 0xFF00_0000;
    inline for (0..3) |i| {
        const sh = 8 * i;
        const d: u8 = @truncate(base >> sh);
        const c = if (sa == 0) d else cd.srcOver(cd.mix(@truncate(img.over_rgb[a] >> sh), @truncate(img.over_rgb[b] >> sh), w), sa, d);
        out |= @as(u32, c) << sh;
    }
    return out;
}

pub fn colour(img: *const A.Images, l: Layers, s: Sample) u32 {
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
