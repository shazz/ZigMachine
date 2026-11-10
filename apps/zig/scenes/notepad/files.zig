// --------------------------------------------------------------------------
// NOTEPAD's files: C:\*.TXT through KOS GEMDOS (docs/KOS_GEMDOS.md), as a TOS
// program reads and writes them: Fsfirst / Fsnext for the ITEM SELECTOR's list,
// Fopen / Fread / Fclose to open, Fcreate / Fwrite / Fclose to save (the host
// writes the whole file at Fclose, through a temporary name: a failed save
// leaves the old file whole). Lines are saved with CR LF, as ST editors wrote
// them; a file read may have either. Every failure is GEMDOS's negative code.
// --------------------------------------------------------------------------
const std = @import("std");
const gemdos = @import("kos_gemdos");
const Text = @import("text.zig").Text;

pub const FOLDER = "C:\\";
pub const MASK = "C:\\*.TXT";
pub const MAX_LIST = 32; // the ITEM SELECTOR's list (rom/gem/desktop/filesel_list.zig MAX_FILES)

pub const Fail = union(enum) { dos: i32, too_big, too_many_lines };

/// Names of C:\*.TXT for the selector, in the order GEMDOS gives them.
pub fn list(out: *[MAX_LIST][13]u8, lens: *[MAX_LIST]u8) usize {
    const dos = gemdos.dos();
    var dta: gemdos.Dta = .{};
    dos.Fsetdta(&dta);
    var n: usize = 0;
    var r = dos.Fsfirst(MASK, 0);
    while (r == 0 and n < MAX_LIST) : (r = dos.Fsnext()) {
        const len = std.mem.indexOfScalar(u8, &dta.name, 0) orelse dta.name.len;
        const k = @min(len, 13);
        @memcpy(out[n][0..k], dta.name[0..k]);
        lens[n] = @intCast(k);
        n += 1;
    }
    return n;
}

/// "C:\" + name into `buf`.
pub fn path(name: []const u8, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}{s}", .{ FOLDER, name }) catch buf[0..0];
}

/// The file into `io` (a byte more than the largest file it takes), then into the text.
pub fn load(p: []const u8, io: []u8, t: *Text) ?Fail {
    const dos = gemdos.dos();
    const h = dos.Fopen(p, 0);
    if (h < 0) return .{ .dos = h };
    defer _ = dos.Fclose(h);
    var got: usize = 0;
    while (got < io.len) {
        const r = dos.Fread(h, @intCast(io.len - got), io.ptr + got);
        if (r < 0) return .{ .dos = r };
        if (r == 0) break;
        got += @intCast(r);
    }
    if (got == io.len) return .too_big; // the buffer filled: the file is longer than it
    t.load(io[0..got]) catch |e| return switch (e) {
        error.Full => .too_big,
        error.TooManyLines => .too_many_lines,
    };
    return null;
}

/// The text with CR LF line ends, written as `p` (replacing it).
pub fn save(p: []const u8, io: []u8, t: *const Text) ?Fail {
    var n: usize = 0;
    for (t.bytes()) |c| {
        if (n + 2 > io.len) return .too_big;
        if (c == '\n') {
            io[n] = '\r';
            n += 1;
        }
        io[n] = c;
        n += 1;
    }
    const dos = gemdos.dos();
    const h = dos.Fcreate(p, 0);
    if (h < 0) return .{ .dos = h };
    const w = dos.Fwrite(h, @intCast(n), io.ptr);
    const c = dos.Fclose(h); // the save itself: the host writes the file here
    if (w < 0) return .{ .dos = w };
    if (c < 0) return .{ .dos = c };
    return null;
}

pub const txtName = @import("names.zig").txtName;
