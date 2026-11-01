// Tests for chisel_copy_plan.zig: what goes to CHISEL, what stays on the CPU.
const std = @import("std");
const plan = @import("chisel_copy_plan.zig");
const expect = std.testing.expect;

const BASE: usize = 0x300000;
const M = plan.Map{ .vram = 0x1100, .region = 1948928, .cart = .{ 0x100000, 0x300000 }, .rom = .{ 0x500000, 0x700000 } };
const VRAM = BASE + 0x1100;

test "a long copy from cart RAM into VRAM goes to CHISEL" {
    try expect(plan.eligible(M, BASE, VRAM, 0x200000, 8192, 4096));
}

test "below the threshold, or with no ZigOS base, the CPU copies" {
    try expect(!plan.eligible(M, BASE, VRAM, 0x200000, 4095, 4096));
    try expect(!plan.eligible(M, 0, VRAM, 0x200000, 8192, 4096));
}

test "a destination outside VRAM stays on the CPU" {
    try expect(!plan.eligible(M, BASE, 0x200000, VRAM, 8192, 4096)); // cart RAM: CHISEL writes only the region
    try expect(!plan.eligible(M, BASE, BASE + 0x80, 0x200000, 8192, 4096)); // the registers, below OFF_VRAM
    try expect(!plan.eligible(M, BASE, BASE + M.region - 100, 0x200000, 8192, 4096)); // runs past the region
}

test "an overlap or a source across two windows stays on the CPU" {
    try expect(!plan.eligible(M, BASE, VRAM, VRAM + 100, 8192, 4096));
    try expect(!plan.eligible(M, BASE, VRAM + 100, VRAM, 8192, 4096));
    try expect(plan.eligible(M, BASE, VRAM, VRAM + 8192, 8192, 4096)); // touching is not overlapping
    try expect(!plan.eligible(M, BASE, VRAM + 0x80000, 0x300000 - 4096, 8192, 4096)); // cart RAM into the region
    try expect(!plan.eligible(M, BASE, VRAM, BASE + M.region + 16, 8192, 4096)); // the gap below the ROM
    try expect(plan.eligible(M, BASE, VRAM, 0x500000, 8192, 4096)); // the ROM's RAM
}

test "the split covers every byte once" {
    const s = plan.split(10000, 4096);
    try expect(s.rows == 2 and s.tail == 1808 and s.rows * 4096 + s.tail == 10000);
    try expect(plan.split(8192, 4096).tail == 0);
}
