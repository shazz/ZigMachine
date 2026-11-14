//! Tests for assets.zig over a fake file system: chunked loads (short reads too), progress,
//! two slots placed side by side, the prefetch of the next blob, waiting for a release, and
//! every failure (unknown id, full queue, missing file, empty, too big, a read error).
const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const assets = @import("assets.zig");

const Fake = struct {
    const File = struct { path: []const u8, data: []const u8 };
    files: []const File,
    short: u32 = 1 << 30, // the most one read returns (a short read)
    fail_at: u32 = 1 << 30, // a read starting at or past this offset fails
    pos: [4]u32 = .{ 0, 0, 0, 0 },
    which: [4]usize = .{ 0, 0, 0, 0 },
    open_n: u32 = 0,
    reads: u32 = 0,
    closed: u32 = 0,

    pub fn open(self: *Fake, path: []const u8) i32 {
        self.open_n += 1;
        for (self.files, 0..) |f, i| {
            if (!std.mem.eql(u8, f.path, path)) continue;
            const h = self.open_n % 4;
            self.pos[h] = 0;
            self.which[h] = i;
            return @intCast(h);
        }
        return -33; // EFILNF
    }
    pub fn size(self: *Fake, h: i32) i32 {
        return @intCast(self.files[self.which[@intCast(h)]].data.len);
    }
    pub fn read(self: *Fake, h: i32, dst: []u8) i32 {
        self.reads += 1;
        const hu: usize = @intCast(h);
        const d = self.files[self.which[hu]].data;
        if (self.pos[hu] >= self.fail_at) return -11;
        const n = @min(dst.len, d.len - self.pos[hu], self.short);
        @memcpy(dst[0..n], d[self.pos[hu]..][0..n]);
        self.pos[hu] += @intCast(n);
        return @intCast(n);
    }
    pub fn close(self: *Fake, h: i32) void {
        _ = h;
        self.closed += 1;
    }
};

const A = assets.Assets(Fake);
var arena_buf: [4096]u8 align(16) = undefined;

fn pattern(comptime n: usize, seed: u8) [n]u8 {
    var b: [n]u8 = undefined;
    for (&b, 0..) |*x, i| x.* = @truncate(i *% 7 +% seed);
    return b;
}
const big = pattern(1000, 1);
const mid = pattern(600, 2);
const huge = pattern(3000, 3);
const files = [_]Fake.File{
    .{ .path = "C:\\BIG.BIN", .data = &big },
    .{ .path = "C:\\MID.BIN", .data = &mid },
    .{ .path = "C:\\HUGE.BIN", .data = &huge },
    .{ .path = "C:\\NONE.BIN", .data = "" },
};
const table = [_]assets.Entry{
    .{ .path = "C:\\BIG.BIN" }, .{ .path = "C:\\MID.BIN" }, .{ .path = "C:\\HUGE.BIN" },
    .{ .path = "C:\\NONE.BIN" }, .{ .path = "C:\\GONE.BIN" },
};

fn make(fs: *Fake, arena: usize) A {
    return .{ .files = fs, .table = &table, .arena = arena_buf[0..arena], .chunk = 256 };
}
fn run(a: *A, n: usize) void {
    for (0..n) |_| a.update();
}

test "a blob loads a chunk an update, ready only after the last, the bytes the file's" {
    var fs = Fake{ .files = &files };
    var a = make(&fs, 4096);
    try a.request(0);
    try expectEqual(assets.State.queued, a.state(0));
    a.update(); // open + place
    try expectEqual(assets.State.loading, a.state(0));
    run(&a, 3);
    try expect(!a.ready(0));
    try expectEqual(@as(?[]align(16) const u8, null), a.bytes(0));
    a.update(); // the 4th chunk: 1000 = 3 x 256 + 232
    try expect(a.ready(0));
    try expectEqual(@as(u32, 4), fs.reads);
    try std.testing.expectEqualSlices(u8, &big, a.bytes(0).?);
    try expectEqual(@as(u32, 1), fs.closed);
}

