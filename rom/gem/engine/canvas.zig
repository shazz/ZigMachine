// --------------------------------------------------------------------------
// GEM 5 engine: the raster the object renderer paints into. One byte a pixel
// (the desk's 8 bpp plane), a stride, and a CLIP that every primitive honours:
// the dirty-rectangle compositor (compose.zig) sets the clip to one exposed
// rectangle at a time and replays the tree, so nothing outside it may change.
//
// Fills: a box of at least BLIT_MIN pixels goes to `fill_fn` when one is set
// (the ROM hands blit.Dst's CHISEL fill: a blit costs ~800 cycles of fixed cost
// on the board, so a small box is cheaper as word stores); everything else is
// a @memset a row. No copies: a copy within one plane is the board's slow path.
// --------------------------------------------------------------------------
const std = @import("std");
const rect = @import("rect.zig");
const Rect = rect.Rect;

/// A 1 bpp font: 256 glyphs of w x h. `packed_rows`: rows of (w+7)/8 bytes, MSB
/// first (the converter's output); else one byte a pixel (ZigOS's raw fonts).
pub const Font = struct {
    w: u8,
    h: u8,
    data: []const u8,
    packed_rows: bool = true,

    pub fn ink(self: *const Font, c: u8, row: usize, col: usize) bool {
        const w: usize = self.w;
        const h: usize = self.h;
        if (!self.packed_rows) {
            const i = @as(usize, c) * w * h + row * w + col;
            return i < self.data.len and self.data[i] != 0;
        }
        const bpr = (w + 7) / 8;
        const i = (@as(usize, c) * h + row) * bpr + col / 8;
        return i < self.data.len and (self.data[i] >> @intCast(7 - col % 8)) & 1 != 0;
    }
};

pub const FillFn = *const fn (ctx: *anyopaque, at: [*]u8, stride: u32, w: u32, h: u32, v: u8) void;
pub const BLIT_MIN: u32 = 4096;

