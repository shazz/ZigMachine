// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const LogicalFB = @import("../zigos.zig").LogicalFB;
const RenderTarget = @import("../zigos.zig").RenderTarget;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("../zigos.zig").HEIGHT;
const WIDTH: usize = @import("../zigos.zig").WIDTH;

pub const Coord = struct {
    x: i16 = undefined,
    y: i16 = undefined,
};

pub const Span = struct {
    x1: i16 = undefined,
    x2: i16 = undefined,
    c1: u8 = undefined,
    c2: u8 = undefined,

    fn init(x1: i16, c1: u8, x2: i16, c2: u8) Span {
        if (x1 < x2) {
            return Span{ .x1 = x1, .c1 = c1, .x2 = x2, .c2 = c2 };
        } else {
            return Span{ .x1 = x2, .c1 = c2, .x2 = x1, .c2 = c1 };
        }
    }
};

pub const Edge = struct {
    x1: i16 = undefined,
    y1: i16 = undefined,
    c1: u8 = undefined,
    x2: i16 = undefined,
    y2: i16 = undefined,
    c2: u8 = undefined,

    // Orders the end points so y1 <= y2: the span walk only steps downwards.
    fn init(x1: i16, y1: i16, c1: u8, x2: i16, y2: i16, c2: u8) Edge {
        if (y1 <= y2) {
            return Edge{ .x1 = x1, .y1 = y1, .c1 = c1, .x2 = x2, .y2 = y2, .c2 = c2 };
        } else {
            return Edge{ .x1 = x2, .y1 = y2, .c1 = c2, .x2 = x1, .y2 = y1, .c2 = c1 };
        }
    }

    fn height(self: Edge) i32 {
        return @as(i32, self.y2) - self.y1;
    }
};

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Drawline
// --------------------------------------------------------------------------
pub fn drawLine(target: RenderTarget, src: Coord, dest: Coord, color_entry: u8) void {
    var coord0: Coord = undefined;
    var coord1: Coord = undefined;

    if (dest.y < src.y) {
        // coord0 = Coord{ .x=@min(dest.x, @as(i16, @intCast(WIDTH))), .y=@min(dest.y, @as(i16, @intCast(HEIGHT)))};
        coord0 = Coord{ .x = dest.x, .y = dest.y };
        coord1 = Coord{ .x = src.x, .y = src.y };
    } else {
        coord0 = Coord{ .x = src.x, .y = src.y };
        coord1 = Coord{ .x = dest.x, .y = dest.y };
    }

    // Console.log("coord 0: ({}, {})", .{coord0.x, coord0.y });
    // Console.log("coord 1: ({}, {})", .{coord1.x, coord1.y });

    // check limits

    var dx: i16 = undefined;
    var dy: i16 = undefined;

    var dp: i16 = undefined;
    var delta_e: i16 = undefined;
    var delta_ne: i16 = undefined;

    // check quadrant
    if (coord1.x >= coord0.x) {
        dx = coord1.x - coord0.x;
        dy = coord1.y - coord0.y;

        if (dx >= dy) {

            // y1 > y0 and x1 > x0 and dx >= dy
            dp = 2 * dy - dx;
            delta_e = 2 * dy;
            delta_ne = 2 * (dy - dx);

            var x = coord0.x;
            var y = coord0.y;

            target.setPixelValue(@as(u16, @intCast(x)), @as(u16, @intCast(y)), color_entry);

            while (x < coord1.x) {
                if (dp <= 0) {
                    dp += delta_e;
                    x += 1;
                } else {
                    dp += delta_ne;
                    x += 1;
                    y += 1;
                }
                target.setPixelValue(@as(u16, @intCast(x)), @as(u16, @intCast(y)), color_entry);
            }
        } else {
            // y1 >= y0 and x1 >= x0 and dx < dy
            dp = 2 * dx - dy;
            delta_e = 2 * dx;
            delta_ne = 2 * (dx - dy);

            var x = coord0.x;
            var y = coord0.y;

            target.setPixelValue(@as(u16, @intCast(x)), @as(u16, @intCast(y)), color_entry);

            while (y < coord1.y) {
                if (dp <= 0) {
                    dp += delta_e;
                    y += 1;
                } else {
                    dp += delta_ne;
                    x += 1;
                    y += 1;
                }
                target.setPixelValue(@as(u16, @intCast(x)), @as(u16, @intCast(y)), color_entry);
            }
        }
    } else {
        dx = coord0.x - coord1.x;
        dy = coord1.y - coord0.y;

        if (dx >= dy) {

            // y1 > y0 and x0 > x1 and dx >= dy
            dp = 2 * dy - dx;
            delta_e = 2 * dy;
            delta_ne = 2 * (dy - dx);

            var x = coord0.x;
            var y = coord0.y;

            target.setPixelValue(@as(u16, @intCast(x)), @as(u16, @intCast(y)), color_entry);

            while (x > coord1.x) {
                if (dp <= 0) {
                    dp += delta_e;
                    x -= 1;
                } else {
                    dp += delta_ne;
                    x -= 1;
                    y += 1;
                }
                target.setPixelValue(@as(u16, @intCast(x)), @as(u16, @intCast(y)), color_entry);
            }
        } else {

            // y1 > y0 and x0 > x1 and dx < dy
            dp = 2 * dx - dy;
            delta_e = 2 * dx;
            delta_ne = 2 * (dx - dy);

            var x = coord0.x;
            var y = coord0.y;

            target.setPixelValue(@as(u16, @intCast(x)), @as(u16, @intCast(y)), color_entry);

            while (y < coord1.y) {
                if (dp <= 0) {
                    dp += delta_e;
                    y += 1;
                } else {
                    dp += delta_ne;
                    x -= 1;
                    y += 1;
                }
                target.setPixelValue(@as(u16, @intCast(x)), @as(u16, @intCast(y)), color_entry);
            }
        }
    }
}

