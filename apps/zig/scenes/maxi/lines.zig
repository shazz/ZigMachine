// MAXI's lines, drawn straight into the overscan plane, and taken back off it.
//
// The screen is a static text page under three spinning wireframes. It used to
// rebuild the whole 320x280 picture every frame (copy the text page into a
// buffer, draw the lines, copy the buffer into the plane): 180 KB of stores a
// frame for ~1,500 changed pixels. Now the text page goes into the plane once,
// and each frame only the pixels that change are written, as an ST coder would:
// last frame's lines are restored from the text page, then this frame's are
// drawn. Same pixels: `walk` is shapes.drawLine's Bresenham step for step (the
// same octants, the same i16 sums, the same plot order) and the same clip, the
// 320x280 window that the buffer was, at x+40 in the 400-wide plane.
const shapes = @import("zigos").shapes;
const Coord = shapes.Coord;

pub const W: u16 = 320; // the drawn window, as the old 320x280 buffer
pub const H: u16 = 280;

pub const Plane = struct {
    px: [*]u8, // the plane's pixels at the window's top-left (fb + border)
    stride: usize, // the plane's row length
    page: [*]const u8, // the text page, W x H: what is under every line

    // shapes.drawLine casts a coordinate to u16 and clips it against the
    // buffer, so a negative one wraps to a large one and is dropped too.
    inline fn at(x: i16, y: i16) ?[2]usize {
        const ux: u16 = @bitCast(x);
        const uy: u16 = @bitCast(y);
        if (ux >= W or uy >= H) return null;
        return .{ ux, uy };
    }

    pub fn plot(self: Plane, x: i16, y: i16, color: u8) void {
        const p = at(x, y) orelse return;
        self.px[p[1] * self.stride + p[0]] = color;
    }

    // `color` unused: what goes back is the text page's pixel.
    pub fn restore(self: Plane, x: i16, y: i16, color: u8) void {
        _ = color;
        const p = at(x, y) orelse return;
        self.px[p[1] * self.stride + p[0]] = self.page[p[1] * W + p[0]];
    }
};

/// shapes.drawLine's walk with `plot(ctx, x, y, color)` for its pixel store.
pub fn walk(ctx: anytype, src: Coord, dest: Coord, color: u8, comptime plot: anytype) void {
    const c0 = if (dest.y < src.y) dest else src;
    const c1 = if (dest.y < src.y) src else dest;
    const step: i16 = if (c1.x >= c0.x) 1 else -1;
    const dx: i16 = if (c1.x >= c0.x) c1.x - c0.x else c0.x - c1.x;
    const dy: i16 = c1.y - c0.y;
    var x = c0.x;
    var y = c0.y;
    plot(ctx, x, y, color);
    if (dx >= dy) {
        var dp: i16 = 2 * dy - dx;
        while (x != c1.x) {
            if (dp <= 0) dp += 2 * dy else {
                dp += 2 * (dy - dx);
                y += 1;
            }
            x += step;
            plot(ctx, x, y, color);
        }
    } else {
        var dp: i16 = 2 * dx - dy;
        while (y < c1.y) {
            if (dp <= 0) dp += 2 * dx else {
                dp += 2 * (dx - dy);
                x += step;
            }
            y += 1;
            plot(ctx, x, y, color);
        }
    }
}

/// Every edge of one object, drawn (`Plane.plot`) or taken back (`Plane.restore`).
pub fn edges(p: Plane, list: []const [2]u16, pts: []const Coord, color: u8, comptime op: anytype) void {
    for (list) |e| walk(p, pts[e[0]], pts[e[1]], color, op);
}
