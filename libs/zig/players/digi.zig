// --------------------------------------------------------------------------
// Native replays for SNDH drivers the machine recognises: the tune's own 68000
// routines, rewritten in Zig, run where the SNDH player would call them on
// Musashi. Everything around the calls is still the SNDH player's (its clock,
// its MFP, its PSG), so the YM writes and their stamps come out the same by
// construction. The test that holds them to it is fpga/tests/test_sndh_native.py:
// the whole tune, write for write, against Musashi.
//
// Why: a digi tune interrupts 263 times a 60 Hz frame, and on the sound CPU each
// interrupt costs ~14.6 k cycles on Musashi for ~26 instructions of 68000
// (docs/FPGA_SOUND_CPU.md "Native players"). Natively it is a few hundred.
//
// A driver is a timer HANDLER, often shared between tunes, plus a SEQUENCER
// (init / play / exit), usually one tune's own. Recognition is all or nothing:
// both signatures, then the tables checked in range. A handler found with an
// unknown sequencer, or tables out of range, is a NEAR MISS: Musashi plays it and
// the status says why (the host prints it), never a native path guessed at.
// --------------------------------------------------------------------------
const std = @import("std");
pub const handler = @import("digi_handler.zig");
pub const beat_dis = @import("digi_beatdis.zig");

pub const Status = enum(u32) {
    musashi = 0, // no known handler: the general path
    beat_dis = 1, // native, players/digi_beatdis.zig
    near_miss_sequencer = 2, // the handler is there, the sequencer is not one we know
    near_miss_data = 3, // the driver matched, its tables point outside the image
    disabled = 4, // a known driver, but native replays are switched off
};

pub const Recognition = struct {
    status: Status = .musashi,
    driver: ?beat_dis.Driver = null,
};

/// `image` is the tune as loaded, at 68000 address `base`.
pub fn recognise(image: []const u8, base: u32) Recognition {
    const found = handler.find(image) orelse return .{};
    const d = beat_dis.match(image, base) orelse return .{ .status = .near_miss_sequencer };
    if (d.handler.addr != base + found or !beat_dis.tablesFit(image, base, d)) return .{ .status = .near_miss_data };
    return .{ .status = .beat_dis, .driver = d };
}

/// FNV-1a 64 over `bytes` with the ranges in `holes` read as zero: a signature
/// that ignores a routine's state words and its PC-relative displacements.
pub fn maskedHash(bytes: []const u8, holes: []const [2]u32) u64 {
    var h: u64 = 0xCBF29CE484222325;
    for (bytes, 0..) |b, i| {
        var v = b;
        for (holes) |r| {
            if (i >= r[0] and i < r[1]) v = 0;
        }
        h = (h ^ v) *% 0x100000001B3;
    }
    return h;
}

pub fn be16(image: []const u8, off: usize) u16 {
    return std.mem.readInt(u16, image[off..][0..2], .big);
}

pub fn be32(image: []const u8, off: usize) u32 {
    return std.mem.readInt(u32, image[off..][0..4], .big);
}

/// The target of `lea d16(pc),An` whose opcode is at 68000 address `at`.
pub fn pcRel(at: u32, disp: u16) u32 {
    return at +% 2 +% @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(disp)))));
}

/// A 68000's long and word accesses on `Bus` (read8 / write16, the SNDH player's
/// bus): a long is two words, high first, as Musashi does them.
pub fn Access(comptime Bus: type) type {
    return struct {
        pub fn rd16(a: u32) u16 {
            return (@as(u16, Bus.read8(a)) << 8) | Bus.read8(a +% 1);
        }
        pub fn rd32(a: u32) u32 {
            return (@as(u32, rd16(a)) << 16) | rd16(a +% 2);
        }
        pub fn wr16(a: u32, v: u16) void {
            Bus.write16(a, v);
        }
        pub fn wr32(a: u32, v: u32) void {
            Bus.write16(a, @truncate(v >> 16));
            Bus.write16(a +% 2, @truncate(v));
        }
    };
}
