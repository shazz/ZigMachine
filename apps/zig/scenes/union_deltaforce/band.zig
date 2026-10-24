// --------------------------------------------------------------------------
// A text band: the canvas chain both of DELTA FORCE's texts go through
// (screen.js:330-337, 353-432), at half resolution:
//
//   text canvas   32 rows: letters printed with font.drawTile, cleared first
//   merge canvas  110 rows: FX.siny of the text canvas, then the gold backdrop
//                 drawn 'source-atop', which keeps the letters' alpha and takes
//                 the gold texture's colour under each of them
//   main canvas   the merge canvas drawn mid-handled with a vertical scale
//
// The text canvas is kept halved twice (see wave.sinyHalved) as alpha levels;
// the merge canvas holds final palette indices, 0 where no letter landed.
// The siny copy and the gold recolour are one pass (band_compose.zig): each
// merge pixel is written once, from the text pixel and the gold pixel under it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const stretch = @import("../union_common/stretch.zig");
const compose = @import("band_compose.zig");

pub const STRIP_ROWS = A.GLYPH_ROWS[1];
pub const MERGE_ROWS = compose.MERGE_ROWS; // new canvas(..., 110)
pub const GoldCols = compose.GoldCols;

pub const Band = struct {
    w: usize,
    strips: [2][]u8, // the text canvas, halved at parity 0 and 1
    merge: []u8,
    text: ?usize = null, // which text the strips hold, for a caller that redraws it only on change
    /// Merge rows [rows[0], rows[1]) hold the text of the columns the last compose
    /// wrote (their other rows are 0), and whether it wrote them upside down.
    rows: [2]usize = .{ 0, 0 },
    flipped: bool = false,
    /// The strips are stored by columns (column i's rows at i * STRIP_ROWS), for a
    /// wave compose, which reads them down a column; else by rows, for a flat one.
    transposed: bool,

    pub fn bytes(w: usize) usize {
        return w * (2 * STRIP_ROWS + MERGE_ROWS);
    }

    /// `buf` must be bytes(w) long.
    pub fn init(buf: []u8, w: usize, transposed: bool) Band {
        @memset(buf, 0); // once: the intro never clears its text canvas again (intro.zig)
        const s = w * STRIP_ROWS;
        return .{ .w = w, .strips = .{ buf[0..s], buf[s .. 2 * s] }, .merge = buf[2 * s ..][0 .. w * MERGE_ROWS], .transposed = transposed };
    }

    /// canvas.clear() of the text canvas, in the one halving a flat siny reads.
    pub fn clearStrip(self: *Band, parity: u1) void {
        @memset(self.strips[parity], 0);
    }

    /// font.drawTile(text canvas, ch - 32, canvas_x, 0). Letters sit 64 canvas
    /// pixels apart, so they never overlap and a plain copy is the composite.
    pub fn letter(self: *Band, font: *const [2]blit.Image, ch: u8, canvas_x: i32) void {
        self.letterOn(0, font, ch, canvas_x);
        self.letterOn(1, font, ch, canvas_x);
    }

    /// letter() into the halving of `parity` only.
    pub fn letterOn(self: *Band, parity: u1, font: *const [2]blit.Image, ch: u8, canvas_x: i32) void {
        const rect = A.glyph(ch, parity) orelse return;
        const x = @divFloor(canvas_x, 2);
        if (!self.transposed) return blit.blit(blit.Dst.buffer(self.strips[parity], self.w), font[parity], rect, x, 0, null, .copy);
        // The same copy, clipped the same way, into the strip stored by columns.
        const sheet = font[parity];
        for (0..rect.w) |c| {
            const col = x + @as(i32, @intCast(c));
            if (col < 0 or col >= @as(i32, @intCast(self.w))) continue;
            const out = self.strips[parity][@as(usize, @intCast(col)) * STRIP_ROWS ..][0..rect.h];
            for (out, 0..) |*o, k| o.* = sheet.data[(rect.y + k) * sheet.w + rect.x + c];
        }
    }

    /// Columns [c0, c1) of the merge canvas, the only ones `draw` will show: FX.siny
    /// the text into them with `sweep` (`next()`: the canvas y of each ST column in
    /// turn, from c0), recoloured by the gold backdrop, which sits in the raster
    /// canvas at goldY - 118, goldY, goldY + 118 (and repeats every 640 canvas
    /// columns: the intro draws it twice). `flip` stores the rows upside down, for a
    /// draw at scale -1. The columns outside are never read (the plane clips them),
    /// so they are left as they are.
    pub fn composeWave(self: *Band, sweep: anytype, gold: compose.GoldCols, gold_y: u32, c0: usize, c1: usize, flip: bool) void {
        if (!self.transposed) unreachable;
        self.rows = compose.wave(self.view(flip), sweep, gold, gold_y, c0, c1);
        self.flipped = flip;
    }

    /// composeWave with one canvas y for every column (siny of amplitude 0).
    pub fn composeFlat(self: *Band, y: i32, gold: blit.Image, gold_y: u32, c0: usize, c1: usize, flip: bool) void {
        if (self.transposed) unreachable;
        self.rows = compose.flat(self.view(flip), y, gold, gold_y, c0, c1);
        self.flipped = flip;
    }

    fn view(self: *const Band, flip: bool) compose.View {
        return .{ .w = self.w, .strips = self.strips, .merge = self.merge, .flip = flip };
    }

    /// mergecanvas.drawPart(main, x, y, 0, 0, w, 110, 1, 0, 1, scale) on a
    /// mid-handled canvas: left edge at `dx`, stretched about `centre_q16`.
    /// At a scale of +-1 that is one keyed copy of the rows holding text (the rows
    /// around them are 0, the key: they draw nothing). stretchY's exact walk puts
    /// source row q at y = q - floor(H/2 + 1/2 - c) for +1, and q = floor(H/2 - 1/2
    /// + c) - y for -1, where the canvas composed upside down (row j = row H-1-j)
    /// lands as a +1 copy at floor(H/2 - 1/2 + c) - H + 1.
    pub fn draw(self: *const Band, dst: blit.Dst, dx: i32, centre_q16: i32, scale: f64) void {
        const flip = scale == -1.0;
        if (self.flipped != flip) unreachable; // the caller composes with flip = (scale == -1)
        if (scale != 1.0 and !flip) return stretch.stretchY(dst, blit.Image.init(self.merge, self.w), dx, centre_q16, scale, 0, .copy);
        if (self.rows[1] <= self.rows[0]) return;
        const h: i32 = MERGE_ROWS;
        const dy: i32 = if (flip) ((h * 32768 - 32768 + centre_q16) >> 16) - h + 1 else -((h * 32768 + 32768 - centre_q16) >> 16);
        const part = blit.Rect{ .x = 0, .y = self.rows[0], .w = self.w, .h = self.rows[1] - self.rows[0] };
        blit.blit(dst, blit.Image.init(self.merge, self.w), part, dx, dy + @as(i32, @intCast(self.rows[0])), 0, .copy);
    }
};
