// --------------------------------------------------------------------------
// STNICCC 2000 scene stream decoder. The format is documented in format.txt of
// github.com/dabadab/st-niccc-2000-html5: per frame a flags byte, an optional
// palette update, an optional shared vertex list, then polygons until an end
// marker. The stream is cut into 64 KB blocks and a frame never crosses one,
// which is what lets the ST (and this scene) load it a block at a time from
// the disk. Pure (no ZigOS), so it is natively tested at the bottom.
// --------------------------------------------------------------------------
const std = @import("std");

pub const BLOCK = 64 * 1024;
pub const MAX_POLY_VERTS: usize = 15;
pub const MAX_VERTS: usize = 255;

pub const Flags = struct { clear: bool, palette: bool, indexed: bool };
pub const Point = struct { x: u8, y: u8 };
pub const Poly = struct { color: u8, n: u8, pts: [MAX_POLY_VERTS]Point };

pub const Error = error{ Truncated, ReadFailed, BadVertexIndex, BadPolygon };

/// Where the bytes come from, one 64 KB block at a time: the disk in the scene,
/// a byte slice in the tests. Fills `dst` with block `index` and returns how
/// many bytes of it exist (0 = nothing there).
pub const Source = struct {
    ctx: *anyopaque,
    readFn: *const fn (ctx: *anyopaque, index: u32, dst: *[BLOCK]u8) usize,
};

/// A Source over bytes already in memory.
pub const SliceSource = struct {
    bytes: []const u8,

    pub fn source(self: *SliceSource) Source {
        return .{ .ctx = self, .readFn = read };
    }
    fn read(ctx: *anyopaque, index: u32, dst: *[BLOCK]u8) usize {
        const self: *SliceSource = @ptrCast(@alignCast(ctx));
        const start = @as(usize, index) * BLOCK;
        if (start >= self.bytes.len) return 0;
        const n = @min(BLOCK, self.bytes.len - start);
        @memcpy(dst[0..n], self.bytes[start..][0..n]);
        return n;
    }
};

const NONE: u32 = std.math.maxInt(u32);

pub const Stream = struct {
    source: Source,
    buf: *[BLOCK]u8, // the block currently loaded
    loaded: u32 = NONE,
    loaded_len: usize = 0,
    pos: u32 = 0, // absolute offset in the stream
    done: bool = false, // the $FD end-of-stream marker was read
    indexed: bool = false, // the current frame names its vertices by index
    n_verts: usize = 0,
    verts: [MAX_VERTS]Point = undefined,

    pub fn seek(self: *Stream, pos: u32) void {
        self.pos = pos;
        self.done = false;
    }

    fn byte(self: *Stream) Error!u8 {
        const index: u32 = self.pos / BLOCK;
        if (index != self.loaded) {
            self.loaded_len = self.source.readFn(self.source.ctx, index, self.buf);
            if (self.loaded_len == 0) {
                self.loaded = NONE;
                return error.ReadFailed;
            }
            self.loaded = index;
        }
        const within = self.pos % BLOCK;
        if (within >= self.loaded_len) return error.Truncated;
        self.pos += 1;
        return self.buf[within];
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
                self.pos = std.mem.alignForward(u32, self.pos, BLOCK);
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

fn testStream(src: *SliceSource, buf: *[BLOCK]u8) Stream {
    return .{ .source = src.source(), .buf = buf };
}

test "an indexed frame with a palette, then a plain frame, then the end" {
    const data = [_]u8{
        0x07, 0x80, 0x01, 0x07, 0x77, 0x07, 0x00, // clear+palette+indexed; colours 0 and 15
        3, 0, 0, 10, 0, 0, 10, // three shared vertices
        0x23, 0, 1, 2, 0xFF, // colour 2, 3 vertices by index; end of frame
        0x00, 0x13, 5, 6, 7, 8, 9, 10, 0xFD, // plain frame, colour 1; end of stream
    };
    var src = SliceSource{ .bytes = &data };
    var buf: [BLOCK]u8 = undefined;
    var s = testStream(&src, &buf);
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

test "$FE skips to the next 64 KB block, which is loaded on demand" {
    const data = try std.testing.allocator.alloc(u8, BLOCK + 2);
    defer std.testing.allocator.free(data);
    @memset(data, 0);
    data[1] = 0xFE;
    data[BLOCK + 1] = 0xFD;
    var src = SliceSource{ .bytes = data };
    var buf: [BLOCK]u8 = undefined;
    var s = testStream(&src, &buf);
    var pal = [_]u16{0} ** 16;
    var poly: Poly = undefined;
    _ = try s.beginFrame(&pal);
    try expect(!try s.nextPoly(&poly));
    try expectEqual(@as(u32, BLOCK), s.pos);
    _ = try s.beginFrame(&pal);
    try expect(!try s.nextPoly(&poly));
    try expect(s.done);
    try expectEqual(@as(u32, 1), s.loaded);
}

test "seeking back re-reads an earlier frame" {
    const data = [_]u8{ 0x00, 0x13, 1, 2, 3, 4, 5, 6, 0xFF, 0x00, 0x23, 7, 8, 9, 10, 11, 12, 0xFD };
    var src = SliceSource{ .bytes = &data };
    var buf: [BLOCK]u8 = undefined;
    var s = testStream(&src, &buf);
    var pal = [_]u16{0} ** 16;
    var poly: Poly = undefined;
    _ = try s.beginFrame(&pal);
    _ = try s.nextPoly(&poly);
    _ = try s.nextPoly(&poly);
    s.seek(0);
    _ = try s.beginFrame(&pal);
    try expect(try s.nextPoly(&poly));
    try expectEqual(Point{ .x = 1, .y = 2 }, poly.pts[0]);
}

test "truncation, a missing block, a bad vertex index and a 2-vertex polygon are errors" {
    var pal = [_]u16{0} ** 16;
    var poly: Poly = undefined;
    var buf: [BLOCK]u8 = undefined;
    var cut_src = SliceSource{ .bytes = &[_]u8{ 0x02, 0x80 } };
    var cut = testStream(&cut_src, &buf);
    try std.testing.expectError(error.Truncated, cut.beginFrame(&pal));
    var gone = testStream(&cut_src, &buf);
    gone.seek(BLOCK);
    try std.testing.expectError(error.ReadFailed, gone.beginFrame(&pal));
    var bad_src = SliceSource{ .bytes = &[_]u8{ 0x04, 1, 3, 3, 0x03, 0, 1, 0 } };
    var bad = testStream(&bad_src, &buf);
    _ = try bad.beginFrame(&pal);
    try std.testing.expectError(error.BadVertexIndex, bad.nextPoly(&poly));
    var short_src = SliceSource{ .bytes = &[_]u8{ 0x00, 0x02, 1, 1, 2, 2 } };
    var short = testStream(&short_src, &buf);
    _ = try short.beginFrame(&pal);
    try std.testing.expectError(error.BadPolygon, short.nextPoly(&poly));
}