pub fn fillPolygon(fb: *LogicalFB, vertices: []const Coord, color_entry: u8) void {
    var min_x: i16 = std.math.maxInt(i16);
    var min_y: i16 = std.math.maxInt(i16);
    var max_x: i16 = std.math.minInt(i16);
    var max_y: i16 = std.math.minInt(i16);

    for (vertices) |pt| {
        min_x = @min(min_x, pt.x);
        min_y = @min(min_y, pt.y);
        max_x = @max(max_x, pt.x);
        max_y = @max(max_y, pt.y);
    }
    // Scan only the polygon's bounding box, clipped to the screen.
    min_x = @max(min_x, 0);
    min_y = @max(min_y, 0);
    max_x = @min(max_x, @as(i16, WIDTH - 1));
    max_y = @min(max_y, @as(i16, HEIGHT - 1));

    var y: i16 = min_y;
    while (y <= max_y) : (y += 1) {
        var x: i16 = min_x;
        while (x <= max_x) : (x += 1) {
            var inside = false;
            const p = Coord{ .x = x, .y = y };

            // free after https://stackoverflow.com/a/17490923

            var j = vertices.len - 1;
            for (vertices, 0..) |p0, i| {
                defer j = i;
                const p1 = vertices[j];

                if ((p0.y > p.y) != (p1.y > p.y) and @as(f32, @floatFromInt(p.x)) < @as(f32, @floatFromInt((p1.x - p0.x) * (p.y - p0.y))) / @as(f32, @floatFromInt((p1.y - p0.y))) + @as(f32, @floatFromInt(p0.x))) {
                    inside = !inside;
                }
            }
            if (inside) {
                if (x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT) {
                    fb.setPixelValue(@as(u16, @intCast(x)), @as(u16, @intCast(y)), color_entry);
                }
            }
        }
    }
}

// The pixels a fill writes to. A plain view (not LogicalFB) so the rasterizer
// runs natively in tests, where zigos.zig's machine modules do not exist.
pub const Plane = struct {
    px: [*]u8,
    stride: u32,
    w: i32,
    h: i32,

    fn of(fb: *LogicalFB) Plane {
        return .{ .px = fb.fb, .stride = fb.stride, .w = fb.fb_w, .h = fb.fb_h };
    }
};

pub fn fillFlatTriangle(fb: *LogicalFB, v1: Coord, v2: Coord, v3: Coord, pal_entry: u8) void {
    fillTriangle(Plane.of(fb), v1, v2, v3, pal_entry);
}

// Scanline triangle fill. Rows y in [top, bottom) are filled, columns in
// [left, right): two triangles sharing an edge never both claim its pixels.
pub fn fillTriangle(fb: Plane, v1: Coord, v2: Coord, v3: Coord, pal_entry: u8) void {
    // Every edge runs top to bottom (y1 <= y2), whatever order the vertices come
    // in: a rotating shape reorders them in y every few frames.
    const edges = [3]Edge{
        Edge.init(v1.x, v1.y, pal_entry, v2.x, v2.y, pal_entry),
        Edge.init(v2.x, v2.y, pal_entry, v3.x, v3.y, pal_entry),
        Edge.init(v3.x, v3.y, pal_entry, v1.x, v1.y, pal_entry),
    };

    // The edge spanning the most rows touches every row of the triangle; the
    // two others cover its upper and lower parts.
    var long_edge: usize = 0;
    for (edges, 0..) |e, i| {
        if (e.height() > edges[long_edge].height()) long_edge = i;
    }

    drawSpansBetweenEdges(fb, &edges[long_edge], &edges[(long_edge + 1) % 3]);
    drawSpansBetweenEdges(fb, &edges[long_edge], &edges[(long_edge + 2) % 3]);
}

fn drawSpansBetweenEdges(fb: Plane, e1: *const Edge, e2: *const Edge) void {
    const e1ydiff: f32 = @floatFromInt(e1.height());
    const e2ydiff: f32 = @floatFromInt(e2.height());
    if (e1ydiff == 0.0 or e2ydiff == 0.0) return;

    const e1xdiff: f32 = @floatFromInt(@as(i32, e1.x2) - e1.x1);
    const e2xdiff: f32 = @floatFromInt(@as(i32, e2.x2) - e2.x1);

    // e2 lies within e1's rows, so its first row sits part-way down e1.
    var factor1: f32 = @as(f32, @floatFromInt(@as(i32, e2.y1) - e1.y1)) / e1ydiff;
    var factor2: f32 = 0.0;

    var y: i32 = e2.y1;
    while (y < e2.y2) : (y += 1) {
        const xa: i32 = e1.x1 + @as(i32, @intFromFloat(e1xdiff * factor1));
        const xb: i32 = e2.x1 + @as(i32, @intFromFloat(e2xdiff * factor2));
        drawSpan(fb, @min(xa, xb), @max(xa, xb), y, e1.c1);
        factor1 += 1.0 / e1ydiff;
        factor2 += 1.0 / e2ydiff;
    }
}

// Fills [x1, x2) on row y, clipped to the plane.
fn drawSpan(fb: Plane, x1: i32, x2: i32, y: i32, pal_entry: u8) void {
    if (y < 0 or y >= fb.h) return;
    const left = @max(x1, 0);
    const right = @min(x2, fb.w);
    if (left >= right) return; // also a span wholly left or right of the plane
    const row: u32 = @as(u32, @intCast(y)) * fb.stride;
    @memset(fb.px[row + @as(u32, @intCast(left)) .. row + @as(u32, @intCast(right))], pal_entry);
}
