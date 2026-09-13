// --------------------------------------------------------------------------
// STNICCC 2000 scene stream decoder. The format is documented in format.txt of
// github.com/dabadab/st-niccc-2000-html5: per frame a flags byte, an optional
// palette update, an optional shared vertex list, then polygons until an end
// marker. The stream is cut into 64 KB blocks and a frame never crosses one.
// Pure (no ZigOS), so it is natively tested at the bottom of this file.
// --------------------------------------------------------------------------
const std = @import("std");

pub const BLOCK: usize = 64 * 1024;
pub const MAX_POLY_VERTS: usize = 15;
pub const MAX_VERTS: usize = 255;

pub const Flags = struct { clear: bool, palette: bool, indexed: bool };
pub const Point = struct { x: u8, y: u8 };
pub const Poly = struct { color: u8, n: u8, pts: [MAX_POLY_VERTS]Point };

pub const Error = error{ Truncated, BadVertexIndex, BadPolygon };

pub const Stream = struct {
    data: []const u8,
    pos: usize = 0,
    done: bool = false, // the $FD end-of-stream marker was read
    indexed: bool = false, // the current frame names its vertices by index
    n_verts: usize = 0,
    verts: [MAX_VERTS]Point = undefined,

    pub fn rewind(self: *Stream) void {
        self.pos = 0;
        self.done = false;
    }

    fn byte(self: *Stream) Error!u8 {
        if (self.pos >= self.data.len) return error.Truncated;
        defer self.pos += 1;
        return self.data[self.pos];
    }
    fn word(self: *Stream) Error!u16 { // big endian, as the ST wrote it
        const hi = try self.byte();
        return (@as(u16, hi) << 8) | try self.byte();
    }

    // Read a frame's header. Palette words land in `pal` (ST 0RRR0GGG0BBB): bit 15
    // of the mask is colour 0 and bit 0 is colour 15, so walking the colours in
    // order walks the mask from its top bit down.
    pub fn beginFrame(self: *Stream, pal: *[16]u16) Error!Flags {
        const f = try self.byte();
        const flags = Flags{ .clear = f & 1 != 0, .palette = f & 2 != 0, .indexed = f & 4 != 0 };
        if (flags.palette) {
            const mask = try self.word();
            for (pal, 0..) |*c, i| {
                if (mask & (@as(u16, 0x8000) >> @intCast(i)) != 0) c.* = try self.word();
            }
        }
        self.indexed = flags.indexed;
        self.n_verts = 0;
        if (flags.indexed) {
            self.n_verts = try self.byte();
            for (self.verts[0..self.n_verts]) |*v| {
                const x = try self.byte();
                v.* = .{ .x = x, .y = try self.byte() };
            }
        }
        return flags;
    }

    // The frame's next polygon into `out`; false at the frame's end marker. $FE
    // also skips to the next 64 KB block, $FD also marks the end of the stream.
    pub fn nextPoly(self: *Stream, out: *Poly) Error!bool {
        const d = try self.byte();
        switch (d) {
            0xFF => return false,
            0xFE => {
                self.pos = std.mem.alignForward(usize, self.pos, BLOCK);
                return false;
            },
            0xFD => {
                self.done = true;
                return false;
            },
            else => {},
        }
        out.color = d >> 4;
        out.n = d & 0x0F;
        if (out.n < 3) return error.BadPolygon;
        for (out.pts[0..out.n]) |*p| p.* = try self.vertex();
        return true;
    }

    fn vertex(self: *Stream) Error!Point {
        if (self.indexed) {
            const i = try self.byte();
            if (i >= self.n_verts) return error.BadVertexIndex;
            return self.verts[i];
        }
        const x = try self.byte();
        return .{ .x = x, .y = try self.byte() };
    }
};

// --- tests ------------------------------------------------------------------
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "an indexed frame with a palette, then a plain frame, then the end" {
    const data = [_]u8{
        0x07, 0x80, 0x01, 0x07, 0x77, 0x07, 0x00, // clear+palette+indexed; colours 0 and 15
        3, 0, 0, 10, 0, 0, 10, // three shared vertices
        0x23, 0, 1, 2, 0xFF, // colour 2, 3 vertices by index; end of frame
        0x00, 0x13, 5, 6, 7, 8, 9, 10, 0xFD, // plain frame, colour 1; end of stream
    };
    var s = Stream{ .data = &data };
    var pal = [_]u16{0} ** 16;
    var poly: Poly = undefined;
    const f = try s.beginFrame(&pal);
    try expect(f.clear and f.palette and f.indexed);
    try expectEqual(@as(u16, 0x0777), pal[0]);
    try expectEqual(@as(u16, 0x0700), pal[15]);
    try expect(try s.nextPoly(&poly));
    try expectEqual(@as(u8, 2), poly.color);
    try expectEqual(Point{ .x = 10, .y = 0 }, poly.pts[1]);
    try expect(!try s.nextPoly(&poly));
    const f2 = try s.beginFrame(&pal);
    try expect(!f2.clear and !f2.indexed);
    try expect(try s.nextPoly(&poly));
    try expectEqual(Point{ .x = 9, .y = 10 }, poly.pts[2]);
    try expect(!try s.nextPoly(&poly));
    try expect(s.done);
}

test "$FE skips to the next 64 KB block" {
    var data = [_]u8{0} ** (BLOCK + 2);
    data[0] = 0x00;
    data[1] = 0xFE;
    data[BLOCK] = 0x00;
    data[BLOCK + 1] = 0xFD;
    var s = Stream{ .data = &data };
    var pal = [_]u16{0} ** 16;
    var poly: Poly = undefined;
    _ = try s.beginFrame(&pal);
    try expect(!try s.nextPoly(&poly));
    try expectEqual(BLOCK, s.pos);
    _ = try s.beginFrame(&pal);
    try expect(!try s.nextPoly(&poly));
    try expect(s.done);
}

test "a truncated frame, a bad vertex index and a 2-vertex polygon are errors" {
    var pal = [_]u16{0} ** 16;
    var poly: Poly = undefined;
    var cut = Stream{ .data = &[_]u8{ 0x02, 0x80 } };
    try std.testing.expectError(error.Truncated, cut.beginFrame(&pal));
    var bad = Stream{ .data = &[_]u8{ 0x04, 1, 3, 3, 0x03, 0, 1, 0 } };
    _ = try bad.beginFrame(&pal);
    try std.testing.expectError(error.BadVertexIndex, bad.nextPoly(&poly));
    var short = Stream{ .data = &[_]u8{ 0x00, 0x02, 1, 1, 2, 2 } };
    _ = try short.beginFrame(&pal);
    try std.testing.expectError(error.BadPolygon, short.nextPoly(&poly));
}
