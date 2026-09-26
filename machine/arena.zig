// --------------------------------------------------------------------------
// RAM ARENA (HW 1.7.0) — hwRamAlloc / hwRamMark / hwRamRelease.
//
// A cart that needs a big working buffer used to declare a module-scope array.
// With imported memory the linker cannot assume the memory is zero, so it writes
// every zero byte of that array into the data segment: a 900 KB buffer costs
// 900 KB of the cart binary AND of the 2 MiB window before the cart runs a line.
// This is the machine's answer: a bump allocator over the part of the window the
// cart does NOT own — above its declared high-water (REG_CART_HIGH), below the
// video region.
//
// The pure half: arithmetic on the two arena registers and a byte view of the
// window. video.zig feeds it the register block and the real window;
// arena_test.zig feeds it a native buffer, so the rules are proven natively.
//
//   - the arena starts at the high-water and grows UP; `top` = 0 means empty;
//   - an allocation is aligned (power of two, 1..MAX_ALIGN) and ZEROED, so a
//     cart can rely on zeroed memory exactly as it did with a static array;
//   - a request that cannot be met returns 0 and bumps `failures` — never silent;
//   - release(mark) frees everything allocated after mark() returned it; a
//     mark outside [high-water, top] is refused and ALSO counted.
// --------------------------------------------------------------------------
const std = @import("std");

pub const MAX_ALIGN: u32 = 1 << 16; // 64 KiB: past a page, alignment is a layout choice, not a type's

pub const State = struct {
    top: u32, // REG_RAM_ARENA_TOP: first byte above the arena, 0 = empty
    failures: u32, // REG_RAM_ALLOC_FAILS
};

/// The cart window as bytes. `base` is the address of mem[0]; natively it is
/// a made-up address, so the arithmetic is the machine's to the byte.
pub const Window = struct {
    base: u32,
    mem: []u8,

    fn top(w: Window) u64 {
        return @as(u64, w.base) + w.mem.len;
    }
    /// The declared high-water, or null when the host never declared one (or
    /// declared one outside the window) — then there is no arena at all.
    fn start(w: Window, high: u32) ?u64 {
        if (high < w.base or high >= w.top()) return null;
        return high;
    }
};

/// The first free byte: the arena's top, or the high-water while it is empty.
/// null = undeclared high-water.
pub fn cursor(s: State, w: Window, high: u32) ?u32 {
    const lo = w.start(high) orelse return null;
    return @intCast(@max(lo, s.top));
}

/// Bytes left above the arena. 0 when undeclared, as hwRamFree always said.
pub fn free(s: State, w: Window, high: u32) u32 {
    const c = cursor(s, w, high) orelse return 0;
    return @intCast(w.top() - c);
}

/// Bytes owned by the cart: statics + stack + arena.
pub fn used(s: State, w: Window, high: u32) u32 {
    const c = cursor(s, w, high) orelse return 0;
    return c - w.base;
}

/// Reserve `bytes` zeroed bytes aligned to `alignment`; its address, or 0.
pub fn alloc(s: *State, w: Window, high: u32, bytes: u32, alignment: u32) u32 {
    const c = cursor(s.*, w, high) orelse return fail(s);
    if (bytes == 0 or alignment == 0 or alignment > MAX_ALIGN or !std.math.isPowerOfTwo(alignment))
        return fail(s);
    const a: u64 = alignment;
    const at: u64 = (@as(u64, c) + a - 1) & ~(a - 1);
    const end: u64 = at + bytes;
    if (end > w.top()) return fail(s);
    @memset(w.mem[@intCast(at - w.base)..@intCast(end - w.base)], 0);
    s.top = @intCast(end);
    return @intCast(at);
}

/// The value release() takes to free everything allocated from now on. 0 when
/// there is no arena (undeclared high-water) — release(0) is then refused.
pub fn mark(s: State, w: Window, high: u32) u32 {
    return cursor(s, w, high) orelse 0;
}

/// Free back to `m`. Refused (and counted) unless high-water <= m <= cursor.
pub fn release(s: *State, w: Window, high: u32, m: u32) void {
    const lo = w.start(high) orelse {
        _ = fail(s);
        return;
    };
    const c = cursor(s.*, w, high).?;
    if (m < lo or m > c) {
        _ = fail(s);
        return;
    }
    s.top = if (m == lo) 0 else m;
}

fn fail(s: *State) u32 {
    s.failures +%= 1;
    return 0;
}
