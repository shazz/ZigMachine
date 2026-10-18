// --------------------------------------------------------------------------
// ZigOS's system-font text (printText / printTextClipped / printTextSmall),
// drawn one SCREEN ROW at a time.
//
// The glyphs of a string sit side by side, so on each screen row the string
// covers one contiguous span of the framebuffer. The old blitGlyphs walked it
// glyph by glyph and pixel by pixel, testing four clip edges and storing a
// byte per pixel (a blocking bus write each on the board). Here each row's span
// is clipped once and written through blit_rows.gen, one store per aligned
// word; the pick walks the glyphs along the row. Every pixel of the span gets
// ink or paper, exactly as before (glyph_line_test.zig holds it to the old loop).
//
// No ZigOS import, so it tests natively; zigos.zig's blitGlyphs calls it.
// --------------------------------------------------------------------------
const rows = @import("blit_rows.zig");

pub const Target = struct { fb: [*]u8, stride: usize, w: i32, h: i32 };
pub const Clip = struct { x0: i32, y0: i32, x1: i32, y1: i32 };

/// Glyph N of an fw x fh font is fw*fh bytes at N*fw*fh, 1 = ink. Draw `text`
/// with its top-left at (x, y), clipped to `clip` and to the target.
pub fn draw(t: Target, text: []const u8, x: i32, y: i32, ink: u8, paper: u8, font: []const u8, fw: i32, fh: i32, clip: Clip) void {
    if (fw <= 0 or fh <= 0 or text.len == 0) return;
    const w = @min(t.w, clip.x1);
    const h = @min(t.h, clip.y1);
    const a = @max(@max(0, clip.x0), x); // first column drawn
    const b = @min(w, x + @as(i32, @intCast(text.len)) * fw); // one past the last
    if (b <= a) return;
    const first: usize = @intCast(@divTrunc(a - x, fw)); // the glyph under column a
    const col0: usize = @intCast(@rem(a - x, fw));
    const n: usize = @intCast(b - a);
    const ufw: usize = @intCast(fw);
    const cell: usize = ufw * @as(usize, @intCast(fh));
    var r: i32 = @max(0, @max(0, clip.y0) - y);
    while (r < fh and y + r < h) : (r += 1) {
        const ur: usize = @intCast(r);
        var walk = Walk{ .text = text.ptr, .len = text.len, .font = font.ptr, .k = first, .c = col0, .fw = ufw, .cell = cell, .row_off = ur * ufw, .ink = ink, .paper = paper };
        walk.glyph = walk.base();
        const out = t.fb[@as(usize, @intCast(y + r)) * t.stride + @as(usize, @intCast(a)) ..][0..n];
        rows.gen(out, &walk, Walk.pick);
    }
}

// Where the row's pick is: glyph k of the text, column c of it.
const Walk = struct {
    text: [*]const u8,
    len: usize,
    font: [*]const u8,
    k: usize,
    c: usize,
    fw: usize,
    cell: usize,
    row_off: usize,
    glyph: [*]const u8 = undefined,
    ink: u8,
    paper: u8,

    inline fn base(wk: *const Walk) [*]const u8 {
        return wk.font + @as(usize, wk.text[wk.k]) * wk.cell + wk.row_off;
    }

    inline fn pick(wk: *Walk, _: u8, _: u8, _: usize) rows.Px {
        const on = wk.glyph[wk.c] == 1;
        wk.c += 1;
        if (wk.c == wk.fw) {
            wk.c = 0;
            wk.k += 1;
            if (wk.k < wk.len) wk.glyph = wk.base(); // not past the string's end
        }
        return rows.put(if (on) wk.ink else wk.paper);
    }
};
