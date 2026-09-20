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
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const P = @import("planes.zig");

const SLOTS: usize = 20; // $95058..$952d8 is 20 columns of 16 words
const ROWS: usize = 16;
const TOP: usize = 12; // screen + $786 is row 12, plane 3
const WAVE_LEN: usize = 180; // entries 180..199 duplicate 0..19 for the window

pub const Scroller = struct {
    ring: [2][SLOTS][ROWS]u16,
    write: [2]usize,
    state: u2,
    glyph: u8, // the glyph states 1..3 cut from
    prev: u8, // ...and the one state 0 spans out of
    text: usize,
    wave: usize,

    pub fn init(self: *Scroller) void {
        for (&self.ring) |*r| for (r) |*s| @memset(s, 0);
        self.write = .{ 0, 0 };
        self.state = 0;
        self.glyph = space();
        self.prev = space();
        self.text = 0;
        self.wave = 0;
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

    pub fn update(self: *Scroller) void {
        if (self.state == 0) {
            self.prev = self.glyph;
            self.glyph = self.nextGlyph();
        }
        const r: usize = self.state & 1; // one ring per ST screen buffer
        const slot = &self.ring[r][self.write[r]];
        for (slot, 0..) |*w, i| w.* = self.column(i);
        self.write[r] = (self.write[r] + 1) % SLOTS;
        self.state +%= 1;

        self.wave += 1;
        if (self.wave >= WAVE_LEN) self.wave = 0;
    }

    /// Paint the ring just written into plane 3, oldest column at screen x 0.
    pub fn draw(self: *const Scroller) void {
        const r: usize = (self.state +% 3) & 1; // the ring update() just pushed
        var c: usize = 0;
        while (c < SLOTS) : (c += 1) {
            const slot = &self.ring[r][(self.write[r] + c) % SLOTS];
            drawColumn(slot, c, TOP + A.wave[self.wave + c]);
        }
    }
};

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

comptime {
    if (WAVE_LEN + SLOTS > A.wave.len) @compileError("the wave window reads past wave.dat");
    if (A.ascii_to_glyph[' '] == 0xff) @compileError("the big font has no space cell");
    // wave[] holds rows 60..120, so the band lives in 68..171 and never leaves
    // the plane or the recomposed band.  Checked here because drawColumn does
    // not clamp -- exactly as $e602 did not.
    @setEvalBranchQuota(8000);
    var lo: usize = 255;
    var hi: usize = 0;
    for (A.wave) |w| {
        if (w < lo) lo = w;
        if (w > hi) hi = w;
    }
    if (TOP + lo < 4 + P.LIVE_TOP) @compileError("the scroller's blank rows run above the recomposed band");
    if (TOP + hi + 40 > P.LIVE_TOP + P.LIVE_ROWS) @compileError("the scroller runs below the recomposed band");
}
