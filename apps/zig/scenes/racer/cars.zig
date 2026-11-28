// --------------------------------------------------------------------------
// RACER: the cars off the disk (M5 car files, Track Kit spirit). When a track goes on show the cart
// looks for `<TRACK>.KCR` (that track's cars), then `CAR.KCR` (every track's), on its own disk and
// then in C:\RACER\ (a user's, as for tracks), and draws the first it finds; with none, the built-in
// GT. A file is the converter's car (tools/racer/carc.py: v1 one model, v2 a set with its own
// colours), raw or ZX0-packed (tools/mkdisks.sh packs the disk's), read whole into one buffer and
// parsed there (carfile.parse bounds every count and offset). A bad file is refused by name with its
// reason (the console and the track select's refusals) and the next one is tried (a bad track's own file
// falls back to CAR.KCR, then the built-in GT): never a trap.
// Board batch: the garage (garage.zig) lists every car file; once the player picks one (the car select, key ]) it is
// drawn on every track instead, and a tagged set's class becomes the car class. docs/ports/kestrel_racing/M5.md, BATCH.md.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const zx0 = @import("depackers").zx0;
const carfile = @import("carfile.zig");
const carmodel = @import("carmodel.zig");
const library = @import("library.zig");
const refusals = @import("refusals.zig");
const garage = @import("garage.zig");
const arcade = @import("arcade.zig");

pub const Fail = error{ ReadFailed, TooBig, BadPack } || carfile.Error;

pub const Cars = struct {
    buf: []align(4) u8 = &.{}, // the car file's bytes, depacked: the active set's slices point here
    stage: []u8 = &.{}, // the file as stored (packed or raw): the track library's stage, shared (library.scan)
    shown: [12]u8 = .{0} ** 12, // the file on show ("" = the built-in GT)
    garage: garage.Garage = .{},

    /// The buffer, carved once at init (before the track library takes what the RAM window has left).
    pub fn init(self: *Cars) void {
        self.buf = std.mem.sliceAsBytes(zg.mem.mustAlloc(u32, carfile.MAX_FILE / 4));
    }

    /// The staging bytes: the track library's stage (a car is read after its track, so they never overlap), or our own when
    /// the library has none big enough (no packed track listed).
    pub fn share(self: *Cars, stage: []u8) void {
        self.stage = if (stage.len >= carfile.MAX_FILE) stage else std.mem.sliceAsBytes(zg.mem.mustAlloc(u32, carfile.MAX_FILE / 4));
        @import("setup.zig").scratch(self.stage); // the board batch's per-frame scratch shares it too
    }

    /// The cars for track `track` (its label): the player's pick, else its own file, the global one, or the built-in GT.
    pub fn forTrack(self: *Cars, track: []const u8, rej: *refusals.Refusals) void {
        if (self.garage.pick) |i| if (self.choose(i, rej)) return;
        carmodel.active = carmodel.builtin; // the buffer is about to change under the old set
        self.shown = .{0} ** 12;
        var own: [12]u8 = undefined;
        const names = [2][]const u8{ std.fmt.bufPrint(&own, "{s}.KCR", .{track[0..@min(track.len, 8)]}) catch "", "CAR.KCR" };
        for (names) |name| if (self.load(name, rej)) return; // a bad track's own file: the global one, else the GT
        zg.Console.log("racer,car,GT,1,0", .{}); // the built-in
    }

    /// Garage entry `i` on show (the GT, or its file): false when the file is missing or refused
    /// (the set on show is the GT then).
    pub fn choose(self: *Cars, i: usize, rej: *refusals.Refusals) bool {
        self.garage.pick = i;
        carmodel.active = carmodel.builtin;
        self.shown = .{0} ** 12;
        if (self.garage.isGt(i)) {
            zg.Console.log("racer,car,GT,1,0", .{});
            return true;
        }
        return self.load(self.garage.file(i), rej);
    }

    /// The garage entry on show (the pick, else the file the track's rule found, else the GT).
    pub fn current(self: *const Cars) usize {
        return self.garage.pick orelse self.garage.indexOf(std.mem.sliceTo(&self.shown, 0));
    }

    /// The name of the cars on show: a set's tag, its file's name, or the GT's.
    pub fn label(self: *const Cars) []const u8 {
        const tag = std.mem.sliceTo(&carmodel.active.name, 0);
        if (tag.len != 0) return tag;
        const f = std.mem.sliceTo(&self.shown, 0);
        return if (f.len == 0) garage.GT_LABEL else f[0 .. std.mem.indexOfScalar(u8, f, '.') orelse f.len];
    }

    /// File `name` read, parsed and on show (a tagged set's class taken); false when it is not there or refused (named, with its reason).
    fn load(self: *Cars, name: []const u8, rej: *refusals.Refusals) bool {
        const got = self.fetch(name) catch |err| {
            refuse(name, err, rej);
            return false;
        };
        const raw = got orelse return false;
        carmodel.active = carfile.parse(@alignCast(self.buf[0..raw])) catch |err| {
            carmodel.active = carmodel.builtin;
            refuse(name, err, rej);
            return false;
        };
        @memcpy(self.shown[0..name.len], name);
        if (carmodel.active.class) |c| if (!garage.break_tag) { // a tagged set (a 32X class's cars): its class
            arcade.class = c;
        };
        zg.Console.log("racer,car,{s},{},{}", .{ name, carmodel.active.n, raw });
        return true;
    }

    /// `name` read whole and depacked into the buffer: its length, or null when no such file is on the disk or in C:.
    fn fetch(self: *Cars, name: []const u8) Fail!?usize {
        const stored = (try self.readDisk(name)) orelse (try self.readHd(name)) orelse return null;
        const src = self.stage[0..stored];
        if (zx0.isPacked(src)) {
            const raw = zx0.depackedLen(src) orelse return error.BadPack;
            if (raw > self.buf.len) return error.TooBig;
            if ((zx0.depack(src, self.buf[0..raw]) orelse 0) != raw) return error.BadPack;
            return raw;
        }
        if (stored > self.buf.len) return error.TooBig; // a raw file: the stage is the track's, far bigger than the car buffer
        @memcpy(self.buf[0..stored], src);
        return stored;
    }

    fn readDisk(self: *Cars, name: []const u8) Fail!?usize {
        const lay = zg.disk.mount() orelse return null;
        const e = zg.disk.find(lay, name) orelse return null;
        if (e.len > self.stage.len or e.len > carfile.MAX_FILE) return error.TooBig;
        if (zg.disk.read(e, self.stage[0..e.len]) != e.len) return error.ReadFailed;
        return e.len;
    }

    fn readHd(self: *Cars, name: []const u8) Fail!?usize {
        var path: [32]u8 = undefined;
        const p = std.fmt.bufPrint(&path, library.HD_DIR ++ "{s}", .{name}) catch return null;
        const cap = @min(self.stage.len, carfile.MAX_FILE + 1); // one byte more than a car file may be: a longer one is TooBig
        const got = library.hdRead(p, self.stage[0..cap]) catch return null; // no such file
        if (got == cap) return error.TooBig;
        return if (got == 0) null else got;
    }
};

fn refuse(name: []const u8, err: Fail, rej: *refusals.Refusals) void {
    zg.Console.log("racer,car,refused,{s},{s}", .{ name, @errorName(err) });
    rej.add(name, .bad_car);
}