pub const Canvas = struct {
    pix: [*]u8,
    stride: u32,
    w: i16,
    h: i16,
    clip: Rect,
    fill_fn: ?FillFn = null,
    fill_ctx: *anyopaque = undefined,
    written: u32 = 0, // pixels written since the counter was zeroed (the harness's cost measure)

    pub fn init(pix: [*]u8, stride: u32, w: i16, h: i16) Canvas {
        return .{ .pix = pix, .stride = stride, .w = w, .h = h, .clip = .{ .w = w, .h = h } };
    }

    /// Clip to `r` inside the canvas.
    pub fn setClip(self: *Canvas, r: Rect) void {
        self.clip = rect.intersect(r, .{ .w = self.w, .h = self.h });
    }

    pub fn fill(self: *Canvas, r: Rect, v: u8) void {
        const c = rect.intersect(r, self.clip);
        if (c.empty()) return;
        const w: u32 = @intCast(c.w);
        const h: u32 = @intCast(c.h);
        const at = self.pix + @as(usize, @intCast(c.y)) * self.stride + @as(usize, @intCast(c.x));
        self.written += w * h;
        if (self.fill_fn) |f| if (w * h >= BLIT_MIN) return f(self.fill_ctx, at, self.stride, w, h, v);
        var row: u32 = 0;
        while (row < h) : (row += 1) @memset(at[row * self.stride ..][0..w], v);
    }

    pub fn plot(self: *Canvas, x: i32, y: i32, v: u8) void {
        if (!self.clip.contains(x, y)) return;
        self.pix[@as(usize, @intCast(y)) * self.stride + @as(usize, @intCast(x))] = v;
        self.written += 1;
    }

    /// A frame of `t` pixels: t > 0 inside `r`, t < 0 outside it (GEM's thickness).
    pub fn frame(self: *Canvas, r: Rect, t: i8, v: u8) void {
        if (t == 0) return;
        const n: i16 = if (t > 0) t else -@as(i16, t);
        const o = if (t > 0) r else r.grow(n);
        self.fill(.{ .x = o.x, .y = o.y, .w = o.w, .h = n }, v);
        self.fill(.{ .x = o.x, .y = o.y + o.h - n, .w = o.w, .h = n }, v);
        self.fill(.{ .x = o.x, .y = o.y + n, .w = n, .h = o.h - 2 * n }, v);
        self.fill(.{ .x = o.x + o.w - n, .y = o.y + n, .w = n, .h = o.h - 2 * n }, v);
    }

    /// A 16x16 pattern (bit set: `fg`, clear: `bg`, or left alone when bg is null),
    /// aligned to the screen as a VDI pattern fill is.
    pub fn pattern(self: *Canvas, r: Rect, pat: *const [16]u16, fg: u8, bg: ?u8) void {
        const c = rect.intersect(r, self.clip);
        if (c.empty()) return;
        var y: i32 = c.y;
        while (y < c.bottom()) : (y += 1) {
            const row_bits = pat[@intCast(@mod(y, 16))];
            const row = self.pix + @as(usize, @intCast(y)) * self.stride;
            var x: i32 = c.x;
            while (x < c.right()) : (x += 1) {
                const on = (row_bits >> @intCast(15 - @mod(x, 16))) & 1 != 0;
                if (on) row[@intCast(x)] = fg else if (bg) |b| row[@intCast(x)] = b;
            }
        }
        self.written += @as(u32, @intCast(c.w)) * @as(u32, @intCast(c.h));
    }

    /// Text in `font` from (x, y): ink where the glyph is set, `paper` (or nothing) elsewhere.
    pub fn text(self: *Canvas, font: *const Font, s: []const u8, x: i32, y: i32, ink: u8, paper: ?u8) void {
        const fw: i32 = font.w;
        if (y >= self.clip.bottom() or y + font.h <= self.clip.y) return;
        for (s, 0..) |ch, i| {
            const gx = x + @as(i32, @intCast(i)) * fw;
            if (gx >= self.clip.right()) return;
            if (gx + fw <= self.clip.x) continue;
            self.glyph(font, ch, gx, y, ink, paper);
        }
    }

    fn glyph(self: *Canvas, font: *const Font, ch: u8, x: i32, y: i32, ink: u8, paper: ?u8) void {
        var row: usize = 0;
        while (row < font.h) : (row += 1) {
            const yy = y + @as(i32, @intCast(row));
            if (yy < self.clip.y or yy >= self.clip.bottom()) continue;
            const line = self.pix + @as(usize, @intCast(yy)) * self.stride;
            var col: usize = 0;
            while (col < font.w) : (col += 1) {
                const xx = x + @as(i32, @intCast(col));
                if (xx < self.clip.x or xx >= self.clip.right()) continue;
                if (font.ink(ch, row, col)) line[@intCast(xx)] = ink else if (paper) |p| line[@intCast(xx)] = p;
            }
        }
        self.written += @as(u32, font.w) * font.h;
    }

    /// A 1 bpp image (rows of `bpr` bytes, MSB first): set bits in `ink`, clear ones in
    /// `paper` (or left alone).
    pub fn bits(self: *Canvas, data: []const u8, bpr: usize, w: i16, h: i16, x: i32, y: i32, ink: ?u8, paper: ?u8) void {
        const box = rect.intersect(.{ .x = @intCast(x), .y = @intCast(y), .w = w, .h = h }, self.clip);
        if (box.empty()) return;
        var yy: i32 = box.y;
        while (yy < box.bottom()) : (yy += 1) {
            const r: usize = @intCast(yy - y);
            const line = self.pix + @as(usize, @intCast(yy)) * self.stride;
            var xx: i32 = box.x;
            while (xx < box.right()) : (xx += 1) {
                const c: usize = @intCast(xx - x);
                const i = r * bpr + c / 8;
                const on = i < data.len and (data[i] >> @intCast(7 - c % 8)) & 1 != 0;
                if (on) {
                    if (ink) |v| line[@intCast(xx)] = v;
                } else if (paper) |v| line[@intCast(xx)] = v;
            }
        }
        self.written += @as(u32, @intCast(box.w)) * @as(u32, @intCast(box.h));
    }

    /// A chunky image (one palette index a pixel, `w` a row) drawn where `mask` is set.
    pub fn chunky(self: *Canvas, col: []const u8, mask: []const u8, bpr: usize, w: i16, h: i16, x: i32, y: i32) void {
        const box = rect.intersect(.{ .x = @intCast(x), .y = @intCast(y), .w = w, .h = h }, self.clip);
        if (box.empty()) return;
        var yy: i32 = box.y;
        while (yy < box.bottom()) : (yy += 1) {
            const r: usize = @intCast(yy - y);
            const line = self.pix + @as(usize, @intCast(yy)) * self.stride;
            var xx: i32 = box.x;
            while (xx < box.right()) : (xx += 1) {
                const c: usize = @intCast(xx - x);
                const m = r * bpr + c / 8;
                const p = r * @as(usize, @intCast(w)) + c;
                if (m < mask.len and p < col.len and (mask[m] >> @intCast(7 - c % 8)) & 1 != 0) line[@intCast(xx)] = col[p];
            }
        }
        self.written += @as(u32, @intCast(box.w)) * @as(u32, @intCast(box.h));
    }

    /// GEM's dotted outline (every other pixel), the shape of every pending gesture.
    pub fn dotted(self: *Canvas, r: Rect, v: u8) void {
        var x: i32 = r.x;
        while (x < r.right()) : (x += 2) {
            self.plot(x, r.y, v);
            self.plot(x, r.bottom() - 1, v);
        }
        var y: i32 = r.y;
        while (y < r.bottom()) : (y += 2) {
            self.plot(r.x, y, v);
            self.plot(r.right() - 1, y, v);
        }
    }
};
