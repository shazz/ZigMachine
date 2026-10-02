// The parts as the disk's loader leaves them in memory (byte for byte from
// SNYD_90.MSA, prototypes/snyd90_re/mk_assets.py). Every blob ships ZX0-packed
// (build.zig: packed_assets.snyd_90) and is depacked, when its part starts,
// into the one part buffer: only one part runs at a time, as on the ST, where
// each overwrote the last. A part that runs on its own memory (st.zig) gets
// the rest of the buffer as that memory, zeroed.
const std = @import("std");
const zg = @import("zigos");
const zx0 = @import("depackers").zx0;
const PACKED = @import("packed_assets").snyd_90;
const menu = @import("menu.zig");
const intro = @import("intro.zig");
const f1 = @import("f1.zig");
const f2 = @import("f2.zig");
const f3 = @import("f3.zig");
const f5 = @import("f5.zig");

pub const Set = enum { intro, menu, f1, f2, f3, f5 };

/// Bytes of the part buffer: the largest part's memory.
pub const PART_LEN: usize = @max(menu.TOP - menu.BASE, intro.LEN, f1.TOP - f1.BASE, f2.TOP - f2.BASE, f3.TOP - f3.BASE, f5.TOP - f5.BASE);

var part: []align(4) u8 = &.{};

/// Once per cart load.
pub fn init() void {
    const words = zg.mem.mustAlloc(u32, PART_LEN / 4);
    const p: [*]align(4) u8 = @ptrCast(words.ptr);
    part = p[0..PART_LEN];
}

fn blob(set: Set) struct { src: []const u8, len: usize } {
    return switch (set) {
        .intro => .{ .src = PACKED.intro_spu, .len = intro.LEN },
        .menu => .{ .src = PACKED.menu, .len = menu.IMAGE },
        // F1's and F2's memory as their own set-up leaves it (the oracle's run).
        .f1 => .{ .src = PACKED.f1, .len = f1.TOP - f1.BASE },
        .f2 => .{ .src = PACKED.f2, .len = f2.TOP - f2.BASE },
        // F3..F6: their set-up run once on the original code (mk_parts.py).
        .f3 => .{ .src = PACKED.f3, .len = f3.TOP - f3.BASE },
        .f5 => .{ .src = PACKED.f5, .len = f5.TOP - f5.BASE },
    };
}

/// Depack `set` to the start of the part buffer and zero the rest; the whole
/// buffer, or null if the blob does not depack to its size (a build fault).
pub fn load(set: Set) ?[]align(4) u8 {
    const b = blob(set);
    const n = zx0.depack(b.src, part[0..b.len]) orelse return null;
    if (n != b.len) return null;
    @memset(part[b.len..], 0);
    return part;
}

test "the part buffer holds the menu's memory" {
    try std.testing.expect(PART_LEN >= menu.TOP - menu.BASE);
}