test "short reads still assemble the file; progress climbs and reaches 1000 once" {
    var fs = Fake{ .files = &files, .short = 100 };
    var a = make(&fs, 4096);
    try a.request(1);
    var last: u32 = 0;
    var full: u32 = 0;
    for (0..20) |_| {
        a.update();
        const p = a.progress(1);
        try expect(p >= last);
        if (p == 1000 and last != 1000) full += 1;
        last = p;
    }
    try expectEqual(@as(u32, 1), full);
    try std.testing.expectEqualSlices(u8, &mid, a.bytes(1).?);
}

test "the next blob prefetches beside the current one, both aligned and apart" {
    var fs = Fake{ .files = &files };
    var a = make(&fs, 4096);
    try a.request(0);
    try a.request(1);
    run(&a, 20);
    try expect(a.ready(0) and a.ready(1));
    const b0 = a.bytes(0).?;
    const b1 = a.bytes(1).?;
    try expectEqual(@as(usize, 0), @intFromPtr(b1.ptr) % 16);
    try expect(@intFromPtr(b1.ptr) >= @intFromPtr(b0.ptr) + b0.len);
    try std.testing.expectEqualSlices(u8, &big, b0);
    try std.testing.expectEqualSlices(u8, &mid, b1);
}

test "a blob that cannot sit beside the current one waits for its release, without reopening" {
    var fs = Fake{ .files = &files };
    var a = make(&fs, 1500); // BIG (1000) + MID (600) > 1500
    try a.request(0);
    run(&a, 6);
    try a.request(1);
    run(&a, 5);
    try expectEqual(assets.State.queued, a.state(1));
    try expectEqual(@as(u32, 2), fs.open_n); // one look at its size, no retry a frame
    a.release(0);
    try expectEqual(assets.State.idle, a.state(0));
    run(&a, 4);
    try expect(a.ready(1));
    try std.testing.expectEqualSlices(u8, &mid, a.bytes(1).?);
}

test "a third request waits while both slots are held" {
    var fs = Fake{ .files = &files };
    var a = make(&fs, 4096);
    try a.request(0);
    try a.request(1);
    try a.request(0); // a repeat is a no-op
    try expectEqual(@as(usize, 2), a.queued);
    run(&a, 20);
    try a.request(3);
    run(&a, 3);
    try expectEqual(assets.State.queued, a.state(3));
}

test "an unknown id and a full queue are refused" {
    var fs = Fake{ .files = &files };
    var a = make(&fs, 4096);
    try std.testing.expectError(error.UnknownAsset, a.request(99));
    for (0..assets.queue_max) |_| {
        a.queue[a.queued] = 0;
        a.queued += 1;
    }
    try std.testing.expectError(error.QueueFull, a.request(1));
}

test "a missing, empty or too big file fails with its reason and frees the queue" {
    var fs = Fake{ .files = &files };
    var a = make(&fs, 2048);
    try a.request(4);
    a.update();
    try expectEqual(assets.State.failed, a.state(4));
    try expectEqual(assets.LoadError.NotFound, a.failed.?.why);
    try a.request(3);
    a.update();
    try expectEqual(assets.LoadError.Empty, a.failed.?.why);
    try a.request(2);
    a.update();
    try expectEqual(assets.LoadError.TooBig, a.failed.?.why);
    try expectEqual(@as(usize, 0), a.queued);
    try expectEqual(@as(u32, 2), fs.closed); // the opened ones are closed
}

test "a read error mid-file fails the load and frees its slot; a retry can load it" {
    var fs = Fake{ .files = &files, .fail_at = 512 };
    var a = make(&fs, 4096);
    try a.request(0);
    run(&a, 4);
    try expectEqual(assets.State.failed, a.state(0));
    try expectEqual(assets.LoadError.ReadFailed, a.failed.?.why);
    try expectEqual(@as(?u16, null), a.slots[0].id);
    fs.fail_at = 1 << 30;
    try a.request(0);
    run(&a, 6);
    try std.testing.expectEqualSlices(u8, &big, a.bytes(0).?);
}

test "releasing a loading blob closes its file; releasing an unknown id changes nothing" {
    var fs = Fake{ .files = &files };
    var a = make(&fs, 4096);
    try a.request(0);
    run(&a, 2);
    a.release(0);
    try expectEqual(@as(u32, 1), fs.closed);
    try expectEqual(assets.State.idle, a.state(0));
    a.release(7);
    try expectEqual(@as(usize, 0), a.queued);
}
