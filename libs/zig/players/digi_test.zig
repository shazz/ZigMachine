// Native tests for the native SNDH replays' recognition (digi.zig): `zig test`
// this file. The fixture is beat_dis.sndh's header, code and tables (its first
// 0x64 + 0x125A bytes); the samples are zeroes here, recognition never reads them.
// That the routines play what Musashi plays is fpga/tests/test_sndh_native.py's.
const std = @import("std");
const digi = @import("digi.zig");

const HEAD = @embedFile("testdata/beat_dis_head.bin");
const FILE_LEN = 426_486; // the real file's length: its samples end at its end
const BASE: u32 = 0x10002; // sndh_player.zig IMAGE_BASE
const CODE: u32 = 0x64; // where the header's INIT branch lands

var image: [FILE_LEN]u8 = undefined;

fn fresh() []u8 {
    @memset(&image, 0);
    @memcpy(image[0..HEAD.len], HEAD);
    return &image;
}

fn status(img: []const u8) digi.Status {
    return digi.recognise(img, BASE).status;
}

test "Beat Dis is recognised, its addresses taken from its own code" {
    const r = digi.recognise(fresh(), BASE);
    try std.testing.expectEqual(digi.Status.beat_dis, r.status);
    const d = r.driver.?;
    try std.testing.expectEqual(BASE + CODE, d.base);
    try std.testing.expectEqual(BASE + CODE + 0x1B4, d.handler.addr);
    try std.testing.expectEqual(BASE + CODE + 0x2A, d.handler.cur);
    try std.testing.expectEqual(BASE + CODE + 0x212, d.handler.table);
}

test "one byte changed in play is a near miss: the handler alone is not enough" {
    const img = fresh();
    img[CODE + 0x146 + 3] ^= 1; // addi.w #1 -> #0
    try std.testing.expectEqual(digi.Status.near_miss_sequencer, status(img));
}

test "a handler whose pointer is somewhere else is a near miss on the data" {
    const img = fresh();
    img[CODE + 0x1B4 + 7] +%= 4; // its `lea cur(pc)` now names END
    try std.testing.expectEqual(digi.Status.near_miss_data, status(img));
}

test "a sequence row of count 0 (65536 entries on a 68000) is refused" {
    const img = fresh();
    img[CODE + 0xE5E] = 0;
    try std.testing.expectEqual(digi.Status.near_miss_data, status(img));
}

test "a sample that ends past the file is refused" {
    // the last sample ends 24 bytes before the file does
    try std.testing.expectEqual(digi.Status.near_miss_data, status(fresh()[0 .. FILE_LEN - 0x20]));
}

test "no handler, no native path: the general case is silent" {
    var other = [_]u8{0x4E} ** 4096;
    try std.testing.expectEqual(digi.Status.musashi, status(&other));
    const img = fresh();
    img[CODE + 0x1B4 + 0x51] = 0x75; // the handler's rte -> rts
    try std.testing.expectEqual(digi.Status.musashi, status(img));
}

test "the code moved by a longer header is still found" {
    var moved: [FILE_LEN + 2]u8 = undefined;
    const img = fresh();
    @memcpy(moved[0..CODE], img[0..CODE]);
    @memcpy(moved[CODE + 2 ..], img[CODE..]);
    for ([_]usize{ 2, 6, 10 }) |disp| moved[disp + 1] += 2; // the three header branches
    const r = digi.recognise(&moved, BASE);
    try std.testing.expectEqual(digi.Status.beat_dis, r.status);
    try std.testing.expectEqual(BASE + CODE + 2, r.driver.?.base);
}

// --- the routines on a recording bus ---------------------------------------
var ram: [FILE_LEN + 0x20000]u8 = undefined;
var psg_latch: u8 = 0;
var psg: [16]u8 = undefined;
var log: [64][2]u8 = undefined;
var log_n: usize = 0;

const Bus = struct {
    pub fn read8(a: u32) u8 {
        const x = a & 0xFFFFFF;
        if (x == 0xFF8800) return psg[psg_latch];
        return if (x < ram.len) ram[x] else 0;
    }
    pub fn write8(a: u32, v: u8) void {
        const x = a & 0xFFFFFF;
        if (x == 0xFF8800) {
            psg_latch = v & 15;
        } else if (x == 0xFF8802) {
            psg[psg_latch] = v;
            log[log_n] = .{ psg_latch, v };
            log_n += 1;
        } else if (x < ram.len) ram[x] = v;
    }
    pub fn write16(a: u32, v: u16) void {
        write8(a, @truncate(v >> 8)); // the PSG takes the even byte only
        if (a & 0xFFFFFF < 0xFF8800) write8(a + 1, @truncate(v));
    }
};

