// --------------------------------------------------------------------------
// The scroller and what shows through it (screen.js damier, 183-216, and
// scroller, 223-230).
//
// damier() paints a sky and a 3D chessboard floor, dancingFate() the logo over
// them, and then scroller() draws the 704x176 scroll canvas at (24, 268) with
// 'destination-in': everything on the main canvas survives ONLY where a glyph
// is opaque. So the big ULM font is a window: the letters are filled with sky,
// floor and logo, and everything else in the box is black.
//
// Here the box's contents are painted into a 352x88 buffer in cart RAM (sky
// and floor are raster INKS, the copper colours them per line), and CHISEL
// writes each glyph's mask ANDed with that buffer to the plane (chisel.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");
const Fate = @import("fate.zig").Fate;
const floor = @import("floor.zig");
const chisel = @import("chisel.zig");
const trig = @import("trig.zig");

// the scroll canvas at (24, 268), 704x176, in ST pixels
pub const BOX_X = 12;
pub const BOX_Y = 134;
pub const BOX_W = 352;
pub const BOX_H = 88;

pub const SKY_TOP = 135; // fillRect(24, 270, 704, 90): the sky pattern's rows 0..44
pub const FLOOR_TOP = 180; // the floor's 90 canvas rows from 360
const FLOOR_W = 704; // drawPart's partw
const DAMIER_AMPL = 400;
const PI: f64 = std.math.pi;
const DAMIER_STEP = trig.phase(PI / 250); // damierSpeed, as a u64 phase

// scrolltext_horizontal.init(scrollCan, font, 12), in canvas pixels
const GLYPH = 192;
const SPEED = 12;
const WIDE = (FLOOR_W + GLYPH - 1) / GLYPH + 1; // ceil(704/192)+1 = 5
const LETTERS = WIDE + 1;
const Ring = zg.scrollring.Ring(i32, LETTERS);

/// What the box holds before the glyphs cut it out, and each letter's glyph
/// unpacked to a 0x00 / 0xFF mask (re-unpacked only when its character changes). Both come
/// from the cart RAM arena (zg.mem) at init: as module-scope arrays they were
/// 82 KB of zeros in the data segment (the zero-segment gate's 64 KB limit).
var box: *align(4) [BOX_W * BOX_H]u8 = undefined;
var glyph_px: *align(4) [LETTERS][A.FONT_W * A.FONT_H]u8 = undefined;

