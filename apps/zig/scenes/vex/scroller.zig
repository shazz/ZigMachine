// --------------------------------------------------------------------------
// The big green scroller ($e3a0), Slippy's all-caps text in Jade's 32x16 font.
//
// The font is one bitplane; the glyph is stored as 16 words of its LEFT half
// followed by 16 of its RIGHT (that is the `lsl.w #6` 64-byte stride, and it is
// how $3864 lays the cells out).  A four-state machine cuts one 16-px column
// out of the glyph pair every frame, at 8-px steps:
//
//   state 0  prev.right low  | cur.left high   (px -8..7, spanning two glyphs)
//   state 1  cur.left                          (px 0..15)
//   state 2  cur.left low    | cur.right high  (px 8..23)
//   state 3  cur.right                         (px 16..31)
//
// States 1 and 3 push into one 20-column ring and 0 and 2 into the other; on
// the ST those two rings belonged to the two screen buffers, which is how 16-px
// steps per ring read as 8 px a frame.  Here the rings alternate on the single
// framebuffer, which comes to the same thing.
//
// Each column is then drawn at 12 + wave[i] rows down, doubled vertically to 32
// lines, with 4 blank rows above and 8 below to erase last frame ($e602).
//
// The rings hold 26 columns, not 20: three either side of the window, so ZIG
// MODE can run the scroller on through the open side borders.  The right
// border shows columns the window has not reached yet, so init() cuts AHEAD
// columns per ring up front: the window still shows the ST's 20 columns, the
// cutter simply runs three of a ring's columns ahead of it.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const P = @import("planes.zig");

const SLOTS: usize = P.BUF_WORDS; // $95058..$952d8 held the window's 20 of them
const AHEAD: usize = SLOTS - P.WIN_WORD - P.WORDS; // 3: the right border's columns
const ROWS: usize = 16;
const TOP: usize = 12; // screen + $786 is row 12, plane 3
const WAVE_LEN: usize = 180; // entries 180..199 let the window read wave[wave + k] without wrapping

pub const Scroller = struct {
    ring: [2][SLOTS][ROWS]u16,
    write: [2]usize,
    state: u2,
    glyph: u8, // the glyph states 1..3 cut from
    prev: u8, // ...and the one state 0 spans out of
    text: usize,
    wave: usize,
    /// Where draw() last put each side-border column (buffer words 0..2 then
    /// 23..25), so ZIG MODE recomposes only the rows that changed.
    side_y0: [2 * P.WIN_WORD]usize,

    pub fn init(self: *Scroller) void {
        for (&self.ring) |*r| for (r) |*s| @memset(s, 0);
        self.write = .{ 0, 0 };
        self.state = 0;
        self.glyph = space();
        self.prev = space();
        self.text = 0;
        self.wave = 0;
        // An even count keeps each ring on its own parity of frames.
        for (0..2 * AHEAD) |_| self.push();
        for (&self.side_y0) |*y| y.* = REACH_TOP + 4;
    }

    fn space() u8 {
        return A.ascii_to_glyph[' '];
    }

    /// $e51c: the next codepoint the font actually has a cell for.
    fn nextGlyph(self: *Scroller) u8 {
        var guard: usize = 0;
        while (guard < A.scroll_big.len) : (guard += 1) {
            const c = A.scroll_big[self.text];
            self.text += 1;
            if (self.text >= A.scroll_big.len) self.text = 0;
            const g = A.ascii_to_glyph[c];
            if (g != 0xff) return g;
        }
        return space();
    }

    fn left(g: u8, i: usize) u16 {
        return A.glyphWord(g, i);
    }
    fn right(g: u8, i: usize) u16 {
        return A.glyphWord(g, 16 + i);
    }

    fn column(self: *Scroller, i: usize) u16 {
        return switch (self.state) {
            0 => ((right(self.prev, i) & 0xff) << 8) | (left(self.glyph, i) >> 8),
            1 => left(self.glyph, i),
            2 => ((left(self.glyph, i) & 0xff) << 8) | (right(self.glyph, i) >> 8),
            3 => right(self.glyph, i),
        };
    }

    /// One cut: a column into the ring of this state's parity.
    fn push(self: *Scroller) void {
        if (self.state == 0) {
            self.prev = self.glyph;
            self.glyph = self.nextGlyph();
        }
        const r: usize = self.state & 1; // one ring per ST screen buffer
        const slot = &self.ring[r][self.write[r]];
        for (slot, 0..) |*w, i| w.* = self.column(i);
        self.write[r] = (self.write[r] + 1) % SLOTS;
        self.state +%= 1;
    }

    pub fn update(self: *Scroller) void {
        self.push();
        self.wave += 1;
        if (self.wave >= WAVE_LEN) self.wave = 0;
    }

    /// Paint the ring just written into plane 3, oldest column at window x 0;
    /// `sides` also paints the three columns either side, for the open borders.
    pub fn draw(self: *Scroller, sides: bool) void {
        const r: usize = (self.state +% 3) & 1; // the ring update() just pushed
        const first: usize = if (sides) 0 else P.WIN_WORD;
        const end: usize = if (sides) SLOTS else P.WIN_WORD + P.WORDS;
        var c: usize = first;
        while (c < end) : (c += 1) {
            const slot = &self.ring[r][(self.write[r] + c) % SLOTS];
            const y0 = TOP + A.wave[waveIndex(self.wave, c)];
            drawColumn(slot, c, y0);
            if (c < P.WIN_WORD) self.side_y0[c] = y0;
            if (c >= P.WIN_WORD + P.WORDS) self.side_y0[c - P.WORDS] = y0;
        }
    }
};

