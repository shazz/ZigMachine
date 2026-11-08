// --------------------------------------------------------------------------
// The VRAM pool's bump allocator (zigos.zig vramAlloc / vramWords): region offsets from
// OFF_VRAM up to OFF_VRAM + VRAM_BYTES, where the PFB starts. It had no guard: an allocation
// past the end was handed out anyway and the plane drew over the PFB (docs/GEM_DESK_MODE.md §5:
// a 640x480 desk plane takes 307,200 of the 1 MiB). Now one past the end is refused.
// --------------------------------------------------------------------------

/// `bytes` from the pool whose next free offset is `top.*` and whose end is `limit`, starting on
/// an `alignment` boundary (a power of two, at least 4); the size is kept a multiple of 4. Null,
/// and `top.*` unchanged, when it does not fit.
pub fn alloc(top: *usize, limit: usize, bytes: usize, alignment: usize) ?usize {
    const a = if (alignment < 4) 4 else alignment;
    const off = (top.* + a - 1) & ~(a - 1);
    const size = (bytes + 3) & ~@as(usize, 3);
    if (off > limit or size > limit - off) return null;
    top.* = off + size;
    return off;
}

test "a pool fits exactly, then refuses one byte more" {
    const std = @import("std");
    var top: usize = 0x1100;
    const limit: usize = 0x1100 + 1024;
    try std.testing.expectEqual(@as(?usize, 0x1100), alloc(&top, limit, 1000, 4));
    try std.testing.expectEqual(@as(?usize, 0x1100 + 1000), alloc(&top, limit, 24, 4)); // exactly full
    try std.testing.expectEqual(@as(?usize, null), alloc(&top, limit, 1, 4)); // one byte over
    try std.testing.expectEqual(limit, top); // a refusal takes nothing
}

test "alignment rounds the start up, sizes stay word multiples" {
    const std = @import("std");
    var top: usize = 0x1104;
    try std.testing.expectEqual(@as(?usize, 0x1140), alloc(&top, 0x100000, 307200, 64));
    try std.testing.expectEqual(@as(usize, 0x1140 + 307200), top);
    try std.testing.expectEqual(@as(?usize, 0x1140 + 307200), alloc(&top, 0x100000, 3, 1));
    try std.testing.expectEqual(@as(usize, 0x1140 + 307204), top);
}

test "a start past the end is refused, not wrapped" {
    const std = @import("std");
    var top: usize = 2000;
    try std.testing.expectEqual(@as(?usize, null), alloc(&top, 1024, 0, 4));
    try std.testing.expectEqual(@as(?usize, null), alloc(&top, 2047, 4, 64)); // rounds to 2048
}
