// --------------------------------------------------------------------------
// The polygon filler's fast path (polyfill.zig): a polygon whose vertices go
// down once and back up once around the outline (any convex one, and most of
// STNICCC's) has exactly TWO crossings on every row, one on the way down and
// one on the way up. So instead of testing every edge on every row and
// sorting, two chains are walked from the top vertex: one edge each a row.
// A row centre (y + 0.5) never meets a vertex, so the edge in effect is always
// one per chain, even where the chains cross (a bow-tie): the span is then
// [min, max) of the two crossings, what the sorted even-odd pair gives.
// Same Edge maths as the general path, so the same pixels (polyfill_test).
// --------------------------------------------------------------------------
const std = @import("std");
const polyfill = @import("polyfill.zig");
const edge = @import("edge.zig");
const span = @import("span.zig");
const Point = polyfill.Point;
const Target = polyfill.Target;

// One side of the outline from the top vertex: `dir` +1 walks forward, -1 back.
const Chain = struct {
    pts: []const Point,
    at: usize, // the vertex the current edge starts from
    dir: i8,
    e: edge.Edge = undefined,
    live: bool = false,

    fn next(c: *const Chain, i: usize) usize {
        if (c.dir > 0) return if (i + 1 == c.pts.len) 0 else i + 1;
        return if (i == 0) c.pts.len - 1 else i - 1;
    }

    // Make the current edge the one that crosses row y (rows come in order).
    fn seek(c: *Chain, y: i32) void {
        while (!c.live or y >= c.e.y_hi) {
            const a = c.pts[c.at];
            const b = c.pts[c.next(c.at)];
            c.at = c.next(c.at);
            c.live = b.y > y; // only an edge going down past row y's centre is used
            if (c.live) c.e = edge.edgeAt(a, b, @max(a.y, y));
        }
    }

    // The crossing on row y.
    fn x(c: *Chain, y: i32) i32 {
        c.seek(y);
        const v = c.e.base + c.e.q;
        edge.step(&c.e);
        return v;
    }
};

/// Fill rows [y, y_end) when the outline is down-then-up; false (nothing drawn)
/// when it is not, for the general path.
pub fn fill(t: Target, pts: []const Point, y_start: i32, y_end: i32, color: u8) bool {
    const top = topIfMonotone(pts) orelse return false;
    var a = Chain{ .pts = pts, .at = top, .dir = 1 };
    var b = Chain{ .pts = pts, .at = top, .dir = -1 };
    if (t.rect != null and t.blit_min != std.math.maxInt(usize)) {
        var run = polyfill.Run{}; // rows that repeat become one rect, for the blitter
        var y = y_start;
        while (y < y_end) : (y += 1) {
            const sp = rowSpan(t, &a, &b, y);
            if (sp.start < sp.end) run.add(t, sp, y, color);
        }
        run.flush(t, color);
        return true;
    }
    // CPU spans, a pair of edges at a time: rows until either edge ends.
    var line = @intFromPtr(t.px.ptr) + @as(usize, @intCast(y_start)) * t.stride + t.ox;
    var y = y_start;
    while (y < y_end) {
        a.seek(y);
        b.seek(y);
        const stop = @min(y_end, @min(a.e.y_hi, b.e.y_hi));
        line = rows(t, &a.e, &b.e, line, stop - y, color);
        y = stop;
    }
    return true;
}

// `n` rows from `line` between two edges, written as they are walked. The edges
// are copied into locals for the loop (registers, not memory) and back after.
fn rows(t: Target, ea: *edge.Edge, eb: *edge.Edge, line0: usize, n: i32, color: u8) usize {
    var a = ea.*;
    var b = eb.*;
    var line = line0;
    var k = n;
    while (k > 0) : (k -= 1) {
        const xa = a.base + a.q;
        const xb = b.base + b.q;
        edge.step(&a);
        edge.step(&b);
        const sp = polyfill.clip(t, @min(xa, xb), @max(xa, xb));
        if (sp.start < sp.end) span.row(line + @as(usize, @intCast(sp.start)), line + @as(usize, @intCast(sp.end)), color);
        line += t.stride;
    }
    ea.* = a;
    eb.* = b;
    return line;
}

inline fn rowSpan(t: Target, a: *Chain, b: *Chain, y: i32) polyfill.Span {
    const xa = a.x(y);
    const xb = b.x(y);
    return polyfill.clip(t, @min(xa, xb), @max(xa, xb));
}

// The first top vertex when the y's, read around the outline and ignoring flat
// steps, change direction exactly twice (once at the top, once at the bottom).
fn topIfMonotone(pts: []const Point) ?usize {
    var turns: u32 = 0;
    var last: i32 = 0; // the sign of the last non-flat step
    var first: i32 = 0;
    var top: usize = 0;
    for (pts, 0..) |p, i| {
        if (p.y < pts[top].y) top = i;
        const q = pts[if (i + 1 == pts.len) 0 else i + 1];
        const d: i32 = if (q.y > p.y) 1 else if (q.y < p.y) -1 else 0;
        if (d == 0) continue;
        if (first == 0) first = d else if (d != last) turns += 1;
        last = d;
    }
    if (first != last) turns += 1; // the step that closes the loop
    return if (turns == 2) top else null;
}
