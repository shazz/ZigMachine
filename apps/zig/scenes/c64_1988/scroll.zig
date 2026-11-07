// --------------------------------------------------------------------------
// Part 1's proportional scroller ($5500): 8 X-expanded sprites, one glyph each, walking left
// 4 pixels a frame ("X coordinates precalculated": idx is an index into tables.scroll_x).
// A glyph that reaches index 0 (off the left edge) is recycled behind the one before it in
// the ring (7 follows 6 ... 0 follows 7) with the next character of the text, spaced
// 12 steps (48 pixels, a whole glyph) minus that character's cut. Blocks run 7 down to 0, so
// sprite 0 follows a sprite 7 already moved this frame: hence its 13.
//
// The text buffer is the original's $60A2: a copy of the text from index 1 to its length
// (index 0 is never copied), read up to index 250 (the scroll position wraps at $F3), so
// what the last text left past 145 stays there, as on the C64.
// --------------------------------------------------------------------------
pub const WRAP: u8 = 0xF3;
pub const FONT_BLOCK: u8 = 0x48; // the glyphs start at sprite block $48 ($D200)

pub const Scroll = struct {
    buf: [256]u8 = .{0} ** 256, // $60A2..
    idx: [8]u8 = .{0} ** 8, // $40..$47: position index per sprite
    ptr: [8]u8 = .{0} ** 8, // $51..$58: sprite pointer per sprite
    pos: u8 = 0, // $50: text position

    pub fn start(self: *Scroll, text: *const [146]u8, len: u8) void {
        var x: usize = len;
        while (x > 0) : (x -= 1) self.buf[x] = text[x];
        for (0..8) |s| {
            self.idx[s] = @intCast(12 * s);
            self.ptr[s] = self.buf[s] +% FONT_BLOCK;
        }
        self.pos = 0;
    }

    pub fn step(self: *Scroll, cut: *const [256]u8) void {
        var s: usize = 8;
        while (s > 0) {
            s -= 1;
            if (self.idx[s] == 0) self.recycle(s, cut);
            self.idx[s] -%= 1;
        }
    }

    fn recycle(self: *Scroll, s: usize, cut: *const [256]u8) void {
        const prev: usize = if (s == 0) 7 else s - 1;
        const gap: u8 = if (s == 0) 13 else 12;
        const c = self.buf[8 + @as(usize, self.pos)];
        self.idx[s] = self.idx[prev] +% gap -% cut[c];
        self.pos = if (self.pos + 1 == WRAP) 0 else self.pos + 1;
        self.ptr[s] = self.buf[7 + @as(usize, self.pos)] +% FONT_BLOCK;
    }
};
