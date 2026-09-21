// --------------------------------------------------------------------------
// The scrolltext feed: UPDATE_CHARACTER + UPDATE_EDGE_BUFFER (TEXT $6ba, $71a),
// which is everything the original does inside its VBL.
//
// The font is not a bitmap. Each pixel column of a glyph is SIX row numbers, and
// a row number toggles the fill state from that row down (band.zig runs the
// XOR). Six toggles is an even number, so a column always closes; a glyph that
// needs fewer edges pads with repeats of row 0, which cancel in pairs — that is
// why a column of "\0\0\0\0\0\x0b" fills rows 0..10 and one of six zeroes fills
// nothing at all.
//
// EDGE_BUFFER is a 320-column ring written two columns a frame (so the text
// scrolls at 2 pixels a frame) and held TWICE end to end, so PLOT_EDGES can read
// 320 columns from any start without wrapping. Kept at module scope: it is this
// cart's, and a 3840-byte array does not belong in the Demo struct.
// --------------------------------------------------------------------------
const A = @import("assets.zig");

var edge: [A.COLUMNS * 2 * A.EDGES]u8 = undefined;

pub const Scroller = struct {
    pos: usize, // EDGE_BUFFER_POS, in columns
    text: usize, // SCROLLER_POS, the index into SCROLL_TEXT
    glyph: usize, // CURRENT_CHAR_PTR, as an offset into the font
    xpos: u8, // CURRENT_CHAR_XPOS: how far into the glyph we are
    width: u8, // CURRENT_CHAR_WIDTH

    pub fn init(self: *Scroller) void {
        self.pos = 0;
        self.text = 0;
        self.glyph = 0;
        self.xpos = 0;
        self.width = 0;
        @memset(&edge, 0);
    }

    /// One VBL: take the next two columns of the current glyph into the ring.
    pub fn step(self: *Scroller) void {
        if (self.xpos == self.width) {
            self.nextChar();
            self.xpos = 0;
        }
        const src = self.glyph + @as(usize, self.xpos) * A.EDGES;
        const n = 2 * A.EDGES;
        const dst = self.pos * A.EDGES;
        @memcpy(edge[dst..][0..n], A.font[src..][0..n]);
        @memcpy(edge[A.COLUMNS * A.EDGES + dst ..][0..n], A.font[src..][0..n]);

        self.pos += 2;
        if (self.pos >= A.COLUMNS) self.pos = 0;
        self.xpos += 2;
    }

    /// The 320 columns PLOT_EDGES reads this frame: oldest first, so a new
    /// column appears at the right-hand edge.
    pub fn window(self: *const Scroller) []const u8 {
        return edge[self.pos * A.EDGES ..][0 .. A.COLUMNS * A.EDGES];
    }

    /// text.bin stops at SCROLL_TEXT's NUL. The original reads that NUL, shows a
    /// SPACE for that one frame and sets SCROLLER_POS to 0, so the wrap costs a
    /// space rather than skipping a glyph; end of the buffer means the same here.
    fn nextChar(self: *Scroller) void {
        var c: u8 = ' ';
        if (self.text < A.text.len) {
            c = A.text[self.text];
            self.text += 1;
        } else {
            self.text = 0;
        }
        const i: usize = if (c >= 0x20 and c < 0x20 + A.GLYPHS) c - 0x20 else 0;
        self.width = A.widths[i];
        self.glyph = i * A.GLYPH_STRIDE;
    }
};
