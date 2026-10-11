// What the glass program touches: the register block on M_AXI_GP0 and the cart
// CPU's RAM in DDR. On the board both are /dev/mem mappings (devmem.zig); on a
// desktop they are a simulated register file and a fake DDR (sim.zig), so the
// whole load path runs and is tested without the board.
//
// Both are reached ONLY with aligned 32-bit volatile accesses. The mappings are
// uncached device memory on the ARM, where an unaligned or byte access to the
// PL faults or is split; one access per word is also what the PL slave takes.
const std = @import("std");

pub const Regs = struct {
    ctx: *anyopaque,
    read_fn: *const fn (ctx: *anyopaque, offset: u32) u32,
    write_fn: *const fn (ctx: *anyopaque, offset: u32, value: u32) void,

    pub fn read(self: Regs, offset: u32) u32 {
        return self.read_fn(self.ctx, offset);
    }

    pub fn write(self: Regs, offset: u32, value: u32) void {
        self.write_fn(self.ctx, offset, value);
    }

    /// A register block mapped into this process (the board): plain volatile words.
    pub fn mapped(words: []volatile u32) Regs {
        return .{ .ctx = @ptrCast(@volatileCast(words.ptr)), .read_fn = mappedRead, .write_fn = mappedWrite };
    }
};

fn mappedRead(ctx: *anyopaque, offset: u32) u32 {
    const words: [*]volatile u32 = @ptrCast(@alignCast(ctx));
    return words[offset / 4];
}

fn mappedWrite(ctx: *anyopaque, offset: u32, value: u32) void {
    const words: [*]volatile u32 = @ptrCast(@alignCast(ctx));
    words[offset / 4] = value;
}

/// The cart CPU's RAM window, as words. Index 0 is the cart CPU's CART_CPU_BASE.
pub const Ddr = struct {
    words: []volatile u32,

    pub fn bytes(self: Ddr) usize {
        return self.words.len * 4;
    }

    /// Place `image` at the window's start and zero the rest, one word at a
    /// time. A trailing partial word is zero-padded.
    pub fn place(self: Ddr, image: []const u8) void {
        self.placeParts(&.{.{ .at = 0, .bytes = image }});
    }

    /// Read the window back against `image` (+ zeros): the first word that
    /// differs, or null. On the board this is what catches a wrong mapping.
    pub fn verify(self: Ddr, image: []const u8) ?usize {
        return self.verifyParts(&.{.{ .at = 0, .bytes = image }});
    }

    /// Every word of the window: the parts' bytes where they are, zero
    /// elsewhere. Parts start on a word and do not overlap (loader.zig's plan).
    pub fn placeParts(self: Ddr, parts: []const Part) void {
        for (self.words, 0..) |*w, i| w.* = expected(parts, i * 4);
    }

    /// placeParts' read-back: the first word that differs, or null.
    pub fn verifyParts(self: Ddr, parts: []const Part) ?usize {
        for (self.words, 0..) |w, i| if (w != expected(parts, i * 4)) return i;
        return null;
    }
};

/// Bytes at a window offset: the image at 0, the disk, its descriptor (loader.zig).
pub const Part = struct {
    at: usize,
    bytes: []const u8,
};

/// The little-endian word at byte offset `at` that the parts make (zero-padded).
fn expected(parts: []const Part, at: usize) u32 {
    var want = [_]u8{0} ** 4;
    for (parts) |p| {
        if (at < p.at or at >= p.at + p.bytes.len) continue;
        const n = @min(4, p.bytes.len - (at - p.at));
        @memcpy(want[0..n], p.bytes[at - p.at ..][0..n]);
    }
    return std.mem.readInt(u32, &want, .little);
}

test "parts land at their offsets, zeros between them" {
    var backing = [_]u32{0xFFFF_FFFF} ** 8;
    const ddr = Ddr{ .words = &backing };
    const parts = [_]Part{ .{ .at = 0, .bytes = "AB" }, .{ .at = 12, .bytes = "CDEFG" }, .{ .at = 28, .bytes = "ZMDK" } };
    ddr.placeParts(&parts);
    try std.testing.expectEqualSlices(u32, &.{ 0x4241, 0, 0, 0x4645_4443, 0x47, 0, 0, 0x4B44_4D5A }, &backing);
    try std.testing.expectEqual(@as(?usize, null), ddr.verifyParts(&parts));
    try std.testing.expectEqual(@as(?usize, 3), ddr.verify("AB"));
}

test "an image lands word by word, padded and followed by zeros" {
    var backing = [_]u32{0xFFFF_FFFF} ** 4;
    const ddr = Ddr{ .words = &backing };
    ddr.place("ABCDEF");
    try std.testing.expectEqual(@as(u32, 0x4443_4241), backing[0]);
    try std.testing.expectEqual(@as(u32, 0x0000_4645), backing[1]);
    try std.testing.expectEqual(@as(u32, 0), backing[3]);
    try std.testing.expectEqual(@as(?usize, null), ddr.verify("ABCDEF"));
    backing[3] = 1;
    try std.testing.expectEqual(@as(?usize, 3), ddr.verify("ABCDEF"));
    try std.testing.expectEqual(@as(?usize, 1), ddr.verify("ABCDEFG"));
}
