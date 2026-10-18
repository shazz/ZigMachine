// --------------------------------------------------------------------------
// The part's own memory. A Nitrowave program addresses its pictures, fonts,
// tables, variables and both screens ABSOLUTELY (MENU.PRG is relocated to 0 in
// the rip, the .BIN parts load at a fixed address), so each port keeps that
// memory and its routines run against the same addresses as the 68000's: a
// ripped table is used where the original used it, and any byte can be held
// against a Hatari RAM dump (prototypes/naos_nitrowave_re/NOTES.md).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

/// A part runs at the original's 50 Hz: one VBL every 20 ms of host time.
pub const VBL_MS: f32 = 20;
/// The ST's 512 KB: every address a part touches lies below it.
pub const RAM_LEN: usize = 0x80000;

pub const Ram = struct {
    m: []u8,

    /// An address read from this memory is data; one outside it traps where
    /// safety is on (the tests) and is clamped inside it in ReleaseSmall.
    inline fn at(self: *const Ram, a: u32, n: usize) usize {
        const off: usize = a;
        if (off < self.m.len and n <= self.m.len - off) return off;
        if (std.debug.runtime_safety) std.debug.panic("naos st.Ram: ${X} + {d} is outside", .{ a, n });
        return self.m.len - n;
    }

    pub inline fn b(self: *const Ram, a: u32) u8 {
        return self.m[self.at(a, 1)];
    }
    pub inline fn w(self: *const Ram, a: u32) u16 {
        return std.mem.readInt(u16, self.m[self.at(a, 2)..][0..2], .big);
    }
    // A long sits on any EVEN address, so half of them are not word aligned. The board's
    // build turns a 32-bit access into one lw/sw and a misaligned one TRAPS (about a
    // thousand cycles, fpga/cycles/trap.c): the menu's VBL reads and writes thousands of
    // longs a frame. Two aligned halfwords instead for those.
    pub inline fn l(self: *const Ram, a: u32) u32 {
        const o = self.at(a, 4);
        if ((@intFromPtr(self.m.ptr) + o) & 3 == 0) return std.mem.readInt(u32, self.m[o..][0..4], .big);
        return @as(u32, std.mem.readInt(u16, self.m[o..][0..2], .big)) << 16 | std.mem.readInt(u16, self.m[o + 2 ..][0..2], .big);
    }
    pub inline fn sb(self: *const Ram, a: u32, v: u8) void {
        self.m[self.at(a, 1)] = v;
    }
    pub inline fn sw(self: *const Ram, a: u32, v: u16) void {
        std.mem.writeInt(u16, self.m[self.at(a, 2)..][0..2], v, .big);
    }
    pub inline fn sl(self: *const Ram, a: u32, v: u32) void {
        const o = self.at(a, 4);
        if ((@intFromPtr(self.m.ptr) + o) & 3 == 0) return std.mem.writeInt(u32, self.m[o..][0..4], v, .big);
        std.mem.writeInt(u16, self.m[o..][0..2], @truncate(v >> 16), .big);
        std.mem.writeInt(u16, self.m[o + 2 ..][0..2], @truncate(v), .big);
    }
    pub inline fn bytes(self: *const Ram, a: u32, n: usize) []u8 {
        return self.m[self.at(a, n)..][0..n];
    }
    /// A forward copy, as move.l (a2)+,(a3)+ makes one (never overlapping here).
    pub inline fn cp(self: *const Ram, dst: u32, src: u32, n: usize) void {
        @memcpy(self.bytes(dst, n), self.bytes(src, n));
    }
};

/// ST colour word -> Color, channel c * 255 / 7 as the other ST ports do.
/// (A table of the 8 levels: rows load 16 colours each, 247 rows a frame.)
const LEVEL: [8]u8 = blk: {
    var t: [8]u8 = undefined;
    for (&t, 0..) |*v, c| v.* = @intCast(c * 255 / 7);
    break :blk t;
};

pub fn color(v: u16) zg.Color {
    return .{ .r = LEVEL[(v >> 8) & 7], .g = LEVEL[(v >> 4) & 7], .b = LEVEL[v & 7], .a = 255 };
}

/// The shifter's planar -> chunky (planar.zig: no zigos import, so its test
/// runs natively from apps/zig/scene_tests.zig).
pub const lineToChunky = @import("planar.zig").lineToChunky;
