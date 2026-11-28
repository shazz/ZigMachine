// --------------------------------------------------------------------------
// BAD APPLE!! polygon-stream decoder ("BAPO", cart 168; the byte layout is tools/badapple/poly.py's).
// A frame is closed contours on the pixel-corner lattice (x 0..320, y 0..200): NEW ones (a first vertex, then
// nibble or escaped steps), KEEP / DELTA ones (the previous frame's contour j, unchanged or each vertex moved
// -7..+7). The frame's contours are then filled even-odd in one pass (polyfill.zig). A block's first frame
// has only NEW contours. Pure Zig: native tests in poly_test.zig.
// --------------------------------------------------------------------------
const polyfill = @import("polyfill.zig");

pub const MAGIC = "BAPO";
pub const MAX_PACKED: usize = 64 * 1024;
pub const MAX_RAW: usize = 96 * 1024;
pub const MAX_VERTS: usize = 6000; // a frame's (tools/badapple/poly.py MAX_VERTS)
pub const MAX_CONTOURS: usize = 1500;
const NEW: u8 = 0;
const KEEP: u8 = 1;
const DELTA: u8 = 2;
const Point = polyfill.Point;

pub const State = struct {
    verts: [2][MAX_VERTS]Point = undefined,
    starts: [2][MAX_CONTOURS + 1]u16 = undefined, // contour i = verts[b][starts[b][i]..starts[b][i + 1]]
    count: [2]u16 = .{ 0, 0 },
    cur: u1 = 0, // the buffer holding the last frame's contours
    first: bool = true,
    fill: polyfill.Fill(MAX_VERTS) = .{},

    pub fn reset(self: *State) void {
        self.count = .{ 0, 0 };
        self.cur = 0;
        self.first = true;
        self.fill.reset();
    }

    /// A polygon block has no preamble: its frames start at once (and may not refer to the last block's).
    pub fn beginBlock(self: *State, raw: []const u8) ?usize {
        _ = raw;
        self.first = true;
        return 0;
    }

    /// Decode one frame's contours and fill them into `fb`. False on any malformed byte (nothing is painted then).
    pub fn decodeFrame(self: *State, bytes: []const u8, fb: []u8, stride: u16) bool {
        if (stride < polyfill.WIDTH or fb.len < @as(usize, stride) * polyfill.HEIGHT) return false;
        var r = Reader{ .b = bytes };
        const flags = r.byte() orelse return false;
        const n = r.varint() orelse return false;
        if (flags > 1 or n > MAX_CONTOURS) return false;
        const nb = self.cur ^ 1;
        var nv: usize = 0;
        self.starts[nb][0] = 0;
        for (0..n) |i| {
            nv = self.contour(&r, nb, nv) orelse return false;
            self.starts[nb][i + 1] = @intCast(nv);
        }
        if (r.p != bytes.len) return false;
        self.count[nb] = @intCast(n);
        self.cur = nb;
        self.first = false;
        self.fill.begin();
        for (0..n) |i| self.fill.contour(self.verts[nb][self.starts[nb][i]..self.starts[nb][i + 1]]);
        self.fill.paint(fb, stride, flags);
        return true;
    }

    /// Reads one contour into buffer nb from vertex nv on; the new vertex count, or null.
    fn contour(self: *State, r: *Reader, nb: u1, nv: usize) ?usize {
        const op = r.byte() orelse return null;
        if (op == NEW) {
            const n = r.varint() orelse return null;
            if (n < 3 or nv + n > MAX_VERTS) return null;
            const head = r.take(3) orelse return null;
            var x: i32 = @as(i32, head[0]) | (@as(i32, head[1]) << 8);
            var y: i32 = head[2];
            for (0..n) |k| {
                if (k > 0) {
                    const d = r.step() orelse return null;
                    x += d[0];
                    y += d[1];
                }
                self.verts[nb][nv + k] = vertex(x, y) orelse return null;
            }
            return nv + n;
        }
        if ((op != KEEP and op != DELTA) or self.first) return null;
        const j = r.varint() orelse return null;
        const pb = self.cur;
        if (j >= self.count[pb]) return null;
        const src = self.verts[pb][self.starts[pb][j]..self.starts[pb][j + 1]];
        if (nv + src.len > MAX_VERTS) return null;
        for (src, 0..) |v, k| {
            var x: i32 = v.x;
            var y: i32 = v.y;
            if (op == DELTA) {
                const d = r.nibbles() orelse return null;
                x += d[0];
                y += d[1];
            }
            self.verts[nb][nv + k] = vertex(x, y) orelse return null;
        }
        return nv + src.len;
    }
};

fn vertex(x: i32, y: i32) ?Point {
    if (x < 0 or x > polyfill.WIDTH or y < 0 or y > polyfill.HEIGHT) return null;
    return .{ .x = @intCast(x), .y = @intCast(y) };
}

const Reader = struct {
    b: []const u8,
    p: usize = 0,

    fn take(self: *Reader, n: usize) ?[]const u8 {
        if (self.p + n > self.b.len) return null;
        self.p += n;
        return self.b[self.p - n .. self.p];
    }

    fn byte(self: *Reader) ?u8 {
        return (self.take(1) orelse return null)[0];
    }

    fn varint(self: *Reader) ?usize {
        const lo = self.byte() orelse return null;
        if (lo & 0x80 == 0) return lo;
        return (lo & 0x7F) | (@as(usize, self.byte() orelse return null) << 7);
    }

    fn zigzag(self: *Reader) ?i32 {
        const v: i32 = @intCast(self.varint() orelse return null);
        return if (v & 1 != 0) -((v + 1) >> 1) else v >> 1;
    }

    /// A vertex step: one nibble byte, or 0x00 and two zigzag varints.
    fn step(self: *Reader) ?[2]i32 {
        if (self.p < self.b.len and self.b[self.p] == 0) {
            self.p += 1;
            return .{ self.zigzag() orelse return null, self.zigzag() orelse return null };
        }
        return self.nibbles();
    }

    fn nibbles(self: *Reader) ?[2]i32 {
        const b = self.byte() orelse return null;
        if (b & 15 == 0 or b >> 4 == 0) return null;
        return .{ @as(i32, b & 15) - 8, @as(i32, b >> 4) - 8 };
    }
};
