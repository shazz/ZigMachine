// --------------------------------------------------------------------------
// MP3 PLAYER: the .MP3 files in C:\MUSIC (KOS GEMDOS Fsfirst / Fsnext), in
// name order, read once at start (and on R): a search is a few requests,
// never a per-frame cost.
// --------------------------------------------------------------------------
const std = @import("std");
const gemdos = @import("kos_gemdos");

pub const FOLDER = "C:\\MUSIC\\";
pub const MAX: usize = 64;

pub const Entry = struct {
    name: [14]u8 = [_]u8{0} ** 14,
    len: u8 = 0,
    size: u32 = 0,

    pub fn slice(self: *const Entry) []const u8 {
        return self.name[0..self.len];
    }
};

pub const List = struct {
    items: [MAX]Entry = [_]Entry{.{}} ** MAX,
    n: usize = 0,
    err: i32 = 0, // the search's answer when it found nothing (EPTHNF: no C:\MUSIC, EDRIVE: no C:)

    pub fn scan(self: *List) void {
        self.n = 0;
        const dos = gemdos.dos();
        var dta: gemdos.Dta = .{};
        dos.Fsetdta(&dta);
        var r = dos.Fsfirst(FOLDER ++ "*.MP3", 0);
        self.err = r;
        while (r == 0 and self.n < MAX) : (r = dos.Fsnext()) {
            const len = std.mem.indexOfScalar(u8, &dta.name, 0) orelse dta.name.len;
            var e = Entry{ .len = @intCast(len), .size = std.mem.readInt(u32, &dta.length, .little) };
            @memcpy(e.name[0..len], dta.name[0..len]);
            self.insert(e);
        }
    }

    fn insert(self: *List, e: Entry) void {
        var at = self.n;
        while (at > 0 and std.mem.order(u8, e.slice(), self.items[at - 1].slice()) == .lt) : (at -= 1) {
            self.items[at] = self.items[at - 1];
        }
        self.items[at] = e;
        self.n += 1;
    }

    /// "C:\MUSIC\NAME.MP3" into `buf`.
    pub fn path(self: *const List, i: usize, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{s}{s}", .{ FOLDER, self.items[i].slice() }) catch buf[0..0];
    }
};
