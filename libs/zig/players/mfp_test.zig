// Native tests for the SNDH player's MFP 68901 (mfp.zig): `zig test` this file.
const std = @import("std");
const m = @import("mfp.zig");

const A = 0; // timer indices, as the player numbers them
const B = 1;
const C = 2;
const D = 3;

fn fresh() m.Mfp {
    var mfp: m.Mfp = undefined;
    mfp.reset();
    return mfp;
}

/// What a tune's init does to start Timer A with its interrupt on.
fn enableA(mfp: *m.Mfp) void {
    mfp.write(m.IERA, mfp.read(m.IERA) | 0x20);
    mfp.write(m.IMRA, mfp.read(m.IMRA) | 0x20);
}

test "reset is the interrupt controller TOS hands over: only Timer C of the four enabled" {
    const mfp = fresh();
    try std.testing.expectEqual(@as(u8, 0x1E), mfp.read(m.IERA));
    try std.testing.expectEqual(@as(u8, 0x64), mfp.read(m.IERB));
    try std.testing.expectEqual(@as(u8, 0x1E), mfp.read(m.IMRA));
    try std.testing.expectEqual(@as(u8, 0x64), mfp.read(m.IMRB));
    try std.testing.expectEqual(@as(u8, 0x40), mfp.read(m.VR));
    try std.testing.expectEqual(@as(u8, 0), mfp.read(m.IPRA));
    try std.testing.expectEqual(@as(u8, 0), mfp.read(m.TACR));
}

test "an enabled, unmasked timer interrupts, once per timeout" {
    var mfp = fresh();
    enableA(&mfp);
    mfp.timeout(A);
    try std.testing.expectEqual(@as(?usize, A), mfp.nextInterrupt());
    try std.testing.expectEqual(@as(?usize, null), mfp.nextInterrupt());
}

test "a DISABLED timer never goes pending, so it never interrupts" {
    var mfp = fresh(); // Timer A is off after reset, as TOS leaves it
    mfp.timeout(A);
    try std.testing.expectEqual(@as(u8, 0), mfp.read(m.IPRA) & 0x20);
    try std.testing.expectEqual(@as(?usize, null), mfp.nextInterrupt());
    // ...and enabling it afterwards does not resurrect the lost timeout.
    enableA(&mfp);
    try std.testing.expectEqual(@as(?usize, null), mfp.nextInterrupt());
}

test "Maestro's SAMSTOP: clearing IERA/IMRA bit 5 stops Timer A interrupting" {
    var mfp = fresh();
    enableA(&mfp);
    mfp.write(m.TACR, 1); // the timer keeps running: SAMSTOP does not touch TACR
    mfp.write(m.IERA, mfp.read(m.IERA) & ~@as(u8, 0x20));
    mfp.write(m.IMRA, mfp.read(m.IMRA) & ~@as(u8, 0x20));
    mfp.timeout(A);
    try std.testing.expectEqual(@as(?usize, null), mfp.nextInterrupt());
    try std.testing.expect(mfp.timerHz(A) > 0); // counting, just not interrupting
}

test "a MASKED timer goes pending and interrupts once unmasked" {
    var mfp = fresh();
    enableA(&mfp);
    mfp.write(m.IMRA, mfp.read(m.IMRA) & ~@as(u8, 0x20));
    mfp.timeout(A);
    mfp.timeout(A); // a second timeout while pending is still ONE request
    try std.testing.expectEqual(@as(u8, 0x20), mfp.read(m.IPRA) & 0x20);
    try std.testing.expectEqual(@as(?usize, null), mfp.nextInterrupt());
    mfp.write(m.IMRA, mfp.read(m.IMRA) | 0x20);
    try std.testing.expectEqual(@as(?usize, A), mfp.nextInterrupt());
    try std.testing.expectEqual(@as(?usize, null), mfp.nextInterrupt());
}

test "disabling a channel drops its pending request" {
    var mfp = fresh();
    enableA(&mfp);
    mfp.write(m.IMRA, mfp.read(m.IMRA) & ~@as(u8, 0x20));
    mfp.timeout(A);
    mfp.write(m.IERA, mfp.read(m.IERA) & ~@as(u8, 0x20));
    try std.testing.expectEqual(@as(u8, 0), mfp.read(m.IPRA) & 0x20);
    // Re-enabled and unmasked: nothing was left waiting.
    enableA(&mfp);
    try std.testing.expectEqual(@as(?usize, null), mfp.nextInterrupt());
    // ...but the next timeout interrupts as normal.
    mfp.timeout(A);
    try std.testing.expectEqual(@as(?usize, A), mfp.nextInterrupt());
}

