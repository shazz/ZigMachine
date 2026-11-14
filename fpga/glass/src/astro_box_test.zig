// ASTROLABE's mailbox server (astro_box.zig) against a mailbox and a DDR window as arrays,
// written the way fpga/cycles/bastro.c writes them.
const std = @import("std");
const box = @import("astro_box.zig");
const ops = @import("astro_ops");
const abi = ops.abi;
const t = std.testing;

const MEM_OFF: u32 = 0x1004; // where the cart's memory starts in the window: word-aligned, not 8
const MEM: u32 = 0x10000;
var mbox: [1024]u32 = undefined;
var ddr: [(MEM_OFF + MEM) / 4]u32 = undefined;
var mirror: [MEM]u8 align(8) = undefined;

fn fresh() box.Server {
    @memset(&mbox, 0);
    @memset(&ddr, 0xDEADBEEF);
    return .{ .box = &mbox, .ddr = &ddr, .mirror = &mirror };
}

fn post(seq: u32, count: u32) void {
    mbox[box.COUNT] = count;
    mbox[box.MEM_OFF] = MEM_OFF;
    mbox[box.MEM_SIZE] = MEM;
    mbox[box.SEQ] = seq; // the doorbell, last
}

fn put64(words: []u32, at: u32, v: f64) void {
    const b: u64 = @bitCast(v);
    words[at] = @truncate(b);
    words[at + 1] = @truncate(b >> 32);
}

fn get64(words: []const u32, at: u32) f64 {
    return @bitCast(@as(u64, words[at + 1]) << 32 | words[at]);
}

fn scalarDesc(i: u32, op: u32, a: f64, b: f64) void {
    const at = box.DESC0 + i * abi.DESC_WORDS;
    mbox[at + abi.W_OP] = op;
    put64(&mbox, at + abi.W_S0, a);
    put64(&mbox, at + abi.W_S1, b);
}

test "a scalar request: TAKEN, the result, ARM-served status, DONE last; served once" {
    var s = fresh();
    try t.expect(!s.poll()); // SEQ 0: nothing
    scalarDesc(0, abi.OP_DIV, 1, 3);
    scalarDesc(1, abi.OP_SIN, 0.5, 0);
    post(7, 2);
    try t.expect(s.poll());
    try t.expectEqual(@as(u32, 7), mbox[box.TAKEN]);
    try t.expectEqual(@as(u32, 7), mbox[box.DONE]);
    try t.expectEqual(abi.ST_OK, mbox[box.RET]);
    const d1 = box.DESC0 + abi.DESC_WORDS;
    try t.expectEqual(abi.ST_OK | abi.SERVED_ARM, mbox[box.DESC0 + abi.W_STATUS]);
    try t.expectEqual(@as(f64, 1.0 / 3.0), get64(&mbox, box.DESC0 + abi.W_R));
    try t.expectEqual(@sin(@as(f64, 0.5)), get64(&mbox, d1 + abi.W_R)); // the machine's own kernel
    try t.expect(!s.poll()); // the same SEQ is not served twice
}

test "an array op is staged from DDR and back: AXPY in place" {
    var s = fresh();
    const a: u32 = 0x100;
    const b: u32 = 0x200;
    for (0..4) |i| {
        put64(&ddr, (MEM_OFF + a) / 4 + 2 * @as(u32, @intCast(i)), @floatFromInt(i));
        put64(&ddr, (MEM_OFF + b) / 4 + 2 * @as(u32, @intCast(i)), 10);
    }
    const at = box.DESC0;
    mbox[at + abi.W_OP] = abi.OP_AXPY;
    mbox[at + abi.W_N] = 4;
    mbox[at + abi.W_A] = a;
    mbox[at + abi.W_B] = b;
    put64(&mbox, at + abi.W_S0, 3);
    post(1, 1);
    try t.expect(s.poll());
    for (0..4) |i| try t.expectEqual(10 + 3 * @as(f64, @floatFromInt(i)), get64(&ddr, (MEM_OFF + b) / 4 + 2 * @as(u32, @intCast(i))));
    try t.expectEqual(@as(u32, 0xDEADBEEF), ddr[(MEM_OFF + b) / 4 + 8]); // nothing past the span
}

test "a cart's bad arrays and a bad request are refused, nothing written to DDR" {
    var s = fresh();
    const at = box.DESC0;
    mbox[at + abi.W_OP] = abi.OP_VADD;
    mbox[at + abi.W_N] = 4;
    mbox[at + abi.W_A] = 0x100;
    mbox[at + abi.W_B] = 0x100;
    mbox[at + abi.W_C] = MEM - 8; // runs past the cart's memory
    post(2, 1);
    try t.expect(s.poll());
    try t.expectEqual(abi.ST_RANGE, mbox[box.RET]);
    try t.expectEqual(abi.ST_RANGE | abi.SERVED_ARM, mbox[at + abi.W_STATUS]);
    for (ddr) |w| try t.expectEqual(@as(u32, 0xDEADBEEF), w);
    mbox[box.COUNT] = abi.MAX_COUNT + 1;
    mbox[box.SEQ] = 3;
    try t.expect(s.poll());
    try t.expectEqual(abi.ST_BAD_DESC, mbox[box.RET]);
    try t.expectEqual(@as(u32, 3), mbox[box.DONE]); // still answered: ZIGGY never hangs on it
    mbox[box.COUNT] = 1;
    mbox[box.MEM_OFF] = (ddr.len * 4) - 8; // a memory past the window
    mbox[box.SEQ] = 4;
    try t.expect(s.poll());
    try t.expectEqual(abi.ST_BAD_DESC, mbox[box.RET]);
}

test "glass reads only the words ZIGGY copies: a scalar op ignores stale array words" {
    var s = fresh();
    scalarDesc(0, abi.OP_MUL, 6, 7);
    mbox[box.DESC0 + abi.W_N] = 0xFFFF_FFFF; // stale: never looked at for a scalar op
    post(9, 1);
    try t.expect(s.poll());
    try t.expectEqual(@as(f64, 42), get64(&mbox, box.DESC0 + abi.W_R));
    try t.expect(box.isScalar(abi.OP_POW) and !box.isScalar(abi.OP_VADD | abi.TYPE_F32));
}

test "a request ZIGGY withdrew before glass's TAKEN is not served" {
    var s = fresh();
    scalarDesc(0, abi.OP_MUL, 6, 7);
    post(5, 1);
    const S = struct {
        var n: u32 = 0;
        fn clock() u64 {
            n += 1;
            mbox[box.SEQ] = 0; // the firmware's withdrawal lands between glass's SEQ read and TAKEN
            return n;
        }
    };
    s.clock = S.clock;
    try t.expect(!s.poll());
    try t.expectEqual(@as(u32, 0), mbox[box.DONE]);
    try t.expectEqual(@as(u32, 0), mbox[box.DESC0 + abi.W_STATUS]);
}
