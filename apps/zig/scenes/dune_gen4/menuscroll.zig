// The menu's scroller ($FFA8): FONTE.DAT's 32x27 one-plane glyphs rolled into
// PLANE 3 of lines 150..176, four one-pixel ROXLs a VBL through the glyph's
// own 32 bits and the line's twenty plane-3 words -- so whatever plane 3 the
// picture had on those lines scrolls away to the left with the text. Colour 8
// there is the gradient Timer B writes from line 150.
//
// A new glyph is fetched every eight VBLs. On the text's $FF the pointer goes
// back to the start and that VBL does not scroll; the glyph in hand by then is
// spent, so the next eight VBLs roll in blank: a 32-pixel gap at the wrap.
const std = @import("std");
const zg = @import("zigos");
const st = @import("st.zig");
const A = @import("assets.zig");

const TEXT = A.T.MENU_TEXT;
pub const TOP = 150; // $5DC0 / 160
pub const LINES = 27; // $1B
const GLYPH_BYTES = 108;

pub const MenuScroll = struct {
    rows: [LINES][20]u16, // plane 3 of each line, as the screen holds it
    glyph: [LINES]u32, // $104AE: what is still to roll in
    count: u8, // $104A8
    next: usize, // $104AA

    /// Start on the picture's own plane 3.
    /// Once: the text from its start ($104A8..$104AE are only data).
    pub fn init(self: *MenuScroll) void {
        @memset(&self.glyph, 0);
        self.count = 0;
        self.next = 0;
    }

    /// Every time the menu is loaded: the band is the picture's plane 3 again,
    /// and the text carries on where it was, half-rolled glyph and all.
    pub fn load(self: *MenuScroll, fb: *zg.LogicalFB) void {
        for (&self.rows, 0..) |*r, l| {
            const px = st.row(fb, TOP + l);
            for (r, 0..) |*w, g| {
                w.* = 0;
                for (0..16) |i| w.* |= @as(u16, (px[g * 16 + i] >> 3) & 1) << @intCast(15 - i);
            }
        }
    }

    pub fn vbl(self: *MenuScroll) void {
        if (self.count == 0) {
            self.count = 8;
            if (self.next >= TEXT.len) { // the $FF
                self.next = 0;
                return;
            }
            self.fetch(TEXT[self.next]);
            self.next += 1;
        }
        self.count -= 1;
        for (0..4) |_| self.roll();
    }

    fn fetch(self: *MenuScroll, c: u8) void {
        const g = A.FONTE[@as(usize, c) * GLYPH_BYTES ..][0..GLYPH_BYTES];
        for (&self.glyph, 0..) |*w, l| w.* = std.mem.readInt(u32, g[l * 4 ..][0..4], .big);
    }

    /// lsl.w 2(a1) / roxl.w (a1) / roxl.w on the twenty words, right to left.
    fn roll(self: *MenuScroll) void {
        for (&self.rows, &self.glyph) |*r, *gl| {
            var x: u16 = @intCast(gl.* >> 31);
            gl.* <<= 1;
            var g: usize = 20;
            while (g > 0) {
                g -= 1;
                const out = r[g] >> 15;
                r[g] = (r[g] << 1) | x;
                x = out;
            }
        }
    }

    /// Plane 3 of the band back into the pixels.
    pub fn draw(self: *const MenuScroll, fb: *zg.LogicalFB) void {
        for (self.rows, 0..) |r, l| {
            const px = st.row(fb, TOP + l);
            for (px) |*p| p.* &= 7;
            for (r, 0..) |w, g| st.orWord(px, @intCast(g * 16), w, 3);
        }
    }
};

comptime {
    @setEvalBranchQuota(10000);
    for (TEXT) |c| if (c >= A.FONTE_GLYPHS) @compileError("menu text names a glyph FONTE.DAT has not");
}
