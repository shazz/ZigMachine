// --------------------------------------------------------------------------
// zg.mem — the machine's RAM arena (hwRamAlloc, HW 1.7.0) for Zig carts.
//
// Instead of a module-scope buffer, which the wasm link writes out byte for byte
// (imported memory is not known to be zero, so a 900 KB `[N]u8` of zeros costs
// 900 KB of cart binary AND of the 2 MiB window before boot):
//
//     const zg = @import("zigos");
//     var work: []u16 = undefined;
//     work = zg.mem.mustAlloc(u16, 320 * 200);          // zeroed; panics if the window is full
//     const maybe = zg.mem.alloc(u8, 64 * 1024) orelse return; // or handle it
//     var list: std.ArrayList(u32) = .empty;            // std containers work too
//     try list.append(zg.mem.allocator, 7);
//
// A multi-part cart reuses one region per part: `const m = zg.mem.mark();` when
// a part starts, `zg.mem.release(m);` when it ends. Nothing is freed singly
// (the allocator's free is a no-op unless the block is the arena's topmost).
//
// Generic over its backend so the adapter is tested natively (mem_test.zig):
// `Ram` provides alloc(bytes, alignment) usize, mark() usize, release(usize),
// failures() u32 and free() usize, with 0 meaning "refused" as hwRamAlloc does.
// --------------------------------------------------------------------------
const std = @import("std");

pub fn Mem(comptime Ram: type) type {
    return struct {
        /// A position in the arena, from mark(); release() frees back to it.
        pub const Mark = usize;

        /// An std.mem.Allocator over the arena. Memory comes back zeroed.
        pub const allocator: std.mem.Allocator = .{ .ptr = undefined, .vtable = &vtable };

        /// `n` zeroed Ts, or null when the window cannot hold them (counted by
        /// the machine: see failures()).
        pub fn alloc(comptime T: type, n: usize) ?[]T {
            const bytes = std.math.mul(usize, @sizeOf(T), n) catch {
                _ = Ram.alloc(std.math.maxInt(usize), 1); // make the refusal count
                return null;
            };
            if (bytes == 0) return &[_]T{};
            const at = Ram.alloc(bytes, @alignOf(T));
            if (at == 0) return null;
            const p: [*]T = @ptrFromInt(at);
            return p[0..n];
        }

        /// alloc() for a buffer the scene cannot run without: a full window is
        /// a build mistake, so it stops the cart with a message, not a garbage
        /// frame.
        pub fn mustAlloc(comptime T: type, n: usize) []T {
            return alloc(T, n) orelse @panic("zg.mem: cart RAM window full (hwRamFree() too small)");
        }

        pub fn mark() Mark {
            return Ram.mark();
        }
        pub fn release(m: Mark) void {
            Ram.release(m);
        }
        /// Refused requests since this cart was loaded. Non-zero = a bug.
        pub fn failures() u32 {
            return Ram.failures();
        }
        /// Bytes left in the window above the arena.
        pub fn free() usize {
            return Ram.free();
        }

        const vtable: std.mem.Allocator.VTable = .{
            .alloc = vAlloc,
            .resize = vResize,
            .remap = vRemap,
            .free = vFree,
        };

        fn vAlloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
            const at = Ram.alloc(len, alignment.toByteUnits());
            return if (at == 0) null else @ptrFromInt(at);
        }

        fn isTop(memory: []u8) bool {
            return @intFromPtr(memory.ptr) + memory.len == Ram.mark();
        }

        // In place: any shrink; a grow only for the topmost block, by bumping
        // the arena (alignment 1 lands exactly on its end). A grow that cannot
        // fit says so BEFORE asking, so it is not counted as a failure: the
        // caller then allocates anew, and THAT refusal is counted.
        fn vResize(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
            if (new_len <= memory.len) {
                if (isTop(memory)) Ram.release(@intFromPtr(memory.ptr) + new_len);
                return true;
            }
            if (!isTop(memory)) return false;
            const extra = new_len - memory.len;
            if (extra > Ram.free()) return false;
            return Ram.alloc(extra, 1) != 0;
        }

        fn vRemap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
            return if (vResize(ctx, memory, alignment, new_len, ra)) memory.ptr else null;
        }

        // An arena frees by mark; only the topmost block can be popped singly.
        fn vFree(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
            if (memory.len != 0 and isTop(memory)) Ram.release(@intFromPtr(memory.ptr));
        }
    };
}
