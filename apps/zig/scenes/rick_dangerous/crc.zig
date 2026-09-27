// --------------------------------------------------------------------------
// The state's fingerprint, as tools/rick_dangerous/make_fixture.py computes it
// from the reference model: CRC-32 (zlib's) over the harness's snapshot
// regions (every byte the game writes in its loop, prototypes/rick_re/
// harness/regions.json), then the video base (big-endian long) and the 16
// colour registers (big-endian words).
// --------------------------------------------------------------------------
const std = @import("std");
const m = @import("ram.zig");
const game = @import("game.zig");

pub const REGIONS = [_][2]usize{
    .{ 0x34A7E, 0x34A88 }, .{ 0x34B18, 0x34B97 }, .{ 0x34EBC, 0x34F0B }, .{ 0x3524A, 0x3524E },
    .{ 0x37C66, 0x389CA }, .{ 0x38A42, 0x38A4C }, .{ 0x38CAC, 0x38CAF }, .{ 0x38D68, 0x38D6F },
    .{ 0x38DB6, 0x38DB7 }, .{ 0x39042, 0x39062 }, .{ 0x39342, 0x39348 }, .{ 0x3980C, 0x3980E },
    .{ 0x39C00, 0x3A564 }, .{ 0x3ADA8, 0x3ADD9 }, .{ 0x3AFA0, 0x3AFA4 }, .{ 0x3B000, 0x3B010 },
    .{ 0x3B23A, 0x3B242 }, .{ 0x3B89A, 0x3B8A0 }, .{ 0x3B994, 0x3B9B2 }, .{ 0x3BA3A, 0x3BA44 },
    .{ 0x3CA8C, 0x3CA8E }, .{ 0x3D6AA, 0x3D6AC }, .{ 0x3D8BE, 0x3D8EA }, .{ 0x3D974, 0x3D994 },
    .{ 0x63810, 0x80000 },
};

pub fn state() u32 {
    var h = std.hash.Crc32.init();
    for (REGIONS) |r| h.update(m.mem[r[0]..r[1]]);
    var b: [4 + 32]u8 = undefined;
    std.mem.writeInt(u32, b[0..4], @truncate(@as(u64, @bitCast(game.vbase))), .big);
    for (game.pal, 0..) |p, i| std.mem.writeInt(u16, b[4 + 2 * i ..][0..2], @truncate(@as(u64, @bitCast(p))), .big);
    h.update(&b);
    return h.final();
}

/// The snapshot regions' total length (the harness's init snapshot must match).
pub fn regionBytes() usize {
    var n: usize = 0;
    for (REGIONS) |r| n += r[1] - r[0];
    return n;
}

/// Load a harness snapshot (the regions, concatenated) into the memory.
pub fn load(snap: []const u8) void {
    var p: usize = 0;
    for (REGIONS) |r| {
        const n = r[1] - r[0];
        @memcpy(m.mem[r[0]..r[1]], snap[p..][0..n]);
        p += n;
    }
}
