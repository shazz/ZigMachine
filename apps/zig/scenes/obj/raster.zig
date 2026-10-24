// --------------------------------------------------------------------------
// OBJ demo: the CPU rasterisers, pixel for pixel CHISEL's own rules
// (machine/blitter.zig doTriangle / doLine), so a face or an edge may go to
// either and the picture does not change:
//   - a triangle covers, on each row y, the span between the two edges with
//     ay <= y < by, at x = ax + floor((bx - ax) * (y - ay) / (by - ay)),
//     both ends included (the old softTriangle, made incremental: 2-3 divides
//     a triangle instead of one per edge per row);
//   - a line is CHISEL's Bresenham, end points included.
// Small faces and short edges are cheaper here than a CHISEL op (~800 cycles
// fixed on the board); render.zig picks. Gouraud has no CHISEL op: always here.
// No ZigOS import: obj/tests.zig tests it natively.
// --------------------------------------------------------------------------
const fdiv = @import("fdiv.zig");

pub const Target = struct { px: [*]u8, stride: u32, w: i32, h: i32 };
pub const P = [2]i16;

/// One edge walked a row at a time: x = ax + floor(dx * k / dy) exactly.
const Edge = struct {
    x: i32,
    err: i32,
    q: i32,
    r: i32,
    dy: i32,

    fn init(a: P, b: P, y: i32) Edge {
        const dy: i32 = @as(i32, b[1]) - a[1];
        const dx: i32 = @as(i32, b[0]) - a[0];
        const qr = fdiv.floorDivRem(dx, dy);
        var e = Edge{ .x = a[0], .err = 0, .q = qr.q, .r = qr.r, .dy = dy };
        const k = y - a[1];
        if (k > 0) { // clipped at the top: dx k / dy = q k + r k / dy
            const s = fdiv.floorDivRem(qr.r * k, dy);
            e.x += qr.q * k + s.q;
            e.err = s.r;
        }
        return e;
    }

    inline fn step(e: *Edge) void {
        e.x += e.q;
        e.err += e.r;
        if (e.err >= e.dy) {
            e.err -= e.dy;
            e.x += 1;
        }
    }
};

fn sortY(v: [3]P) [3]P {
    var s = v;
    if (s[1][1] < s[0][1]) swap(&s[0], &s[1]);
    if (s[2][1] < s[1][1]) swap(&s[1], &s[2]);
    if (s[1][1] < s[0][1]) swap(&s[0], &s[1]);
    return s;
}
fn swap(a: *P, b: *P) void {
    const t = a.*;
    a.* = b.*;
    b.* = t;
}

/// Calls span(ctx, y, xl, xr) for every row the triangle covers, clipped to
/// the target's rows (columns are the span's business).
fn walk(t: Target, v: [3]P, ctx: anytype, comptime span: fn (@TypeOf(ctx), i32, i32, i32) void) void {
    const s = sortY(v);
    const y0: i32 = s[0][1];
    const y1: i32 = s[1][1];
    const y2: i32 = s[2][1];
    if (y0 == y2) return;
    var y = @max(y0, 0);
    const yend = @min(y2, t.h); // exclusive: no edge is active on row y2
    if (y >= yend) return;
    var long = Edge.init(s[0], s[2], y);
    var short = if (y < y1) Edge.init(s[0], s[1], y) else Edge.init(s[1], s[2], y);
    while (y < yend) : (y += 1) {
        if (y == y1 and y1 > y0) short = Edge.init(s[1], s[2], y);
        span(ctx, y, @min(long.x, short.x), @max(long.x, short.x));
        long.step();
        short.step();
    }
}

const Flat = struct { t: Target, color: u8 };

fn flatSpan(c: Flat, y: i32, xl: i32, xr: i32) void {
    const l = @max(xl, 0);
    const r = @min(xr, c.t.w - 1);
    if (r < l) return;
    const row = c.t.px + @as(usize, @intCast(y)) * c.t.stride;
    fill(row[@intCast(l)..@intCast(r + 1)], c.color);
}

/// Short spans (most of a fine mesh's) in a byte loop, long ones by memset:
/// its call costs more than the few stores of a short one.
inline fn fill(span: []u8, v: u8) void {
    if (span.len <= 12) {
        for (span) |*p| p.* = v;
    } else @memset(span, v);
}

/// A flat triangle: CHISEL's TRIANGLE with the copy minterm, on the CPU.
pub fn flat(t: Target, v: [3]P, color: u8) void {
    walk(t, v, Flat{ .t = t, .color = color }, flatSpan);
}

fn softSpan(c: Flat, y: i32, xl: i32, xr: i32) void {
    const l = @max(xl, 0);
    const r = @min(xr, c.t.w - 1); // exclusive, as LogicalFB.drawScanline drew it
    if (r <= l) return;
    const row = c.t.px + @as(usize, @intCast(y)) * c.t.stride;
    fill(row[@intCast(l)..@intCast(r)], c.color);
}

/// The old SOFT mode's own rasteriser (obj_demo's softTriangle): CHISEL's rows
/// but each span's right end left out. Kept so SOFT's picture is unchanged.
pub fn soft(t: Target, v: [3]P, color: u8) void {
    walk(t, v, Flat{ .t = t, .color = color }, softSpan);
}

fn orSpan(c: Flat, y: i32, xl: i32, xr: i32) void {
    const l = @max(xl, 0);
    const r = @min(xr, c.t.w - 1);
    if (r < l) return;
    const row = c.t.px + @as(usize, @intCast(y)) * c.t.stride;
    for (row[@intCast(l)..@intCast(r + 1)]) |*p| p.* |= c.color;
}

/// CHISEL's TRIANGLE with the OR minterm (glenz), on the CPU.
pub fn glenz(t: Target, v: [3]P, bit: u8) void {
    walk(t, v, Flat{ .t = t, .color = bit }, orSpan);
}

/// CHISEL's LINE (copy minterm): Bresenham, both ends drawn, clipped.
pub fn line(t: Target, a: P, b: P, color: u8) void {
    var x: i32 = a[0];
    var y: i32 = a[1];
    const x1: i32 = b[0];
    const y1: i32 = b[1];
    const dx: i32 = @intCast(@abs(x1 - x));
    const dy: i32 = -@as(i32, @intCast(@abs(y1 - y)));
    const sx: i32 = if (x < x1) 1 else -1;
    const sy: i32 = if (y < y1) 1 else -1;
    var err = dx + dy;
    while (true) {
        if (x >= 0 and y >= 0 and x < t.w and y < t.h) t.px[@as(usize, @intCast(y)) * t.stride + @as(usize, @intCast(x))] = color;
        if (x == x1 and y == y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y += sy;
        }
    }
}

pub const gouraud = @import("gouraud.zig").triangle;
pub const walkRows = walk;
