// --------------------------------------------------------------------------
// The ball as GENERATED CODE, Leonard's way (the 2005 record's "generated sprite
// code": one routine per pixel shift, every store an immediate value at an
// immediate offset, no mask, no loop, no load).
//
// On the ST each of the 16 shifts was a run of `move.l #imm,d16(a0)`. In the
// chunky plane a shift is the ball's x mod 4 (the u32 grid), so 4 routines.
// For each row, each run of opaque pixels is cut into the fewest stores that
// keep their alignment (u8 to reach a u16 boundary, u16 to reach a u32 one,
// u64 while 8 or more remain, u32 while 4 or more, then u16/u8 for the tail).
// The ball's 208 pixels come out as 52-60 stores (asserted in ball_test.zig).
//
// What a store costs on the board (KESTREL, 2026-10-25): the board runs the
// cart through wasm2c, which RELOADS the memory base (two dependent loads)
// after every wasm store, and a load waits for the posted stores to drain
// (bench raw.hit 8.6 cycles): ~10 cycles a wasm store, whatever its width.
// So the fewer wasm stores the better: a u64 is two `sw` behind one reload,
// and it needs only 4-byte alignment on rv32 (zm_variant.h). ZIGGY traps a
// misaligned access (~210 cycles), so nothing here is misaligned.
//
// The plane's stride is a RUN-TIME value (the caller passes the plane's own):
// each row's stores then sit at a small offset from a row pointer, which the
// rv32 compiler folds into the store instruction. With the stride a constant,
// LLVM folded rows 3-15 into offsets up to 8,660, beyond rv32's 12-bit
// immediates, and GCC kept ~20 of them as spilled registers (a load each).
//
// The tables are built at COMPILE TIME from the ball's own pixels, and
// `draw` unrolls them with `inline for`: what the CPU runs is the list.
// Generic over the image so the native test can feed it any sprite.
// --------------------------------------------------------------------------
const std = @import("std");

/// One store: `width` bytes (1, 2, 4 or 8) of `val` at byte `x` of row `row`,
/// x relative to the u32-aligned word holding the sprite's left edge.
pub const Store = struct { row: u32, x: u32, val: u64, width: u8 };

/// `img`: w*h indices, 0 = transparent. `ink`: added to every opaque index
/// (the merged palette's ball block).
pub fn Sprite(comptime w: u32, comptime h: u32, comptime img: [w * h]u8, comptime ink: u8) type {
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

        // One opaque run [x0, x1) of row y, as aligned stores.
        fn runStores(comptime y: u32, comptime x0: u32, comptime x1: u32, comptime shift: u32) []const Store {
            var list: []const Store = &.{};
            var a = shift + x0;
            const b = shift + x1;
            while (a < b) {
                const width: u8 = if (a % 4 == 0 and b - a >= 8) 8 else if (a % 4 == 0 and b - a >= 4) 4 else if (a % 2 == 0 and b - a >= 2) 2 else 1;
                var val: u64 = 0;
                for (0..width) |k| val |= @as(u64, img[y * w + (a - shift) + k] + ink) << @intCast(8 * k);
                list = list ++ [_]Store{.{ .row = y, .x = a, .val = val, .width = width }};
                a += width;
            }
            return list;
        }

        /// The sprite's top-left at (x, y) of the plane at `dst` (4-aligned),
        /// `stride` bytes a row (a multiple of 4). No clipping: the caller
        /// keeps the sprite inside the plane.
        pub inline fn draw(dst: [*]align(4) u8, stride: u32, x: u32, y: u32) void {
            const base: [*]align(4) u8 = @alignCast(dst + (y * stride + (x & ~@as(u32, 3))));
            routines[x & 3](base, stride);
        }

        // One routine per shift, called through a TABLE so that nothing
        // inlines it into the caller's ball loop (the board's GCC inlines a
        // function called once, `noinline` or not: it is gone by wasm2c).
        // Inlined, GCC hoisted the four routines' constants and row pointers
        // out of the loop into ~20 spilled registers, a stack load per few
        // stores. Alone, a routine is straight-line code with nothing to hoist.
        const Routine = *const fn ([*]align(4) u8, u32) void;
        const routines = [4]Routine{ Shift(0).run, Shift(1).run, Shift(2).run, Shift(3).run };
        fn Shift(comptime s: u32) type {
            return struct {
                fn run(base: [*]align(4) u8, stride: u32) void {
                    stores(comptime program(s), base, stride);
                }
            };
        }

        // VOLATILE so LLVM keeps each store as written (it would otherwise
        // merge and reorder them across rows).
        inline fn stores(comptime list: []const Store, base: [*]align(4) u8, stride: u32) void {
            var row: [*]align(4) u8 = base;
            comptime var at: u32 = 0; // the row `row` points at
            inline for (list) |st| {
                inline while (at < st.row) : (at += 1) row = @alignCast(row + stride);
                const p = row + st.x;
                switch (st.width) {
                    8 => @as(*align(4) volatile u64, @ptrCast(@alignCast(p))).* = st.val,
                    4 => @as(*volatile u32, @ptrCast(@alignCast(p))).* = @intCast(st.val),
                    2 => @as(*volatile u16, @ptrCast(@alignCast(p))).* = @intCast(st.val),
                    else => @as(*volatile u8, @ptrCast(p)).* = @intCast(st.val),
                }
            }
        }
    };
}
