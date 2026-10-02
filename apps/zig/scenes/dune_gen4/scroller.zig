// The main part's scroller ($465C, $4AF6): ALPHA.DAT's 32x32 two-plane glyphs
// on lines 200..231 -- under the screen, in the lower border Timer B opens --
// four pixels a VBL, inked by colour 3, which Timer B rewrites every line there.
//
// The original keeps the last eleven characters and redraws them all every
// VBL from four copies of the font pre-shifted by 12, 8, 4 and 0 pixels, at
// 16-pixel columns that alternate between odd and even every four VBLs. Taken
// together that is one thing: character k back from the newest has its left
// edge at 316 - 32k - 4f, f = 0..7 the VBLs since it came in, clipped to the
// 320-pixel line. The eleven start as the text's first eleven, newest first,
// and the part ends when the text's $FF is read.
const std = @import("std");
const zg = @import("zigos");
const st = @import("st.zig");
const A = @import("assets.zig");

const TEXT = A.T.MAIN_TEXT;
pub const TOP = 200; // $1320
pub const LINES = 32;
const KEPT = 11; // $12E0..$12F4

pub const Scroller = struct {
    chars: [KEPT]u8, // [0] = the newest
    next: usize, // $1326, into TEXT
    f: u8, // 4 x state ($132C) + phase ($12F8)
    done: bool, // $132A

    pub fn init(self: *Scroller) void {
        for (&self.chars, 0..) |*c, k| c.* = TEXT[k];
        self.next = KEPT;
        self.f = 0;
        self.done = false;
    }

    pub fn vbl(self: *Scroller) void {
        self.f += 1;
        if (self.f < 8) return;
        self.f = 0;
        std.mem.copyBackwards(u8, self.chars[1..], self.chars[0 .. KEPT - 1]);
        if (self.next >= TEXT.len) {
            self.done = true;
            self.chars[0] = A.ALPHA_GLYPHS; // nothing
            return;
        }
        self.chars[0] = TEXT[self.next];
        self.next += 1;
    }

    pub fn clear(fb: *zg.LogicalFB) void {
        for (TOP..TOP + LINES) |y| @memset(st.row(fb, y), 0);
    }

    pub fn draw(self: *const Scroller, fb: *zg.LogicalFB) void {
        clear(fb);
        for (self.chars, 0..) |c, k| {
            const x = 316 - 32 * @as(i32, @intCast(k)) - 4 * @as(i32, self.f);
            drawGlyph(fb, c, x);
        }
    }
};

fn drawGlyph(fb: *zg.LogicalFB, g: u8, x: i32) void {
    if (g >= A.ALPHA_GLYPHS or x <= -32 or x >= st.W) return;
    const glyph = A.ALPHA[@as(usize, g) * 256 ..][0..256];
    for (0..LINES) |l| {
        const px = st.row(fb, TOP + l);
        const w = glyph[l * 8 ..][0..8];
        st.orWord(px, x, be16(w[0..2]), 0);
        st.orWord(px, x, be16(w[2..4]), 1);
        st.orWord(px, x + 16, be16(w[4..6]), 0);
        st.orWord(px, x + 16, be16(w[6..8]), 1);
    }
}

fn be16(b: *const [2]u8) u16 {
    return std.mem.readInt(u16, b, .big);
}
