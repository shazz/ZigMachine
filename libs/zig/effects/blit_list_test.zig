// Tests for blit_list.zig against the QUEUE's rules (machine/blitter_queue.zig):
// every list run on a copy of the block, so a list closed because its half was
// full must hand the next one the words set() gave (the bug the first version
// had: stniccc's spans lost their destination at each mid-frame kick).
const std = @import("std");
const bl = @import("blit_list.zig");
const expect = std.testing.expect;

const HALF: usize = 256;
var ring: [2 * HALF]u32 = undefined;
var block = [_]u32{0} ** bl.WORDS;

const Op = struct { cmd: u8, w: [bl.WORDS]u32 };
var ran: [4096]Op = undefined;
var nran: usize = 0;

// What the machine does with a closed list: a working copy of the block, the
// descriptors' words into it, each op recorded with the copy it ran on.
fn run(r: bl.Range) void {
    var w = block;
    var i = r.start;
    const end = r.start + r.count;
    while (i < end) {
        const hdr = ring[i];
        i += 1;
        var m: u32 = hdr & 0xFF_FFFF;
        while (m != 0) : (m &= m - 1) {
            const k = @ctz(m);
            w[k] = if (k == 0) (w[0] & 0xFF00_00FF) | (ring[i] & 0x00FF_FF00) else ring[i];
            i += 1;
        }
        const cmd: u8 = @truncate(hdr >> 24);
        if (cmd != 0) {
            ran[nran] = .{ .cmd = cmd, .w = w };
            nran += 1;
        }
    }
}

fn fresh() bl.List {
    nran = 0;
    block = [_]u32{0} ** bl.WORDS;
    block[8] = 0x1100;
    block[9] = 320;
    return .{ .ring = &ring, .block = &block, .half = HALF };
}

fn queue(l: *bl.List, cmd: u8, words: []const bl.Word) void {
    if (!l.fits(words.len)) run(l.close().?);
    l.op(cmd, words);
}

fn fill(l: *bl.List, i: u32) void {
    queue(l, 2, &.{ .{ .k = 1, .v = 7 }, .{ .k = 10, .v = 8 | 1 << 16 }, .{ .k = 11, .v = i } });
}

test "fills after several full halves still run on the destination set() gave" {
    var l = fresh();
    queue(&l, 0, &.{ .{ .k = 8, .v = 0x9000 }, .{ .k = 9, .v = 400 } });
    for (0..500) |i| fill(&l, @intCast(i));
    run(l.close().?);
    try expect(nran == 500);
    for (ran[0..nran], 0..) |o, i| {
        try expect(o.cmd == 2 and o.w[8] == 0x9000 and o.w[9] == 400 and o.w[11] == i and o.w[1] == 7);
    }
}

test "a list only restates what the block does not hold" {
    var l = fresh();
    queue(&l, 0, &.{.{ .k = 9, .v = 400 }});
    for (0..200) |i| fill(&l, @intCast(i));
    const before = nran;
    run(l.close().?);
    // the second list opened with the op() words the block does not hold: COLOR, D_STRIDE, W/H, X0/Y0
    try expect(before > 0 and ring[HALF] == (1 << 1 | 1 << 9 | 1 << 10 | 1 << 11) and ring[HALF + 2] == 400);
}

test "a closed list (a flush) does not lose the words set() gave; unset words follow the block" {
    var l = fresh();
    queue(&l, 0, &.{.{ .k = 8, .v = 0x9000 }});
    fill(&l, 0);
    run(l.close().?);
    block[9] = 640; // someone else changed a word the queue never set
    fill(&l, 1);
    run(l.close().?);
    try expect(nran == 2 and ran[0].w[8] == 0x9000 and ran[1].w[8] == 0x9000 and ran[1].w[9] == 640);
}

test "a word set to the block's own value is still the queue's when the block moves" {
    var l = fresh();
    queue(&l, 0, &.{.{ .k = 8, .v = 0x1100 }}); // what the block holds
    fill(&l, 0);
    run(l.close().?);
    block[8] = 0x5000;
    fill(&l, 1);
    run(l.close().?);
    try expect(nran == 2 and ran[1].w[8] == 0x1100);
}

test "whole3 fills state their own words: not restated, and they give up an older op's" {
    var l = fresh();
    queue(&l, 0, &.{ .{ .k = 1, .v = 3 }, .{ .k = 8, .v = 0x9000 } });
    var i: u32 = 0;
    while (i < 300) : (i += 1) {
        if (!l.fits(3)) run(l.close().?);
        l.whole3(2 << 24 | 1 << 1 | 1 << 10 | 1 << 11, 7, 8 | 1 << 16, i);
    }
    const first_of_second = ring[HALF];
    run(l.close().?);
    try expect(nran == 300);
    for (ran[0..nran], 0..) |o, k| try expect(o.w[8] == 0x9000 and o.w[1] == 7 and o.w[11] == k);
    try expect(first_of_second == 1 << 8); // only D_BASE restated: COLOR went with the fills
}
