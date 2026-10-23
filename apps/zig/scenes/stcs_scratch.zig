// --------------------------------------------------------------------------
// STCS STARGOOSE — the scroller strip, built by CHISEL in the two DISABLED planes.
//
// Every period copies the 320x34 strip of letters onto plane 1 in some shape:
// straight, upside down, one line in two, or both. CHISEL has no flip and no
// destination step, so each shape gets its own source strip, rebuilt every frame
// from the font (9 letter blits from cart RAM each) and copied by stepped,
// per-column-group blits (stcs_strip.zig):
//   N   the strip itself                      400 x 34, plane 2 +0
//   F   N upside down (from the flipped font)  400 x 34, plane 2 +13600
//   G   N on every other row (rows 2y), the     400 x 68, plane 2 +27200
//       rows between hold KEY: a keyed blit of G writes N one line in two
//   FG  F the same way                          400 x 68, plane 3 +0
// A strip is the screen from x = -40 to 360 (strip x = screen x + XO): the
// window's 320 px and, for ZIG MODE's open side borders (stcs_zig.zig), 40 px
// either side. Outside ZIG MODE the letters are clipped to the window as before
// and the copies read only its columns.
// G and FG are written through an 800-stride view (one strip row lands every
// other 400-pixel row); the KEY rows between are filled at init (and swapped
// for 0 while ZIG MODE's stars want every strip 0 keyed out: setKeyRows). Planes 2 and 3 are never enabled, so FRESCO never composites
// them, and every copy onto plane 1 reads another plane: no in-plane copy.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

const LogicalFB = zg.LogicalFB;
const Blitter = zg.Blitter;

pub const W: u16 = zg.WIDTH; // the window
pub const SW: u16 = W + 2 * XO; // a strip: the window and both side borders
pub const XO: u16 = zg.HORIZONTAL_BORDERS_WIDTH; // strip x of screen x 0
pub const GW: u16 = 40; // letter width
pub const GH: u16 = 34; // letter height = strip height
pub const KEY: u8 = 0xFF; // never a font pixel (COLORS)
/// Every pixel the strips put on plane 1 is a font pixel or 0, so below this.
pub const COLORS: usize = 16;
const STRIP: usize = @as(usize, SW) * GH;

pub const Kind = enum { n, f, g, fg };

// The flipped font: each 40x34 glyph upside down, built at compile time from
// the font itself (the same bytes, rows reversed), so F is 9 blits a frame.
fn flipFont(comptime font: []const u8) [font.len]u8 {
    @setEvalBranchQuota(100_000);
    const glyph = @as(usize, GW) * GH;
    var out: [font.len]u8 = undefined;
    for (0..font.len / glyph) |g| {
        for (0..GH) |r| {
            const to = g * glyph + r * GW;
            const from = g * glyph + (GH - 1 - r) * GW;
            out[to..][0..GW].* = font[from..][0..GW].*;
        }
    }
    return out;
}

pub const Scratch = struct {
    font: []const u8,
    flipped: []const u8,
    /// 320-stride views, read as copy sources
    src: [4]LogicalFB = undefined,
    /// write views: N and F as they are, G and FG one strip row every 640 bytes
    put: [4]LogicalFB = undefined,

    pub fn init(self: *Scratch, c: *Blitter, zigos: *zg.ZigOS) void {
        const p2 = zigos.lfbs[2].fb;
        const p3 = zigos.lfbs[3].fb;
        const at = [4][*]u8{ p2, p2 + STRIP, p2 + 2 * STRIP, p3 };
        for (at, 0..) |base, i| {
            self.src[i] = view(base, SW);
            self.put[i] = view(base, if (i >= 2) 2 * SW else SW);
        }
        self.setKeyRows(c, KEY);
    }

    /// The rows between G's and FG's strip rows (the odd 400-pixel rows): KEY,
    /// or 0 while every copy is keyed on 0 (ZIG MODE's stars).
    pub fn setKeyRows(self: *Scratch, c: *Blitter, v: u8) void {
        for (self.put[2..]) |p| {
            var keys = view(p.fb + SW, 2 * SW);
            c.fill(&keys, 0, 0, SW, GH, v);
        }
    }

    /// Rebuild strip `k` from the scroller's letters, as letter_rows.draw built
    /// the CPU strip: cleared to 0, then each letter clipped to the window
    /// (0..320), in order. `wide`: clipped to -40..360 instead, with the letter
    /// that left the window on the left and the one about to enter on the
    /// right added (the scroller keeps 9 letters, 360 px: ZIG MODE shows 400).
    pub fn build(self: *Scratch, c: *Blitter, st: anytype, k: Kind, wide: bool) void {
        const v = &self.put[@intFromEnum(k)];
        const lo: i32 = if (wide) -@as(i32, XO) else 0;
        const hi: i32 = if (wide) W + XO else W;
        c.fill(v, 0, 0, SW, GH, 0);
        const font = if (k == .f or k == .fg) self.flipped else self.font;
        var left: i32 = std.math.maxInt(i32);
        var right: i32 = std.math.minInt(i32);
        for (&st.fonts) |*f| {
            self.letter(c, v, font, @intFromPtr(f.sprite.data.ptr) - @intFromPtr(self.font.ptr), f.pos_x, lo, hi);
            left = @min(left, f.pos_x);
            right = @max(right, f.pos_x);
        }
        if (!wide) return;
        // the text runs on: the rightmost letter is text[text_pos - 1]
        const n = st.text.len;
        const prev = st.text[(st.text_pos + 2 * n - 1 - st.fonts.len) % n];
        const next = st.text[if (st.text_pos >= n) 0 else st.text_pos];
        self.letter(c, v, font, glyphOff(st, prev), left - GW, lo, hi);
        self.letter(c, v, font, glyphOff(st, next), right + GW, lo, hi);
    }

    fn letter(_: *Scratch, c: *Blitter, v: *LogicalFB, font: []const u8, off: usize, x: i32, lo: i32, hi: i32) void {
        const from: i32 = @max(0, lo - x);
        const to: i32 = @min(@as(i32, GW), hi - x);
        if (from >= to) return;
        const glyph = font[off..][0 .. @as(usize, GW) * GH];
        c.blitImage(v, @intCast(x + XO + from), 0, glyph, GW, @intCast(from), 0, @intCast(to - from), GH, null);
    }
};

fn glyphOff(st: anytype, ch: u8) usize {
    return @as(usize, ch - st.font_chars[0]) * GW * GH;
}

pub fn scratch(comptime font: []const u8) Scratch {
    comptime {
        @setEvalBranchQuota(200_000);
        for (font) |px| if (px >= COLORS) @compileError("font pixel >= COLORS (and KEY)");
    }
    const F = struct {
        const flipped = flipFont(font);
    };
    return .{ .font = font, .flipped = &F.flipped };
}

fn view(base: [*]u8, stride: u16) LogicalFB {
    return .{ .fb = base, .stride = stride, .fb_w = stride, .fb_h = zg.HEIGHT };
}
