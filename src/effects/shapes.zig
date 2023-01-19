// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const LogicalFB = @import("../zigos.zig").LogicalFB;
const Console = @import("../utils/debug.zig").Console;

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
    c2: i16 = undefined,

    fn init(x1: i16, y1: i16, c1: u8, x2: i16, y2: i16, c2: u8) Span {
        if (y1 < y2) {
            return Edge{ .x1 = x1, .y1 = y1, .c1 = c1, .x2 = x2, .x2 = x2, .c2 = c2 };
        } else {
            return Edge{ .x1 = x2, .y1 = y2, .c1 = c2, .x2 = x1, .x2 = x1, .c2 = c1 };
        }
    }
};

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Drawline
// --------------------------------------------------------------------------
pub fn drawLine(fb: *LogicalFB, src: Coord, dest: Coord, color_entry: u8) void {
    var coord0: Coord = undefined;
    var coord1: Coord = undefined;

    if (dest.y < src.y) {
        // coord0 = Coord{ .x=@min(dest.x, @intCast(i16, WIDTH)), .y=@min(dest.y, @intCast(i16, HEIGHT))};
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

            fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);

            while (x < coord1.x) {
                if (dp <= 0) {
                    dp += delta_e;
                    x += 1;
                } else {
                    dp += delta_ne;
                    x += 1;
                    y += 1;
                }
                fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);
            }
        } else {
            // y1 >= y0 and x1 >= x0 and dx < dy
            dp = 2 * dx - dy;
            delta_e = 2 * dx;
            delta_ne = 2 * (dx - dy);

            var x = coord0.x;
            var y = coord0.y;

            fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);

            while (y < coord1.y) {
                if (dp <= 0) {
                    dp += delta_e;
                    y += 1;
                } else {
                    dp += delta_ne;
                    x += 1;
                    y += 1;
                }
                fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);
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

            fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);

            while (x > coord1.x) {
                if (dp <= 0) {
                    dp += delta_e;
                    x -= 1;
                } else {
                    dp += delta_ne;
                    x -= 1;
                    y += 1;
                }
                fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);
            }
        } else {

            // y1 > y0 and x0 > x1 and dx < dy
            dp = 2 * dx - dy;
            delta_e = 2 * dx;
            delta_ne = 2 * (dx - dy);

            var x = coord0.x;
            var y = coord0.y;

            fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);

            while (y < coord1.y) {
                if (dp <= 0) {
                    dp += delta_e;
                    y += 1;
                } else {
                    dp += delta_ne;
                    x -= 1;
                    y += 1;
                }
                fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);
            }
        }
    }
}

pub fn fillPolygon(fb: *LogicalFB, vertices: []const Coord, color_entry: u8) void {
    var min_x: i16 = 0; //std.math.maxInt(i16);
    var min_y: i16 = 0; //std.math.maxInt(i16);
    var max_x: i16 = WIDTH - 1; //std.math.minInt(i16);
    var max_y: i16 = HEIGHT - 1; //std.math.minInt(i16);

    for (vertices) |pt| {
        min_x = std.math.min(min_x, pt.x);
        min_y = std.math.min(min_y, pt.y);
        max_x = std.math.max(max_x, pt.x);
        max_y = std.math.max(max_y, pt.y);
    }

    var y: i16 = min_y;
    while (y <= max_y) : (y += 1) {
        var x: i16 = min_x;
        while (x <= max_x) : (x += 1) {
            var inside = false;
            const p = Coord{ .x = x, .y = y };

            // free after https://stackoverflow.com/a/17490923

            var j = vertices.len - 1;
            for (vertices) |p0, i| {
                defer j = i;
                const p1 = vertices[j];

                if ((p0.y > p.y) != (p1.y > p.y) and @intToFloat(f32, p.x) < @intToFloat(f32, (p1.x - p0.x) * (p.y - p0.y)) / @intToFloat(f32, (p1.y - p0.y)) + @intToFloat(f32, p0.x)) {
                    inside = !inside;
                }
            }
            if (inside) {
                if (x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT) {
                    fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);
                }
            }
        }
    }
}

