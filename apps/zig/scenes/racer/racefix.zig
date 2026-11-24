// --------------------------------------------------------------------------
// RACER: the Lua reference's race fixtures (tools/racer/race_fixture.py) and the runners that
// play them through race.zig. Two formats: `RRAC` (every car's words every tick) and `RCRC` (a
// CRC-32 a tick, the finish ticks, sparse full rows). Used by the native tests; no ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const race = @import("race.zig");

const FULL0 = @embedFile("../../assets/screens/racer/race_npc2.bin");
const FULL1 = @embedFile("../../assets/screens/racer/race_ram.bin");
const CRC_RAW = @embedFile("../../assets/screens/racer/race_full.bin");
const full0: [FULL0.len]u8 align(16) = FULL0.*;
const full1: [FULL1.len]u8 align(16) = FULL1.*;
const crc_blob: [CRC_RAW.len]u8 align(16) = CRC_RAW.*;
pub const player_btn = @import("data.zig").race_v2;

pub const Which = enum { npc2, ram };

pub const Full = struct {
    cars: u32,
    ticks: u32,
    wpt: u32,
    words: []const i32,

    /// The state words of tick `t` (0-based); the player's buttons follow them.
    pub fn tick(self: Full, t: usize) []const i32 {
        return self.words[t * self.wpt ..][0 .. self.wpt - 1];
    }

    pub fn buttons(self: Full, t: usize) u8 {
        return @intCast(self.words[t * self.wpt + self.wpt - 1]);
    }
};

fn word(b: []const u8, i: usize) u32 {
    return std.mem.readInt(u32, b[i * 4 ..][0..4], .little);
}

pub fn full(which: Which) !Full {
    const b: []align(4) const u8 = switch (which) {
        .npc2 => &full0,
        .ram => &full1,
    };
    const n = word(b, 2) * word(b, 3);
    if (word(b, 0) != 0x43415252 or b.len != 16 + 4 * n) return error.BadFixture;
    const p: [*]const i32 = @ptrCast(@alignCast(&b[16]));
    return .{ .cars = word(b, 1), .ticks = word(b, 2), .wpt = word(b, 3), .words = p[0..n] };
}

pub const Crc = struct { cars: u32, ticks: u32, every: u32, finish: []const u32, crcs: []const u32 };

pub fn crc() !Crc {
    const b: []align(4) const u8 = &crc_blob;
    const n = word(b, 1);
    const nt = word(b, 2);
    if (word(b, 0) != 0x43524352) return error.BadFixture;
    const p: [*]const u32 = @ptrCast(@alignCast(&b[24]));
    return .{ .cars = n, .ticks = nt, .every = word(b, 4), .finish = p[0..n], .crcs = p[n..][0..nt] };
}

/// The tick (1-based) of the first difference between a race and the fixture rows, or null.
pub fn firstDiff(r: *race.Race, f: Full) ?u32 {
    var w: [race.WORDS]i32 = undefined;
    for (0..f.ticks) |t| {
        r.tick(f.buttons(t));
        if (!std.mem.eql(i32, r.words(&w), f.tick(t))) return @intCast(t + 1);
    }
    return null;
}

/// The CRC-32 of one tick's words, as the fixture writer takes it.
pub fn crcOf(r: *const race.Race) u32 {
    return r.crc();
}
