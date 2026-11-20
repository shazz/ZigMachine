//! The NFO viewer's drawing: CP437 text split into 80-column lines, one pixel ROW at a time
//! (640 palette indices), and the prompt bar. Row-wise so the scroller can repaint the one row
//! the bar uncovers; paint-once-then-pan needs nothing else. Integers only, no allocation.
const glyph = @import("nfo_glyph.zig");

pub const cols: usize = 80;
pub const row_px: usize = cols * glyph.cell_w; // 640, the desk's stride
pub const max_lines: usize = 160;
pub const bar_h: u32 = 18;

pub const Error = error{ TooManyLines, PromptTooLong };

/// The text as lines of up to `cols` bytes (longer lines are cut at the 80th column, as the
/// viewers do). A final newline does not start an empty line; 0x1A (DOS end-of-file) ends the text.
pub const Text = struct {
    bytes: []const u8,
    starts: [max_lines]u32 = undefined,
    lens: [max_lines]u8 = undefined,
    n: u32 = 0,

    pub fn parse(bytes: []const u8) Error!Text {
        var t = Text{ .bytes = bytes };
        var i: usize = 0;
        while (i < bytes.len and bytes[i] != 0x1A) {
            var j = i;
            while (j < bytes.len and bytes[j] != '\n' and bytes[j] != 0x1A) j += 1;
            if (t.n == max_lines) return error.TooManyLines;
            var end = j;
            if (end > i and bytes[end - 1] == '\r') end -= 1;
            t.starts[t.n] = @intCast(i);
            t.lens[t.n] = @intCast(@min(end - i, cols));
            t.n += 1;
            i = if (j < bytes.len and bytes[j] == 0x1A) bytes.len else j + 1;
        }
        return t;
    }

    pub fn line(self: *const Text, r: u32) []const u8 {
        if (r >= self.n) return "";
        return self.bytes[self.starts[r]..][0..self.lens[r]];
    }

    /// Pixel height of the text: 9 rows a line.
    pub fn height(self: *const Text) u32 {
        return self.n * glyph.cell_h;
    }
};

fn at(l: []const u8, c: usize) u8 {
    return if (c < l.len) l[c] else 0x20;
}

/// Pixel row `y` of the text area into `out` (640 bytes): each ink pixel, and where a pixel
/// has none, the viewer's drop shadow if the ink pixel up and to the left of it has some.
pub fn renderRow(t: *const Text, y: u32, out: []u8) void {
    const ly = y % glyph.cell_h;
    const cur = t.line(y / glyph.cell_h);
    const up = if (y == 0) "" else t.line((y - 1) / glyph.cell_h);
    const uly = if (y == 0) 0 else (y - 1) % glyph.cell_h;
    for (0..cols) |c| {
        const dst = out[c * glyph.cell_w ..][0..glyph.cell_w];
        const ch = at(cur, c);
        const quiet = !glyph.bleeds(at(up, c)) and (c == 0 or !glyph.bleeds(at(up, c - 1)));
        if (glyph.blank(ch) and quiet) {
            @memset(dst, glyph.bg);
            continue;
        }
        for (0..glyph.cell_w) |x| dst[x] = pixelAt(ch, up, c, @intCast(x), .{ .y = y, .ly = ly, .uly = uly });
    }
}

const Rows = struct { y: u32, ly: u32, uly: u32 };

fn pixelAt(ch: u8, up: []const u8, c: usize, x: u32, r: Rows) u8 {
    const own = glyph.pix(ch, x, r.ly, r.y & 1);
    if (own != 0 or r.y == 0) return own;
    const src = if (x > 0) at(up, c) else if (c > 0) at(up, c - 1) else 0x20;
    return if (glyph.pix(src, (x + 7) & 7, r.uly, (r.y - 1) & 1) != 0) glyph.shadow else glyph.bg;
}

/// The prompt bar (bar_h rows of 640): a light rule on top, the text centred with the same
/// shadow as the page. Longer than the 80 columns is an error, not a clip.
pub fn buildBar(prompt: []const u8, bar: *[bar_h * row_px]u8) Error!void {
    if (prompt.len > cols) return error.PromptTooLong;
    @memset(bar, glyph.bar_bg);
    @memset(bar[0..row_px], glyph.bar_line);
    const x0 = (row_px - prompt.len * glyph.cell_w) / 2;
    for ([2]u8{ glyph.bar_shadow, glyph.white }) |colour| {
        const d: usize = if (colour == glyph.white) 0 else 1;
        for (prompt, 0..) |ch, i| inkChar(bar, ch, x0 + i * glyph.cell_w + d, 5 + d, colour);
    }
}

fn inkChar(bar: *[bar_h * row_px]u8, ch: u8, x0: usize, y0: usize, colour: u8) void {
    for (0..8) |ly| for (0..8) |x| {
        if (glyph.pix(ch, @intCast(x), @intCast(ly), 0) != 0) bar[(y0 + ly) * row_px + x0 + x] = colour;
    };
}