/// The window's column k reads wave[wave + k], exactly as $e602 did (180 + 20
/// entries, so it never wraps). The side columns, k = -3..-1 and 20..22, step
/// past either end of that and are folded back by the 180-entry period.
fn waveIndex(wave: usize, c: usize) usize {
    var i = wave + c;
    if (i < P.WIN_WORD) i += WAVE_LEN;
    i -= P.WIN_WORD;
    if (i >= A.wave.len) i -= WAVE_LEN;
    return i;
}

fn drawColumn(slot: *const [ROWS]u16, c: usize, y0: usize) void {
    var k: usize = 0;
    while (k < 4) : (k += 1) P.scroll[y0 - 4 + k][c] = 0;
    for (slot, 0..) |w, i| {
        P.scroll[y0 + 2 * i][c] = w;
        P.scroll[y0 + 2 * i + 1][c] = w;
    }
    k = 0;
    while (k < 8) : (k += 1) P.scroll[y0 + 32 + k][c] = 0;
}

/// The rows a column's ink can reach (wave.dat's range): ZIG MODE opens the
/// side borders on these lines and no others.
pub const INK_TOP: usize = TOP + waveMin();
pub const INK_END: usize = TOP + waveMax() + 2 * ROWS;
/// drawColumn() paints from 4 rows above a column's y0 to 8 below its ink.
pub const REACH_TOP: usize = INK_TOP - 4;
pub const REACH_END: usize = INK_END + 8;
pub const COLUMN_ROWS: usize = 4 + 2 * ROWS + 8;

fn waveMin() usize {
    @setEvalBranchQuota(8000);
    var lo: usize = 255;
    for (A.wave) |w| lo = @min(lo, w);
    return lo;
}
fn waveMax() usize {
    @setEvalBranchQuota(8000);
    var hi: usize = 0;
    for (A.wave) |w| hi = @max(hi, w);
    return hi;
}

comptime {
    if (WAVE_LEN + P.WORDS > A.wave.len) @compileError("the wave window reads past wave.dat");
    if (WAVE_LEN + P.BUF_WORDS - P.WIN_WORD > A.wave.len + WAVE_LEN) @compileError("a side column folds twice");
    if (A.ascii_to_glyph[' '] == 0xff) @compileError("the big font has no space cell");
    // wave[] holds rows 60..120, so the band lives in 68..171 and never leaves
    // the plane or the recomposed band.  Checked here because drawColumn does
    // not clamp -- exactly as $e602 did not.
    if (REACH_TOP < P.LIVE_TOP) @compileError("the scroller's blank rows run above the recomposed band");
    if (REACH_END > P.LIVE_TOP + P.LIVE_ROWS) @compileError("the scroller runs below the recomposed band");
}
