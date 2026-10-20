// --------------------------------------------------------------------------
// STCS STARGOOSE — the scroller strip, built by CHISEL in the two DISABLED planes.
//
// Every period copies the 320x34 strip of letters onto plane 1 in some shape:
// straight, upside down, one line in two, or both. CHISEL has no flip and no
// destination step, so each shape gets its own source strip, rebuilt every frame
// from the font (9 letter blits from cart RAM each) and copied by stepped,
// per-column-group blits (stcs_strip.zig):
//   N   the strip itself                      320 x 34, plane 2 +0
//   F   N upside down (from the flipped font)  320 x 34, plane 2 +10880
//   G   N on every other row (rows 2y), the     320 x 68, plane 2 +21760
//       rows between hold KEY: a keyed blit of G writes N one line in two
//   FG  F the same way                          320 x 68, plane 3 +0
// G and FG are written through a 640-stride view (one strip row lands every
// other 320-pixel row); the KEY rows between are filled once at init and never
// written again. Planes 2 and 3 are never enabled, so FRESCO never composites
// them, and every copy onto plane 1 reads another plane: no in-plane copy.
// --------------------------------------------------------------------------
const zg = @import("zigos");

const LogicalFB = zg.LogicalFB;
const Blitter = zg.Blitter;

pub const W: u16 = zg.WIDTH;
pub const GW: u16 = 40; // letter width
pub const GH: u16 = 34; // letter height = strip height
pub const KEY: u8 = 0xFF; // never a font pixel (COLORS)
/// Every pixel the strips put on plane 1 is a font pixel or 0, so below this.
pub const COLORS: usize = 16;
const STRIP: usize = @as(usize, W) * GH;

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
            self.src[i] = view(base, W);
            self.put[i] = view(base, if (i >= 2) 2 * W else W);
        }
        // the KEY rows of G and FG: the odd 320-pixel rows, once
        for (at[2..]) |base| {
            var keys = view(base + W, 2 * W);
            c.fill(&keys, 0, 0, W, GH, KEY);
        }
    }

    /// Rebuild strip `k` from the scroller's letters, as letter_rows.draw built
    /// the CPU strip: cleared to 0, then each letter clipped to 0..320, in order.
    pub fn build(self: *Scratch, c: *Blitter, st: anytype, k: Kind) void {
        const v = &self.put[@intFromEnum(k)];
        c.fill(v, 0, 0, W, GH, 0);
        const font = if (k == .f or k == .fg) self.flipped else self.font;
        for (&st.fonts) |*f| {
            const from: i32 = @max(0, -f.pos_x);
            const to: i32 = @min(@as(i32, GW), @as(i32, W) - f.pos_x);
            if (from >= to) continue;
            const off = @intFromPtr(f.sprite.data.ptr) - @intFromPtr(self.font.ptr);
            const glyph = font[off..][0 .. @as(usize, GW) * GH];
            c.blitImage(v, @intCast(f.pos_x + from), 0, glyph, GW, @intCast(from), 0, @intCast(to - from), GH, null);
        }
    }
};

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
