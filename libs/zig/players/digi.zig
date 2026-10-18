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
pub const monty = @import("digi_monty.zig");
pub const wow = @import("digi_wow.zig");
pub const irq = @import("digi_irq.zig");

pub const Status = enum(u32) {
    musashi = 0, // no known handler: the general path
    beat_dis = 1, // native, players/digi_beatdis.zig
    near_miss_sequencer = 2, // the handler is there, the sequencer is not one we know
    near_miss_data = 3, // the driver matched, its tables point outside the image
    disabled = 4, // a known driver, but native replays are switched off
    monty = 5, // native, players/digi_monty.zig (Mad Max's Monty digidrums, Timer D)
    wow = 6, // native, players/digi_wow.zig (MAN Cool's Wow Scroller, Timer A)
    big_digital = 7, // handler native, digi_big.zig (Mad Max's 3-voice mixer: the B.I.G. Demo's digital tunes)
    hippel_mix4 = 8, // handler native, digi_mix4.zig (Hippel's 4-voice mixer: Thalion Forever)
    tcb_digi = 10, // handler native, digi_tcb.zig (the Swedish New Year Demo's TCB 1 one-byte digi)
    sync_mix4 = 11, // handler native, digi_sync4.zig (the Swedish New Year Demo's self-modifying 4-voice mixer)
    mix3_timer_c = 12, // handler native, digi_mix3.zig (a 3-voice mixer on Timer C: snyd_90's part 6)
    tcb_streams = 13, // handler native, digi_tcb3.zig (three volume streams: TCB's Spreadpoint)
    mym_drums = 14, // handler native, digi_mym.zig (maxYMiser's digidrums: crystallized)
};

pub const Driver = union(enum) {
    beat_dis: beat_dis.Driver,
    monty: monty.Driver,
    wow: wow.Driver,
    irq: irq.Driver, // the timer handler only: init, play and exit on Musashi (digi_irq.zig)
};

/// What mode 3 needs of a byte-a-tick driver: where its sample pointer and the
/// segment's end live, where its samples start, and the timer's rate. Its bytes
/// are unsigned and inverted, as handler.linear says (the same volume table).
pub const Pcm = struct { cur: u32, end: u32, lo: u32, hz: f32 };

pub fn pcmOf(d: Driver) ?Pcm {
    return switch (d) {
        .beat_dis => |bd| .{ .cur = bd.handler.cur, .end = bd.handler.cur + 4, .lo = beat_dis.samples(bd), .hz = 2457600.0 / 4.0 / 39.0 },
        .wow => |wd| .{ .cur = wd.base + wow.CUR, .end = wd.base + wow.END, .lo = wd.base + wow.DATA, .hz = wow.HZ },
        .monty => null, // 4-bit drums on one channel, not this table: no PCM path
        .irq => null, // mixers and other tables: no PCM path
    };
}

pub const Recognition = struct {
    status: Status = .musashi,
    driver: ?Driver = null,
};

/// `image` is the tune as loaded, at 68000 address `base`.
pub fn recognise(image: []const u8, base: u32) Recognition {
    if (monty.match(image, base)) |d| return .{ .status = .monty, .driver = .{ .monty = d } };
    if (irq.recognise(image, base)) |d| return .{ .status = irq.status(d), .driver = .{ .irq = d } };
    if (wow.match(image, base)) |d| {
        if (!wow.tablesFit(image)) return .{ .status = .near_miss_data };
        return .{ .status = .wow, .driver = .{ .wow = d } };
    }
    const found = handler.find(image) orelse return .{};
    const d = beat_dis.match(image, base) orelse return .{ .status = .near_miss_sequencer };
    if (d.handler.addr != base + found or !beat_dis.tablesFit(image, base, d)) return .{ .status = .near_miss_data };
    return .{ .status = .beat_dis, .driver = .{ .beat_dis = d } };
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
/// bus): a long is two words, high first, as Musashi does them. A Bus with `mem`
/// (the 68000's RAM) is read and written there directly for an address in RAM:
/// the bytes the bus functions would reach, without a call per byte, which on
/// BARD was most of a native interrupt's cost.
pub fn Access(comptime Bus: type) type {
    return struct {
        /// The `n` bytes at `a` in RAM, or null (hardware, or a Bus without `mem`).
        inline fn ram(a: u32, comptime n: u32) ?*[n]u8 {
            if (comptime !@hasDecl(Bus, "mem")) return null;
            const m = Bus.mem();
            const x = a & 0xFFFFFF;
            return if (x + n <= m.len) m[x..][0..n] else null;
        }
        pub fn rd16(a: u32) u16 {
            if (ram(a, 2)) |r| return std.mem.readInt(u16, r, .big);
            return (@as(u16, Bus.read8(a)) << 8) | Bus.read8(a +% 1);
        }
        pub fn rd32(a: u32) u32 {
            if (ram(a, 4)) |r| return std.mem.readInt(u32, r, .big);
            return (@as(u32, rd16(a)) << 16) | rd16(a +% 2);
        }
        pub fn wr16(a: u32, v: u16) void {
            if (ram(a, 2)) |r| return std.mem.writeInt(u16, r, v, .big);
            Bus.write16(a, v);
        }
        pub fn wr32(a: u32, v: u32) void {
            if (ram(a, 4)) |r| return std.mem.writeInt(u32, r, v, .big);
            Bus.write16(a, @truncate(v >> 16));
            Bus.write16(a +% 2, @truncate(v));
        }
        pub fn rd8(a: u32) u8 {
            if (ram(a, 1)) |r| return r[0];
            return Bus.read8(a);
        }
        pub fn wr8(a: u32, v: u8) void {
            if (ram(a, 1)) |r| {
                r[0] = v;
                return;
            }
            Bus.write8(a, v);
        }
        /// bset / bclr #bit on a byte in memory: a read, then a write.
        pub fn bset(a: u32, bit: u3) void {
            Bus.write8(a, Bus.read8(a) | @as(u8, 1) << bit);
        }
        pub fn bclr(a: u32, bit: u3) void {
            Bus.write8(a, Bus.read8(a) & ~(@as(u8, 1) << bit));
        }
        pub fn btst(a: u32, bit: u3) bool {
            return Bus.read8(a) & @as(u8, 1) << bit != 0;
        }
    };
}
