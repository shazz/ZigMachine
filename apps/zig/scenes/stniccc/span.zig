// --------------------------------------------------------------------------
// STNICCC's polygon spans, filled by the CPU with aligned word stores.
//
// Why not CHISEL (stniccc/gpu.zig) for every span: on the posted-store board a
// CHISEL op pays ~830 cycles of start, spin and D$ invalidate before its first
// pixel, then ~1-1.85 clocks a pixel (apps/perf/cost_model.mjs BLIT_CALL,
// BLIT_UNIT; BLITTER_HW_SPEC 10.5), while a ZIGGY word store drains in ~2.26
// cycles for FOUR pixels (cost_model STORE_DRAIN, bench ms.lib.64K). The flight
// makes ~2,100 fills a frame, ~2,000 of them under 256 pixels: 1.6 Mc of start
// costs alone (frame_cost, 2026-10-23). The CPU is ahead at every size, so
// polyfill sends a fill to the blitter only from BLIT_MIN pixels up.
//
// Stores are aligned by ADDRESS (head bytes up to a word boundary, words, tail
// bytes): a misaligned sw traps on the board (~210 cycles).
// --------------------------------------------------------------------------
const std = @import("std");

/// The area (pixels) from which a rectangle goes to CHISEL instead of the CPU.
/// The model puts the CPU ahead even for the 400x280 clear (~63 K cycles of
/// stores vs ~208 K for the FILL at 1.85 a pixel, ~116 K at the spec's 1.03),
/// so nothing reaches CHISEL: maxInt. Keeping every pixel on one writer also
/// leaves no CPU-then-blitter ordering for the board to get right.
pub const BLIT_MIN: usize = std.math.maxInt(usize);

/// Fill `w` x `h` pixels of colour `color` from `at`, rows `stride` apart.
pub fn rect(px: []u8, at: usize, w: usize, h: usize, stride: usize, color: u8) void {
    if (w == 0 or h == 0) return;
    std.debug.assert(at + (h - 1) * stride + w <= px.len);
    var a = @intFromPtr(px.ptr) + at;
    for (0..h) |_| {
        row(a, a + w, color);
        a += stride;
    }
}

/// The bytes [a, e) of one row, by address: up to a byte and a halfword to the
/// next word boundary, four-word strides, words, then a halfword and a byte.
pub inline fn row(start: usize, e: usize, color: u8) void {
    var a = start;
    const word = @as(u32, color) * 0x0101_0101;
    if (e - a < 4) return bytes(a, e, color); // short: may not reach a word boundary
    if (a & 1 != 0) {
        @as(*u8, @ptrFromInt(a)).* = color;
        a += 1;
    }
    if (a & 2 != 0) {
        @as(*u16, @ptrFromInt(a)).* = @truncate(word);
        a += 2;
    }
    while (a + 16 <= e) : (a += 16) {
        const q: *[4]u32 = @ptrFromInt(a);
        q[0] = word;
        q[1] = word;
        q[2] = word;
        q[3] = word;
    }
    while (a + 4 <= e) : (a += 4) @as(*u32, @ptrFromInt(a)).* = word;
    if (a + 2 <= e) {
        @as(*u16, @ptrFromInt(a)).* = @truncate(word);
        a += 2;
    }
    if (a < e) @as(*u8, @ptrFromInt(a)).* = color;
}

fn bytes(start: usize, e: usize, color: u8) void {
    var a = start;
    while (a < e) : (a += 1) @as(*u8, @ptrFromInt(a)).* = color;
}

test "every offset and width writes exactly its bytes" {
    var buf: [64]u8 align(4) = undefined;
    for (0..8) |at| for (0..48) |w| {
        @memset(&buf, 0xEE);
        rect(&buf, at, w, 1, 64, 7);
        for (buf, 0..) |b, i| try std.testing.expectEqual(@as(u8, if (i >= at and i < at + w) 7 else 0xEE), b);
    };
}

test "rows follow the stride and stop at h" {
    var buf: [4 * 10]u8 align(4) = [_]u8{0} ** 40;
    rect(&buf, 1, 3, 3, 10, 5);
    for (buf, 0..) |b, i| {
        const inside = i / 10 < 3 and i % 10 >= 1 and i % 10 < 4;
        try std.testing.expectEqual(@as(u8, if (inside) 5 else 0), b);
    }
}
