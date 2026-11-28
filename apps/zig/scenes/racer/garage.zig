// --------------------------------------------------------------------------
// RACER: the garage (R82 board batch, items 7 and 10): every car the cart can put on the road, for the car select and the
// in-race car switch (key ]). The car FILES are each `*.KCR` on the cart's own disk, then in C:\RACER\ (the same places
// cars.zig looks for a track's cars), listed once at boot by name, deduplicated, in disk order; the built-in GT is always
// the last entry. A file is only read when it is chosen (cars.zig loads, checks and refuses it by name as before).
// `pick` is the player's choice; null (until one is made) keeps the M5 rule: the track's own `<TRACK>.KCR`, the disk's
// `CAR.KCR`, else the GT. Choosing a tagged set (carfile.zig's TAG: a 32X class's cars) sets the car class too.
// The list logic is pure (coursemesh_test.zig tests it); `scan` is the only ZigOS part.
// --------------------------------------------------------------------------
const std = @import("std");

pub const MAX = 8; // car files listed (more are ignored: logged)
pub const GT_LABEL = "KESTREL GT";
pub var break_tag = false; // racer_batch.mjs --break tag (key >): a tagged set's class not taken

pub const Garage = struct {
    names: [MAX][12]u8 = undefined,
    n: usize = 0, // files listed: entries 0..n-1; entry n is the built-in GT
    pick: ?usize = null, // the player's choice, or null: the track's own cars (cars.forTrack)
    dropped: u32 = 0, // past MAX

    /// A file's name listed once (a name already listed, from the disk, wins over C:'s).
    pub fn add(self: *Garage, name: []const u8) void {
        if (name.len == 0 or name.len > 12) return;
        for (self.names[0..self.n]) |*x| if (std.ascii.eqlIgnoreCase(std.mem.sliceTo(x, 0), name)) return;
        if (self.n == MAX) {
            self.dropped += 1;
            return;
        }
        self.names[self.n] = @splat(0);
        @memcpy(self.names[self.n][0..name.len], name);
        self.n += 1;
    }

    /// Entries: the files and the GT.
    pub fn count(self: *const Garage) usize {
        return self.n + 1;
    }

    pub fn isGt(self: *const Garage, i: usize) bool {
        return i >= self.n;
    }

    /// Entry i's file name ("" for the GT).
    pub fn file(self: *const Garage, i: usize) []const u8 {
        return if (self.isGt(i)) "" else std.mem.sliceTo(&self.names[i], 0);
    }

    /// The entry `step` (+1 / -1) on from `i`, wrapping over the files and the GT.
    pub fn step(self: *const Garage, i: usize, dir: i32) usize {
        const n: i32 = @intCast(self.count());
        return @intCast(@mod(@as(i32, @intCast(@min(i, self.n))) + dir, n));
    }

    /// The entry showing file `shown` ("" = the GT): where a switch starts from before the player picked one.
    pub fn indexOf(self: *const Garage, shown: []const u8) usize {
        for (self.names[0..self.n], 0..) |*x, i| if (std.ascii.eqlIgnoreCase(std.mem.sliceTo(x, 0), shown)) return i;
        return self.n;
    }

    /// The disk's and C:'s *.KCR (the cart's own; not in native tests).
    pub fn scan(self: *Garage) void {
        const zg = @import("zigos");
        self.* = .{};
        if (zg.disk.mount()) |lay| {
            var i: u16 = 0;
            while (i < lay.count) : (i += 1) {
                const e = zg.disk.entryAt(lay, i) orelse continue;
                const name = std.mem.sliceTo(&e.name, 0);
                if (std.ascii.endsWithIgnoreCase(name, ".KCR")) self.add(name);
            }
        }
        const gemdos = @import("kos_gemdos");
        const dos = gemdos.dos();
        var dta: gemdos.Dta = .{};
        dos.Fsetdta(&dta);
        var r = dos.Fsfirst(@import("hdfile.zig").HD_DIR ++ "*.KCR", 0);
        while (r == 0) : (r = dos.Fsnext()) self.add(std.mem.sliceTo(&dta.name, 0));
        zg.Console.log("racer,garage,{},{}", .{ self.n, self.dropped });
    }
};
