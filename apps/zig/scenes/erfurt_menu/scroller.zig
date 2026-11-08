// --------------------------------------------------------------------------
// The scroller in plane 2 ($12EB4 init, $13D0E a frame).
//
// The text sits in a ring of 32 columns x 40 lines (16 px a column, $703DC).
// A column holds one character of the 16x16 font ($308A2), its pixel columns
// pushed down by a wave baked once at init: W[x] = (9 sin x + 3 sin 2x) / 2048
// + 12 over x = 0..255, less the smallest W of the column's 16 pixels (that
// minimum is how far the whole column starts down, at most 16). The wave goes
// with the ring column, so it travels with the letters.
//
// Each frame the ring moves 2 px; on screen, line L of the 40 is read from the
// ring 16*first + sub + h(L) pixels in, h(L) = sin(p + 2L)/256 + 8 a second wave
// that runs DOWN the lines (p += $260 a frame): the strip shimmies. The strip's
// top bobs on two more sines around the drum's middle, clamped to 45..127.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const S = @import("screen.zig");

pub const LINES = 40;
const COLS = 32;
const TOP_MIN: i32 = 45;
const TOP_MAX: i32 = 166 - 39; // $4EBCC - $27

pub const Scroller = struct {
    ring: [COLS][LINES]u16,
    wave: [256]u8, // $64CB2
    pad: [16]u8, // $703BC
    first: u16, // $64CA0: ring column at the strip's left
    sub: u16, // $64CA2: 0..14, two pixels a frame
    text_pos: usize, // $64C9E: text index of ring column `first`
    ph_bob1: u16, // $64CA6
    ph_bob2: u16, // $64CA8
    ph_shim: u16, // $64CAA
    top: i32, // $64CB0

    pub fn init(self: *Scroller, text_pos: usize) void {
        for (0..256) |x| { // $12F08
            const s1: i32 = A.sinAt(x);
            const s2: i32 = A.sinAt(2 * x);
            const v = (9 * s1 + 3 * s2 + 0x400) >> 11;
            self.wave[x] = @intCast(v + 12);
        }
        for (0..16) |g| { // $12F54
            var m: u8 = 0x7F;
            for (self.wave[16 * g ..][0..16]) |w| m = @min(m, w);
            self.pad[g] = @min(m, 16);
        }
        self.first = 0;
        self.sub = 0;
        self.text_pos = text_pos % A.scrolltext.len;
        self.ph_bob1 = 0;
        self.ph_bob2 = 0;
        self.ph_shim = 0;
        self.top = TOP_MIN;
        for (0..COLS) |c| self.fill(c);
    }

    /// $130C0 + $13178: ring column `c` gets the character the text has there.
    fn fill(self: *Scroller, c: usize) void {
        const ahead = (c + COLS - self.first) % COLS;
        const ch = A.scrolltext[(self.text_pos + ahead) % A.scrolltext.len];
        const g = c & 15;
        const col = &self.ring[c];
        @memset(col, 0);
        if (ch < 0x20 or ch - 0x20 >= A.SCROLL_GLYPHS) return;
        const glyph = @as(usize, ch - 0x20) * 16;
        const pad = self.pad[g];
        // $1302E: the 24-line tile, each pixel column dropped by its wave
        for (0..16) |b| {
            const mask = @as(u16, 0x8000) >> @intCast(b);
            const drop = @min(self.wave[16 * g + b] - pad, 8);
            for (0..16) |r| {
                const w = A.be(A.scrollfont, glyph + r) & mask;
                col[pad + drop + r] |= w;
            }
        }
    }

    /// $13D0E's motion: two pixels, a new column every 8 frames.
    pub fn step(self: *Scroller, drum_top: i32, drum_n: i32) void {
        self.sub += 2;
        if (self.sub >= 16) {
            self.sub -= 16;
            const old = self.first;
            self.first = (self.first + 1) % COLS;
            self.text_pos = (self.text_pos + 1) % A.scrolltext.len;
            self.fill(old); // the column that left on the left comes back on the right
        }
        self.ph_bob1 +%= 0x120;
        self.ph_bob2 +%= 0xB0;
        self.ph_shim +%= 0x260;
        const s1: i32 = A.sin(self.ph_bob1);
        const s2: i32 = A.sin(self.ph_bob2);
        var y: i32 = @as(i16, @truncate(3 * s1)) >> 9;
        y += s2 >> 9;
        y += drum_top + (drum_n >> 1) - 16;
        self.top = @max(TOP_MIN, @min(y, TOP_MAX));
    }

    pub fn textPos(self: *const Scroller) usize {
        return self.text_pos;
    }

    /// Plane 2 of lines 45..166: the strip, nothing else.
    pub fn draw(self: *const Scroller, st: *S.Screen) void {
        var y: usize = @intCast(TOP_MIN);
        while (y <= 166) : (y += 1) {
            for (0..20) |g| st.rows[y][4 * g + 2] = 0;
        }
        for (0..LINES) |l| {
            const h: u32 = @intCast((A.sinAt((self.ph_shim >> 8) + 2 * l) >> 8) + 8);
            const off: u32 = 16 * @as(u32, self.first) + self.sub + h;
            const row = &st.rows[@intCast(self.top + @as(i32, @intCast(l)))];
            for (0..20) |g| row[4 * g + 2] = self.word(l, off + 16 * @as(u32, @intCast(g)));
        }
    }

    /// 16 ring pixels from pixel `px` of line `l`, wrapping round the 512.
    fn word(self: *const Scroller, l: usize, px: u32) u16 {
        const c = (px >> 4) % COLS;
        const s: u5 = @intCast(px & 15);
        const hi: u32 = self.ring[c][l];
        const lo: u32 = self.ring[(c + 1) % COLS][l];
        return @truncate(((hi << 16) | lo) >> (16 - @as(u5, s)));
    }
};