pub const Scroller = struct {
    ring: Ring,
    cached: [LETTERS]u8, // the character glyph_px[i] holds, 0 = none
    damier_ctr: u64, // damierCtr, 2^64 = one turn
    tx: i32, // the chessboard pattern's translation this frame
    ty: i32,
    dirty: Fate.Rows, // the box rows the logo painted over last frame

    pub fn init(self: *Scroller) void {
        // as words: floor.row stores four pixels at a time
        box = @ptrCast(zg.mem.mustAlloc(u32, BOX_W * BOX_H / 4)[0 .. BOX_W * BOX_H / 4]);
        glyph_px = @ptrCast(zg.mem.mustAlloc(u32, LETTERS * A.FONT_W * A.FONT_H / 4)[0 .. LETTERS * A.FONT_W * A.FONT_H / 4]);
        self.ring = Ring.init(A.text, WIDE * GLYPH, GLYPH);
        self.cached = @splat(0);
        self.damier_ctr = 0;
        self.tx = 0;
        self.ty = 0;
        // canvas rows 268-269: nothing is drawn there; then the sky, which only
        // the logo ever paints over (render puts those rows back)
        @memset(box[0..BOX_W], 0);
        @memset(box[BOX_W .. (FLOOR_TOP - BOX_Y) * BOX_W], A.SKY_INK);
        self.dirty = .{ .lo = 0, .hi = 0 };
    }

    /// damier()'s part of go(): the pattern offset it draws with, then the step.
    pub fn stepFloor(self: *Scroller) void {
        // trunc(-400 - 400 cos a) = -floor(400 (1 + cos a)): in Q30, no float
        self.tx = sway(trig.sincos(trig.angle(self.damier_ctr)).c);
        self.ty = sway(trig.sincos(trig.angle(self.damier_ctr *% 2)).s);
        self.damier_ctr +%= DAMIER_STEP;
    }

    /// scrolltext.draw(0)'s move. A letter reaching -192 over a ^C command runs
    /// it (codef_scrolltext.js:119-125) and takes the character after it: the
    /// JS takes that character one frame later, from x -204 instead of -192,
    /// which lands it at the same x (948) the frame after, both off screen.
    pub fn step(self: *Scroller, fate: *Fate) void {
        for (self.ring.x) |x| {
            if (x - SPEED > -GLYPH) continue;
            while (true) {
                switch (self.ring.upcoming()) {
                    A.LOGO_FATE => fate.logoFate(),
                    A.LOGO_WAVEFORM => fate.logoWaveform(),
                    else => break,
                }
                self.ring.skip();
            }
            break; // letters are 192 apart: one wraps per frame at most
        }
        _ = self.ring.step(SPEED);
    }

    /// Paint the box (sky, floor, logo) in cart RAM, then let CHISEL keep only
    /// the glyphs: each glyph's mask ANDed with the box under it goes straight
    /// to the plane, at canvas (cx, cy) + the box's place. Columns no glyph
    /// covers (none while the letters sit 96 apart, edge to edge) are filled black.
    pub fn render(self: *Scroller, fb: *zg.LogicalFB, bl: *zg.Blitter, cx: i16, cy: i16, fate: *const Fate) void {
        for (self.dirty.lo..self.dirty.hi) |r| skyRow(r);
        comptime std.debug.assert(FLOOR_TOP + floor.ROWS == BOX_Y + BOX_H and floor.W == BOX_W and BOX_W % 4 == 0);
        for (0..floor.ROWS) |k| floor.row(k, self.tx, self.ty, @alignCast(box[(FLOOR_TOP - BOX_Y + k) * BOX_W ..][0..BOX_W]));
        self.dirty = fate.draw(box, BOX_W, BOX_X, BOX_Y);

        const hx = cx + BOX_X;
        const hy = cy + BOX_Y;
        var spans: [LETTERS][2]u16 = undefined;
        var n: usize = 0;
        for (self.ring.x, self.ring.c, 0..) |x, c, i| {
            const gx = @divExact(x, 2);
            const lo: u16 = @intCast(std.math.clamp(gx, 0, BOX_W));
            const hi: u16 = @intCast(std.math.clamp(gx + A.FONT_W, 0, BOX_W));
            if (lo >= hi) continue;
            if (self.cached[i] != c) unpack(&glyph_px[i], c);
            self.cached[i] = c;
            const mask = glyph_px[i][@intCast(lo - gx)..];
            chisel.andBlit(fb, hx + @as(i16, @intCast(lo)), hy, mask.ptr, A.FONT_W, box[lo..].ptr, BOX_W, hi - lo, BOX_H);
            spans[n] = .{ lo, hi };
            n += 1;
        }
        std.sort.insertion([2]u16, spans[0..n], {}, spanLess);
        var edge: u16 = 0; // glyphs are cut edge to edge: none overlaps another
        for (spans[0..n]) |sp| {
            if (sp[0] > edge) bl.fill(fb, hx + @as(i16, @intCast(edge)), hy, sp[0] - edge, BOX_H, 0);
            edge = @max(edge, sp[1]);
        }
        if (edge < BOX_W) bl.fill(fb, hx + @as(i16, @intCast(edge)), hy, BOX_W - edge, BOX_H, 0);
    }
};

comptime {
    std.debug.assert(GLYPH / 2 == A.FONT_W and A.FONT_H >= BOX_H); // the glyphs tile the box
}

fn spanLess(_: void, a: [2]u16, b: [2]u16) bool {
    return a[0] < b[0];
}

/// Box row r as it is before the logo: black, then the sky (the floor rows
/// are repainted every frame anyway).
fn skyRow(r: usize) void {
    if (r >= FLOOR_TOP - BOX_Y) return;
    const v: u32 = if (r == 0) 0 else @as(u32, A.SKY_INK) * 0x0101_0101;
    const words: *[BOX_W / 4]u32 = @ptrCast(@alignCast(box[r * BOX_W ..][0..BOX_W]));
    for (words) |*w| w.* = v;
}

/// A glyph's bits (pixel 0 in a byte's top bit) as 0x00 / 0xFF bytes, a word
/// (one nibble of the font) at a time.
fn unpack(out: *align(4) [A.FONT_W * A.FONT_H]u8, c: u8) void {
    const bits = A.font[@as(usize, c - A.FONT_FIRST) * A.FONT_H * A.FONT_ROW_BYTES ..][0 .. A.FONT_H * A.FONT_ROW_BYTES];
    const words: *[A.FONT_W * A.FONT_H / 4]u32 = @ptrCast(out);
    for (words, 0..) |*w, j| w.* = nibble_mask[(bits[j >> 1] >> @intCast(4 - 4 * (j & 1))) & 0xF];
}

/// nibble_mask[n]: byte b is 0xFF where n's bit 3 - b is set (pixel order).
const nibble_mask: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (&t, 0..) |*m, n| {
        m.* = 0;
        for (0..4) |b| if ((n >> (3 - b)) & 1 != 0) {
            m.* |= @as(u32, 0xFF) << (8 * b);
        };
    }
    break :blk t;
};

/// trunc(-AMPL - AMPL * v) for v in Q30.
fn sway(v: i32) i32 {
    return -@as(i32, @intCast((DAMIER_AMPL * ((@as(i64, 1) << 30) + v)) >> 30));
}
