// --------------------------------------------------------------------------
// Clipped, signed-coordinate blits of 8-bit palette-index images.
//
// Every CODEF port used to carry its own blit: per-pixel bounds tests, u16
// coordinates, a hardcoded 320 width. `zg.Sprite` cannot stand in for them — it
// assumes a 320x200 target, keeps a u16 offset (a 400x280 plane is 112000
// bytes) and casts a negative y after its clamp. So this is the one blit:
//
//   - destination is a `Dst` VIEW: a plane of any mode (its real stride and
//     size), a scratch buffer, or a `window()` onto either, which is how a scene
//     clips to a hole in its artwork;
//   - coordinates are signed; the call clips ONCE, then the inner loops run
//     with no bounds tests;
//   - the ink mode is switched outside the pixel loop, so each mode gets its
//     own tight loop.
//
// No ZigOS import on purpose: `Dst.plane` duck-types the plane, which keeps this
// file testable natively (blit_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const rows = @import("blit_rows.zig");

/// Where pixels go. `stride` is the distance between rows in `buf`; `w`/`h` are
/// the drawable size, which for a window is smaller than the stride.
pub const Dst = struct {
    buf: []u8,
    stride: usize,
    w: usize,
    h: usize,

    pub const empty = Dst{ .buf = &.{}, .stride = 1, .w = 0, .h = 0 };

    /// A plane's whole buffer, in whatever mode it is in (320x200, 400x280,
    /// a scroll buffer): anything with `fb`, `stride`, `fb_w`, `fb_h`.
    pub fn plane(fb: anytype) Dst {
        const w: usize = fb.fb_w;
        const h: usize = fb.fb_h;
        const stride: usize = fb.stride;
        if (w == 0 or h == 0) return empty;
        return .{ .buf = fb.fb[0 .. (h - 1) * stride + w], .stride = stride, .w = w, .h = h };
    }

    /// A row-major scratch buffer `w` pixels wide; its height is whatever `buf`
    /// holds. A zero width is an empty destination.
    pub fn buffer(buf: []u8, w: usize) Dst {
        if (w == 0 or buf.len < w) return empty;
        return .{ .buf = buf, .stride = w, .w = w, .h = buf.len / w };
    }

    /// The w x h rectangle at (x, y), clipped to this view. Drawing into it is
    /// clipped to it, and its coordinates start at its own top-left.
    pub fn window(self: Dst, x: usize, y: usize, w: usize, h: usize) Dst {
        if (x >= self.w or y >= self.h) return empty;
        const cw = @min(w, self.w - x);
        const ch = @min(h, self.h - y);
        if (cw == 0 or ch == 0) return empty;
        return .{ .buf = self.buf[y * self.stride + x ..], .stride = self.stride, .w = cw, .h = ch };
    }

    /// Fill the w x h rectangle at signed (x, y) with `v`, clipped to the view:
    /// one @memset (word stores) a row, for the bands and boxes carts filled
    /// pixel by pixel through setPixelValue.
    pub fn fill(self: Dst, x: i32, y: i32, w: usize, h: usize, v: u8) void {
        const cx = axis(x, w, self.w) orelse return;
        const cy = axis(y, h, self.h) orelse return;
        for (cy.at..cy.at + cy.n) |r| @memset(self.buf[r * self.stride + cx.at ..][0..cx.n], v);
    }
};

/// A row-major palette-index image.
pub const Image = struct {
    data: []const u8,
    w: usize,
    h: usize,

    /// `data` is w pixels per row; a trailing partial row is ignored.
    pub fn init(data: []const u8, w: usize) Image {
        if (w == 0) return .{ .data = &.{}, .w = 0, .h = 0 };
        return .{ .data = data, .w = w, .h = data.len / w };
    }
};

/// A source sub-rectangle.
pub const Rect = struct { x: usize, y: usize, w: usize, h: usize };

/// A colouring image laid over the destination: destination pixel (x, y) takes
/// img's pixel (x - ox, y - oy). Pixels outside img are not drawn. This is
/// canvas 'source-atop': the source gives the SHAPE, the pattern the COLOUR.
pub const Pattern = struct { img: Image, ox: i32, oy: i32 };

/// Draw p only where `set[destination pixel] == inside`. With `set` = the
/// palette entries of a layer's opaque pixels, `inside = true` is canvas
/// 'source-atop' onto that layer and `inside = false` draws only around it.
pub const Select = struct { set: *const [256]bool, inside: bool };

/// What a drawn (non-key) source pixel `p` writes.
pub const Ink = union(enum) {
    copy, // p
    flat: u8, // one index (a font's ink)
    offset: u8, // p +% base (a sprite sheet shifted into a palette range)
    lut: *const [256]u8, // lut[p]
    row: []const u8, // row[destination y]; rows past its end are not drawn
    pattern: Pattern, // the pattern pixel under the destination
    select: Select, // p, where the destination is (or is not) in a palette set
};

/// The clipped job: `w` x `h` pixels from src (sx, sy) to dst (dx, dy).
const Span = struct { sx: usize, sy: usize, dx: usize, dy: usize, w: usize, h: usize };

/// Blit `part` of `src` (all of it when null) with its top-left at (dx, dy).
/// Source pixels equal to `key` are skipped. Off-screen, empty or fully
/// clipped calls draw nothing.
pub fn blit(dst: Dst, src: Image, part: ?Rect, dx: i32, dy: i32, key: ?u8, ink: Ink) void {
    var s = clip(dst, src, part, dx, dy) orelse return;
    switch (ink) {
        .row => |r| s.h = @min(s.h, if (r.len > s.dy) r.len - s.dy else 0),
        .pattern => |p| if (!clipToPattern(&s, p)) return,
        else => {},
    }
    if (s.w == 0 or s.h == 0) return;
    switch (ink) {
        inline else => |v, tag| if (key) |k| draw(dst, src, s, tag, v, true, k) else draw(dst, src, s, tag, v, false, 0),
    }
}

