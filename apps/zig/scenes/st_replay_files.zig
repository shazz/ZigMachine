// --------------------------------------------------------------------------
// ST Replay's samples off the GEMDOS drives (Matt on the board, 10 Nov: "drive C
// is disabled in ST Replay"). A: stays on the floppy path (st_replay.zig walks
// the FAT through zg.disk, as it always has); every other drive GEMDOS answers
// (Dsetdrv's map) is listed with Fsfirst / Fsnext (the folder's sub-folders, then
// the .RAW files) and loaded with Fopen / Fread / Fclose (docs/KOS_GEMDOS.md).
// --------------------------------------------------------------------------
const std = @import("std");
const gemdos = @import("kos_gemdos");

pub const MAX_SPEC = 64; // the selector's path spec (rom/gem/desktop/filesel_path.zig MAX)
const FA_DIR: u8 = 0x10;

/// The drives that answer (GEMDOS Dsetdrv's map, bit 0 = A:), for the DRIVE: buttons.
pub fn drives() u32 {
    const dos = gemdos.dos();
    return @bitCast(dos.Dsetdrv(dos.Dgetdrv()));
}

/// Is the spec on A: (a bare mask, as ST Replay opens with, is A:)?
pub fn onFloppy(spec: []const u8) bool {
    return spec.len < 2 or spec[1] != ':' or (spec[0] | 0x20) == 'a';
}

/// The spec's folder (up to and with its last backslash), "" for a bare mask.
pub fn dirOf(spec: []const u8) []const u8 {
    const i = std.mem.lastIndexOfScalar(u8, spec, '\\') orelse return spec[0..0];
    return spec[0 .. i + 1];
}

/// The names for `spec` through `add`: sub-folders (a trailing backslash: drawn as folders),
/// then the files the mask matches.
pub fn list(spec: []const u8, ctx: anytype, comptime add: fn (@TypeOf(ctx), []const u8) void) void {
    var all: [MAX_SPEC + 4]u8 = undefined;
    const every = std.fmt.bufPrint(&all, "{s}*.*", .{dirOf(spec)}) catch return;
    scan(every, FA_DIR, true, ctx, add);
    scan(spec, 0, false, ctx, add);
}

fn scan(spec: []const u8, attr: i32, folders: bool, ctx: anytype, comptime add: fn (@TypeOf(ctx), []const u8) void) void {
    const dos = gemdos.dos();
    var dta: gemdos.Dta = .{};
    dos.Fsetdta(&dta);
    var r = dos.Fsfirst(spec, attr);
    while (r == 0) : (r = dos.Fsnext()) {
        const len = std.mem.indexOfScalar(u8, &dta.name, 0) orelse dta.name.len;
        var name: [13]u8 = undefined;
        const n = @min(len, 12);
        if ((dta.attrib & FA_DIR != 0) != folders or n == 0 or dta.name[0] == '.') continue;
        @memcpy(name[0..n], dta.name[0..n]);
        if (folders) name[n] = '\\';
        add(ctx, name[0 .. n + @intFromBool(folders)]);
    }
}

/// The file at `dir` + `name` into `out`: the bytes read, or GEMDOS's negative code.
pub fn load(dir: []const u8, name: []const u8, out: []u8) i32 {
    var buf: [MAX_SPEC + 16]u8 = undefined;
    const p = std.fmt.bufPrint(&buf, "{s}{s}", .{ dir, name }) catch return -33; // EFILNF
    const dos = gemdos.dos();
    const h = dos.Fopen(p, 0);
    if (h < 0) return h;
    defer _ = dos.Fclose(h);
    var got: usize = 0;
    while (got < out.len) {
        const r = dos.Fread(h, @intCast(out.len - got), out.ptr + got);
        if (r < 0) return r;
        if (r == 0) break;
        got += @intCast(r);
    }
    return @intCast(got);
}
