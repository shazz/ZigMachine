// --------------------------------------------------------------------------
// Even-odd scanline polygon filler for STNICCC's polygons: 3..15 vertices,
// possibly NON-convex (format.txt says so), integer coordinates. A pixel is
// filled when its centre lies inside the polygon, so two polygons sharing an
// edge tile without a gap or a double row. Pure; tested in polyfill_test.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const span = @import("span.zig");
const edge = @import("edge.zig");
const monotone = @import("monotone.zig");
const Edge = edge.Edge;

pub const MAX_VERTS: usize = 15;
pub const Point = struct { x: i32, y: i32 };

// Where to draw: `w` x `h` pixels inside `px`, starting `ox` pixels into each
// `stride`-wide row. Nothing outside that window is ever written.
/// `rect`, when set, fills a rectangle (x counted from the row start, so `ox`
/// is included) on the blitter, for fills of span.BLIT_MIN pixels and up.
pub const Target = struct {
    px: []u8,
    stride: usize,
    w: usize,
    h: usize,
    ox: usize,
    rect: ?*const fn (x: usize, y: usize, w: usize, h: usize, color: u8) void = null,
    blit_min: usize = span.BLIT_MIN, // the area from which `rect` is used (tests lower it)
};

/// The span [start, end) of a row's pixels whose centres fall in [x0, x1) (16.16).
pub const Span = struct { start: i32, end: i32 };
pub fn clip(t: Target, x0: i32, x1: i32) Span {
    const w: i32 = @intCast(t.w);
    return .{ .start = @max(0, (x0 + 0x7FFF) >> 16), .end = @min(w, (x1 + 0x7FFF) >> 16) };
}

pub fn fill(t: Target, pts: []const Point, color: u8) void {
    // A real branch, not std.debug.assert (gone in ReleaseSmall): an empty list
    // would wrap `pts.len - 1` and more than MAX_VERTS overruns `edges`.
    if (pts.len < 3 or pts.len > MAX_VERTS) return;
    var ymin: i32 = std.math.maxInt(i32);
    var ymax: i32 = std.math.minInt(i32);
    for (pts) |p| {
        ymin = @min(ymin, p.y);
        ymax = @max(ymax, p.y);
    }
    const y = @max(ymin, 0);
    const y_end = @min(ymax, @as(i32, @intCast(t.h))); // row y's centre is y + 0.5
    if (y >= y_end) return;
    if (monotone.fill(t, pts, y, y_end, color)) return;
    fillAny(t, pts, y, y_end, color);
}

// Any polygon, whatever its rows cross: every edge is tested on every row and
// the crossings are sorted, then filled in pairs (even-odd).
fn fillAny(t: Target, pts: []const Point, y_start: i32, y_end: i32, color: u8) void {
    var edges: [MAX_VERTS]Edge = undefined;
    var ne: usize = 0;
    var j = pts.len - 1;
    for (pts, 0..) |a, i| {
        defer j = i;
        const b = pts[j];
        if (a.y == b.y) continue;
        const lo = if (a.y < b.y) a else b;
        const hi = if (a.y < b.y) b else a;
        if (hi.y <= y_start or lo.y >= y_end) continue; // never crosses a drawn row
        edges[ne] = edge.edgeAt(lo, hi, @max(lo.y, y_start));
        ne += 1;
    }
    var run = Run{};
    var y = y_start;
    while (y < y_end) : (y += 1) {
        var xs: [MAX_VERTS]i32 = undefined;
        const n = crossings(edges[0..ne], y, &xs);
        var k: usize = 0;
        while (k + 1 < n) : (k += 2) {
            const sp = clip(t, xs[k], xs[k + 1]);
            if (sp.start >= sp.end) continue;
            if (n == 2) {
                run.add(t, sp, y, color);
            } else {
                run.flush(t, color);
                emit(t, sp, y, 1, color);
            }
        }
    }
    run.flush(t, color);
}

// Row y's crossings of the edges that span it, sorted (insertion: at most 15).
fn crossings(edges: []Edge, y: i32, xs: *[MAX_VERTS]i32) usize {
    var n: usize = 0;
    for (edges) |*e| {
        if (y < e.y_lo or y >= e.y_hi) continue;
        const x = e.base + e.q;
        edge.step(e);
        var m = n;
        while (m > 0 and xs[m - 1] > x) : (m -= 1) xs[m] = xs[m - 1];
        xs[m] = x;
        n += 1;
    }
    return n;
}

// A pending fill: the rows from `y` that all show span `sp` (a polygon's vertical
// sides repeat it row after row), flushed as ONE rectangle. Same pixels.
pub const Run = struct {
    sp: Span = .{ .start = 0, .end = 0 },
    y: i32 = 0,
    h: i32 = 0,

    fn extend(r: *Run, sp: Span, y: i32) bool {
        if (r.h == 0 or r.sp.start != sp.start or r.sp.end != sp.end or r.y + r.h != y) return false;
        r.h += 1;
        return true;
    }

    /// Row y's only span: one taller fill when it repeats the row above.
    pub fn add(r: *Run, t: Target, sp: Span, y: i32, color: u8) void {
        if (r.extend(sp, y)) return;
        r.flush(t, color);
        r.* = .{ .sp = sp, .y = y, .h = 1 };
    }

    pub fn flush(r: *Run, t: Target, color: u8) void {
        if (r.h > 0) emit(t, r.sp, r.y, r.h, color);
        r.h = 0;
    }
};

fn emit(t: Target, sp: Span, y: i32, h: i32, color: u8) void {
    const start: usize = @intCast(sp.start);
    rect(t, start, @intCast(y), @as(usize, @intCast(sp.end)) - start, @intCast(h), color);
}

/// Fill a w x h rectangle of the window (x, y from its top-left corner): on
/// CHISEL when `t.rect` is set and it covers t.blit_min pixels, else on the CPU.
pub fn rect(t: Target, x: usize, y: usize, w: usize, h: usize, color: u8) void {
    if (t.rect) |blit| if (w * h >= t.blit_min) return blit(t.ox + x, y, w, h, color);
    span.rect(t.px, y * t.stride + t.ox + x, w, h, t.stride, color);
}