pub fn fillFlatTriangle(fb: *LogicalFB, v1: Coord, v2: Coord, v3: Coord, pal_entry: u8) void {
    var edges: [3]Edge = undefined;
    edges[0] = .{ .x1 = v1.x, .y1 = v1.y, .c1 = pal_entry, .x2 = v2.x, .y2 = v2.y, .c2 = pal_entry };
    edges[1] = .{ .x1 = v2.x, .y1 = v2.y, .c1 = pal_entry, .x2 = v3.x, .y2 = v3.y, .c2 = pal_entry };
    edges[2] = .{ .x1 = v3.x, .y1 = v3.y, .c1 = pal_entry, .x2 = v1.x, .y2 = v1.y, .c2 = pal_entry };

    var max_length: usize = 0;
    var long_edge: usize = 0;
    var i: usize = 0;

    // find edge with the greatest length in the y axis
    while (i < 3) : (i += 1) {
        var length: usize = @intCast(usize, edges[i].y2 - edges[i].y1);
        if (length > max_length) {
            max_length = length;
            long_edge = i;
        }
    }

    const short_edge1 = @mod(long_edge + 1, 3);
    const short_edge2 = @mod(long_edge + 2, 3);

    // draw spans between edges; the long edge can be drawn
    // with the shorter edges to draw the full triangle
    drawSpansBetweenEdges(fb, &edges[long_edge], &edges[short_edge1]);
    drawSpansBetweenEdges(fb, &edges[long_edge], &edges[short_edge2]);
}

fn drawSpansBetweenEdges(fb: *LogicalFB, e1: *const Edge, e2: *const Edge) void {

    // calculate difference between the y coordinates
    // of the first edge and return if 0
    var e1ydiff: f32 = @intToFloat(f32, (e1.y2 - e1.y1));
    if (e1ydiff == 0.0)
        return;

    // calculate difference between the y coordinates
    // of the second edge and return if 0
    var e2ydiff: f32 = @intToFloat(f32, (e2.y2 - e2.y1));
    if (e2ydiff == 0.0)
        return;

    // calculate differences between the x coordinates
    // and colors of the points of the edges
    var e1xdiff = @intToFloat(f32, (e1.x2 - e1.x1));
    var e2xdiff = @intToFloat(f32, (e2.x2 - e2.x1));

    // color gradient
    // Color e1colordiff = (e1.Color2 - e1.Color1);
    // Color e2colordiff = (e2.Color2 - e2.Color1);

    // calculate factors to use for interpolation
    // with the edges and the step values to increase
    // them by after drawing each span
    var factor1 = @intToFloat(f32, (e2.y1 - e1.y1)) / e1ydiff;
    var factorStep1: f32 = 1.0 / e1ydiff;
    var factor2: f32 = 0.0;
    var factorStep2: f32 = 1.0 / e2ydiff;

    // loop through the lines between the edges and draw spans
    var y = e2.y1;
    while (y < e2.y2) : (y += 1) {

        // create and draw span
        var span = Span.init(e1.x1 + @floatToInt(i16, e1xdiff * factor1), e1.c1, e2.x1 + @floatToInt(i16, e2xdiff * factor2), e2.c1);
        // Span span(e1.Color1 + (e1colordiff * factor1),
        //           e1.X1 + (int)(e1xdiff * factor1),
        //           e2.Color1 + (e2colordiff * factor2),
        //           e2.X1 + (int)(e2xdiff * factor2));
        drawSpan(fb, &span, y);

        // increase factors
        factor1 += factorStep1;
        factor2 += factorStep2;
    }
}

fn drawSpan(fb: *LogicalFB, span: *const Span, y: i16) void {

    // Console.log("drawSpan at y={} from {} to {} in color {}", .{y, span.x1, span.x2, span.c1});

    var xdiff = span.x2 - span.x1;
    if (xdiff == 0) {
        // Console.log("not drawn as xdiff == {}", . {xdiff});
        return;
    }

    // Color colordiff = span.Color2 - span.Color1;
    // var factor: f32 = 0.0;
    // float factorStep = 1.0f / (float)xdiff;

    // draw each pixel in the span
    fb.drawScanline(@intCast(u16, span.x1), @intCast(u16, span.x2), @intCast(u16, y), span.c1);

    // var x = span.x1;
    // while(x < span.x2) : ( x += 1 ) {
    //     // Console.log("setPixelValue at ({}, {}) in color {}", .{x, y, span.c1});
    //     fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), span.c1);

    // 	// SetPixel(x, y, span.Color1 + (colordiff * factor));
    // 	// factor += factorStep;
    // }
}
