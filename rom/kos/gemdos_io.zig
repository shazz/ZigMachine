// --------------------------------------------------------------------------
// GEMDOS's file and search calls (docs/KOS_GEMDOS.md §2), methods of gemdos.Dos: Fopen, Fclose,
// Fread, Fseek, Fsetdta, Fgetdta, Fsfirst, Fsnext. Handles are TOS's: 6 and up.
// --------------------------------------------------------------------------
const gemdos = @import("gemdos.zig");
const gp = @import("gemdos_path.zig");
const search = @import("gemdos_search.zig");
const err = @import("gemdos_err.zig");
const fat = @import("fat.zig");
const Dos = gemdos.Dos;
const File = gemdos.File;

/// Mode 0 (read); a write mode is refused (phase 1: every drive is read-only).
pub fn Fopen(dos: *Dos, path: []const u8, mode: i32) i32 {
    if (mode != 0) return if (mode == 1 or mode == 2) err.EACCDN else err.EINVFN;
    var e: fat.Entry = undefined;
    const letter = dos.entryOf(path, &e) catch |x| return err.code(x);
    if (e.isDir()) return err.EFILNF;
    for (&dos.files, 0..) |*f, i| if (!f.used) {
        f.open(letter, e);
        return gemdos.FIRST_HANDLE + @as(i32, @intCast(i));
    };
    return err.ENHNDL;
}

pub fn Fclose(dos: *Dos, h: i32) i32 {
    const f = file(dos, h) orelse return err.EIHNDL;
    f.used = false;
    return 0;
}

/// Up to `count` bytes into `buf`; the count read (0 at the end).
pub fn Fread(dos: *Dos, h: i32, count: i32, buf: [*]u8) i32 {
    const f = file(dos, h) orelse return err.EIHNDL;
    if (count < 0) return err.ERANGE;
    const d = dos.drives[f.drive] orelse return err.EIHNDL;
    const got = f.read(d, buf[0..@intCast(count)]) catch return err.EREADF;
    return @intCast(got);
}

/// Mode 0 from the start, 1 from the position, 2 from the end; the new position.
pub fn Fseek(dos: *Dos, offset: i32, h: i32, mode: i32) i32 {
    const f = file(dos, h) orelse return err.EIHNDL;
    const base: i64 = switch (mode) {
        0 => 0,
        1 => f.pos,
        2 => f.entry.size,
        else => return err.EINVFN,
    };
    const to = base + offset;
    if (to < 0 or to > f.entry.size) return err.ERANGE;
    f.pos = @intCast(to);
    return @intCast(to);
}

pub fn Fsetdta(dos: *Dos, t: *search.Dta) void {
    dos.dta = t;
}

pub fn Fgetdta(dos: *Dos) *search.Dta {
    return dos.dta orelse &dos.own_dta;
}

/// The first entry `spec` (a path ending in a name or pattern) matches into the DTA: 0, or
/// EFILNF / EPTHNF / EDRIVE.
pub fn Fsfirst(dos: *Dos, spec: []const u8, attr: i32) i32 {
    var p = gp.parse(spec) catch return err.EFILNF;
    if (p.n == 0) return err.EFILNF; // no name: TOS finds nothing
    const pattern = p.names[p.n - 1];
    p.n -= 1;
    const letter = if (p.drive == gp.NO_DRIVE) dos.current else p.drive;
    const d = dos.drive(letter) catch |x| return err.code(x);
    const folder = dos.folderOf(d, &p) catch |x| return err.code(x);
    const t = Fgetdta(dos);
    search.start(t, letter, folder, @truncate(@as(u32, @bitCast(attr))), pattern);
    const r = Fsnext(dos);
    return if (r == err.ENMFIL) err.EFILNF else r;
}

/// The next match of the DTA's search: 0, or ENMFIL.
pub fn Fsnext(dos: *Dos) i32 {
    const t = Fgetdta(dos);
    const d = dos.drive(search.driveOf(t)) catch |x| return err.code(x);
    const found = search.next(t, &d.vol) catch return err.EREADF;
    return if (found) 0 else err.ENMFIL;
}

fn file(dos: *Dos, h: i32) ?*File {
    if (h < gemdos.FIRST_HANDLE or h >= gemdos.FIRST_HANDLE + gemdos.MAX_FILES) return null;
    const f = &dos.files[@intCast(h - gemdos.FIRST_HANDLE)];
    return if (f.used) f else null;
}
