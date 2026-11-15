//! A fake file system for ring_test.zig and records_test.zig: one file in memory, reads that can
//! come back short or fail, seeks, and counters.
const std = @import("std");

pub const Fake = struct {
    path: []const u8,
    data: []const u8,
    pos: u32 = 0,
    open_n: u32 = 0,
    reads: u32 = 0,
    seeks: u32 = 0,
    short: u32 = 1 << 30, // the most one read returns
    fail_at: u32 = 1 << 30, // a read starting at or past this offset fails

    pub fn open(self: *Fake, path: []const u8) i32 {
        if (!std.mem.eql(u8, path, self.path)) return -33; // EFILNF
        self.open_n += 1;
        self.pos = 0;
        return 3;
    }
    pub fn read(self: *Fake, h: i32, dst: []u8) i32 {
        _ = h;
        self.reads += 1;
        if (self.pos >= self.fail_at) return -11;
        const n: u32 = @intCast(@min(dst.len, self.data.len - self.pos, self.short));
        @memcpy(dst[0..n], self.data[self.pos..][0..n]);
        self.pos += n;
        return @intCast(n);
    }
    pub fn seek(self: *Fake, h: i32, off: u32) i32 {
        _ = h;
        self.seeks += 1;
        if (off > self.data.len) return -64;
        self.pos = off;
        return @intCast(off);
    }
    pub fn close(self: *Fake, h: i32) void {
        _ = self;
        _ = h;
    }
};

pub fn put32(b: []u8, at: usize, v: u32) void {
    std.mem.writeInt(u32, b[at..][0..4], v, .little);
}
