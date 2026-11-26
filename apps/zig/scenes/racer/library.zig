// --------------------------------------------------------------------------
// RACER: the track library (M5 step 2). The oval is built in (the gate's fallback, and the recorded
// button streams are its); every other track is a FILE: each `*.KTR` on the cart's own disk (zg.disk's
// FAT, in the FAT's order) and in C:\RACER\ (KOS GEMDOS: a user's own tracks on the SD card's /HD).
// A file is the converter's v3 binary (tools/racer/trackc.py), raw or ZX0-packed (tools/mkdisks.sh
// packs the disk's). The scan reads each file's first block only; a track is read into ONE buffer
// when it is chosen and parsed there (trk.parse bounds every count and offset), and a bad file is
// refused by name with the reason, never trapped on. docs/ports/kestrel_racing/M5.md.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const gemdos = @import("kos_gemdos");
const zx0 = @import("depackers").zx0;
const data = @import("data.zig");
const refusals = @import("refusals.zig");
const trk = @import("trk.zig");
const Preview = @import("preview.zig").Preview;
// The select's previews: a module variable, not a field, so no `self.* = .{}` copies a 9 KB default blob (the struct-default trap).
var previews: [MAX]Preview = undefined;

pub const MAX = 16; // tracks listed, the oval included
pub const MAX_FILE: u32 = 1 << 20; // a track's bytes once depacked (the stress city: 755,720)
pub const MAX_VERTS = 25600; // the frame's vertex cache (the stress city: 25,009)
pub const MAX_FACES = 10240; // ... and its face stamps (the stress city: 9,904)
const hdfile = @import("hdfile.zig");
pub const HD_DIR = hdfile.HD_DIR;
pub const hdRead = hdfile.hdRead;
const hdPath = hdfile.hdPath;
const RESERVE: usize = 64 * 1024; // cart RAM left for everything allocated after the library
const BLOCK = 512;

pub const Source = enum { builtin, disk, hd };
pub const Fail = error{ BadPack, ReadFailed, TooBig } || trk.Error;

pub const Entry = struct {
    name: [8]u8 = .{0} ** 8,
    src: Source = .builtin,
    start: u32 = 0, // disk: the file's byte offset in the image
    stored: u32 = 0, // its bytes on the medium
    raw: u32 = 0, // its bytes once depacked (= stored when raw)
    bad: bool = false,
    why: []const u8 = "", // the loader's reason when bad (an error name: the select screen shows it)

    pub fn label(self: *const Entry) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
    fn packed_(self: *const Entry) bool {
        return self.raw != self.stored;
    }
};