test "init plays entry 0 and silences the YM; each interrupt is one byte through the table" {
    const d = digi.recognise(fresh(), BASE).driver.?;
    @memset(&ram, 0);
    @memcpy(ram[BASE..][0..FILE_LEN], &image);
    psg = [_]u8{0xFF} ** 16;
    log_n = 0;
    ram[d.base + 0x125A] = 0x7F; // the first sample byte
    digi.beat_dis.call(Bus, d, 0);
    const want_init = [_][2]u8{ .{ 0, 0 }, .{ 1, 0 }, .{ 2, 0 }, .{ 3, 0 }, .{ 4, 0 }, .{ 5, 0 }, .{ 7, 0xFF } };
    try std.testing.expectEqualSlices([2]u8, &want_init, log[0..log_n]);
    try std.testing.expectEqual(d.handler.addr, std.mem.readInt(u32, ram[0x134..][0..4], .big));
    log_n = 0;
    digi.handler.irq(Bus, d.handler);
    const e = d.handler.table + 0xFF * 8; // 0x7F + 0x80
    const want = [_][2]u8{ .{ 8, ram[e + 1] }, .{ 9, ram[e + 3] }, .{ 10, ram[e + 5] } };
    try std.testing.expectEqualSlices([2]u8, &want, log[0..log_n]);
    try std.testing.expectEqual(d.base + 0x125A + 1, std.mem.readInt(u32, ram[d.base + 0x2A ..][0..4], .big));
}

test "play moves on only once the pointer is PAST the end, and wraps at the -1 to entry 0" {
    const d = digi.recognise(fresh(), BASE).driver.?;
    @memset(&ram, 0);
    @memcpy(ram[BASE..][0..FILE_LEN], &image);
    digi.beat_dis.call(Bus, d, 0);
    const cur = d.base + 0x2A;
    const end = std.mem.readInt(u32, ram[d.base + 0x2E ..][0..4], .big);
    std.mem.writeInt(u32, ram[cur..][0..4], end, .big);
    digi.beat_dis.call(Bus, d, 8);
    try std.testing.expectEqual(end, std.mem.readInt(u32, ram[cur..][0..4], .big)); // at the end: not yet
    std.mem.writeInt(u32, ram[cur..][0..4], end + 1, .big);
    digi.beat_dis.call(Bus, d, 8);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, ram[d.base + 0x36 ..][0..2], .big));
    var last: u16 = 0; // the playlist's last entry: the next one is the -1
    while (std.mem.readInt(u32, ram[d.base + 0xA12 + (@as(u32, last) + 1) * 8 ..][0..4], .big) != 0xFFFF_FFFF) last += 1;
    std.mem.writeInt(u16, ram[d.base + 0x36 ..][0..2], last, .big);
    std.mem.writeInt(u32, ram[cur..][0..4], end + 1, .big);
    digi.beat_dis.call(Bus, d, 8);
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, ram[d.base + 0x36 ..][0..2], .big));
}

// --- mode 3: what a sample byte means ----------------------------------------
/// The table's three volumes for `byte`, summed as amplitudes (3 dB a step).
fn level(byte: u8) f64 {
    const e = CODE + 0x212 + @as(u32, byte ^ 0x80) * 8; // the handler's addi.b #$80, lsl #3
    var sum: f64 = 0;
    for ([_]u32{ 1, 3, 5 }) |k| {
        const v = HEAD[e + k] & 15;
        if (v != 0) sum += std.math.pow(f64, 2.0, (@as(f64, @floatFromInt(v)) - 15.0) / 2.0);
    }
    return sum;
}

fn correlation(comptime f: fn (u8) f64) f64 {
    var sx: f64 = 0;
    var sy: f64 = 0;
    for (0..256) |i| sx += level(@intCast(i));
    for (0..256) |i| sy += f(@intCast(i));
    const mx, const my = .{ sx / 256, sy / 256 };
    var xy: f64 = 0;
    var xx: f64 = 0;
    var yy: f64 = 0;
    for (0..256) |i| {
        const x, const y = .{ level(@intCast(i)) - mx, f(@intCast(i)) - my };
        xy += x * y;
        xx += x * x;
        yy += y * y;
    }
    return xy / @sqrt(xx * yy);
}

fn asLinear(b: u8) f64 {
    return @floatFromInt(@as(i8, @bitCast(digi.handler.linear(b))));
}

fn asSigned(b: u8) f64 {
    return @floatFromInt(@as(i8, @bitCast(b)));
}

test "Beat Dis's bytes are unsigned and inverted: linear() follows the YM level, the raw signed byte does not" {
    _ = fresh();
    try std.testing.expect(level(0) > level(0x7F) and level(0x80) > level(0xFF)); // falls in each half
    try std.testing.expectEqual(@as(f64, 0), level(0xFF)); // 255 is silence
    try std.testing.expect(correlation(asLinear) > 0.97); // measured 0.979
    try std.testing.expect(correlation(asSigned) < 0.6); // measured 0.49: the fold at the midpoint
}
