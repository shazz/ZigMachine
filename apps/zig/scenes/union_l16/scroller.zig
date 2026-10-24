// --------------------------------------------------------------------------
// LEVEL 16's vertical scroller: CODEF scrolltext_vertical (codef_scrolltext.js:
// 177-298) as screen.js:28-31 sets it up, the Union Demo's main scrolltext moving
// up 1.8 canvas px a frame in the 32 px column at canvas x 736. It shows through
// the picture's pipe-shaped hole.
//
// At 1.8 px a frame every letter sits at a fractional y, and Chrome resamples its
// rows (chrome_draw.zig). A frame's column shows up to 140 distinct blends, too
// many beside the picture's 174 colours, but a ROW of it at most 16: each row
// gets its own entries, which the plane's HBL loads (lines.zig). A row's blends
// are told apart by their two font inks (the row's weight is the same for all),
// and only the column's pixels the picture leaves see-through are drawn.
//
// Letters are drawn in ring order, not sorted by y as draw() does: their snapped
// rectangles never overlap or leave a gap over the whole cycle, so the order
// changes no pixel (and a row drawn twice is handed out afresh the second time).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const cd = zg.chrome_draw;
const A = @import("assets.zig");
const L = @import("lines.zig");

/// font.png's inks packed 0x00BBGGRR (index 0 is clear, black once premultiplied).
const INKS = blk: {
    var out: [16]u32 = undefined;
    for (&out, 0..) |*c, i| {
        const k = A.fontInk(i);
        c.* = @as(u32, k[0]) | @as(u32, k[1]) << 8 | @as(u32, k[2]) << 16;
    }
    break :blk out;
};

// The row being drawn: ink pair (a << 4 | b) -> its entry, valid where stamp == row_gen.
var pair_entry: [256]u8 = undefined;
var pair_stamp = [_]u32{0} ** 256;
var row_gen: u32 = 0;

/// jsApp.scrolltext (main.js:50), the hub's text, byte for byte: the hub's note
/// offsets index it. The hub packs its copy as the last 16,128 bytes of
/// union_demo/menu_assets.bin; union_l16_headless.mjs checks the two are identical.
pub const TEXT = @embedFile("../../assets/screens/union_l16/scrolltext.txt");

pub const COLUMN_X = 736; // scrolltext.draw(736)
pub const COLUMN_W = 32;
const FIRST_CHAR = 32; // font.initTile(32,32,32)
const GLYPH: f64 = 32;
const GLYPH_ROWS = 32; // the same, as integer rows
const SHEET_COLS = 16; // 512 / 32
const LETTERS = 20; // wide = ceil(572/32)+1 = 19, letters 0..wide
const WIDE: f64 = 19 * 32;
const SPEED: f64 = 1.8; // scrolltext.init(offscreencanvas, font, 1.8, ...)

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| {
        if (c < FIRST_CHAR or c >= FIRST_CHAR + SHEET_COLS * 4) @compileError("scrolltext character outside font.png");
        if (c == '^') @compileError("scrolltext control codes (^P, ^S) are not ported");
    }
}

