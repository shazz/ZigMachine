// KOS's C: (docs/KOS_FAT.md F5): ZIGGY cannot see the SD card, glass can. The cart's
// env.kosDriveRead (cycles/bkosdrive.c) writes a request block at window end - KOS_DRIVE_FROM_TOP
// (map_cart.zig) and spins; this server, polled from its own thread at ~2 kHz (startThread), reads
// the sectors off the SD card's partition into the window at the request's offset, then answers:
// KD_DONE the sectors read (0 refused), KD_ACK the request's sequence, last. Read-only: the
// partition is mounted read-only by Linux, so reading it raw is safe; nothing is ever written.
// The rules are host/disk.h's host_kos_drive_read, so C: answers alike everywhere.
const std = @import("std");
const linux = std.os.linux;
const mc = @import("map_cart.zig");
const kos_file = @import("kos_file.zig");
const net_card = @import("net_card.zig");
const layout = @import("layout.zig");
const HD_DIR = layout.ROOT ++ "/" ++ layout.HD; // C:\ for writes: Linux's own view of the card (KESTREL layout)
const layout_root: [*:0]const u8 = layout.ROOT;

pub const SECTOR = 512;
pub const PARTITION = "/dev/mmcblk0p1"; // the SD card's FAT32 partition: C:

/// Where the sectors come from: the partition (a read-only fd on the board), a file or bytes in tests.
pub const Source = struct {
    ctx: *anyopaque,
    read_fn: *const fn (ctx: *anyopaque, sector: u64, dst: []u8) bool, // the whole run, or false

    /// Sectors off a file descriptor (pread: no shared offset with anyone).
    pub fn fd(handle: *const i32) Source {
        return .{ .ctx = @ptrCast(@constCast(handle)), .read_fn = fdRead };
    }
};

fn fdRead(ctx: *anyopaque, sector: u64, dst: []u8) bool {
    const handle: *const i32 = @ptrCast(@alignCast(ctx));
    var got: usize = 0;
    while (got < dst.len) {
        const rc = linux.pread(handle.*, dst[got..].ptr, dst.len - got, @intCast(sector * SECTOR + got));
        if (linux.errno(rc) != .SUCCESS or rc == 0) return false;
        got += rc;
    }
    return true;
}

pub const Server = struct {
    words: []volatile u32, // the cart window, index 0 = CART_CPU_BASE
    src: Source,
    served: u32 = 0,
    buf: [mc.KOS_DRIVE_MAX_SECTORS * SECTOR]u8 = undefined,

    fn block(self: *Server) *volatile [mc.KOS_DRIVE_WORDS]u32 {
        return self.words[(self.words.len * 4 - mc.KOS_DRIVE_FROM_TOP) / 4 ..][0..mc.KOS_DRIVE_WORDS];
    }

    /// One look at the block: a whole request not yet answered is served. True if one was.
    pub fn poll(self: *Server) bool {
        const w = self.block();
        if (w[mc.KD_MAGIC] != mc.KOS_DRIVE_MAGIC) return false;
        const seq = w[mc.KD_SEQ];
        if (seq == 0 or w[mc.KD_ACK] == seq) return false; // answered: the firmware has not moved on yet
        const unit = w[mc.KD_UNIT];
        const sector = w[mc.KD_SECTOR];
        const count = w[mc.KD_COUNT];
        const offset = w[mc.KD_OFFSET];
        if (w[mc.KD_CHECK] != ~(mc.KOS_DRIVE_MAGIC ^ seq ^ unit ^ sector ^ count ^ offset)) return false; // half-written
        w[mc.KD_DONE] = self.serve(unit, sector, count, offset);
        w[mc.KD_ACK] = seq;
        self.served +%= 1;
        return true;
    }

    fn serve(self: *Server, unit: u32, sector: u32, count: u32, offset: u32) u32 {
        if (unit != mc.KOS_DRIVE_UNIT_C or count == 0 or count > mc.KOS_DRIVE_MAX_SECTORS) return 0;
        const n = count * SECTOR;
        if (offset % 4 != 0 or @as(u64, offset) + n > self.words.len * 4 - mc.KOS_DRIVE_FROM_TOP) return 0;
        const bytes = self.buf[0..n];
        if (!self.src.read_fn(self.src.ctx, sector, bytes)) return 0;
        const dst = self.words[offset / 4 ..][0 .. n / 4];
        for (dst, 0..) |*d, i| d.* = std.mem.readInt(u32, bytes[i * 4 ..][0..4], .little);
        return count;
    }
};

