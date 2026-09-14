// --------------------------------------------------------------------------
// LEVEL 16's vertical scroller: CODEF scrolltext_vertical (codef_scrolltext.js:
// 177-298) as screen.js:28-31 sets it up, the Union Demo's main scrolltext moving
// up 1.8 canvas px a frame in the 32 px column at canvas x 736. It shows through
// the picture's pipe-shaped hole.
//
// At 1.8 px a frame every letter sits at a fractional y, and Chrome resamples its
// rows (chrome_draw.zig). One frame's column holds at most 141 distinct blends
// (the whole 287,120-frame text cycle, checked against the Chrome model), so
// they are the bottom plane's entries from SCROLL_FIRST up, handed out per frame
// by a colour bank.
//
// Letters are drawn in ring order, not sorted by y as draw() does: their snapped
// rectangles never overlap or leave a gap over the whole cycle, so the order
// changes no pixel.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const cd = zg.chrome_draw;
const A = @import("assets.zig");

/// jsApp.scrolltext (main.js:50), the hub's text, byte for byte: the hub's note
/// offsets index it. The hub packs its copy as the last 16,128 bytes of
/// union_demo/menu_assets.bin; union_l16_headless.mjs checks the two are identical.
pub const TEXT = @embedFile("../../assets/screens/union_l16/scrolltext.txt");

pub const COLUMN_X = 736; // scrolltext.draw(736)
pub const COLUMN_W = 32;
const FIRST_CHAR = 32; // font.initTile(32,32,32)
const GLYPH: f64 = 32;
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
    bank: zg.colour_bank.ColourBank,
    lost: u32, // pixels drawn black because the bank ran out (never, per the scan)

    /// scrolltext.init(..., jsApp.mainscrollerPos): `offset` is the hub scroller's
    /// next character (0 when the hub left no note, or one past the text).
    pub fn init(self: *Scroller, first_entry: u8, offset: usize) void {
        self.next = if (offset < TEXT.len) offset else 0;
        for (&self.posy, &self.ltr, 0..) |*y, *c, i| {
            y.* = @ceil(WIDE + @as(f64, @floatFromInt(i)) * GLYPH);
            // init() does not wrap: charCodeAt past the end would be NaN, so wrap here
            c.* = TEXT[self.next];
            self.next = (self.next + 1) % TEXT.len;
        }
        self.bank.init(first_entry);
        self.lost = 0;
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

    /// Paint the column (plane columns planeX(736)..+16) and its palette entries.
    pub fn draw(self: *Scroller, column: blit.Dst, font: []const u8, palette: [*]u32, black: u8) void {
        self.bank.begin();
        // row by row: the window's buffer runs on past its 16 columns to the plane's edge
        for (0..column.h) |y| @memset(column.buf[y * column.stride ..][0..column.w], black);
        for (self.posy, self.ltr) |posy, ltr| {
            const g: usize = ltr - FIRST_CHAR;
            const sx = g % SHEET_COLS * (A.FONT_W / SHEET_COLS);
            const sy = g / SHEET_COLS * @as(usize, @intFromFloat(GLYPH));
            const rows = planeRows(posy, column.h);
            for (rows.start..rows.end) |y| {
                const t = cd.partTaps(posy, @intCast(sy), @intFromFloat(GLYPH), A.FONT_H, A.canvasRow(y)) orelse continue;
                const row_a = font[@as(usize, t.top) * A.FONT_W + sx ..][0..column.w];
                const row_b = font[@as(usize, t.bottom) * A.FONT_W + sx ..][0..column.w];
                const out = column.buf[y * column.stride ..][0..column.w];
                for (row_a, row_b, out) |ia, ib, *d| {
                    const rgb = cd.mixRgb(A.fontInk(ia), A.fontInk(ib), t.w);
                    d.* = self.bank.entry(palette, rgb) orelse blk: {
                        self.lost += 1;
                        break :blk black;
                    };
                }
            }
        }
    }
};

/// The plane rows whose canvas rows a letter's 32 drawn rows may cover: from
/// round(y), y as Chrome's float32 (chrome_draw.partTaps).
fn planeRows(posy: f64, h: usize) Range {
    const fy: f64 = @as(f32, @floatCast(posy));
    const top = @floor(fy + 0.5) - A.CROP_Y;
    const first = @max(0, @ceil(top / 2));
    const last = @min(@as(f64, @floatFromInt(h)), @ceil((top + GLYPH) / 2));
    if (last <= first) return .{ .start = 0, .end = 0 };
    return .{ .start = @intFromFloat(first), .end = @intFromFloat(last) };
}

const Range = struct { start: usize, end: usize };
