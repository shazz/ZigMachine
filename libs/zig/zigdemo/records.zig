//! zigdemo records: a part's file of FIXED-STRIDE records (one an animation frame: a pose, a list,
//! its colours, its cameras) read ONE record a picture, a frame AHEAD, into one of two aligned
//! buffers, for animations too big for the assets arena. A seek (a debug jump, an A-B loop) is one
//! seek of the file: the record is read when the picture asks for it.
//! The demo reads and checks its own header (open() hands it the first bytes), then gives the
//! layout: record f is at `base + f * stride`, `count` records. Over the same `Files` contract as
//! zigdemo.assets, plus seek(self, h, off) i32 (the new position, < 0 an error).

const NONE: u32 = 0xFFFF_FFFF;

pub fn Records(comptime F: type) type {
    return struct {
        const Self = @This();
        files: *F,
        bufs: [2][]align(16) u8, // the biggest stride each (the demo allocates them)
        held: [2]u32 = .{ NONE, NONE },
        last: usize = 0, // the buffer the picture read last: a prefetch goes in the other
        h: i32 = -1,
        pos: u32 = 0, // the file position after the last read
        failed: bool = false,
        reads: u32 = 0,
        base: u32 = 0,
        stride: u32 = 0,
        count: u32 = 0,

        /// Opens `path` and reads its first hdr.len bytes into `hdr`; false (failed) if it cannot.
        pub fn open(self: *Self, path: []const u8, hdr: []u8) bool {
            self.h = self.files.open(path);
            if (self.h < 0) return self.fail();
            if (self.files.read(self.h, hdr) != @as(i32, @intCast(hdr.len))) return self.fail();
            self.pos = @intCast(hdr.len);
            return true;
        }

        /// The layout the demo read from its header; false (failed) if a record cannot fit a buffer.
        pub fn layout(self: *Self, base: u32, stride: u32, count: u32) bool {
            if (stride > self.bufs[0].len or stride > self.bufs[1].len) return self.fail();
            self.base = base;
            self.stride = stride;
            self.count = count;
            return true;
        }

        pub fn fail(self: *Self) bool {
            self.close();
            self.failed = true;
            return false;
        }

        pub fn close(self: *Self) void {
            if (self.h >= 0) self.files.close(self.h);
            self.h = -1;
        }

        /// Record f (read now if no buffer holds it); null when the file failed.
        pub fn get(self: *Self, f: u32) ?[]align(16) u8 {
            const i = self.find(f) orelse blk: {
                const o = self.last ^ 1;
                if (!self.load(f, o)) return null;
                break :blk o;
            };
            self.last = i;
            return self.bufs[i][0..self.stride];
        }

        /// Record f into the buffer the picture did not read last, if no buffer holds it yet.
        pub fn prefetch(self: *Self, f: u32) void {
            if (f >= self.count or self.find(f) != null) return;
            _ = self.load(f, self.last ^ 1);
        }

        fn find(self: *const Self, f: u32) ?usize {
            for (self.held, 0..) |h, i| if (h == f) return i;
            return null;
        }

        fn load(self: *Self, f: u32, i: usize) bool {
            if (self.h < 0 or f >= self.count) return false;
            const at = self.base + f * self.stride;
            if (self.pos != at and self.files.seek(self.h, at) != @as(i32, @intCast(at))) return self.fail();
            self.held[i] = NONE;
            const dst = self.bufs[i][0..self.stride];
            if (self.files.read(self.h, dst) != @as(i32, @intCast(dst.len))) return self.fail();
            self.pos = at + self.stride;
            self.held[i] = f;
            self.reads += 1;
            return true;
        }
    };
}
