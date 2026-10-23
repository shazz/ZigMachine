// --------------------------------------------------------------------------
// The ball as GENERATED CODE, Leonard's way (the 2005 record's "generated sprite
// code": one routine per pixel shift, every store an immediate value at an
// immediate offset, no mask, no loop, no load).
//
// On the ST each of the 16 shifts was a run of `move.l #imm,d16(a0)`. In the
// chunky plane a shift is the ball's x mod 4 (the u32 grid), so 4 routines.
// For each row, each run of opaque pixels is cut into the fewest ALIGNED
// stores (u8 to reach a u16 boundary, u16 to reach a u32 one, u32 while 4 or
// more remain, then u16/u8 for the tail): ZIGGY traps a misaligned access
// (~210 cycles), an aligned store is ~2.3. The ball's 208 pixels at any shift
// come out as 72 stores (asserted in ball_test.zig).
//
// The tables are built at COMPILE TIME from the ball's own pixels, and
// `draw` unrolls them with `inline for`: what the CPU runs is the list.
// Generic over the image so the native test can feed it any sprite.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Store = struct { off: u32, val: u32, width: u8 };

/// `img`: w*h indices, 0 = transparent. `ink`: added to every opaque index
/// (the merged palette's ball block). `stride`: the plane's bytes per row.
pub fn Sprite(comptime w: u32, comptime h: u32, comptime img: [w * h]u8, comptime ink: u8, comptime stride: u32) type {
    return struct {
        pub const W = w;
        pub const H = h;

        /// The store list of one shift (0..3), in row order.
        pub fn program(comptime shift: u32) []const Store {
            comptime {
                @setEvalBranchQuota(100_000);
                var list: []const Store = &.{};
                for (0..h) |y| {
                    var x: u32 = 0;
                    while (x < w) {
                        if (img[y * w + x] == 0) {
                            x += 1;
                            continue;
                        }
                        var end = x;
                        while (end < w and img[y * w + end] != 0) end += 1;
                        list = list ++ runStores(@intCast(y), x, end, shift);
                        x = end;
                    }
                }
                const out = list[0..list.len].*;
                return &out;
            }
        }

        // One opaque run [x0, x1) of row y, as aligned stores relative to the
        // u32-aligned word holding the sprite's left edge.
        fn runStores(comptime y: u32, comptime x0: u32, comptime x1: u32, comptime shift: u32) []const Store {
            var list: []const Store = &.{};
            var a = shift + x0;
            const b = shift + x1;
            while (a < b) {
                const width: u8 = if (a % 4 == 0 and b - a >= 4) 4 else if (a % 2 == 0 and b - a >= 2) 2 else 1;
                var val: u32 = 0;
                for (0..width) |k| val |= @as(u32, img[y * w + (a - shift) + k] + ink) << @intCast(8 * k);
                list = list ++ [_]Store{.{ .off = y * stride + a, .val = val, .width = width }};
                a += width;
            }
            return list;
        }

        /// The sprite's top-left at (x, y) of the plane at `dst` (4-aligned).
        /// No clipping: the caller keeps the sprite inside the plane.
        pub inline fn draw(dst: [*]align(4) u8, x: u32, y: u32) void {
            const base: [*]align(4) u8 = @alignCast(dst + (y * stride + (x & ~@as(u32, 3))));
            switch (x & 3) {
                inline 0...3 => |s| run(program(s), base),
                else => unreachable,
            }
        }

        // VOLATILE so LLVM keeps each store as written: left alone it merges
        // neighbouring u32 stores into i64 stores with a 4-byte alignment hint,
        // which frame_cost counts as 18,000 misaligned (trapping) accesses a
        // frame at 2,048 balls (4.4 Mc estimated instead of 0.55).
        inline fn run(comptime list: []const Store, base: [*]align(4) u8) void {
            inline for (list) |st| {
                switch (st.width) {
                    4 => @as(*volatile u32, @ptrCast(@alignCast(base + st.off))).* = st.val,
                    2 => @as(*volatile u16, @ptrCast(@alignCast(base + st.off))).* = @intCast(st.val),
                    else => @as(*volatile u8, @ptrCast(base + st.off)).* = @intCast(st.val),
                }
            }
        }
    };
}