/// CODEF `image.draw(dst, x, y, alpha, 0, 1, sy)` on a mid-handled image: `src`
/// stretched vertically by `sy` about the row `centre_y`, left edge at `dx`.
/// A negative `sy` flips it; 0 draws nothing. Each destination row takes the
/// source row under its pixel centre (nearest, where the canvas interpolates).
pub fn stretchY(dst: Dst, src: Image, dx: i32, centre_y: f64, sy: f64, key: ?u8, ink: Ink) void {
    if (sy == 0 or src.h == 0 or dst.h == 0) return;
    const half: f64 = @as(f64, @floatFromInt(src.h)) / 2;
    const extent = half * @abs(sy);
    const top: usize = @intFromFloat(std.math.clamp(@floor(centre_y - extent), 0, @as(f64, @floatFromInt(dst.h))));
    const bottom: usize = @intFromFloat(std.math.clamp(@ceil(centre_y + extent), 0, @as(f64, @floatFromInt(dst.h))));
    for (top..bottom) |y| {
        const v = half + (@as(f64, @floatFromInt(y)) + 0.5 - centre_y) / sy;
        if (!(v >= 0 and v < @as(f64, @floatFromInt(src.h)))) continue;
        blit(dst, src, .{ .x = 0, .y = @intFromFloat(v), .w = src.w, .h = 1 }, dx, @intCast(y), key, ink);
    }
}

fn clip(dst: Dst, src: Image, part: ?Rect, dx: i32, dy: i32) ?Span {
    const p = part orelse Rect{ .x = 0, .y = 0, .w = src.w, .h = src.h };
    if (p.x >= src.w or p.y >= src.h) return null;
    const x = axis(dx, @min(p.w, src.w - p.x), dst.w) orelse return null;
    const y = axis(dy, @min(p.h, src.h - p.y), dst.h) orelse return null;
    return .{ .sx = p.x + x.skip, .sy = p.y + y.skip, .dx = x.at, .dy = y.at, .w = x.n, .h = y.n };
}

/// One axis of the clip: `len` source pixels placed at `d` on a destination of
/// `lim`. In unsigned 32-bit arithmetic (no i64, which rv32 does in pairs of
/// instructions), and nothing can wrap: `skip` is |d| only when d < 0.
fn axis(d: i32, len: usize, lim: usize) ?struct { skip: usize, at: usize, n: usize } {
    const skip: usize = if (d < 0) @abs(d) else 0;
    const at: usize = if (d < 0) 0 else @intCast(d);
    if (skip >= len or at >= lim) return null;
    return .{ .skip = skip, .at = at, .n = @min(len - skip, lim - at) };
}

/// Narrow the span to the destination pixels the pattern covers.
fn clipToPattern(s: *Span, p: Pattern) bool {
    const px0 = @max(@as(i64, @intCast(s.dx)), @as(i64, p.ox));
    const py0 = @max(@as(i64, @intCast(s.dy)), @as(i64, p.oy));
    const px1 = @min(@as(i64, @intCast(s.dx + s.w)), @as(i64, p.ox) + @as(i64, @intCast(p.img.w)));
    const py1 = @min(@as(i64, @intCast(s.dy + s.h)), @as(i64, p.oy) + @as(i64, @intCast(p.img.h)));
    if (px1 <= px0 or py1 <= py0) return false;
    const ddx: usize = @intCast(px0 - @as(i64, @intCast(s.dx)));
    const ddy: usize = @intCast(py0 - @as(i64, @intCast(s.dy)));
    s.* = .{
        .sx = s.sx + ddx,
        .sy = s.sy + ddy,
        .dx = s.dx + ddx,
        .dy = s.dy + ddy,
        .w = @intCast(px1 - px0),
        .h = @intCast(py1 - py0),
    };
    return true;
}

fn draw(dst: Dst, src: Image, s: Span, comptime tag: std.meta.Tag(Ink), v: anytype, comptime keyed: bool, key: u8) void {
    for (0..s.h) |r| {
        const y = s.dy + r;
        const out = dst.buf[y * dst.stride + s.dx ..][0..s.w];
        const in = src.data[(s.sy + r) * src.w + s.sx ..][0..s.w];
        switch (tag) {
            .copy => if (keyed) rows.row(out, in, key, rows.keyedCopy, false) else @memcpy(out, in),
            .row => rows.row(out, in, rows.Inked(u8, keyed){ .key = key, .v = v[y] }, rows.Inked(u8, keyed).flat, false),
            .pattern => {
                const py: usize = @intCast(@as(i64, @intCast(y)) - v.oy);
                const px: usize = @intCast(@as(i64, @intCast(s.dx)) - v.ox);
                const pat = v.img.data[py * v.img.w + px ..][0..s.w];
                rows.row(out, in, rows.Inked([]const u8, keyed){ .key = key, .v = pat }, rows.Inked([]const u8, keyed).pattern, false);
            },
            .select => rows.row(out, in, rows.Inked(Select, keyed){ .key = key, .v = v }, rows.Inked(Select, keyed).select, true),
            else => rows.row(out, in, rows.Inked(@TypeOf(v), keyed){ .key = key, .v = v }, @field(rows.Inked(@TypeOf(v), keyed), @tagName(tag)), false),
        }
    }
}
