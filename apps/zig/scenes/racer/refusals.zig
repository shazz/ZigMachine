// --------------------------------------------------------------------------
// RACER: the track files the library refused at the scan (M5 step 4), kept by name and reason so the
// track select can show them (step 2 only logged them: on the board the player saw nothing). A file the
// LOADER refuses later stays in the list, marked bad, with its own reason (library.Entry.why). The
// console line is the same as step 2's: racer,track,refused,<NAME>,<why>.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

pub const MAX = 8; // more are logged, not kept

pub const Why = enum {
    not_track,
    too_big,
    no_ram,

    /// The console's reason (step 2's words: racer_library.mjs and the board logs read them).
    pub fn long(self: Why) []const u8 {
        return switch (self) {
            .not_track => "not a track (magic, version or size)",
            .too_big => "over the 1 MiB track buffer",
            .no_ram => "no cart RAM left for it",
        };
    }

    /// The select screen's (8 columns: the list's tag column).
    pub fn short(self: Why) []const u8 {
        return switch (self) {
            .not_track => "INVALID",
            .too_big => "TOO BIG",
            .no_ram => "NO RAM",
        };
    }
};

pub const Refusal = struct {
    name: [12]u8 = .{0} ** 12,
    why: Why = .not_track,

    pub fn label(self: *const Refusal) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
};

pub const Refusals = struct {
    list: [MAX]Refusal = .{Refusal{}} ** MAX,
    n: usize = 0,

    pub fn add(self: *Refusals, name: []const u8, why: Why) void {
        zg.Console.log("racer,track,refused,{s},{s}", .{ name, why.long() });
        if (self.n == MAX) return;
        var r = Refusal{ .why = why };
        const stem = name[0 .. std.mem.indexOfScalar(u8, name, '.') orelse name.len]; // the list shows 8.3 stems
        const k = @min(stem.len, r.name.len);
        @memcpy(r.name[0..k], stem[0..k]);
        self.list[self.n] = r;
        self.n += 1;
    }
};
