// --------------------------------------------------------------------------
// BAD APPLE!! POLYGONS: the even-odd scanline fill of a whole frame's contours (cart 168). ONE edge table for
// the frame, not one fill a polygon (STNICCC's polyfill paints each polygon in its own colour; here holes are
// contours too, and the parity of all of them decides a pixel). Integer only, the exact rule of
// tools/badapple/poly.py raster(): an edge (xa, ya)-(xb, yb), ya < yb, has slope = trunc((xb - xa) << 16 /
// (yb - ya)), X = (xa << 16) + trunc(slope / 2) at row ya, + slope a row, rows ya..yb-1; a row's change points
// are (X + 0x7FFF) >> 16 in X order, and its colours alternate from the background. A row whose change points
// are those of the last frame is not repainted (only modify what needs to be modified). Pure Zig.
// --------------------------------------------------------------------------
pub const WIDTH: usize = 320;
pub const HEIGHT: usize = 200;
const ROW_CAP: usize = 48; // change points a row the cache keeps; a busier row is repainted every frame
const NONE: u16 = 0xFFFF;

pub const Point = struct { x: i16, y: i16 };

const Edge = struct { x: i32, slope: i32, y1: u16, next: u16 };

const RowCache = struct { n: u8, bg: u8, p: [ROW_CAP]u16 };

pub fn Fill(comptime max_edges: usize) type {
    return struct {
        const Self = @This();

        edges: [max_edges]Edge = undefined,
        n_edges: usize = 0,
        bucket: [HEIGHT]u16 = undefined, // the first edge starting on each row (linked by .next)
        active: [max_edges]u16 = undefined,
        pts: [max_edges]u16 = undefined, // one row's change points
        cache: [HEIGHT]RowCache = undefined,

        /// The plane holds all-black rows (the cart cleared it).
        pub fn reset(self: *Self) void {
            for (&self.cache) |*c| {
                c.n = 0;
                c.bg = 0;
            }
        }

        pub fn begin(self: *Self) void {
            self.n_edges = 0;
            @memset(&self.bucket, NONE);
        }

        /// One contour's edges (closed: the last vertex joins the first). The caller keeps the total under max_edges.
        pub fn contour(self: *Self, v: []const Point) void {
            for (v, 0..) |a, i| {
                const b = v[(i + 1) % v.len];
                if (a.y == b.y) continue;
                const lo, const hi = if (a.y < b.y) .{ a, b } else .{ b, a };
                const dy: i32 = @as(i32, hi.y) - lo.y;
                const slope = @divTrunc((@as(i32, hi.x) - lo.x) << 16, dy);
                const ya: usize = @intCast(lo.y);
                self.edges[self.n_edges] = .{
                    .x = (@as(i32, lo.x) << 16) + @divTrunc(slope, 2),
                    .slope = slope,
                    .y1 = @intCast(hi.y),
                    .next = self.bucket[ya],
                };
                self.bucket[ya] = @intCast(self.n_edges);
                self.n_edges += 1;
            }
        }

        /// Scan every row and repaint the rows that changed. `bg` is the background colour (0 or 1).
        pub fn paint(self: *Self, fb: []u8, stride: usize, bg: u8) void {
            var n_act: usize = 0;
            for (0..HEIGHT) |r| {
                var e = self.bucket[r];
                while (e != NONE) : (e = self.edges[e].next) {
                    self.active[n_act] = e;
                    n_act += 1;
                }
                self.sortActive(n_act);
                var k: usize = 0;
                for (self.active[0..n_act]) |ai| {
                    const x = self.edges[ai].x;
                    self.pts[k] = @intCast(@min(@as(i32, WIDTH), @max(0, (x + 0x7FFF) >> 16))); // i32 throughout: a usize bound made it i64 maths
                    k += 1;
                }
                if (self.changed(r, k, bg)) paintRow(fb[r * stride ..][0..WIDTH], self.pts[0..k], bg);
                // step every edge to the next row, dropping the ones that end here
                var kept: usize = 0;
                for (self.active[0..n_act]) |ai| {
                    const ed = &self.edges[ai];
                    if (ed.y1 <= r + 1) continue;
                    ed.x += ed.slope;
                    self.active[kept] = ai;
                    kept += 1;
                }
                n_act = kept;
            }
        }

        /// Insertion sort by X: the list is nearly sorted from the last row, so this is about one pass.
        fn sortActive(self: *Self, n: usize) void {
            var i: usize = 1;
            while (i < n) : (i += 1) {
                const v = self.active[i];
                const vx = self.edges[v].x;
                var j = i;
                while (j > 0 and self.edges[self.active[j - 1]].x > vx) : (j -= 1) self.active[j] = self.active[j - 1];
                self.active[j] = v;
            }
        }

        /// False when row r already shows exactly these change points on this background; updates the cache.
        fn changed(self: *Self, r: usize, k: usize, bg: u8) bool {
            const c = &self.cache[r];
            const pts = self.pts[0..k];
            if (c.n != 0xFF and c.n == k and c.bg == bg and std_eql(c.p[0..k], pts)) return false;
            c.bg = bg;
            if (k > ROW_CAP) {
                c.n = 0xFF; // too busy to cache: always repainted
            } else {
                c.n = @intCast(k);
                @memcpy(c.p[0..k], pts);
            }
            return true;
        }
    };
}

fn std_eql(a: []const u16, b: []const u16) bool {
    for (a, b) |x, y| if (x != y) return false;
    return true;
}

/// One 320-pixel row: colours alternate from `bg` at each change point (sorted; equal points cancel out).
fn paintRow(row: []u8, pts: []const u16, bg: u8) void {
    var x: usize = 0;
    var col = bg;
    for (pts) |p| {
        if (p > x) {
            @memset(row[x..p], col);
            x = p;
        }
        col ^= 1;
    }
    if (x < WIDTH) @memset(row[x..WIDTH], col);
}
