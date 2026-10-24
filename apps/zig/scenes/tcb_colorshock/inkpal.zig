// --------------------------------------------------------------------------
// COLORSHOCK 2 — the ink's colours in the FIELD's palette, so the logo and the
// scroll strip can be drawn into the panned plane instead of a second one.
//
// The field rewrites entries 0..104 on every line (field.zig). The ink's 255
// colours (logo 10, font + scroll_acc 245) can't sit beside them whole, but on
// any one LINE they can: the logo's lines (49..81) and the strip's (85..207)
// never meet, the logo needs 10 entries, and one strip row needs only the
// colours of the 11 glyphs on screen plus scroll_acc's — at most 113 over the
// whole scrolltext (inkpal_test.zig). So:
//   105..114  the logo, fixed (written once)
//   115..255  strip row gy's colours, handed out per frame and written by the
//             HBL on the strip's line gy (hbl.zig), like TCB's own per-line
//             palettes
//
// The planes (2026-10-23; every enabled plane costs FRESCO ~0.6 Mc a frame,
// and the ink plane was a whole one for 7 % of its lines):
//   effect                     before                    after
//   512-colour field (pan)     plane 0, HW scroll,       plane 0, entries 0..104
//                              105 entries a line (HBL)  a line (HBL)
//   THE CAREBEARS logo         plane 1, ink palette      plane 0, entries 105..114
//   scroll strip               plane 1, ink palette      plane 0, entries 115..255
//                                                        per strip line (HBL)
// Plane 0 is kept for the hardware pan (setScroll: one register, zero pixels).
// The ink is drawn into the pan buffer at the window's position every frame,
// and the field put back under it from the tile in cart RAM (field.restore).
// --------------------------------------------------------------------------
const std = @import("std");

const DIR = "../../assets/screens/tcb_colorshock/";
const ink_pal_b = @embedFile(DIR ++ "ink_pal.dat");
const logo_b = @embedFile(DIR ++ "logo.raw");

pub const FIELD_COLOURS: u8 = 105;
pub const LOGO_FIRST: u8 = FIELD_COLOURS;
pub const LOGO_COLOURS: u8 = 10;
pub const STRIP_FIRST: u8 = LOGO_FIRST + LOGO_COLOURS; // 115
pub const STRIP_ENTRIES: usize = 256 - @as(usize, STRIP_FIRST); // 141

/// ink_pal.dat as palette words (the same little-endian RGBA as the field's).
pub const ink_words: [256]u32 = blk: {
    @setEvalBranchQuota(10_000);
    var w: [256]u32 = undefined;
    for (&w, 0..) |*x, i| x.* = std.mem.readInt(u32, ink_pal_b[i * 4 ..][0..4], .little);
    break :blk w;
};

const LogoMap = struct { pixels: [logo_b.len]u8, colours: [LOGO_COLOURS]u32 };

/// The logo with its ink indices renumbered to LOGO_FIRST.., 0 kept (the key).
const logo_map: LogoMap = blk: {
    @setEvalBranchQuota(100_000);
    var m: LogoMap = undefined;
    var to = [_]u8{0} ** 256;
    var n: u8 = 0;
    for (logo_b, 0..) |v, i| {
        if (v != 0 and to[v] == 0) {
            if (n == LOGO_COLOURS) @compileError("the logo has more than LOGO_COLOURS colours");
            to[v] = LOGO_FIRST + n;
            m.colours[n] = ink_words[v];
            n += 1;
        }
        m.pixels[i] = to[v];
    }
    break :blk m;
};
pub const logo_pixels = logo_map.pixels;
pub const logo_colours = logo_map.colours;

/// Renumbers the strip one row at a time and keeps each row's palette for the
/// HBL. The key is the ink index itself, so a stamp table is the whole lookup.
pub fn StripPal(comptime rows: usize) type {
    return struct {
        const Self = @This();
        /// Row gy's entries from STRIP_FIRST on, and how many it uses.
        colours: [rows][STRIP_ENTRIES]u32 = undefined,
        used: [rows]u8 = [_]u8{0} ** rows,
        to: [256]u8 = undefined,
        stamp: [256]u32 = [_]u32{0} ** 256,
        gen: u32 = 0,
        /// Most entries any row has needed, and pixels that found none.
        peak: u8 = 0,
        overflow: u32 = 0,

        /// Forget every row: a re-entered scene must not inherit them.
        pub fn reset(self: *Self) void {
            @memset(&self.used, 0);
            @memset(&self.stamp, 0);
            self.gen = 0;
            self.peak = 0;
            self.overflow = 0;
        }

        /// Lay `over` on `row` (ink indices, 0 = transparent: scroll_acc on the
        /// glyphs) and renumber the result in place as strip row gy. One pass.
        pub fn remapRow(self: *Self, gy: usize, row: []u8, over: []const u8) void {
            self.gen +%= 1;
            if (self.gen == 0) {
                @memset(&self.stamp, 0);
                self.gen = 1;
            }
            var n: u8 = 0;
            for (row, over) |*p, a| {
                const v = if (a != 0) a else p.*;
                if (v == 0) continue;
                if (self.stamp[v] != self.gen) {
                    self.stamp[v] = self.gen;
                    self.to[v] = self.take(gy, &n, v);
                }
                p.* = self.to[v];
            }
            self.used[gy] = n;
            self.peak = @max(self.peak, n);
        }

        fn take(self: *Self, gy: usize, n: *u8, v: u8) u8 {
            if (n.* == STRIP_ENTRIES) {
                self.overflow += 1;
                return 255;
            }
            const k = n.*;
            self.colours[gy][k] = ink_words[v];
            n.* = k + 1;
            return STRIP_FIRST + k;
        }
    };
}