pub const Scroller = struct {
    posy: [LETTERS]f64,
    ltr: [LETTERS]u8,
    next: usize, // scroffset
    frame: u32, // draw() calls: a row whose `drawn` is not this got no letter
    drawn: [A.H]u32,

    /// scrolltext.init(..., jsApp.mainscrollerPos): `offset` is the hub scroller's
    /// next character (0 when the hub left no note, or one past the text).
    pub fn init(self: *Scroller, offset: usize) void {
        self.next = if (offset < TEXT.len) offset else 0;
        for (&self.posy, &self.ltr, 0..) |*y, *c, i| {
            y.* = @ceil(WIDE + @as(f64, @floatFromInt(i)) * GLYPH);
            // init() does not wrap: charCodeAt past the end would be NaN, so wrap here
            c.* = TEXT[self.next];
            self.next = (self.next + 1) % TEXT.len;
        }
        self.frame = 0;
        @memset(&self.drawn, 0);
    }

    /// The move at the top of draw().
    pub fn update(self: *Scroller) void {
        for (&self.posy, &self.ltr) |*y, *c| {
            y.* -= SPEED;
            if (y.* <= -GLYPH) {
                y.* = WIDE + (y.* + GLYPH);
                c.* = TEXT[self.next];
                self.next += 1;
                if (self.next > TEXT.len - 1) self.next = 0;
            }
        }
    }

    /// Paint the column's see-through pixels (`holes`, lines.compose) in the
    /// plane window `column` (plane columns planeX(736)..+16), and each row's
    /// entries into `rows`.
    pub fn draw(self: *Scroller, column: zg.blit.Dst, font: []const u8, holes: *const [A.H]u16, rows: *L.RowPalettes) void {
        self.frame +%= 1;
        for (self.posy, self.ltr) |posy, ltr| {
            const g: usize = ltr - FIRST_CHAR;
            const sx = g % SHEET_COLS * (A.FONT_W / SHEET_COLS);
            const sy = g / SHEET_COLS * GLYPH_ROWS;
            const fy = cd.fyOf(posy);
            const span = planeRows(fy, A.H);
            for (span.start..span.end) |y| {
                if (holes[y] == 0) continue;
                const t = cd.partTapsFy(fy, @intCast(sy), GLYPH_ROWS, A.FONT_H, A.canvasRow(y)) orelse continue;
                self.drawn[y] = self.frame;
                const a = font[@as(usize, t.top) * A.FONT_W + sx ..][0..L.SLOTS];
                const b = font[@as(usize, t.bottom) * A.FONT_W + sx ..][0..L.SLOTS];
                drawRow(column.buf[y * column.stride ..][0..L.SLOTS], a, b, holes[y], t.w, rows, y);
            }
        }
        // A see-through row no letter reached shows the column's black.
        for (holes, self.drawn, 0..) |mask, d, y| if (mask != 0 and d != self.frame) {
            rows.used[y] = 0;
            var m = mask;
            while (m != 0) : (m &= m - 1) column.buf[y * column.stride + @ctz(m)] = L.BLACK;
        };
    }
};

/// One row of the column: each see-through pixel takes its ink pair's entry; the
/// pair's first pixel writes the blend (cd.mixRgb's, packed) into the row's palette.
fn drawRow(out: *[L.SLOTS]u8, a: *const [L.SLOTS]u8, b: *const [L.SLOTS]u8, mask: u16, w: u8, rows: *L.RowPalettes, y: usize) void {
    row_gen +%= 1;
    if (row_gen == 0) { // stamps wrapped: clear them once
        @memset(&pair_stamp, 0);
        row_gen = 1;
    }
    var used: u8 = 0;
    var m = mask;
    while (m != 0) : (m &= m - 1) {
        const c = @ctz(m);
        const ia = a[c] & 15; // font.png has 15 inks
        const ib = b[c] & 15;
        const pair = ia << 4 | ib;
        if (pair_stamp[pair] != row_gen) {
            pair_stamp[pair] = row_gen;
            pair_entry[pair] = L.SCROLL_FIRST + used;
            rows.colours[y][used] = 0xFF00_0000 | L.mixPacked(INKS[ia], INKS[ib], w);
            used += 1; // at most one per see-through pixel: never past SLOTS
        }
        out[c] = pair_entry[pair];
    }
    rows.used[y] = used;
}

/// The plane rows whose canvas rows a letter's 32 drawn rows may cover: from
/// round(y), y as Chrome's float32 in Q32 (chrome_draw.fyOf), all in integers.
fn planeRows(fy: cd.Fy, h: usize) Range {
    const top: i64 = ((fy + (1 << 31)) >> 32) - A.CROP_Y; // floor(y + 0.5) - CROP_Y
    const first = @max(0, (top + 1) >> 1); // ceil(top / 2)
    const last = @min(@as(i64, @intCast(h)), (top + GLYPH_ROWS + 1) >> 1); // ceil((top + 32) / 2)
    if (last <= first) return .{ .start = 0, .end = 0 };
    return .{ .start = @intCast(first), .end = @intCast(last) };
}

const Range = struct { start: usize, end: usize };
