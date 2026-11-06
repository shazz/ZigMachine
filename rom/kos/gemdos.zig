// --------------------------------------------------------------------------
// KOS GEMDOS (docs/KOS_GEMDOS.md): TOS's file calls for KESTREL carts, read-only in phase 1, over
// drives A: (a FAT floppy image) and C: (the SD card's /HD). It runs in the cart, over the sector
// imports every host already serves (diskReadBlock, kosDriveRead): no host code, the same on the
// page, the native host and the board. gemdos_cart.zig binds it to those imports, the tests to an
// image. Every call answers as TOS does: >= 0 a result, < 0 a GEMDOS error (gemdos_err.zig).
// Drives and folders are here; files and searches in gemdos_io.zig.
// --------------------------------------------------------------------------
const fat = @import("fat.zig");
const gp = @import("gemdos_path.zig");
const io = @import("gemdos_io.zig");
pub const Drive = @import("gemdos_drive.zig").Drive;
pub const File = @import("gemdos_file.zig").File;
pub const search = @import("gemdos_search.zig");
pub const Dta = search.Dta;
pub const err = @import("gemdos_err.zig");
const E = err.Error;

pub const MAX_FILES = 8;
pub const FIRST_HANDLE = 6; // 0..5 are TOS's standard handles (console, aux, printer)
pub const DRIVE_A: u8 = 0;
pub const DRIVE_C: u8 = 2;
pub const MAX_RUN = @import("gemdos_drive.zig").MAX_RUN;

pub const Dos = struct {
    drives: [26]?*Drive = [_]?*Drive{null} ** 26,
    files: [MAX_FILES]File = [_]File{.{}} ** MAX_FILES,
    current: u8 = DRIVE_A,
    dta: ?*Dta = null, // null: own_dta (TOS's default DTA)
    own_dta: Dta = .{},

    pub const Fopen = io.Fopen;
    pub const Fclose = io.Fclose;
    pub const Fread = io.Fread;
    pub const Fseek = io.Fseek;
    pub const Fsetdta = io.Fsetdta;
    pub const Fgetdta = io.Fgetdta;
    pub const Fsfirst = io.Fsfirst;
    pub const Fsnext = io.Fsnext;

    /// A drive letter's backend (null: none); the drive mounts at its first use.
    pub fn attach(dos: *Dos, letter: u8, d: ?*Drive) void {
        dos.drives[letter] = d;
    }

    /// The drive `letter` names (NO_DRIVE: the current one), mounted.
    pub fn drive(dos: *Dos, letter: u8) E!*Drive {
        const l = if (letter == gp.NO_DRIVE) dos.current else letter;
        if (l >= 26) return error.NoDrive;
        const d = dos.drives[l] orelse return error.NoDrive;
        return if (d.ready()) d else error.NoDrive;
    }

    pub fn Dgetdrv(dos: *Dos) i32 {
        return dos.current;
    }

    /// Makes `d` current (any letter, as TOS); the drives that answer, a bit each (bit 0 A:).
    pub fn Dsetdrv(dos: *Dos, d: i32) i32 {
        if (d >= 0 and d < 26) dos.current = @intCast(d);
        var map: i32 = 0;
        for (0..26) |l| if (dos.drive(@intCast(l))) |_| {
            map |= @as(i32, 1) << @intCast(l);
        } else |_| {};
        return map;
    }

    /// The current folder of drive `drv` (0 the current drive, 1 A:, 3 C:) as `\A\B`, "" at the root.
    pub fn Dgetpath(dos: *Dos, buf: []u8, drv: i32) i32 {
        return err.answer(dos.getpath(buf, drv));
    }

    fn getpath(dos: *Dos, buf: []u8, drv: i32) E!i32 {
        if (drv < 0 or drv > 26) return error.NoDrive;
        const d = try dos.drive(if (drv == 0) gp.NO_DRIVE else @intCast(drv - 1));
        var n: usize = 0;
        for (d.cwd[0..d.depth]) |*f| {
            var name: [12]u8 = undefined;
            const k = gp.show(f, &name);
            if (n + 1 + k >= buf.len) return error.Range;
            buf[n] = '\\';
            @memcpy(buf[n + 1 ..][0..k], name[0..k]);
            n += 1 + k;
        }
        if (n >= buf.len) return error.Range;
        buf[n] = 0;
        return 0;
    }

    /// The current folder of the path's drive (a drive letter in it: that drive's), checked.
    pub fn Dsetpath(dos: *Dos, path: []const u8) i32 {
        return err.answer(dos.setpath(path));
    }

    fn setpath(dos: *Dos, path: []const u8) E!i32 {
        const p = gp.parse(path) catch return error.PathNotFound;
        const d = try dos.drive(p.drive);
        var buf: [gp.MAX_DEPTH * 2 + 1]gp.Fcb = undefined;
        const names = d.absolute(&p, &buf) orelse return error.PathNotFound;
        if (names.len > gp.MAX_DEPTH) return error.PathNotFound;
        _ = try walk(d, names);
        @memcpy(d.cwd[0..names.len], names);
        d.depth = @intCast(names.len);
        return 0;
    }

    /// A file's or folder's attributes (a drive's root: FA_DIR). Setting them: write-protected.
    pub fn Fattrib(dos: *Dos, path: []const u8, wflag: i32, attr: i32) i32 {
        _ = attr;
        var e: fat.Entry = undefined;
        _ = dos.entryOf(path, &e) catch |x| return err.code(x);
        if (wflag != 0) return err.EWRPRO;
        return e.attr;
    }

    /// The entry `path` names (a drive's root: a folder entry of its own); its drive letter.
    pub fn entryOf(dos: *Dos, path: []const u8, out: *fat.Entry) E!u8 {
        var p = gp.parse(path) catch return error.FileNotFound;
        const letter = if (p.drive == gp.NO_DRIVE) dos.current else p.drive;
        const d = try dos.drive(letter);
        var buf: [gp.MAX_DEPTH * 2 + 1]gp.Fcb = undefined;
        const names = d.absolute(&p, &buf) orelse return error.PathNotFound;
        if (names.len == 0) {
            out.* = .{ .attr = search.FA_DIR, .cluster = d.top.cluster };
            return letter;
        }
        const last = names[names.len - 1];
        if (gp.hasWild(&last)) return error.FileNotFound;
        const folder = try walk(d, names[0 .. names.len - 1]);
        out.* = (d.lookup(folder, &last) catch return error.ReadFault) orelse return error.FileNotFound;
        return letter;
    }

    /// The folder `p` names (all its names: Fsfirst takes the pattern off first).
    pub fn folderOf(dos: *Dos, d: *Drive, p: *const gp.Path) E!fat.Dir {
        _ = dos;
        var buf: [gp.MAX_DEPTH * 2 + 1]gp.Fcb = undefined;
        const names = d.absolute(p, &buf) orelse return error.PathNotFound;
        return walk(d, names);
    }

    fn walk(d: *Drive, names: []const gp.Fcb) E!fat.Dir {
        return (d.walk(d.top, names) catch return error.ReadFault) orelse error.PathNotFound;
    }
};
