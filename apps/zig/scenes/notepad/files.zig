// --------------------------------------------------------------------------
// NOTEPAD's files: text files on C: through KOS GEMDOS (docs/KOS_GEMDOS.md), as a
// TOS program reads and writes them: Fsfirst / Fsnext for the ITEM SELECTOR's list
// (the folder's sub-folders, then the files its mask matches), Fopen / Fread /
// Fclose to open, Fcreate / Fwrite / Fclose to save (the host writes the whole file
// at Fclose, through a temporary name: a failed save leaves the old file whole),
// each in the folder the selector was in. Lines are saved with CR LF, as ST editors
// wrote them; a file read may have either. Every failure is GEMDOS's negative code.
// --------------------------------------------------------------------------
const std = @import("std");
const gemdos = @import("kos_gemdos");
const Text = @import("text.zig").Text;

pub const FOLDER = "C:\\";
pub const MASK = "C:\\*.TXT";
pub const MAX_LIST = 32; // the ITEM SELECTOR's list (rom/gem/desktop/filesel_list.zig MAX_FILES)
pub const MAX_SPEC = 64; // the selector's path spec (rom/gem/desktop/filesel_path.zig MAX)
const FA_DIR: u8 = 0x10;

pub const Fail = union(enum) { dos: i32, too_big, too_many_lines };

/// The folder part of a path spec, its last backslash included: `C:\NET\` of `C:\NET\*.TXT`.
pub fn dirOf(spec: []const u8) []const u8 {
    const i = std.mem.lastIndexOfScalar(u8, spec, '\\') orelse return spec[0..0];
    return spec[0 .. i + 1];
}

/// What the ITEM SELECTOR lists for `spec`, as TOS's did: the folder's sub-folders (each with
/// a trailing backslash: the ROM draws it as a folder), then the files the mask matches, each
/// in GEMDOS's order, MAX_LIST in all. A missing folder lists nothing (TOS: an empty list).
pub fn list(spec: []const u8, out: *[MAX_LIST][13]u8, lens: *[MAX_LIST]u8) usize {
    var all: [MAX_SPEC + 4]u8 = undefined;
    const every = std.fmt.bufPrint(&all, "{s}*.*", .{dirOf(spec)}) catch return 0;
    const n = scan(every, FA_DIR, true, 0, out, lens);
    return scan(spec, 0, false, n, out, lens);
}

// The names Fsfirst(spec, attr) gives, folders only or files only, added from `start` on.
fn scan(spec: []const u8, attr: i32, folders: bool, start: usize, out: *[MAX_LIST][13]u8, lens: *[MAX_LIST]u8) usize {
    const dos = gemdos.dos();
    var dta: gemdos.Dta = .{};
    dos.Fsetdta(&dta);
    var n = start;
    var r = dos.Fsfirst(spec, attr);
    while (r == 0 and n < MAX_LIST) : (r = dos.Fsnext()) {
        const len = std.mem.indexOfScalar(u8, &dta.name, 0) orelse dta.name.len;
        const name = dta.name[0..@min(len, 12)];
        if ((dta.attrib & FA_DIR != 0) != folders or name.len == 0 or name[0] == '.') continue;
        @memcpy(out[n][0..name.len], name);
        if (folders) out[n][name.len] = '\\';
        lens[n] = @intCast(name.len + @intFromBool(folders));
        n += 1;
    }
    return n;
}

/// The folder + name into `buf`.
pub fn path(dir: []const u8, name: []const u8, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}{s}", .{ dir, name }) catch buf[0..0];
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

test "a spec's folder" {
    try std.testing.expectEqualStrings("C:\\NET\\", dirOf("C:\\NET\\*.TXT"));
    try std.testing.expectEqualStrings("C:\\", dirOf("C:\\*.TXT"));
    try std.testing.expectEqualStrings("", dirOf("*.TXT"));
}
