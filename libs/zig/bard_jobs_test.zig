// The BARD job server and kernels (bard_jobs/): answers against independent
// references, the same bytes whether a job runs in one step or in slices (BARD
// slices between audio renders), and the cart's bad jobs refused, never run.
//   zig test libs/zig/bard_jobs_test.zig      (from the repo root)
const std = @import("std");
const L = @import("bard_jobs/layout.zig");
const K = @import("bard_jobs/kernels.zig");
const S = @import("bard_jobs/server.zig");
const zx0_pack = @import("depackers/zx0_pack.zig");
const zx0 = @import("depackers/zx0.zig");

/// A clock that moves 1000 cycles a read: a budget of 1 ends every slice.
const Tick = struct {
    var t: u32 = 0;
    pub fn now() u32 {
        t +%= 1000;
        return t;
    }
};
const NoClock = struct {
    pub fn now() u32 {
        return 0;
    }
};

const ARENA = 1 << 20;
var arena: [ARENA]u8 align(64) = undefined;
const BLOCK: u32 = 64;

fn mem() S.Mem {
    return .{ .base = @intFromPtr(&arena), .size = ARENA };
}
fn words(off: u32) [*]u32 {
    return @ptrCast(@alignCast(&arena[off]));
}
fn job(n: u32) *L.Job {
    return @ptrCast(@alignCast(&arena[BLOCK + 4 * L.HEAD_WORDS + 64 * (n & (L.SLOTS - 1))]));
}

fn setup() void {
    @memset(&arena, 0);
    const h = words(BLOCK);
    h[L.H.magic] = L.MAGIC;
    h[L.H.slots] = L.SLOTS;
}

fn post(n: u32, op: L.Op, a: []const u32) void {
    const j = job(n);
    j.op = @intFromEnum(op);
    for (a, 0..) |v, i| j.a[i] = v;
    j.done = L.NONE;
    j.seq = n;
}

/// Serve post 0..head with `Clock`, a budget of `budget` a call, to the end.
fn serveAll(comptime Clock: type, head: u32, budget: u32) !u32 {
    var s: S.Server(Clock, zx0) = .{};
    try std.testing.expect(s.open(mem(), BLOCK, 0));
    var turns: u32 = 0;
    while (s.step(head, budget) != .idle) turns += 1;
    return turns;
}

test "crc32: zlib's answer, per chunk and whole" {
    setup();
    @memcpy(arena[4096..][0..8], "12345678");
    @memcpy(arena[4104..][0..8], "abcdefgh");
    post(0, .crc32, &.{ 4096, 16, 3, 8192 });
    _ = try serveAll(NoClock, 1, 0xFFFF_FFFF);
    try std.testing.expectEqual(@as(u32, 0), job(0).err);
    try std.testing.expectEqual(std.hash.Crc32.hash("12345678"), words(8192)[0]);
    try std.testing.expectEqual(std.hash.Crc32.hash("abcdefgh"), words(8192)[1]);
    try std.testing.expectEqual(std.hash.Crc32.hash(arena[8192..][0..8]), job(0).result);
    try std.testing.expectEqual(@as(u32, 0), job(0).done);
}

test "zx0: the depacked bytes, sliced or not" {
    var input: [20000]u8 = undefined;
    for (&input, 0..) |*b, i| b.* = @truncate((i * 7) ^ (i >> 5));
    const image = try zx0_pack.pack(std.testing.allocator, &input, .{});
    defer std.testing.allocator.free(image);
    for ([_]bool{ false, true }) |sliced| {
        setup();
        @memcpy(arena[4096..][0..image.len], image);
        post(0, .zx0, &.{ 4096, @intCast(image.len), 65536, 32768 });
        const turns = if (sliced) try serveAll(Tick, 1, 1) else try serveAll(NoClock, 1, 0xFFFF_FFFF);
        try std.testing.expect(sliced == (turns > 1));
        try std.testing.expectEqual(@as(u32, input.len), job(0).result);
        try std.testing.expectEqualSlices(u8, &input, arena[65536..][0..input.len]);
    }
}

fn shapes(n: u32) void {
    const a: [*]L.Point = @ptrCast(@alignCast(&arena[8192]));
    const b: [*]L.Point = @ptrCast(@alignCast(&arena[8192 + 8 * 4096]));
    for (0..n) |i| {
        const k: i16 = @intCast(i);
        a[i] = .{ .x = k * 7 - 9000, .y = 4000 - k * 3, .z = k * 5 - 6000 };
        b[i] = .{ .x = 3000 - k * 2, .y = k * 4 - 5000, .z = 7000 - k * 3 };
    }
    const x: *L.Xform = @ptrCast(@alignCast(&arena[4096]));
    x.* = .{ .m = .{ 16384, 0, 0, 0, 16384, 0, 0, 0, 16384 }, .zoff = 32768, .cx = 160, .cy = 100, .w = 320, .h = 200,
        .stride = 320, .ztab = 4608, .ztab_n = 256, .zshift = 8, .shade_shift = 6 };
    const zt = words(4608);
    for (0..256) |d| zt[d] = if (d == 0) 0 else @intCast(@as(u32, 160 << 16) / @as(u32, @intCast(d * 256)));
}