pub const Library = struct {
    list: [MAX]Entry = .{Entry{}} ** MAX,
    n: usize = 1,
    buf: []align(4) u8 = &.{}, // the one loaded track's bytes
    stage: []u8 = &.{}, // a packed file's bytes before the depack
    blocks: u32 = 0, // disk blocks the last load read (the board estimate: docs M5.md)
    rej: refusals.Refusals = .{}, // the files refused at the scan, by name and reason (the select screen lists them)
    cars: @import("cars.zig").Cars = .{}, // the car files (M5): their buffers are carved before the track buffer's

    /// The oval, then the disk's files, then C:'s; the car buffer; then the two track buffers, sized to the largest file listed.
    pub fn scan(self: *Library, now: *const fn () u32) void {
        self.* = .{};
        @memcpy(self.list[0].name[0..4], "OVAL");
        self.list[0].raw = @intCast(data.oval.len);
        if (zg.disk.mount()) |lay| self.scanDisk(lay);
        self.scanHd();
        self.cars.init();
        self.size();
        self.cars.share(self.stage); // a car file stages in the track stage (a track is loaded before its cars)
        self.previewAll(now);
    }

    /// What the select shows of entry `i` (previewAll's).
    pub fn preview(self: *const Library, i: usize) *const Preview {
        _ = self;
        return &previews[i];
    }

    /// Every listed track loaded once, for what the select shows (preview.zig); a file the loader refuses is marked bad here.
    fn previewAll(self: *Library, now: *const fn () u32) void {
        const t0 = now();
        for (0..self.n) |i| {
            const e = &self.list[i];
            previews[i] = .{};
            const t = self.load(i) catch |err| {
                e.bad = true;
                e.why = @errorName(err);
                zg.Console.log("racer,track,refused,{s},{s}", .{ e.label(), e.why });
                continue;
            };
            previews[i] = Preview.of(&t);
        }
        zg.Console.log("racer,scan,{},{}", .{ self.n, now() -% t0 }); // the boot's cost of the previews (us)
    }

    fn scanDisk(self: *Library, lay: zg.disk.Layout) void {
        var i: u16 = 0;
        while (i < lay.count and self.n < MAX) : (i += 1) {
            const e = zg.disk.entryAt(lay, i) orelse continue;
            const name = std.mem.sliceTo(&e.name, 0);
            if (!std.ascii.endsWithIgnoreCase(name, ".KTR")) continue;
            var head: [BLOCK]u8 = undefined;
            const got = zg.disk.read(e.e, &head);
            self.add(name, .disk, e.e.start, e.e.len, head[0..got]);
        }
    }

    fn scanHd(self: *Library) void {
        const dos = gemdos.dos();
        var dta: gemdos.Dta = .{};
        dos.Fsetdta(&dta);
        var r = dos.Fsfirst(HD_DIR ++ "*.KTR", 0);
        while (r == 0 and self.n < MAX) : (r = dos.Fsnext()) {
            const name = std.mem.sliceTo(&dta.name, 0);
            var head: [BLOCK]u8 = undefined;
            var path: [32]u8 = undefined;
            const got = hdRead(hdPath(&path, name), head[0..]) catch continue;
            self.add(name, .hd, 0, std.mem.readInt(u32, &dta.length, .little), head[0..got]);
        }
    }

    /// One listed file from its first bytes: a v3 header (its size must be the file's) or a ZX0 header.
    fn add(self: *Library, name: []const u8, src: Source, start: u32, stored: u32, head: []const u8) void {
        const raw = rawLen(head, stored) orelse return self.rej.add(name, .not_track);
        if (raw > MAX_FILE) return self.rej.add(name, .too_big);
        var e = Entry{ .src = src, .start = start, .stored = stored, .raw = raw };
        const stem = name[0 .. std.mem.indexOfScalar(u8, name, '.') orelse name.len];
        @memcpy(e.name[0..@min(stem.len, 8)], stem[0..@min(stem.len, 8)]);
        self.list[self.n] = e;
        self.n += 1;
    }

    /// The buffers for the largest files; files that do not fit the RAM left are dropped from the list, the largest first.
    fn size(self: *Library) void {
        while (self.n > 1) {
            var raw: usize = 0;
            var stage: usize = 0;
            var big: usize = 1;
            for (self.list[1..self.n], 1..) |e, i| {
                raw = @max(raw, e.raw);
                if (e.packed_()) stage = @max(stage, e.stored, @import("carfile.zig").MAX_FILE); // the car files' too
                if (e.raw > self.list[big].raw) big = i;
            }
            const need = std.mem.alignForward(usize, raw, 4) + std.mem.alignForward(usize, stage, 4);
            if (need + RESERVE <= zg.mem.free()) {
                self.buf = std.mem.sliceAsBytes(zg.mem.mustAlloc(u32, (raw + 3) / 4))[0..raw];
                self.stage = std.mem.sliceAsBytes(zg.mem.mustAlloc(u32, (stage + 3) / 4))[0..stage];
                return;
            }
            self.rej.add(self.list[big].label(), .no_ram);
            std.mem.copyForwards(Entry, self.list[big .. self.n - 1], self.list[big + 1 .. self.n]);
            self.n -= 1;
        }
    }

    /// The boot log: the list, the buffer and the RAM left (racer_tracks.mjs reads the free KB).
    pub fn report(self: *const Library) void {
        zg.Console.log("racer: {} tracks, buffer {} KB, cart RAM free {} KB", .{ self.n, self.buf.len / 1024, zg.mem.free() / 1024 });
        for (self.list[0..self.n]) |*e| zg.Console.log("racer,track,{s},{s},{},{}", .{ e.label(), @tagName(e.src), e.stored, e.raw });
    }

    /// Track `i` into the buffer (the built-in oval needs none) and parsed. The buffer's old track is gone either way.
    pub fn load(self: *Library, i: usize) Fail!trk.Track {
        const e = &self.list[i];
        if (e.src == .builtin) return trk.parse(data.oval);
        if (e.raw > self.buf.len or (e.packed_() and e.stored > self.stage.len)) return error.TooBig;
        const dst = if (e.packed_()) self.stage[0..e.stored] else self.buf[0..e.raw];
        self.blocks = (e.start % BLOCK + e.stored + BLOCK - 1) / BLOCK;
        switch (e.src) {
            .disk => if (zg.disk.read(.{ .start = e.start, .len = e.stored, .kind = 0 }, dst) != dst.len) return error.ReadFailed,
            .hd => {
                var path: [32]u8 = undefined;
                var full: [16]u8 = undefined;
                const name = std.fmt.bufPrint(&full, "{s}.KTR", .{e.label()}) catch return error.ReadFailed;
                if ((hdRead(hdPath(&path, name), dst) catch return error.ReadFailed) != dst.len) return error.ReadFailed;
            },
            .builtin => unreachable,
        }
        if (e.packed_() and (zx0.depack(dst, self.buf[0..e.raw]) orelse 0) != e.raw) return error.BadPack;
        const t = try trk.parse(self.buf[0..e.raw]);
        if (t.verts.len > MAX_VERTS or t.faces.len > MAX_FACES) return error.TooBig;
        return t;
    }
};

/// The built-in oval (a bad one is a build mistake: it stops the cart).
pub fn builtin() trk.Track {
    return trk.parse(data.oval) catch |e| @panic(@errorName(e));
}

/// The size a file's first bytes say it depacks to: a v3 track whose total is the file's size, or a ZX0 image's stated length.
pub fn rawLen(head: []const u8, stored: u32) ?u32 {
    if (zx0.isPacked(head)) return zx0.depackedLen(head);
    if (head.len < 16 or std.mem.readInt(u32, head[0..4], .little) != trk.MAGIC) return null;
    if (std.mem.readInt(u32, head[4..8], .little) != trk.VERSION) return null;
    const total = std.mem.readInt(u32, head[12..16], .little);
    return if (total == stored) total else null;
}