test "software clears IPR with 0s; writing 1s sets nothing" {
    var mfp = fresh();
    enableA(&mfp);
    mfp.write(m.IMRA, mfp.read(m.IMRA) & ~@as(u8, 0x20));
    mfp.timeout(A);
    mfp.write(m.IPRA, 0xFF); // all ones: no change
    try std.testing.expectEqual(@as(u8, 0x20), mfp.read(m.IPRA));
    mfp.write(m.IPRA, ~@as(u8, 0x20)); // `bclr #5,$fffa0b`
    try std.testing.expectEqual(@as(u8, 0), mfp.read(m.IPRA));
    mfp.write(m.IMRA, mfp.read(m.IMRA) | 0x20);
    try std.testing.expectEqual(@as(?usize, null), mfp.nextInterrupt());
}

test "ISR is clear-only: a handler's end-of-interrupt write cannot set it" {
    var mfp = fresh();
    mfp.write(m.ISRA, 0xFF);
    try std.testing.expectEqual(@as(u8, 0), mfp.read(m.ISRA));
}

test "the B-register timers gate on IERB/IMRB: C is on after reset, D is not" {
    var mfp = fresh();
    mfp.timeout(D);
    mfp.timeout(C);
    try std.testing.expectEqual(@as(?usize, C), mfp.nextInterrupt());
    try std.testing.expectEqual(@as(?usize, null), mfp.nextInterrupt());
    mfp.write(m.IERB, mfp.read(m.IERB) | 0x10);
    mfp.write(m.IMRB, mfp.read(m.IMRB) | 0x10);
    mfp.timeout(D);
    try std.testing.expectEqual(@as(?usize, D), mfp.nextInterrupt());
}

test "Timer B is bit 0 of the A registers" {
    var mfp = fresh();
    mfp.write(m.IERA, 0x01);
    mfp.write(m.IMRA, 0x01);
    mfp.timeout(B);
    try std.testing.expectEqual(@as(u8, 0x01), mfp.read(m.IPRA));
    try std.testing.expectEqual(@as(?usize, B), mfp.nextInterrupt());
}

test "pending requests are delivered highest priority first: A, B, C, D" {
    var mfp = fresh();
    mfp.write(m.IERA, 0x21);
    mfp.write(m.IERB, 0x30);
    for ([_]usize{ D, C, B, A }) |t| mfp.timeout(t); // all masked except C
    mfp.write(m.IMRA, 0x21);
    mfp.write(m.IMRB, 0x30);
    for ([_]usize{ A, B, C, D }) |t| try std.testing.expectEqual(@as(?usize, t), mfp.nextInterrupt());
    try std.testing.expectEqual(@as(?usize, null), mfp.nextInterrupt());
}

test "Xbtimer with a vector enables and unmasks its timer, as TOS's jenabint does" {
    var mfp = fresh();
    mfp.xbtimer(A, 1, 128, true);
    try std.testing.expectEqual(@as(u8, 1), mfp.read(m.TACR));
    try std.testing.expectEqual(@as(u8, 128), mfp.read(m.TADR));
    try std.testing.expectEqual(@as(u8, 0x20), mfp.read(m.IERA) & 0x20);
    try std.testing.expectEqual(@as(u8, 0x20), mfp.read(m.IMRA) & 0x20);
    mfp.xbtimer(D, 1, 2, false); // no vector: registers only
    try std.testing.expectEqual(@as(u8, 0x01), mfp.read(m.TCDCR) & 0x07);
    try std.testing.expectEqual(@as(u8, 0), mfp.read(m.IERB) & 0x10);
}

test "vector slots follow VR's base: Timer A at $134 under TOS's $40" {
    var mfp = fresh();
    try std.testing.expectEqual(@as(u32, 0x134), mfp.vectorSlot(A));
    try std.testing.expectEqual(@as(u32, 0x120), mfp.vectorSlot(B));
    try std.testing.expectEqual(@as(u32, 0x114), mfp.vectorSlot(C));
    try std.testing.expectEqual(@as(u32, 0x110), mfp.vectorSlot(D));
}

test "register reads return what was written" {
    var mfp = fresh();
    for ([_]u32{ m.TACR, m.TADR, m.VR, m.IMRA, m.IERB, m.TCDCR }) |r| {
        mfp.write(r, 0x5A);
        try std.testing.expectEqual(@as(u8, 0x5A), mfp.read(r));
    }
}
