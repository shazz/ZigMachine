// --------------------------------------------------------------------------
// The battle's own memory, byte for byte.
//
// ns.app is compiled C (Aztec, 16-bit int) and keeps ALL of the battle's state
// in its data/BSS segment. The port keeps the same bytes: `Mem.ram` is flat
// $1C3F0..$1DA80 (RAM = flat + $D0A8 in the reference session), big-endian, so
// every field has the 68000's width, signedness and wrap, and the state can be
// compared byte for byte with the reference model (apps/north_south_headless.mjs).
// Pointers are stored exactly as the game stores them: absolute RAM addresses.
//
// The read-only tables (animation scripts, formations, decor lists, terrain,
// AI scripts, the joystick map) are ns.app's own bytes, flat $17E00..$18C20.
// --------------------------------------------------------------------------
const A = @import("assets.zig");

/// ns.app's load address in the reference session: RAM = flat + B.
pub const B: u32 = 0xD0A8;
/// The battle's variables: sound, RNG, records, objects, sides, grid and what
/// follows the grid (read by out-of-range grid lookups, as the original does).
pub const LO: u32 = 0x1C3F0;
pub const HI: u32 = 0x1DA80;
pub const SIZE: usize = HI - LO;

const ROM_LO: u32 = 0x17E00;
const ROM_HI: u32 = 0x18C20;

/// Reads outside the two windows. The original would read other RAM there; the
/// reference model never does on any scripted frame, and the harness asserts
/// this stays 0, so a port path that strays is caught rather than guessed.
pub var misses: u32 = 0;

/// Sign-extend the low 16 bits (a C int stored and read back).
pub inline fn s16(v: i32) i32 {
    return @as(i16, @truncate(v));
}

/// `mulu.w`, low word, used as a signed word by the callers.
pub inline fn muluW(a: i32, b: i32) i32 {
    const p = @as(u32, @as(u16, @truncate(@as(u32, @bitCast(a))))) *% @as(u32, @as(u16, @truncate(@as(u32, @bitCast(b)))));
    return s16(@bitCast(p));
}

pub const Mem = struct {
    ram: [SIZE]u8,

    inline fn at(a: u32, n: u32) ?usize {
        if (a < LO or a + n > HI) {
            misses += 1;
            return null;
        }
        return a - LO;
    }

    /// Signed word.
    pub fn w(self: *const Mem, a: u32) i32 {
        const i = at(a, 2) orelse return 0;
        return @as(i16, @bitCast(@as(u16, self.ram[i]) << 8 | self.ram[i + 1]));
    }
    pub fn setw(self: *Mem, a: u32, v: i32) void {
        const i = at(a, 2) orelse return;
        const u: u16 = @truncate(@as(u32, @bitCast(v)));
        self.ram[i] = @truncate(u >> 8);
        self.ram[i + 1] = @truncate(u);
    }
    pub fn addw(self: *Mem, a: u32, v: i32) void {
        self.setw(a, self.w(a) + v);
    }
    /// Unsigned byte.
    pub fn b(self: *const Mem, a: u32) i32 {
        const i = at(a, 1) orelse return 0;
        return self.ram[i];
    }
    /// Signed byte.
    pub fn sb(self: *const Mem, a: u32) i32 {
        const i = at(a, 1) orelse return 0;
        return @as(i8, @bitCast(self.ram[i]));
    }
    pub fn setb(self: *Mem, a: u32, v: i32) void {
        const i = at(a, 1) orelse return;
        self.ram[i] = @truncate(@as(u32, @bitCast(v)));
    }
    /// Long (a pointer).
    pub fn l(self: *const Mem, a: u32) u32 {
        const i = at(a, 4) orelse return 0;
        return @as(u32, self.ram[i]) << 24 | @as(u32, self.ram[i + 1]) << 16 |
            @as(u32, self.ram[i + 2]) << 8 | self.ram[i + 3];
    }
    pub fn setl(self: *Mem, a: u32, v: u32) void {
        const i = at(a, 4) orelse return;
        self.ram[i] = @truncate(v >> 24);
        self.ram[i + 1] = @truncate(v >> 16);
        self.ram[i + 2] = @truncate(v >> 8);
        self.ram[i + 3] = @truncate(v);
    }
    /// Word at a RAM pointer: inside the battle variables or in ns.app's tables.
    pub fn derefW(self: *const Mem, ptr: u32) i32 {
        const a = ptr -% B;
        if (a >= LO and a < HI) return self.w(a);
        return romW(a);
    }
    pub fn derefSb(self: *const Mem, ptr: u32) i32 {
        const a = ptr -% B;
        if (a >= LO and a < HI) return self.sb(a);
        return romSb(a);
    }
};

inline fn romAt(a: u32, n: u32) ?usize {
    if (a < ROM_LO or a + n > ROM_HI) {
        misses += 1;
        return null;
    }
    return a - ROM_LO;
}

/// Signed word of ns.app's tables (flat address).
pub fn romW(a: u32) i32 {
    const i = romAt(a, 2) orelse return 0;
    return @as(i16, @bitCast(@as(u16, A.rom[i]) << 8 | A.rom[i + 1]));
}
pub fn romB(a: u32) i32 {
    const i = romAt(a, 1) orelse return 0;
    return A.rom[i];
}
pub fn romSb(a: u32) i32 {
    const i = romAt(a, 1) orelse return 0;
    return @as(i8, @bitCast(A.rom[i]));
}