test "xform: a point projects as the formula says; sliced = whole" {
    setup();
    shapes(1000);
    post(0, .xform, &.{ 1000, 8192, 8192 + 8 * 4096, 128, 4096, 131072 });
    _ = try serveAll(NoClock, 1, 0xFFFF_FFFF);
    const whole = try std.testing.allocator.dupe(u32, words(131072)[0..1000]);
    defer std.testing.allocator.free(whole);
    // Point 0: t = 128 halfway, x = (-9000 + 3000) / 2 = -3000, y = -500, z = 500 -> depth 33268, index 129.
    const r: i32 = @intCast(words(4608)[129]);
    const sx = 160 + ((-3000 * r) >> 16);
    const sy = 100 + ((-500 * r) >> 16);
    try std.testing.expectEqual(@as(u32, 129 >> 6) << 24 | @as(u32, @intCast(sy * 320 + sx)), whole[0]);
    setup();
    shapes(1000);
    post(0, .xform, &.{ 1000, 8192, 8192 + 8 * 4096, 128, 4096, 131072 });
    _ = try serveAll(Tick, 1, 1);
    try std.testing.expectEqualSlices(u32, whole, words(131072)[0..1000]);
}

test "particles: gravity, the floor, respawn; sliced = whole" {
    setup();
    const p: *L.Physics = @ptrCast(@alignCast(&arena[4096]));
    p.* = .{ .gravity = 1 << 14, .floor = 180 << 16, .bounce = 160, .rest = 1 << 15, .w = 320, .h = 200, .stride = 320,
        .ex = 160 << 16, .ey = 170 << 16, .spread = 1 << 16, .lift = -(4 << 16) };
    const in: [*]L.Particle = @ptrCast(@alignCast(&arena[8192]));
    in[0] = .{ .x = 10 << 16, .y = 50 << 16, .vx = 1 << 16, .vy = 0 };
    in[1] = .{ .x = 10 << 16, .y = (180 << 16) - 1, .vx = 0, .vy = 1 << 16 }; // hits the floor: bounces
    in[2] = .{ .x = 0, .y = 50 << 16, .vx = -(1 << 16), .vy = 0 }; // leaves the plane: respawns
    post(0, .particles, &.{ 600, 8192, 8192 + 16 * 600, 4096, 65536, 7 });
    _ = try serveAll(NoClock, 1, 0xFFFF_FFFF);
    const st: [*]L.Particle = @ptrCast(@alignCast(&arena[8192 + 16 * 600]));
    try std.testing.expectEqual(L.Particle{ .x = 11 << 16, .y = (50 << 16) + (1 << 14), .vx = 1 << 16, .vy = 1 << 14 }, st[0]);
    try std.testing.expectEqual(@as(i32, 180 << 16), st[1].y);
    try std.testing.expectEqual(-(((1 << 16) + (1 << 14)) * 160 >> 8), st[1].vy);
    try std.testing.expectEqual(@as(i32, 160 << 16), st[2].x);
    try std.testing.expectEqual(@as(u32, 50 * 320 + 11), words(65536)[0]);
    const whole = try std.testing.allocator.dupe(u8, arena[8192 + 16 * 600 ..][0 .. 16 * 600]);
    defer std.testing.allocator.free(whole);
    _ = try serveAll(Tick, 1, 1);
    try std.testing.expectEqualSlices(u8, whole, arena[8192 + 16 * 600 ..][0 .. 16 * 600]);
}

test "refused: out of the cart, misaligned, unknown op, overlapping; the next job still runs" {
    setup();
    post(0, .crc32, &.{ ARENA - 8, 16, 3, 8192 }); // past the cart's memory
    post(1, .crc32, &.{ 4098, 16, 3, 8192 }); // misaligned
    post(2, @enumFromInt(99), &.{});
    post(3, .particles, &.{ 10, 8192, 8192 + 16, 4096, 65536, 0 }); // in and out overlap
    post(4, .crc32, &.{ 4096, 8, 3, 8192 });
    _ = try serveAll(NoClock, 5, 0xFFFF_FFFF);
    const want = [_]L.Err{ .range, .alignment, .bad_op, .data, .ok };
    for (want, 0..) |e, i| {
        try std.testing.expectEqual(@intFromEnum(e), job(@intCast(i)).err);
        try std.testing.expectEqual(@as(u32, @intCast(i)), job(@intCast(i)).done);
    }
}

test "a slot not whole yet is not served" {
    setup();
    post(0, .crc32, &.{ 4096, 8, 3, 8192 });
    job(0).seq = L.NONE; // the seq store not landed
    var s: S.Server(NoClock, zx0) = .{};
    try std.testing.expect(s.open(mem(), BLOCK, 0));
    try std.testing.expectEqual(S.Progress.waiting, s.step(1, 0xFFFF_FFFF));
    try std.testing.expectEqual(L.NONE, job(0).done);
    job(0).seq = 0;
    try std.testing.expectEqual(S.Progress.idle, s.step(1, 0xFFFF_FFFF));
    try std.testing.expectEqual(@as(u32, 0), job(0).done);
}

test "kernels hash: deterministic, every bit moves" {
    try std.testing.expectEqual(K.hash(3, 9), K.hash(3, 9));
    try std.testing.expect(K.hash(3, 9) != K.hash(4, 9) and K.hash(3, 9) != K.hash(3, 10));
}