/// The board's server: the partition opened read-only, polled every 500 us for glass's life, and
/// C:'s writes (kos_file.zig) polled by the same thread, so a write and a sector read never overlap.
/// No partition (a card with none, a desk run): no thread, the firmware's requests time out to 0.
pub fn startThread(words: []volatile u32) void {
    const S = struct {
        var handle: i32 = -1;
        var server: Server = undefined;
        var files: ?kos_file.Server = null;
        var net: net_card.Card = undefined; // ZIGNIC (docs/GEM_NET.md N2): env.netOp served on Linux's sockets
        fn loop() void {
            const ts = linux.timespec{ .sec = 0, .nsec = 500_000 };
            while (true) {
                _ = server.poll();
                if (files) |*f| _ = f.poll();
                while (net.poll()) {} // a cart may post several ops a frame: each answered at once
                _ = linux.nanosleep(&ts, null);
            }
        }
        // A write went through Linux's FAT: the partition's cached sectors may be stale for raw reads.
        fn dropCache() void {
            _ = linux.fadvise(handle, 0, 0, linux.POSIX_FADV.DONTNEED);
        }
    };
    const rc = linux.open(PARTITION, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return std.log.warn("C: {s}: {t} (KOS's C: will not answer)", .{ PARTITION, linux.errno(rc) });
    S.handle = @intCast(rc);
    S.server = .{ .words = words, .src = Source.fd(&S.handle) };
    S.net = .{ .words = words };
    const hd = linux.open(HD_DIR, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
    if (linux.errno(hd) == .SUCCESS)
        S.files = .{ .words = words, .be = .{ .root = @intCast(hd), .mount_point = layout_root, .after = S.dropCache } }
    else
        std.log.warn("C: {s}: {t} (C:'s writes will not answer)", .{ HD_DIR, linux.errno(hd) });
    const t = std.Thread.spawn(.{}, S.loop, .{}) catch |err| return std.log.warn("C: server thread: {t}", .{err});
    t.detach();
}

const T = struct {
    var disk: [8 * SECTOR]u8 = undefined;
    var fail = false;
    fn read(_: *anyopaque, sector: u64, dst: []u8) bool {
        if (fail or sector * SECTOR + dst.len > disk.len) return false;
        @memcpy(dst, disk[@intCast(sector * SECTOR)..][0..dst.len]);
        return true;
    }
    var dummy: u8 = 0;
    const src = Source{ .ctx = &dummy, .read_fn = read };
};

/// The block as cycles/bkosreq.h writes it.
fn ask(words: []volatile u32, seq: u32, unit: u32, sector: u32, count: u32, offset: u32) void {
    const w = words[(words.len * 4 - mc.KOS_DRIVE_FROM_TOP) / 4 ..][0..mc.KOS_DRIVE_WORDS];
    w.* = .{ mc.KOS_DRIVE_MAGIC, seq, unit, sector, count, offset, ~(mc.KOS_DRIVE_MAGIC ^ seq ^ unit ^ sector ^ count ^ offset), 0, 0 };
}

fn answer(words: []volatile u32) [2]u32 {
    const at = (words.len * 4 - mc.KOS_DRIVE_FROM_TOP) / 4;
    return .{ words[at + mc.KD_DONE], words[at + mc.KD_ACK] };
}

test "a request is served once: the sectors land at its offset, then the count and the sequence" {
    for (&T.disk, 0..) |*b, i| b.* = @truncate(i * 7 + 1);
    var win = [_]u32{0} ** 4096; // 16 KiB
    var s = Server{ .words = &win, .src = T.src };
    try std.testing.expect(!s.poll()); // no block
    ask(&win, 1, 2, 3, 2, 0x100);
    try std.testing.expect(s.poll());
    try std.testing.expectEqual([2]u32{ 2, 1 }, answer(&win));
    try std.testing.expectEqualSlices(u8, T.disk[3 * SECTOR ..][0 .. 2 * SECTOR], std.mem.sliceAsBytes(win[0x40..][0 .. 2 * SECTOR / 4]));
    try std.testing.expectEqual(@as(u32, 0), win[0x40 + 2 * SECTOR / 4]); // not a byte more
    try std.testing.expect(!s.poll()); // answered: never served twice
    ask(&win, 2, 2, 0, 1, 0);
    try std.testing.expect(s.poll());
    try std.testing.expectEqual([2]u32{ 1, 2 }, answer(&win));
}

test "a refused request is answered 0, and a half-written one is not answered at all" {
    var win = [_]u32{0} ** 4096;
    var s = Server{ .words = &win, .src = T.src };
    const top: u32 = @intCast(win.len * 4 - mc.KOS_DRIVE_FROM_TOP);
    const bad = [_][4]u32{
        .{ 0, 0, 1, 0 }, // drive A is not served here
        .{ 2, 0, 0, 0 }, // no sectors
        .{ 2, 0, mc.KOS_DRIVE_MAX_SECTORS + 1, 0 }, // over one request
        .{ 2, 0, 1, 2 }, // a dst off a word
        .{ 2, 0, 1, top - SECTOR + 4 }, // into the top block's words
        .{ 2, 7, 2, 0 }, // past the partition's end
    };
    for (bad, 10..) |b, seq| {
        ask(&win, @intCast(seq), b[0], b[1], b[2], b[3]);
        try std.testing.expect(s.poll());
        try std.testing.expectEqual([2]u32{ 0, @intCast(seq) }, answer(&win));
    }
    T.fail = true;
    defer T.fail = false;
    ask(&win, 20, 2, 0, 1, 0);
    try std.testing.expect(s.poll()); // an I/O error is an answer too
    try std.testing.expectEqual([2]u32{ 0, 20 }, answer(&win));
    ask(&win, 21, 2, 0, 1, 0);
    win[(win.len * 4 - mc.KOS_DRIVE_FROM_TOP) / 4 + mc.KD_CHECK] ^= 1;
    try std.testing.expect(!s.poll());
    try std.testing.expectEqual([2]u32{ 0, 0 }, answer(&win));
}
