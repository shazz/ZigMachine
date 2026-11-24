// --------------------------------------------------------------------------
// SID-WIZARD Z's files, as the host of the library's pure file dialog (filer.zig):
//   the floppy   read-only, off the cart's own disk (zg.disk: the .zmd FAT): the example song
//   C:\          read and write, KOS GEMDOS (docs/os/KOS_GEMDOS.md): Fsfirst/Fsnext, Fopen/Fread,
//                Fcreate/Fwrite/Fclose (the host writes the whole file at Fclose, through a temporary
//                name: a failed save leaves the old file whole)
// A listing is C:'s files of the dialog's extension, then the floppy's; a load tries C: first.
// A save always goes to C:. GEMDOS names are 8.3, so a longer name is refused, not truncated.
// Every failure is a value (Fail), never a silent default.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const gemdos = @import("kos_gemdos");
const filer = @import("filer.zig");
const names = @import("names.zig");

pub const Fail = error{ NoFile, TooBig, BadName, Dos };

const FA_DIR: u8 = 0x10;

/// The dialog's listing at `cwd`, names without extension, in `out`. The floppy's root lists its files of `ext` and the
/// folder "C" (the other drive, as the C cart's does); a C: folder lists ".." (up), its folders, then its files of `ext`.
pub fn listing(cwd: *const names.Cwd, ext: []const u8, out: *[filer.max_files]filer.Entry) usize {
    if (!cwd.on_c) return names.addFolder(out, listFloppy(ext, out, 0), "C");
    var n = names.addFolder(out, 0, "..");
    n = listCFolders(cwd, out, n);
    return listCFiles(cwd, ext, out, n);
}

fn scanC(cwd: *const names.Cwd, attr: i32, dirs: bool, ext: []const u8, out: *[filer.max_files]filer.Entry, start: usize) usize {
    var base: [64]u8 = undefined;
    const spec = cwd.path(&base, "*.*") orelse return start;
    const dos = gemdos.dos();
    var dta: gemdos.Dta = .{};
    dos.Fsetdta(&dta);
    var n = start;
    var r = dos.Fsfirst(spec, attr);
    while (r == 0 and n < out.len) : (r = dos.Fsnext()) {
        const is_dir = dta.attrib & FA_DIR != 0;
        const len = std.mem.indexOfScalar(u8, &dta.name, 0) orelse dta.name.len;
        const name = dta.name[0..len];
        if (is_dir != dirs or name.len == 0 or name[0] == '.') continue;
        n = if (dirs) names.addFolder(out, n, name) else names.addEntry(out, n, name, ext);
    }
    return n;
}

fn listCFolders(cwd: *const names.Cwd, out: *[filer.max_files]filer.Entry, start: usize) usize {
    return scanC(cwd, FA_DIR, true, "", out, start);
}

fn listCFiles(cwd: *const names.Cwd, ext: []const u8, out: *[filer.max_files]filer.Entry, start: usize) usize {
    return scanC(cwd, 0, false, ext, out, start);
}

fn listFloppy(ext: []const u8, out: *[filer.max_files]filer.Entry, start: usize) usize {
    const lay = zg.disk.mount() orelse return start;
    var n = start;
    var i: u16 = 0;
    while (i < lay.count) : (i += 1) {
        const ent = zg.disk.entryAt(lay, i) orelse continue;
        const len = std.mem.indexOfScalar(u8, &ent.name, 0) orelse ent.name.len;
        n = names.addEntry(out, n, ent.name[0..len], ext);
    }
    return n;
}

/// `name` into `buf` from the dialog's place: C:'s folder, or the floppy's root. The slice is the file's bytes.
pub fn read(cwd: *const names.Cwd, name: []const u8, buf: []u8) Fail![]u8 {
    if (!names.valid(name)) return Fail.BadName;
    if (!cwd.on_c) return readFloppy(name, buf);
    var path: [64]u8 = undefined;
    const p = cwd.path(&path, name) orelse return Fail.BadName;
    return buf[0..try readC(p, buf)];
}

/// The example song, off the floppy's root, whatever the dialog's place.
pub fn readStart(name: []const u8, buf: []u8) Fail![]u8 {
    if (!names.valid(name)) return Fail.BadName;
    return readFloppy(name, buf);
}

fn readC(path: []const u8, buf: []u8) Fail!usize {
    const dos = gemdos.dos();
    const h = dos.Fopen(path, 0);
    if (h < 0) return Fail.NoFile;
    defer _ = dos.Fclose(h);
    var got: usize = 0;
    while (got < buf.len) {
        const r = dos.Fread(h, @intCast(buf.len - got), buf.ptr + got);
        if (r < 0) return Fail.Dos;
        if (r == 0) return got;
        got += @intCast(r);
    }
    return Fail.TooBig; // the buffer filled: the file may be longer
}

fn readFloppy(name: []const u8, buf: []u8) Fail![]u8 {
    const lay = zg.disk.mount() orelse return Fail.NoFile;
    const e = zg.disk.find(lay, name) orelse return Fail.NoFile;
    if (e.len > buf.len) return Fail.TooBig;
    const got = zg.disk.read(e, buf);
    if (got != e.len) return Fail.Dos; // the drive ran out before the file did
    return buf[0..got];
}

/// `data` as `name` in the dialog's C: folder (the floppy is read-only: its root saves to C:\). The host writes it at Fclose.
pub fn write(cwd: *const names.Cwd, name: []const u8, data: []const u8) Fail!void {
    if (!names.valid(name)) return Fail.BadName;
    var path: [64]u8 = undefined;
    const p = (if (cwd.on_c) cwd.path(&path, name) else (names.Cwd{ .on_c = true, .len = 0 }).path(&path, name)) orelse return Fail.BadName;
    const dos = gemdos.dos();
    const h = dos.Fcreate(p, 0);
    if (h < 0) return Fail.Dos;
    const w = dos.Fwrite(h, @intCast(data.len), data.ptr);
    const c = dos.Fclose(h); // the save itself
    if (w != data.len or c < 0) return Fail.Dos;
}
