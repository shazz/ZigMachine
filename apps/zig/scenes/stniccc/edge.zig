// --------------------------------------------------------------------------
// The polygon filler's edge walker (polyfill.zig): exact pixel-centre
// crossings, stepped a row at a time with no divide.
// --------------------------------------------------------------------------
const Point = @import("polyfill.zig").Point;

// One non-horizontal edge, walked a row at a time. Row y's centre crossing is
//   x = lo.x * 65536 + floor(dx * 32768 * (2k + 1) / dy)      (k = y - lo.y)
// and the numerator grows by A = dx * 65536 a row, so the floor is stepped as a
// quotient and a remainder (0 <= r < dy): no divide per row. The old code did an
// i64 divide per edge per row (a soft routine on rv32: ~3 Mc a frame on the board).
pub const Edge = struct {
    y_lo: i32, // first row the edge crosses
    y_hi: i32, // one past the last
    base: i32, // lo.x * 65536
    q: i32, // floor(numerator / dy) at the next row
    r: i32, // the remainder of that division
    dy: i32,
    qs: i32, // floor(A / dy)
    rs: i32, // A mod dy
};

pub fn edgeAt(lo: Point, hi: Point, y_first: i32) Edge {
    const dx = hi.x - lo.x;
    const dy = hi.y - lo.y;
    const a = dx * 65536;
    var e = Edge{ .y_lo = lo.y, .y_hi = hi.y, .base = lo.x * 65536, .q = 0, .r = 0, .dy = dy, .qs = @divFloor(a, dy), .rs = @mod(a, dy) };
    const k = y_first - lo.y;
    if (k == 0) { // the usual start: a 32-bit numerator
        e.q = @divFloor(dx * 32768, dy);
        e.r = @mod(dx * 32768, dy);
    } else { // a polygon clipped at the top: its numerator may not fit 32 bits
        const n = @as(i64, dx) * 32768 * (2 * @as(i64, k) + 1);
        e.q = @intCast(@divFloor(n, dy));
        e.r = @intCast(@mod(n, dy));
    }
    return e;
}

pub inline fn step(e: *Edge) void {
    e.q += e.qs;
    e.r += e.rs;
    if (e.r >= e.dy) {
        e.r -= e.dy;
        e.q += 1;
    }
}
